'use strict';
const jwt        = require('jsonwebtoken');
const nodemailer = require('nodemailer');
const db         = require('./db');

const JWT_SECRET     = process.env.SESSION_SECRET || 'changeme';
const MAGIC_LINK_TTL = 15 * 60 * 1000; // 15 min

const makeTransport = () => {
    if (process.env.SMTP_HOST) {
        return nodemailer.createTransport({
            host:   process.env.SMTP_HOST,
            port:   parseInt(process.env.SMTP_PORT || '587'),
            secure: process.env.SMTP_SECURE === 'true',
            auth:   { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS }
        });
    }
    // Sans SMTP configuré : log dans la console (mode dev/setup)
    return nodemailer.createTransport({ jsonTransport: true });
};

const sendMagicLink = async (email, baseUrl) => {
    email = email.toLowerCase().trim();

    // Upsert utilisateur
    let result = await db.query(
        `INSERT INTO users (email) VALUES ($1)
         ON CONFLICT (email) DO UPDATE SET email = EXCLUDED.email
         RETURNING id`,
        [email]
    );
    const userId = result.rows[0].id;

    // JWT 15 min
    const token = jwt.sign({ userId, email }, JWT_SECRET, { expiresIn: '15m' });

    await db.query(
        'INSERT INTO magic_links (user_id, token, expires_at) VALUES ($1, $2, $3)',
        [userId, token, new Date(Date.now() + MAGIC_LINK_TTL)]
    );

    const link = `${baseUrl}/auth/verify?token=${encodeURIComponent(token)}`;
    const transport = makeTransport();

    const info = await transport.sendMail({
        from:    process.env.SMTP_FROM || 'GamadCode <noreply@gamadcode.dev>',
        to:      email,
        subject: 'Votre lien de connexion GamadCode',
        html: `
<!DOCTYPE html>
<html>
<body style="font-family:sans-serif;background:#0f0f1a;color:#e2e8f0;margin:0;padding:40px 20px">
  <div style="max-width:480px;margin:0 auto;background:#1a1a2e;border-radius:16px;padding:40px;border:1px solid #2d2d4e">
    <div style="text-align:center;margin-bottom:32px">
      <span style="font-size:32px;font-weight:800;background:linear-gradient(135deg,#6366f1,#a855f7);-webkit-background-clip:text;-webkit-text-fill-color:transparent">GamadCode</span>
    </div>
    <h2 style="margin:0 0 16px;font-size:20px;font-weight:600">Connexion à votre espace</h2>
    <p style="color:#94a3b8;margin:0 0 28px;line-height:1.6">
      Cliquez sur le bouton ci-dessous pour vous connecter. Ce lien est valable <strong style="color:#e2e8f0">15 minutes</strong>.
    </p>
    <a href="${link}"
       style="display:block;text-align:center;background:linear-gradient(135deg,#6366f1,#a855f7);color:white;padding:14px 24px;border-radius:10px;text-decoration:none;font-size:16px;font-weight:600">
      Se connecter →
    </a>
    <p style="color:#475569;font-size:12px;margin-top:28px;text-align:center">
      Si vous n'avez pas demandé cette connexion, ignorez cet email.
    </p>
  </div>
</body>
</html>`
    });

    // Mode dev sans SMTP : affiche le lien dans les logs
    if (!process.env.SMTP_HOST) {
        const parsed = JSON.parse(info.message);
        console.log('[DEV] Magic link pour', email, '→', link);
    }

    return { userId };
};

const verifyMagicLink = async (token) => {
    let payload;
    try {
        payload = jwt.verify(token, JWT_SECRET);
    } catch {
        throw new Error('Token invalide ou expiré');
    }

    const result = await db.query(
        `SELECT id, user_id FROM magic_links
         WHERE token = $1 AND used_at IS NULL AND expires_at > NOW()`,
        [token]
    );

    if (result.rows.length === 0) {
        throw new Error('Lien de connexion invalide ou déjà utilisé');
    }

    await db.query(
        'UPDATE magic_links SET used_at = NOW() WHERE id = $1',
        [result.rows[0].id]
    );

    const userResult = await db.query(
        'SELECT id, email, name, is_admin FROM users WHERE id = $1',
        [payload.userId]
    );

    return userResult.rows[0];
};

module.exports = { sendMagicLink, verifyMagicLink };
