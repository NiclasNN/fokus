/* Fokus push-server — Cloudflare Worker.
 *
 * Enda uppgift: knacka på telefonen när ett pass tar slut.
 * Servern får veta en anonym push-adress och en tidsstämpel. Inget annat —
 * inte vad passet handlar om, inte uppgifter, inte statistik.
 *
 * Notisen skickas UTAN innehåll. Texten ligger redan i telefonens cache och
 * läses av service workern. Därför slipper vi nyttolastkryptering (ECDH +
 * HKDF + AES-GCM) och behöver bara signera ett VAPID-JWT.
 */

const CORS = {
  'Access-Control-Allow-Origin': 'https://niclasnn.github.io',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

export default {
  async fetch(req, env) {
    if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
    const url = new URL(req.url);

    if (url.pathname === '/schedule' || url.pathname === '/cancel') {
      let body;
      try { body = await req.json(); } catch { return bad('trasig json'); }

      const ep = body?.subscription?.endpoint;
      if (typeof ep !== 'string' || !/^https:\/\//.test(ep)) return bad('saknar endpoint');

      // Ett Durable Object per prenumeration — id:t härleds ur endpointen,
      // så samma telefon landar alltid i samma objekt.
      const id = env.ALARM.idFromName(await sha256(ep));
      return env.ALARM.get(id).fetch(new Request(url.origin + url.pathname, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      }));
    }
    return new Response('Fokus push', { headers: CORS });
  },
};

function bad(msg) {
  return new Response(JSON.stringify({ error: msg }), {
    status: 400, headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

export class Alarm {
  constructor(state, env) { this.state = state; this.env = env; }

  async fetch(req) {
    const url = new URL(req.url);
    const body = await req.json();

    if (url.pathname === '/cancel') {
      await this.state.storage.deleteAlarm();
      await this.state.storage.deleteAll();
      return json({ ok: true, cancelled: true });
    }

    const endsAt = Number(body.endsAt);
    if (!Number.isFinite(endsAt)) return bad('endsAt saknas');

    const om = endsAt - Date.now();
    if (om < 0 || om > 5 * 60 * 60 * 1000) return bad('endsAt utanför rimligt spann');

    await this.state.storage.put('sub', body.subscription);
    await this.state.storage.setAlarm(endsAt);
    return json({ ok: true, om: Math.round(om / 1000) });
  }

  async alarm() {
    const sub = await this.state.storage.get('sub');
    await this.state.storage.deleteAll();
    if (!sub) return;
    try { await sendPush(sub, this.env); } catch (e) { console.log('push misslyckades', e); }
  }
}

const json = o => new Response(JSON.stringify(o), {
  headers: { ...CORS, 'Content-Type': 'application/json' },
});

/* ── VAPID ───────────────────────────────────────────────────────── */

const b64url = buf => btoa(String.fromCharCode(...new Uint8Array(buf)))
  .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

async function sha256(s) {
  const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return b64url(d);
}

async function signJwt(aud, env) {
  const header  = b64url(new TextEncoder().encode(JSON.stringify({ typ: 'JWT', alg: 'ES256' })));
  const payload = b64url(new TextEncoder().encode(JSON.stringify({
    aud,
    exp: Math.floor(Date.now() / 1000) + 12 * 3600,
    sub: env.VAPID_SUBJECT,
  })));
  const data = `${header}.${payload}`;

  const key = await crypto.subtle.importKey(
    'jwk', JSON.parse(env.VAPID_PRIVATE_JWK),
    { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key,
    new TextEncoder().encode(data));

  return `${data}.${b64url(sig)}`;
}

async function sendPush(sub, env) {
  const aud = new URL(sub.endpoint).origin;
  const jwt = await signJwt(aud, env);
  const res = await fetch(sub.endpoint, {
    method: 'POST',
    headers: {
      Authorization: `vapid t=${jwt}, k=${env.VAPID_PUBLIC}`,
      TTL: '120',
      Urgency: 'high',
      'Content-Length': '0',
    },
  });
  if (!res.ok) throw new Error(`${res.status} ${await res.text()}`);
}
