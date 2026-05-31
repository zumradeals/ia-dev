'use strict';
const { execFile } = require('child_process');
const path = require('path');
const db   = require('./db');

const WORKSPACE_BASE  = process.env.WORKSPACE_BASE  || '/opt/gamadcode/users';
const SNAPSHOTS_BASE  = process.env.SNAPSHOTS_BASE  || '/opt/gamadcode/snapshots';

// Limites informatives par plan (heures/mois, -1 = illimité)
const PLAN_HOUR_LIMITS = { free: 50, pro: 300, enterprise: -1 };
const PLAN_SNAP_LIMITS = { free: 3,  pro: 15,  enterprise: -1 };

// Cache disk usage (5 min par userId)
const diskCache = new Map(); // userId → { bytes, ts }
const DISK_CACHE_TTL = 5 * 60 * 1000;

const execP = (cmd, args, opts = {}) => new Promise((resolve, reject) =>
    execFile(cmd, args, { timeout: 30_000, ...opts }, (err, stdout) =>
        err ? reject(err) : resolve(stdout.trim())
    )
);

const getDiskUsage = async (userId) => {
    const cached = diskCache.get(userId);
    if (cached && Date.now() - cached.ts < DISK_CACHE_TTL) return cached.bytes;

    const wsPath = path.join(WORKSPACE_BASE, String(userId));
    try {
        const out   = await execP('du', ['-sb', wsPath]);
        const bytes = parseInt(out.split('\t')[0], 10) || 0;
        diskCache.set(userId, { bytes, ts: Date.now() });
        return bytes;
    } catch {
        return 0;
    }
};

const formatBytes = (b) => {
    if (b >= 1e9) return (b / 1e9).toFixed(1) + ' GB';
    if (b >= 1e6) return (b / 1e6).toFixed(0) + ' MB';
    return (b / 1024).toFixed(0) + ' KB';
};

const formatDuration = (secs) => {
    const h = Math.floor(secs / 3600);
    const m = Math.floor((secs % 3600) / 60);
    if (h === 0) return `${m} min`;
    return m > 0 ? `${h}h ${m}min` : `${h}h`;
};

const getUserMetrics = async (userId) => {
    const curMonth = new Date().toISOString().slice(0, 7);

    const [wsRow, snapRow, diskBytes, user] = await Promise.all([
        db.query('SELECT * FROM workspaces WHERE user_id = $1', [userId]),
        db.query(`SELECT COUNT(*) AS count, COALESCE(SUM(size_bytes),0) AS total_size
                  FROM snapshots WHERE user_id = $1`, [userId]),
        getDiskUsage(userId),
        db.query('SELECT plan FROM users WHERE id = $1', [userId]),
    ]);

    const ws   = wsRow.rows[0] || null;
    const plan = user.rows[0]?.plan || 'free';

    // Heures ce mois
    let usedSecs = 0;
    if (ws) {
        const stored = (ws.usage_month === curMonth) ? (ws.usage_seconds_month || 0) : 0;
        const liveSecs = (ws.status === 'running' && ws.session_started_at)
            ? Math.floor((Date.now() - new Date(ws.session_started_at).getTime()) / 1000)
            : 0;
        usedSecs = stored + liveSecs;
    }

    const hourLimit  = PLAN_HOUR_LIMITS[plan] ?? 50;
    const snapLimit  = PLAN_SNAP_LIMITS[plan] ?? 3;
    const snapCount  = parseInt(snapRow.rows[0].count, 10);
    const snapSize   = parseInt(snapRow.rows[0].total_size, 10);

    return {
        month:          curMonth,
        plan,
        usedSeconds:    usedSecs,
        usedFormatted:  formatDuration(usedSecs),
        hourLimit,
        hourLimitLabel: hourLimit === -1 ? 'illimité' : `${hourLimit}h`,
        hourPct:        hourLimit === -1 ? 0 : Math.min(100, Math.round(usedSecs / (hourLimit * 3600) * 100)),
        disk: {
            bytes:     diskBytes,
            formatted: formatBytes(diskBytes),
        },
        snapshots: {
            count:       snapCount,
            limit:       snapLimit,
            limitLabel:  snapLimit === -1 ? 'illimité' : String(snapLimit),
            sizeBytes:   snapSize,
            sizeFormatted: formatBytes(snapSize),
            pct:         snapLimit === -1 ? 0 : Math.min(100, Math.round(snapCount / snapLimit * 100)),
        },
    };
};

// Vue admin : métriques agrégées par utilisateur
const getAllMetrics = async () => {
    const curMonth = new Date().toISOString().slice(0, 7);

    const rows = await db.query(`
        SELECT u.id, u.email, u.plan,
               w.status, w.session_started_at, w.usage_seconds_month, w.usage_month,
               COALESCE(s.snap_count, 0) AS snap_count,
               COALESCE(s.snap_size,  0) AS snap_size
        FROM users u
        LEFT JOIN workspaces w ON w.user_id = u.id
        LEFT JOIN (
            SELECT user_id, COUNT(*) AS snap_count, SUM(size_bytes) AS snap_size
            FROM snapshots GROUP BY user_id
        ) s ON s.user_id = u.id
        ORDER BY u.created_at DESC`
    );

    return Promise.all(rows.rows.map(async (r) => {
        const stored  = (r.usage_month === curMonth) ? (r.usage_seconds_month || 0) : 0;
        const live    = (r.status === 'running' && r.session_started_at)
            ? Math.floor((Date.now() - new Date(r.session_started_at).getTime()) / 1000) : 0;
        const usedSecs = stored + live;

        const diskBytes = await getDiskUsage(r.id).catch(() => 0);

        return {
            userId:         r.id,
            email:          r.email,
            plan:           r.plan || 'free',
            wsStatus:       r.status || 'none',
            usedSeconds:    usedSecs,
            usedFormatted:  formatDuration(usedSecs),
            diskFormatted:  formatBytes(diskBytes),
            diskBytes,
            snapCount:      parseInt(r.snap_count, 10),
            snapSizeFormatted: formatBytes(parseInt(r.snap_size, 10) || 0),
        };
    }));
};

module.exports = { getUserMetrics, getAllMetrics, formatBytes, formatDuration };
