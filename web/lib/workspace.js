'use strict';
const Docker = require('dockerode');
const path   = require('path');
const fs     = require('fs');
const db     = require('./db');

const docker = new Docker({ socketPath: '/var/run/docker.sock' });

const PORT_MIN           = 10000;
const PORT_MAX           = 20000;
const CODE_SERVER_IMAGE  = process.env.CODE_SERVER_IMAGE || 'codercom/code-server:latest';
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
    const result = await db.query(
        'SELECT provider, key_value FROM api_keys WHERE user_id = $1',
        [userId]
    );
    return result.rows
        .filter(r => r.key_value)
        .map(r => `${PROVIDER_ENV_MAP[r.provider] || r.provider.toUpperCase() + '_KEY'}=${r.key_value}`);
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

const createWorkspace = async (userId) => {
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
                const cmd = info.Config?.Cmd || [];
                const isUpToDate = cmd.some(c => c.includes('start-workspace'));

                if (isUpToDate) {
                    if (!info.State.Running) {
                        await c.start();
                        await db.query(
                            "UPDATE workspaces SET status = 'running' WHERE id = $1",
                            [ws.id]
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

    const port    = await getNextPort();
    const envVars = await getUserEnvVars(userId);
    const wsPath  = path.join(WORKSPACE_BASE, String(userId));

    fs.mkdirSync(wsPath, { recursive: true });
    await ensureImage(CODE_SERVER_IMAGE);

    const STARTUP_SCRIPT = process.env.WORKSPACE_STARTUP_SCRIPT || '/opt/gamadcode/start-workspace.sh';

    const container = await docker.createContainer({
        Image: CODE_SERVER_IMAGE,
        name:  `gamadcode-${userId}`,
        Cmd:   ['/usr/local/bin/start-workspace.sh'],
        Env:   envVars,
        ExposedPorts: { '8080/tcp': {} },
        HostConfig: {
            PortBindings:  { '8080/tcp': [{ HostPort: String(port) }] },
            Binds: [
                `${wsPath}:/home/coder/workspace`,
                `${STARTUP_SCRIPT}:/usr/local/bin/start-workspace.sh:ro`
            ],
            RestartPolicy: { Name: 'unless-stopped' }
        }
    });

    await container.start();

    const result = await db.query(
        `INSERT INTO workspaces (user_id, container_id, port, status)
         VALUES ($1, $2, $3, 'running') RETURNING *`,
        [userId, container.id, port]
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

    await db.query(
        "UPDATE workspaces SET status = 'stopped' WHERE id = $1",
        [ws.id]
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

    return ws;
};

module.exports = { createWorkspace, stopWorkspace, getWorkspaceStatus };
