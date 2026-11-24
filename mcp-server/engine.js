/* ==========================================================================
   Graviton ChronoScope — Cognitive Precision Curve, Scheduler & AI Signal
   Shared single-source-of-truth engine (Browser UMD + Node / Vercel API)
   Schema: graviton-cognitive-state/v1
   ========================================================================== */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.GravitonCognitiveEngine = factory();
  }
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  const SCHEMA_VERSION = 'graviton-cognitive-state/v1';
  const TWO_PI = Math.PI * 2;
  const SLOT_MINUTES = 30;
  const SLOTS_PER_DAY = 48; // 00:00 .. 23:30

  const EPISTEMIC_BOUNDARY =
    'Behavioral timing model estimate derived from circadian phase, sleep pressure, and optional psychophysics calibration. Not a medical device, clinical sleep assessment, or direct neural measurement.';

  const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));

  const mod24 = (h) => ((h % 24) + 24) % 24;

  const formatHour = (h) => {
    const norm = mod24(h);
    let hh = Math.floor(norm);
    let mm = Math.round((norm - hh) * 60);
    if (mm === 60) {
      hh = (hh + 1) % 24;
      mm = 0;
    }
    return `${String(hh).padStart(2, '0')}:${String(mm).padStart(2, '0')}`;
  };

  const formatDurationMinutes = (mins) => {
    const m = Math.max(0, Math.round(mins));
    const h = Math.floor(m / 60);
    const rem = m % 60;
    if (h === 0) return `${rem}m`;
    if (rem === 0) return `${h}h`;
    return `${h}h ${rem}m`;
  };

  // Tiny exact Gaussian elimination solver for 6x6 ridge normal equations
  const solveLinear = (A, b) => {
    const n = b.length;
    const M = A.map((row, i) => [...row, b[i]]);
    for (let i = 0; i < n; i++) {
      let piv = i;
      for (let r = i + 1; r < n; r++) {
        if (Math.abs(M[r][i]) > Math.abs(M[piv][i])) piv = r;
      }
      [M[i], M[piv]] = [M[piv], M[i]];
      const diag = Math.abs(M[i][i]) > 1e-12 ? M[i][i] : 1e-9;
      for (let j = i; j <= n; j++) M[i][j] /= diag;
      for (let r = 0; r < n; r++) {
        if (r === i) continue;
        const f = M[r][i];
        for (let j = i; j <= n; j++) M[r][j] -= f * M[i][j];
      }
    }
    return M.map((row) => row[n]);
  };

  /**
   * Fit Graviton Equation 01 in-browser / server:
   *   log CV_timing = alpha + betaC*cos(phi) + betaS*sin(phi) + gamma*(S/12) + eta*(A/10) + kappa*(1 - R_phi)
   */
  const fitEquation01 = (sessions) => {
    const p = 6;
    const XtX = Array.from({ length: p }, () => Array(p).fill(0));
    const Xty = Array(p).fill(0);
    for (const s of sessions) {
      const x = [
        1,
        Math.cos(s.phaseRad),
        Math.sin(s.phaseRad),
        s.sleepPressureS / 12,
        s.alertnessA / 10,
        s.misalignmentProxy,
      ];
      const y = Math.log(Math.max(1e-4, s.cvTiming));
      for (let i = 0; i < p; i++) {
        Xty[i] += x[i] * y;
        for (let j = 0; j < p; j++) XtX[i][j] += x[i] * x[j];
      }
    }
    // Mild L2 ridge on non-intercept terms for numerical stability at small N
    for (let i = 1; i < p; i++) XtX[i][i] += 0.08;
    const w = solveLinear(XtX, Xty);
    const amp = Math.hypot(w[1], w[2]);
    return {
      alpha: w[0],
      betaC: w[1],
      betaS: w[2],
      amp,
      gamma: w[3],
      eta: w[4],
      kappa: w[5],
    };
  };

  /**
   * Estimate habitual wake hour assuming a 7.5 h sleep window centered on sleepMidpoint.
   */
  const getWakeHour = (sleepMidpoint) => mod24(sleepMidpoint + 3.75);
  const getSleepStartHour = (sleepMidpoint) => mod24(sleepMidpoint - 3.75);

  const isInWindow = (hour, start, end) => {
    const h = mod24(hour);
    const s = mod24(start);
    const e = mod24(end);
    if (s === e) return true;
    if (s < e) return h >= s && h < e;
    return h >= s || h < e;
  };

  const hoursAwakeAt = (hour, sleepMidpoint) => {
    const wake = getWakeHour(sleepMidpoint);
    const sinceWake = mod24(hour - wake);
    // During sleep window (16.5..24h since wake), treat as resting/resetting
    return sinceWake <= 16.5 ? sinceWake : 0;
  };

  /**
   * Uncalibrated physiological chronotype prior for log(CV_timing) at clock hour `hour`.
   * Captures:
   *  - Circadian nadir near sleep midpoint (phi = 0) and morning peak ~3.5-5h post-wake (phi ~ 110 deg)
   *  - Post-lunch dip harmonic (~7-9h post-wake, phi ~ 165 deg)
   *  - Linear homeostatic sleep-pressure accumulation (gamma * S)
   *  - Misalignment penalty kappa * (1 - R_phi) from recent schedule shift
   */
  const priorLogCvRaw = (hour, sleepMidpoint, shiftHours, alertnessA) => {
    const phaseDeg = mod24(hour - sleepMidpoint) * 15;
    const phi = (phaseDeg * Math.PI) / 180;
    const awake = hoursAwakeAt(hour, sleepMidpoint);
    const misalignment = clamp(shiftHours / 6, 0, 1);

    // Primary circadian cosine: nadir at sleep midpoint (phi = 0), sharpest circadian drive around phi = 125 deg (~11:30 for 03:30 mid)
    const circ1 = 0.22 * Math.cos(phi - 0.10) - 0.14 * Math.sin(phi - 0.10);
    // Brief morning sleep-inertia tail in the first ~60 min after waking
    const inertia = awake < 2.5 ? 0.10 * Math.exp(-awake / 0.65) : 0;
    // Post-lunch circadian dip (~7.5h post-wake, phi ~ 168 deg -> ~14:30 for 03:30 mid)
    const dipCenter = (168 * Math.PI) / 180;
    const postLunchDip = 0.21 * Math.exp(-Math.pow(Math.sin((phi - dipCenter) / 2), 2) / 0.032);
    // Homeostatic sleep pressure S accumulation across waking hours
    const sleepTerm = 0.28 * Math.pow(awake / 16, 1.35);
    // Subjective alertness offset (centered on 7/10)
    const alertTerm = -0.028 * ((alertnessA - 7) / 3);
    // Schedule misalignment penalty kappa * (1 - R_phi)
    const misalignTerm = 0.34 * misalignment;

    // Base log(0.058) ≈ -2.847
    return -2.847 + circ1 + inertia + postLunchDip + sleepTerm + alertTerm + misalignTerm;
  };

  /**
   * Evaluate predicted log(CV) and CV at any local hour `hour`.
   */
  const evaluateLogCv = (hour, params) => {
    const {
      sleepMidpoint = 3.5,
      shiftHours = 0.5,
      alertnessA = 7,
      fit = null,
      calibration = null,
    } = params;

    if (fit) {
      const phaseRad = (mod24(hour - sleepMidpoint) * 15 * Math.PI) / 180;
      const awake = hoursAwakeAt(hour, sleepMidpoint);
      const misalignment = clamp(shiftHours / 6, 0, 1);
      const logCv =
        fit.alpha +
        fit.betaC * Math.cos(phaseRad) +
        fit.betaS * Math.sin(phaseRad) +
        fit.gamma * (awake / 12) +
        fit.eta * (alertnessA / 10) +
        fit.kappa * misalignment;
      return clamp(logCv, Math.log(0.02), Math.log(0.35));
    }

    let logCv = priorLogCvRaw(hour, sleepMidpoint, shiftHours, alertnessA);
    if (calibration && typeof calibration.cvTiming === 'number' && calibration.cvTiming > 0) {
      const calHour = typeof calibration.hourLocal === 'number' ? calibration.hourLocal : hour;
      const calShift = typeof calibration.shiftHours === 'number' ? calibration.shiftHours : shiftHours;
      const calAlert = typeof calibration.alertnessA === 'number' ? calibration.alertnessA : alertnessA;
      const expectedAtCal = priorLogCvRaw(calHour, sleepMidpoint, calShift, calAlert);
      const observedLog = Math.log(clamp(calibration.cvTiming, 0.02, 0.35));
      // Anchors the prior curve cleanly to the user's measured 60-second check
      const anchorOffset = clamp(observedLog - expectedAtCal, -0.75, 0.75);
      logCv += anchorOffset;
    }
    return clamp(logCv, Math.log(0.02), Math.log(0.35));
  };

  /**
   * Formally verified 3-tier classifier (mirrors Lean 4 theorem CT-04 in CircadianTiming.lean):
   *   score <= tauPeak        -> 'peak'
   *   tauPeak < score <= tauLow -> 'moderate'
   *   score > tauLow          -> 'low_reliability'
   */
  const classifyTier = (tauPeak, tauLow, score) => {
    if (score <= tauPeak) return 'peak';
    if (score <= tauLow) return 'moderate';
    return 'low_reliability';
  };

  const TIER_META = {
    peak: {
      label: 'Peak Precision',
      shortLabel: 'PEAK',
      recommended: [
        'Deep analytical work, proofs, architecture, and complex coding',
        'High-stakes writing, research synthesis, and strategic decisions',
        'Tasks sensitive to subtle errors or temporal focus',
      ],
      defer: ['Inbox triage, routine admin, and passive status meetings'],
    },
    moderate: {
      label: 'Steady / Moderate',
      shortLabel: 'MODERATE',
      recommended: [
        'Collaborative sessions, code reviews, and structured implementation',
        'Meetings, feedback loops, and medium-complexity execution',
      ],
      defer: ['Most fragile first-principles work if a Peak block is upcoming'],
    },
    low_reliability: {
      label: 'Low Reliability · Routine',
      shortLabel: 'ROUTINE',
      recommended: [
        'Routine administration, email, scheduling, and logistics',
        'Low-stakes organization, light reading, or a short walk/reset',
      ],
      defer: [
        'High-precision quantitative work, irreversible decisions, or dense debugging',
      ],
    },
    rest: {
      label: 'Off-Hours / Recovery',
      shortLabel: 'RECOVERY',
      recommended: ['Wind-down, circadian light hygiene, and restorative sleep'],
      defer: ['Cognitive performance work and bright-screen late sessions'],
    },
  };

  /**
   * Build the complete 24-hour precision curve, tier thresholds, contiguous schedule blocks,
   * and real-time `graviton-cognitive-state/v1` signal.
   */
  const computeCognitiveSchedule = (options = {}) => {
    const now = options.now instanceof Date ? options.now : new Date();
    const sleepMidpoint = clamp(Number(options.sleepMidpoint ?? 3.5), 0, 12);
    const shiftHours = clamp(Number(options.shiftHours ?? 0.5), 0, 6);
    const alertnessA = clamp(Number(options.alertnessA ?? 7), 1, 10);
    const workStart = clamp(Number(options.workStart ?? 8), 0, 23.5);
    const workEnd = clamp(Number(options.workEnd ?? 20), 0.5, 24);
    const hourLocal =
      typeof options.hourLocal === 'number' && Number.isFinite(options.hourLocal)
        ? mod24(options.hourLocal)
        : now.getHours() + now.getMinutes() / 60;

    const sessions = Array.isArray(options.sessions) ? options.sessions : [];
    const providedFit = options.fit || null;
    const providedCal = options.calibration || null;

    let mode = 'chronotype_prior';
    let modeLabel = 'Chronotype Prior (uncalibrated)';
    let fit = null;
    let calibration = null;
    let includesSyntheticDemo = false;

    if (providedFit && typeof providedFit.alpha === 'number') {
      fit = providedFit;
      mode = 'empirical_fit';
      modeLabel = 'Empirical Equation 01 Fit (parameters)';
    } else if (sessions.length >= 4) {
      fit = fitEquation01(sessions);
      includesSyntheticDemo = sessions.some((s) => s.synthetic);
      mode = includesSyntheticDemo ? 'synthetic_demo_fit' : 'empirical_fit';
      modeLabel = includesSyntheticDemo
        ? `Demo Equation 01 Fit (${sessions.length} synthetic sessions)`
        : `Empirical Equation 01 Fit (${sessions.length} sessions)`;
    } else if (providedCal && typeof providedCal.cvTiming === 'number' && providedCal.cvTiming > 0) {
      calibration = providedCal;
      mode = 'morning_check_prior';
      modeLabel = '60s Check + Chronotype Prior';
    } else if (sessions.length >= 1) {
      const latest = sessions[sessions.length - 1];
      calibration = latest;
      includesSyntheticDemo = Boolean(latest.synthetic);
      mode = 'morning_check_prior';
      modeLabel = `Calibrated Prior (${sessions.length} check${sessions.length > 1 ? 's' : ''})`;
    }

    const evalParams = { sleepMidpoint, shiftHours, alertnessA, fit, calibration };

    // 1. Sample 48 half-hour slots across 00:00..23:30
    const rawSlots = [];
    for (let i = 0; i < SLOTS_PER_DAY; i++) {
      const hour = (i * SLOT_MINUTES) / 60;
      const logCv = evaluateLogCv(hour, evalParams);
      const cv = Math.exp(logCv);
      const inWorkday = isInWindow(hour, workStart, workEnd);
      const wake = getWakeHour(sleepMidpoint);
      const sleepStart = getSleepStartHour(sleepMidpoint);
      const isSleep = isInWindow(hour, sleepStart, wake);
      rawSlots.push({
        index: i,
        hour,
        label: formatHour(hour),
        logCv,
        cv,
        inWorkday,
        isSleep,
      });
    }

    // 2. Compute deterministic tier thresholds (tauPeak < tauLow) over active workday slots
    const activeSlots = rawSlots.filter((s) => s.inWorkday && !s.isSleep);
    const pool = activeSlots.length >= 4 ? activeSlots : rawSlots;
    const sortedScores = pool.map((s) => s.logCv).sort((a, b) => a - b);
    const idxPeak = Math.max(0, Math.floor(sortedScores.length * 0.30) - 1);
    const idxLow = Math.min(sortedScores.length - 1, Math.floor(sortedScores.length * 0.72));
    const tauPeak = sortedScores[idxPeak];
    // Guarantee strict separation tauPeak < tauLow for theorem CT-04
    const tauLow = Math.max(sortedScores[idxLow], tauPeak + 1e-6);

    const minLog = Math.min(...rawSlots.map((s) => s.logCv));
    const maxLog = Math.max(...rawSlots.map((s) => s.logCv));
    const span = Math.max(0.05, maxLog - minLog);

    const slots = rawSlots.map((s) => {
      const tier = !s.inWorkday || s.isSleep ? 'rest' : classifyTier(tauPeak, tauLow, s.logCv);
      const precisionIndex = Math.round(clamp((1 - (s.logCv - minLog) / span) * 100, 5, 99));
      return {
        ...s,
        tier,
        precisionIndex,
      };
    });

    // 3. Merge contiguous slots of the same tier into clean blocks (workday blocks only)
    const blocks = [];
    let cur = null;
    for (let i = 0; i < slots.length; i++) {
      const sl = slots[i];
      if (sl.tier === 'rest') {
        if (cur) {
          blocks.push(cur);
          cur = null;
        }
        continue;
      }
      if (!cur || cur.tier !== sl.tier) {
        if (cur) blocks.push(cur);
        cur = {
          tier: sl.tier,
          label: TIER_META[sl.tier].label,
          startHour: sl.hour,
          endHour: sl.hour + SLOT_MINUTES / 60,
          start: formatHour(sl.hour),
          end: formatHour(sl.hour + SLOT_MINUTES / 60),
          slots: [sl],
        };
      } else {
        cur.endHour = sl.hour + SLOT_MINUTES / 60;
        cur.end = formatHour(cur.endHour);
        cur.slots.push(sl);
      }
    }
    if (cur) blocks.push(cur);

    const summaryBlocks = blocks.map((b) => {
      const avgCv = b.slots.reduce((a, x) => a + x.cv, 0) / b.slots.length;
      const avgIdx = Math.round(b.slots.reduce((a, x) => a + x.precisionIndex, 0) / b.slots.length);
      return {
        tier: b.tier,
        label: b.label,
        start: b.start,
        end: b.end,
        start_hour: b.startHour,
        end_hour: b.endHour,
        duration_minutes: Math.round((b.endHour - b.startHour) * 60),
        predicted_cv_mean: Number(avgCv.toFixed(4)),
        precision_index: avgIdx,
      };
    });

    // 4. Current instant evaluation
    const currentLogCv = evaluateLogCv(hourLocal, evalParams);
    const currentCv = Math.exp(currentLogCv);
    const currentPhaseDeg = mod24(hourLocal - sleepMidpoint) * 15;
    const currentAwake = hoursAwakeAt(hourLocal, sleepMidpoint);
    const currentInWorkday = isInWindow(hourLocal, workStart, workEnd);
    const currentIsSleep = isInWindow(hourLocal, getSleepStartHour(sleepMidpoint), getWakeHour(sleepMidpoint));
    const currentTier =
      !currentInWorkday || currentIsSleep ? 'rest' : classifyTier(tauPeak, tauLow, currentLogCv);
    const currentPrecisionIndex = Math.round(clamp((1 - (currentLogCv - minLog) / span) * 100, 5, 99));

    // Find next peak block or remaining duration in active peak block
    const peakBlocks = summaryBlocks.filter((b) => b.tier === 'peak');
    const routineBlocks = summaryBlocks.filter((b) => b.tier === 'low_reliability');
    const moderateBlocks = summaryBlocks.filter((b) => b.tier === 'moderate');

    let nextPeakInMinutes = null;
    let activePeakRemainingMinutes = null;
    let nextPeakWindow = null;

    if (peakBlocks.length > 0) {
      const activePeak = peakBlocks.find((b) => hourLocal >= b.start_hour && hourLocal < b.end_hour);
      if (activePeak) {
        activePeakRemainingMinutes = Math.max(1, Math.round((activePeak.end_hour - hourLocal) * 60));
        nextPeakInMinutes = 0;
        nextPeakWindow = `${activePeak.start}–${activePeak.end}`;
      } else {
        let bestDelta = Infinity;
        for (const b of peakBlocks) {
          let delta = b.start_hour - hourLocal;
          if (delta <= 0) delta += 24;
          if (delta < bestDelta) {
            bestDelta = delta;
            nextPeakWindow = `${b.start}–${b.end}`;
          }
        }
        nextPeakInMinutes = Math.round(bestDelta * 60);
      }
    }

    const latestJndMs =
      calibration && typeof calibration.jndMs === 'number'
        ? calibration.jndMs
        : sessions.length > 0 && typeof sessions[sessions.length - 1].jndMs === 'number'
          ? sessions[sessions.length - 1].jndMs
          : null;

    const tierInfo = TIER_META[currentTier];

    const signal = {
      schema: SCHEMA_VERSION,
      generated_at: now.toISOString(),
      local_time: formatHour(hourLocal),
      state: currentTier,
      state_label: tierInfo.label,
      mode,
      mode_label: modeLabel,
      includes_synthetic_demo: includesSyntheticDemo,
      current: {
        predicted_cv: Number(currentCv.toFixed(4)),
        precision_index: currentPrecisionIndex,
        latest_jnd_ms: latestJndMs !== null ? Number(latestJndMs.toFixed(1)) : null,
        phase_deg: Math.round(currentPhaseDeg),
        estimated_hours_awake: Number(currentAwake.toFixed(1)),
        schedule_shift_h: Number(shiftHours.toFixed(1)),
        misalignment_proxy: Number(clamp(shiftHours / 6, 0, 1).toFixed(3)),
      },
      thresholds: {
        tau_peak_log_cv: Number(tauPeak.toFixed(4)),
        tau_low_log_cv: Number(tauLow.toFixed(4)),
        peak_cv_cutoff: Number(Math.exp(tauPeak).toFixed(4)),
        low_cv_cutoff: Number(Math.exp(tauLow).toFixed(4)),
        lean_theorem: 'GravitonCert.Studies.CircadianTiming.tier_classifier_soundness (CT-04)',
      },
      windows_today: {
        workday: [formatHour(workStart), formatHour(workEnd)],
        peak: peakBlocks.map((b) => ({
          start: b.start,
          end: b.end,
          predicted_cv: b.predicted_cv_mean,
          precision_index: b.precision_index,
        })),
        moderate: moderateBlocks.map((b) => ({
          start: b.start,
          end: b.end,
          predicted_cv: b.predicted_cv_mean,
          precision_index: b.precision_index,
        })),
        low_reliability: routineBlocks.map((b) => ({
          start: b.start,
          end: b.end,
          predicted_cv: b.predicted_cv_mean,
          precision_index: b.precision_index,
        })),
      },
      ai_guidance: {
        active_peak_remaining_minutes: activePeakRemainingMinutes,
        next_peak_in_minutes: nextPeakInMinutes,
        next_peak_window: nextPeakWindow,
        recommended_tasks: tierInfo.recommended,
        defer_tasks: tierInfo.defer,
      },
      epistemic_boundary: EPISTEMIC_BOUNDARY,
    };

    return {
      signal,
      slots,
      blocks: summaryBlocks,
      fit,
      tauPeak,
      tauLow,
      hourLocal,
      sleepMidpoint,
      workStart,
      workEnd,
    };
  };

  /* ---------- RFC 5545 .ics Calendar Generator ---------- */
  const pad2 = (n) => String(n).padStart(2, '0');

  const formatIcsUtcStamp = (d) =>
    `${d.getUTCFullYear()}${pad2(d.getUTCMonth() + 1)}${pad2(d.getUTCDate())}T${pad2(d.getUTCHours())}${pad2(d.getUTCMinutes())}${pad2(d.getUTCSeconds())}Z`;

  const formatIcsLocalDateTime = (year, month, day, hourFloat) => {
    const h = Math.floor(hourFloat);
    const m = Math.round((hourFloat - h) * 60);
    return `${year}${pad2(month)}${pad2(day)}T${pad2(h)}${pad2(m)}00`;
  };

  const escapeIcsText = (str) =>
    String(str)
      .replace(/\\/g, '\\\\')
      .replace(/;/g, '\\;')
      .replace(/,/g, '\\,')
      .replace(/\r?\n/g, '\\n');

  // RFC 5545 Section 3.1 line folding at 74 chars with CRLF + single space
  const foldIcsLine = (line) => {
    if (line.length <= 74) return line;
    const chunks = [];
    chunks.push(line.slice(0, 74));
    let pos = 74;
    while (pos < line.length) {
      chunks.push(' ' + line.slice(pos, pos + 73));
      pos += 73;
    }
    return chunks.join('\r\n');
  };

  /**
   * Generate an RFC 5545-compliant .ics Cognitive Precision Schedule.
   * Uses floating local time (DTSTART:YYYYMMDDTHHMMSS) so imported calendar blocks
   * stay pinned to the user's actual local wall-clock time across Apple/Google/Outlook.
   */
  const generateIcsCalendar = (scheduleResult, opts = {}) => {
    const days = clamp(parseInt(opts.days ?? 7, 10) || 7, 1, 28);
    const includeCheck = opts.includeMorningCheck !== false;
    const includeModerate = Boolean(opts.includeModerate);
    const now = opts.now instanceof Date ? opts.now : new Date();
    const dtstamp = formatIcsUtcStamp(now);
    const sig = scheduleResult.signal;

    const lines = [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Graviton Research Foundation//ChronoScope Cognitive Schedule//EN',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      'X-WR-CALNAME:Graviton Cognitive Precision Schedule',
      `X-WR-CALDESC:${escapeIcsText(`Personal circadian timing schedule (${sig.mode_label}). ${EPISTEMIC_BOUNDARY}`)}`,
    ];

    const startDate = opts.startDate instanceof Date
      ? new Date(opts.startDate.getTime())
      : new Date(now.getFullYear(), now.getMonth(), now.getDate());

    const pushEvent = ({ uid, y, mo, d, startH, endH, summary, description, categories, busy, alarmMin }) => {
      const safeEnd = endH > startH ? endH : Math.min(23.95, startH + 0.5);
      lines.push('BEGIN:VEVENT');
      lines.push(`UID:${uid}`);
      lines.push(`DTSTAMP:${dtstamp}`);
      lines.push(`DTSTART:${formatIcsLocalDateTime(y, mo, d, startH)}`);
      lines.push(`DTEND:${formatIcsLocalDateTime(y, mo, d, safeEnd)}`);
      lines.push(`SUMMARY:${escapeIcsText(summary)}`);
      lines.push(`DESCRIPTION:${escapeIcsText(description)}`);
      lines.push(`CATEGORIES:${categories}`);
      lines.push(`TRANSP:${busy ? 'OPAQUE' : 'TRANSPARENT'}`);
      lines.push('URL:https://gravitonresearch.org/lab/chronoscope/');
      if (alarmMin && alarmMin > 0) {
        lines.push('BEGIN:VALARM');
        lines.push('ACTION:DISPLAY');
        lines.push(`TRIGGER:-PT${alarmMin}M`);
        lines.push(`DESCRIPTION:${escapeIcsText(summary)}`);
        lines.push('END:VALARM');
      }
      lines.push('END:VEVENT');
    };

    const wakeHour = getWakeHour(scheduleResult.sleepMidpoint);
    const checkHour = clamp(Math.round((wakeHour + 0.5) * 2) / 2, 5, 11.5);

    for (let dayOffset = 0; dayOffset < days; dayOffset++) {
      const dt = new Date(startDate.getFullYear(), startDate.getMonth(), startDate.getDate() + dayOffset);
      const y = dt.getFullYear();
      const mo = dt.getMonth() + 1;
      const d = dt.getDate();
      const dateTag = `${y}${pad2(mo)}${pad2(d)}`;

      if (includeCheck) {
        pushEvent({
          uid: `graviton-check-${dateTag}@gravitonresearch.org`,
          y,
          mo,
          d,
          startH: checkHour,
          endH: checkHour + 0.25,
          summary: '[Graviton Check] 60s ChronoScope Calibration (AirPods Ready)',
          description:
            'Run a 60-second auditory two-pulse JND + duration reproduction check with AirPods or speakers at https://gravitonresearch.org/lab/chronoscope/ to recalibrate today’s peak precision curve.',
          categories: 'GRAVITON,CALIBRATION',
          busy: false,
          alarmMin: 5,
        });
      }

      scheduleResult.blocks.forEach((b, bIdx) => {
        if (b.tier === 'peak') {
          pushEvent({
            uid: `graviton-peak-${dateTag}-${bIdx}@gravitonresearch.org`,
            y,
            mo,
            d,
            startH: b.start_hour,
            endH: b.end_hour,
            summary: `[Graviton Peak] High-Precision Deep Work (CV ~${b.predicted_cv_mean.toFixed(3)})`,
            description:
              `Protected Peak Precision Window (${b.start}–${b.end}, Precision Index ${b.precision_index}/100, predicted CV_timing ${b.predicted_cv_mean.toFixed(4)}).\n` +
              `Model: ${sig.mode_label}.\n` +
              `Best for: Deep analytical work, coding, writing, hard decisions.\n` +
              `Boundary: ${EPISTEMIC_BOUNDARY}`,
            categories: 'GRAVITON,PEAK_PRECISION,DEEP_WORK',
            busy: true,
            alarmMin: 10,
          });
        } else if (b.tier === 'low_reliability') {
          pushEvent({
            uid: `graviton-routine-${dateTag}-${bIdx}@gravitonresearch.org`,
            y,
            mo,
            d,
            startH: b.start_hour,
            endH: b.end_hour,
            summary: `[Graviton Routine] Low-Reliability / Admin Window (CV ~${b.predicted_cv_mean.toFixed(3)})`,
            description:
              `Lower timing-reliability window (${b.start}–${b.end}, Precision Index ${b.precision_index}/100, predicted CV_timing ${b.predicted_cv_mean.toFixed(4)}).\n` +
              `Model: ${sig.mode_label}.\n` +
              `Best for: Email, inbox triage, routine admin, logistics, or a short recovery walk.\n` +
              `Defer: High-stakes quantitative work or complex debugging.\n` +
              `Boundary: ${EPISTEMIC_BOUNDARY}`,
            categories: 'GRAVITON,ROUTINE,ADMIN',
            busy: false,
            alarmMin: 0,
          });
        } else if (b.tier === 'moderate' && includeModerate) {
          pushEvent({
            uid: `graviton-moderate-${dateTag}-${bIdx}@gravitonresearch.org`,
            y,
            mo,
            d,
            startH: b.start_hour,
            endH: b.end_hour,
            summary: `[Graviton Steady] Collaborative & Execution Window`,
            description:
              `Moderate precision window (${b.start}–${b.end}, Precision Index ${b.precision_index}/100).\nBest for: Meetings, reviews, collaborative implementation.`,
            categories: 'GRAVITON,MODERATE',
            busy: false,
            alarmMin: 0,
          });
        }
      });
    }

    lines.push('END:VCALENDAR');
    return lines.map(foldIcsLine).join('\r\n') + '\r\n';
  };

  /**
   * Build a clean, copy-ready system prompt snippet for ChatGPT, Claude, Gemini, or AI schedulers.
   */
  const buildAiContextPrompt = (scheduleResult, apiUrl) => {
    const s = scheduleResult.signal;
    const peakList = s.windows_today.peak.map((w) => `${w.start}–${w.end}`).join(', ') || 'None in workday';
    const routineList =
      s.windows_today.low_reliability.map((w) => `${w.start}–${w.end}`).join(', ') || 'None in workday';
    const nextNote =
      s.ai_guidance.active_peak_remaining_minutes !== null
        ? `Peak window active now (${formatDurationMinutes(s.ai_guidance.active_peak_remaining_minutes)} remaining).`
        : s.ai_guidance.next_peak_in_minutes !== null
          ? `Next peak window (${s.ai_guidance.next_peak_window}) begins in ${formatDurationMinutes(s.ai_guidance.next_peak_in_minutes)}.`
          : 'No peak window remaining in configured workday.';

    return [
      `# Personal Cognitive Precision Context (Graviton ChronoScope · ${s.schema})`,
      `- Current local time: ${s.local_time} | State: ${s.state_label} (${s.current.precision_index}/100, predicted CV_timing=${s.current.predicted_cv})`,
      `- Model basis: ${s.mode_label}${s.current.latest_jnd_ms !== null ? ` | Latest auditory JND: ${s.current.latest_jnd_ms} ms` : ''}`,
      `- Peak Precision Windows today: ${peakList}`,
      `- Low-Reliability / Routine Windows today: ${routineList}`,
      `- Timing note: ${nextNote}`,
      apiUrl ? `- Live JSON API signal: ${apiUrl}` : null,
      ``,
      `Scheduling & interaction rules for you (my AI assistant):`,
      `1. Schedule deep analytical, creative, math, architecture, or high-stakes tasks strictly inside my Peak Precision Windows (${peakList}).`,
      `2. Route email, routine admin, status check-ins, and low-stakes chores to my Low-Reliability Windows (${routineList}).`,
      `3. If I ask for complex work during a Low-Reliability window, keep outputs concise, double-check edge cases, and suggest deferring irreversible decisions until ${s.ai_guidance.next_peak_window || 'my next peak window'}.`,
      `4. Epistemic note: Treat this as a behavioral timing estimate, never medical advice.`,
    ]
      .filter((x) => x !== null)
      .join('\n');
  };

  return {
    SCHEMA_VERSION,
    EPISTEMIC_BOUNDARY,
    formatHour,
    formatDurationMinutes,
    fitEquation01,
    classifyTier,
    computeCognitiveSchedule,
    generateIcsCalendar,
    buildAiContextPrompt,
  };
});
