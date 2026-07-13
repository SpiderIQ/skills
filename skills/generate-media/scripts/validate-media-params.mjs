#!/usr/bin/env node
/**
 * validate-media-params.mjs — pre-flight a media generation against the model's
 * DECLARED schema, so "schema-aware" is a fact you can check, not a hope.
 *
 * The SpiderGate media endpoint SILENTLY DROPS any param a model's `inputs` schema
 * does not declare (SF-16.1b). That means an agent can pass `seed`/`cfg_scale` to a
 * model that ignores them, pay for the generation, and get a result that quietly
 * disregarded half the request. This script closes that gap: it fetches the model's
 * declared `inputs` and classifies every param you intend to send —
 *
 *   HONORED      — declared; will reach the provider
 *   DROPPED      — NOT declared; will be silently discarded (fix or remove it)
 *   OUT-OF-ENUM  — declared enum, but your value isn't in it
 *   OUT-OF-RANGE — declared numeric, but your value is outside min/max
 *   MISSING-REQ  — a required declared param you didn't provide
 *
 * It prints a table and EXITS NON-ZERO if anything is DROPPED / invalid / missing —
 * so you fix it BEFORE the billed generation call. Paste the report; don't claim
 * "schema-aware" without it.
 *
 * No dependencies — Node 18+ built-in fetch only. Runs anywhere Node is present.
 *
 * Usage:
 *   node validate-media-params.mjs --model fal/flux-dev --params '{"prompt":"a fox","seed":7}'
 *   # offline (skip the network — pass the model's inputs directly):
 *   node validate-media-params.mjs --model x --params '{...}' --schema '{"prompt":{...},"seed":{...}}'
 *
 * Env (for the live schema fetch):
 *   SPIDERIQ_API_URL   default https://spideriq.ai
 *   SPIDERIQ_PAT       your Bearer token (client-triple or spideriq_pat_*)
 */

function parseArgs(argv) {
  const ALIAS = { m: 'model', p: 'params', s: 'schema' };
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    let key = null;
    if (a.startsWith('--')) key = a.slice(2);
    else if (a.startsWith('-') && a.length === 2) key = ALIAS[a.slice(1)] || a.slice(1);
    if (key) {
      const nxt = argv[i + 1];
      const val = nxt && !nxt.startsWith('-') ? argv[++i] : 'true';
      out[key] = val;
    }
  }
  return out;
}

function fail(msg) {
  console.error(`ERROR: ${msg}`);
  process.exit(2);
}

async function fetchInputs(model) {
  const base = (process.env.SPIDERIQ_API_URL || 'https://spideriq.ai').replace(/\/+$/, '');
  const pat = process.env.SPIDERIQ_PAT;
  if (!pat) fail('SPIDERIQ_PAT is not set (needed to fetch the model schema — or pass --schema to run offline).');
  const url = `${base}/api/gate/v1/media/models?include_inactive=true`;
  let res;
  try {
    res = await fetch(url, { headers: { Authorization: `Bearer ${pat}` } });
  } catch (e) {
    fail(`could not reach ${url}: ${e.message}`);
  }
  if (!res.ok) fail(`GET /media/models returned ${res.status} — check SPIDERIQ_PAT / SPIDERIQ_API_URL.`);
  const body = await res.json();
  const row = (body.models || []).find((m) => m.id === model);
  if (!row) {
    const ids = (body.models || []).map((m) => m.id).join(', ');
    fail(`model "${model}" not found. Available: ${ids || '(none)'}`);
  }
  return row.inputs || {};
}

function classify(params, inputs) {
  const declared = new Set(Object.keys(inputs || {}));
  const rows = [];

  // Each provided param → HONORED / DROPPED / OUT-OF-ENUM / OUT-OF-RANGE.
  for (const [k, v] of Object.entries(params)) {
    if (!declared.has(k)) {
      rows.push({ param: k, value: v, status: 'DROPPED', note: 'not declared by this model — will be discarded' });
      continue;
    }
    const spec = inputs[k] || {};
    if (Array.isArray(spec.enum) && !spec.enum.map(String).includes(String(v))) {
      rows.push({ param: k, value: v, status: 'OUT-OF-ENUM', note: `allowed: ${spec.enum.join(' | ')}` });
      continue;
    }
    const isNum = spec.type === 'int' || spec.type === 'float' || spec.type === 'number';
    if (isNum && v !== null && v !== undefined && v !== '') {
      const n = Number(v);
      if (Number.isNaN(n)) {
        rows.push({ param: k, value: v, status: 'OUT-OF-RANGE', note: 'not a number' });
        continue;
      }
      if (spec.min !== undefined && n < spec.min) {
        rows.push({ param: k, value: v, status: 'OUT-OF-RANGE', note: `min ${spec.min}` });
        continue;
      }
      if (spec.max !== undefined && n > spec.max) {
        rows.push({ param: k, value: v, status: 'OUT-OF-RANGE', note: `max ${spec.max}` });
        continue;
      }
    }
    rows.push({ param: k, value: v, status: 'HONORED', note: spec.type || '' });
  }

  // Required declared params that weren't provided.
  for (const [k, spec] of Object.entries(inputs || {})) {
    if (spec && spec.required && !(k in params)) {
      rows.push({ param: k, value: '(absent)', status: 'MISSING-REQ', note: 'required by this model' });
    }
  }
  return rows;
}

function render(model, rows) {
  const pad = (s, n) => String(s).padEnd(n);
  const w = { p: Math.max(6, ...rows.map((r) => String(r.param).length)), s: 12 };
  console.log(`\nmodel: ${model}`);
  console.log(`${pad('PARAM', w.p)}  ${pad('STATUS', w.s)}  VALUE / NOTE`);
  console.log(`${'-'.repeat(w.p)}  ${'-'.repeat(w.s)}  ${'-'.repeat(30)}`);
  for (const r of rows) {
    const detail = r.status === 'HONORED' ? `${JSON.stringify(r.value)}` : `${JSON.stringify(r.value)} — ${r.note}`;
    console.log(`${pad(r.param, w.p)}  ${pad(r.status, w.s)}  ${detail}`);
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.model) fail('--model <provider/model> is required.');
  let params;
  try {
    params = JSON.parse(args.params || '{}');
  } catch {
    fail(`--params must be valid JSON (got: ${args.params})`);
  }
  if (typeof params !== 'object' || Array.isArray(params) || params === null) {
    fail('--params must be a JSON object.');
  }

  let inputs;
  if (args.schema) {
    try {
      inputs = JSON.parse(args.schema);
    } catch {
      fail(`--schema must be valid JSON (the model's inputs object).`);
    }
  } else {
    inputs = await fetchInputs(args.model);
  }

  const rows = classify(params, inputs);
  render(args.model, rows);

  const problems = rows.filter((r) => r.status !== 'HONORED');
  const counts = problems.reduce((a, r) => ((a[r.status] = (a[r.status] || 0) + 1), a), {});
  if (problems.length) {
    const summary = Object.entries(counts).map(([k, n]) => `${n} ${k}`).join(', ');
    console.error(`\nNOT SCHEMA-CLEAN: ${summary}. Fix these before calling gate_media_generate ` +
      `(or note them in your summary's "params the model ignored" line). See the model's \`inputs\` via gate_media_models.`);
    process.exit(1);
  }
  console.log(`\nOK — all ${rows.length} param(s) are declared and in range. Safe to generate.`);
}

main().catch((e) => fail(e && e.message ? e.message : String(e)));
