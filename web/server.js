#!/usr/bin/env node
// GamadCode — API server + WebSocket + Magic-link auth + Workspace Docker
'use strict';

const express    = require('express');
const session    = require('express-session');
const passport   = require('passport');
const GitHubStrategy = require('passport-github2').Strategy;
const { WebSocketServer } = require('ws');
const { execFile, spawn } = require('child_process');
const { promisify } = require('util');
const si         = require('systeminformation');
const fs         = require('fs');
const path       = require('path');
const http       = require('http');
const crypto     = require('crypto');

require('dotenv').config({ path: path.join(__dirname, '../config/secrets.env') });
require('dotenv').config({ path: path.join(__dirname, '../config/local.env'), override: false });

const execFileAsync = promisify(execFile);

// ── Config ───────────────────────────────────────────────────────────────────
const PORT               = process.env.GAMADCODE_UI_PORT   || 3000;
const DEVLAB_ROOT        = path.join(__dirname, '..');
const SESSION_SECRET     = process.env.SESSION_SECRET      || 'changeme-in-secrets.env';
const GITHUB_CLIENT_ID   = process.env.GITHUB_CLIENT_ID   || '';
const GITHUB_CLIENT_SECRET = process.env.GITHUB_CLIENT_SECRET || '';
const GITHUB_CALLBACK_URL  = process.env.GITHUB_CALLBACK_URL  || `http://localhost:${PORT}/auth/github/callback`;
const ADMIN_GITHUB_LOGIN   = process.env.ADMIN_GITHUB_LOGIN   || '';

// DB + Auth + Workspace (lazy — ne crash pas si pg non configuré au boot)
let db, authLib, workspaceLib;
const loadLibs = () => {
    if (db) return;
    try {
        db           = require('./lib/db');
        authLib      = require('./lib/auth');
        workspaceLib = require('./lib/workspace');
    } catch (e) {
        console.warn('[warn] libs non chargées (pg probablement absent) :', e.message);
    }
};

// ── Express ──────────────────────────────────────────────────────────────────
const app    = express();
const server = http.createServer(app);

app.set('trust proxy', 1);

app.use(express.json());
app.use(express.urlencoded({ extended: false }));
app.use(session({
    secret:            SESSION_SECRET,
    resave:            false,
    saveUninitialized: false,
    cookie:            { secure: 'auto', maxAge: 30 * 24 * 60 * 60 * 1000 }
}));
app.use(passport.initialize());
app.use(passport.session());
app.use(express.static(path.join(__dirname, 'public')));

// ── GitHub OAuth (admin) ─────────────────────────────────────────────────────
if (GITHUB_CLIENT_ID && GITHUB_CLIENT_SECRET) {
    passport.use(new GitHubStrategy({
        clientID:    GITHUB_CLIENT_ID,
        clientSecret: GITHUB_CLIENT_SECRET,
        callbackURL:  GITHUB_CALLBACK_URL
    }, (accessToken, refreshToken, profile, done) => {
        return done(null, {
            id:      profile.id,
            login:   profile.username,
            name:    profile.displayName || profile.username,
            avatar:  profile.photos?.[0]?.value || '',
            token:   accessToken,
            isAdmin: !ADMIN_GITHUB_LOGIN || profile.username === ADMIN_GITHUB_LOGIN
        });
    }));
}
passport.serializeUser((u, done) => done(null, u));
passport.deserializeUser((u, done) => done(null, u));

// ── Middlewares auth ─────────────────────────────────────────────────────────
const requireAdmin = (req, res, next) => {
    if (!GITHUB_CLIENT_ID) return next();
    if (req.isAuthenticated() && req.user?.isAdmin) return next();
    if (req.path.startsWith('/api/')) return res.status(403).json({ error: 'Accès admin requis' });
    res.redirect('/');
};

// Utilisateur email (SaaS) OU admin GitHub
const requireUser = (req, res, next) => {
    if (req.session.userId) return next();
    if (req.isAuthenticated()) return next(); // admin GitHub
    if (req.path.startsWith('/api/')) return res.status(401).json({ error: 'Non authentifié' });
    res.redirect('/login');
};

// ── /api/me — unifié admin + user email ──────────────────────────────────────
app.get('/api/me', async (req, res) => {
    // Admin GitHub
    if (req.isAuthenticated() && !req.session.userId) {
        return res.json({ authenticated: true, type: 'admin', oauthConfigured: !!GITHUB_CLIENT_ID, ...req.user });
    }
    // Utilisateur email
    if (req.session.userId) {
        loadLibs();
        if (!db) return res.json({ authenticated: true, type: 'user', email: req.session.userEmail });
        try {
            const r = await db.query('SELECT id, email, name, is_admin, created_at FROM users WHERE id = $1', [req.session.userId]);
            if (!r.rows.length) { req.session.destroy(); return res.json({ authenticated: false }); }
            const u = r.rows[0];
            return res.json({ authenticated: true, type: 'user', userId: u.id, email: u.email, name: u.name, isAdmin: u.is_admin, createdAt: u.created_at });
        } catch (e) {
            return res.json({ authenticated: true, type: 'user', email: req.session.userEmail });
        }
    }
    // Non connecté (sans OAuth configuré → accès libre pour admin DevLab)
    if (!GITHUB_CLIENT_ID) {
        return res.json({ authenticated: true, type: 'admin', name: 'root', login: 'root', isAdmin: true, oauthConfigured: false });
    }
    res.json({ authenticated: false, oauthConfigured: !!GITHUB_CLIENT_ID });
});

// ── Captcha (math côté serveur, stocké en session) ────────────────────────────
// Chaque formulaire (login / register) a son propre slot dans req.session.captchas
app.get('/api/auth/captcha', (req, res) => {
    loadLibs();
    if (!authLib) return res.status(503).json({ error: 'Service non disponible' });

    const form    = req.query.form === 'register' ? 'register' : 'login';
    const captcha = authLib.generateCaptcha();
    const id      = crypto.randomBytes(8).toString('hex');

    if (!req.session.captchas) req.session.captchas = {};
    req.session.captchas[id] = { answer: captcha.answer, form, expires: Date.now() + 5 * 60 * 1000 };

    res.json({ id, question: captcha.question });
});

const verifyCaptcha = (req, id, answer) => {
    const store = req.session.captchas || {};
    const entry = store[id];
    if (!entry) return false;
    if (Date.now() > entry.expires) { delete store[id]; return false; }
    const ok = String(entry.answer) === String(answer).trim();
    delete store[id]; // usage unique
    return ok;
};

// ── Inscription ───────────────────────────────────────────────────────────────
app.post('/api/auth/register', async (req, res) => {
    loadLibs();
    if (!authLib || !db) return res.status(503).json({ error: 'Service non disponible (base de données non configurée)' });

    const { email, password, captchaId, captcha } = req.body;

    if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))
        return res.status(400).json({ error: 'Email invalide' });
    if (!password || password.length < 8)
        return res.status(400).json({ error: 'Mot de passe trop court (8 caractères minimum)' });
    if (!verifyCaptcha(req, captchaId, captcha))
        return res.status(400).json({ error: 'Réponse au captcha incorrecte' });

    try {
        const user = await authLib.register(email, password);
        req.session.userId    = user.id;
        req.session.userEmail = user.email;
        res.json({ ok: true });
    } catch (e) {
        res.status(400).json({ error: e.message });
    }
});

// ── Connexion ─────────────────────────────────────────────────────────────────
app.post('/api/auth/login', async (req, res) => {
    loadLibs();
    if (!authLib || !db) return res.status(503).json({ error: 'Service non disponible (base de données non configurée)' });

    const { email, password, captchaId, captcha } = req.body;

    if (!verifyCaptcha(req, captchaId, captcha))
        return res.status(400).json({ error: 'Réponse au captcha incorrecte' });

    try {
        const user = await authLib.login(email, password);
        req.session.userId    = user.id;
        req.session.userEmail = user.email;
        res.json({ ok: true });
    } catch (e) {
        res.status(401).json({ error: e.message });
    }
});

app.post('/auth/logout', (req, res) => {
    req.session.destroy(() => res.json({ ok: true }));
});

// ── GitHub OAuth (admin) ─────────────────────────────────────────────────────
app.get('/auth/github', passport.authenticate('github', { scope: ['user:email'] }));
app.get('/auth/github/callback',
    passport.authenticate('github', { failureRedirect: '/?error=auth' }),
    (req, res) => res.redirect('/dashboard')
);
app.get('/auth/logout', (req, res) => {
    req.logout(() => { req.session.destroy(); res.redirect('/'); });
});

// ── Workspace routes ─────────────────────────────────────────────────────────
app.get('/api/workspace', requireUser, async (req, res) => {
    loadLibs();
    const userId = req.session.userId;
    if (!userId || !workspaceLib) return res.json({ status: 'none' });

    try {
        const ws = await workspaceLib.getWorkspaceStatus(userId);

        // Construire l'URL d'accès au workspace
        let url = null;
        if (ws.status === 'running' && ws.port) {
            const wsHost = process.env.GAMADCODE_DOMAIN || req.hostname;
            url = `http://${wsHost}:${ws.port}`;
        }

        res.json({ ...ws, url });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

app.post('/api/workspace/start', requireUser, async (req, res) => {
    loadLibs();
    const userId = req.session.userId;
    if (!userId || !workspaceLib) return res.status(503).json({ error: 'Service non disponible' });

    try {
        const ws = await workspaceLib.createWorkspace(userId);
        const wsHost = process.env.GAMADCODE_DOMAIN || req.hostname;
        const url    = `http://${wsHost}:${ws.port}`;
        res.json({ ...ws, url });
    } catch (e) {
        console.error('[workspace] start error:', e.message);
        res.status(500).json({ error: e.message });
    }
});

app.post('/api/workspace/stop', requireUser, async (req, res) => {
    loadLibs();
    const userId = req.session.userId;
    if (!userId || !workspaceLib) return res.status(503).json({ error: 'Service non disponible' });

    try {
        await workspaceLib.stopWorkspace(userId);
        res.json({ ok: true });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// ── API Keys ──────────────────────────────────────────────────────────────────
app.get('/api/keys', requireUser, async (req, res) => {
    loadLibs();
    const userId = req.session.userId;
    if (!userId || !db) return res.json([]);

    try {
        const r = await db.query('SELECT provider, created_at FROM api_keys WHERE user_id = $1', [userId]);
        res.json(r.rows);
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

app.post('/api/keys', requireUser, async (req, res) => {
    loadLibs();
    const userId = req.session.userId;
    if (!userId || !db) return res.status(503).json({ error: 'Service non disponible' });

    const { provider, key } = req.body;
    const ALLOWED_PROVIDERS = ['anthropic', 'openai', 'github'];
    if (!ALLOWED_PROVIDERS.includes(provider)) return res.status(400).json({ error: 'Provider non supporté' });
    if (!key || key.length < 8) return res.status(400).json({ error: 'Clé invalide' });

    try {
        await db.query(
            `INSERT INTO api_keys (user_id, provider, key_value)
             VALUES ($1, $2, $3)
             ON CONFLICT (user_id, provider) DO UPDATE SET key_value = EXCLUDED.key_value, created_at = NOW()`,
            [userId, provider, key.trim()]
        );
        res.json({ ok: true });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

app.delete('/api/keys/:provider', requireUser, async (req, res) => {
    loadLibs();
    const userId   = req.session.userId;
    const provider = req.params.provider;
    if (!userId || !db) return res.status(503).json({ error: 'Service non disponible' });

    try {
        await db.query('DELETE FROM api_keys WHERE user_id = $1 AND provider = $2', [userId, provider]);
        res.json({ ok: true });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// ── Setup wizard config writer ────────────────────────────────────────────────
app.post('/api/setup/write-config', (req, res) => {
    const { domain, uiDomain, project, uiPort, vscPort, ghId, ghSecret, ghAdmin, ghCb,
            gitName, gitEmail, githubUser, claudeKey,
            smtpHost, smtpPort, smtpUser, smtpPass, smtpFrom,
            pgHost, pgPort, pgDb, pgUser, pgPassword } = req.body;

    const localEnv   = path.join(DEVLAB_ROOT, 'config/local.env');
    const secretsEnv = path.join(DEVLAB_ROOT, 'config/secrets.env');

    const sessionSecret = (process.env.SESSION_SECRET && process.env.SESSION_SECRET !== 'changeme-in-secrets.env')
        ? process.env.SESSION_SECRET
        : crypto.randomBytes(32).toString('hex');

    const localLines = [
        '# Generated by GamadCode setup wizard — ' + new Date().toISOString(),
        `GAMADCODE_DOMAIN="${domain   || ''}"`,
        `GAMADCODE_UI_DOMAIN="${uiDomain || ''}"`,
        `GAMADCODE_PROJECT_NAME="${project || 'GamadCode'}"`,
        `GAMADCODE_UI_PORT="${uiPort  || 3000}"`,
        `CODE_SERVER_PORT="${vscPort  || 8080}"`,
        ghAdmin    ? `ADMIN_GITHUB_LOGIN="${ghAdmin}"` : '',
        ghCb       ? `GITHUB_CALLBACK_URL="${ghCb}"` : '',
        gitName    ? `GIT_USER_NAME="${gitName}"` : '',
        gitEmail   ? `GIT_USER_EMAIL="${gitEmail}"` : '',
        githubUser ? `GITHUB_USERNAME="${githubUser}"` : '',
        smtpHost   ? `SMTP_HOST="${smtpHost}"` : '',
        smtpPort   ? `SMTP_PORT="${smtpPort}"` : '',
        smtpFrom   ? `SMTP_FROM="${smtpFrom}"` : '',
        pgHost     ? `POSTGRES_HOST="${pgHost}"` : '',
        pgPort     ? `POSTGRES_PORT="${pgPort}"` : '',
        pgDb       ? `POSTGRES_DB="${pgDb}"` : '',
        pgUser     ? `POSTGRES_USER="${pgUser}"` : '',
    ].filter(Boolean).join('\n') + '\n';

    const existingSecrets = fs.existsSync(secretsEnv) ? fs.readFileSync(secretsEnv, 'utf8') : '';
    const hasSecret = existingSecrets.includes('SESSION_SECRET=');

    const secretLines = [
        '# GamadCode secrets — chmod 600 — DO NOT COMMIT',
        !hasSecret      ? `SESSION_SECRET="${sessionSecret}"` : '',
        ghId            ? `GITHUB_CLIENT_ID="${ghId}"` : '',
        ghSecret        ? `GITHUB_CLIENT_SECRET="${ghSecret}"` : '',
        claudeKey       ? `ANTHROPIC_API_KEY="${claudeKey}"` : '',
        smtpUser        ? `SMTP_USER="${smtpUser}"` : '',
        smtpPass        ? `SMTP_PASS="${smtpPass}"` : '',
        pgPassword      ? `POSTGRES_PASSWORD="${pgPassword}"` : '',
    ].filter(Boolean).join('\n') + '\n';

    try {
        fs.writeFileSync(localEnv, localLines, { mode: 0o644 });
        if (ghSecret || claudeKey || smtpPass || pgPassword || !hasSecret) {
            fs.writeFileSync(secretsEnv, secretLines, { mode: 0o600 });
        }
        res.json({ ok: true });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// ── Setup status ──────────────────────────────────────────────────────────────
const isSetupDone = () => {
    const f = path.join(DEVLAB_ROOT, 'state/registry.json');
    if (!fs.existsSync(f)) return false;
    try { return JSON.parse(fs.readFileSync(f, 'utf8'))['bootstrap.base-packages']?.status === 'installed'; }
    catch { return false; }
};

app.get('/api/setup/status', (req, res) => res.json({ done: isSetupDone() }));

// ── Config URLs ───────────────────────────────────────────────────────────────
app.get('/api/config/urls', (req, res) => {
    const vscodeDomain = process.env.GAMADCODE_DOMAIN    || '';
    const uiDomain     = process.env.GAMADCODE_UI_DOMAIN || '';
    const vscPort      = process.env.CODE_SERVER_PORT    || '8080';
    const uiPort       = process.env.GAMADCODE_UI_PORT   || '3000';
    const proto        = req.protocol;
    const reqHost      = req.hostname;
    const isLocal      = /^(localhost|127\.|::1)/.test(reqHost);

    const vscodeUrl = vscodeDomain ? `${proto}://${vscodeDomain}`
                    : !isLocal     ? `http://${reqHost}:${vscPort}`
                    : `http://localhost:${vscPort}`;

    const uiUrl     = uiDomain  ? `${proto}://${uiDomain}`
                    : !isLocal  ? `http://${reqHost}:${uiPort}`
                    : `http://localhost:${uiPort}`;

    res.json({ vscode: vscodeUrl, ui: uiUrl, vscodeDomain, uiDomain, vscPort, uiPort });
});

// ── System info (admin) ───────────────────────────────────────────────────────
app.get('/api/system', requireUser, async (req, res) => {
    try {
        const [cpu, mem, disk, os] = await Promise.all([
            si.currentLoad(), si.mem(), si.fsSize(), si.osInfo()
        ]);
        res.json({
            cpu:  { load: Math.round(cpu.currentLoad) },
            mem:  { total: mem.total, used: mem.active, pct: Math.round(mem.active / mem.total * 100) },
            disk: disk[0] ? { total: disk[0].size, used: disk[0].used, pct: Math.round(disk[0].use) } : {},
            os:   os.distro + ' ' + os.release
        });
    } catch (e) { res.status(500).json({ error: e.message }); }
});

// ── Services status (admin) ───────────────────────────────────────────────────
const SERVICES = ['nginx', 'postgresql', 'redis-server', 'docker', 'ssh', 'fail2ban'];
const checkService = async (name) => {
    try { await execFileAsync('systemctl', ['is-active', '--quiet', name], { timeout: 3000 }); return 'active'; }
    catch { return 'inactive'; }
};

app.get('/api/services', requireUser, async (req, res) => {
    const results = await Promise.all(SERVICES.map(async s => ({ name: s, status: await checkService(s) })));
    res.json(results);
});

// ── Modules registry (admin) ──────────────────────────────────────────────────
app.get('/api/modules', requireUser, (req, res) => {
    const f = path.join(DEVLAB_ROOT, 'state/registry.json');
    try { res.json(fs.existsSync(f) ? JSON.parse(fs.readFileSync(f, 'utf8')) : {}); }
    catch { res.json({}); }
});

app.get('/api/modules/available', requireUser, (req, res) => {
    const f = path.join(DEVLAB_ROOT, 'config/modules.conf');
    if (!fs.existsSync(f)) return res.json([]);
    const result = fs.readFileSync(f, 'utf8').split('\n')
        .map(l => l.match(/^MODULE_([A-Z_]+)=(true|false)/))
        .filter(Boolean)
        .map(m => ({ key: m[1], enabled: m[2] === 'true' }));
    res.json(result);
});

// ── Command runner (admin only) ───────────────────────────────────────────────
app.post('/api/run', requireUser, requireAdmin, (req, res) => {
    const { command, args = [] } = req.body;
    if (!['devlab', 'systemctl'].includes(command)) {
        return res.status(400).json({ error: 'Commande non autorisée' });
    }
    const bin  = command === 'devlab' ? path.join(DEVLAB_ROOT, 'bin/devlab') : 'systemctl';
    const proc = spawn(bin, args, { stdio: ['ignore', 'pipe', 'pipe'] });
    let out = '';
    proc.stdout.on('data', d => { out += d; });
    proc.stderr.on('data', d => { out += d; });
    proc.on('close', code => res.json({ code, output: out }));
    proc.on('error', err => res.status(500).json({ error: err.message }));
});

// ── WebSocket — live logs ─────────────────────────────────────────────────────
const wss = new WebSocketServer({ server, path: '/ws/logs' });
wss.on('connection', (ws) => {
    const logDir = path.join(DEVLAB_ROOT, 'logs');
    if (!fs.existsSync(logDir)) { ws.close(); return; }
    const logFile = fs.readdirSync(logDir).filter(f => f.endsWith('.log')).sort().pop();
    if (!logFile) { ws.send(JSON.stringify({ line: 'Aucun log disponible.' })); ws.close(); return; }

    const fullPath = path.join(logDir, logFile);
    ws.send(JSON.stringify({ file: logFile }));
    const tail = spawn('tail', ['-n', '100', '-f', fullPath]);
    tail.stdout.on('data', d => { if (ws.readyState === 1) ws.send(JSON.stringify({ line: d.toString() })); });
    ws.on('close', () => tail.kill());
    ws.on('error', () => tail.kill());
});

// ── Pages ─────────────────────────────────────────────────────────────────────
app.get('/',          (req, res) => res.sendFile(path.join(__dirname, 'public/landing.html')));
app.get('/login',     (req, res) => res.sendFile(path.join(__dirname, 'public/login.html')));
app.get('/my',        requireUser, (req, res) => res.sendFile(path.join(__dirname, 'public/user-dashboard.html')));
app.get('/dashboard', requireUser, (req, res) => res.sendFile(path.join(__dirname, 'public/dashboard.html')));
app.get('/modules',   requireUser, (req, res) => res.sendFile(path.join(__dirname, 'public/modules.html')));
app.get('/logs',      requireUser, (req, res) => res.sendFile(path.join(__dirname, 'public/logs.html')));
app.get('/setup',     (req, res)  => res.sendFile(path.join(__dirname, 'public/setup.html')));

// ── Start ─────────────────────────────────────────────────────────────────────
server.listen(PORT, '0.0.0.0', () => {
    console.log(`GamadCode → http://0.0.0.0:${PORT}`);
});
