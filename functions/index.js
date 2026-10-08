const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue, Timestamp } = require('firebase-admin/firestore');
const { defineSecret } = require('firebase-functions/params');
const { randomInt } = require('node:crypto');

initializeApp();
const db = getFirestore();
const region = 'us-central1';
const maxPlayers = 40;
const matchAnswerBank = defineSecret('JANG_MATCH_ANSWER_BANK');

function privateAnswer(question) {
  const id = cleanText(question && question.id, 40);
  let bank;
  try { bank = JSON.parse(matchAnswerBank.value()); } catch (_) { bank = {}; }
  const answer = Number(bank[id]);
  if (!id || !Number.isInteger(answer) || answer < 0 || answer > 3) {
    throw new HttpsError('failed-precondition', 'Le corrigé de cette question n’est pas disponible.');
  }
  return answer;
}

function requireAuth(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Connecte-toi pour continuer.');
  return request.auth.uid;
}

function cleanText(value, max = 500) {
  return typeof value === 'string' ? value.trim().slice(0, max) : '';
}

exports.createMatch = onCall({ region, secrets: [matchAnswerBank] }, async (request) => {
  const uid = requireAuth(request);
  const data = request.data || {};
  const incoming = data.questions;
  if (!Array.isArray(incoming) || incoming.length < 1 || incoming.length > 200) {
    throw new HttpsError('invalid-argument', 'Le match doit contenir entre 1 et 200 questions.');
  }
  const publicQuestions = [];
  const answers = [];
  for (const item of incoming) {
    const q = cleanText(item && item.q, 1000);
    const options = Array.isArray(item && item.o) ? item.o.slice(0, 4).map((v) => cleanText(v, 500)) : [];
    if (!q || options.length !== 4 || options.some((v) => !v) || !cleanText(item && item.id, 40)) {
      throw new HttpsError('invalid-argument', 'Une question du match est invalide.');
    }
    publicQuestions.push({
      id: cleanText(item.id, 40),
      q,
      o: options,
      ...(cleanText(item.t, 3000) ? { t: cleanText(item.t, 3000) } : {}),
      ...(cleanText(item.d, 100) ? { d: cleanText(item.d, 100) } : {}),
      ...(cleanText(item.n, 100) ? { n: cleanText(item.n, 100) } : {}),
    });
    answers.push({ r: privateAnswer(item), e: '' });
  }

  const ref = db.collection('matchs').doc();
  let code = '';
  for (let attempt = 0; attempt < 10; attempt++) {
    const candidate = String(randomInt(0, 1000000)).padStart(6, '0');
    const found = await db.collection('matchs').where('code', '==', candidate).where('open', '==', true).limit(1).get();
    if (found.empty) { code = candidate; break; }
  }
  if (!code) throw new HttpsError('resource-exhausted', 'Impossible de créer un code maintenant. Réessaie.');

  const hostName = cleanText(data.hostName, 80) || cleanText(request.auth.token.name, 80) || 'Joueur';
  const hostPlays = data.hostPlays !== false;
  const match = {
    code, open: true, hostUid: uid, hostName, hostPlays,
    state: 'attente', index: -1, seconds: 20, questions: publicQuestions,
    revealedAnswers: {}, domaine: cleanText(data.domain, 100), niveau: cleanText(data.level, 100),
    title: cleanText(data.title, 120), tournamentId: cleanText(data.tournamentId, 120),
    classId: cleanText(data.classId, 120), itemId: cleanText(data.itemId, 120),
    createdAt: FieldValue.serverTimestamp(),
  };
  const batch = db.batch();
  batch.set(ref, match);
  batch.create(db.collection('matchAnswers').doc(ref.id), { answers });
  if (hostPlays) {
    batch.set(ref.collection('joueurs').doc(uid), {
      uid, name: hostName, score: 0, answeredIndices: [], reaction: '',
      at: FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
  return { id: ref.id, code };
});


exports.checkPracticeAnswer = onCall({ region, secrets: [matchAnswerBank] }, async (request) => {
  requireAuth(request);
  const id = cleanText(request.data && request.data.id, 40);
  if (!id) throw new HttpsError('invalid-argument', 'Question introuvable.');
  const bank = JSON.parse(matchAnswerBank.value());
  const answer = Number(bank[id]);
  if (!Number.isInteger(answer) || answer < 0 || answer > 3) {
    throw new HttpsError('not-found', 'Corrigé introuvable.');
  }
  return { answer };
});

exports.joinMatch = onCall({ region }, async (request) => {
  const uid = requireAuth(request);
  const matchId = cleanText(request.data && request.data.matchId, 120);
  const name = cleanText(request.data && request.data.name, 80) || 'Joueur';
  if (!matchId) throw new HttpsError('invalid-argument', 'Match introuvable.');
  const matchRef = db.collection('matchs').doc(matchId);
  const playerRef = matchRef.collection('joueurs').doc(uid);
  await db.runTransaction(async (tx) => {
    const [matchSnap, playerSnap, playersSnap] = await Promise.all([
      tx.get(matchRef), tx.get(playerRef), tx.get(matchRef.collection('joueurs')),
    ]);
    if (!matchSnap.exists) throw new HttpsError('not-found', 'Match introuvable.');
    const match = matchSnap.data();
    if (!match.open || match.state !== 'attente') throw new HttpsError('failed-precondition', 'Ce match a déjà commencé.');
    if (playerSnap.exists) return;
    if (playersSnap.size >= maxPlayers) throw new HttpsError('resource-exhausted', 'Ce match est plein.');
    tx.create(playerRef, { uid, name, score: 0, answeredIndices: [], reaction: '', at: FieldValue.serverTimestamp() });
  });
  return { id: matchId };
});

exports.submitMatchAnswer = onCall({ region }, async (request) => {
  const uid = requireAuth(request);
  const data = request.data || {};
  const matchId = cleanText(data.matchId, 120);
  const index = Number(data.index);
  const choice = Number(data.choice);
  if (!matchId || !Number.isInteger(index) || !Number.isInteger(choice) || choice < 0 || choice > 3) {
    throw new HttpsError('invalid-argument', 'Réponse invalide.');
  }
  const matchRef = db.collection('matchs').doc(matchId);
  const playerRef = matchRef.collection('joueurs').doc(uid);
  const privateRef = db.collection('matchAnswers').doc(matchId);
  return db.runTransaction(async (tx) => {
    const [matchSnap, playerSnap, keySnap, answerSnap] = await Promise.all([
      tx.get(matchRef), tx.get(playerRef), tx.get(privateRef),
      tx.get(playerRef.collection('reponses').doc(String(index))),
    ]);
    if (!matchSnap.exists || !playerSnap.exists || !keySnap.exists) throw new HttpsError('permission-denied', 'Tu ne participes pas à ce match.');
    const match = matchSnap.data();
    if (!match.open || match.state !== 'question' || match.index !== index) throw new HttpsError('failed-precondition', 'Le temps de réponse est terminé.');
    if (answerSnap.exists) throw new HttpsError('already-exists', 'Ta réponse a déjà été envoyée.');
    const askedAt = match.askedAt;
    if (!(askedAt instanceof Timestamp)) throw new HttpsError('failed-precondition', 'La question n’est pas encore lancée.');
    const elapsed = Math.max(0, Date.now() - askedAt.toMillis());
    const duration = Math.min(20, Math.max(1, Number(match.seconds) || 20)) * 1000;
    if (elapsed > duration) throw new HttpsError('deadline-exceeded', 'Le temps est écoulé.');
    const correctIndex = Number(keySnap.data().answers[index] && keySnap.data().answers[index].r);
    const ok = choice === correctIndex;
    const points = ok ? Math.round(20 * Math.max(0, duration - elapsed) / duration) : 0;
    tx.create(playerRef.collection('reponses').doc(String(index)), {
      choice, correct: ok, elapsedMs: elapsed, at: FieldValue.serverTimestamp(),
    });
    tx.update(playerRef, {
      answeredIndices: FieldValue.arrayUnion(index),
      score: FieldValue.increment(points),
    });
    return { points, correct: ok };
  });
});

exports.revealMatchQuestion = onCall({ region }, async (request) => {
  const uid = requireAuth(request);
  const matchId = cleanText(request.data && request.data.matchId, 120);
  if (!matchId) throw new HttpsError('invalid-argument', 'Match introuvable.');
  const matchRef = db.collection('matchs').doc(matchId);
  const keyRef = db.collection('matchAnswers').doc(matchId);
  await db.runTransaction(async (tx) => {
    const [matchSnap, keySnap, playersSnap] = await Promise.all([
      tx.get(matchRef), tx.get(keyRef), tx.get(matchRef.collection('joueurs')),
    ]);
    if (!matchSnap.exists || !keySnap.exists) throw new HttpsError('not-found', 'Match introuvable.');
    const match = matchSnap.data();
    if (match.hostUid !== uid) throw new HttpsError('permission-denied', 'Seul l’hôte peut montrer la réponse.');
    if (match.state !== 'question' || !Number.isInteger(match.index)) throw new HttpsError('failed-precondition', 'Aucune question à corriger.');
    const answer = keySnap.data().answers[match.index];
    if (!answer) throw new HttpsError('not-found', 'Corrigé introuvable.');
    const playerAnswers = await Promise.all(playersSnap.docs.map((player) =>
      tx.get(player.ref.collection('reponses').doc(String(match.index)))));
    tx.update(matchRef, {
      state: 'correction',
      ['revealedAnswers.' + match.index]: { r: answer.r, e: answer.e || '' },
    });
    for (let i = 0; i < playersSnap.docs.length; i++) {
      if (playerAnswers[i].exists && playerAnswers[i].data().correct === true) {
        tx.update(playersSnap.docs[i].ref, {
          correctIndices: FieldValue.arrayUnion(match.index),
        });
      }
    }
  });
  return { ok: true };
});

exports.advanceMatch = onCall({ region }, async (request) => {
  const uid = requireAuth(request);
  const matchId = cleanText(request.data && request.data.matchId, 120);
  if (!matchId) throw new HttpsError('invalid-argument', 'Match introuvable.');
  const matchRef = db.collection('matchs').doc(matchId);
  await db.runTransaction(async (tx) => {
    const [matchSnap, playersSnap] = await Promise.all([
      tx.get(matchRef), tx.get(matchRef.collection('joueurs')),
    ]);
    if (!matchSnap.exists) throw new HttpsError('not-found', 'Match introuvable.');
    const match = matchSnap.data();
    if (match.hostUid !== uid) throw new HttpsError('permission-denied', 'Seul l’hôte peut lancer le match.');
    if (!match.open) throw new HttpsError('failed-precondition', 'Ce match est terminé.');
    if (match.state === 'attente') {
      const minimum = match.hostPlays ? 2 : 1;
      if (playersSnap.size < minimum) throw new HttpsError('failed-precondition', 'Il faut plus de joueurs pour commencer.');
      tx.update(matchRef, { state: 'question', index: 0, askedAt: FieldValue.serverTimestamp() });
    } else if (match.state === 'correction') {
      const nextIndex = Number(match.index) + 1;
      if (nextIndex >= match.questions.length) {
        tx.update(matchRef, { state: 'fini', open: false });
      } else {
        tx.update(matchRef, { state: 'question', index: nextIndex, askedAt: FieldValue.serverTimestamp() });
      }
    } else {
      throw new HttpsError('failed-precondition', 'Attends la correction avant de passer à la suite.');
    }
  });
  return { ok: true };
});

exports.finishMatch = onCall({ region }, async (request) => {
  const uid = requireAuth(request);
  const matchId = cleanText(request.data && request.data.matchId, 120);
  if (!matchId) throw new HttpsError('invalid-argument', 'Match introuvable.');
  const ref = db.collection('matchs').doc(matchId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError('not-found', 'Match introuvable.');
    if (snap.data().hostUid !== uid) throw new HttpsError('permission-denied', 'Seul l’hôte peut terminer le match.');
    tx.update(ref, { state: 'fini', open: false });
  });
  return { ok: true };
});

exports.createTournament = onCall({ region, secrets: [matchAnswerBank] }, async (request) => {
  const uid = requireAuth(request);
  const data = request.data || {};
  const incoming = data.questions;
  if (!Array.isArray(incoming) || incoming.length < 1 || incoming.length > 200) {
    throw new HttpsError('invalid-argument', 'Le tournoi doit contenir des questions.');
  }
  const publicQuestions = [];
  const answers = [];
  for (const item of incoming) {
    const q = cleanText(item && item.q, 1000);
    const options = Array.isArray(item && item.o) ? item.o.slice(0, 4).map((v) => cleanText(v, 500)) : [];
    if (!q || options.length !== 4 || options.some((v) => !v) || !cleanText(item && item.id, 40)) {
      throw new HttpsError('invalid-argument', 'Une question du tournoi est invalide.');
    }
    publicQuestions.push({
      id: cleanText(item.id, 40),
      q, o: options,
      ...(cleanText(item.t, 3000) ? { t: cleanText(item.t, 3000) } : {}),
      ...(cleanText(item.d, 100) ? { d: cleanText(item.d, 100) } : {}),
      ...(cleanText(item.n, 100) ? { n: cleanText(item.n, 100) } : {}),
    });
    answers.push({ r: privateAnswer(item), e: '' });
  }
  const ref = db.collection('tournaments').doc();
  const hostName = cleanText(data.hostName, 80) || cleanText(request.auth.token.name, 80) || 'Organisateur';
  const title = cleanText(data.title, 120) || 'Tournoi de ' + hostName;
  const capacity = Math.min(16, Math.max(2, Number(data.capacity) || 16));
  const batch = db.batch();
  batch.set(ref, {
    title, hostUid: uid, hostName, status: 'waiting', round: 0, capacity,
    questions: publicQuestions, createdAt: FieldValue.serverTimestamp(),
  });
  batch.create(db.collection('tournamentAnswers').doc(ref.id), { answers });
  await batch.commit();
  return { id: ref.id };
});

exports.getTournamentQuestions = onCall({ region }, async (request) => {
  const uid = requireAuth(request);
  const tournamentId = cleanText(request.data && request.data.tournamentId, 120);
  if (!tournamentId) throw new HttpsError('invalid-argument', 'Tournoi introuvable.');
  const [tournamentSnap, answersSnap] = await Promise.all([
    db.collection('tournaments').doc(tournamentId).get(),
    db.collection('tournamentAnswers').doc(tournamentId).get(),
  ]);
  if (!tournamentSnap.exists || !answersSnap.exists) throw new HttpsError('not-found', 'Tournoi introuvable.');
  if (tournamentSnap.data().hostUid !== uid) {
    throw new HttpsError('permission-denied', 'Seul l’organisateur peut préparer les matchs.');
  }
  return { questions: tournamentSnap.data().questions };
});
