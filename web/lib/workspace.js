'use strict';
const Docker = require('dockerode');
const path   = require('path');
const fs     = require('fs');
const crypto = require('crypto');
const db     = require('./db');

const docker = new Docker({ socketPath: '/var/run/docker.sock' });

const PORT_MIN           = 10000;
const PORT_MAX           = 20000;
const WORKSPACE_IMAGE    = process.env.WORKSPACE_IMAGE   || 'zumradeals/gamadcode-workspace:latest';
const WORKSPACE_BASE     = process.env.WORKSPACE_BASE    || '/opt/gamadcode/users';

const PROVIDER_ENV_MAP = {
    anthropic: 'ANTHROPIC_API_KEY',
    openai:    'OPENAI_API_KEY',
    github:    'GITHUB_TOKEN'
};

const getNextPort = async () => {
    const result = await db.query(
        "SELECT port FROM workspaces WHERE status != 'stopped'"
    );
    const used = new Set(result.rows.map(r => r.port));
    for (let p = PORT_MIN; p <= PORT_MAX; p++) {
        if (!used.has(p)) return p;
    }
    throw new Error('Plus de ports disponibles');
};

const getUserEnvVars = async (userId) => {
    const [keysResult, userResult] = await Promise.all([
        db.query('SELECT provider, key_value FROM api_keys WHERE user_id = $1', [userId]),
        db.query('SELECT claude_model FROM users WHERE id = $1', [userId]),
    ]);

    const vars = keysResult.rows
        .filter(r => r.key_value)
        .map(r => `${PROVIDER_ENV_MAP[r.provider] || r.provider.toUpperCase() + '_KEY'}=${r.key_value}`);

    const hasAnthropic = keysResult.rows.some(r => r.provider === 'anthropic' && r.key_value);
    if (!hasAnthropic && process.env.ANTHROPIC_API_KEY) {
        vars.push(`ANTHROPIC_API_KEY=${process.env.ANTHROPIC_API_KEY}`);
    }

    // Modèle : choix utilisateur > défaut admin > rien
    const claudeModel = userResult.rows[0]?.claude_model || process.env.CLAUDE_DEFAULT_MODEL;
    if (claudeModel) vars.push(`CLAUDE_DEFAULT_MODEL=${claudeModel}`);

    return vars;
};

const pullImage = (image) => new Promise((resolve, reject) => {
    docker.pull(image, (err, stream) => {
        if (err) return reject(err);
        docker.modem.followProgress(stream, (pullErr) => {
            if (pullErr) reject(pullErr);
            else resolve();
        });
    });
});

const ensureImage = async (image) => {
    try {
        await docker.getImage(image).inspect();
    } catch {
        await pullImage(image);
    }
};

const VALID_TEMPLATES = new Set(['blank', 'react-vite', 'fastapi', 'express-ts']);

const createWorkspace = async (userId, template = 'blank') => {
    if (!VALID_TEMPLATES.has(template)) template = 'blank';
    // Workspace existant ?
    const existing = await db.query(
        'SELECT * FROM workspaces WHERE user_id = $1',
        [userId]
    );

    if (existing.rows.length > 0) {
        const ws = existing.rows[0];

        if (ws.container_id) {
            try {
                const c    = docker.getContainer(ws.container_id);
                const info = await c.inspect();
                const image = info.Config?.Image || '';
                const isUpToDate = image.includes('openvscode-server')
                    || image.startsWith(WORKSPACE_IMAGE.split(':')[0]);

                if (isUpToDate) {
                    if (!info.State.Running) {
                        await c.start();
                        const curMonth = new Date().toISOString().slice(0, 7);
                        await db.query(
                            `UPDATE workspaces SET status = 'running', session_started_at = NOW(),
                             usage_seconds_month = CASE WHEN usage_month = $1 THEN usage_seconds_month ELSE 0 END,
                             usage_month = $1 WHERE id = $2`,
                            [curMonth, ws.id]
                        );
                    }
                    return { ...ws, status: 'running' };
                }
                // Ancienne config → stopper, supprimer, recréer avec le nouveau script
                try { await c.stop({ t: 5 }); } catch { /* déjà arrêté */ }
                await c.remove();
            } catch { /* conteneur introuvable → recréer */ }
            await db.query('DELETE FROM workspaces WHERE id = $1', [ws.id]);
        }
    }

    const port     = await getNextPort();
    const envVars  = await getUserEnvVars(userId);
    if (template !== 'blank') envVars.push(`WORKSPACE_TEMPLATE=${template}`);
    const wsPath   = path.join(WORKSPACE_BASE, String(userId));

    // Limites de ressources selon le plan de l'utilisateur
    const planRow = await db.query(
        `SELECT p.cpu_limit, p.ram_limit FROM users u
         LEFT JOIN plans p ON p.name = COALESCE(u.plan, 'free')
         WHERE u.id = $1`, [userId]
    );
    const { cpu_limit = 1.0, ram_limit = 512 } = planRow.rows[0] || {};

    fs.mkdirSync(wsPath, { recursive: true });
    try { fs.chownSync(wsPath, 1000, 1000); } catch {}
    await ensureImage(WORKSPACE_IMAGE);

    const STARTUP_SCRIPT  = process.env.WORKSPACE_STARTUP_SCRIPT  || '/opt/gamadcode/start-workspace.sh';
    const EXTENSIONS_CONF = process.env.WORKSPACE_EXTENSIONS_CONF || '/opt/gamadcode/workspace-extensions.conf';

    const container = await docker.createContainer({
        Image:      WORKSPACE_IMAGE,
        name:       `gamadcode-${userId}`,
        Entrypoint: ['/usr/bin/bash', '/gamad-startup.sh'],
        Cmd:        [],
        Env:        envVars,
        ExposedPorts: { '8080/tcp': {} },
        HostConfig: {
            PortBindings:  { '8080/tcp': [{ HostPort: String(port) }] },
            Binds: [
                `${wsPath}:/home/workspace`,
                `${STARTUP_SCRIPT}:/gamad-startup.sh:ro`,
                `${EXTENSIONS_CONF}:/opt/gamadcode/extensions.conf:ro`
            ],
            RestartPolicy: { Name: 'unless-stopped' },
            NanoCPUs: Math.round(cpu_limit * 1e9),
            Memory:   ram_limit * 1024 * 1024,
        }
    });

    await container.start();

    const previewToken = crypto.randomBytes(24).toString('hex');

    const curMonth = new Date().toISOString().slice(0, 7);
    const result = await db.query(
        `INSERT INTO workspaces
         (user_id, container_id, port, status, last_activity, template, preview_token, session_started_at, usage_month)
         VALUES ($1, $2, $3, 'running', NOW(), $4, $5, NOW(), $6) RETURNING *`,
        [userId, container.id, port, template, previewToken, curMonth]
    );

    return result.rows[0];
};

const stopWorkspace = async (userId) => {
    const result = await db.query(
        'SELECT * FROM workspaces WHERE user_id = $1',
        [userId]
    );
    if (result.rows.length === 0) return;
    const ws = result.rows[0];

    if (ws.container_id) {
        try {
            await docker.getContainer(ws.container_id).stop({ t: 10 });
        } catch { /* déjà arrêté */ }
    }

    // Calculer et flush le temps de la session courante
    const curMonth = new Date().toISOString().slice(0, 7);
    const sessionSecs = ws.session_started_at
        ? Math.floor((Date.now() - new Date(ws.session_started_at).getTime()) / 1000)
        : 0;
    const prevSecs = (ws.usage_month === curMonth) ? (ws.usage_seconds_month || 0) : 0;

    await db.query(
        `UPDATE workspaces
         SET status = 'stopped', session_started_at = NULL,
             usage_seconds_month = $1, usage_month = $2
         WHERE id = $3`,
        [prevSecs + sessionSecs, curMonth, ws.id]
    );
};

const getWorkspaceStatus = async (userId) => {
    const result = await db.query(
        'SELECT * FROM workspaces WHERE user_id = $1',
        [userId]
    );
    if (result.rows.length === 0) return { status: 'none' };

    const ws = result.rows[0];

    // Synchronise le statut DB avec le vrai état Docker
    if (ws.container_id) {
        try {
            const info    = await docker.getContainer(ws.container_id).inspect();
            const running = info.State.Running;
            const dbStatus = running ? 'running' : 'stopped';
            if (dbStatus !== ws.status) {
                await db.query(
                    'UPDATE workspaces SET status = $1 WHERE id = $2',
                    [dbStatus, ws.id]
                );
                ws.status = dbStatus;
            }
        } catch {
            ws.status = 'stopped';
        }
    }

    // Générer le token si absent (workspaces antérieurs à migration 007)
    if (!ws.preview_token) {
        const token = crypto.randomBytes(24).toString('hex');
        await db.query('UPDATE workspaces SET preview_token = $1 WHERE id = $2', [token, ws.id]);
        ws.preview_token = token;
    }

    return ws;
};

const { execFile } = require('child_process');
const execFileP = (cmd, args, opts) => new Promise((resolve, reject) =>
    execFile(cmd, args, opts, (err, stdout, stderr) =>
        err ? reject(Object.assign(err, { stderr })) : resolve(stdout)));

const cloneRepo = async (userId, cloneUrl, repoName) => {
    // Clone directement sur le host dans le volume → visible immédiatement dans le conteneur
    const hostTarget      = path.join(WORKSPACE_BASE, String(userId), repoName);
    const containerTarget = `/home/workspace/${repoName}`;

    fs.mkdirSync(path.join(WORKSPACE_BASE, String(userId)), { recursive: true });

    if (!fs.existsSync(path.join(hostTarget, '.git'))) {
        await execFileP('git', ['clone', '--depth=1', cloneUrl, hostTarget], { timeout: 60000 });
    }

    return containerTarget;
};

module.exports = { createWorkspace, stopWorkspace, getWorkspaceStatus, cloneRepo, VALID_TEMPLATES };
