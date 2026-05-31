'use strict';
const bcrypt = require('bcryptjs');
const crypto = require('crypto');
const db     = require('./db');

const TOKEN_BYTES        = 32;
const VERIFY_TTL_HOURS   = 24;
const RESET_TTL_MINUTES  = 60;

const SALT_ROUNDS = 12;

// ── Captcha mathématique côté serveur ────────────────────────────────────────
// Stocké dans req.session.captcha — aucun service externe requis
const generateCaptcha = () => {
    const a   = Math.floor(Math.random() * 12) + 1;
    const b   = Math.floor(Math.random() * 12) + 1;
    const ops = ['+', '-', '×'];
    const op  = ops[Math.floor(Math.random() * ops.length)];
    let answer;
    if (op === '+') answer = a + b;
    else if (op === '-') return { question: `${a + b} - ${b}`, answer: a };
    else answer = a * b;
    return { question: `${a} ${op} ${b}`, answer };
};

// ── Inscription ───────────────────────────────────────────────────────────────
const register = async (email, password) => {
    email = email.toLowerCase().trim();

    const exists = await db.query('SELECT id FROM users WHERE email = $1', [email]);
    if (exists.rows.length > 0) throw new Error('Un compte existe déjà avec cet email');

    if (password.length < 8) throw new Error('Mot de passe trop court (8 caractères minimum)');

    const hash   = await bcrypt.hash(password, SALT_ROUNDS);
    const result = await db.query(
        'INSERT INTO users (email, password_hash) VALUES ($1, $2) RETURNING id, email, name, is_admin, created_at',
        [email, hash]
    );
    return result.rows[0];
};

// ── Connexion ─────────────────────────────────────────────────────────────────
const login = async (email, password) => {
    email = email.toLowerCase().trim();

    const result = await db.query(
        'SELECT id, email, name, is_admin, created_at, password_hash FROM users WHERE email = $1',
        [email]
    );

    if (result.rows.length === 0) {
        // Timing constant pour éviter l'énumération d'emails
        await bcrypt.compare(password, '$2a$12$invalidhashpaddingtoconstanttime0000000000000000000000');
        throw new Error('Email ou mot de passe incorrect');
    }

    const user  = result.rows[0];
    const valid = await bcrypt.compare(password, user.password_hash);
    if (!valid) throw new Error('Email ou mot de passe incorrect');

    const { password_hash, ...safeUser } = user;
    return safeUser;
};

// ── Vérification email ────────────────────────────────────────────────────────
const generateEmailToken = async (userId) => {
    const token = crypto.randomBytes(TOKEN_BYTES).toString('hex');
    await db.query('UPDATE users SET email_token = $1 WHERE id = $2', [token, userId]);
    return token;
};

const verifyEmailToken = async (token) => {
    if (!token || token.length !== TOKEN_BYTES * 2) throw new Error('Token invalide');
    const r = await db.query(
        'UPDATE users SET email_verified = true, email_token = NULL WHERE email_token = $1 RETURNING id, email',
        [token]
    );
    if (!r.rows.length) throw new Error('Lien invalide ou déjà utilisé');
    return r.rows[0];
};

// ── Reset mot de passe ────────────────────────────────────────────────────────
const generateResetToken = async (email) => {
    email = email.toLowerCase().trim();
    const r = await db.query('SELECT id FROM users WHERE email = $1', [email]);
    if (!r.rows.length) return null; // silencieux — ne pas révéler si l'email existe
    const token   = crypto.randomBytes(TOKEN_BYTES).toString('hex');
    const expires = new Date(Date.now() + RESET_TTL_MINUTES * 60 * 1000);
    await db.query(
        'UPDATE users SET reset_token = $1, reset_expires = $2 WHERE id = $3',
        [token, expires, r.rows[0].id]
    );
    return { token, userId: r.rows[0].id };
};

const validateResetToken = async (token) => {
    if (!token || token.length !== TOKEN_BYTES * 2) throw new Error('Token invalide');
    const r = await db.query(
        'SELECT id, email FROM users WHERE reset_token = $1 AND reset_expires > NOW()',
        [token]
    );
    if (!r.rows.length) throw new Error('Lien invalide ou expiré');
    return r.rows[0];
};

const resetPassword = async (token, newPassword) => {
    if (!newPassword || newPassword.length < 8) throw new Error('Mot de passe trop court (8 caractères minimum)');
    const user = await validateResetToken(token);
    const hash = await bcrypt.hash(newPassword, SALT_ROUNDS);
    await db.query(
        'UPDATE users SET password_hash = $1, reset_token = NULL, reset_expires = NULL WHERE id = $2',
        [hash, user.id]
    );
    return user;
};

module.exports = { register, login, generateCaptcha, generateEmailToken, verifyEmailToken, generateResetToken, validateResetToken, resetPassword };
