'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const root = path.resolve(__dirname, '..', '..');
const quizDir = path.join(root, 'contenus', 'quiz');
const domains = ['vocabulaire', 'grammaire', 'expressions', 'comprehension', 'culture', 'synonymes', 'antonymes', 'francais_anglais'];
const levels = ['debutant', 'intermediaire', 'avance'];
const token = process.env.FIREBASE_TOKEN;
if (!token) throw new Error('FIREBASE_TOKEN requis pour protéger les réponses des banques.');

const files = fs.readdirSync(quizDir).filter((name) => name.endsWith('.json')).sort();
const answerMap = {};
let changed = false;
for (const name of files) {
  const match = name.match(/^(.+)_(debutant|intermediaire|avance)\.json$/);
  if (!match) continue;
  const domainIndex = domains.indexOf(match[1]);
  const levelIndex = levels.indexOf(match[2]);
  if (domainIndex < 0 || levelIndex < 0) continue;
  const file = path.join(quizDir, name);
  const bank = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (!Array.isArray(bank.questions)) continue;
  for (let i = 0; i < bank.questions.length; i++) {
    const question = bank.questions[i];
    const id = question.id || `q${domainIndex.toString(36)}${levelIndex.toString(36)}${i.toString(36)}`;
    if (question.id !== id) { question.id = id; changed = true; }
    if (Number.isInteger(question.r) && question.r >= 0 && question.r <= 3) {
      answerMap[id] = question.r;
      delete question.r;
      changed = true;
    }
    if ('e' in question) { delete question.e; changed = true; }
  }
  fs.writeFileSync(file, JSON.stringify(bank, null, 2) + '\n');
}
if (Object.keys(answerMap).length === 0) {
  console.log('Les banques ne contiennent plus de corrigés à migrer.');
  process.exit(0);
}
let previous = {};
try {
  const raw = execFileSync('firebase', ['functions:secrets:access', 'JANG_MATCH_ANSWER_BANK', '--project', 'jang-ea5f3', '--token', token], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  previous = JSON.parse(raw);
} catch (_) {}
Object.assign(previous, answerMap);
const payload = JSON.stringify(previous);
if (Buffer.byteLength(payload, 'utf8') > 64 * 1024) throw new Error('La banque privée dépasse la limite de taille d’un secret Firebase.');
const secretFile = path.join(process.env.RUNNER_TEMP || require('node:os').tmpdir(), 'jang-match-answer-bank.json');
fs.writeFileSync(secretFile, payload, { mode: 0o600 });
execFileSync('firebase', ['functions:secrets:set', 'JANG_MATCH_ANSWER_BANK', '--data-file', secretFile, '--project', 'jang-ea5f3', '--token', token], { stdio: 'inherit' });
fs.rmSync(secretFile, { force: true });
if (changed) {
  execFileSync('git', ['config', 'user.name', 'jang-bot']);
  execFileSync('git', ['config', 'user.email', 'jang-bot@users.noreply.github.com']);
  execFileSync('git', ['add', 'contenus/quiz']);
  execFileSync('git', ['commit', '-m', 'Protéger les corrigés des banques de matchs']);
  execFileSync('git', ['push']);
}
console.log(`Corrigés transférés dans Firebase et retirés de ${files.length} banques publiques.`);
