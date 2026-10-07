/* ============================================================
   Fokus — app logic
   Vanilla JS, no build step. Everything persists to localStorage.
   ============================================================ */
(() => {
'use strict';

const VERSION = '1.1.0';
const KEY = 'fokus.state.v1';
const $  = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];

/* ── categories ──────────────────────────────────────────── */
const CATS = [
  { id:'socialt',  name:'Socialt',        short:'Socialt',  icon:'i-social',   c:'#FF5C7A', hi:'#FF97A9' },
  { id:'struktur', name:'Struktur',       short:'Struktur', icon:'i-struktur', c:'#4C8DFF', hi:'#93B8FF' },
  { id:'pengar',   name:'Pengar/Karriär', short:'Pengar',   icon:'i-pengar',   c:'#14C08C', hi:'#5FE2B9' },
  { id:'halsa',    name:'Utseende/Hälsa', short:'Hälsa',    icon:'i-halsa',    c:'#F5B443', hi:'#FFD68C' },
];
const catById = id => CATS.find(c => c.id === id) || CATS[1];
const PRESETS = [5, 15, 25, 45, 60, 90];
const MIN_MS  = 60000;
/* Push-servern knackar på telefonen när passet tar slut. Utan den kan iOS
   inte väcka appen med släckt skärm — det finns inget web-API för det. */
const VAPID_PUBLIC = 'BK_YVWPUw7jW3k5SYXOkxqVxz5xsy5P-A6AqG0YYMJ27wjsnQssvjk2VVahoaoPARjFE_G--nE4_H_4a2PtRQL8';
const PUSH_URL = 'https://fokus-push.juridiskaistottning.workers.dev';   // ett pass under en minut varken startas, sparas eller räknas

/* ── utils ───────────────────────────────────────────────── */
const p2   = n => String(n).padStart(2, '0');
const uid  = () => Math.random().toString(36).slice(2, 10) + Date.now().toString(36).slice(-4);
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const dayKey = ts => { const d = new Date(ts); return `${d.getFullYear()}-${p2(d.getMonth()+1)}-${p2(d.getDate())}`; };

function fmtClock(ms){
  // ceil, inte round: en nedräkning ska visa 25:00 tills den faktiskt
  // passerat 25:00, och 00:01 hela sista sekunden.
  const t = Math.max(0, Math.ceil(ms / 1000 - 1e-6));
  const h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), s = t % 60;
  return h ? `${h}:${p2(m)}:${p2(s)}` : `${p2(m)}:${p2(s)}`;
}
function fmtDur(ms){
  const min = Math.round(ms / 60000);
  if (min < 60) return `${min} min`;
  const h = Math.floor(min / 60), m = min % 60;
  return m ? `${h} h ${m} min` : `${h} h`;
}
function fmtShort(ms){
  const min = Math.round(ms / 60000);
  return min < 60 ? `${min}m` : `${Math.floor(min/60)}h ${min%60 ? min%60+'m' : ''}`.trim();
}

/* ── state ───────────────────────────────────────────────── */
const defaults = () => ({
  v: 2,
  tasks: [],
  projects: [],
  sessions: [],
  timer: { status:'idle', catId:'struktur', taskId:null, durationMs: 25*60*1000, startedAt:0, elapsedBefore:0 },
  settings: { theme:'light', sound:true, haptics:true, keepAwake:false, notify:true, lastDurMin:25, hintSeen:false },
});

let S = load();

function load(){
  try{
    const raw = localStorage.getItem(KEY);
    if (!raw) return defaults();
    const parsed = JSON.parse(raw);
    const base = defaults();
    return migrate({
      ...base, ...parsed,
      timer:    { ...base.timer,    ...(parsed.timer    || {}) },
      settings: { ...base.settings, ...(parsed.settings || {}) },
      tasks:    Array.isArray(parsed.tasks)    ? parsed.tasks    : [],
      projects: Array.isArray(parsed.projects) ? parsed.projects : [],
      sessions: Array.isArray(parsed.sessions) ? parsed.sessions : [],
    });
  } catch (e){ console.warn('Kunde inte läsa sparad data', e); return defaults(); }
}

/* Gammal data ska aldrig behöva tänkas på längre upp. En uppgift från
   v1 saknar varje Things-fält; här får den dem, en gång, vid inläsning.
   Utan dag hamnar den i "När som helst" — ingenting tappas bort. */
function migrate(s){
  s.tasks.forEach(t => {
    if (t.type === 'heading'){ t.title = t.title || ''; t.projectId = t.projectId || null; return; }
    t.catId      = t.catId || null;
    t.projectId  = t.projectId || null;
    t.notes      = typeof t.notes === 'string' ? t.notes : '';
    t.checklist  = Array.isArray(t.checklist) ? t.checklist : [];
    t.tags       = Array.isArray(t.tags) ? t.tags : [];
    t.when       = t.when === undefined ? null : t.when;
    t.evening    = !!t.evening;
    t.deadline   = t.deadline || null;
    t.durationMs = typeof t.durationMs === 'number' ? t.durationMs : 25 * 60000;
    t.done       = !!t.done;
  });
  s.projects.forEach(p => {
    p.catId = p.catId || null; p.notes = p.notes || '';
    p.when = p.when === undefined ? null : p.when;
    p.deadline = p.deadline || null; p.done = !!p.done;
  });
  s.v = 2;
  return s;
}
let saveTimer = null;
function save(){
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    try { localStorage.setItem(KEY, JSON.stringify(S)); }
    catch (e){ toast('Kunde inte spara — enhetens lagring är full'); }
  }, 120);
}
function saveNow(){ clearTimeout(saveTimer); try{ localStorage.setItem(KEY, JSON.stringify(S)); }catch(e){} }

/* ── theme & accent ──────────────────────────────────────── */
const mq = matchMedia('(prefers-color-scheme: light)');
function applyTheme(){
  const pref = S.settings.theme;
  const resolved = pref === 'system' ? (mq.matches ? 'light' : 'dark') : pref;
  document.documentElement.dataset.theme = resolved;
  const bg = resolved === 'light' ? '#EDF1FA' : '#06070A';
  $$('meta[name="theme-color"]').forEach(m => m.remove());
  const m = document.createElement('meta');
  m.name = 'theme-color'; m.content = bg;
  document.head.appendChild(m);
}
mq.addEventListener?.('change', () => { if (S.settings.theme === 'system') applyTheme(); });

function applyAccent(){
  const c = catById(S.timer.catId);
  document.body.dataset.cat = c.id;      // rummet tonas efter valt livsområde
  const r = document.documentElement.style;
  r.setProperty('--accent', c.c);
  r.setProperty('--accent-hi', c.hi);
  r.setProperty('--accent-soft', hexA(c.c, .15));
}
function hexA(hex, a){
  const n = parseInt(hex.slice(1), 16);
  return `rgba(${(n>>16)&255},${(n>>8)&255},${n&255},${a})`;
}

/* ── haptics & sound ─────────────────────────────────────── */
function buzz(pattern){
  if (!S.settings.haptics) return;
  try { navigator.vibrate?.(pattern); } catch(e){}
}
let ac = null, acIdle = null;
function audio(){
  clearTimeout(acIdle);
  if (!ac){ const C = window.AudioContext || window.webkitAudioContext; if (C) ac = new C(); }
  // iOS sätter state till 'interrupted' vid appväxling, inte 'suspended'.
  // Bara resume från 'suspended' gjorde ljudet permanent dött efter första växlingen.
  if (ac && ac.state !== 'running') ac.resume().catch(() => {});
  return ac;
}
/* En vaken AudioContext håller en aktiv ljudsession — det enda i appen som
   fortsätter kosta ström med släckt skärm. Somna när ingenting låter. */
function acSleepSoon(){
  clearTimeout(acIdle);
  acIdle = setTimeout(() => {
    // aldrig under ett pass: WebKit kan vägra resume() utan gest, och
    // sluttonen kommer inte från en gest
    if (T.status !== 'running' && dragPid === null && !flying
        && ac && ac.state === 'running') ac.suspend().catch(() => {});
  }, 4000);
}
function tone(freq, at, dur, vol = .18, type = 'sine'){
  const a = audio(); if (!a) return;
  const o = a.createOscillator(), g = a.createGain();
  o.type = type; o.frequency.value = freq;
  const t0 = a.currentTime + at;
  g.gain.setValueAtTime(0, t0);
  g.gain.linearRampToValueAtTime(vol, t0 + .012);
  g.gain.exponentialRampToValueAtTime(.0001, t0 + dur);
  o.connect(g); g.connect(a.destination);
  o.onended = () => { try { o.disconnect(); g.disconnect(); } catch(e){} };
  o.start(t0); o.stop(t0 + dur + .05);
  acSleepSoon();
}
/* Ett detentklick, inte en pipsignal. Två partialer med snabb
   exponentiell död: en torr transient upptill och lite kropp under.
   Tonhöjden stiger när man drar upp och sjunker när man drar ner. */
let lastTickAt = 0;
function detent(dir, kind){
  if (!S.settings.sound) return;
  const a = audio(); if (!a) return;
  const t0 = a.currentTime;
  if (t0 - lastTickAt < 0.022) return;        // tak vid snabba drag
  lastTickAt = t0;

  const bas  = kind === 'hour' ? 1500 : kind === 'five' ? 2500 : 2050;
  const lut  = dir > 0 ? 1.06 : 0.94;         // upp ljusare, ner mörkare
  const vol  = kind === 'min' ? 0.05 : kind === 'five' ? 0.075 : 0.1;
  const dur  = kind === 'hour' ? 0.05 : 0.016;

  const click = (freq, gain, len, type) => {
    const o = a.createOscillator(), g = a.createGain();
    o.type = type;
    o.frequency.setValueAtTime(freq, t0);
    o.frequency.exponentialRampToValueAtTime(freq * 0.72, t0 + len);
    g.gain.setValueAtTime(0, t0);
    g.gain.linearRampToValueAtTime(gain, t0 + 0.001);
    g.gain.exponentialRampToValueAtTime(0.0001, t0 + len);
    o.connect(g); g.connect(a.destination);
    o.onended = () => { try { o.disconnect(); g.disconnect(); } catch(e){} };
    o.start(t0); o.stop(t0 + len + 0.02);
  };
  click(bas * lut, vol, dur, 'triangle');           // transienten
  click(bas * lut * 0.5, vol * 0.55, dur * 1.6, 'sine');   // kroppen
  if (kind === 'hour') click(320, 0.09, 0.12, 'sine');     // hel timme: en dov stöt
  acSleepSoon();
}

const sndStart = () => { if (S.settings.sound){ tone(523.25, 0, .28, .12); tone(783.99, .06, .34, .09); } };
const sndDone  = () => { if (!S.settings.sound) return;
  [880, 1108.73, 1318.51, 1760].forEach((f, i) => tone(f, i * .16, 1.5 - i * .18, .2 - i * .03)); };

/* ── toast ───────────────────────────────────────────────── */
function toast(msg, ms = 2600){
  const host = $('#toasts');
  host.replaceChildren();
  const el = document.createElement('div');
  el.className = 'toast'; el.textContent = msg;
  host.appendChild(el);
  setTimeout(() => { el.classList.add('is-out'); setTimeout(() => el.remove(), 320); }, ms);
}

/* ── notifications ───────────────────────────────────────── */
let swReg = null;
const notifSupported = 'Notification' in window;
const hasVibe = typeof navigator.vibrate === 'function';   // saknas helt i Safari/iOS

function notifyGranted(){
  return notifSupported && Notification.permission === 'granted';
}
let warnedNoAlarm = false;

async function ensureNotifyPermission(interactive){
  if (!notifSupported) return 'unsupported';
  if (Notification.permission === 'granted') return 'granted';
  if (Notification.permission === 'denied') return 'denied';
  if (!interactive) return 'default';
  try { return await Notification.requestPermission(); } catch(e){ return 'default'; }
}
/* Texten till notisen läggs i cachen, inte i pushen. Service workern läser
   den när knackningen kommer. */
async function stashAlarmText(title, body){
  try {
    const c = await caches.open('fokus-alarm');
    await c.put(new URL('__alarm', location.href).href,
      new Response(JSON.stringify({ title, body }), { headers:{ 'Content-Type':'application/json' } }));
  } catch(e){}
}

async function pushSubscription(){
  if (!PUSH_URL || !('PushManager' in window)) return null;
  const reg = swReg || (await navigator.serviceWorker?.ready.catch(() => null));
  if (!reg) return null;
  try {
    const cur = await reg.pushManager.getSubscription();
    if (cur){
      // Hör den till samma VAPID-nyckel? Annars är den värdelös och måste bytas.
      const k = cur.options?.applicationServerKey;
      const same = !k || btoa(String.fromCharCode(...new Uint8Array(k)))
        .replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'') === VAPID_PUBLIC;
      if (same) return cur;
      await cur.unsubscribe().catch(() => {});
    }
    return await reg.pushManager.subscribe({
      userVisibleOnly: true, applicationServerKey: VAPID_PUBLIC,
    });
  } catch(e){ console.log('kunde inte prenumerera på push', e); return null; }
}

async function serverSchedule(endsAt, title, body){
  const sub = await pushSubscription();
  if (!sub) return;
  try {
    const res = await fetch(PUSH_URL + '/schedule', {
      method:'POST', headers:{ 'Content-Type':'application/json' },
      body: JSON.stringify({ subscription: sub.toJSON(), endsAt, seq: Date.now(), title, body }),
    });
    const out = await res.json().catch(() => ({}));
    if (out.gone){                       // prenumerationen är död — skapa en ny
      await sub.unsubscribe().catch(() => {});
      const fresh = await pushSubscription();
      if (fresh) await fetch(PUSH_URL + '/schedule', {
        method:'POST', headers:{ 'Content-Type':'application/json' },
        body: JSON.stringify({ subscription: fresh.toJSON(), endsAt, seq: Date.now(), title, body }),
      });
    }
  } catch(e){}
}
async function serverCancel(){
  if (!PUSH_URL) return;
  const reg = swReg || (await navigator.serviceWorker?.ready.catch(() => null));
  const sub = await reg?.pushManager.getSubscription().catch(() => null);
  if (!sub) return;
  try {
    await fetch(PUSH_URL + '/cancel', {
      method:'POST', headers:{ 'Content-Type':'application/json' },
      body: JSON.stringify({ subscription: sub.toJSON(), seq: Date.now() }),
    });
  } catch(e){}
}

/* Larmets text på ETT ställe. Skrevs den olika i startTimer och vid
   återupptagning tappade notisen uppgiftens namn bara för att appen öppnats. */
function alarmText(){
  return ['Passet är klart 🎉', `${sessionTitle()} — ${fmtDur(T.durationMs)} avklarat`];
}

async function scheduleAlarm(endsAt, title, body){
  if (!S.settings.notify || !notifSupported || Notification.permission !== 'granted') return;
  const reg = swReg || (await navigator.serviceWorker?.ready.catch(() => null));
  if (!reg) return;
  const opts = {
    body, tag:'fokus-timer', renotify:true, requireInteraction:true,
    icon:'icons/icon-192.png', badge:'icons/badge.png',
    vibrate:[220, 90, 220, 90, 380],
    data:{ endsAt },
  };
  await stashAlarmText(title, body);
  await serverSchedule(endsAt, title, body);   // enda vägen som når en släckt iPhone
  // Chromium: fires even when the app is closed.
  if ('showTrigger' in Notification.prototype && window.TimestampTrigger){
    try { await reg.showNotification(title, { ...opts, showTrigger: new TimestampTrigger(endsAt) }); return; }
    catch(e){ /* fall through */ }
  }
  // Everywhere else: best effort while the service worker is still alive.
  reg.active?.postMessage({ type:'schedule', endsAt, title, options: opts });
}
async function cancelAlarm(){
  const reg = swReg || (await navigator.serviceWorker?.ready.catch(() => null));
  if (!reg) return;
  reg.active?.postMessage({ type:'cancel' });
  await serverCancel();
  try { (await reg.getNotifications({ tag:'fokus-timer' })).forEach(n => n.close()); } catch(e){}
}
async function fireNow(title, body){
  if (!notifSupported || Notification.permission !== 'granted' || !S.settings.notify) return;
  const reg = swReg || (await navigator.serviceWorker?.ready.catch(() => null));
  const opts = { body, tag:'fokus-timer', renotify:true, icon:'icons/icon-192.png',
                 badge:'icons/badge.png', vibrate:[220,90,220,90,380] };
  try { reg ? await reg.showNotification(title, opts) : new Notification(title, opts); } catch(e){}
}

/* ── wake lock ───────────────────────────────────────────── */
let wake = null, wakeReq = null;
async function wakeOn(){
  if (!S.settings.keepAwake || !('wakeLock' in navigator)) return;
  if (wake || wakeReq) return;                 // aldrig två samtidiga begäran
  try {
    wakeReq = navigator.wakeLock.request('screen');
    wake = await wakeReq;
    wake.addEventListener('release', () => { wake = null; });
  } catch(e){}
  finally { wakeReq = null; }
}
async function wakeOff(){ const w = wake; wake = null; try { await w?.release(); } catch(e){} }

document.addEventListener('visibilitychange', () => {
  if (document.hidden){
    clearInterval(loopId); loopId = null; wakeOff();
    try { ac?.suspend(); } catch(e){}
    return;
  }
  audio();                                    // före tick: passet kan ha tagit slut
  if (T.status === 'running') wakeOn();
  tick(true);
  loop();
});

/* ── timer engine ────────────────────────────────────────── */
const T = S.timer;
const elapsed = () => T.elapsedBefore + (T.status === 'running' ? Date.now() - T.startedAt : 0);
const remaining = () => Math.max(0, T.durationMs - elapsed());

function startTimer(){
  audio();
  if (T.status === 'running') return;
  if (T.durationMs < MIN_MS){ toast('Ställ minst en minut först'); return; }
  if (T.status === 'idle') T.elapsedBefore = 0;
  T.status = 'running';
  T.startedAt = Date.now();
  save(); sndStart(); buzz(12); wakeOn(); loop();
  if (S.settings.notify && !notifyGranted() && !warnedNoAlarm){
    warnedNoAlarm = true;
    toast('Inget larm i bakgrunden — slå på notiser under Mer', 3600);
  } else if (S.settings.notify && notifyGranted() && !PUSH_URL && !warnedNoAlarm){
    warnedNoAlarm = true;
    toast('Larmet väcker inte en släckt skärm ännu', 3400);
  }
  scheduleAlarm(Date.now() + remaining(), ...alarmText());
  renderFocus();
}
function pauseTimer(){
  if (T.status !== 'running') return;
  T.elapsedBefore += Date.now() - T.startedAt;
  T.status = 'paused';
  save(); buzz(10); wakeOff(); cancelAlarm(); loop();
  renderFocus();
}
function resetTimer(){
  T.status = 'idle'; T.elapsedBefore = 0; T.startedAt = 0;
  save(); buzz(8); wakeOff(); cancelAlarm(); loop();
  renderFocus();
}
function finishEarly(){
  const ms = elapsed();
  if (ms < MIN_MS){ resetTimer(); toast('Pass under en minut sparas inte'); return; }
  logSession(ms, Date.now());
  resetTimer();
  toast(`${fmtDur(ms)} sparat i ${catById(T.catId).name}`);
  renderAll();
}
function completeTimer(at = Date.now()){
  const ms = T.durationMs;
  logSession(ms, at);
  T.status = 'idle'; T.elapsedBefore = 0; T.startedAt = 0;
  save(); wakeOff(); loop();
  sndDone(); buzz([220, 90, 220, 90, 380]);
  cancelAlarm();                       // annars knackar servern på strax efteråt
  fireNow('Passet är klart 🎉', `${catById(T.catId).name} · ${fmtDur(ms)} fokuserat`);
  doneSequence();
  renderAll();
}
function logSession(ms, endedAt){
  const task = currentTask();
  S.sessions.unshift({
    id: uid(), catId: T.catId, taskId: T.taskId || null,
    title: sessionTitle(), ms, endedAt,
  });
  if (S.sessions.length > 600) S.sessions.length = 600;
  if (task){ task.focusedMs = (task.focusedMs || 0) + ms; task.sessions = (task.sessions || 0) + 1; }
  saveNow();
}
/* Ett pass som har tid på sig äger tiden, uppgiften och livsområdet.
   Allt som skulle skriva över dem går igenom den här vakten först. */
function timeLocked(){
  if (T.status === 'idle') return false;
  toast(T.status === 'running'
    ? 'Pausa passet först — eller spara det med bocken'
    : 'Nollställ eller spara passet först');
  buzz(12);
  return true;
}

function currentTask(){ return S.tasks.find(x => x.id === T.taskId) || null; }
function sessionTitle(){ return currentTask()?.title || catById(T.catId).name; }

let loopId = null;
/* 240 ms-intervallet startades vid init och stoppades aldrig — det tickade
   vidare i vila, i bakgrunden och med skärmen släckt. Nu lever det bara
   medan något faktiskt räknar ner och appen är synlig. */
function loop(){
  clearInterval(loopId); loopId = null;
  if (T.status !== 'running' || document.hidden) return;
  loopId = setInterval(() => tick(), 240);
}
function tick(force){
  if (T.status === 'running' && remaining() <= 0){
    const at = T.startedAt + (T.durationMs - T.elapsedBefore);
    completeTimer(Math.min(at, Date.now()));
    return;
  }
  if (T.status === 'running'){
    // samma kvantitet som fmtClock visar, annars hoppar värdet
    const rem = remaining(), sec = Math.ceil(rem / 1000 - 1e-6);
    if (sec === lastSec && !force) return;      // rita bara när siffran faktiskt ändras
    lastSec = sec;
    document.body.classList.toggle('is-endgame', rem <= 10000);
    paintDial(force);                            // force = återkomst från bakgrunden
    return;
  }
  if (force) paintDial(true);
}

/* ── dial: "Glöd" — ett upplyst föremål ──────────────────── */
const R = 100, C = 2 * Math.PI * R, CX = 130;
const K_HYST = 0.58;   // minuter innan värdet flippar (3,48°)
const K_ELAS = 0.55;   // ljusets gain inom ett steg
const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)');

const lapsOf = m => Math.floor((m - 1) / 60);
const arcOf  = m => m - lapsOf(m) * 60;        // alltid 1–60

let minsFloat = 25, cur = 25, dragPid = null, flying = false, flightCancel = null;
let lastSec = -1, shownLaps = -1, lastBuzzAt = 0, lastAriaAt = 0, nudged = false;

/* En graverad skala. Aldrig accentfärgad, aldrig omritad. */
function buildTicks(){
  $('#ticks').innerHTML = Array.from({ length: 60 }, (_, i) => {
    const a = (i * 6 - 90) * Math.PI / 180;
    const r1 = i % 5 === 0 ? 108 : 111, r2 = 116;
    return `<line x1="${(CX + r1*Math.cos(a)).toFixed(2)}" y1="${(CX + r1*Math.sin(a)).toFixed(2)}"
                  x2="${(CX + r2*Math.cos(a)).toFixed(2)}" y2="${(CX + r2*Math.sin(a)).toFixed(2)}"/>`;
  }).join('');
  [$('#core'), $('#trail'), $('#arcMaskArc')].forEach(el => el.style.strokeDasharray = `${C}`);
}

/* Enda stället som rör ljusets geometri. */
function paintRing(frac, headDeg){
  const off = `${C * (1 - clamp(frac, 0, 1))}`;
  $('#core').style.strokeDashoffset = off;
  $('#trail').style.strokeDashoffset = off;
  $('#arcMaskArc').style.strokeDashoffset = off;
  $('#gHead').setAttribute('transform', `rotate(${headDeg.toFixed(2)} 130 130)`);
  $('#headInner').setAttribute('transform', `rotate(${(-headDeg).toFixed(2)} 130 30)`);
}

function setLaps(n){
  if (n === shownLaps) return;
  const grow = n > shownLaps;
  shownLaps = n;
  $('#gLaps').innerHTML = Array.from({ length: n }, (_, i) =>
    `<circle cx="130" cy="130" r="${80 - i * 8}" class="${grow && i === n - 1 ? 'is-new' : ''}"/>`).join('');
}

/* IDLE: ett varv = 60 minuter, hela timmar som varvringar. */
function paintIdle(mins, elasticDeg = 0){
  const arc = arcOf(mins);
  paintRing(arc / 60, arc * 6 + elasticDeg);
  setLaps(lapsOf(mins));
  writeIdleTime(mins);
}

/* RUNNING/PAUSED: ett varv = hela passet. Varvringarna göms. */
function paintRun(rem){
  const frac = T.durationMs > 0 ? clamp(rem / T.durationMs, 0, 1) : 0;
  paintRing(frac, frac * 360);
  setLaps(0);
  writeClock(rem);
}

function writeIdleTime(mins){
  const el = $('#dialTime'), num = $('#dialNum'), unit = $('#dialUnit');
  const exact = (dragPid === null && !flying) ? Math.round(T.durationMs / 1000) % 60 : 0;
  if (exact){ writeClock(T.durationMs); return; }
  el.classList.remove('is-clock', 'is-long');
  unit.hidden = false;
  if (mins < 60){ num.textContent = mins; unit.textContent = 'min'; }
  else {
    const h = Math.floor(mins / 60), m = mins % 60;
    num.textContent = m ? `${h}:${p2(m)}` : String(h);
    unit.textContent = 'tim';
  }
}
function writeClock(ms){
  const el = $('#dialTime'), txt = fmtClock(ms);
  $('#dialNum').textContent = txt;
  $('#dialUnit').hidden = true;
  el.classList.add('is-clock');
  el.classList.toggle('is-long', txt.length > 5);
}

/* Samma sanning på alla flikar: pillret läses ur samma remaining(). */
function paintPill(){
  const el = $('#timerPill');
  const live = T.status === 'running' || T.status === 'paused';
  const show = live && document.body.dataset.view !== 'focus';
  el.hidden = !show;
  $('#todayPill').hidden = show;          // topbaren rymmer inte bådadera
  if (!show) return;
  $('#timerPillText').textContent = fmtClock(remaining());
  el.classList.toggle('is-paused', T.status === 'paused');
}

function paintDial(jump){
  const dial = $('#dial');
  if (jump) dial.classList.add('is-jump');
  const live = T.status === 'running' || T.status === 'paused';
  if (live) paintRun(remaining());
  else { cur = minsFloat = Math.round(T.durationMs / 60000); paintIdle(cur); }
  document.title = live ? `${fmtClock(remaining())} · Fokus` : 'Fokus — fyra livsområden';
  paintPill();
  if (jump){ void dial.offsetWidth; dial.classList.remove('is-jump'); }
  paintSteppers();
}

function paintSteppers(){
  if (!$('#stepH')) return;
  const t = Math.round(T.durationMs / 1000);
  $('#stepH').textContent = p2(Math.floor(t / 3600));
  $('#stepM').textContent = p2(Math.floor((t % 3600) / 60));
  $('#stepS').textContent = p2(t % 60);
}

function renderFocus(){
  applyAccent();
  const c = catById(T.catId);
  $('#dialCat').textContent = c.name.toUpperCase();
  const task = currentTask();
  renderTaskStrip();

  const running = T.status === 'running', paused = T.status === 'paused';
  $('#dial').classList.toggle('is-running', running);
  document.body.classList.toggle('is-running', running);
  document.body.classList.toggle('is-paused', paused);
  if (!running) document.body.classList.remove('is-endgame');
  lastSec = -1;
  $('#btnPlay').innerHTML = running
    ? '<svg class="ic"><use href="#i-pause"></use></svg><span>Pausa</span>'
    : `<svg class="ic"><use href="#i-play"></use></svg><span>${paused ? 'Fortsätt' : 'Starta'}</span>`;
  $('#dialSub').textContent = running ? sessionTitle()
                            : paused  ? 'Pausad'
                            : task ? task.title
                            : 'Redo att starta';
  // Idle behöver ingen text — presentationsnudgen visar gesten i stället.
  const hint = $('#dialHint');
  if (paused){ hint.textContent = 'Pausad — nollställ för att ändra tiden'; hint.hidden = false; }
  else { hint.hidden = true; }
  $('#btnReset').disabled = T.status === 'idle' && T.elapsedBefore === 0;
  $('#btnDone').disabled  = T.status === 'idle';

  $$('#cats .corner').forEach(el => el.classList.toggle('is-on', el.dataset.id === T.catId));
  markPreset();
  paintDial();
  if (!running && !paused) maybeNudge();
}

/* Dagens plan styr remsan. En uppgift hör till området antingen direkt
   eller via sitt projekt, och "någon gång" ska inte ligga och skräpa här. */
function renderTaskStrip(){
  const host = $('#taskStrip');
  const rank = t => (isDate(t.when) && t.when <= tkey()) ? 0
                  : (isDate(t.deadline) && t.deadline <= keyAdd(3)) ? 1 : 2;
  const open = S.tasks
    .filter(t => !isHead(t) && !t.done && t.when !== 'someday' &&
                 (t.catId === T.catId || projById(t.projectId)?.catId === T.catId))
    .sort((a, b) => rank(a) - rank(b));

  host.innerHTML = open.length
    ? open.map(t => `<button type="button" class="tchip ${T.taskId === t.id ? 'is-on' : ''}"
          data-id="${t.id}" data-dur="${t.durationMs}">
          <span class="tchip__t">${escapeHtml(t.title)}</span>
          <span class="tchip__done" data-done="1" role="button" tabindex="0"
                aria-label="Markera klar"><svg class="ic ic--xs"><use href="#i-check"></use></svg></span>
        </button>`).join('') +
      `<button type="button" class="tchip tchip--add" id="tchipAdd" aria-label="Ny uppgift"><svg class="ic ic--sm"><use href="#i-plus"></use></svg></button>`
    : `<button type="button" class="tchip tchip--add tchip--empty" id="tchipAdd">
         <svg class="ic ic--sm"><use href="#i-plus"></use></svg><span>Vad ska du göra?</span></button>`;

  $('#tchipAdd').addEventListener('click', () => { buzz(8); openSheet('task'); });

  $$('.tchip[data-id]', host).forEach(el => el.addEventListener('click', ev => {
    if (timeLocked()) return;
    const id = el.dataset.id;
    const t = S.tasks.find(x => x.id === id);
    if (!t) return;
    if (ev.target.closest('[data-done]')){
      t.done = true; t.completedAt = Date.now();
      if (T.taskId === id) T.taskId = null;
      buzz([10, 40, 16]); save(); renderAll(); toast(`"${t.title}" är klar ✓`);
      return;
    }
    if (T.taskId === id) T.taskId = null;            // tryck igen = avmarkera
    else {
      T.taskId = id;
      if (T.status === 'idle'){ T.durationMs = t.durationMs; T.elapsedBefore = 0; T.startedAt = 0; }
    }
    buzz(8); save(); renderFocus();
  }));

  host.querySelector('.tchip.is-on')?.scrollIntoView({ inline:'center', block:'nearest', behavior:'smooth' });
}

function markPreset(){
  const min = Math.round(T.durationMs / 60000);
  $$('#presets .chip[data-min]').forEach(el => el.classList.toggle('is-on', +el.dataset.min === min));
}

function renderCorners(){
  const host = $('#cats');
  const pos = ['tl','tr','bl','br'];
  const order = ['socialt','struktur','pengar','halsa'];
  host.innerHTML = order.map((id, i) => {
    const c = catById(id);
    return `<button type="button" class="corner corner--${pos[i]}" data-id="${c.id}" style="--c:${c.c}" role="tab" aria-label="${c.name}">
      <span class="corner__dot"></span>
      <svg class="ic"><use href="#${c.icon}"></use></svg>
      <span class="corner__name">${c.short}</span>
    </button>`;
  }).join('');
  $$('.corner', host).forEach(el => el.addEventListener('click', () => {
    if (el.dataset.id === T.catId) return;
    if (timeLocked()) return;
    buzz(10);
    T.catId = el.dataset.id; T.taskId = null;
    save(); renderFocus();
  }));
}

/* ── gesten: tryck var som helst i bandet, ljuset flyter dit ─ */
function initDial(){
  const dial = $('#dial'), band = $('#dialBand');
  let prevAng = 0;

  const polar = e => {
    const r = dial.getBoundingClientRect();
    const dx = e.clientX - (r.left + r.width / 2);
    const dy = e.clientY - (r.top  + r.height / 2);
    return { rad: Math.hypot(dx, dy),
             ang: (Math.atan2(dy, dx) * 180 / Math.PI + 90 + 360) % 360,
             k: r.width / 260, half: r.width / 2 };
  };

  band.addEventListener('pointerdown', e => {
    if (T.status !== 'idle'){ timeLocked(); return; }
    if (dragPid !== null) return;                       // andra fingret ignoreras
    const { rad, ang, k, half } = polar(e);
    if (rad < 56 || rad > Math.min(half + 24, 142)) return;

    audio();                                    // låses upp av just den här gesten
    dragPid = e.pointerId;
    try { band.setPointerCapture(dragPid); } catch(err){}
    dial.classList.add('is-drag');
    $('#gHead').style.willChange = 'transform';
    minsFloat = cur = Math.round(T.durationMs / 60000);

    // greppar man pärlan behåller den sitt avstånd; annars flyger ljuset hit
    const headAng = arcOf(cur) * 6;
    const arcPx = Math.abs(((ang - headAng + 540) % 360) - 180) * Math.PI / 180 * 100 * k;
    prevAng = ang;
    buzz(6);
    if (arcPx > 30) flyToAngle(ang);
  });

  band.addEventListener('pointermove', e => {
    if (e.pointerId !== dragPid || flying) return;
    const { ang } = polar(e);
    let d = ang - prevAng;
    if (d > 180) d -= 360; if (d < -180) d += 360;
    if (Math.abs(d) > 90){ prevAng = ang; return; }     // tappad händelse, inte en rörelse
    prevAng = ang;

    const want = minsFloat + d / 6;                      // 6° = 1 minut
    minsFloat = clamp(want, 1, 240);                     // clampen ÄR rebaseringen
    if (minsFloat !== want) edgeFlash();
    if (Math.abs(minsFloat - cur) > K_HYST){
      const prev = cur;
      cur = clamp(Math.round(minsFloat), 1, 240);
      commitMinutes(cur, prev);
    }
    paintIdle(cur, clamp((minsFloat - cur) * 6 * K_ELAS, -3.5, 3.5));
  });

  const end = e => {
    if (e.pointerId !== dragPid) return;
    dragPid = null;
    dial.classList.remove('is-drag');
    $('#gHead').style.willChange = '';
    try { band.releasePointerCapture(e.pointerId); } catch(err){}
    minsFloat = cur;
    paintIdle(cur, 0);
    buzz(8);
    announce(cur);
    save(); renderFocus();                               // enda skrivningen i hela gesten
  };
  ['pointerup', 'pointercancel', 'lostpointercapture'].forEach(ev => band.addEventListener(ev, end));

  let wheelAccum = 0;
  band.addEventListener('wheel', e => {
    if (T.status !== 'idle') return;
    e.preventDefault();
    wheelAccum += e.deltaY;
    while (Math.abs(wheelAccum) >= 50){
      const dir = wheelAccum > 0 ? -1 : 1;
      wheelAccum -= dir * -50;
      setMinutes(clamp(cur + dir, 1, 240));
    }
  }, { passive: false });

  band.addEventListener('keydown', e => {
    if (T.status !== 'idle') return;
    const big = e.shiftKey ? 5 : 1;
    const map = { ArrowRight: big, ArrowUp: big, ArrowLeft: -big, ArrowDown: -big,
                  PageUp: 15, PageDown: -15 };
    let v = null;
    if (e.key in map) v = clamp(cur + map[e.key], 1, 240);
    else if (e.key === 'Home') v = 1;
    else if (e.key === 'End')  v = 240;
    if (v === null) return;
    e.preventDefault();
    flyToMin(v, 160);
  });
}

/* Sätt ett värde direkt, utan flygning. */
function setMinutes(v){
  if (v === cur) return;
  const prev = cur;
  cur = minsFloat = v;
  commitMinutes(v, prev);
  paintIdle(cur, 0);
  save();
}

/* Ett steg passerat: skriv värdet i minnet och kvittera. */
function commitMinutes(next, prev){
  // Rör ALDRIG status här. En flygning landar hundratals ms efter gesten,
  // och hann användaren trycka Starta emellan raderades passet.
  T.durationMs = next * 60000;
  S.settings.lastDurMin = next;
  S.settings.hintSeen = true;
  markPreset();
  ariaUpdate(next);

  const newLap = lapsOf(next) !== lapsOf(prev);
  const dir = next > prev ? 1 : -1;
  detent(dir, newLap ? 'hour' : next % 5 === 0 ? 'five' : 'min');

  const now = performance.now();
  if (now - lastBuzzAt >= 40){
    lastBuzzAt = now;
    if (newLap)                      buzz([12, 40, 12, 40, 18]);
    else if (PRESETS.includes(next)) buzz([6, 26, 6]);
    else if (next % 5 === 0)         buzz(14);
    else                             buzz(7);
  }
  if (next % 5 === 0) flashOnce('#core', 'blink', 130);
  if (newLap)         flashOnce('#dialTime', 'pop', 180);
}

function flashOnce(sel, cls, ms){
  if (reduceMotion.matches) return;
  const el = $(sel); if (!el) return;
  el.classList.remove(cls); void el.offsetWidth; el.classList.add(cls);
  setTimeout(() => el.classList.remove(cls), ms);
}
let edgeAt = 0;
function edgeFlash(){
  const now = performance.now();
  if (now - edgeAt < 400) return;              // en gång, inte varje bildruta
  edgeAt = now; buzz(2); flashOnce('#edge', 'flash', 180);
}

/* Ljuset rinner till fingret — 260 ms instruktion utan text. */
function flyToAngle(ang){
  let a = Math.round(ang / 6); if (a === 0) a = 60;
  const lap = lapsOf(cur);
  const target = [lap - 1, lap, lap + 1].map(L => L * 60 + a)
    .filter(v => v >= 1 && v <= 240)
    .sort((x, y) => Math.abs(x - cur) - Math.abs(y - cur))[0];
  const arcDeg = Math.abs(((target - cur) % 60) * 6);
  flyToMin(target, Math.min(260, 140 + arcDeg * 0.55));
}

function flyToMin(target, dur){
  target = clamp(Math.round(target), 1, 240);
  flightCancel?.();                    // sista trycket ska vinna
  const from = minsFloat;              // fortsätt där ljuset faktiskt står
  if (Math.abs(from - target) < 0.01) return;
  // rAF fryser i en dold flik — hoppa direkt i stället för att aldrig landa
  if (reduceMotion.matches || document.hidden){ setMinutes(target); announce(target); return; }

  flying = true;
  let done = false;
  const finish = () => {
    if (done) return;
    if (T.status !== 'idle'){          // ett pass hann starta — landa tyst
      done = true; flying = false; flightCancel = null; clearTimeout(guard); return;
    }
    done = true; flying = false; flightCancel = null; clearTimeout(guard);
    const prev = cur;
    cur = minsFloat = target;
    commitMinutes(target, prev);
    paintIdle(cur, 0);
    buzz(8); announce(target); save();
  };
  const guard = setTimeout(finish, dur + 300);   // skyddsnät om bildrutorna uteblir
  flightCancel = () => { done = true; flying = false; clearTimeout(guard); };

  const delta = target - from, t0 = performance.now();
  const step = now => {
    if (done || T.status !== 'idle'){ flying = false; return; }
    const t = Math.min(1, (now - t0) / dur);
    const v = from + delta * (1 - Math.pow(1 - t, 3));
    minsFloat = v;                     // avbryts flygningen vet nästa var ljuset står
    const whole = Math.round(v);
    paintIdle(whole, (v - whole) * 6);
    if (t < 1) requestAnimationFrame(step); else finish();
  };
  requestAnimationFrame(step);
}

function ariaUpdate(v){
  const now = performance.now();
  if (now - lastAriaAt < 120) return;
  lastAriaAt = now;
  const b = $('#dialBand');
  b.setAttribute('aria-valuenow', v);
  b.setAttribute('aria-valuetext', fmtDur(v * 60000));
}
function announce(v){
  $('#dialBand').setAttribute('aria-valuenow', v);
  $('#dialBand').setAttribute('aria-valuetext', fmtDur(v * 60000));
  $('#dialLive').textContent = fmtDur(v * 60000);
}

/* Gesten visas i stället för att beskrivas — en gång per session. */
function maybeNudge(){
  if (nudged || S.settings.hintSeen || T.status !== 'idle') return;
  nudged = true;
  if (reduceMotion.matches){
    const h = $('#dialHint');
    h.textContent = 'Dra runt ringen'; h.hidden = false;
    setTimeout(() => { h.hidden = true; }, 4000);
    return;
  }
  setTimeout(() => {
    if (T.status !== 'idle' || dragPid !== null || flying) return;
    const t0 = performance.now(), dur = 620;
    const step = now => {
      if (T.status !== 'idle' || dragPid !== null) return;
      const t = Math.min(1, (now - t0) / dur);
      paintIdle(cur, -7 * Math.sin(t * Math.PI));
      if (t < 1) requestAnimationFrame(step); else paintIdle(cur, 0);
    };
    requestAnimationFrame(step);
  }, 900);
}

/* ── steppers ────────────────────────────────────────────── */
const stopAll = new Set();
['pointerup','pointercancel','blur'].forEach(ev =>
  addEventListener(ev, () => { stopAll.forEach(fn => fn()); stopAll.clear(); }));

function wireSteppers(root){
  const step = (unit, dir) => {
    if (T.status !== 'idle') return;
    const mult = unit === 'h' ? 3600 : unit === 'm' ? 60 : 5;
    let t = Math.round(T.durationMs / 1000) + dir * mult;
    t = clamp(t, MIN_MS / 1000, 240 * 60);
    T.durationMs = t * 1000; T.elapsedBefore = 0; T.status = 'idle'; T.startedAt = 0;
    S.settings.lastDurMin = Math.round(t / 60);
    paintSteppers(); markPreset(); paintDial();   // allt steppern faktiskt rör
  };
  $$('.stepper__btn', root).forEach(btn => {
    const unit = btn.closest('.stepper').dataset.unit;
    const dir  = +btn.dataset.dir;
    let hold = null, rep = null;
    const go   = () => step(unit, dir);
    const stop = () => { clearTimeout(hold); clearInterval(rep); hold = rep = null;
                         stopAll.delete(stop); renderFocus(); save(); };   // tungt först vid släpp
    btn.addEventListener('pointerdown', e => {
      try { btn.setPointerCapture(e.pointerId); } catch(err){}
      go();
      stopAll.add(stop);
      hold = setTimeout(() => { rep = setInterval(go, 90); }, 420);
    });
    ['pointerup','pointerleave','pointercancel','lostpointercapture'].forEach(ev =>
      btn.addEventListener(ev, stop));
  });
}

/* ── presets ─────────────────────────────────────────────── */
function renderPresets(){
  $('#presets').innerHTML = PRESETS.map(m =>
    `<button type="button" class="chip" data-min="${m}">${m < 60 ? m + ' min' : (m/60 % 1 ? (m/60).toFixed(1) : m/60) + ' h'}</button>`
  ).join('') + '<button type="button" class="chip" id="chipCustom">Egen tid</button>';
  $('#chipCustom').addEventListener('click', () => { if (timeLocked()) return; buzz(8); openSheet('time'); });
  $$('#presets .chip[data-min]').forEach(el => el.addEventListener('click', () => {
    if (timeLocked()) return;
    const m = +el.dataset.min;
    buzz(8);
    flyToMin(m, Math.abs(m - cur) > 60 ? 560 : 420);   // användaren SER mekaniken röra sig
  }));
}

/* ══════════════════════════════════════════════════════════
   LISTOR — Things-modellen ovanpå fokustimern

   Fyra livsområden är Areas. Under dem ligger projekt, och i
   dem uppgifter. Var en uppgift hamnar avgörs av två fält:
     when      null | 'someday' | 'ÅÅÅÅ-MM-DD'   — när den ska göras
     deadline  null | 'ÅÅÅÅ-MM-DD'               — när den MÅSTE vara klar
   Listorna är vyer över de fälten, aldrig egna lagringsplatser.

   S.tasks är EN platt array och ordningen i den ÄR sorteringen —
   även rubriker ligger där (type:'heading'), så ett projekts
   rubriker och uppgifter växlar av sig själva utan sorteringsfält.
   ══════════════════════════════════════════════════════════ */

function escapeHtml(s){ return String(s).replace(/[&<>"']/g, m => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m])); }

const DAY = 86400000;
const LISTS = [
  { id:'inbox',    name:'Inkorg',        icon:'i-inbox',    c:'#5B8DEF',
    empty:['Inkorgen är tom', 'Allt du fångar utan att sortera hamnar här.'] },
  { id:'today',    name:'Idag',          icon:'i-star',     c:'#F0A92E',
    empty:['Inget inplanerat idag', 'Lägg till en uppgift eller flytta hit något från Kommande.'] },
  { id:'upcoming', name:'Kommande',      icon:'i-calendar', c:'#E8734A',
    empty:['Inget på kalendern', 'Sätt ett datum på en uppgift så dyker den upp här.'] },
  { id:'anytime',  name:'När som helst', icon:'i-layers',   c:'#17B588',
    empty:['Inget att ta tag i', 'Uppgifter utan datum samlas här.'] },
  { id:'someday',  name:'Någon gång',    icon:'i-box',      c:'#B8923F',
    empty:['Inga idéer parkerade', 'Lägg sådant du kanske vill göra här — det stör ingen annan lista.'] },
  { id:'logbook',  name:'Loggbok',       icon:'i-book',     c:'#5DAE6B',
    empty:['Inget avklarat ännu', 'Bockade uppgifter hamnar här.'] },
];
const listById = id => LISTS.find(l => l.id === id);

/* ── datum ───────────────────────────────────────────────── */
const keyOf  = d => `${d.getFullYear()}-${p2(d.getMonth()+1)}-${p2(d.getDate())}`;
const today0 = () => { const d = new Date(); d.setHours(0,0,0,0); return d; };
const tkey   = () => keyOf(today0());
const keyAdd = n => { const d = today0(); d.setDate(d.getDate() + n); return keyOf(d); };
const isDate = v => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v);
const keyDate = k => { const [y,m,d] = k.split('-').map(Number); return new Date(y, m-1, d); };
const dayDiff = k => Math.round((keyDate(k) - today0()) / DAY);
const WD = ['söndag','måndag','tisdag','onsdag','torsdag','fredag','lördag'];
const MO = ['jan','feb','mars','apr','maj','juni','juli','aug','sep','okt','nov','dec'];
const cap = s => s.charAt(0).toUpperCase() + s.slice(1);

function fmtDay(k){
  const n = dayDiff(k);
  if (n === 0)  return 'Idag';
  if (n === 1)  return 'I morgon';
  if (n === -1) return 'I går';
  const d = keyDate(k);
  if (n > 1 && n < 7) return cap(WD[d.getDay()]);
  const y = d.getFullYear() !== new Date().getFullYear() ? ` ${d.getFullYear()}` : '';
  return `${d.getDate()} ${MO[d.getMonth()]}${y}`;
}
function dueText(k){
  const n = dayDiff(k);
  if (n < 0)   return `${-n} ${-n === 1 ? 'dag' : 'dagar'} sen`;
  if (n === 0) return 'Idag';
  if (n === 1) return 'I morgon';
  if (n <= 14) return `om ${n} dagar`;
  return fmtDay(k);
}

/* ── modellen ────────────────────────────────────────────── */
const isHead  = t => t.type === 'heading';
const byId    = id => S.tasks.find(t => t.id === id) || null;
const projById = id => S.projects.find(p => p.id === id) || null;
const catOrNull = id => CATS.find(c => c.id === id) || null;
const filed   = t => !!(t.catId || t.projectId);
const openOf  = pid => S.tasks.filter(t => !isHead(t) && t.projectId === pid && !t.done).length;
const allOf   = pid => S.tasks.filter(t => !isHead(t) && t.projectId === pid).length;

/* Uppgiftens färg: områdets, projektets områdes, annars inkorgsblått. */
function rowColor(t){
  const c = catOrNull(t.catId) || catOrNull(projById(t.projectId)?.catId);
  return c ? c.c : '#5B8DEF';
}

/* Hör posten hemma i listan? Enda stället som vet vad listorna betyder. */
function inList(t, id){
  const K = tkey();
  if (t.done) return id === 'logbook';
  const late = isDate(t.deadline) && t.deadline <= K;
  switch (id){
    case 'inbox':    return !filed(t);
    // en deadline som gått ut tränger sig in i Idag, precis som i Things
    case 'today':    return (isDate(t.when) && t.when <= K) || (late && t.when !== 'someday');
    case 'upcoming': return isDate(t.when) && t.when > K;
    case 'anytime':  return filed(t) && t.when !== 'someday' && !(isDate(t.when) && t.when > K);
    case 'someday':  return t.when === 'someday';
  }
  return false;
}
function listItems(id){
  if (id === 'logbook'){
    return S.tasks.filter(t => !isHead(t) && t.done)
      .sort((a, b) => (b.completedAt || 0) - (a.completedAt || 0)).slice(0, 200);
  }
  const ps = S.projects.filter(p => !p.done && inList(p, id));
  const ts = S.tasks.filter(t => !isHead(t) && !t.done && inList(t, id));
  return [...ps.map(p => ({ ...p, _proj: true })), ...ts];
}
const listCount = id => id === 'logbook' ? 0 : listItems(id).length;

/* ── navigeringsstack ────────────────────────────────────── */
let stack = [{ k:'home' }];
let openId = null;          // uppgiften som står uppslagen
let findQ = '';
const topv = () => stack[stack.length - 1];
function pushView(v){ stack.push(v); openId = null; findQ = ''; renderLists(); scrollTop(); }
function popView(){ if (stack.length > 1){ stack.pop(); openId = null; renderLists(); scrollTop(); } }
function scrollTop(){ $('.stage').scrollTo({ top:0 }); }

/* ── rendering ───────────────────────────────────────────── */
function renderLists(){
  const v = topv(), head = $('#listHead'), body = $('#listBody');
  if (!head) return;
  if      (v.k === 'home') renderHome(head, body);
  else if (v.k === 'list') renderSmart(head, body, v.id);
  else if (v.k === 'area') renderArea(head, body, v.id);
  else if (v.k === 'proj') renderProject(head, body, v.id);
  else { stack = [{ k:'home' }]; renderHome(head, body); }
  // Ett öppet kort ritas om som alla andra rader, men dess fält är levande
  // element. Utan den här raden tappade titeln och anteckningarna sina
  // lyssnare så fort man satte ett datum — och vidare skrivning försvann.
  if (openId){
    const row = $(`.todo[data-id="${openId}"]`), t = byId(openId);
    if (row && t){ wireCard(row, t); row.querySelectorAll('textarea').forEach(autoGrow); }
    else openId = null;
  }
}

function headHtml(o){
  const back = stack.length > 1
    ? `<button class="lh__back" data-act="back" type="button" aria-label="Tillbaka"><svg class="ic"><use href="#i-back"></use></svg></button>` : '';
  const ic = o.pie != null
    ? pieHtml(o.pie, 30)
    : `<span class="lh__ic"><svg class="ic"><use href="#${o.icon}"></use></svg></span>`;
  const n = o.count ? `<span class="lh__c">${o.count}</span>` : '';
  return `<div class="lhead" style="--lc:${o.c}">${back}${ic}<h1 class="lh__t">${escapeHtml(o.name)}</h1>${n}</div>`
       + (o.sub ? `<p class="lh__sub">${escapeHtml(o.sub)}</p>` : '');
}
function pieHtml(frac, size = 19){
  const r = 7.4, C2 = 2 * Math.PI * r;
  if (frac >= 1) return `<svg class="pie" style="width:${size}px;height:${size}px" viewBox="0 0 20 20"><circle class="pie__done" cx="10" cy="10" r="9"/><path d="M6 10.2 8.9 13 14 7.6" fill="none" stroke="var(--surface)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" transform="rotate(90 10 10)"/></svg>`;
  return `<svg class="pie" style="width:${size}px;height:${size}px" viewBox="0 0 20 20">
    <circle class="pie__bg" cx="10" cy="10" r="${r}"/>
    <circle class="pie__fg" cx="10" cy="10" r="${r}" stroke-dasharray="${(C2*frac).toFixed(2)} ${C2.toFixed(2)}"/></svg>`;
}

/* ── hemmet: listorna och områdena ───────────────────────── */
function renderHome(head, body){
  head.innerHTML = `<div class="lhead"><h1 class="lh__t">Listor</h1></div>
    <div class="find">
      <svg class="ic"><use href="#i-search"></use></svg>
      <input id="findInput" type="search" placeholder="Sök uppgifter och projekt" value="${escapeHtml(findQ)}"
             autocomplete="off" autocorrect="off" spellcheck="false" enterkeyhint="search">
      ${findQ ? `<button class="find__x" data-act="findclear" type="button" aria-label="Rensa"><svg class="ic"><use href="#i-x"></use></svg></button>` : ''}
    </div>`;
  const inp = $('#findInput');
  inp.addEventListener('input', () => { findQ = inp.value; renderHomeBody(body); });
  renderHomeBody(body);
}
function renderHomeBody(body){
  if (findQ.trim()){ renderHits(body); return; }
  const lists = LISTS.map(l => {
    const n = listCount(l.id);
    return `<button class="grow" data-act="golist" data-id="${l.id}" type="button" style="--lc:${l.c}">
      <span class="grow__ic"><svg class="ic"><use href="#${l.icon}"></use></svg></span>
      <span class="grow__n">${l.name}</span>
      ${n ? `<span class="grow__c">${n}</span>` : ''}
      <svg class="ic grow__chev"><use href="#i-chev"></use></svg></button>`;
  }).join('');

  const areas = CATS.map(c => {
    const projs = S.projects.filter(p => p.catId === c.id && !p.done);
    const n = S.tasks.filter(t => !isHead(t) && t.catId === c.id && !t.done && t.when !== 'someday').length;
    const rows = projs.map(p => {
      const tot = allOf(p.id), dn = tot - openOf(p.id);
      return `<button class="grow grow--sub" data-act="goproj" data-id="${p.id}" type="button" style="--lc:${c.c}">
        ${pieHtml(tot ? dn / tot : 0)}
        <span class="grow__n">${escapeHtml(p.title)}</span>
        ${tot ? `<span class="grow__c">${dn}/${tot}</span>` : ''}
        <svg class="ic grow__chev"><use href="#i-chev"></use></svg></button>`;
    }).join('');
    return `<button class="grow" data-act="goarea" data-id="${c.id}" type="button" style="--lc:${c.c}">
      <span class="grow__ic"><svg class="ic"><use href="#${c.icon}"></use></svg></span>
      <span class="grow__n">${c.name}</span>
      ${n ? `<span class="grow__c">${n}</span>` : ''}
      <svg class="ic grow__chev"><use href="#i-chev"></use></svg></button>` + rows;
  }).join('');

  body.innerHTML = `<div class="group">${lists}</div>
    <p class="slabel">Livsområden</p>
    <div class="group">${areas}</div>`;
}

/* ── sökträffar ──────────────────────────────────────────── */
function renderHits(body){
  const q = findQ.trim().toLowerCase();
  const hitT = S.tasks.filter(t => !isHead(t) &&
    (t.title.toLowerCase().includes(q) || (t.notes || '').toLowerCase().includes(q)
     || (t.tags || []).some(x => x.toLowerCase().includes(q)))).slice(0, 40);
  const hitP = S.projects.filter(p => p.title.toLowerCase().includes(q));
  if (!hitT.length && !hitP.length){
    body.innerHTML = `<div class="empty"><b>Ingen träff</b>Inget som heter "${escapeHtml(findQ.trim())}".</div>`;
    return;
  }
  const ph = hitP.map(p => {
    const c = catOrNull(p.catId), tot = allOf(p.id), dn = tot - openOf(p.id);
    return `<button class="grow" data-act="goproj" data-id="${p.id}" type="button" style="--lc:${c ? c.c : '#5B8DEF'}">
      ${pieHtml(tot ? dn / tot : 0)}<span class="grow__n">${escapeHtml(p.title)}</span>
      <svg class="ic grow__chev"><use href="#i-chev"></use></svg></button>`;
  }).join('');
  body.innerHTML =
    (ph ? `<p class="slabel">Projekt</p><div class="group">${ph}</div>` : '') +
    (hitT.length ? `<p class="slabel">Uppgifter</p><div class="group hit">${hitT.map(todoRow).join('')}</div>` : '');
}

/* ── en smart lista ──────────────────────────────────────── */
function renderSmart(head, body, id){
  const l = listById(id); if (!l){ popView(); return; }
  const items = listItems(id);
  head.innerHTML = headHtml({ name:l.name, icon:l.icon, c:l.c, count: id === 'logbook' ? 0 : items.length });

  if (!items.length){ body.innerHTML = emptyHtml(l.empty); return; }

  if (id === 'upcoming' || id === 'logbook'){ body.innerHTML = dayGroups(items, id, l.c); return; }

  if (id === 'today'){
    const dayT = items.filter(t => !t.evening), eve = items.filter(t => t.evening);
    body.innerHTML =
      (dayT.length ? `<div class="group">${dayT.map(itemRow).join('')}</div>` : '') +
      (eve.length ? `<p class="slabel"><svg class="ic"><use href="#i-moon"></use></svg>I kväll</p>
         <div class="group">${eve.map(itemRow).join('')}</div>` : '');
    return;
  }
  body.innerHTML = `<div class="group">${items.map(itemRow).join('')}</div>`;
}
function dayGroups(items, id, c){
  const key = t => id === 'logbook' ? dayKey(t.completedAt || t.createdAt || Date.now()) : t.when;
  const map = new Map();
  items.forEach(t => { const k = key(t); if (!map.has(k)) map.set(k, []); map.get(k).push(t); });
  const keys = [...map.keys()].sort();
  if (id === 'logbook') keys.reverse();
  return keys.map(k => {
    const d = keyDate(k), date = `${d.getDate()} ${MO[d.getMonth()]}`, wd = cap(WD[d.getDay()]);
    const main = fmtDay(k);
    // underrubriken fyller i det rubriken inte redan sagt
    const sub = main === date ? wd : main === wd ? date : `${wd} · ${date}`;
    return `<div class="dgroup ${k === tkey() ? 'is-today' : ''}" data-day="${k}">
      <div class="dgroup__h"><span class="dgroup__d">${main}</span><span class="dgroup__w">${sub}</span></div>
      <div class="group">${map.get(k).map(itemRow).join('')}</div></div>`;
  }).join('');
}
const emptyHtml = ([t, d]) => `<div class="empty"><b>${t}</b>${d}</div>`;
const itemRow = x => x._proj ? projRow(x) : todoRow(x);

/* ── ett område ──────────────────────────────────────────── */
function renderArea(head, body, id){
  const c = catOrNull(id); if (!c){ popView(); return; }
  const projs = S.projects.filter(p => p.catId === id && !p.done);
  const loose = S.tasks.filter(t => !isHead(t) && t.catId === id && !t.projectId && !t.done && t.when !== 'someday');
  const some  = S.tasks.filter(t => !isHead(t) && t.catId === id && !t.projectId && !t.done && t.when === 'someday');
  head.innerHTML = headHtml({ name:c.name, icon:c.icon, c:c.c, count:loose.length + projs.length });

  const ph = projs.map(p => {
    const tot = allOf(p.id), dn = tot - openOf(p.id);
    return `<button class="grow" data-act="goproj" data-id="${p.id}" type="button" style="--lc:${c.c}">
      ${pieHtml(tot ? dn / tot : 0)}<span class="grow__n">${escapeHtml(p.title)}</span>
      ${tot ? `<span class="grow__c">${dn}/${tot}</span>` : ''}
      <svg class="ic grow__chev"><use href="#i-chev"></use></svg></button>`;
  }).join('');

  body.innerHTML =
    `<div class="group">${ph}<button class="grow" data-act="newproj" type="button" style="--lc:${c.c}">
       <span class="grow__ic"><svg class="ic"><use href="#i-plus"></use></svg></span>
       <span class="grow__n" style="color:var(--lc)">Nytt projekt</span></button></div>` +
    (loose.length ? `<p class="slabel">Uppgifter</p><div class="group">${loose.map(todoRow).join('')}</div>`
      : !projs.length ? emptyHtml(['Tomt här', `Lägg det du vill lägga tid på i ${c.name}.`]) : '') +
    (some.length ? `<p class="slabel"><svg class="ic"><use href="#i-box"></use></svg>Någon gång</p>
       <div class="group">${some.map(todoRow).join('')}</div>` : '');
}

/* ── ett projekt ─────────────────────────────────────────── */
function renderProject(head, body, id){
  const p = projById(id); if (!p){ popView(); return; }
  const c = catOrNull(p.catId);
  const col = c ? c.c : '#5B8DEF';
  const items = S.tasks.filter(t => t.projectId === id && (isHead(t) || !t.done));
  const tot = allOf(id), dn = tot - openOf(id);
  head.innerHTML = headHtml({ name:p.title, pie: tot ? dn / tot : 0, c:col,
    sub: [c ? c.name : null, tot ? `${dn} av ${tot} klara` : null].filter(Boolean).join(' · ') });

  const done = S.tasks.filter(t => !isHead(t) && t.projectId === id && t.done);
  const rows = items.length
    ? items.map(t => isHead(t) ? headingRow(t, col) : todoRow(t)).join('')
    : '';
  body.innerHTML = `<div class="group" id="projRows" style="--lc:${col}">${rows}</div>` +
    (!items.length ? emptyHtml(['Inga steg ännu', 'Tryck på plusset — dra det åt vänster för en rubrik.']) : '') +
    (done.length ? `<p class="slabel">Klart (${done.length})</p>
       <div class="group">${done.slice(0, 30).map(todoRow).join('')}</div>` : '') +
    `<div class="pbtns" style="--lc:${col};margin:16px 2px 0">
       <button class="pb" data-act="projwhen" type="button"><svg class="ic"><use href="#i-calendar"></use></svg>${p.when ? whenLabel(p) : 'Planera projektet'}</button>
       <button class="pb pb--del" data-act="projdel" type="button"><svg class="ic"><use href="#i-trash"></use></svg>Ta bort projektet</button>
     </div>`;
}
function headingRow(h, col){
  return `<div class="phead" data-head="${h.id}" style="--lc:${col}">
    <input class="phead__t" value="${escapeHtml(h.title)}" placeholder="Rubrik" maxlength="60" data-act="headedit">
    <button class="phead__x" data-act="headdel" type="button" aria-label="Ta bort rubrik"><svg class="ic"><use href="#i-x"></use></svg></button></div>`;
}

/* ── raderna ─────────────────────────────────────────────── */
function projRow(p){
  const c = catOrNull(p.catId), col = c ? c.c : '#5B8DEF';
  const tot = allOf(p.id), dn = tot - openOf(p.id);
  return `<button class="grow" data-act="goproj" data-id="${p.id}" type="button" style="--lc:${col}">
    ${pieHtml(tot ? dn / tot : 0)}<span class="grow__n">${escapeHtml(p.title)}</span>
    ${tot ? `<span class="grow__c">${dn}/${tot}</span>` : ''}
    <svg class="ic grow__chev"><use href="#i-chev"></use></svg></button>`;
}
function todoRow(t){
  const open = openId === t.id;
  return `<div class="todo ${t.done ? 'is-done' : ''} ${open ? 'is-open' : ''}" data-id="${t.id}" style="--lc:${rowColor(t)}">
    <button class="tbox" data-act="done" type="button" aria-label="${t.done ? 'Ångra' : 'Markera klar'}"><svg class="ic"><use href="#i-check"></use></svg></button>
    <div class="tmain" data-act="open">${open ? titleEdit(t) : `<div class="tt">${escapeHtml(t.title)}</div>${metaHtml(t)}`}</div>
    ${t.done ? '' : `<button class="tgo" data-act="focus" type="button" aria-label="Fokusera på den här"><svg class="ic"><use href="#i-play"></use></svg></button>`}
    <div class="tpanel"><div class="tpanel__in"><div class="tpanel__pad">${open ? cardHtml(t) : ''}</div></div></div>
  </div>`;
}
const titleEdit = t => `<textarea class="tedit" rows="1" maxlength="140" placeholder="Vad ska du göra?" data-act="title">${escapeHtml(t.title)}</textarea>`;

function metaHtml(t){
  const m = [];
  const v = topv();
  const p = projById(t.projectId);
  if (p && !(v.k === 'proj' && v.id === p.id))
    m.push(`<span class="mchip mchip--proj"><svg class="ic"><use href="#i-chev"></use></svg>${escapeHtml(p.title)}</span>`);
  else if (!p && t.catId && v.k !== 'area'){
    const c = catOrNull(t.catId);
    if (c) m.push(`<span class="mchip mchip--proj"><svg class="ic"><use href="#${c.icon}"></use></svg>${escapeHtml(c.short)}</span>`);
  }
  // datumet visas bara där det bär information
  if (isDate(t.when) && !t.done && v.id !== 'today' && v.id !== 'upcoming')
    m.push(`<span class="mchip"><svg class="ic"><use href="#i-calendar"></use></svg>${fmtDay(t.when)}</span>`);
  if (t.when === 'someday' && v.id !== 'someday')
    m.push(`<span class="mchip"><svg class="ic"><use href="#i-box"></use></svg>Någon gång</span>`);
  if (t.evening && v.id !== 'today')
    m.push(`<span class="mchip"><svg class="ic"><use href="#i-moon"></use></svg>I kväll</span>`);
  if (isDate(t.deadline) && !t.done)
    m.push(`<span class="mchip mchip--due ${dayDiff(t.deadline) > 2 ? 'is-soft' : ''}"><svg class="ic"><use href="#i-flag"></use></svg>${dueText(t.deadline)}</span>`);
  const ck = t.checklist || [];
  if (ck.length) m.push(`<span class="mchip"><svg class="ic"><use href="#i-check"></use></svg>${ck.filter(x => x.done).length}/${ck.length}</span>`);
  if ((t.notes || '').trim()) m.push(`<span class="mchip"><svg class="ic"><use href="#i-notes"></use></svg></span>`);
  if (t.focusedMs) m.push(`<span class="mchip mchip--focus"><svg class="ic"><use href="#i-clock"></use></svg>${fmtShort(t.focusedMs)}</span>`);
  (t.tags || []).forEach(x => m.push(`<span class="mchip mchip--tag">${escapeHtml(x)}</span>`));
  return m.length ? `<div class="tmeta">${m.join('')}</div>` : '';
}

/* ── kortet ──────────────────────────────────────────────── */
function whenLabel(t){
  if (t.when === 'someday') return 'Någon gång';
  if (isDate(t.when)) return t.evening && t.when === tkey() ? 'I kväll' : fmtDay(t.when);
  return 'När';
}
function cardHtml(t){
  const ck = t.checklist || [];
  const p = projById(t.projectId), c = catOrNull(t.catId);
  const where = p ? p.title : c ? c.short : 'Lägg i…';
  return `<textarea class="tnotes" rows="1" placeholder="Anteckningar" data-act="notes">${escapeHtml(t.notes || '')}</textarea>
    <div class="cklist">${ck.map(ckHtml).join('')}
      <button class="ckadd" data-act="ckadd" type="button"><svg class="ic"><use href="#i-plus"></use></svg>Lägg till steg</button>
    </div>
    <div class="pbtns">
      <button class="pb ${t.when ? 'is-set' : ''}" data-act="when" type="button"><svg class="ic"><use href="#i-calendar"></use></svg>${whenLabel(t)}</button>
      <button class="pb pb--due ${t.deadline ? 'is-set' : ''}" data-act="due" type="button"><svg class="ic"><use href="#i-flag"></use></svg>${isDate(t.deadline) ? fmtDay(t.deadline) : 'Deadline'}</button>
      <button class="pb ${(t.tags || []).length ? 'is-set' : ''}" data-act="tags" type="button"><svg class="ic"><use href="#i-tag"></use></svg>${(t.tags || []).length ? t.tags.join(', ') : 'Taggar'}</button>
      <button class="pb ${filed(t) ? 'is-set' : ''}" data-act="move" type="button"><svg class="ic"><use href="#i-layers"></use></svg>${escapeHtml(where)}</button>
      <button class="pb" data-act="dur" type="button"><svg class="ic"><use href="#i-clock"></use></svg>${fmtDur(t.durationMs)} per pass</button>
      <button class="pb pb--del" data-act="del" type="button" aria-label="Ta bort"><svg class="ic"><use href="#i-trash"></use></svg></button>
    </div>`;
}
const ckHtml = x => `<div class="ck ${x.done ? 'is-done' : ''}" data-ck="${x.id}">
  <button class="ckbox" data-act="cktoggle" type="button" aria-label="Markera steg"><svg class="ic"><use href="#i-check"></use></svg></button>
  <input class="ck__t" value="${escapeHtml(x.title)}" placeholder="Steg" maxlength="100" data-act="cktitle" enterkeyhint="next">
  <button class="ck__x" data-act="ckdel" type="button" aria-label="Ta bort steg"><svg class="ic"><use href="#i-x"></use></svg></button></div>`;

/* ── öppna och stänga ett kort ───────────────────────────── */
function autoGrow(el){ el.style.height = 'auto'; el.style.height = el.scrollHeight + 'px'; }
function openTodo(id){
  if (openId === id) return;
  closeTodo();
  const t = byId(id); if (!t || t.done) return;
  const row = $(`.todo[data-id="${id}"]`); if (!row) return;
  openId = id;
  row.querySelector('.tmain').innerHTML = titleEdit(t);
  row.querySelector('.tpanel__pad').innerHTML = cardHtml(t);
  wireCard(row, t, true);
  requestAnimationFrame(() => {
    row.classList.add('is-open');
    row.querySelectorAll('textarea').forEach(autoGrow);
    setTimeout(() => row.scrollIntoView({ block:'nearest', behavior:'smooth' }), 240);
  });
  buzz(6);
}
function closeTodo(){
  if (!openId) return;
  const id = openId, row = $(`.todo[data-id="${id}"]`);
  openId = null;
  const t = byId(id);
  // en uppgift utan namn är en ångrad uppgift, inte en tom rad
  if (t && !t.title.trim()){ S.tasks = S.tasks.filter(x => x.id !== id); save(); renderLists(); return; }
  if (!row || !t) return;
  row.classList.remove('is-open');
  row.querySelector('.tmain').innerHTML = `<div class="tt">${escapeHtml(t.title)}</div>${metaHtml(t)}`;
  setTimeout(() => {
    const pad = row.querySelector('.tpanel__pad');
    if (pad && !row.classList.contains('is-open')) pad.innerHTML = '';
  }, 340);
}

function wireCard(row, t, focus){
  const q = s => row.querySelector(s);
  const title = q('.tedit');
  if (title){
    title.addEventListener('input', () => { autoGrow(title); t.title = title.value; save(); });
    title.addEventListener('keydown', e => { if (e.key === 'Enter'){ e.preventDefault(); title.blur(); closeTodo(); } });
    if (focus) setTimeout(() => { title.focus(); title.setSelectionRange(title.value.length, title.value.length); }, 60);
  }
  const notes = q('.tnotes');
  if (notes) notes.addEventListener('input', () => { autoGrow(notes); t.notes = notes.value; save(); });

  row.querySelectorAll('.ck').forEach(el => {
    const ck = (t.checklist || []).find(x => x.id === el.dataset.ck); if (!ck) return;
    el.querySelector('.ck__t').addEventListener('input', e => { ck.title = e.target.value; save(); });
    el.querySelector('.ck__t').addEventListener('keydown', e => {
      if (e.key !== 'Enter') return;
      e.preventDefault(); addCheck(t, row, el);
    });
  });
}
function addCheck(t, row, after){
  t.checklist = t.checklist || [];
  const item = { id:uid(), title:'', done:false };
  const at = after ? t.checklist.findIndex(x => x.id === after.dataset.ck) + 1 : t.checklist.length;
  t.checklist.splice(at, 0, item);
  save();
  const host = row.querySelector('.cklist');
  const el = document.createElement('div');
  el.innerHTML = ckHtml(item);
  const node = el.firstElementChild;
  host.insertBefore(node, after ? after.nextSibling : host.querySelector('.ckadd'));
  wireCard(row, t);
  node.querySelector('.ck__t').focus();
  buzz(5);
}

/* ── alla klick i listvyn på ett ställe ──────────────────── */
/* Delegerat och kopplat EN gång. Vyn ritas om vid varje bock och
   varje byte — en lyssnare per omritning hade blivit hundratals. */
function onListClick(ev){
  // utanför kortet = klart med kortet
  if (openId && !ev.target.closest('.todo.is-open')) closeTodo();
  const btn = ev.target.closest('[data-act]'); if (!btn) return;
  const act = btn.dataset.act;
  const row = btn.closest('.todo');
  const t = row ? byId(row.dataset.id) : null;

  switch (act){
    case 'back':      buzz(8); closeTodo(); popView(); return;
    case 'findclear': findQ = ''; renderLists(); return;
    case 'golist':    buzz(8); pushView({ k:'list', id:btn.dataset.id }); return;
    case 'goarea':    buzz(8); pushView({ k:'area', id:btn.dataset.id }); return;
    case 'goproj':    buzz(8); pushView({ k:'proj', id:btn.dataset.id }); return;
    case 'newproj':   newProject(topv().id); return;
    case 'projwhen':  openSheet('when', { proj: projById(topv().id) }); return;
    case 'projdel':   delProject(topv().id); return;
    case 'headdel':   delHeading(btn.closest('.phead').dataset.head); return;
  }
  if (!t) return;

  switch (act){
    case 'done':  toggleDone(t, row); break;
    case 'open':  if (t.done) return; openId === t.id ? closeTodo() : openTodo(t.id); break;
    case 'focus': focusOn(t); break;
    case 'when':  openSheet('when', { task:t }); break;
    case 'due':   openSheet('due',  { task:t }); break;
    case 'tags':  openSheet('tags', { task:t }); break;
    case 'move':  openSheet('move', { task:t }); break;
    case 'dur':   openSheet('dur',  { task:t }); break;
    case 'del':
      openId = null;
      S.tasks = S.tasks.filter(x => x.id !== t.id);
      if (T.taskId === t.id) T.taskId = null;
      buzz(12); save(); renderLists(); renderFocus(); toast('Uppgiften är borta');
      break;
    case 'ckadd':     addCheck(t, row, null); break;
    case 'cktoggle': {
      const el = btn.closest('.ck');
      const ck = (t.checklist || []).find(x => x.id === el.dataset.ck); if (!ck) return;
      ck.done = !ck.done; el.classList.toggle('is-done', ck.done);
      buzz(ck.done ? 8 : 5); save();
      break;
    }
    case 'ckdel': {
      const el = btn.closest('.ck');
      t.checklist = (t.checklist || []).filter(x => x.id !== el.dataset.ck);
      el.remove(); buzz(8); save();
      break;
    }
  }
}

/* Bocken: raden kvitterar, glider undan och listan sluter sig. */
function toggleDone(t, row){
  const now = !t.done;
  t.done = now; t.completedAt = now ? Date.now() : null;
  if (now && T.taskId === t.id) T.taskId = null;
  buzz(now ? [10, 40, 16] : 8);
  save();
  if (now && row){
    openId = null;
    row.classList.add('is-done');
    sndCheck();
    setTimeout(() => { row.classList.add('is-leaving');
      setTimeout(() => { renderLists(); renderFocus(); renderCatDots(); renderHeader(); }, 300); }, 240);
  } else { renderLists(); renderFocus(); renderCatDots(); }
}
/* Ett litet kvitto — samma familj som detentljudet, inte en pipsignal. */
function sndCheck(){
  if (!S.settings.sound) return;
  tone(1046.5, 0, .09, .07, 'triangle');
  tone(1568, .045, .14, .05, 'sine');
}

/* ── uppgiften möter timern ──────────────────────────────── */
function focusOn(t){
  if (timeLocked()) return;
  const area = t.catId || projById(t.projectId)?.catId;
  // Utan livsområde finns ingen ärlig plats att bokföra tiden på.
  if (!area){ openSheet('move', { task:t, then:'focus' }); return; }
  T.catId = area;
  T.taskId = t.id; T.durationMs = t.durationMs;
  T.elapsedBefore = 0; T.status = 'idle'; T.startedAt = 0;
  closeTodo(); buzz(10); save(); go('focus'); renderFocus();
}

/* ── projekt och rubriker ────────────────────────────────── */
function newProject(catId){ openSheet('project', { catId }); }
function createProject(catId, title){
  const p = { id:uid(), catId, title:title.trim(), notes:'', when:null, deadline:null,
              done:false, completedAt:null, createdAt:Date.now() };
  S.projects.push(p); buzz(12); save(); pushView({ k:'proj', id:p.id });
}
function delProject(id){
  const p = projById(id); if (!p) return;
  const n = allOf(id);
  if (!confirm(n ? `Ta bort "${p.title}" och ${n} uppgifter?` : `Ta bort "${p.title}"?`)) return;
  S.tasks = S.tasks.filter(t => t.projectId !== id);
  S.projects = S.projects.filter(x => x.id !== id);
  buzz(14); save(); popView(); toast('Projektet är borta');
}
function delHeading(id){
  S.tasks = S.tasks.filter(t => t.id !== id);
  buzz(10); save(); renderLists();
}

/* ── magiska plusset ─────────────────────────────────────── */
/* Ett tryck lägger en uppgift sist i listan. Lyfter man knappen och
   drar hamnar uppgiften där man släpper — och åt vänster i ett
   projekt blir det en rubrik i stället. */
function initMagic(){
  const btn = $('#magicPlus'), line = $('#insertLine'), hint = $('#magicHint');
  let pid = null, x0 = 0, y0 = 0, moved = false, slot = null, heading = false;

  const rowsNow = () => [...$$('#listBody .todo, #listBody .phead')];

  function aim(e){
    const inProj = topv().k === 'proj';
    heading = inProj && e.clientX < 76;
    const rows = rowsNow();
    if (heading){
      const r = rows.length ? rows[Math.min(rows.length - 1, nearest(rows, e.clientY))] : null;
      place(r, true);
      slot = { idx: nearest(rows, e.clientY), rows };
      hint.textContent = 'Ny rubrik';
      return;
    }
    if (!rows.length){ line.hidden = true; slot = { idx:0, rows }; hint.textContent = 'Ny uppgift'; return; }
    const i = nearest(rows, e.clientY);
    slot = { idx:i, rows };
    place(rows[Math.min(i, rows.length - 1)], false, i >= rows.length);
    const day = (rows[Math.min(i, rows.length - 1)].closest('.dgroup') || {}).dataset?.day;
    hint.textContent = day ? fmtDay(day) : 'Ny uppgift';
  }
  const nearest = (rows, y) => rows.filter(r => { const b = r.getBoundingClientRect(); return y > b.top + b.height / 2; }).length;

  function place(row, isHeading, below){
    if (!row){ line.hidden = true; return; }
    const b = row.getBoundingClientRect();
    line.hidden = false;
    line.classList.toggle('is-heading', !!isHeading);
    line.style.top = `${(below ? b.bottom : b.top) - 1}px`;
    line.style.left = `${b.left + 12}px`;
    line.style.width = `${b.width - 24}px`;
  }

  btn.addEventListener('pointerdown', e => {
    if (pid !== null) return;
    pid = e.pointerId; moved = false; slot = null; heading = false;
    x0 = e.clientX; y0 = e.clientY;
    try { btn.setPointerCapture(pid); } catch(err){}
    buzz(6);
  });
  btn.addEventListener('pointermove', e => {
    if (e.pointerId !== pid) return;
    const dx = e.clientX - x0, dy = e.clientY - y0;
    if (!moved && Math.hypot(dx, dy) < 7) return;
    if (!moved){ moved = true; btn.classList.add('is-lift'); closeTodo(); renderLists(); }
    btn.style.transform = `translate(${dx}px, ${dy}px) scale(1.06)`;
    aim(e);
  });
  const drop = e => {
    if (e.pointerId !== pid) return;
    pid = null;
    btn.classList.remove('is-lift'); btn.style.transform = '';
    line.hidden = true; hint.textContent = '';
    try { btn.releasePointerCapture(e.pointerId); } catch(err){}
    if (!moved){ createAt(null, false); return; }
    createAt(slot, heading);
  };
  ['pointerup','pointercancel','lostpointercapture'].forEach(ev => btn.addEventListener(ev, drop));
}

/* Var i S.tasks hamnar den nya posten? Positionen i arrayen ÄR ordningen. */
function globalIndex(slot){
  if (!slot || !slot.rows.length) return S.tasks.length;
  const rows = slot.rows, i = slot.idx;
  if (i >= rows.length){
    const last = byId(rows[rows.length - 1].dataset.id || rows[rows.length - 1].dataset.head);
    return last ? S.tasks.indexOf(last) + 1 : S.tasks.length;
  }
  const ref = byId(rows[i].dataset.id || rows[i].dataset.head);
  return ref ? S.tasks.indexOf(ref) : S.tasks.length;
}
function createAt(slot, heading){
  closeTodo();
  const v = topv();
  if (v.k === 'home'){ pushView({ k:'list', id:'inbox' }); setTimeout(() => createAt(null, false), 60); return; }
  const at = globalIndex(slot);

  if (heading && v.k === 'proj'){
    S.tasks.splice(at, 0, { id:uid(), type:'heading', projectId:v.id, title:'' });
    buzz(12); save(); renderLists();
    setTimeout(() => $$('#listBody .phead__t').find(el => !el.value)?.focus(), 60);
    return;
  }

  const d = { catId:null, projectId:null, when:null, evening:false };
  if (v.k === 'list'){
    if (v.id === 'today')    d.when = tkey();
    if (v.id === 'someday')  d.when = 'someday';
    if (v.id === 'upcoming') d.when = keyAdd(1);
  }
  if (v.k === 'area') d.catId = v.id;
  if (v.k === 'proj'){ const p = projById(v.id); d.projectId = v.id; d.catId = p ? p.catId : null; }
  // släppte man på en dag i Kommande ärver uppgiften den dagen
  if (slot && slot.rows.length){
    const r = slot.rows[Math.min(slot.idx, slot.rows.length - 1)];
    const day = r.closest('.dgroup')?.dataset.day;
    if (day && v.id === 'upcoming') d.when = day;
    if (v.id === 'today') d.evening = !!r.closest('.group')?.previousElementSibling?.querySelector('[href="#i-moon"]');
  }

  const t = newTask(d);
  S.tasks.splice(at, 0, t);
  buzz(12); save();
  openId = t.id;
  renderLists();
  const row = $(`.todo[data-id="${t.id}"]`);
  if (row){ row.classList.add('is-open', 'todo--new'); wireCard(row, t, true);
            row.querySelectorAll('textarea').forEach(autoGrow); }
}

/* Enda stället som vet hur en uppgift ser ut när den föds. */
function newTask(over){
  return { id:uid(), catId:null, projectId:null, title:'', notes:'', checklist:[], tags:[],
           when:null, evening:false, deadline:null,
           durationMs: (S.settings.lastDurMin || 25) * 60000,
           done:false, completedAt:null, createdAt:Date.now(), focusedMs:0, sessions:0, ...over };
}


/* ── valarken: när, deadline, taggar, plats, tid ─────────── */
const PICKERS = {
  when(body, ctx){
    const o = ctx.task || ctx.proj; if (!o) return;
    $('#sheetTitle').textContent = 'När ska den göras?';
    const K = tkey(), T1 = keyAdd(1);
    const on = c => c ? 'is-on' : '';
    body.innerHTML = `<div class="pickgrid">
      <button class="pick ${on(o.when === K && !o.evening)}" data-w="today" style="--pc:#F0A92E" type="button"><svg class="ic"><use href="#i-star"></use></svg>Idag</button>
      <button class="pick ${on(o.when === K && o.evening)}" data-w="evening" style="--pc:#7C83F7" type="button"><svg class="ic"><use href="#i-moon"></use></svg>I kväll</button>
      <button class="pick ${on(o.when === T1)}" data-w="tomorrow" style="--pc:#E8734A" type="button"><svg class="ic"><use href="#i-calendar"></use></svg>I morgon</button>
      <button class="pick ${on(o.when === 'someday')}" data-w="someday" style="--pc:#B8923F" type="button"><svg class="ic"><use href="#i-box"></use></svg>Någon gång</button>
      <button class="pick pick--wide ${on(!o.when)}" data-w="clear" style="--pc:#17B588" type="button"><svg class="ic"><use href="#i-layers"></use></svg>När som helst — ingen dag</button>
    </div>
    <p class="fieldlabel" style="margin-top:16px">Eller en bestämd dag</p>
    <div class="pickdate"><input type="date" id="pickDate" value="${isDate(o.when) ? o.when : ''}"></div>`;

    const set = (when, evening) => {
      o.when = when; o.evening = !!evening;
      buzz(10); save(); closeSheet(); renderLists(); renderFocus(); renderCatDots();
    };
    body.querySelectorAll('.pick').forEach(b => b.addEventListener('click', () => {
      const w = b.dataset.w;
      if (w === 'today')    return set(tkey(), false);
      if (w === 'evening')  return set(tkey(), true);
      if (w === 'tomorrow') return set(keyAdd(1), false);
      if (w === 'someday')  return set('someday', false);
      set(null, false);
    }));
    $('#pickDate').addEventListener('change', e => { if (e.target.value) set(e.target.value, false); });
  },

  due(body, ctx){
    const o = ctx.task || ctx.proj; if (!o) return;
    $('#sheetTitle').textContent = 'Deadline';
    body.innerHTML = `<p class="muted small">En deadline är när uppgiften måste vara klar — inte när du tänkt göra den. Den som går ut tränger sig in i Idag.</p>
    <div class="pickgrid" style="margin-top:12px">
      <button class="pick" data-d="0" style="--pc:#F2445A" type="button"><svg class="ic"><use href="#i-flag"></use></svg>Idag</button>
      <button class="pick" data-d="1" style="--pc:#E8734A" type="button"><svg class="ic"><use href="#i-flag"></use></svg>I morgon</button>
      <button class="pick" data-d="7" style="--pc:#F0A92E" type="button"><svg class="ic"><use href="#i-flag"></use></svg>Om en vecka</button>
      <button class="pick ${o.deadline ? '' : 'is-on'}" data-d="x" style="--pc:#17B588" type="button"><svg class="ic"><use href="#i-x"></use></svg>Ingen</button>
    </div>
    <p class="fieldlabel" style="margin-top:16px">Eller ett datum</p>
    <div class="pickdate"><input type="date" id="pickDue" value="${isDate(o.deadline) ? o.deadline : ''}"></div>`;
    const set = v => { o.deadline = v; buzz(10); save(); closeSheet(); renderLists(); };
    body.querySelectorAll('.pick').forEach(b => b.addEventListener('click', () =>
      set(b.dataset.d === 'x' ? null : keyAdd(+b.dataset.d))));
    $('#pickDue').addEventListener('change', e => set(e.target.value || null));
  },

  tags(body, ctx){
    const t = ctx.task; if (!t) return;
    $('#sheetTitle').textContent = 'Taggar';
    const all = [...new Set(S.tasks.flatMap(x => x.tags || []))].sort();
    const draw = () => {
      body.innerHTML = `<div class="tagwrap">${all.length
        ? all.map(x => `<button class="tagc ${t.tags.includes(x) ? 'is-on' : ''}" data-t="${escapeHtml(x)}" type="button">${escapeHtml(x)}</button>`).join('')
        : '<p class="muted small">Inga taggar ännu. Skriv en nedan.</p>'}</div>
      <form class="taginput" id="tagForm" autocomplete="off">
        <input id="tagNew" type="text" placeholder="Ny tagg" maxlength="24" enterkeyhint="done">
        <button class="sheetadd__go" type="submit" aria-label="Lägg till"><svg class="ic"><use href="#i-plus"></use></svg></button>
      </form>`;
      body.querySelectorAll('.tagc').forEach(b => b.addEventListener('click', () => {
        const v = b.dataset.t;
        t.tags = t.tags.includes(v) ? t.tags.filter(x => x !== v) : [...t.tags, v];
        buzz(7); save(); draw(); renderLists();
      }));
      $('#tagForm').addEventListener('submit', e => {
        e.preventDefault();
        const v = $('#tagNew').value.trim(); if (!v) return;
        if (!all.includes(v)) all.push(v), all.sort();
        if (!t.tags.includes(v)) t.tags.push(v);
        buzz(10); save(); draw(); renderLists();
      });
    };
    draw();
  },

  move(body, ctx){
    const t = ctx.task; if (!t) return;
    $('#sheetTitle').textContent = ctx.then === 'focus' ? 'Var ska tiden bokas?' : 'Var hör den hemma?';
    const rows = [`<button class="pick pick--wide ${!filed(t) ? 'is-on' : ''}" data-m="inbox" style="--pc:#5B8DEF" type="button"><svg class="ic"><use href="#i-inbox"></use></svg>Inkorgen</button>`];
    CATS.forEach(c => {
      rows.push(`<button class="pick pick--wide ${t.catId === c.id && !t.projectId ? 'is-on' : ''}" data-m="cat:${c.id}" style="--pc:${c.c}" type="button"><svg class="ic"><use href="#${c.icon}"></use></svg>${c.name}</button>`);
      S.projects.filter(p => p.catId === c.id && !p.done).forEach(p =>
        rows.push(`<button class="pick pick--wide ${t.projectId === p.id ? 'is-on' : ''}" data-m="proj:${p.id}" style="--pc:${c.c};padding-left:34px" type="button"><svg class="ic"><use href="#i-chev"></use></svg>${escapeHtml(p.title)}</button>`));
    });
    if (ctx.then === 'focus') rows.shift();      // inkorgen är inget svar här
    body.innerHTML = `<div class="pickgrid">${rows.join('')}</div>`
      + (ctx.then === 'focus' ? '<p class="muted small" style="margin-top:12px">Passet bokförs på området du väljer. Du kan flytta uppgiften igen när som helst.</p>' : '');
    body.querySelectorAll('.pick').forEach(b => b.addEventListener('click', () => {
      const [k, v] = b.dataset.m.split(':');
      t.catId = k === 'cat' ? v : k === 'proj' ? (projById(v)?.catId || null) : null;
      t.projectId = k === 'proj' ? v : null;
      buzz(10); save(); closeSheet(); renderLists(); renderFocus(); renderCatDots();
      if (ctx.then === 'focus') setTimeout(() => focusOn(t), 280);
    }));
  },

  dur(body, ctx){
    const t = ctx.task; if (!t) return;
    $('#sheetTitle').textContent = 'Tid per pass';
    body.innerHTML = `<p class="muted small">Så lång blir timern när du startar den här uppgiften.</p>
      <div class="durpick" style="display:flex;flex-wrap:wrap;gap:7px;margin-top:12px">${PRESETS.map(m =>
        `<button class="chip ${t.durationMs === m * 60000 ? 'is-on' : ''}" data-min="${m}" type="button">${m < 60 ? m + ' min' : m / 60 + ' h'}</button>`).join('')}</div>`;
    body.querySelectorAll('.chip').forEach(b => b.addEventListener('click', () => {
      t.durationMs = +b.dataset.min * 60000;
      if (T.taskId === t.id && T.status === 'idle'){ T.durationMs = t.durationMs; paintDial(true); }
      buzz(9); save(); closeSheet(); renderLists();
    }));
  },

  project(body, ctx){
    $('#sheetTitle').textContent = 'Nytt projekt';
    const c = catOrNull(ctx.catId);
    body.innerHTML = `<form class="sheetadd" id="projForm" autocomplete="off">
        <input class="sheetadd__input" id="projName" type="text" maxlength="60" enterkeyhint="done" placeholder="Vad ska bli gjort?">
        <button class="sheetadd__go" type="submit" aria-label="Skapa"><svg class="ic"><use href="#i-plus"></use></svg></button>
      </form>
      <p class="muted small">Ett projekt är flera steg mot ett mål${c ? ` — det här hamnar i ${c.name}` : ''}.</p>`;
    $('#projForm').addEventListener('submit', e => {
      e.preventDefault();
      const v = $('#projName').value.trim(); if (!v) return;
      closeSheet(); createProject(ctx.catId, v);
    });
    setTimeout(() => $('#projName')?.focus(), 340);
  },
};

/* ── prickar på hörnplattorna ────────────────────────────── */
function renderCatDots(){
  $$('#cats .corner').forEach(el => el.classList.toggle('has-tasks',
    S.tasks.some(t => !isHead(t) && t.catId === el.dataset.id && !t.done && t.when !== 'someday')));
}

/* ── stats ───────────────────────────────────────────────── */
function renderStats(){
  const now = Date.now(), today = dayKey(now);
  const todayMs = S.sessions.filter(s => dayKey(s.endedAt) === today).reduce((a, s) => a + s.ms, 0);

  const days = Array.from({ length: 7 }, (_, i) => {
    const d = new Date(); d.setHours(0,0,0,0); d.setDate(d.getDate() - (6 - i));
    return { key: dayKey(d.getTime()), label: ['sö','må','ti','on','to','fr','lö'][d.getDay()], ts: d.getTime() };
  });
  const byDay = {}; days.forEach(d => byDay[d.key] = {});
  let weekMs = 0;
  S.sessions.forEach(s => { const k = dayKey(s.endedAt);
    if (byDay[k]){ byDay[k][s.catId] = (byDay[k][s.catId] || 0) + s.ms; weekMs += s.ms; } });

  $('#kpis').innerHTML = [
    ['Idag', fmtSplit(todayMs)],
    ['7 dagar', fmtSplit(weekMs)],
    ['Pass totalt', `<span class="kpi__v">${S.sessions.length}</span>`],
  ].map(([l, v]) => `<div class="kpi">${v}<div class="kpi__l">${l}</div></div>`).join('');

  const max = Math.max(1, ...days.map(d => Object.values(byDay[d.key]).reduce((a, b) => a + b, 0)));
  $('#week').innerHTML = days.map(d => {
    const tot = Object.values(byDay[d.key]).reduce((a, b) => a + b, 0);
    const h = Math.round((tot / max) * 100);
    const segs = CATS.filter(c => byDay[d.key][c.id])
      .map(c => `<span class="week__seg" style="height:${(byDay[d.key][c.id]/tot*100).toFixed(1)}%;background:${c.c}"></span>`).join('');
    return `<div class="week__col ${d.key === today ? 'is-today' : ''}">
      <div class="week__bar" style="height:${Math.max(h, tot ? 6 : 3)}%">${segs}</div>
      <div class="week__d">${d.label}</div></div>`;
  }).join('');
  $('#weekTotal').textContent = weekMs ? fmtDur(weekMs) : '—';

  const perCat = {}; let sum = 0;
  S.sessions.forEach(s => { if (byDay[dayKey(s.endedAt)]){ perCat[s.catId] = (perCat[s.catId] || 0) + s.ms; sum += s.ms; } });
  const top = Math.max(1, ...CATS.map(c => perCat[c.id] || 0));
  $('#balance').innerHTML = CATS.map(c => {
    const ms = perCat[c.id] || 0;
    return `<div class="bal"><div class="bal__n">${c.name}</div>
      <div class="bal__t"><div class="bal__f" style="width:${(ms/top*100).toFixed(1)}%;background:${c.c}"></div></div>
      <div class="bal__v">${ms ? fmtDur(ms) : '—'}</div></div>`;
  }).join('');
  $('#balanceMeta').textContent = sum ? 'senaste 7 dagarna' : '';

  $('#sessions').innerHTML = S.sessions.length
    ? S.sessions.slice(0, 12).map(s => {
        const c = catById(s.catId), d = new Date(s.endedAt);
        return `<div class="ses"><span class="ses__dot" style="background:${c.c}"></span>
          <span class="ses__t">${escapeHtml(s.title)}</span>
          <span class="ses__m">${fmtShort(s.ms)} · ${p2(d.getHours())}:${p2(d.getMinutes())}</span></div>`;
      }).join('')
    : '<div class="empty"><b>Inga pass ännu</b>Starta din första timer så dyker den upp här.</div>';
}
function fmtSplit(ms){
  const min = Math.round(ms / 60000);
  return min < 60 ? `<span class="kpi__v">${min}<small>min</small></span>`
                  : `<span class="kpi__v">${Math.floor(min/60)}<small>h</small> ${min%60}<small>m</small></span>`;
}
function streak(){
  const set = new Set(S.sessions.filter(s => s.ms >= MIN_MS).map(s => dayKey(s.endedAt)));
  let n = 0; const d = new Date(); d.setHours(0,0,0,0);
  if (!set.has(dayKey(d.getTime()))) d.setDate(d.getDate() - 1);
  while (set.has(dayKey(d.getTime()))){ n++; d.setDate(d.getDate() - 1); }
  return n;
}
function renderHeader(){
  const n = streak();
  $('#streakVal').textContent = n;
  $('#streakPill').classList.toggle('is-hot', n > 0);
  const today = dayKey(Date.now());
  const ms = S.sessions.filter(s => dayKey(s.endedAt) === today).reduce((a, s) => a + s.ms, 0);
  $('#todayVal').textContent = ms ? fmtDur(ms) : '0 min';
}

/* ── settings ────────────────────────────────────────────── */
const TOGGLES = [
  ['sound',     'Ljud',              'Tick när du ställer tiden, klocka när passet är slut'],
  ['haptics',   'Vibration',         'Taktil respons på telefonen'],
  ['keepAwake', 'Håll skärmen tänd','Under pågående pass. Drar mycket batteri'],
  ['notify',    'Notiser',           'Larm även när appen ligger i bakgrunden'],
];
function toggleOn(k){
  return k === 'notify' ? (S.settings.notify && notifyGranted()) : !!S.settings[k];
}
function renderSettings(){
  $('#toggles').innerHTML = TOGGLES.map(([k, t, d]) => {
    const on = k === 'haptics' ? (hasVibe && S.settings.haptics) : toggleOn(k);
    const desc = k === 'notify' && !on
      ? (notifSupported ? 'Behörighet saknas — tryck för att tillåta' : 'Stöds inte i den här webbläsaren')
      : k === 'haptics' && !hasVibe ? 'Stöds inte på iPhone — Safari saknar Vibration API'
      : d;
    return `<div class="row"><div><div class="row__t">${t}</div><div class="row__d">${desc}</div></div>
      <button type="button" class="switch ${on ? 'is-on' : ''}" data-k="${k}" role="switch"
        aria-checked="${on}" aria-label="${t}" ${k === 'haptics' && !hasVibe ? 'disabled' : ''}></button></div>`;
  }).join('');
  $$('#toggles .switch').forEach(el => el.addEventListener('click', async () => {
    const k = el.dataset.k;
    if (k === 'notify'){
      if (!notifSupported){ toast('Den här webbläsaren stöder inte notiser'); return; }
      if (!notifyGranted()){ S.settings.notify = true; save(); buzz(8); await enableNotifications(); return; }
      S.settings.notify = !S.settings.notify;
      if (!S.settings.notify) serverCancel();      // inget larm ska ligga kvar hos servern
    } else {
      S.settings[k] = !S.settings[k];
      if (k === 'keepAwake'){
        if (S.settings.keepAwake){ if (T.status === 'running') wakeOn(); }
        else wakeOff();
      }
    }
    buzz(8); save(); renderSettings();
  }));

  $$('#themeSeg button').forEach(b => {
    b.classList.toggle('is-on', b.dataset.theme === S.settings.theme);
    b.onclick = () => { S.settings.theme = b.dataset.theme; applyTheme(); renderSettings(); save(); buzz(8); };
  });

  const perm = notifSupported ? Notification.permission : 'unsupported';
  $('#notifyText').textContent = perm === 'granted' ? 'Notiser är på' : 'Aktivera notiser';
  $('#btnNotify').hidden = perm === 'granted';
  $('#notifyStatus').innerHTML =
    perm === 'granted' ? notifyCapabilityText()
  : perm === 'denied'  ? 'Notiser är blockerade i webbläsarens inställningar för den här sidan.'
  : perm === 'unsupported' ? 'Den här webbläsaren stöder inte notiser — larmet spelas i appen istället.'
  : 'Tillåt notiser så pinglar Fokus dig när passet är slut.';

  // Mätvärden från enheten — så vi slipper gissa vad iOS gör med viewporten
  const cs = getComputedStyle(document.documentElement);
  const px = v => Math.round(parseFloat(cs.getPropertyValue(v)) || 0);
  const st = matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
  const perm2 = notifSupported ? Notification.permission : 'saknas';
  const push  = 'PushManager' in window ? 'push-API finns' : 'ingen push-API';
  $('#appVersion').textContent =
    `v${VERSION} · ${innerWidth}×${innerHeight} av ${screen.width}×${screen.height}` +
    ` · marginal ${px('--sat')}/${px('--sab')} · ${st ? 'hemskärm' : 'webbläsare'}` +
    ` · notiser: ${perm2} · ${push} · vibration: ${hasVibe ? 'finns' : 'saknas'}`;
  storageInfo();
}
function notifyCapabilityText(){
  const scheduled = 'showTrigger' in (window.Notification?.prototype || {});
  return scheduled
    ? 'Larmet är schemalagt i systemet och kommer fram även om appen är helt stängd.'
    : 'Larmet visas när passet tar slut. På iPhone väcks appen inte alltid i bakgrunden — då kommer notisen så snart du öppnar Fokus igen, och tiden räknas ändå korrekt.';
}
async function enableNotifications(){
  const r = await ensureNotifyPermission(true);
  if (r === 'granted'){
    toast('Notiser aktiverade');
    pushSubscription();
    fireNow('Fokus är redo', 'Så här ser larmet ut när ett pass är klart.');
    navigator.storage?.persist?.().catch(() => {});
  } else if (r === 'denied'){
    toast('Notiser blockerade — ändra i webbläsarens inställningar');
  }
  renderSettings();
}
async function storageInfo(){
  let txt = '';
  try{
    const est = await navigator.storage?.estimate?.();
    const bytes = new Blob([localStorage.getItem(KEY) || '']).size;
    txt = `${S.tasks.length} uppgifter · ${S.sessions.length} pass · ${(bytes/1024).toFixed(1)} kB på enheten`;
    if (est && await navigator.storage.persisted?.()) txt += ' · skyddad lagring';
  } catch(e){}
  $('#storageInfo').textContent = txt;
}

/* ── install ─────────────────────────────────────────────── */
let deferredPrompt = null;
const standalone = matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
window.addEventListener('beforeinstallprompt', e => {
  e.preventDefault(); deferredPrompt = e;
  $('#installCard').hidden = false; $('#btnInstall').hidden = false; $('#iosHowto').hidden = true;
});
function initInstall(){
  if (standalone) return;
  const isIOS = /iP(hone|ad|od)/.test(navigator.userAgent) ||
                (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1
                 && !('onbeforeinstallprompt' in window));
  if (isIOS){
    $('#installCard').hidden = false;
    $('#btnInstall').hidden = true;
    $('#iosHowto').hidden = false;
    $('#installText').textContent = 'Lägg till Fokus på hemskärmen så körs den i helskärm, offline — och kan visa notiser (kräver iOS 16.4+).';
  }
  $('#btnInstall').addEventListener('click', async () => {
    if (!deferredPrompt) return;
    deferredPrompt.prompt();
    const { outcome } = await deferredPrompt.userChoice;
    if (outcome === 'accepted'){ toast('Fokus installeras…'); $('#installCard').hidden = true; }
    deferredPrompt = null;
  });
}

/* ── data export / import ────────────────────────────────── */
function initData(){
  $('#btnExport').addEventListener('click', async () => {
    const json = JSON.stringify(S, null, 2);
    const name = `fokus-backup-${dayKey(Date.now())}.json`;
    const file = new File([json], name, { type:'application/json' });
    if (navigator.canShare?.({ files:[file] })){
      try { await navigator.share({ files:[file], title:'Fokus backup' }); return; } catch(e){ if (e.name === 'AbortError') return; }
    }
    const url = URL.createObjectURL(new Blob([json], { type:'application/json' }));
    const a = document.createElement('a'); a.href = url; a.download = name; a.click();
    setTimeout(() => URL.revokeObjectURL(url), 4000);
    toast('Backup exporterad');
  });
  $('#btnImport').addEventListener('click', () => $('#importFile').click());
  $('#importFile').addEventListener('change', async e => {
    const f = e.target.files?.[0]; if (!f) return;
    try{
      const data = JSON.parse(await f.text());
      if (!data || !Array.isArray(data.tasks)) throw new Error('fel format');
      if (!confirm('Ersätt all nuvarande data med säkerhetskopian?')) return;
      localStorage.setItem(KEY, JSON.stringify(data));
      location.reload();
    } catch(err){ toast('Kunde inte läsa filen'); }
    e.target.value = '';
  });
  $('#btnWipe').addEventListener('click', () => {
    if (!confirm('Rensa alla uppgifter, pass och inställningar på den här enheten?')) return;
    localStorage.removeItem(KEY); location.reload();
  });
}

/* ── sheet (task picker) ─────────────────────────────────── */
function openSheet(mode = 'task', ctx = {}){
  const body = $('#sheetBody');
  if (PICKERS[mode]){ PICKERS[mode](body, ctx); }
  else if (mode === 'time'){
    $('#sheetTitle').textContent = 'Egen tid';
    body.innerHTML = `
      <div class="steppers" id="steppers">
        <div class="stepper" data-unit="h"><button class="stepper__btn" data-dir="1" type="button" aria-label="Öka timmar">+</button><b class="stepper__val" id="stepH">00</b><button class="stepper__btn" data-dir="-1" type="button" aria-label="Minska timmar">−</button><span class="stepper__lbl">Timmar</span></div>
        <div class="stepper" data-unit="m"><button class="stepper__btn" data-dir="1" type="button" aria-label="Öka minuter">+</button><b class="stepper__val" id="stepM">25</b><button class="stepper__btn" data-dir="-1" type="button" aria-label="Minska minuter">−</button><span class="stepper__lbl">Minuter</span></div>
        <div class="stepper" data-unit="s"><button class="stepper__btn" data-dir="1" type="button" aria-label="Öka sekunder">+</button><b class="stepper__val" id="stepS">00</b><button class="stepper__btn" data-dir="-1" type="button" aria-label="Minska sekunder">−</button><span class="stepper__lbl">Sekunder</span></div>
      </div>
      <p class="muted small" style="text-align:center">Håll in + eller − för att spola snabbt. Du kan också dra runt ringen.</p>
      <button class="btn btn--wide" id="sheetOk" type="button">Klart</button>`;
    wireSteppers(body); paintSteppers();
    $('#sheetOk').addEventListener('click', closeSheet);
  } else {
    const c = catById(T.catId);
    $('#sheetTitle').textContent = 'Ny uppgift';
    body.innerHTML = `
      <form class="sheetadd" id="sheetAdd" autocomplete="off">
        <input class="sheetadd__input" id="sheetAddInput" type="text" enterkeyhint="done"
               maxlength="90" placeholder="Vad ska du göra?">
        <button class="sheetadd__go" type="submit" aria-label="Lägg till"><svg class="ic"><use href="#i-plus"></use></svg></button>
      </form>
      <p class="muted small">Sparas i ${c.name} med ${fmtDur(T.durationMs)} och väljs direkt.</p>`;

    $('#sheetAdd').addEventListener('submit', e => {
      e.preventDefault();
      const title = $('#sheetAddInput').value.trim();
      if (!title) return;
      // fångad på fokusvyn = planerad för idag, annars syns den inte där
      const t = newTask({ catId:T.catId, title, durationMs:T.durationMs, when:tkey() });
      S.tasks.unshift(t);
      T.taskId = t.id;
      buzz(12); save(); closeSheet(); renderAll();
    });
    setTimeout(() => $('#sheetAddInput')?.focus(), 340);
  }
  $('#sheet').hidden = false; $('#sheetBackdrop').hidden = false;
  // när scrimen hunnit bli ogenomskinlig: koppla bort de dyra lagren
  clearTimeout(sheetOpenAt);
  sheetOpenAt = setTimeout(() => document.body.classList.add('sheet-open'), 180);
}
let sheetOpenAt = null;
function closeSheet(){
  const s = $('#sheet');
  if (s.hidden || s.classList.contains('is-closing')) return;
  if (document.activeElement && s.contains(document.activeElement)) document.activeElement.blur();
  clearTimeout(sheetOpenAt);
  s.classList.add('is-closing');
  setTimeout(() => {
    s.hidden = true; s.classList.remove('is-closing');
    $('#sheetBackdrop').hidden = true;
    document.body.classList.remove('sheet-open');   // först när arket är borta
  }, 260);
}

/* ── klart: ljuset fylls, ratten andas ut ────────────────── */
function doneSequence(){
  const dial = $('#dial'), aura = $('.dial__aura');
  paintRing(1, 360);
  if (reduceMotion.matches) return;
  dial.classList.add('is-done');
  aura.style.opacity = '.55';
  setTimeout(() => { aura.style.opacity = ''; }, 1600);
  setTimeout(() => dial.classList.remove('is-done'), 1900);
}

/* ── navigation ──────────────────────────────────────────── */
function go(view){
  document.body.dataset.view = view;
  $$('.view').forEach(v => v.classList.toggle('is-active', v.id === 'view-' + view));
  $$('#tabbar .tab').forEach(t => t.classList.toggle('is-active', t.dataset.tab === view));
  paintPill();
  if (view === 'tasks')    renderLists();
  if (view === 'stats')    renderStats();
  if (view === 'settings') renderSettings();
  $('.stage').scrollTo({ top:0, behavior:'smooth' });
}
function renderAll(){ renderHeader(); renderFocus(); renderCatDots();
  if (document.body.dataset.view === 'stats') renderStats();
  if (document.body.dataset.view === 'tasks') renderLists(); }

/* ── url shortcuts & keyboard ────────────────────────────── */
function initShortcuts(){
  const q = new URLSearchParams(location.search);
  const view = q.get('view');
  if (view && ['focus','tasks','stats','settings'].includes(view)) go(view);
  const list = q.get('list');
  if (list && listById(list)){ stack = [{ k:'home' }, { k:'list', id:list }]; go('tasks'); }
  const quick = parseInt(q.get('quick'), 10);
  if (quick > 0 && quick <= 240 && T.status === 'idle'){
    T.durationMs = quick * 60000; T.elapsedBefore = 0; T.status = 'idle'; T.startedAt = 0;
    renderFocus();
    setTimeout(startTimer, 300);
  }
  if (location.search) history.replaceState(null, '', location.pathname);
}
function initKeys(){
  addEventListener('keydown', e => {
    if (e.target.matches('input, textarea')) return;
    if (e.code === 'Space'){ e.preventDefault(); T.status === 'running' ? pauseTimer() : startTimer(); }
    if (e.key === 'Escape'){
      if (!$('#sheet').hidden) closeSheet();
      else if (openId) closeTodo();
      else if (stack.length > 1 && document.body.dataset.view === 'tasks') popView();
    }
  });
}

/* ── boot ────────────────────────────────────────────────── */
function init(){
  applyTheme(); applyAccent(); buildTicks(); renderPresets(); initDial(); renderCorners();
  initMagic();
  // delegerat en gång: vyn ritas om hela tiden, lyssnarna ska inte följa med
  $('#listBody').addEventListener('click', onListClick);
  $('#listHead').addEventListener('click', onListClick);
  $('#listBody').addEventListener('input', e => {
    const el = e.target.closest('.phead__t'); if (!el) return;
    const h = byId(el.closest('.phead').dataset.head);
    if (h){ h.title = el.value; save(); }
  });

  $('#btnPlay').addEventListener('click',  () => T.status === 'running' ? pauseTimer() : startTimer());
  $('#btnReset').addEventListener('click', resetTimer);
  $('#btnDone').addEventListener('click',  finishEarly);
  $('#dialTime').addEventListener('pointerdown', e => e.stopPropagation());
  $('#dialTime').addEventListener('click', () => {
    if (T.status !== 'idle') return;
    buzz(8); openSheet('time');
  });
  $('#sheetClose').addEventListener('click', closeSheet);
  $('#sheetBackdrop').addEventListener('click', closeSheet);
  $('#btnNotify').addEventListener('click', enableNotifications);
  $('#timerPill').addEventListener('click', () => { buzz(8); go('focus'); });
  $('#streakPill').addEventListener('click', () => go('stats'));
  $('#todayPill').addEventListener('click', () => go('stats'));
  $$('#tabbar .tab').forEach(t => t.addEventListener('click', () => { buzz(8); go(t.dataset.tab); }));

  initInstall(); initData(); initShortcuts(); initKeys();

  // resume a timer that was running when the app was closed
  if (T.status === 'running'){
    if (remaining() <= 0) completeTimer(Math.min(T.startedAt + (T.durationMs - T.elapsedBefore), Date.now()));
    else { wakeOn(); scheduleAlarm(Date.now() + remaining(), ...alarmText()); }
  }

  renderAll(); loop();

  addEventListener('beforeunload', saveNow);
  addEventListener('pagehide', saveNow);

  if ('serviceWorker' in navigator){
    navigator.serviceWorker.register('sw.js', { updateViaCache:'none' }).then(r => { swReg = r; }).catch(() => {});
    navigator.serviceWorker.addEventListener('message', e => {
      if (e.data?.type === 'focus-app') go('focus');
    });
  }
  navigator.storage?.persist?.().catch(() => {});
}

document.addEventListener('DOMContentLoaded', init);
})();
