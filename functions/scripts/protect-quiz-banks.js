'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const root = path.resolve(__dirname, '..', '..');
const quizDir = path.join(root, 'contenus', 'quiz');
const domains = ['vocabulaire', 'grammaire', 'expressions', 'comprehension', 'culture', 'synonymes', 'antonymes', 'francais_anglais', 'anglais_francais'];
const levels = ['debutant', 'intermediaire', 'avance'];
const token = process.env.FIREBASE_TOKEN;
if (!token) throw new Error('FIREBASE_TOKEN requis pour protéger les réponses des banques.');

function firebase(args, options = {}) {
  return execFileSync('firebase', [...args, '--project', 'jang-ea5f3', '--token', token], {
    encoding: 'utf8', stdio: options.stdio || ['ignore', 'pipe', 'ignore'],
  }).trim();
}
function secretName(domain, level) {
  return `JANG_MATCH_ANSWERS_${domain.toUpperCase()}_${level.toUpperCase()}`;
}
function readSecret(name) {
  try { return JSON.parse(firebase(['functions:secrets:access', name])); } catch (_) { return {}; }
}

const legacy = readSecret('JANG_MATCH_ANSWER_BANK');
let changed = false;
const answerBanks = new Map();
for (const domain of domains) {
  for (const level of levels) {
    const key = `${domain}_${level}`;
    const previous = readSecret(secretName(domain, level));
    const answers = { ...legacy, ...previous };
    const file = path.join(quizDir, `${key}.json`);
    if (!fs.existsSync(file) || fs.statSync(file).size === 0) {
      if (Object.keys(previous).length) answerBanks.set(key, previous);
      continue;
    }
    const bank = JSON.parse(fs.readFileSync(file, 'utf8'));
    if (!Array.isArray(bank.questions)) throw new Error(`Banque invalide : ${file}`);
    for (let i = 0; i < bank.questions.length; i++) {
      const question = bank.questions[i];
      const id = question.id || `q${domains.indexOf(domain).toString(36)}${levels.indexOf(level).toString(36)}${i.toString(36)}`;
      if (question.id !== id) { question.id = id; changed = true; }
      if (Number.isInteger(question.r) && question.r >= 0 && question.r <= 3) {
        answers[id] = question.r;
        delete question.r;
        changed = true;
      }
      if (!Object.prototype.hasOwnProperty.call(answers, id)) {
        throw new Error(`Corrigé absent pour ${key}/${id}. Les fichiers n'ont pas été publiés.`);
      }
      if ('e' in question) { delete question.e; changed = true; }
    }
    const localAnswers = {};
    for (const question of bank.questions) localAnswers[question.id] = answers[question.id];
    if (Buffer.byteLength(JSON.stringify(localAnswers), 'utf8') > 60000) {
      throw new Error(`La banque privée ${key} dépasse la limite sûre d'un secret Firebase.`);
    }
    answerBanks.set(key, localAnswers);
    if (changed) fs.writeFileSync(file, JSON.stringify(bank) + '\n');
  }
}

const secretFile = path.join(process.env.RUNNER_TEMP || require('node:os').tmpdir(), 'jang-match-answer-bank.json');
for (const [key, answers] of answerBanks) {
  fs.writeFileSync(secretFile, JSON.stringify(answers), { mode: 0o600 });
  const splitAt = key.lastIndexOf('_');
  const domain = key.slice(0, splitAt);
  const level = key.slice(splitAt + 1);
  firebase(['functions:secrets:set', secretName(domain, level), '--data-file', secretFile], { stdio: 'inherit' });
}
fs.rmSync(secretFile, { force: true });

if (changed) {
  execFileSync('git', ['config', 'user.name', 'jang-bot']);
  execFileSync('git', ['config', 'user.email', 'jang-bot@users.noreply.github.com']);
  execFileSync('git', ['add', 'contenus/quiz']);
  execFileSync('git', ['commit', '-m', 'Protéger les corrigés des banques de matchs']);
  execFileSync('git', ['push']);
}
console.log(`Corrigés répartis entre ${answerBanks.size} secrets Firebase. ${changed ? 'Les réponses ont été retirées des fichiers publics.' : 'Les banques sont déjà protégées.'}`);
