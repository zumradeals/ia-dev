'use strict';
const { execFile } = require('child_process');
const path  = require('path');
const fs    = require('fs');
const db    = require('./db');

const SNAPSHOTS_BASE = process.env.SNAPSHOTS_BASE || '/opt/gamadcode/snapshots';
const WORKSPACE_BASE = process.env.WORKSPACE_BASE || '/opt/gamadcode/users';

// Limites par plan (nb max de snapshots, -1 = illimité)
const PLAN_LIMITS = { free: 3, pro: 15, enterprise: -1 };

const execP = (cmd, args, opts = {}) => new Promise((resolve, reject) =>
    execFile(cmd, args, { ...opts, maxBuffer: 10 * 1024 * 1024 }, (err, stdout, stderr) =>
        err ? reject(Object.assign(err, { stderr })) : resolve(stdout)
    )
);

const sanitizeName = (name) =>
    (name || 'snapshot').replace(/[^a-zA-Z0-9_\- ]/g, '').trim().slice(0, 40) || 'snapshot';

const formatBytes = (b) => {
    if (b >= 1e9) return (b / 1e9).toFixed(1) + ' GB';
    if (b >= 1e6) return (b / 1e6).toFixed(0) + ' MB';
    return (b / 1024).toFixed(0) + ' KB';
};

// ── Créer un snapshot ────────────────────────────────────────────────────────
const create = async (userId, rawName) => {
    const name     = sanitizeName(rawName);
    const userPlan = await db.query('SELECT plan FROM users WHERE id = $1', [userId]);
    const plan     = userPlan.rows[0]?.plan || 'free';
    const limit    = PLAN_LIMITS[plan] ?? 3;

    if (limit !== -1) {
        const count = await db.query('SELECT COUNT(*) FROM snapshots WHERE user_id = $1', [userId]);
        if (parseInt(count.rows[0].count, 10) >= limit)
            throw new Error(`Limite atteinte (${limit} snapshots max sur le plan ${plan})`);
    }

    const wsPath  = path.join(WORKSPACE_BASE, String(userId));
    if (!fs.existsSync(wsPath)) throw new Error('Workspace introuvable');

    const userDir = path.join(SNAPSHOTS_BASE, String(userId));
    fs.mkdirSync(userDir, { recursive: true });

    const ts       = Date.now();
    const safeName = name.replace(/\s+/g, '_');
    const filename = `${ts}-${safeName}.tar.gz`;
    const filePath = path.join(userDir, filename);

    // tar avec exclusions (node_modules, venv, __pycache__, .git/objects)
    await execP('tar', [
        '-czf', filePath,
        '--exclude=node_modules',
        '--exclude=.venv',
        '--exclude=venv',
        '--exclude=__pycache__',
        '--exclude=.git/objects',
        '--exclude=*.pyc',
        '-C', wsPath,
        '.',
    ], { timeout: 5 * 60 * 1000 });

    const size = fs.statSync(filePath).size;

    const r = await db.query(
        `INSERT INTO snapshots (user_id, name, path, size_bytes)
         VALUES ($1, $2, $3, $4) RETURNING *`,
        [userId, name, filePath, size]
    );

    return { ...r.rows[0], sizeFormatted: formatBytes(size) };
};

// ── Lister les snapshots d'un utilisateur ────────────────────────────────────
const list = async (userId) => {
    const r = await db.query(
        'SELECT * FROM snapshots WHERE user_id = $1 ORDER BY created_at DESC',
        [userId]
    );
    return r.rows.map(s => ({ ...s, sizeFormatted: formatBytes(s.size_bytes || 0) }));
};

// ── Restaurer un snapshot ────────────────────────────────────────────────────
const restore = async (userId, snapshotId) => {
    const r = await db.query(
        'SELECT * FROM snapshots WHERE id = $1 AND user_id = $2',
        [snapshotId, userId]
    );
    if (!r.rows.length) throw new Error('Snapshot introuvable');

    const snap    = r.rows[0];
    const wsPath  = path.join(WORKSPACE_BASE, String(userId));

    if (!fs.existsSync(snap.path)) throw new Error('Fichier snapshot introuvable sur le disque');

    // S'assurer que le workspace container est arrêté avant restore
    const wsRow = await db.query("SELECT status FROM workspaces WHERE user_id = $1", [userId]);
    if (wsRow.rows[0]?.status === 'running')
        throw new Error('Arrêtez le workspace avant de restaurer un snapshot');

    fs.mkdirSync(wsPath, { recursive: true });

    // Vider le répertoire existant (sauf fichiers cachés système)
    await execP('find', [wsPath, '-mindepth', '1', '-maxdepth', '1',
        '!', '-name', '.gamad-setup-*',
        '!', '-name', '.gamad-template-applied',
        '-exec', 'rm', '-rf', '{}', '+',
    ], { timeout: 60 * 1000 }).catch(() => {});

    // Extraire le snapshot
    await execP('tar', ['-xzf', snap.path, '-C', wsPath], { timeout: 5 * 60 * 1000 });

    try { fs.chownSync(wsPath, 1000, 1000); } catch {}

    return snap;
};

// ── Supprimer un snapshot ────────────────────────────────────────────────────
const remove = async (userId, snapshotId) => {
    const r = await db.query(
        'DELETE FROM snapshots WHERE id = $1 AND user_id = $2 RETURNING path',
        [snapshotId, userId]
    );
    if (!r.rows.length) throw new Error('Snapshot introuvable');

    const filePath = r.rows[0].path;
    try { fs.unlinkSync(filePath); } catch { /* déjà supprimé */ }
    return { ok: true };
};

// ── Lister tous les snapshots (admin) ────────────────────────────────────────
const listAll = async () => {
    const r = await db.query(`
        SELECT s.*, u.email FROM snapshots s
        JOIN users u ON u.id = s.user_id
        ORDER BY s.created_at DESC`
    );
    return r.rows.map(s => ({ ...s, sizeFormatted: formatBytes(s.size_bytes || 0) }));
};

module.exports = { create, list, restore, remove, listAll, PLAN_LIMITS, formatBytes };
