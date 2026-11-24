#!/usr/bin/env node
'use strict';

/**
 * Graviton ChronoScope MCP Server (Zero-Dependency JSON-RPC 2.0 over stdio)
 *
 * Reads the shared local profile synced by the macOS ChronoScope Companion App
 * (~/.graviton/chronoscope-profile.json) and exposes real-time cognitive state,
 * task-to-precision-curve scheduling, and RFC 5545 .ics export to any MCP client
 * (Antigravity, Claude Desktop, Cursor, Windsurf, etc.).
 *
 * Epistemic boundary: Behavioral timing model estimate; never medical advice.
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const readline = require('readline');
const engine = require('./engine.js');

const SERVER_INFO = {
  name: 'graviton-chronoscope',
  version: '0.1.0',
};

const PROTOCOL_VERSION = '2024-11-05';
const DEFAULT_PROFILE_DIR = path.join(os.homedir(), '.graviton');
const PROFILE_PATH = process.env.CHRONOSCOPE_PROFILE_PATH || path.join(DEFAULT_PROFILE_DIR, 'chronoscope-profile.json');

/* ---------- Local Profile Persistence (shared with macOS Companion App) ---------- */
function defaultProfile() {
  return {
    schema: 'graviton-chronoscope-profile/v1',
    updated_at: new Date().toISOString(),
    settings: {
      sleep_midpoint: 3.5,
      shift_hours: 0.5,
      alertness: 7,
      work_start: 8,
      work_end: 20,
      include_morning_check: true,
    },
    healthkit_context: null,
    sessions: [],
  };
}

function loadProfile() {
  try {
    if (!fs.existsSync(PROFILE_PATH)) return defaultProfile();
    const raw = fs.readFileSync(PROFILE_PATH, 'utf8');
    const parsed = JSON.parse(raw);
    return {
      ...defaultProfile(),
      ...parsed,
      settings: {
        ...defaultProfile().settings,
        ...(parsed.settings || {}),
      },
      sessions: Array.isArray(parsed.sessions) ? parsed.sessions : [],
    };
  } catch {
    return defaultProfile();
  }
}

function saveProfile(profile) {
  const dir = path.dirname(PROFILE_PATH);
  fs.mkdirSync(dir, { recursive: true });
  profile.updated_at = new Date().toISOString();
  fs.writeFileSync(PROFILE_PATH, JSON.stringify(profile, null, 2) + '\n', 'utf8');
}

function normalizeSessionsForEngine(sessions) {
  return sessions
    .filter((s) => typeof (s.cvTiming ?? s.cv_timing) === 'number' && (s.cvTiming ?? s.cv_timing) > 0)
    .map((s) => {
      const hourLocal = Number(s.hourLocal ?? s.hour_local ?? 10);
      const sleepMidpoint = Number(s.sleepMidpoint ?? s.sleep_midpoint ?? 3.5);
      const phaseDeg =
        typeof (s.phaseDeg ?? s.phase_deg) === 'number'
          ? Number(s.phaseDeg ?? s.phase_deg)
          : ((((hourLocal - sleepMidpoint) % 24) + 24) % 24) * 15;
      const shiftHours = Number(s.shiftHours ?? s.shift_hours ?? 0.5);
      return {
        iso: s.iso || new Date().toISOString(),
        hourLocal,
        sleepMidpoint,
        phaseDeg,
        phaseRad: (phaseDeg * Math.PI) / 180,
        sleepPressureS: Number(s.sleepPressureS ?? s.sleep_pressure_s ?? 4.0),
        alertnessA: Number(s.alertnessA ?? s.alertness ?? 7),
        shiftHours,
        misalignmentProxy: Math.min(1, shiftHours / 6),
        cvTiming: Number(s.cvTiming ?? s.cv_timing),
        jndMs: s.jndMs ?? s.jnd_ms ?? null,
        bias: Number(s.bias ?? 1.0),
        synthetic: Boolean(s.synthetic),
      };
    });
}

function computeFromProfile(overrides = {}) {
  const profile = loadProfile();
  const s = profile.settings;
  const sessions = normalizeSessionsForEngine(profile.sessions);
  const now = new Date();
  const hourLocal =
    typeof overrides.hour_local === 'number' && Number.isFinite(overrides.hour_local)
      ? overrides.hour_local
      : now.getHours() + now.getMinutes() / 60;

  const schedule = engine.computeCognitiveSchedule({
    now,
    hourLocal,
    sleepMidpoint: overrides.sleep_midpoint ?? s.sleep_midpoint,
    shiftHours: overrides.shift_hours ?? s.shift_hours,
    alertnessA: overrides.alertness ?? s.alertness,
    workStart: overrides.work_start ?? s.work_start,
    workEnd: overrides.work_end ?? s.work_end,
    sessions,
  });

  return { profile, schedule };
}

function buildLiveApiUrl(profile, schedule, format = 'json') {
  const s = profile.settings;
  const params = new URLSearchParams();
  params.set('mid', Number(s.sleep_midpoint).toFixed(1));
  params.set('shift', Number(s.shift_hours).toFixed(1));
  params.set('alert', String(s.alertness));
  params.set('work_start', String(s.work_start));
  params.set('work_end', String(s.work_end));
  params.set('tz_offset', String(new Date().getTimezoneOffset()));
  if (schedule.fit) {
    params.set('alpha', schedule.fit.alpha.toFixed(4));
    params.set('bc', schedule.fit.betaC.toFixed(4));
    params.set('bs', schedule.fit.betaS.toFixed(4));
    params.set('gamma', schedule.fit.gamma.toFixed(4));
    params.set('eta', schedule.fit.eta.toFixed(4));
    params.set('kappa', schedule.fit.kappa.toFixed(4));
  } else if (profile.sessions.length > 0) {
    const last = normalizeSessionsForEngine(profile.sessions).slice(-1)[0];
    if (last) {
      params.set('cal_cv', last.cvTiming.toFixed(4));
      params.set('cal_hour', last.hourLocal.toFixed(2));
      if (last.jndMs !== null) params.set('cal_jnd', Number(last.jndMs).toFixed(1));
    }
  }
  if (format === 'ics') {
    params.set('format', 'ics');
    params.set('days', '7');
  }
  return `https://gravitonresearch.org/api/cognitive-state/?${params.toString()}`;
}

/* ---------- Task-to-Precision-Curve Slot Matcher ---------- */
const LOAD_PREFERENCE = {
  high: { peak: 100, moderate: 58, low_reliability: 18, rest: 5 },
  deep_work: { peak: 100, moderate: 58, low_reliability: 18, rest: 5 },
  decision: { peak: 100, moderate: 62, low_reliability: 15, rest: 5 },
  medium: { peak: 72, moderate: 100, low_reliability: 55, rest: 10 },
  meetings: { peak: 65, moderate: 100, low_reliability: 60, rest: 10 },
  low: { peak: 30, moderate: 75, low_reliability: 100, rest: 20 },
  routine: { peak: 25, moderate: 72, low_reliability: 100, rest: 20 },
};

function parseHourString(val) {
  if (typeof val === 'number' && Number.isFinite(val)) return val;
  if (typeof val === 'string') {
    const m = val.trim().match(/^(\d{1,2}):(\d{2})$/);
    if (m) return parseInt(m[1], 10) + parseInt(m[2], 10) / 60;
    const f = Number(val);
    if (Number.isFinite(f)) return f;
  }
  return null;
}

function evaluateCandidateSlots(schedule, taskType, candidates) {
  const pref = LOAD_PREFERENCE[String(taskType || 'high').toLowerCase()] || LOAD_PREFERENCE.high;
  const scored = candidates.map((c) => {
    const startH = parseHourString(c.start ?? c);
    const durMin = Number(c.duration_minutes ?? 60);
    if (startH === null) {
      return { input: c, error: 'Invalid start time; expected "HH:MM" or decimal hour' };
    }
    const endH = Math.min(24, startH + durMin / 60);
    const covered = schedule.slots.filter((sl) => sl.hour + 0.5 > startH && sl.hour < endH);
    const use = covered.length > 0 ? covered : [schedule.slots[Math.min(47, Math.max(0, Math.floor(startH * 2)))]];
    const avgFit = Math.round(use.reduce((a, sl) => a + (pref[sl.tier] ?? 50), 0) / use.length);
    const avgCv = Number((use.reduce((a, sl) => a + sl.cv, 0) / use.length).toFixed(4));
    const avgPrecision = Math.round(use.reduce((a, sl) => a + sl.precisionIndex, 0) / use.length);
    const tiers = Array.from(new Set(use.map((sl) => sl.tier)));
    let verdict = 'good_match';
    if (avgFit >= 85) verdict = 'optimal';
    else if (avgFit < 45) verdict = 'mismatch_defer_if_possible';
    return {
      start: engine.formatHour(startH),
      end: engine.formatHour(endH),
      duration_minutes: durMin,
      fit_score: avgFit,
      verdict,
      tiers_crossed: tiers,
      predicted_cv_mean: avgCv,
      precision_index: avgPrecision,
    };
  });
  return scored.sort((a, b) => (b.fit_score || 0) - (a.fit_score || 0));
}

function scheduleTasksToCurve(schedule, tasks, busyBlocks = []) {
  // Build 48 half-hour availability slots within the workday
  const occupied = new Set();
  for (const b of busyBlocks) {
    const s = parseHourString(b.start);
    const e = parseHourString(b.end);
    if (s !== null && e !== null) {
      for (let i = 0; i < 48; i++) {
        const h = i * 0.5;
        if (h + 0.5 > s && h < e) occupied.add(i);
      }
    }
  }

  // Sort high-load tasks first so they get first claim on Peak windows
  const priorityOrder = { high: 0, deep_work: 0, decision: 0, medium: 1, meetings: 1, low: 2, routine: 2 };
  const ordered = tasks
    .map((t, idx) => ({ ...t, _idx: idx, _load: String(t.cognitive_load || t.load || 'medium').toLowerCase() }))
    .sort((a, b) => (priorityOrder[a._load] ?? 1) - (priorityOrder[b._load] ?? 1));

  const assignments = [];
  for (const task of ordered) {
    const durMin = Math.max(30, Math.round((Number(task.duration_minutes) || 60) / 30) * 30);
    const neededSlots = Math.max(1, Math.round(durMin / 30));
    const pref = LOAD_PREFERENCE[task._load] || LOAD_PREFERENCE.medium;

    let bestStartIdx = -1;
    let bestScore = -1;

    for (let i = 0; i <= 48 - neededSlots; i++) {
      let ok = true;
      let scoreSum = 0;
      for (let k = 0; k < neededSlots; k++) {
        const sl = schedule.slots[i + k];
        if (!sl.inWorkday || sl.isSleep || occupied.has(i + k)) {
          ok = false;
          break;
        }
        // Tie-break gently by exact precision index (high load prefers sharper, low load prefers noisier)
        const tie = task._load === 'low' || task._load === 'routine' ? (100 - sl.precisionIndex) * 0.05 : sl.precisionIndex * 0.05;
        scoreSum += (pref[sl.tier] ?? 50) + tie;
      }
      if (ok && scoreSum / neededSlots > bestScore) {
        bestScore = scoreSum / neededSlots;
        bestStartIdx = i;
      }
    }

    if (bestStartIdx >= 0) {
      const usedSlots = [];
      for (let k = 0; k < neededSlots; k++) {
        occupied.add(bestStartIdx + k);
        usedSlots.push(schedule.slots[bestStartIdx + k]);
      }
      const startH = bestStartIdx * 0.5;
      const endH = (bestStartIdx + neededSlots) * 0.5;
      assignments.push({
        title: task.title || `Task ${task._idx + 1}`,
        cognitive_load: task._load,
        scheduled: true,
        start: engine.formatHour(startH),
        end: engine.formatHour(endH),
        duration_minutes: durMin,
        primary_tier: usedSlots[0].tier,
        predicted_cv_mean: Number((usedSlots.reduce((a, x) => a + x.cv, 0) / usedSlots.length).toFixed(4)),
        fit_score: Math.round(bestScore),
      });
    } else {
      assignments.push({
        title: task.title || `Task ${task._idx + 1}`,
        cognitive_load: task._load,
        scheduled: false,
        reason: 'No contiguous free workday slot available for requested duration',
      });
    }
  }

  return assignments.sort((a, b) => (a.start || '99:99').localeCompare(b.start || '99:99'));
}

/* ---------- MCP Tool, Resource, and Prompt Definitions ---------- */
const TOOLS = [
  {
    name: 'get_cognitive_state',
    description:
      'Get the user’s live biological cognitive precision state (peak / moderate / low_reliability), predicted CV_timing, precision index (0-100), latest AirPods auditory JND (ms), next peak countdown, and recommended/deferred task guidance.',
    inputSchema: {
      type: 'object',
      properties: {
        hour_local: {
          type: 'number',
          description: 'Optional local clock hour (0-24) to evaluate instead of current local time (e.g. 14.5 for 14:30).',
        },
        sleep_midpoint: {
          type: 'number',
          description: 'Optional override for habitual sleep midpoint in hours (e.g. 3.5 for 03:30).',
        },
        shift_hours: {
          type: 'number',
          description: 'Optional override for recent schedule shift / jet lag hours (0-6).',
        },
      },
    },
  },
  {
    name: 'get_precision_schedule',
    description:
      'Get the user’s full 24-hour Cognitive Precision Schedule divided into contiguous Peak Precision, Steady/Moderate, and Low-Reliability windows, plus the live subscribable .ics URL.',
    inputSchema: {
      type: 'object',
      properties: {
        work_start: { type: 'number', description: 'Workday start hour (default from profile, typically 8).' },
        work_end: { type: 'number', description: 'Workday end hour (default from profile, typically 20).' },
      },
    },
  },
  {
    name: 'evaluate_task_slot',
    description:
      'Evaluate and rank one or more candidate calendar time slots against the user’s personal cognitive precision curve for a given task type (deep_work, decision, meetings, routine).',
    inputSchema: {
      type: 'object',
      required: ['task_type', 'candidates'],
      properties: {
        task_type: {
          type: 'string',
          enum: ['deep_work', 'decision', 'high', 'meetings', 'medium', 'routine', 'low'],
          description: 'Cognitive demand category of the task.',
        },
        candidates: {
          type: 'array',
          description: 'Candidate slots to score, e.g. [{"start":"10:00","duration_minutes":90},{"start":"14:30","duration_minutes":90}].',
          items: {
            type: 'object',
            required: ['start'],
            properties: {
              start: { type: 'string', description: 'Start time in HH:MM (24-hour local time).' },
              duration_minutes: { type: 'number', description: 'Duration in minutes (default 60).' },
            },
          },
        },
      },
    },
  },
  {
    name: 'schedule_tasks_to_curve',
    description:
      'Automatically place a list of tasks (with cognitive_load: high | medium | low and duration_minutes) into optimal Peak Precision, Moderate, and Low-Reliability windows while respecting existing busy calendar blocks.',
    inputSchema: {
      type: 'object',
      required: ['tasks'],
      properties: {
        tasks: {
          type: 'array',
          items: {
            type: 'object',
            required: ['title'],
            properties: {
              title: { type: 'string' },
              cognitive_load: { type: 'string', enum: ['high', 'medium', 'low'] },
              duration_minutes: { type: 'number' },
            },
          },
        },
        busy_blocks: {
          type: 'array',
          description: 'Existing busy intervals to avoid, e.g. [{"start":"11:00","end":"12:00"}].',
          items: {
            type: 'object',
            required: ['start', 'end'],
            properties: {
              start: { type: 'string' },
              end: { type: 'string' },
            },
          },
        },
      },
    },
  },
  {
    name: 'export_ics_schedule',
    description:
      'Generate an RFC 5545 .ics Cognitive Precision Schedule (for Apple Calendar, Google Calendar, or Outlook), optionally saving it to a file path on disk.',
    inputSchema: {
      type: 'object',
      properties: {
        days: { type: 'number', description: 'Number of days to generate (1-28, default 7).' },
        include_morning_check: { type: 'boolean', description: 'Include daily 60s AirPods check reminders (default true).' },
        output_path: { type: 'string', description: 'Optional file path to write the .ics file (e.g. ~/Desktop/graviton-schedule.ics).' },
      },
    },
  },
  {
    name: 'log_calibration_check',
    description:
      'Save a completed ChronoScope behavioral calibration check (CV_timing, optional auditory JND ms, sleep midpoint, shift hours) to the shared local profile (~/.graviton/chronoscope-profile.json) used by the macOS companion app and MCP server.',
    inputSchema: {
      type: 'object',
      required: ['cv_timing'],
      properties: {
        cv_timing: { type: 'number', description: 'Measured timing reliability CV = sigma / mu (e.g. 0.048).' },
        jnd_ms: { type: 'number', description: 'Optional auditory/visual two-pulse JND in milliseconds (e.g. 16.5).' },
        hour_local: { type: 'number', description: 'Local clock hour of measurement (defaults to now).' },
        sleep_midpoint: { type: 'number', description: 'Habitual sleep midpoint in local hours (e.g. 3.5).' },
        shift_hours: { type: 'number', description: 'Recent schedule shift / jet lag hours (0-6).' },
        alertness: { type: 'number', description: 'Subjective alertness 1-10.' },
        sleep_pressure_s: { type: 'number', description: 'Hours awake at time of check.' },
      },
    },
  },
];

const RESOURCES = [
  {
    uri: 'chronoscope://state/current',
    name: 'Current Cognitive Precision State',
    description: 'Real-time graviton-cognitive-state/v1 JSON derived from local ChronoScope profile.',
    mimeType: 'application/json',
  },
  {
    uri: 'chronoscope://schedule/today.ics',
    name: 'Cognitive Precision Schedule (.ics)',
    description: 'RFC 5545 calendar schedule with Peak Precision and Low-Reliability windows.',
    mimeType: 'text/calendar',
  },
];

const PROMPTS = [
  {
    name: 'plan_my_day_by_precision',
    description: 'Inject live ChronoScope biological precision windows so the AI schedules deep work in Peak blocks and admin in Low-Reliability dips.',
    arguments: [],
  },
];

/* ---------- Tool Execution ---------- */
function callTool(name, args = {}) {
  switch (name) {
    case 'get_cognitive_state': {
      const { profile, schedule } = computeFromProfile(args);
      const out = {
        ...schedule.signal,
        profile_path: PROFILE_PATH,
        logged_sessions: profile.sessions.length,
        healthkit_context: profile.healthkit_context,
        live_api_url: buildLiveApiUrl(profile, schedule, 'json'),
      };
      return { content: [{ type: 'text', text: JSON.stringify(out, null, 2) }] };
    }

    case 'get_precision_schedule': {
      const { profile, schedule } = computeFromProfile(args);
      const out = {
        schema: schedule.signal.schema,
        mode: schedule.signal.mode,
        mode_label: schedule.signal.mode_label,
        local_time: schedule.signal.local_time,
        current_state: schedule.signal.state,
        blocks: schedule.blocks,
        live_api_url: buildLiveApiUrl(profile, schedule, 'json'),
        subscribable_ics_url: buildLiveApiUrl(profile, schedule, 'ics'),
        epistemic_boundary: engine.EPISTEMIC_BOUNDARY,
      };
      return { content: [{ type: 'text', text: JSON.stringify(out, null, 2) }] };
    }

    case 'evaluate_task_slot': {
      const { schedule } = computeFromProfile({});
      const ranked = evaluateCandidateSlots(schedule, args.task_type, args.candidates || []);
      return {
        content: [
          {
            type: 'text',
            text: JSON.stringify(
              {
                task_type: args.task_type,
                mode: schedule.signal.mode_label,
                recommended_slot: ranked[0] || null,
                ranked_candidates: ranked,
                epistemic_boundary: engine.EPISTEMIC_BOUNDARY,
              },
              null,
              2
            ),
          },
        ],
      };
    }

    case 'schedule_tasks_to_curve': {
      const { schedule } = computeFromProfile({});
      const plan = scheduleTasksToCurve(schedule, args.tasks || [], args.busy_blocks || []);
      return {
        content: [
          {
            type: 'text',
            text: JSON.stringify(
              {
                mode: schedule.signal.mode_label,
                workday: schedule.signal.windows_today.workday,
                peak_windows: schedule.signal.windows_today.peak,
                low_reliability_windows: schedule.signal.windows_today.low_reliability,
                scheduled_plan: plan,
                epistemic_boundary: engine.EPISTEMIC_BOUNDARY,
              },
              null,
              2
            ),
          },
        ],
      };
    }

    case 'export_ics_schedule': {
      const { profile, schedule } = computeFromProfile({});
      const days = Number(args.days) || 7;
      const includeMorningCheck = args.include_morning_check !== false;
      const ics = engine.generateIcsCalendar(schedule, { days, includeMorningCheck });
      let savedTo = null;
      if (args.output_path) {
        const resolved = args.output_path.startsWith('~/')
          ? path.join(os.homedir(), args.output_path.slice(2))
          : path.resolve(args.output_path);
        fs.mkdirSync(path.dirname(resolved), { recursive: true });
        fs.writeFileSync(resolved, ics, 'utf8');
        savedTo = resolved;
      }
      return {
        content: [
          {
            type: 'text',
            text: JSON.stringify(
              {
                saved_to: savedTo,
                days,
                subscribable_ics_url: buildLiveApiUrl(profile, schedule, 'ics'),
                ics_preview: ics.split('\r\n').slice(0, 24).join('\n'),
                ics_bytes: Buffer.byteLength(ics, 'utf8'),
              },
              null,
              2
            ),
          },
        ],
      };
    }

    case 'log_calibration_check': {
      const cvTiming = Number(args.cv_timing);
      if (!Number.isFinite(cvTiming) || cvTiming <= 0 || cvTiming > 1) {
        return {
          isError: true,
          content: [{ type: 'text', text: 'cv_timing must be a positive number between 0 and 1 (e.g. 0.048).' }],
        };
      }
      const profile = loadProfile();
      const now = new Date();
      const hourLocal =
        typeof args.hour_local === 'number' && Number.isFinite(args.hour_local)
          ? args.hour_local
          : now.getHours() + now.getMinutes() / 60;
      if (typeof args.sleep_midpoint === 'number') profile.settings.sleep_midpoint = args.sleep_midpoint;
      if (typeof args.shift_hours === 'number') profile.settings.shift_hours = args.shift_hours;
      if (typeof args.alertness === 'number') profile.settings.alertness = args.alertness;

      const mid = profile.settings.sleep_midpoint;
      const shiftH = profile.settings.shift_hours;
      const phaseDeg = ((((hourLocal - mid) % 24) + 24) % 24) * 15;
      const rec = {
        iso: now.toISOString(),
        hour_local: Number(hourLocal.toFixed(3)),
        sleep_midpoint: mid,
        phase_deg: Number(phaseDeg.toFixed(1)),
        sleep_pressure_s: Number(args.sleep_pressure_s ?? Math.max(0.5, (((hourLocal - (mid + 3.75)) % 24) + 24) % 24)),
        alertness: profile.settings.alertness,
        shift_hours: shiftH,
        cv_timing: Number(cvTiming.toFixed(5)),
        jnd_ms: typeof args.jnd_ms === 'number' ? Number(args.jnd_ms.toFixed(1)) : null,
        bias: 1.0,
        source: 'mcp',
        synthetic: false,
      };
      profile.sessions.push(rec);
      saveProfile(profile);

      const { schedule } = computeFromProfile({});
      return {
        content: [
          {
            type: 'text',
            text: JSON.stringify(
              {
                status: 'saved',
                profile_path: PROFILE_PATH,
                total_sessions: profile.sessions.length,
                updated_state: schedule.signal,
              },
              null,
              2
            ),
          },
        ],
      };
    }

    default:
      throw { code: -32601, message: `Unknown tool: ${name}` };
  }
}

/* ---------- JSON-RPC 2.0 Stdio Transport ---------- */
function send(msg) {
  process.stdout.write(JSON.stringify(msg) + '\n');
}

function handleRequest(req) {
  const { id, method, params } = req;
  // Notifications (no id) require no response
  if (id === undefined || id === null) return;

  try {
    if (method === 'initialize') {
      return send({
        jsonrpc: '2.0',
        id,
        result: {
          protocolVersion: params?.protocolVersion || PROTOCOL_VERSION,
          capabilities: {
            tools: {},
            resources: {},
            prompts: {},
          },
          serverInfo: SERVER_INFO,
        },
      });
    }

    if (method === 'ping') {
      return send({ jsonrpc: '2.0', id, result: {} });
    }

    if (method === 'tools/list') {
      return send({ jsonrpc: '2.0', id, result: { tools: TOOLS } });
    }

    if (method === 'tools/call') {
      const result = callTool(params?.name, params?.arguments || {});
      return send({ jsonrpc: '2.0', id, result });
    }

    if (method === 'resources/list') {
      return send({ jsonrpc: '2.0', id, result: { resources: RESOURCES } });
    }

    if (method === 'resources/read') {
      const uri = params?.uri;
      const { schedule } = computeFromProfile({});
      if (uri === 'chronoscope://state/current') {
        return send({
          jsonrpc: '2.0',
          id,
          result: {
            contents: [{ uri, mimeType: 'application/json', text: JSON.stringify(schedule.signal, null, 2) }],
          },
        });
      }
      if (uri === 'chronoscope://schedule/today.ics') {
        return send({
          jsonrpc: '2.0',
          id,
          result: {
            contents: [{ uri, mimeType: 'text/calendar', text: engine.generateIcsCalendar(schedule, { days: 7 }) }],
          },
        });
      }
      throw { code: -32002, message: `Resource not found: ${uri}` };
    }

    if (method === 'prompts/list') {
      return send({ jsonrpc: '2.0', id, result: { prompts: PROMPTS } });
    }

    if (method === 'prompts/get') {
      if (params?.name !== 'plan_my_day_by_precision') {
        throw { code: -32602, message: `Unknown prompt: ${params?.name}` };
      }
      const { profile, schedule } = computeFromProfile({});
      const apiUrl = buildLiveApiUrl(profile, schedule, 'json');
      const promptText = engine.buildAiContextPrompt(schedule, apiUrl);
      return send({
        jsonrpc: '2.0',
        id,
        result: {
          description: 'Live ChronoScope Cognitive Precision scheduling instructions',
          messages: [{ role: 'user', content: { type: 'text', text: promptText } }],
        },
      });
    }

    throw { code: -32601, message: `Method not found: ${method}` };
  } catch (err) {
    send({
      jsonrpc: '2.0',
      id,
      error: {
        code: err.code || -32603,
        message: err.message || String(err),
      },
    });
  }
}

const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
rl.on('line', (line) => {
  const trimmed = line.trim();
  if (!trimmed) return;
  try {
    const req = JSON.parse(trimmed);
    handleRequest(req);
  } catch {
    send({ jsonrpc: '2.0', id: null, error: { code: -32700, message: 'Parse error' } });
  }
});
