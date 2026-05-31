'use strict';
const nodemailer = require('nodemailer');

const createTransport = () => {
    const host = process.env.SMTP_HOST;
    if (!host) return null;
    const port   = parseInt(process.env.SMTP_PORT || '587', 10);
    const secure = port === 465;
    return nodemailer.createTransport({
        host,
        port,
        secure,
        auth: process.env.SMTP_USER
            ? { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS || '' }
            : undefined,
        tls: { rejectUnauthorized: false },
    });
};

const send = async ({ to, subject, html, text }) => {
    const transport = createTransport();
    if (!transport) throw new Error('SMTP non configuré (SMTP_HOST manquant)');
    const uiDomain = process.env.GAMADCODE_UI_DOMAIN || process.env.GAMADCODE_DOMAIN || 'localhost';
    const from = process.env.SMTP_FROM || `GamadCode <noreply@${uiDomain}>`;
    await transport.sendMail({ from, to, subject, html, text });
};

const verify = async () => {
    const transport = createTransport();
    if (!transport) throw new Error('SMTP non configuré');
    await transport.verify();
};

module.exports = { send, verify, createTransport };
