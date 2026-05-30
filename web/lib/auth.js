'use strict';
const bcrypt = require('bcryptjs');
const crypto = require('crypto');
const db     = require('./db');

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

module.exports = { register, login, generateCaptcha };
