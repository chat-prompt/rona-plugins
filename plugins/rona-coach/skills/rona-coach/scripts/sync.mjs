#!/usr/bin/env node
import { createHash } from 'node:crypto';
import { appendFileSync, chmodSync, mkdirSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join, posix, win32 } from 'node:path';
import { fileURLToPath } from 'node:url';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const CHECKPOINT_ID = /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/;
const STATES = new Set(['active', 'paused', 'completed']);
const STEP_STATES = new Set(['pending', 'active', 'done']);
const COACHING_PHASES = new Set(['onboarding', 'checkpoint', 'review', 'completed']);
const ACKNOWLEDGED = new Set(['created', 'updated', 'duplicate', 'unchanged', 'stale']);
const REJECTED = new Set([
  'checkpoint-approval-required', 'checkpoint-transition-invalid',
  'coaching-phase-required', 'coaching-status-phase-mismatch',
  'plan-session-untrusted', 'plan-identity-mismatch', 'invalid-initial-plan',
]);

function invalid() { throw new Error('invalid plan snapshot'); }
function text(value, max) {
  if (typeof value !== 'string' || value.length === 0 || value.length > max) invalid();
}

function validatePlan(value) {
  if (!value || value.schemaVersion !== 1 || !UUID.test(value.planId || '')
    || (value.challengeId !== null && !UUID.test(value.challengeId || ''))
    || !STATES.has(value.status)
    || (value.engine !== null && !['claude', 'codex'].includes(value.engine))
    || (value.sessionRef !== null && !/^[A-Za-z0-9._~-]{16,128}$/.test(value.sessionRef || ''))
    || (value.coachingPhase !== undefined && !COACHING_PHASES.has(value.coachingPhase))
    || !Number.isInteger(value.revision) || value.revision < 0
    || !Array.isArray(value.checkpoints) || value.checkpoints.length > 100
    || !Number.isFinite(Date.parse(value.createdAt)) || !Number.isFinite(Date.parse(value.updatedAt))) invalid();
  text(value.title, 200); text(value.outcome, 2_000); text(value.completionCriteria, 2_000); text(value.workspace, 2_000);
  if (!(posix.isAbsolute(value.workspace) || win32.isAbsolute(value.workspace))) invalid();
  const checkpointIds = new Set();
  let activeCheckpoints = 0;
  for (const step of value.checkpoints) {
    if (!step || !CHECKPOINT_ID.test(step.id || '') || !STEP_STATES.has(step.state)) invalid();
    if (checkpointIds.has(step.id)) invalid();
    checkpointIds.add(step.id);
    if (step.state === 'active' && ++activeCheckpoints > 1) invalid();
    text(step.title, 200);
    if (step.description !== undefined) text(step.description, 500);
  }
  if (value.glossary !== undefined) {
    if (!Array.isArray(value.glossary) || value.glossary.length > 20) invalid();
    const terms = new Set();
    for (const entry of value.glossary) {
      if (!entry) invalid();
      text(entry.term, 100); text(entry.definition, 500); text(entry.analogy, 300); text(entry.introducedAt, 64);
      if (terms.has(entry.term)) invalid();
      terms.add(entry.term);
      if (entry.introducedAt !== 'onboarding' && !checkpointIds.has(entry.introducedAt)) invalid();
    }
  }
  return value;
}

export function stableEventId(planId, revision) {
  const bytes = createHash('sha256').update(`${planId}:${revision}`).digest().subarray(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString('hex');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

export function supportDataDirectory({ platform = process.platform, env = process.env, home = homedir() } = {}) {
  if (env.RONA_SUPPORT_DATA_DIR) return env.RONA_SUPPORT_DATA_DIR;
  if (platform === 'darwin') return join(home, 'Library', 'Application Support', 'rona-support');
  if (platform === 'win32' && env.APPDATA) return `${env.APPDATA}/rona-support`;
  return join(env.XDG_CONFIG_HOME || join(home, '.config'), 'rona-support');
}

function readDiscovery(dataDir) {
  try {
    const value = JSON.parse(readFileSync(join(dataDir, 'plan-bridge.json'), 'utf8'));
    const url = new URL(value.url);
    if (value.schemaVersion !== 1 || url.protocol !== 'http:'
      || !['127.0.0.1', 'localhost'].includes(url.hostname)
      || typeof value.token !== 'string' || value.token.length < 32 || value.token.length > 256) return null;
    return value;
  } catch { return null; }
}

function appendOffline(dataDir, envelope) {
  mkdirSync(dataDir, { recursive: true, mode: 0o700 });
  const queuePath = join(dataDir, 'plan-events.jsonl');
  appendFileSync(queuePath, `${JSON.stringify(envelope)}\n`, { encoding: 'utf8', mode: 0o600 });
  try { chmodSync(queuePath, 0o600); } catch {}
}

export async function syncPlanFile(planPath, options = {}) {
  const plan = validatePlan(JSON.parse(readFileSync(planPath, 'utf8')));
  const approvedCheckpointId = options.approvedCheckpointId;
  if (approvedCheckpointId !== undefined && !CHECKPOINT_ID.test(approvedCheckpointId || '')) invalid();
  const envelope = { eventId: stableEventId(plan.planId, plan.revision), plan };
  const dataDir = options.dataDir || supportDataDirectory(options);
  const discovery = readDiscovery(dataDir);
  if (discovery) {
    try {
      const response = await (options.fetch || fetch)(discovery.url, {
        method: 'POST',
        headers: {
          'content-type': 'application/json', authorization: `Bearer ${discovery.token}`,
          ...(approvedCheckpointId === undefined ? {} : { 'x-rona-approved-checkpoint': approvedCheckpointId }),
        },
        body: JSON.stringify(envelope),
        signal: AbortSignal.timeout(2_000),
      });
      if (response.ok) {
        const result = await response.json();
        if (result?.ok === true && ACKNOWLEDGED.has(result.reason)) return { synced: true, queued: false };
        if (result?.ok === true && REJECTED.has(result.reason)) {
          return { synced: false, queued: false, rejected: true, reason: result.reason };
        }
      }
    } catch {}
  }
  if (approvedCheckpointId !== undefined) {
    return { synced: false, queued: false, rejected: true, reason: 'checkpoint-approval-support-required' };
  }
  appendOffline(dataDir, envelope);
  return { synced: false, queued: true };
}

function arg(name) {
  const index = process.argv.indexOf(name);
  if (index < 0) return { present: false, value: undefined };
  const value = process.argv[index + 1];
  return { present: true, value: value && !value.startsWith('--') ? value : undefined };
}

const isMain = process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1];
if (isMain) {
  const planArg = arg('--file');
  const approvalArg = arg('--approve-checkpoint');
  const planPath = planArg.value;
  const approvedCheckpointId = approvalArg.value;
  if (!planPath || (approvalArg.present && !approvedCheckpointId)) {
    console.error('usage: sync.mjs --file <.rona/plan.json> [--approve-checkpoint <id>]');
    process.exitCode = 2;
  } else {
    syncPlanFile(planPath, { approvedCheckpointId })
      .then((result) => {
        if (result.rejected) {
          console.error(result.reason === 'checkpoint-approval-support-required'
            ? 'Rona Support를 연 뒤 다시 동기화해 주세요.'
            : `진행표 동기화가 거부됐어요: ${result.reason}`);
          process.exitCode = 1;
        } else console.log(result.synced ? 'Support와 동기화했어요.' : '로컬에 안전하게 보관했어요.');
      })
      .catch(() => { console.error('실행 계획 파일을 확인하지 못했어요.'); process.exitCode = 1; });
  }
}
