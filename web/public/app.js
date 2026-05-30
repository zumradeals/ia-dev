// GamadCode — shared client utilities

const API = {
    async get(path) {
        const r = await fetch(path);
        if (!r.ok) throw new Error(await r.text());
        return r.json();
    },
    async post(path, body) {
        const r = await fetch(path, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body)
        });
        if (!r.ok) throw new Error(await r.text());
        return r.json();
    }
};

function fmt(bytes) {
    if (bytes > 1e9) return (bytes / 1e9).toFixed(1) + ' GB';
    if (bytes > 1e6) return (bytes / 1e6).toFixed(0) + ' MB';
    return (bytes / 1e3).toFixed(0) + ' KB';
}

function pctColor(pct) {
    if (pct > 85) return 'danger';
    if (pct > 65) return 'warn';
    return '';
}

function renderProgress(el, pct) {
    el.style.width = pct + '%';
    el.className = 'progress-bar ' + pctColor(pct);
}

async function loadUser(cb) {
    try {
        const me = await API.get('/api/me');
        if (cb) cb(me);
        return me;
    } catch { return null; }
}

function renderSidebar(activePage) {
    const user = window._user;
    const avatar = user?.avatar ? `<img src="${user.avatar}" alt="">` : `<div style="width:32px;height:32px;border-radius:50%;background:var(--bg3);border:1px solid var(--border)"></div>`;
    const name   = user?.name || user?.login || 'root';
    const role   = user?.isAdmin ? 'Admin' : 'Membre';

    const pages = [
        { id: 'dashboard', href: '/dashboard', label: 'Dashboard', icon: '<path d="M3 13h8V3H3v10zm0 8h8v-6H3v6zm10 0h8V11h-8v10zm0-18v6h8V3h-8z"/>' },
        { id: 'modules',   href: '/modules',   label: 'Modules',   icon: '<path d="M20 6h-2.18c.07-.44.18-.88.18-1.36C18 2.53 15.54 1 12.87 1c-1.4 0-2.71.46-3.78 1.34L12 5.17l2.91-2.83C15.56 2.12 16.2 2 16.87 2c1.52 0 2.13.94 2.13 1.64 0 .44-.24.87-.64 1.36H10c-3.31 0-6 2.69-6 6v1h16v-1c0-1.48-.65-2.8-1.68-3.71l1.42-1.38C21.29 7.49 22 8.96 22 10.64V17c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2v-6.36C2 8.69 4.69 6 8 6h12z"/>' },
        { id: 'logs',      href: '/logs',      label: 'Logs live',  icon: '<path d="M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm-2 12H6v-2h12v2zm0-3H6V9h12v2zm0-3H6V6h12v2z"/>' },
    ];

    const nav = pages.map(p => `
        <a class="nav-item ${activePage === p.id ? 'active' : ''}" href="${p.href}">
          <svg viewBox="0 0 24 24" fill="var(--muted)" style="fill:currentColor"><g>${p.icon}</g></svg>
          ${p.label}
        </a>`).join('');

    document.getElementById('sidebar').innerHTML = `
        <div class="sidebar-logo">
          <h2>GamadCode</h2>
          <small>Laboratoire IA</small>
        </div>
        <nav class="sidebar-nav">${nav}</nav>
        <div class="sidebar-user">
          ${avatar}
          <div class="user-info">
            <div class="user-name">${name}</div>
            <div class="user-role">${role}</div>
          </div>
          <a href="/auth/logout" title="Déconnexion">⏏</a>
        </div>`;
}

window.API = API;
window.fmt = fmt;
window.pctColor = pctColor;
window.renderProgress = renderProgress;
window.loadUser = loadUser;
window.renderSidebar = renderSidebar;
