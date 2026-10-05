// Jàng : petit serveur gratuit (Cloudflare Worker) pour les notifications push
// et la suppression des comptes. Il garde la clé secrète de Firebase : l'app ne la voit jamais.
//
// Routes (appelées par l'app admin, avec le jeton de connexion Firebase de l'utilisateur) :
//   POST /send         { type: "annonce", topic, title, body, id }   annonce à un groupe
//                      { type: "message", uids: [...], title, body }  message à des élèves
//   POST /delete-user  { uid }                                         supprimer un compte (admin)
// Tâche planifiée (toutes les 5 minutes) : envoie les annonces programmées et les
// notifications retenues pendant la nuit (21 h – 7 h, heure de Dakar).

const NIGHT_START = 21;
const NIGHT_END = 7;

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return new Response(null, { headers: cors() });
    if (request.method !== "POST") return json({ ok: true, service: "jang-push" });
    try {
      const url = new URL(request.url);
      const idToken = (request.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
      const uid = await verifyUser(env, idToken);
      if (!uid) return json({ error: "connexion refusée" }, 401);
      const me = await getDoc(env, `users/${uid}`);
      const role = me?.role;
      if (role !== "admin" && role !== "prof") return json({ error: "réservé aux profs" }, 403);
      const body = await request.json();

      if (url.pathname === "/delete-user") {
        if (role !== "admin") return json({ error: "réservé à l'admin" }, 403);
        await deleteAuthUser(env, String(body.uid || ""));
        return json({ ok: true });
      }

      if (url.pathname === "/send") {
        const title = String(body.title || "Jàng").slice(0, 120);
        const text = String(body.body || "").slice(0, 400);
        if (body.type === "annonce") {
          const topic = String(body.topic || "");
          if (!/^[a-zA-Z0-9_.~%-]+$/.test(topic)) return json({ error: "sujet invalide" }, 400);
          if (role === "prof" && !profMayAnnounce(me, topic)) return json({ error: "hors de tes matières" }, 403);
          if (isNight()) return json({ ok: false, later: true }, 202); // la tâche planifiée l'enverra à 7 h
          await sendFcm(env, { topic }, title, text, { kind: "annonce", id: String(body.id || "") });
          return json({ ok: true });
        }
        if (body.type === "message") {
          const uids = Array.isArray(body.uids) ? body.uids.slice(0, 500).map(String) : [];
          if (isNight()) {
            for (const u of uids) await addDoc(env, "pushQueue", { uid: u, title, body: text });
            return json({ ok: false, later: true }, 202);
          }
          for (const u of uids) await sendToUser(env, u, title, text);
          return json({ ok: true, count: uids.length });
        }
        return json({ error: "type inconnu" }, 400);
      }
      return json({ error: "route inconnue" }, 404);
    } catch (e) {
      return json({ error: String(e && e.message ? e.message : e) }, 500);
    }
  },

  async scheduled(event, env, ctx) {
    ctx.waitUntil(flush(env));
  },
};

// ---------- Règles ----------

function isNight(d = new Date()) {
  const h = d.getUTCHours(); // heure de Dakar = UTC
  return h >= NIGHT_START || h < NIGHT_END;
}

// Un prof n'annonce que dans ses matières : sujets « mat_<matière> » ou « mat_<matière>_<niveau> ».
function profMayAnnounce(me, topic) {
  const subjects = me.profSubjects || [];
  const levels = me.profExams || [];
  for (const s of subjects) {
    if (topic === `mat_${s}` && levels.length === 0) return true;
    if (topic.startsWith(`mat_${s}_`)) {
      const level = topic.slice(`mat_${s}_`.length);
      if (levels.length === 0 || levels.includes(level)) return true;
    }
  }
  return false;
}

// ---------- Tâche planifiée ----------

async function flush(env) {
  if (isNight()) return;
  // 1. Annonces programmées (ou retenues la nuit) pas encore envoyées.
  const now = new Date().toISOString();
  const due = await runQuery(env, {
    from: [{ collectionId: "annonces" }],
    where: {
      compositeFilter: {
        op: "AND",
        filters: [
          { fieldFilter: { field: { fieldPath: "pushed" }, op: "EQUAL", value: { booleanValue: false } } },
          { fieldFilter: { field: { fieldPath: "sendAt" }, op: "LESS_THAN_OR_EQUAL", value: { timestampValue: now } } },
        ],
      },
    },
    limit: 20,
  });
  for (const { name, data } of due) {
    const topic = topicFor(data.examId || "", data.subject || "");
    await sendFcm(env, { topic }, data.title || "Jàng", data.text || "", { kind: "annonce", id: name.split("/").pop() });
    await patchDoc(env, name, { pushed: true });
  }
  // 2. Messages retenus pendant la nuit.
  const queued = await runQuery(env, { from: [{ collectionId: "pushQueue" }], limit: 100 });
  for (const { name, data } of queued) {
    await sendToUser(env, data.uid, data.title, data.body);
    await deleteDoc(env, name);
  }
}

function topicFor(examId, subject) {
  const clean = (s) => s.replace(/[^a-zA-Z0-9_.~%-]/g, "_");
  if (!examId && !subject) return "tous";
  if (!subject) return clean(`niveau_${examId}`);
  if (!examId) return clean(`mat_${subject}`);
  return clean(`mat_${subject}_${examId}`);
}

// ---------- Firebase Cloud Messaging ----------

async function sendToUser(env, uid, title, body) {
  const user = await getDoc(env, `users/${uid}`);
  const token = user?.fcmToken;
  if (!token) return;
  await sendFcm(env, { token }, title, body, { kind: "message" });
}

async function sendFcm(env, target, title, body, data) {
  const access = await accessToken(env);
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/messages:send`, {
    method: "POST",
    headers: { Authorization: `Bearer ${access}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      message: {
        ...target,
        notification: { title, body },
        data: Object.fromEntries(Object.entries(data || {}).map(([k, v]) => [k, String(v)])),
        android: { priority: "HIGH", notification: { channel_id: "messages" } },
      },
    }),
  });
  if (!res.ok && res.status !== 404) throw new Error(`FCM ${res.status}: ${await res.text()}`);
}

// ---------- Comptes ----------

// Vérifie le jeton de connexion de l'utilisateur auprès de Firebase. Renvoie son uid.
async function verifyUser(env, idToken) {
  if (!idToken) return null;
  const res = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${env.FIREBASE_API_KEY}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ idToken }),
  });
  if (!res.ok) return null;
  const j = await res.json();
  return j.users && j.users[0] ? j.users[0].localId : null;
}

async function deleteAuthUser(env, uid) {
  if (!uid) throw new Error("uid manquant");
  const access = await accessToken(env);
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/accounts:delete`,
    {
      method: "POST",
      headers: { Authorization: `Bearer ${access}`, "Content-Type": "application/json" },
      body: JSON.stringify({ localId: uid }),
    },
  );
  if (!res.ok) throw new Error(`suppression ${res.status}: ${await res.text()}`);
}

// ---------- Firestore (API REST) ----------

const base = (env) => `https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents`;

async function getDoc(env, path) {
  const access = await accessToken(env);
  const res = await fetch(`${base(env)}/${path}`, { headers: { Authorization: `Bearer ${access}` } });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`Firestore ${res.status}`);
  return decode((await res.json()).fields || {});
}

async function addDoc(env, collection, data) {
  const access = await accessToken(env);
  await fetch(`${base(env)}/${collection}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${access}`, "Content-Type": "application/json" },
    body: JSON.stringify({ fields: encode(data) }),
  });
}

async function patchDoc(env, name, data) {
  const access = await accessToken(env);
  const mask = Object.keys(data).map((k) => `updateMask.fieldPaths=${k}`).join("&");
  await fetch(`https://firestore.googleapis.com/v1/${name}?${mask}`, {
    method: "PATCH",
    headers: { Authorization: `Bearer ${access}`, "Content-Type": "application/json" },
    body: JSON.stringify({ fields: encode(data) }),
  });
}

async function deleteDoc(env, name) {
  const access = await accessToken(env);
  await fetch(`https://firestore.googleapis.com/v1/${name}`, {
    method: "DELETE",
    headers: { Authorization: `Bearer ${access}` },
  });
}

async function runQuery(env, structuredQuery) {
  const access = await accessToken(env);
  const res = await fetch(`${base(env)}:runQuery`, {
    method: "POST",
    headers: { Authorization: `Bearer ${access}`, "Content-Type": "application/json" },
    body: JSON.stringify({ structuredQuery }),
  });
  if (!res.ok) throw new Error(`Firestore ${res.status}: ${await res.text()}`);
  const rows = await res.json();
  return rows.filter((r) => r.document).map((r) => ({ name: r.document.name, data: decode(r.document.fields || {}) }));
}

function decode(fields) {
  const out = {};
  for (const [k, v] of Object.entries(fields)) out[k] = value(v);
  return out;
}

function value(v) {
  if ("stringValue" in v) return v.stringValue;
  if ("booleanValue" in v) return v.booleanValue;
  if ("integerValue" in v) return Number(v.integerValue);
  if ("doubleValue" in v) return v.doubleValue;
  if ("timestampValue" in v) return v.timestampValue;
  if ("nullValue" in v) return null;
  if ("arrayValue" in v) return (v.arrayValue.values || []).map(value);
  if ("mapValue" in v) return decode(v.mapValue.fields || {});
  return null;
}

function encode(data) {
  const out = {};
  for (const [k, v] of Object.entries(data)) {
    if (typeof v === "boolean") out[k] = { booleanValue: v };
    else if (typeof v === "number") out[k] = { integerValue: String(Math.round(v)) };
    else out[k] = { stringValue: String(v ?? "") };
  }
  return out;
}

// ---------- Jeton d'accès Google (compte de service) ----------

let cached = { token: "", exp: 0 };

async function accessToken(env) {
  const now = Math.floor(Date.now() / 1000);
  if (cached.token && cached.exp - 60 > now) return cached.token;
  const sa = JSON.parse(env.SERVICE_ACCOUNT);
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(claims))}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToBuffer(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned));
  const jwt = `${unsigned}.${b64url(sig)}`;
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${jwt}`,
  });
  const j = await res.json();
  if (!j.access_token) throw new Error("jeton Google refusé");
  cached = { token: j.access_token, exp: now + (j.expires_in || 3600) };
  return cached.token;
}

function pemToBuffer(pem) {
  const b64 = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const bin = atob(b64);
  const buf = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
  return buf.buffer;
}

function b64url(input) {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : new Uint8Array(input);
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// ---------- Réponses ----------

function cors() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Authorization, Content-Type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...cors() },
  });
}
