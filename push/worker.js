/* Fokus push-server — Cloudflare Worker.
 *
 * Uppgift: knacka på telefonen när ett pass tar slut. iOS väcker inte en
 * webbapp på schemalagd tid; utan det här kommer larmet aldrig fram med
 * släckt skärm.
 *
 * Nyttolasten krypteras enligt RFC 8291 (ECDH + HKDF + AES-128-GCM). Det var
 * frestande att skicka en tom push och läsa texten ur telefonens cache, men
 * att Apples tjänst accepterar nyttolastfria pushar är ett antagande — och
 * cachen kan dessutom raderas av en service worker-uppdatering. Krypterad
 * nyttolast tar bort båda riskerna.
 *
 * Vad servern får veta: en anonym push-adress, en tidsstämpel, och den text
 * som ska visas. Inte vem du är, inte dina uppgifter, inte din statistik.
 */

const ALLOWED_ORIGIN = 'https://niclasnn.github.io';

/* Bara riktiga push-tjänster. Utan den här listan är servern en öppen relä:
   vem som helst kunde be den POSTa mot godtycklig värd, upp till fem timmar
   fördröjt, från Cloudflares IP-adresser. */
const PUSH_HOST = /^(([a-z0-9-]+\.)?push\.apple\.com|fcm\.googleapis\.com|updates\.push\.services\.mozilla\.com|[a-z0-9-]+\.notify\.windows\.com)$/;

const CORS = {
  'Access-Control-Allow-Origin': ALLOWED_ORIGIN,
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Access-Control-Max-Age': '86400',
};

const json = (o, status = 200) => new Response(JSON.stringify(o), {
  status, headers: { ...CORS, 'Content-Type': 'application/json' },
});
const bad = msg => json({ error: msg }, 400);

function validEndpoint(ep) {
  if (typeof ep !== 'string' || ep.length > 800) return false;
  let u; try { u = new URL(ep); } catch { return false; }
  return u.protocol === 'https:' && PUSH_HOST.test(u.hostname);
}

export default {
  async fetch(req, env) {
    if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
    const url = new URL(req.url);
    if (url.pathname !== '/schedule' && url.pathname !== '/cancel') {
      return new Response('Fokus push', { headers: CORS });
    }
    if (req.method !== 'POST') return bad('POST krävs');

    let body;
    try { body = await req.json(); } catch { return bad('trasig json'); }

    const sub = body?.subscription;
    if (!validEndpoint(sub?.endpoint)) return bad('ogiltig endpoint');
    if (typeof sub?.keys?.auth !== 'string' || typeof sub?.keys?.p256dh !== 'string') {
      return bad('saknar nycklar');
    }

    // Ett Durable Object per prenumeration. Id:t härleds ur endpointen, så
    // samma telefon landar alltid i samma objekt.
    const id = env.ALARM.idFromName(await sha256b64(sub.endpoint));
    return env.ALARM.get(id).fetch(new Request(url.origin + url.pathname, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    }));
  },
};

export class Alarm {
  constructor(state, env) { this.state = state; this.env = env; }

  async fetch(req) {
    const url = new URL(req.url);
    const body = await req.json();
    const sub  = body.subscription;

    /* keys.auth är en 16-byte-hemlighet webbläsaren genererar och som INTE
       ingår i endpoint-URL:en. Den duger som ägarbevis: utan den kan ingen
       styra eller avboka någon annans larm. */
    const known = await this.state.storage.get('auth');
    if (known && known !== sub.keys.auth) return json({ error: 'fel ägare' }, 403);

    /* Paus och start kan hinna gå om varandra. En monoton sekvens gör att ett
       gammalt /cancel inte raderar ett nyss satt alarm. */
    const seq  = Number(body.seq) || 0;
    const last = (await this.state.storage.get('seq')) || 0;
    if (seq && seq < last) return json({ ok: true, ignored: true });
    if (seq) await this.state.storage.put('seq', seq);

    if (url.pathname === '/cancel') {
      await this.state.storage.deleteAlarm();
      await this.state.storage.deleteAll();
      return json({ ok: true, cancelled: true });
    }

    if (await this.state.storage.get('dead')) return json({ gone: true });

    const endsAt = Number(body.endsAt);
    if (!Number.isFinite(endsAt)) return bad('endsAt saknas');
    const om = endsAt - Date.now();
    if (om < 0 || om > 5 * 60 * 60 * 1000) return bad('endsAt utanför rimligt spann');

    await this.state.storage.put('sub', sub);
    await this.state.storage.put('auth', sub.keys.auth);
    await this.state.storage.put('text', {
      title: String(body.title || 'Passet är klart 🎉').slice(0, 120),
      body:  String(body.body  || '').slice(0, 200),
    });
    await this.state.storage.setAlarm(endsAt);
    return json({ ok: true, om: Math.round(om / 1000) });
  }

  async alarm() {
    const sub  = await this.state.storage.get('sub');
    const text = (await this.state.storage.get('text')) || { title: 'Passet är klart 🎉', body: '' };
    if (!sub) return;

    let status;
    try {
      status = await sendPush(sub, text, this.env);
    } catch (e) {
      // Nätverksfel: låt Durable Objects försöka igen i stället för att
      // svälja det. Storage är kvar, så nästa försök har allt det behöver.
      console.log('push-fel', e?.message ?? 'okänt');
      throw e;
    }

    if (status === 404 || status === 410) {
      // Prenumerationen finns inte längre. Märk den död så appen kan skapa
      // en ny i stället för att larmet tyst slutar fungera.
      await this.state.storage.deleteAll();
      await this.state.storage.put('dead', true);
      return;
    }
    if (status >= 500 || status === 429) throw new Error(`push ${status}`);  // låt DO försöka igen
    await this.state.storage.deleteAll();   // först efter lyckad sändning
  }
}

/* ── kryptografi ─────────────────────────────────────────────────── */

const enc = new TextEncoder();
const b64u = buf => btoa(String.fromCharCode(...new Uint8Array(buf)))
  .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const unb64u = s => {
  const b = atob(s.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(s.length / 4) * 4, '='));
  return Uint8Array.from(b, c => c.charCodeAt(0));
};
async function sha256b64(s) { return b64u(await crypto.subtle.digest('SHA-256', enc.encode(s))); }

const concat = (...a) => {
  const out = new Uint8Array(a.reduce((n, x) => n + x.length, 0));
  let o = 0; for (const x of a) { out.set(x, o); o += x.length; }
  return out;
};

async function hkdf(salt, ikm, info, len) {
  const key = await crypto.subtle.importKey('raw', ikm, 'HKDF', false, ['deriveBits']);
  return new Uint8Array(await crypto.subtle.deriveBits(
    { name: 'HKDF', hash: 'SHA-256', salt, info }, key, len * 8));
}

/* RFC 8291 §3.4 — aes128gcm */
async function encryptPayload(plaintext, p256dhB64, authB64) {
  const uaPublic = unb64u(p256dhB64);
  const authSecret = unb64u(authB64);

  const eph = await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits']);
  const asPublic = new Uint8Array(await crypto.subtle.exportKey('raw', eph.publicKey));
  const uaKey = await crypto.subtle.importKey('raw', uaPublic, { name: 'ECDH', namedCurve: 'P-256' }, false, []);
  const shared = new Uint8Array(await crypto.subtle.deriveBits({ name: 'ECDH', public: uaKey }, eph.privateKey, 256));

  const ikm = await hkdf(authSecret, shared,
    concat(enc.encode('WebPush: info\0'), uaPublic, asPublic), 32);

  const salt  = crypto.getRandomValues(new Uint8Array(16));
  const cek   = await hkdf(salt, ikm, enc.encode('Content-Encoding: aes128gcm\0'), 16);
  const nonce = await hkdf(salt, ikm, enc.encode('Content-Encoding: nonce\0'), 12);

  const aesKey = await crypto.subtle.importKey('raw', cek, 'AES-GCM', false, ['encrypt']);
  const padded = concat(enc.encode(plaintext), new Uint8Array([2]));   // 0x02 = sista posten
  const ct = new Uint8Array(await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv: nonce }, aesKey, padded));

  const rs = new Uint8Array(4);
  new DataView(rs.buffer).setUint32(0, 4096);
  return concat(salt, rs, new Uint8Array([asPublic.length]), asPublic, ct);
}

async function signJwt(aud, env) {
  const head = b64u(enc.encode(JSON.stringify({ typ: 'JWT', alg: 'ES256' })));
  const pay  = b64u(enc.encode(JSON.stringify({
    aud, exp: Math.floor(Date.now() / 1000) + 12 * 3600, sub: env.VAPID_SUBJECT,
  })));
  const data = `${head}.${pay}`;
  const key = await crypto.subtle.importKey('jwk', JSON.parse(env.VAPID_PRIVATE_JWK),
    { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  // WebCrypto ger rå r||s, vilket är exakt vad JWS vill ha — ingen DER-avkodning
  const sig = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, enc.encode(data));
  return `${data}.${b64u(sig)}`;
}

async function sendPush(sub, text, env) {
  // Utan fail-fast blir en saknad hemlighet ett tyst SyntaxError i alarm()
  if (!env.VAPID_PRIVATE_JWK || !env.VAPID_PUBLIC ||
      !/^(mailto:|https:)/.test(env.VAPID_SUBJECT || '')) {
    throw new Error('VAPID-konfiguration saknas');
  }
  if (!validEndpoint(sub.endpoint)) return 400;           // försvar på djupet
  const aud  = new URL(sub.endpoint).origin;
  const jwt  = await signJwt(aud, env);
  const body = await encryptPayload(JSON.stringify(text), sub.keys.p256dh, sub.keys.auth);

  const res = await fetch(sub.endpoint, {
    method: 'POST',
    headers: {
      Authorization: `vapid t=${jwt}, k=${env.VAPID_PUBLIC}`,
      'Content-Encoding': 'aes128gcm',
      'Content-Type': 'application/octet-stream',
      TTL: '1800',                    // telefonen kan vara offline en stund
      Urgency: 'high',
    },
    body,
  });
  return res.status;                  // aldrig svarskroppen — den kan innehålla adresser
}
