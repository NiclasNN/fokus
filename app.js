/* ============================================================
   Fokus — app logic
   Vanilla JS, no build step. Everything persists to localStorage.
   ============================================================ */
(() => {
'use strict';

const VERSION = '1.0.2';
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
const MIN_MS  = 60000;   // ett pass under en minut varken startas, sparas eller räknas

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
  v: 1,
  tasks: [],
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
    return {
      ...base, ...parsed,
      timer:    { ...base.timer,    ...(parsed.timer    || {}) },
      settings: { ...base.settings, ...(parsed.settings || {}) },
      tasks:    Array.isArray(parsed.tasks)    ? parsed.tasks    : [],
      sessions: Array.isArray(parsed.sessions) ? parsed.sessions : [],
    };
  } catch (e){ console.warn('Kunde inte läsa sparad data', e); return defaults(); }
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
let ac = null;
function audio(){
  if (!ac){ const C = window.AudioContext || window.webkitAudioContext; if (C) ac = new C(); }
  if (ac && ac.state === 'suspended') ac.resume();
  return ac;
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
  o.start(t0); o.stop(t0 + dur + .05);
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
    o.start(t0); o.stop(t0 + len + 0.02);
  };
  click(bas * lut, vol, dur, 'triangle');           // transienten
  click(bas * lut * 0.5, vol * 0.55, dur * 1.6, 'sine');   // kroppen
  if (kind === 'hour') click(320, 0.09, 0.12, 'sine');     // hel timme: en dov stöt
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
let wake = null;
async function wakeOn(){
  if (!S.settings.keepAwake || !('wakeLock' in navigator)) return;
  try { wake = await navigator.wakeLock.request('screen'); } catch(e){}
}
function wakeOff(){ try { wake?.release(); } catch(e){} wake = null; }
document.addEventListener('visibilitychange', () => {
  if (document.hidden){ clearInterval(loopId); loopId = null; wakeOff(); return; }
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
  }
  const c = catById(T.catId);
  scheduleAlarm(Date.now() + remaining(), 'Passet är klart 🎉',
                `${sessionTitle()} — ${fmtDur(T.durationMs)} avklarat`);
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
    if (sec === lastSec && !force) return;      // 1000 ms-transitionen får löpa klart
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

let minsFloat = 25, cur = 25, dragPid = null, flying = false;
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

function renderTaskStrip(){
  const host = $('#taskStrip');
  const open = S.tasks.filter(t => t.catId === T.catId && !t.done);

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
    T.catId = el.dataset.id; T.taskId = null; taskCat = T.catId;
    save(); renderFocus();
  }));
}

function renderCats(host, onPick){
  host.innerHTML = CATS.map(c => `
    <button type="button" class="cat" data-id="${c.id}" style="--c:${c.c}" role="tab">
      <span class="cat__dot"></span>
      <svg class="ic"><use href="#${c.icon}"></use></svg>
      <span class="cat__name">${c.short}</span>
    </button>`).join('');
  $$('.cat', host).forEach(el =>
    el.addEventListener('click', () => { buzz(8); onPick(el.dataset.id); }));
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
  T.durationMs = next * 60000;
  T.elapsedBefore = 0; T.status = 'idle'; T.startedAt = 0;
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
  const from = cur;
  if (target === from) return;
  // rAF fryser i en dold flik — hoppa direkt i stället för att aldrig landa
  if (reduceMotion.matches || document.hidden){ setMinutes(target); announce(target); return; }

  flying = true;
  let done = false;
  const finish = () => {
    if (done) return;
    done = true; flying = false; clearTimeout(guard);
    const prev = cur;
    cur = minsFloat = target;
    commitMinutes(target, prev);
    paintIdle(cur, 0);
    buzz(8); announce(target); save();
  };
  const guard = setTimeout(finish, dur + 300);   // skyddsnät om bildrutorna uteblir

  const delta = target - from, t0 = performance.now();
  const step = now => {
    if (done) return;
    const t = Math.min(1, (now - t0) / dur);
    const v = from + delta * (1 - Math.pow(1 - t, 3));
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
    buzz(5); renderFocus(); save();
  };
  $$('.stepper__btn', root).forEach(btn => {
    const unit = btn.closest('.stepper').dataset.unit;
    const dir  = +btn.dataset.dir;
    let hold = null, rep = null;
    const go   = () => step(unit, dir);
    const stop = () => { clearTimeout(hold); clearInterval(rep); hold = rep = null; stopAll.delete(stop); };
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

/* ── tasks view ──────────────────────────────────────────── */
let taskCat = S.timer.catId;
let newDurMin = 25;

function renderDurPick(){
  $('#durPick').innerHTML = PRESETS.map(m =>
    `<button type="button" class="chip ${m === newDurMin ? 'is-on' : ''}" data-min="${m}">${m < 60 ? m + ' min' : m/60 + ' h'}</button>`
  ).join('');
  $$('#durPick .chip').forEach(el => el.addEventListener('click', () => {
    newDurMin = +el.dataset.min; buzz(6); renderDurPick();
  }));
}
function renderTasks(){
  const c = catById(taskCat);
  document.documentElement.style.setProperty('--c-task', c.c);
  $$('#catsTasks .cat').forEach(el => el.classList.toggle('is-on', el.dataset.id === taskCat));
  $('#addInput').placeholder = `Ny uppgift i ${c.name}…`;

  const open = S.tasks.filter(t => t.catId === taskCat && !t.done);
  const done = S.tasks.filter(t => t.catId === taskCat && t.done);
  const list = $('#taskList');

  list.innerHTML = open.length ? open.map(t => taskRow(t, c)).join('')
    : `<div class="empty"><b>Inget här ännu</b>Lägg till det du vill lägga tid på i ${c.name}.</div>`;
  wireTasks(list);

  $('#doneWrap').innerHTML = done.length ? `
    <div class="donewrap__head"><span>Klart (${done.length})</span><button type="button" id="clearDone">Rensa</button></div>
    <div class="tasklist">${done.slice(0, 20).map(t => taskRow(t, c)).join('')}</div>` : '';
  if (done.length){
    wireTasks($('#doneWrap'));
    $('#clearDone').addEventListener('click', () => {
      S.tasks = S.tasks.filter(t => !(t.catId === taskCat && t.done));
      save(); renderTasks(); renderCatDots(); toast('Klara uppgifter rensade');
    });
  }
}
function taskRow(t, c){
  const active = T.taskId === t.id;
  const focused = t.focusedMs ? `<b>${fmtShort(t.focusedMs)} fokuserat</b>` : '';
  return `<div class="task ${t.done ? 'is-done' : ''} ${active ? 'is-active' : ''}" data-id="${t.id}" style="--c:${c.c}">
    <button type="button" class="task__check" data-act="toggle" aria-label="Markera klar"><svg class="ic"><use href="#i-check"></use></svg></button>
    <div class="task__main">
      <div class="task__title">${escapeHtml(t.title)}</div>
      <div class="task__meta"><span>${fmtDur(t.durationMs)}</span>${focused}</div>
    </div>
    ${t.done ? '' : '<button type="button" class="task__play" data-act="start" aria-label="Starta"><svg class="ic ic--sm"><use href="#i-play"></use></svg></button>'}
    <button type="button" class="task__del" data-act="del" aria-label="Ta bort"><svg class="ic ic--sm"><use href="#i-trash"></use></svg></button>
  </div>`;
}
function wireTasks(root){
  $$('.task', root).forEach(row => {
    const id = row.dataset.id;
    $$('[data-act]', row).forEach(btn => btn.addEventListener('click', ev => {
      ev.stopPropagation();
      const t = S.tasks.find(x => x.id === id); if (!t) return;
      const act = btn.dataset.act;
      if (act === 'toggle'){
        t.done = !t.done; t.completedAt = t.done ? Date.now() : null;
        buzz(t.done ? [10, 40, 16] : 8);
        if (t.done && T.taskId === t.id) T.taskId = null;
        save(); renderTasks(); renderCatDots(); renderFocus();
        if (t.done) toast('Snyggt jobbat ✓');
      }
      if (act === 'del'){
        S.tasks = S.tasks.filter(x => x.id !== id);
        if (T.taskId === id) T.taskId = null;
        buzz(12); save(); renderTasks(); renderCatDots(); renderFocus();
      }
      if (act === 'start'){
        if (timeLocked()) return;
        T.catId = t.catId; T.taskId = t.id;
        T.durationMs = t.durationMs; T.elapsedBefore = 0; T.status = 'idle'; T.startedAt = 0;
        save(); go('focus'); renderFocus();
        setTimeout(startTimer, 260);
      }
    }));
  });
}
function escapeHtml(s){ return String(s).replace(/[&<>"']/g, m => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m])); }
function renderCatDots(){
  $$('#cats .corner, #catsTasks .cat').forEach(el =>
    el.classList.toggle('has-tasks', S.tasks.some(t => t.catId === el.dataset.id && !t.done)));
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
    const on = toggleOn(k);
    const desc = k === 'notify' && !on
      ? (notifSupported ? 'Behörighet saknas — tryck för att tillåta' : 'Stöds inte i den här webbläsaren')
      : d;
    return `<div class="row"><div><div class="row__t">${t}</div><div class="row__d">${desc}</div></div>
      <button type="button" class="switch ${on ? 'is-on' : ''}" data-k="${k}" role="switch" aria-checked="${on}" aria-label="${t}"></button></div>`;
  }).join('');
  $$('#toggles .switch').forEach(el => el.addEventListener('click', async () => {
    const k = el.dataset.k;
    if (k === 'notify'){
      if (!notifSupported){ toast('Den här webbläsaren stöder inte notiser'); return; }
      if (!notifyGranted()){ S.settings.notify = true; save(); buzz(8); await enableNotifications(); return; }
      S.settings.notify = !S.settings.notify;
    } else {
      S.settings[k] = !S.settings[k];
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

  $('#appVersion').textContent = 'v' + VERSION;
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
function openSheet(mode = 'task'){
  const body = $('#sheetBody');
  if (mode === 'time'){
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
      const t = { id:uid(), catId:T.catId, title, durationMs:T.durationMs,
                  done:false, createdAt:Date.now(), focusedMs:0, sessions:0 };
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
  if (view === 'tasks')    { renderDurPick(); renderTasks(); }
  if (view === 'stats')    renderStats();
  if (view === 'settings') renderSettings();
  $('.stage').scrollTo({ top:0, behavior:'smooth' });
}
function renderAll(){ renderHeader(); renderFocus(); renderCatDots();
  if (document.body.dataset.view === 'stats') renderStats();
  if (document.body.dataset.view === 'tasks') renderTasks(); }

/* ── url shortcuts & keyboard ────────────────────────────── */
function initShortcuts(){
  const q = new URLSearchParams(location.search);
  const view = q.get('view');
  if (view && ['focus','tasks','stats','settings'].includes(view)) go(view);
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
    if (e.key === 'Escape' && !$('#sheet').hidden) closeSheet();
  });
}

/* ── boot ────────────────────────────────────────────────── */
function init(){
  applyTheme(); applyAccent(); buildTicks(); renderPresets(); initDial(); renderCorners();
  renderCats($('#catsTasks'), id => { taskCat = id; renderTasks(); });

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

  $('#addForm').addEventListener('submit', e => {
    e.preventDefault();
    const title = $('#addInput').value.trim(); if (!title) return;
    S.tasks.unshift({ id:uid(), catId:taskCat, title, durationMs:newDurMin*60000,
                      done:false, createdAt:Date.now(), focusedMs:0, sessions:0 });
    $('#addInput').value = ''; buzz(10); save(); renderTasks(); renderCatDots();
  });

  initInstall(); initData(); initShortcuts(); initKeys();

  // resume a timer that was running when the app was closed
  if (T.status === 'running'){
    if (remaining() <= 0) completeTimer(Math.min(T.startedAt + (T.durationMs - T.elapsedBefore), Date.now()));
    else { wakeOn(); scheduleAlarm(Date.now() + remaining(), 'Passet är klart 🎉', catById(T.catId).name); }
  }

  renderAll(); loop();

  // unlock audio on the first real interaction
  const unlock = () => { audio(); removeEventListener('pointerdown', unlock); };
  addEventListener('pointerdown', unlock, { once:true });
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
