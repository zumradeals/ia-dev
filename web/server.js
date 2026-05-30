#!/usr/bin/env node
// GamadCode — API server + WebSocket + GitHub OAuth

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
require('dotenv').config({ path: path.join(__dirname, '../config/secrets.env') });
require('dotenv').config({ path: path.join(__dirname, '../config/local.env'), override: false });

const execFileAsync = promisify(execFile);

// ── Config ──────────────────────────────────────────────────────────────────
const PORT         = process.env.GAMADCODE_UI_PORT || 3000;
const DEVLAB_ROOT  = path.join(__dirname, '..');
const SESSION_SECRET = process.env.SESSION_SECRET || 'changeme-in-secrets.env';
const GITHUB_CLIENT_ID     = process.env.GITHUB_CLIENT_ID     || '';
const GITHUB_CLIENT_SECRET = process.env.GITHUB_CLIENT_SECRET || '';
const GITHUB_CALLBACK_URL  = process.env.GITHUB_CALLBACK_URL  || `http://localhost:${PORT}/auth/github/callback`;
const ADMIN_GITHUB_LOGIN   = process.env.ADMIN_GITHUB_LOGIN   || '';

// ── Express ─────────────────────────────────────────────────────────────────
const app    = express();
const server = http.createServer(app);

app.use(express.json());
app.use(express.urlencoded({ extended: false }));
app.use(session({
    secret: SESSION_SECRET,
    resave: false,
    saveUninitialized: false,
    cookie: { secure: false, maxAge: 7 * 24 * 60 * 60 * 1000 }
}));
app.use(passport.initialize());
app.use(passport.session());
app.use(express.static(path.join(__dirname, 'public')));

// ── Passport GitHub OAuth ────────────────────────────────────────────────────
if (GITHUB_CLIENT_ID && GITHUB_CLIENT_SECRET) {
    passport.use(new GitHubStrategy({
        clientID: GITHUB_CLIENT_ID,
        clientSecret: GITHUB_CLIENT_SECRET,
        callbackURL: GITHUB_CALLBACK_URL
    }, (accessToken, refreshToken, profile, done) => {
        const user = {
            id:       profile.id,
            login:    profile.username,
            name:     profile.displayName || profile.username,
            avatar:   profile.photos?.[0]?.value || '',
            token:    accessToken,
            isAdmin:  !ADMIN_GITHUB_LOGIN || profile.username === ADMIN_GITHUB_LOGIN
        };
        return done(null, user);
    }));
}

passport.serializeUser((user, done) => done(null, user));
passport.deserializeUser((user, done) => done(null, user));

// ── Auth middleware ──────────────────────────────────────────────────────────
const requireAuth = (req, res, next) => {
    if (!GITHUB_CLIENT_ID) return next(); // OAuth not configured → open access
    if (req.isAuthenticated()) return next();
    if (req.path.startsWith('/api/')) return res.status(401).json({ error: 'Non authentifié' });
    res.redirect('/');
};

const requireAdmin = (req, res, next) => {
    if (!GITHUB_CLIENT_ID) return next();
    if (req.user?.isAdmin) return next();
    res.status(403).json({ error: 'Accès administrateur requis' });
};

// ── Auth routes ──────────────────────────────────────────────────────────────
app.get('/auth/github', passport.authenticate('github', { scope: ['user:email'] }));

app.get('/auth/github/callback',
    passport.authenticate('github', { failureRedirect: '/?error=auth' }),
    (req, res) => res.redirect('/dashboard')
);

app.get('/auth/logout', (req, res) => {
    req.logout(() => res.redirect('/'));
});

app.get('/api/me', (req, res) => {
    if (!GITHUB_CLIENT_ID) {
        return res.json({ authenticated: true, name: 'root', login: 'root', isAdmin: true, oauthConfigured: false });
    }
    if (!req.user) return res.json({ authenticated: false, oauthConfigured: true });
    res.json({ authenticated: true, oauthConfigured: true, ...req.user });
});

// ── Setup detection ──────────────────────────────────────────────────────────
const isSetupDone = () => {
    const stateFile = path.join(DEVLAB_ROOT, 'state/registry.json');
    if (!fs.existsSync(stateFile)) return false;
    try {
        const reg = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
        return reg['bootstrap.base-packages']?.status === 'installed';
    } catch { return false; }
};

app.get('/api/setup/status', (req, res) => {
    res.json({ done: isSetupDone() });
});

// ── System info ──────────────────────────────────────────────────────────────
app.get('/api/system', requireAuth, async (req, res) => {
    try {
        const [cpu, mem, disk, os] = await Promise.all([
            si.currentLoad(),
            si.mem(),
            si.fsSize(),
            si.osInfo()
        ]);
        res.json({
            cpu:  { load: Math.round(cpu.currentLoad) },
            mem:  {
                total: mem.total,
                used:  mem.active,
                pct:   Math.round(mem.active / mem.total * 100)
            },
            disk: disk[0] ? {
                total: disk[0].size,
                used:  disk[0].used,
                pct:   Math.round(disk[0].use)
            } : {},
            os: os.distro + ' ' + os.release
        });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// ── Services status ──────────────────────────────────────────────────────────
const SERVICES = ['nginx', 'postgresql', 'redis-server', 'docker', 'ssh', 'fail2ban'];

const checkService = async (name) => {
    try {
        await execFileAsync('systemctl', ['is-active', '--quiet', name], { timeout: 3000 });
        return 'active';
    } catch {
        return 'inactive';
    }
};

app.get('/api/services', requireAuth, async (req, res) => {
    const results = await Promise.all(
        SERVICES.map(async (s) => ({ name: s, status: await checkService(s) }))
    );
    res.json(results);
});

// ── Modules registry ──────────────────────────────────────────────────────────
app.get('/api/modules', requireAuth, (req, res) => {
    const stateFile = path.join(DEVLAB_ROOT, 'state/registry.json');
    try {
        const reg = fs.existsSync(stateFile)
            ? JSON.parse(fs.readFileSync(stateFile, 'utf8'))
            : {};
        res.json(reg);
    } catch {
        res.json({});
    }
});

app.get('/api/modules/available', requireAuth, (req, res) => {
    const confFile = path.join(DEVLAB_ROOT, 'config/modules.conf');
    const result = [];
    if (!fs.existsSync(confFile)) return res.json(result);
    const lines = fs.readFileSync(confFile, 'utf8').split('\n');
    for (const line of lines) {
        const m = line.match(/^MODULE_([A-Z_]+)=(true|false)/);
        if (m) result.push({ key: m[1], enabled: m[2] === 'true' });
    }
    res.json(result);
});

// ── Setup wizard config writer ───────────────────────────────────────────────
app.post('/api/setup/write-config', (req, res) => {
    const { domain, project, uiPort, vscPort, ghId, ghSecret, ghAdmin, ghCb } = req.body;
    const localEnv = path.join(DEVLAB_ROOT, 'config/local.env');
    const secretsEnv = path.join(DEVLAB_ROOT, 'config/secrets.env');

    const localLines = [
        '# Generated by GamadCode setup wizard',
        `GAMADCODE_DOMAIN="${domain || ''}"`,
        `GAMADCODE_PROJECT_NAME="${project || 'GamadCode'}"`,
        `GAMADCODE_UI_PORT="${uiPort || 3000}"`,
        `CODE_SERVER_PORT="${vscPort || 8080}"`,
        ghAdmin ? `ADMIN_GITHUB_LOGIN="${ghAdmin}"` : '',
        ghCb    ? `GITHUB_CALLBACK_URL="${ghCb}"` : '',
    ].filter(Boolean).join('\n') + '\n';

    const secretLines = [
        '# GamadCode secrets — DO NOT COMMIT',
        ghId     ? `GITHUB_CLIENT_ID="${ghId}"` : '',
        ghSecret ? `GITHUB_CLIENT_SECRET="${ghSecret}"` : '',
    ].filter(Boolean).join('\n') + '\n';

    try {
        fs.writeFileSync(localEnv, localLines, { mode: 0o644 });
        if (ghSecret) fs.writeFileSync(secretsEnv, secretLines, { mode: 0o600 });
        res.json({ ok: true });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// ── Devlab command runner (admin only) ───────────────────────────────────────
app.post('/api/run', requireAuth, requireAdmin, (req, res) => {
    const { command, args = [] } = req.body;
    const ALLOWED = ['devlab', 'systemctl'];
    if (!ALLOWED.includes(command)) {
        return res.status(400).json({ error: 'Commande non autorisée' });
    }
    const bin = command === 'devlab' ? path.join(DEVLAB_ROOT, 'bin/devlab') : 'systemctl';
    const proc = spawn(bin, args, { stdio: ['ignore', 'pipe', 'pipe'] });
    let out = '';
    proc.stdout.on('data', d => { out += d; });
    proc.stderr.on('data', d => { out += d; });
    proc.on('close', code => res.json({ code, output: out }));
    proc.on('error', err => res.status(500).json({ error: err.message }));
});

// ── WebSocket — live logs ─────────────────────────────────────────────────────
const wss = new WebSocketServer({ server, path: '/ws/logs' });

wss.on('connection', (ws, req) => {
    const logDir = path.join(DEVLAB_ROOT, 'logs');
    if (!fs.existsSync(logDir)) { ws.close(); return; }

    const logFile = fs.readdirSync(logDir)
        .filter(f => f.endsWith('.log'))
        .sort()
        .pop();

    if (!logFile) { ws.send(JSON.stringify({ line: 'Aucun log disponible.' })); ws.close(); return; }

    const fullPath = path.join(logDir, logFile);
    ws.send(JSON.stringify({ file: logFile }));

    const tail = spawn('tail', ['-n', '100', '-f', fullPath]);
    tail.stdout.on('data', data => {
        if (ws.readyState === 1) {
            ws.send(JSON.stringify({ line: data.toString() }));
        }
    });
    ws.on('close', () => tail.kill());
    ws.on('error', () => tail.kill());
});

// ── SPA fallback ─────────────────────────────────────────────────────────────
app.get('/dashboard', requireAuth, (req, res) => res.sendFile(path.join(__dirname, 'public/dashboard.html')));
app.get('/modules',   requireAuth, (req, res) => res.sendFile(path.join(__dirname, 'public/modules.html')));
app.get('/logs',      requireAuth, (req, res) => res.sendFile(path.join(__dirname, 'public/logs.html')));
app.get('/setup',     (req, res)  => res.sendFile(path.join(__dirname, 'public/setup.html')));

// ── Start ─────────────────────────────────────────────────────────────────────
server.listen(PORT, '0.0.0.0', () => {
    console.log(`GamadCode UI → http://0.0.0.0:${PORT}`);
});
