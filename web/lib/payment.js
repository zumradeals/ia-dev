'use strict';
// ── GeniusPay — client de paiement ───────────────────────────────────────────
// Documentation : https://pay.genius.ci/docs/api
// Auth : headers X-API-Key + X-API-Secret sur chaque requête

const https  = require('https');
const crypto = require('crypto');

const GENIUS_BASE   = 'pay.genius.ci';
const GENIUS_PATH   = '/api/v1/merchant';
const API_KEY       = process.env.GENIUSPAY_API_KEY    || '';
const API_SECRET    = process.env.GENIUSPAY_API_SECRET || '';

// Prix et labels par défaut (utilisés si la DB n'est pas disponible)
const PLAN_PRICES = {
    pro:        9900,
    enterprise: 49000
};

const PLAN_LABELS = {
    pro:        'GamadCode Pro — 1 mois',
    enterprise: 'GamadCode Entreprise — 1 mois'
};

// ── HTTP helper ───────────────────────────────────────────────────────────────
const geniusRequest = (method, endpoint, body = null) => new Promise((resolve, reject) => {
    const data = body ? JSON.stringify(body) : null;
    const req  = https.request({
        hostname: GENIUS_BASE,
        path:     GENIUS_PATH + endpoint,
        method,
        headers: {
            'X-API-Key':    API_KEY,
            'X-API-Secret': API_SECRET,
            'Content-Type': 'application/json',
            ...(data ? { 'Content-Length': Buffer.byteLength(data) } : {})
        }
    }, (res) => {
        let d = '';
        res.on('data', c => d += c);
        res.on('end', () => {
            try { resolve({ status: res.statusCode, body: JSON.parse(d) }); }
            catch (e) { reject(new Error('Réponse GeniusPay invalide : ' + d.slice(0, 200))); }
        });
    });
    req.on('error', reject);
    if (data) req.write(data);
    req.end();
});

// ── Créer une session de checkout ─────────────────────────────────────────────
// Retourne { reference, checkout_url } — rediriger l'utilisateur vers checkout_url
const createCheckout = async ({ plan, amount, label, userId, userEmail, userName, successUrl, errorUrl }) => {
    if (!API_KEY || !API_SECRET) throw new Error('Clés GeniusPay non configurées (GENIUSPAY_API_KEY / GENIUSPAY_API_SECRET)');

    const finalAmount = amount || PLAN_PRICES[plan];
    const finalLabel  = label  || PLAN_LABELS[plan] || plan;

    if (!finalAmount || finalAmount < 200) throw new Error(`Montant invalide pour le plan ${plan} : ${finalAmount} XOF (minimum 200)`);

    const { status, body } = await geniusRequest('POST', '/payments', {
        amount:      finalAmount,
        currency:    'XOF',
        description: finalLabel,
        customer: {
            name:  userName  || userEmail,
            email: userEmail || ''
        },
        success_url: successUrl,
        error_url:   errorUrl,
        metadata: {
            user_id:  String(userId),
            plan,
            product:  'gamadcode_subscription'
        }
    });

    // GeniusPay peut retourner 200 ou 201 selon les versions
    if (!(status === 200 || status === 201) || !body.success) {
        const msg = body?.error?.message || body?.message || JSON.stringify(body).slice(0, 300);
        throw new Error('GeniusPay erreur ' + status + ' : ' + msg);
    }

    const data = body.data || body;
    const checkoutUrl = data.checkout_url || data.payment_url || data.redirect_url || data.url;
    if (!checkoutUrl) throw new Error('GeniusPay : URL de paiement introuvable dans la réponse — ' + JSON.stringify(data).slice(0, 200));

    return {
        reference:    data.reference || data.id || '',
        checkout_url: checkoutUrl
    };
};

// ── Récupérer le statut d'un paiement ────────────────────────────────────────
const getPayment = async (reference) => {
    const { status, body } = await geniusRequest('GET', '/payments/' + reference);
    if (status !== 200 || !body.success) throw new Error('Paiement introuvable : ' + reference);
    return body.data;
};

// ── Vérifier la signature d'un webhook ───────────────────────────────────────
// Format GeniusPay : HMAC-SHA256(timestamp + "." + json_payload, webhook_secret)
// Headers : X-Webhook-Signature, X-Webhook-Timestamp
const verifyWebhook = (rawBody, signature, timestamp) => {
    const secret = process.env.GENIUSPAY_WEBHOOK_SECRET || API_SECRET;
    if (!secret || !signature || !timestamp) return false;

    // Rejeter les webhooks de plus de 5 minutes (anti-replay)
    if (Math.abs(Date.now() / 1000 - parseInt(timestamp, 10)) > 300) return false;

    const expected = crypto
        .createHmac('sha256', secret)
        .update(timestamp + '.' + rawBody)
        .digest('hex');

    try {
        return crypto.timingSafeEqual(
            Buffer.from(signature, 'hex'),
            Buffer.from(expected,  'hex')
        );
    } catch { return false; }
};

module.exports = { createCheckout, getPayment, verifyWebhook, PLAN_PRICES, PLAN_LABELS };
