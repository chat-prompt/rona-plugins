#!/usr/bin/env node
import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';

const pluginUrl = new URL('../plugins/rona-coach/skills/rona-coach/SKILL.md', import.meta.url);
const supportTarget = process.env.RONA_SUPPORT_SKILL
  || new URL('../../rona-support/assets/rona-coach/SKILL.md', import.meta.url);
const pluginSyncUrl = new URL('../plugins/rona-coach/skills/rona-coach/scripts/sync.mjs', import.meta.url);
const supportSyncTarget = process.env.RONA_SUPPORT_SKILL
  ? resolve(dirname(process.env.RONA_SUPPORT_SKILL), 'scripts', 'sync.mjs')
  : new URL('../../rona-support/assets/rona-coach/scripts/sync.mjs', import.meta.url);
const [plugin, support, pluginSync, supportSync] = await Promise.all([
  readFile(pluginUrl, 'utf8'),
  readFile(supportTarget, 'utf8'),
  readFile(pluginSyncUrl, 'utf8'),
  readFile(supportSyncTarget, 'utf8'),
]);

const clauses = [
  '실제 자료', '명시적으로 동의', 'start_coaching', 'get_coaching_state',
  'update_coaching_state', 'submit_coaching_artifact', 'submit_coaching_evidence',
  'userReviewed', 'complete_coaching', 'revision_conflict', 'partial', 'blocked', 'Stop',
];
const missing = clauses.flatMap((clause) => [
  ...(plugin.includes(clause) ? [] : [`plugin:${clause}`]),
  ...(support.includes(clause) ? [] : [`support:${clause}`]),
]);
if (missing.length) {
  console.error(`로나 코칭 계약 불일치: ${missing.join(', ')}`);
  process.exitCode = 1;
} else if (plugin !== support || pluginSync !== supportSync) {
  console.error('로나 코칭 배포본이 Support 정본과 바이트 단위로 다릅니다.');
  process.exitCode = 1;
} else {
  console.log('로나 코칭 Skill과 동기화 helper가 plugin과 Support에서 완전히 같습니다.');
}
