'use strict';
const fs   = require('fs');
const path = require('path');

const WORKSPACE_BASE = process.env.WORKSPACE_BASE || '/opt/gamadcode/users';

// Fichiers indicateurs lus pour l'analyse (tronqués à 4KB chacun)
const INDICATOR_FILES = [
    'package.json', 'package-lock.json',
    'requirements.txt', 'pyproject.toml', 'setup.py', 'Pipfile',
    'Cargo.toml', 'go.mod', 'pom.xml', 'build.gradle',
    'composer.json', 'Gemfile', 'mix.exs',
    'README.md', 'readme.md',
    'Dockerfile', 'docker-compose.yml',
    '.env.example',
];

const readTruncated = (filePath, maxBytes = 4096) => {
    try {
        const buf = Buffer.alloc(maxBytes);
        const fd  = fs.openSync(filePath, 'r');
        const read = fs.readSync(fd, buf, 0, maxBytes, 0);
        fs.closeSync(fd);
        return buf.slice(0, read).toString('utf8');
    } catch { return null; }
};

const collectContext = (repoPath) => {
    const files = {};
    for (const f of INDICATOR_FILES) {
        const content = readTruncated(path.join(repoPath, f));
        if (content) files[f] = content;
    }
    // Liste des fichiers racine
    try {
        files['__ls__'] = fs.readdirSync(repoPath)
            .filter(f => !f.startsWith('.'))
            .slice(0, 40)
            .join('\n');
    } catch {}
    return files;
};

// ── Détection heuristique (fallback sans API key) ────────────────────────────
const heuristicAnalysis = (files) => {
    if (files['package.json']) {
        try {
            const pkg = JSON.parse(files['package.json']);
            const deps = { ...pkg.dependencies, ...pkg.devDependencies };
            const fw = deps['next'] ? 'Next.js' : deps['react'] ? 'React' : deps['vue'] ? 'Vue.js' :
                       deps['svelte'] ? 'Svelte' : deps['express'] ? 'Express' : 'Node.js';
            const devScript = pkg.scripts?.dev || pkg.scripts?.start || 'npm start';
            const port = deps['next'] ? 3000 : deps['react'] || deps['vite'] ? 5173 : 3000;
            return {
                language: Object.keys(deps).some(d => d.includes('typescript') || d === 'ts-node') ? 'TypeScript' : 'JavaScript',
                framework: fw, install_commands: ['npm install'],
                dev_command: devScript.startsWith('npm') ? devScript : `npm run ${Object.keys(pkg.scripts||{})[0] || 'dev'}`,
                dev_port: port,
                extensions: ['esbenp.prettier-vscode', 'dbaeumer.vscode-eslint'],
                claude_md: generateClaudeMd(pkg.name || 'project', fw, 'npm install', devScript, port),
                source: 'heuristic',
            };
        } catch {}
    }
    if (files['requirements.txt'] || files['pyproject.toml'] || files['setup.py']) {
        const hasFastapi = (files['requirements.txt'] || '').includes('fastapi');
        const hasDjango  = (files['requirements.txt'] || '').includes('django');
        const fw = hasFastapi ? 'FastAPI' : hasDjango ? 'Django' : 'Python';
        const devCmd = hasFastapi ? 'uvicorn main:app --reload' : hasDjango ? 'python manage.py runserver' : 'python main.py';
        return {
            language: 'Python', framework: fw,
            install_commands: ['pip install -r requirements.txt'],
            dev_command: devCmd, dev_port: hasFastapi ? 8000 : 8000,
            extensions: ['ms-python.python'],
            claude_md: generateClaudeMd('project', fw, 'pip install -r requirements.txt', devCmd, 8000),
            source: 'heuristic',
        };
    }
    if (files['Cargo.toml']) {
        return {
            language: 'Rust', framework: 'Cargo',
            install_commands: ['cargo build'],
            dev_command: 'cargo run', dev_port: 8080,
            extensions: ['rust-lang.rust-analyzer'],
            claude_md: generateClaudeMd('project', 'Rust', 'cargo build', 'cargo run', 8080),
            source: 'heuristic',
        };
    }
    if (files['go.mod']) {
        return {
            language: 'Go', framework: 'Go modules',
            install_commands: ['go mod download'],
            dev_command: 'go run .', dev_port: 8080,
            extensions: ['golang.go'],
            claude_md: generateClaudeMd('project', 'Go', 'go mod download', 'go run .', 8080),
            source: 'heuristic',
        };
    }
    return {
        language: 'Unknown', framework: 'Unknown',
        install_commands: [], dev_command: '', dev_port: 3000,
        extensions: [], source: 'heuristic',
        claude_md: '# Project\n\nAucune configuration détectée automatiquement.\n',
    };
};

const generateClaudeMd = (name, framework, installCmd, devCmd, port) => `# ${name}

## Stack
${framework}

## Setup
\`\`\`bash
${installCmd}
\`\`\`

## Développement
\`\`\`bash
${devCmd}
\`\`\`

L'app tourne sur le port **${port}** — utilisez la Preview URL pour y accéder depuis le navigateur.

## Notes
- Ajoutez ici les conventions du projet, variables d'environnement, etc.
`;

// ── Analyse IA via Claude ────────────────────────────────────────────────────
const analyzeWithClaude = async (repoPath, repoName) => {
    const apiKey = process.env.ANTHROPIC_API_KEY;
    const files  = collectContext(repoPath);

    if (!apiKey) return heuristicAnalysis(files);

    const filesText = Object.entries(files)
        .map(([name, content]) => `### ${name}\n\`\`\`\n${content}\n\`\`\``)
        .join('\n\n');

    const prompt = `Tu es un assistant DevOps expert. Analyse ce dépôt GitHub nommé "${repoName}" et retourne un objet JSON (uniquement du JSON, aucun texte autour) avec cette structure exacte :

{
  "language": "langage principal (ex: TypeScript, Python, Rust, Go)",
  "framework": "framework principal (ex: Next.js, FastAPI, Express, Django)",
  "install_commands": ["commande1", "commande2"],
  "dev_command": "commande pour lancer le serveur de dev",
  "dev_port": 3000,
  "extensions": ["publisher.extensionId", ...],
  "summary": "1-2 phrases décrivant le projet",
  "claude_md": "contenu complet du fichier CLAUDE.md (markdown)"
}

Extensions disponibles : esbenp.prettier-vscode, dbaeumer.vscode-eslint, ms-python.python, rust-lang.rust-analyzer, golang.go, ms-vscode.vscode-typescript-next, bradlc.vscode-tailwindcss.

Pour claude_md, inclus : description courte, stack, commandes setup/dev, port, variables d'env si détectées.

Fichiers du dépôt :

${filesText}`;

    try {
        const Anthropic = require('@anthropic-ai/sdk');
        const client    = new Anthropic.default({ apiKey });
        const msg = await client.messages.create({
            model:      'claude-haiku-4-5-20251001',
            max_tokens: 1024,
            messages:   [{ role: 'user', content: prompt }],
        });

        const text = msg.content[0]?.text || '';
        // Extraire le JSON (peut être entouré de ```json ... ```)
        const jsonMatch = text.match(/```(?:json)?\s*([\s\S]*?)```/) || text.match(/(\{[\s\S]*\})/);
        const result = JSON.parse(jsonMatch ? jsonMatch[1] : text);
        return { ...result, source: 'claude' };
    } catch (e) {
        console.warn('[ai-onboarding] Claude API error, fallback heuristic:', e.message);
        return { ...heuristicAnalysis(files), source: 'heuristic' };
    }
};

// ── Appliquer l'onboarding dans le container ─────────────────────────────────
const { execFile } = require('child_process');
const execP = (cmd, args, opts = {}) => new Promise((resolve, reject) =>
    execFile(cmd, args, { timeout: 5 * 60_000, ...opts }, (err, stdout, stderr) =>
        err ? reject(Object.assign(err, { stderr, stdout })) : resolve({ stdout, stderr })
    )
);

const applyOnboarding = async (userId, repoName, analysis, containerId) => {
    const repoPath = path.join(WORKSPACE_BASE, String(userId), repoName);
    const logs     = [];

    // Écrire CLAUDE.md si absent
    const claudeMdPath = path.join(repoPath, 'CLAUDE.md');
    if (!fs.existsSync(claudeMdPath) && analysis.claude_md) {
        fs.writeFileSync(claudeMdPath, analysis.claude_md, 'utf8');
        logs.push('✓ CLAUDE.md créé');
    }

    // Exécuter les commandes d'installation dans le container
    for (const cmd of (analysis.install_commands || [])) {
        const parts   = cmd.split(' ');
        const cwd     = `/home/workspace/${repoName}`;
        try {
            await execP('docker', [
                'exec', '--workdir', cwd, containerId,
                'bash', '-c', `export PATH="$HOME/.npm-global/bin:/usr/local/bin:$PATH"; ${cmd}`,
            ]);
            logs.push(`✓ ${cmd}`);
        } catch (e) {
            logs.push(`✗ ${cmd} — ${e.stderr?.slice(0, 200) || e.message}`);
        }
    }

    return logs;
};

module.exports = { analyzeWithClaude, applyOnboarding, collectContext };
