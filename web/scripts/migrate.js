#!/usr/bin/env node
'use strict';

const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../../config/secrets.env') });
require('dotenv').config({ path: path.join(__dirname, '../../config/local.env'), override: false });

const fs = require('fs');
const db = require('../lib/db');

async function migrate() {
    const sqlFile = path.join(__dirname, '../migrations/001_init.sql');
    const sql     = fs.readFileSync(sqlFile, 'utf8');

    console.log('[migrate] Connexion PostgreSQL...');
    try {
        await db.query(sql);
        console.log('[migrate] Migration 001_init.sql appliquée avec succès');
    } catch (e) {
        console.error('[migrate] Erreur :', e.message);
        process.exit(1);
    } finally {
        await db.end();
    }
}

migrate();
