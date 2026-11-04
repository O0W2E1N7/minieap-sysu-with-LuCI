'use strict';
// Dependency-free interaction tests for the script embedded in the Lua template.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const template = fs.readFileSync(path.join(__dirname, '../root/usr/lib/lua/luci/view/minieap_sysu/index.htm'), 'utf8');
const script = template.match(/<script type="text\/javascript">([\s\S]*?)<\/script>/)[1];

function fixture(opts = {}) {
  function element(id, value = '') {
    return {
      id, value, textContent: '', checked: false, disabled: false, required: false,
      validationMessage: '', children: [], listeners: {}, scrollTop: 0, scrollHeight: 300, clientHeight: 100,
      addEventListener(type, handler) { (this.listeners[type] ||= []).push(handler); },
      fire(type, extra = {}) {
        const event = Object.assign({defaultPrevented: false, preventDefault() { this.defaultPrevented = true; }}, extra);
        for (const handler of this.listeners[type] || []) handler.call(this, event);
        return event;
      },
      appendChild(child) { this.children.push(child); },
      setCustomValidity(message) { this.validationMessage = message; },
      checkValidity() { return !this.validationMessage && (!this.required || !!this.value); },
      reportValidity() { this.reported = true; }
    };
  }
  const ids = ['connection', 'duration', 'success', 'dismiss', 'page', 'running', 'autostart', 'nic', 'carrier', 'address', 'wan', 'state-error',
    'auto', 'refresh', 'refresh-note', 'user', 'password', 'password-help', 'enabled', 'logs', 'log-message', 'operation'];
  if (opts.fold) ids.push('fold');
  const els = Object.fromEntries(ids.map(id => [id, element('campus-' + id)]));
  els.user.value = 'old-user';
  els.auto.checked = true;
  els.dismiss.getAttribute = () => 'campus-success';
  els.duration.getAttribute = () => '';
  if (opts.autodismiss) els.success.getAttribute = key => key === 'data-autodismiss' ? opts.autodismiss : null;
  const intervals = []; let clock = 0;
  const actions = ['start', 'restart', 'stop'].map(action => element('', action));
  const settings = ['save', 'save_restart'].map(action => element('', action));
  const serviceForm = element('service-form'), settingsForm = element('campus-settings');
  serviceForm.querySelectorAll = () => actions;
  settingsForm.querySelectorAll = () => settings;
  settingsForm.checkValidity = () => els.user.value !== '' && els.password.checkValidity();
  els.page.getAttribute = () => '/cgi-bin/luci/admin/services/minieap_sysu/status';
  els.page.querySelectorAll = selector => selector === 'button[data-dismiss]' ? [els.dismiss] : selector === 'form.campus-action-form'
    ? [serviceForm, settingsForm] : [...actions, ...settings, els.refresh];
  const document = element('document');
  document.hidden = false;
  document.getElementById = id => els[id.replace('campus-', '')];
  document.createElement = () => element('');
  const window = element('window');
  let reloads = 0;
  window.location = opts.location || {reload() { reloads++; }};
  if (opts.storage) window.sessionStorage = opts.storage;
  if (opts.history) window.history = opts.history;
  window.scrollTo = opts.scrollTo || function () {};
  window.scrollY = opts.scrollY || 0;
  const timers = new Map(), requests = [];
  let timerID = 0;
  function XMLHttpRequest() { requests.push(this); }
  XMLHttpRequest.prototype.open = function(method, url) { this.method = method; this.url = url; };
  XMLHttpRequest.prototype.send = function(body) { this.body = body; };
  XMLHttpRequest.prototype.abort = function() { this.aborted = true; if (this.onabort) this.onabort(); };
  XMLHttpRequest.prototype.respond = function(status, body) { this.status = status; this.responseText = body; this.onload(); };
  vm.runInNewContext(script, {
    document, window, XMLHttpRequest, Date, JSON, Error, performance: {now: () => clock},
    setInterval(fn) { intervals.push(fn); },
    setTimeout(fn, ms) { const id = ++timerID; timers.set(id, {fn, ms}); return id; },
    clearTimeout(id) { timers.delete(id); }
  });
  function pollTimer() {
    const polls = [...timers].filter(([, t]) => t.ms === 5000 || t.ms === 2000);
    assert.equal(polls.length, 1, 'exactly one pending poll');
    return polls[0];
  }
  function tick() {
    const [id, entry] = pollTimer(); timers.delete(id); entry.fn();
  }
  function fireTimer(ms) {
    const hits = [...timers].filter(([, t]) => t.ms === ms);
    assert.equal(hits.length, 1, 'exactly one timer at ' + ms + 'ms');
    const [id, entry] = hits[0]; timers.delete(id); entry.fn();
  }
  return {els, actions, settings, serviceForm, settingsForm, document, window, timers, requests, tick, fireTimer, advance(seconds) { clock += seconds * 1000; intervals.forEach(fn => fn()); }, reloads: () => reloads};
}
function data(overrides = {}) {
  return JSON.stringify({state: {running: true, enabled: true, carrier: true, wan_up: true, nic: 'eth0', address: '192.0.2.10'}, logs: '<img src=x onerror=alert(1)>', ...overrides});
}

// Polling updates only status/log text, preserves edits, and never submits credentials.
let f = fixture();
f.els.user.value = 'unsaved-user'; f.els.password.value = 'unsaved-secret'; f.els.enabled.checked = false;
f.els.logs.scrollTop = 200;
f.tick();
assert.equal(f.requests.length, 1);
assert.equal(f.requests[0].method, 'GET');
assert.match(f.requests[0].url, /^\/cgi-bin\/luci\/admin\/services\/minieap_sysu\/status\?_=[0-9]+$/);
assert.equal(f.requests[0].body, undefined);
f.els.refresh.fire('click'); assert.equal(f.requests.length, 1, 'in-flight polls do not overlap');
f.requests[0].respond(200, data());
assert.equal(f.els.running.textContent, '运行中');
assert.equal(f.els.user.value, 'unsaved-user'); assert.equal(f.els.password.value, 'unsaved-secret');
assert.equal(f.els.enabled.checked, false);
assert.equal(f.els.logs.textContent, '<img src=x onerror=alert(1)>');
assert.equal(f.els.logs.innerHTML, undefined, 'logs rendered with textContent');
assert.equal(f.els.logs.scrollTop, 300);
f.els.logs.scrollTop = 12;
f.tick(); f.requests[1].respond(200, data({logs: 'new line'}));
assert.equal(f.els.logs.scrollTop, 12, 'reading older logs does not force scroll to bottom');
f.tick(); f.requests[2].respond(200, '<html>login</html>');
assert.match(f.els['refresh-note'].textContent, /刷新失败/);
assert.equal(f.els.user.value, 'unsaved-user'); assert.equal(f.reloads(), 0);
f.els.auto.checked = false; f.els.auto.fire('change'); assert.equal(f.timers.size, 0);
f.els.refresh.fire('click'); assert.equal(f.requests.length, 4, 'manual refresh still available');
f.requests[3].ontimeout(); assert.equal(f.timers.size, 0);
f.els.auto.checked = true; f.document.hidden = true; f.document.fire('visibilitychange'); assert.equal(f.timers.size, 0);
f.document.hidden = false; f.document.fire('visibilitychange'); assert.equal(f.timers.size, 1);

// Changing the username requires a new password; invalid submits remain editable.
f = fixture();
f.els.user.value = 'new-user'; f.els.user.fire('input');
assert.equal(f.els.password.required, true);
let event = f.settingsForm.fire('submit', {submitter: f.settings[1]});
assert.equal(event.defaultPrevented, true); assert.equal(f.settingsForm.children.length, 0);
assert.equal(f.settings[1].disabled, false); assert.equal(f.settingsForm.reported, true);
f.els.user.value = 'old-user'; f.els.user.fire('input');
assert.equal(f.els.password.required, false); assert.equal(f.els.password.validationMessage, '');
f.els.user.value = 'new-user'; f.els.user.fire('input');
f.els.password.value = 'new-secret'; f.els.password.fire('input');
f.tick();
event = f.settingsForm.fire('submit', {submitter: f.settings[1]});
assert.equal(event.defaultPrevented, false);
assert.equal(f.settingsForm.children[0].name, 'action');
assert.equal(f.settingsForm.children[0].value, 'save_restart');
assert.equal(f.els.password.disabled, false, 'password remains part of the POST');
assert.ok([...f.settings, ...f.actions, f.els.refresh].every(button => button.disabled));
assert.equal(f.requests[0].aborted, true); assert.equal(f.timers.size, 0);
assert.equal(f.settingsForm.fire('submit', {submitter: f.settings[1]}).defaultPrevented, true);
assert.equal(f.serviceForm.fire('submit', {submitter: f.actions[0]}).defaultPrevented, true);
assert.equal(f.settingsForm.children.length, 1); assert.equal(f.serviceForm.children.length, 0);

// Older browsers without SubmitEvent.submitter retain the clicked action.
f = fixture(); f.actions[2].fire('click');
assert.equal(f.serviceForm.fire('submit').defaultPrevented, false);
assert.equal(f.serviceForm.children[0].value, 'stop');
f = fixture(); assert.equal(f.settingsForm.fire('submit').defaultPrevented, false);
assert.equal(f.settingsForm.children[0].value, 'save', 'Enter defaults to save only');
f.window.fire('pageshow', {persisted: true}); assert.equal(f.reloads(), 1);
console.log('PASS: polling, unsaved inputs, text-only logs, scroll position, session/network failures, visibility, account validation, selected action, duplicate submission, pending-request cancellation, cached back navigation.');

// Connection timer follows backend session age, not page lifetime or wall clock.
f = fixture(); f.tick();
f.requests[0].respond(200, data({state: {running: true, connection_text: '已认证', connected_seconds: 3661}}));
assert.equal(f.els.duration.textContent, '01:01:01');
f.advance(2); assert.equal(f.els.duration.textContent, '01:01:03');
f.tick(); f.requests[1].respond(200, data({state: {running: true, connection_text: '正在连接校园网…'}}));
f.advance(5); assert.equal(f.els.duration.textContent, '—');
// Closing a notice does not submit a form, reload, or change the timer.
f = fixture(); f.els.dismiss.fire('click');
assert.equal(f.els.success.hidden, true);
assert.equal(f.requests.length, 0); assert.equal(f.reloads(), 0);
console.log('PASS: connection timer resync/reset; manual notice dismissal.');


// v1.5.2 page polish: notices, progress, scroll restore, fast poll and log folding.
assert.match(template, /display:\s*flex[\s\S]*campus-dismiss[\s\S]*width:\s*32px/, 'notice row is a flex box with a 32px hit target');
assert.match(template, /id="campus-alerts"[\s\S]*id="campus-success"[\s\S]*id="campus-warning"/, 'notices share one container');
assert.match(template, /href="#campus-logs"/, 'success notice links to the log pane');
assert.match(template, /class="campus-summary"[\s\S]*id="campus-connection"/, 'status summary sits above the settings');

// The success banner dismisses itself; hovering pauses the countdown.
let g = fixture({autodismiss: '6000'});
assert.equal(g.els.success.hidden, undefined);
g.fireTimer(6000);
assert.equal(g.els.success.hidden, true);
g = fixture({autodismiss: '6000'});
g.els.success.fire('mouseenter');
assert.equal([...g.timers].filter(([, t]) => t.ms === 6000).length, 0, 'hover cancels auto dismissal');
g.els.success.fire('mouseleave');
g.fireTimer(3000);
assert.equal(g.els.success.hidden, true);

// One-shot result tokens are removed from the address bar.
let replacedUrl = null;
fixture({
  location: {pathname: '/cgi-bin/luci/admin/services/minieap_sysu', search: '?result=abc', reload() {}},
  history: {replaceState(_, __, url) { replacedUrl = url; }}
});
assert.equal(replacedUrl, '/cgi-bin/luci/admin/services/minieap_sysu');

function store(initial = {}) {
  return {
    data: Object.assign({}, initial),
    getItem(key) { return key in this.data ? this.data[key] : null; },
    setItem(key, value) { this.data[key] = String(value); },
    removeItem(key) { delete this.data[key]; }
  };
}

// Submitting reports progress, remembers the re-authentication and the scroll offset.
const memory = store();
g = fixture({storage: memory, scrollY: 300});
g.settingsForm.fire('submit', {submitter: g.settings[1]});
assert.equal(g.settings[1].textContent, '提交中…');
assert.equal(memory.getItem('campus-reauth'), '1');
assert.equal(memory.getItem('campus-scroll'), '300');

// The stored offset is restored once, after the redirect.
memory.setItem('campus-scroll', '420');
let restoredTo = null;
g = fixture({storage: memory, scrollTo(_, y) { restoredTo = y; }});
assert.equal(restoredTo, 420);
assert.equal(memory.getItem('campus-scroll'), null, 'restored offset is consumed');

// A pending re-authentication shows its own state and polls faster until the backend settles.
const pending = store({'campus-reauth': '1'});
g = fixture({storage: pending});
assert.equal(g.els.connection.textContent, '正在重新认证…');
assert.equal([...g.timers].filter(([, t]) => t.ms === 2000).length, 1, 'fast poll while re-authenticating');
g.tick();
g.requests[0].respond(200, data({state: {running: true, connected_seconds: 5}}));
assert.equal(pending.getItem('campus-reauth'), null, 'fast poll clears once the session is up');

// Repeated heartbeat lines collapse, and the toggle restores the raw text.
g = fixture({fold: true});
g.els.fold.checked = true;
g.tick();
g.requests[0].respond(200, data({logs: 'a ] x\nb ] x\nc ] y'}));
assert.match(g.els.logs.textContent, /共 2 次/);
assert.match(g.els.logs.textContent, /c \] y/);
g.els.fold.checked = false;
g.els.fold.fire('change');
assert.equal(g.els.logs.textContent, 'a ] x\nb ] x\nc ] y');
console.log('PASS: notice layout/auto-dismiss/anchor, URL cleanup, submit progress, scroll restore, re-auth fast poll, log folding.');

