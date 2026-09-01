#!/usr/bin/env node
import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';

const pluginUrl = new URL('../plugins/rona-coach/skills/rona-coach/SKILL.md', import.meta.url);
const supportTarget = process.env.RONA_SUPPORT_SKILL
  || new URL('../../rona-support/assets/rona-coach/SKILL.md', import.meta.url);
const pluginSyncUrl = new URL('../plugins/rona-coach/skills/rona-coach/scripts/sync.mjs', import.meta.url);
const pluginManifestUrl = new URL('../plugins/rona-coach/skills/rona-coach/manifest.json', import.meta.url);
const pluginReviewUrl = new URL('../plugins/rona-coach/skills/rona-coach/references/review.md', import.meta.url);
const pluginReviewSkillUrl = new URL('../plugins/rona-coach/skills/rona-review/SKILL.md', import.meta.url);
const supportSyncTarget = process.env.RONA_SUPPORT_SKILL
  ? resolve(dirname(process.env.RONA_SUPPORT_SKILL), 'scripts', 'sync.mjs')
  : new URL('../../rona-support/assets/rona-coach/scripts/sync.mjs', import.meta.url);
const supportManifestTarget = process.env.RONA_SUPPORT_SKILL
  ? resolve(dirname(process.env.RONA_SUPPORT_SKILL), 'manifest.json')
  : new URL('../../rona-support/assets/rona-coach/manifest.json', import.meta.url);
const supportReviewTarget = process.env.RONA_SUPPORT_SKILL
  ? resolve(dirname(process.env.RONA_SUPPORT_SKILL), 'references', 'review.md')
  : new URL('../../rona-support/assets/rona-coach/references/review.md', import.meta.url);
const supportReviewSkillTarget = process.env.RONA_SUPPORT_SKILL
  ? resolve(dirname(process.env.RONA_SUPPORT_SKILL), '..', 'rona-review', 'SKILL.md')
  : new URL('../../rona-support/assets/rona-review/SKILL.md', import.meta.url);
const [plugin, support, pluginSync, supportSync, pluginManifest, supportManifest, pluginReview, supportReview, pluginReviewSkill, supportReviewSkill] = await Promise.all([
  readFile(pluginUrl, 'utf8'),
  readFile(supportTarget, 'utf8'),
  readFile(pluginSyncUrl, 'utf8'),
  readFile(supportSyncTarget, 'utf8'),
  readFile(pluginManifestUrl, 'utf8'),
  readFile(supportManifestTarget, 'utf8'),
  readFile(pluginReviewUrl, 'utf8'),
  readFile(supportReviewTarget, 'utf8'),
  readFile(pluginReviewSkillUrl, 'utf8'),
  readFile(supportReviewSkillTarget, 'utf8'),
]);

const clauses = [
  '실제 자료', '명시적으로 동의', 'start_coaching',
  'update_coaching_state', 'submit_coaching_artifact', 'submit_coaching_evidence',
  'userReviewed', 'complete_coaching', 'revision_conflict', 'Stop',
];
const missing = clauses.flatMap((clause) => [
  ...(plugin.includes(clause) ? [] : [`plugin:${clause}`]),
  ...(support.includes(clause) ? [] : [`support:${clause}`]),
]);
if (missing.length) {
  console.error(`로나 코칭 계약 불일치: ${missing.join(', ')}`);
  process.exitCode = 1;
} else if (plugin !== support || pluginSync !== supportSync || pluginManifest !== supportManifest || pluginReview !== supportReview || pluginReviewSkill !== supportReviewSkill) {
  console.error('로나 코칭 배포본이 Support 정본과 바이트 단위로 다릅니다.');
  process.exitCode = 1;
} else {
  console.log('로나 코칭 Skill, 후기 절차, 버전 manifest와 동기화 helper가 plugin과 Support에서 완전히 같습니다.');
}
