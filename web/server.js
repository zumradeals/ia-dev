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
const https      = require('https');
const crypto     = require('crypto');
const { createProxyMiddleware } = require('http-proxy-middleware');

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

// ── Workspace proxy helpers ───────────────────────────────────────────────────
const wsTokenStore     = new Map(); // token → { port, userId, created }
const containerIPCache = new Map(); // port (number) → { ip, expires }
const activityCache    = new Map(); // userId → last DB write timestamp (debounce)

// Résoudre l'IP interne Docker d'un conteneur via son port externe
const resolveContainerIP = async (wsPort) => {
    const now = Date.now();
    const cached = containerIPCache.get(wsPort);
    if (cached && cached.expires > now) return cached.ip;

    const Docker = require('dockerode');
    const d = new Docker({ socketPath: '/var/run/docker.sock' });
    const containers = await d.listContainers({ filters: JSON.stringify({ status: ['running'] }) });
    for (const c of containers) {
        if ((c.Ports || []).some(p => p.PublicPort === wsPort)) {
            const info = await d.getContainer(c.Id).inspect();
            const nws  = info.NetworkSettings?.Networks || {};
            const ip   = Object.values(nws)[0]?.IPAddress;
            if (ip) {
                containerIPCache.set(wsPort, { ip, expires: now + 120000 });
                return ip;
            }
        }
    }
    return null;
};

// Résoudre l'ID d'un container via son port externe (pour docker exec)
const containerIDCache = new Map(); // ws_port → { id, expires }
const resolveContainerID = async (wsPort) => {
    const now = Date.now();
    const cached = containerIDCache.get(wsPort);
    if (cached && cached.expires > now) return cached.id;

    const Docker = require('dockerode');
    const d = new Docker({ socketPath: '/var/run/docker.sock' });
    const containers = await d.listContainers({ filters: JSON.stringify({ status: ['running'] }) });
    for (const c of containers) {
        if ((c.Ports || []).some(p => p.PublicPort === wsPort)) {
            containerIDCache.set(wsPort, { id: c.Id, expires: now + 120000 });
            return c.Id;
        }
    }
    return null;
};

// Proxy HTTP bas-niveau → pas de createProxyMiddleware (évite l'accrochage sur server.upgrade)
const proxyHTTP = (req, res, ip, internalPort) => {
    const subPath = (req.url || '/').replace(/^\/proxy\/\d+/, '') || '/';
    const opts = { hostname: ip, port: internalPort, path: subPath, method: req.method,
                   headers: { ...req.headers, host: `${ip}:${internalPort}` } };
    delete opts.headers.connection;
    const upstream = http.request(opts, (proxyRes) => {
        res.writeHead(proxyRes.statusCode, proxyRes.headers);
        proxyRes.pipe(res, { end: true });
    });
    req.pipe(upstream, { end: true });
    upstream.on('error', () => { try { res.status(502).end(); } catch {} });
};

// Proxy WebSocket bas-niveau via net.createConnection
const proxyWS = (req, socket, head, ip, internalPort) => {
    const net = require('net');
    const subPath  = (req.url || '/').replace(/^\/proxy\/\d+/, '') || '/';
    const hdrs     = Object.entries(req.headers).map(([k, v]) => `${k}: ${v}`).join('\r\n');
    const conn = net.createConnection({ host: ip, port: internalPort }, () => {
        conn.write(`${req.method || 'GET'} ${subPath} HTTP/1.1\r\n${hdrs}\r\n\r\n`);
        if (head?.length) conn.write(head);
        socket.pipe(conn);
        conn.pipe(socket);
    });
    conn.on('error', () => { try { socket.destroy(); } catch {} });
    socket.on('error', () => { try { conn.destroy(); } catch {} });
};

// wstoken : one-time URL token → lié à userId + port, TTL 4h
const generateWsToken = (port, userId) => {
    const cutoff = Date.now() - 4 * 3600000;
    for (const [k, v] of wsTokenStore) if (v.created < cutoff) wsTokenStore.delete(k);
    const token = crypto.randomBytes(32).toString('hex');
    wsTokenStore.set(token, { port, userId, created: Date.now() });
    return token;
};

// Cookie signé : ws_sig = port:userId:hmac — impossible à forger sans SESSION_SECRET
const signWsCookie = (port, userId) => {
    const payload  = `${port}:${userId}`;
    const hmac     = crypto.createHmac('sha256', SESSION_SECRET).update(payload).digest('hex').slice(0, 24);
    return `${payload}:${hmac}`;
};

const verifyWsCookie = (val) => {
    if (!val) return null;
    const parts = val.split(':');
    if (parts.length !== 3) return null;
    const [portStr, userStr, hmac] = parts;
    if (!/^\d+$/.test(portStr) || !/^\d+$/.test(userStr)) return null;
    const payload  = `${portStr}:${userStr}`;
    const expected = crypto.createHmac('sha256', SESSION_SECRET).update(payload).digest('hex').slice(0, 24);
    // Comparaison en temps constant pour éviter les timing attacks
    try {
        if (!crypto.timingSafeEqual(Buffer.from(hmac, 'utf8'), Buffer.from(expected, 'utf8'))) return null;
    } catch { return null; }
    return { port: parseInt(portStr, 10), userId: parseInt(userStr, 10) };
};

const parseCookie = (header, name) => {
    const m = (header || '').match(new RegExp('(?:^|;\\s*)' + name + '=([^;]*)'));
    return m ? decodeURIComponent(m[1]) : null;
};

const workspaceProxy = createProxyMiddleware({
    target: 'http://127.0.0.1',
    router: (req) => {
        const verified = verifyWsCookie(parseCookie(req.headers.cookie, 'ws_sig'));
        return `http://127.0.0.1:${verified ? verified.port : 0}`;
    },
    changeOrigin: false,
    ws: true,
    on: {
        error: (err, req, res) => {
            if (res && !res.headersSent && typeof res.status === 'function') {
                res.status(502).type('html').send(
                    'Workspace inaccessible — vérifiez qu\'il est démarré sur <a href="https://app.gamad.net/my">app.gamad.net</a>.'
                );
            }
        }
    }
});

// DB + Auth + Workspace + Payment (lazy — ne crash pas si pg non configuré au boot)
let db, authLib, workspaceLib;
let paymentLib = null;
try { paymentLib = require('./lib/payment'); } catch (e) { console.warn('[warn] payment.js non chargé :', e.message); }

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

// ── Auto-sleep des workspaces inactifs ───────────────────────────────────────
// Vérifie toutes les 2 min ; stoppe les workspaces sans activité depuis WORKSPACE_IDLE_MINUTES
setInterval(async () => {
    const idleMin = parseInt(process.env.WORKSPACE_IDLE_MINUTES || '30', 10);
    if (!db || !workspaceLib || isNaN(idleMin) || idleMin <= 0) return;
    try {
        const r = await db.query(
            `SELECT user_id FROM workspaces
             WHERE status = 'running'
             AND last_activity < NOW() - ($1 * INTERVAL '1 minute')`,
            [idleMin]
        );
        for (const row of r.rows) {
            workspaceLib.stopWorkspace(row.user_id).catch(() => {});
            console.log(`[auto-sleep] workspace user ${row.user_id} arrêté (inactif > ${idleMin} min)`);
        }
    } catch { /* silencieux */ }
}, 2 * 60 * 1000);

// ── Express ──────────────────────────────────────────────────────────────────
const app    = express();
const server = http.createServer(app);

app.set('trust proxy', 1);

// Capture du raw body pour vérification signature webhook GeniusPay
app.use(express.json({
    verify: (req, _res, buf) => { req.rawBody = buf.toString('utf8'); }
}));
app.use(express.urlencoded({ extended: false }));
app.use(session({
    secret:            SESSION_SECRET,
    resave:            false,
    saveUninitialized: false,
    cookie:            { secure: 'auto', maxAge: 30 * 24 * 60 * 60 * 1000 }
}));
app.use(passport.initialize());
app.use(passport.session());

// ── Proxy workspace (code.gamad.net) ─────────────────────────────────────────
app.use((req, res, next) => {
    const host = (req.headers.host || '').split(':')[0];
    if (host !== 'code.gamad.net') return next();

    // Token reçu → valider → set cookie signé → redirect
    if (req.query.wstoken) {
        const data = wsTokenStore.get(req.query.wstoken);
        if (!data || Date.now() - data.created > 4 * 3600000) {
            return res.status(403).type('html').send(
                'Lien expiré. <a href="https://app.gamad.net/my">Retour à app.gamad.net</a>.'
            );
        }
        wsTokenStore.delete(req.query.wstoken); // usage unique
        const sig = signWsCookie(data.port, data.userId);
        res.setHeader('Set-Cookie', `ws_sig=${sig}; Path=/; HttpOnly; Secure; SameSite=None; Max-Age=14400`);
        const extra = Object.entries(req.query).filter(([k]) => k !== 'wstoken').map(([k, v]) => `${k}=${encodeURIComponent(v)}`).join('&');
        return res.redirect(302, extra ? `/?${extra}` : '/');
    }

    // Cookie signé présent → vérifier HMAC + extraire port
    const verified = verifyWsCookie(parseCookie(req.headers.cookie, 'ws_sig'));
    if (!verified) {
        return res.status(403).type('html').send(
            'Non autorisé. <a href="https://app.gamad.net/my">Ouvrez votre workspace depuis app.gamad.net</a>.'
        );
    }
    const port = verified.port;

    // /proxy/:internalPort/* → proxy direct vers l'IP interne du conteneur
    const portMatch = req.path.match(/^\/proxy\/(\d+)/);
    if (portMatch) {
        const internalPort = parseInt(portMatch[1]);
        resolveContainerIP(port)
            .then(ip => {
                if (!ip) return res.status(502).send('Conteneur introuvable');
                proxyHTTP(req, res, ip, internalPort);
            })
            .catch(() => res.status(502).send('Erreur proxy interne'));
        return;
    }

    // OAuth callback Claude Code : /callback?code=...&state=...
    // L'extension démarre un serveur HTTP local sur un port aléatoire pour recevoir
    // le token — on détecte ce port via ss dans le container et on proxy vers lui.
    if (req.path === '/callback' && req.query.code && req.query.state) {
        const wsPort = verified.port;
        if (!wsPort) return res.status(403).send('Session expirée');

        Promise.all([
            resolveContainerIP(wsPort),
            resolveContainerID(wsPort)
        ]).then(([ip, containerId]) => {
            if (!ip || !containerId) return res.status(502).send('Container introuvable');

            execFile('docker', ['exec', containerId, 'ss', '-tlnp'], (err, stdout) => {
                if (err) return res.status(504).send(
                    'Serveur OAuth non trouvé. Réessayez la connexion dans Claude Code.'
                );
                const ports = (stdout.match(/:\d+/g) || [])
                    .map(p => parseInt(p.slice(1)))
                    .filter(p => p > 1024 && p !== 8080);

                if (!ports.length) return res.status(504).send(
                    'Serveur OAuth non trouvé. Réessayez la connexion dans Claude Code.'
                );
                proxyHTTP(req, res, ip, ports[0]);
            });
        }).catch(() => res.status(502).send('Erreur proxy OAuth'));
        return;
    }

    // Mettre à jour last_activity (au plus 1 écriture/min par user)
    if (verified.userId && db) {
        const now = Date.now();
        const last = activityCache.get(verified.userId) || 0;
        if (now - last > 60_000) {
            activityCache.set(verified.userId, now);
            db.query("UPDATE workspaces SET last_activity = NOW() WHERE user_id = $1", [verified.userId])
              .catch(() => {});
        }
    }

    workspaceProxy(req, res, next);
});

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
    if (req.isAuthenticated() && req.user?.isAdmin) return next(); // GitHub OAuth
    if (req.session.isAdmin) return next();                        // email admin
    if (!GITHUB_CLIENT_ID && !req.session.userId) return next();   // dev mode sans auth
    if (req.path.startsWith('/api/')) return res.status(403).json({ error: 'Accès admin requis' });
    res.redirect('/login');
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
            const r = await db.query('SELECT id, email, name, is_admin, plan, claude_model, created_at FROM users WHERE id = $1', [req.session.userId]);
            if (!r.rows.length) { req.session.destroy(); return res.json({ authenticated: false }); }
            const u = r.rows[0];
            return res.json({ authenticated: true, type: 'user', userId: u.id, email: u.email, name: u.name, isAdmin: u.is_admin, plan: u.plan || 'free', claudeModel: u.claude_model || null, createdAt: u.created_at });
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

// ── Modèle Claude utilisateur (user → son propre choix) ──────────────────────
app.put('/api/me/model', requireUser, async (req, res) => {
    loadLibs();
    if (!db) return res.status(503).json({ error: 'DB non disponible' });
    const userId = req.session.userId;
    if (!userId) return res.status(403).json({ error: 'Non autorisé' });
    const { model } = req.body;
    const ALLOWED = ['claude-sonnet-4-6', 'claude-opus-4-8', 'claude-haiku-4-5-20251001', null, ''];
    if (!ALLOWED.includes(model)) return res.status(400).json({ error: 'Modèle invalide' });
    try {
        await db.query('UPDATE users SET claude_model = $1 WHERE id = $2', [model || null, userId]);
        res.json({ ok: true });
    } catch (e) { res.status(500).json({ error: e.message }); }
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
        req.session.isAdmin   = user.is_admin || false;
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
            const wsDomain = process.env.CODE_SERVER_DOMAIN || 'code.gamad.net';
            const token    = generateWsToken(ws.port, userId);
            url = `https://${wsDomain}/?wstoken=${token}`;
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
        const ws       = await workspaceLib.createWorkspace(userId);
        const wsDomain = process.env.CODE_SERVER_DOMAIN || 'code.gamad.net';
        const token    = generateWsToken(ws.port, userId);
        const url      = `https://${wsDomain}/?wstoken=${token}`;
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

// ── Lancement d'un outil IA (Claude / Codex) à l'ouverture du workspace ───────
// Écrit un marqueur dans le volume du user ; l'extension gamadcode-launcher du
// conteneur le lit et ouvre l'outil (webview natif, fallback terminal).
app.post('/api/workspace/launch', requireUser, async (req, res) => {
    loadLibs();
    const userId = req.session.userId;
    if (!Number.isInteger(userId) || userId <= 0) return res.status(400).json({ error: 'Session invalide' });
    if (!workspaceLib) return res.status(503).json({ error: 'Service non disponible' });

    const tool = req.body.tool;
    if (!['claude', 'codex'].includes(tool)) return res.status(400).json({ error: 'Outil non supporté' });

    try {
        // getWorkspaceStatus évite de recréer un workspace déjà running
        const ws = await workspaceLib.getWorkspaceStatus(userId);
        if (ws.status !== 'running' || !ws.port) {
            return res.status(409).json({ error: 'Démarrez votre environnement avant de lancer un outil' });
        }

        // Volume host monté sur /home/workspace dans le conteneur (WORKSPACE_BASE/<userId> → /home/workspace)
        const base     = process.env.WORKSPACE_BASE || '/opt/gamadcode/users';
        const gamadDir = path.join(base, String(userId), '.gamad');
        const marker   = path.join(gamadDir, 'autostart');
        const nonce    = crypto.randomBytes(8).toString('hex');

        // Le répertoire et le fichier sont owned par coder (uid 1000) pour
        // que l'extension puisse supprimer le marker sans droits root.
        fs.mkdirSync(gamadDir, { recursive: true });
        fs.chownSync(gamadDir, 1000, 1000);
        fs.chmodSync(gamadDir, 0o755);
        fs.writeFileSync(marker, `${tool}:${nonce}:${Date.now()}`);
        fs.chownSync(marker, 1000, 1000);
        fs.chmodSync(marker, 0o644);

        const wsDomain = process.env.CODE_SERVER_DOMAIN || 'code.gamad.net';
        const token    = generateWsToken(ws.port, userId);
        res.json({ url: `https://${wsDomain}/?wstoken=${token}` });
    } catch (e) {
        console.error('[workspace] launch error:', e.message);
        res.status(500).json({ error: e.message });
    }
});

// ── GitHub repos ──────────────────────────────────────────────────────────────
const githubGet = (path, token) => new Promise((resolve, reject) => {
    https.get(`https://api.github.com${path}`, {
        headers: { 'Authorization': `Bearer ${token}`, 'Accept': 'application/vnd.github.v3+json', 'User-Agent': 'GamadCode/1.0' }
    }, (res) => {
        let d = '';
        res.on('data', c => d += c);
        res.on('end', () => {
            try { resolve({ status: res.statusCode, data: JSON.parse(d) }); }
            catch (e) { reject(e); }
        });
    }).on('error', reject);
});

app.get('/api/github/repos', requireUser, async (req, res) => {
    loadLibs();
    const userId = req.session.userId;
    if (!userId || !db) return res.status(503).json({ error: 'Service non disponible' });

    try {
        const r = await db.query("SELECT key_value FROM api_keys WHERE user_id = $1 AND provider = 'github'", [userId]);
        if (!r.rows.length) return res.status(404).json({ error: 'Token GitHub non configuré' });

        const { status, data } = await githubGet('/user/repos?per_page=100&sort=updated&affiliation=owner,collaborator', r.rows[0].key_value);
        if (status !== 200) return res.status(status).json({ error: data.message || 'Erreur GitHub API' });

        res.json(data.map(repo => ({
            id: repo.id, name: repo.name, full_name: repo.full_name,
            private: repo.private, description: repo.description,
            language: repo.language, updated_at: repo.updated_at,
            clone_url: repo.clone_url, html_url: repo.html_url,
            stargazers_count: repo.stargazers_count
        })));
    } catch (e) { res.status(500).json({ error: e.message }); }
});

app.post('/api/workspace/open-repo', requireUser, async (req, res) => {
    loadLibs();
    const userId = req.session.userId;
    if (!userId || !workspaceLib || !db) return res.status(503).json({ error: 'Service non disponible' });

    const { cloneUrl, repoName } = req.body;
    if (!cloneUrl || !repoName) return res.status(400).json({ error: 'Paramètres manquants' });
    if (!/^[a-zA-Z0-9._-]+$/.test(repoName)) return res.status(400).json({ error: 'Nom de dépôt invalide' });

    try {
        const ws = await workspaceLib.getWorkspaceStatus(userId);
        if (ws.status !== 'running') return res.status(400).json({ error: 'Démarrez votre environnement d\'abord' });

        // Injecter le token dans l'URL pour les dépôts privés
        let authUrl = cloneUrl;
        const tokenRow = await db.query("SELECT key_value FROM api_keys WHERE user_id=$1 AND provider='github'", [userId]);
        if (tokenRow.rows.length && cloneUrl.startsWith('https://github.com/')) {
            authUrl = cloneUrl.replace('https://github.com/', `https://oauth2:${tokenRow.rows[0].key_value}@github.com/`);
        }

        const targetPath = await workspaceLib.cloneRepo(userId, authUrl, repoName);

        const wsDomain = process.env.CODE_SERVER_DOMAIN || 'code.gamad.net';
        const token    = generateWsToken(ws.port, userId);
        res.json({ url: `https://${wsDomain}/?wstoken=${token}&folder=${encodeURIComponent(targetPath)}` });
    } catch (e) { res.status(500).json({ error: e.message }); }
});

// ── Billing GeniusPay ─────────────────────────────────────────────────────────

// POST /api/billing/checkout — crée une session de paiement GeniusPay
app.post('/api/billing/checkout', requireUser, async (req, res) => {
    loadLibs();
    const userId = req.session.userId;
    if (!Number.isInteger(userId) || userId <= 0) return res.status(400).json({ error: 'Session invalide' });
    if (!paymentLib) return res.status(503).json({ error: 'Paiement non configuré' });
    if (!db) return res.status(503).json({ error: 'Base de données non disponible' });

    const { plan } = req.body;
    if (!['pro', 'enterprise'].includes(plan)) return res.status(400).json({ error: 'Plan invalide' });

    try {
        const user = await db.query('SELECT email, name FROM users WHERE id = $1', [userId]);
        if (!user.rows.length) return res.status(404).json({ error: 'Utilisateur introuvable' });

        const uiDomain = process.env.GAMADCODE_UI_DOMAIN || process.env.GAMADCODE_DOMAIN || `localhost:${PORT}`;
        const proto    = uiDomain.startsWith('localhost') ? 'http' : 'https';

        const session = await paymentLib.createCheckout({
            plan,
            userId,
            userEmail:  user.rows[0].email,
            userName:   user.rows[0].name,
            successUrl: `${proto}://${uiDomain}/billing/success`,
            errorUrl:   `${proto}://${uiDomain}/billing/error`
        });

        res.json({ checkout_url: session.checkout_url, reference: session.reference });
    } catch (e) {
        console.error('[billing] checkout error:', e.message);
        res.status(500).json({ error: e.message });
    }
});

// GET /api/billing — statut d'abonnement de l'utilisateur connecté
app.get('/api/billing', requireUser, async (req, res) => {
    loadLibs();
    const userId = req.session.userId;
    if (!userId || !db) return res.json({ plan: 'free', status: 'none' });

    try {
        const sub = await db.query(
            `SELECT s.plan, s.status, s.expires_at, s.payment_reference, s.started_at
             FROM subscriptions s
             WHERE s.user_id = $1 AND s.status = 'active'
             ORDER BY s.created_at DESC LIMIT 1`,
            [userId]
        );
        if (!sub.rows.length) return res.json({ plan: 'free', status: 'none' });

        const s = sub.rows[0];
        // Vérifier expiration
        if (s.expires_at && new Date(s.expires_at) < new Date()) {
            await db.query("UPDATE subscriptions SET status='expired' WHERE user_id=$1 AND status='active'", [userId]);
            await db.query("UPDATE users SET plan='free' WHERE id=$1", [userId]);
            return res.json({ plan: 'free', status: 'expired' });
        }
        res.json({ plan: s.plan, status: s.status, expires_at: s.expires_at, started_at: s.started_at });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// POST /api/billing/webhook — webhook GeniusPay (signature HMAC vérifiée)
app.post('/api/billing/webhook', async (req, res) => {
    loadLibs();
    if (!paymentLib || !db) return res.status(503).json({ error: 'Service non disponible' });

    const signature = req.headers['x-webhook-signature'] || '';
    const timestamp = req.headers['x-webhook-timestamp'] || '';
    const event     = req.headers['x-webhook-event']     || req.body?.event || '';

    // Vérification HMAC — rejeter si invalide
    if (!paymentLib.verifyWebhook(req.rawBody || JSON.stringify(req.body), signature, timestamp)) {
        console.warn('[billing] webhook signature invalide');
        return res.status(401).json({ error: 'Signature invalide' });
    }

    const payload   = req.body;
    const data      = payload.data || {};
    const reference = data.reference;
    const metadata  = data.metadata || {};
    const userId    = parseInt(metadata.user_id, 10);
    const plan      = metadata.plan;

    // Logger tous les événements
    try {
        await db.query(
            `INSERT INTO payment_events (user_id, reference, event, amount, currency, status, payload)
             VALUES ($1, $2, $3, $4, $5, $6, $7)`,
            [userId || null, reference, event, data.amount, data.currency, data.status, JSON.stringify(payload)]
        );
    } catch (e) { console.error('[billing] log event error:', e.message); }

    // Paiement réussi → activer l'abonnement
    if (event === 'payment.success' && Number.isInteger(userId) && userId > 0 && plan) {
        try {
            const expiresAt = new Date();
            expiresAt.setDate(expiresAt.getDate() + 31); // 31 jours

            // Expirer les anciens abonnements actifs
            await db.query(
                "UPDATE subscriptions SET status='cancelled' WHERE user_id=$1 AND status='active'",
                [userId]
            );

            // Créer le nouvel abonnement
            await db.query(
                `INSERT INTO subscriptions (user_id, plan, status, payment_reference, expires_at)
                 VALUES ($1, $2, 'active', $3, $4)`,
                [userId, plan, reference, expiresAt]
            );

            // Mettre à jour le plan de l'utilisateur
            await db.query('UPDATE users SET plan=$1 WHERE id=$2', [plan, userId]);

            console.log(`[billing] ✓ ${plan} activé pour user ${userId} (réf: ${reference})`);
        } catch (e) {
            console.error('[billing] activation error:', e.message);
            return res.status(500).json({ error: e.message });
        }
    }

    res.json({ received: true });
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

// ── Admin API ─────────────────────────────────────────────────────────────────
app.get('/api/admin/users', requireUser, requireAdmin, async (req, res) => {
    loadLibs();
    if (!db) return res.status(503).json({ error: 'DB non disponible' });
    try {
        const r = await db.query(`
            SELECT u.id, u.email, u.name, u.is_admin, u.plan, u.created_at,
                   w.status AS ws_status, w.port AS ws_port, w.container_id
            FROM users u LEFT JOIN workspaces w ON w.user_id = u.id
            ORDER BY u.created_at DESC`);
        res.json(r.rows);
    } catch (e) { res.status(500).json({ error: e.message }); }
});

app.put('/api/admin/users/:id', requireUser, requireAdmin, async (req, res) => {
    loadLibs();
    if (!db) return res.status(503).json({ error: 'DB non disponible' });
    const { plan, is_admin } = req.body;
    const fields = [], vals = [];
    if (plan !== undefined)     { fields.push(`plan=$${fields.length+1}`);     vals.push(plan); }
    if (is_admin !== undefined) { fields.push(`is_admin=$${fields.length+1}`); vals.push(is_admin); }
    if (!fields.length) return res.status(400).json({ error: 'Rien à modifier' });
    vals.push(req.params.id);
    try {
        await db.query(`UPDATE users SET ${fields.join(',')} WHERE id=$${vals.length}`, vals);
        res.json({ ok: true });
    } catch (e) { res.status(500).json({ error: e.message }); }
});

app.delete('/api/admin/users/:id', requireUser, requireAdmin, async (req, res) => {
    loadLibs();
    if (!db || !workspaceLib) return res.status(503).json({ error: 'Service non disponible' });
    try {
        await workspaceLib.stopWorkspace(req.params.id).catch(() => {});
        await db.query('DELETE FROM users WHERE id=$1', [req.params.id]);
        res.json({ ok: true });
    } catch (e) { res.status(500).json({ error: e.message }); }
});

app.post('/api/admin/users/:id/workspace/stop', requireUser, requireAdmin, async (req, res) => {
    loadLibs();
    if (!workspaceLib) return res.status(503).json({ error: 'Service non disponible' });
    try { await workspaceLib.stopWorkspace(req.params.id); res.json({ ok: true }); }
    catch (e) { res.status(500).json({ error: e.message }); }
});

app.post('/api/admin/users/:id/workspace/reset', requireUser, requireAdmin, async (req, res) => {
    loadLibs();
    if (!workspaceLib || !db) return res.status(503).json({ error: 'Service non disponible' });
    try {
        await workspaceLib.stopWorkspace(req.params.id).catch(() => {});
        const ws = await db.query('SELECT container_id FROM workspaces WHERE user_id=$1', [req.params.id]);
        if (ws.rows.length && ws.rows[0].container_id) {
            const Docker = require('dockerode');
            const d = new Docker({ socketPath: '/var/run/docker.sock' });
            try { await d.getContainer(ws.rows[0].container_id).remove({ force: true }); } catch {}
        }
        await db.query('DELETE FROM workspaces WHERE user_id=$1', [req.params.id]);
        res.json({ ok: true });
    } catch (e) { res.status(500).json({ error: e.message }); }
});

// ── Admin : Claude Code settings ──────────────────────────────────────────────
const LOCAL_ENV_PATH = path.join(DEVLAB_ROOT, 'config/local.env');

const CLAUDE_MODELS = [
    { value: 'claude-sonnet-4-6',          label: 'Claude Sonnet 4.6 (standard — recommandé)' },
    { value: 'claude-opus-4-8',            label: 'Claude Opus 4.8 (puissant, contexte standard)' },
    { value: 'claude-haiku-4-5-20251001',  label: 'Claude Haiku 4.5 (rapide, léger)' },
];

app.get('/api/admin/claude-settings', requireUser, requireAdmin, (req, res) => {
    try {
        const content = fs.existsSync(LOCAL_ENV_PATH) ? fs.readFileSync(LOCAL_ENV_PATH, 'utf8') : '';
        const modelMatch = content.match(/^CLAUDE_DEFAULT_MODEL="?([^"\n]+)"?/m);
        const idleMatch  = content.match(/^WORKSPACE_IDLE_MINUTES="?(\d+)"?/m);
        res.json({
            model:        modelMatch ? modelMatch[1] : (process.env.CLAUDE_DEFAULT_MODEL || 'claude-sonnet-4-6'),
            idleMinutes:  idleMatch  ? parseInt(idleMatch[1], 10) : parseInt(process.env.WORKSPACE_IDLE_MINUTES || '30', 10),
            models: CLAUDE_MODELS,
        });
    } catch (e) { res.status(500).json({ error: e.message }); }
});

app.put('/api/admin/claude-settings', requireUser, requireAdmin, (req, res) => {
    const { model, idleMinutes } = req.body;
    if (model !== undefined && !CLAUDE_MODELS.some(m => m.value === model))
        return res.status(400).json({ error: 'Modèle invalide' });
    if (idleMinutes !== undefined) {
        const n = parseInt(idleMinutes, 10);
        if (isNaN(n) || n < 5 || n > 1440) return res.status(400).json({ error: 'idleMinutes doit être entre 5 et 1440' });
    }
    try {
        let content = fs.existsSync(LOCAL_ENV_PATH) ? fs.readFileSync(LOCAL_ENV_PATH, 'utf8') : '';
        const setEnv = (key, val) => {
            if (new RegExp(`^${key}=`, 'm').test(content)) {
                content = content.replace(new RegExp(`^${key}=.*`, 'm'), `${key}="${val}"`);
            } else {
                content = content.trimEnd() + `\n${key}="${val}"\n`;
            }
        };
        if (model !== undefined)      { setEnv('CLAUDE_DEFAULT_MODEL', model); process.env.CLAUDE_DEFAULT_MODEL = model; }
        if (idleMinutes !== undefined) { setEnv('WORKSPACE_IDLE_MINUTES', idleMinutes); process.env.WORKSPACE_IDLE_MINUTES = String(idleMinutes); }
        fs.writeFileSync(LOCAL_ENV_PATH, content, 'utf8');
        res.json({ ok: true });
    } catch (e) { res.status(500).json({ error: e.message }); }
});

const EXTENSIONS_CONF_PATH = process.env.WORKSPACE_EXTENSIONS_CONF || '/opt/gamadcode/workspace-extensions.conf';

app.get('/api/admin/extensions', requireUser, requireAdmin, (req, res) => {
    try { res.json({ content: fs.readFileSync(EXTENSIONS_CONF_PATH, 'utf8') }); }
    catch { res.json({ content: '' }); }
});

app.put('/api/admin/extensions', requireUser, requireAdmin, (req, res) => {
    const { content } = req.body;
    if (typeof content !== 'string') return res.status(400).json({ error: 'Contenu invalide' });
    try {
        fs.writeFileSync(EXTENSIONS_CONF_PATH, content, 'utf8');
        // Synchroniser le repo si symlink
        const repoPath = path.join(DEVLAB_ROOT, 'config/workspace-extensions.conf');
        if (!fs.existsSync(repoPath) || fs.readFileSync(repoPath,'utf8') !== content)
            fs.writeFileSync(repoPath, content, 'utf8');
        res.json({ ok: true });
    } catch (e) { res.status(500).json({ error: e.message }); }
});

// ── WebSocket — routing centralisé ───────────────────────────────────────────
// noServer: true évite que wss détruise les sockets code.gamad.net
const wss = new WebSocketServer({ noServer: true });

server.on('upgrade', (req, socket, head) => {
    const host = (req.headers.host || '').split(':')[0];

    // Workspace OpenVSCode Server → proxy vers le conteneur Docker
    if (host === 'code.gamad.net') {
        const wsSig = verifyWsCookie(parseCookie(req.headers.cookie, 'ws_sig'));
        if (!wsSig) { socket.destroy(); return; }
        const wsPort = wsSig.port;

        // /proxy/:internalPort/* → WS direct vers IP interne (ex: Claude Code MCP)
        const urlPath    = (req.url || '').split('?')[0];
        const portMatch  = urlPath.match(/^\/proxy\/(\d+)/);
        if (portMatch) {
            resolveContainerIP(wsPort)
                .then(ip => {
                    if (!ip) { socket.destroy(); return; }
                    proxyWS(req, socket, head, ip, parseInt(portMatch[1]));
                })
                .catch(() => socket.destroy());
            return;
        }

        workspaceProxy.upgrade(req, socket, head);
        return;
    }

    // Live logs → wss
    const urlPath = (req.url || '').split('?')[0];
    if (urlPath === '/ws/logs') {
        wss.handleUpgrade(req, socket, head, (ws) => wss.emit('connection', ws, req));
        return;
    }

    socket.destroy();
});

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
app.get('/admin',     requireUser, requireAdmin, (req, res) => res.sendFile(path.join(__dirname, 'public/admin.html')));
app.get('/modules',   requireUser, (req, res) => res.sendFile(path.join(__dirname, 'public/modules.html')));
app.get('/logs',      requireUser, (req, res) => res.sendFile(path.join(__dirname, 'public/logs.html')));
app.get('/setup',           (req, res)  => res.sendFile(path.join(__dirname, 'public/setup.html')));
app.get('/billing/success', requireUser, (req, res) => res.sendFile(path.join(__dirname, 'public/billing-success.html')));
app.get('/billing/error',   (req, res)  => res.sendFile(path.join(__dirname, 'public/billing-error.html')));

// ── Start ─────────────────────────────────────────────────────────────────────
server.listen(PORT, '0.0.0.0', () => {
    console.log(`GamadCode → http://0.0.0.0:${PORT}`);
});
