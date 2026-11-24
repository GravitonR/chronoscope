import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import readline from 'node:readline';

const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'chronoscope-mcp-test-'));
const tmpProfile = path.join(tmpDir, 'profile.json');
const tmpIcs = path.join(tmpDir, 'schedule.ics');

const serverPath = path.resolve(new URL('./server.js', import.meta.url).pathname);
const child = spawn(process.execPath, [serverPath], {
  env: { ...process.env, CHRONOSCOPE_PROFILE_PATH: tmpProfile },
  stdio: ['pipe', 'pipe', 'pipe'],
});

const rl = readline.createInterface({ input: child.stdout });
const pending = new Map();
let nextId = 1;

rl.on('line', (line) => {
  const msg = JSON.parse(line);
  const resolver = pending.get(msg.id);
  if (resolver) {
    pending.delete(msg.id);
    resolver(msg);
  }
});

const rpc = (method, params = {}) =>
  new Promise((resolve) => {
    const id = nextId++;
    pending.set(id, resolve);
    child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
  });

try {
  const init = await rpc('initialize', { protocolVersion: '2024-11-05', clientInfo: { name: 'test', version: '1.0' } });
  assert.equal(init.result.serverInfo.name, 'graviton-chronoscope');

  const tools = await rpc('tools/list');
  assert.equal(tools.result.tools.length, 6);

  // 1. Log a 60s AirPods calibration check
  const logged = await rpc('tools/call', {
    name: 'log_calibration_check',
    arguments: { cv_timing: 0.046, jnd_ms: 16.0, hour_local: 10.5, sleep_midpoint: 3.5, shift_hours: 0.5, alertness: 8 },
  });
  const loggedJson = JSON.parse(logged.result.content[0].text);
  assert.equal(loggedJson.status, 'saved');
  assert.equal(loggedJson.total_sessions, 1);

  // 2. Query live cognitive state at 10:30
  const st = await rpc('tools/call', { name: 'get_cognitive_state', arguments: { hour_local: 10.5 } });
  const stJson = JSON.parse(st.result.content[0].text);
  assert.equal(stJson.state, 'peak');
  assert.equal(stJson.current.latest_jnd_ms, 16.0);

  // 3. Evaluate candidate slots for deep work
  const ev = await rpc('tools/call', {
    name: 'evaluate_task_slot',
    arguments: {
      task_type: 'deep_work',
      candidates: [
        { start: '14:30', duration_minutes: 60 },
        { start: '10:30', duration_minutes: 90 },
        { start: '18:30', duration_minutes: 60 },
      ],
    },
  });
  const evJson = JSON.parse(ev.result.content[0].text);
  assert.equal(evJson.recommended_slot.start, '10:30');
  assert.equal(evJson.recommended_slot.verdict, 'optimal');

  // 4. Auto-schedule mixed-load tasks onto the user's curve
  const sched = await rpc('tools/call', {
    name: 'schedule_tasks_to_curve',
    arguments: {
      tasks: [
        { title: 'Prove Lean 4 lemma', cognitive_load: 'high', duration_minutes: 90 },
        { title: 'Inbox triage & receipts', cognitive_load: 'low', duration_minutes: 60 },
        { title: 'Design sync', cognitive_load: 'medium', duration_minutes: 60 },
      ],
      busy_blocks: [{ start: '12:00', end: '13:00' }],
    },
  });
  const schedJson = JSON.parse(sched.result.content[0].text);
  const deepTask = schedJson.scheduled_plan.find((t) => t.title === 'Prove Lean 4 lemma');
  const adminTask = schedJson.scheduled_plan.find((t) => t.title === 'Inbox triage & receipts');
  assert.equal(deepTask.primary_tier, 'peak');
  assert.equal(adminTask.primary_tier, 'low_reliability');

  // 5. Export RFC 5545 .ics to disk
  const icsRes = await rpc('tools/call', {
    name: 'export_ics_schedule',
    arguments: { days: 3, output_path: tmpIcs },
  });
  const icsJson = JSON.parse(icsRes.result.content[0].text);
  assert.equal(icsJson.saved_to, tmpIcs);
  const rawIcs = fs.readFileSync(tmpIcs, 'utf8');
  assert(rawIcs.startsWith('BEGIN:VCALENDAR\r\n'));
  assert(rawIcs.includes('[Graviton Peak]'));

  // 6. Read MCP resource + prompt
  const resRead = await rpc('resources/read', { uri: 'chronoscope://state/current' });
  assert.equal(JSON.parse(resRead.result.contents[0].text).schema, 'graviton-cognitive-state/v1');
  const prm = await rpc('prompts/get', { name: 'plan_my_day_by_precision' });
  assert(prm.result.messages[0].content.text.includes('Personal Cognitive Precision Context'));

  console.log('ALL MCP SERVER TESTS PASSED:', {
    deepTaskSlot: `${deepTask.start}-${deepTask.end} (${deepTask.primary_tier})`,
    adminTaskSlot: `${adminTask.start}-${adminTask.end} (${adminTask.primary_tier})`,
    icsBytes: icsJson.ics_bytes,
  });
} finally {
  child.kill();
  fs.rmSync(tmpDir, { recursive: true, force: true });
}
