'use strict';
const { Pool } = require('pg');

const pool = new Pool({
    host:     process.env.POSTGRES_HOST     || 'localhost',
    port:     parseInt(process.env.POSTGRES_PORT || '5432'),
    database: process.env.POSTGRES_DB       || 'gamadcode',
    user:     process.env.POSTGRES_USER     || 'gamadcode',
    password: process.env.POSTGRES_PASSWORD || ''
});

pool.on('error', (err) => console.error('[db] pool error:', err.message));

module.exports = pool;
