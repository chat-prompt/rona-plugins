import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { lstat, readFile, readdir } from 'node:fs/promises';
import { isAbsolute, join, resolve } from 'node:path';
import test from 'node:test';

const root = resolve(new URL('..', import.meta.url).pathname);
const plugin = join(root, 'plugins', 'rona-coach');
const supportSources = [
  ['skills/rona-coach/SKILL.md', 'assets/rona-coach/SKILL.md', '270ee0dec4bca7c49f1094b6dfac378aac07f033ff305fb766ce2b20cff56891'],
  ['skills/rona-coach/references/review.md', 'assets/rona-coach/references/review.md', '925c2c59143a4cd9bf22764d64bcc6a4f8ab1d096077653349e6491c3ccee2f6'],
  ['skills/rona-review/SKILL.md', 'assets/rona-review/SKILL.md', '69eb39f129a4677abdaad375d5225292695bc77b6e2b9b4e9488ac9809c5980d'],
  ['skills/rona-coach/scripts/sync.mjs', 'assets/rona-coach/scripts/sync.mjs', 'b96f34e88f210084d9e3f2c0478b122f88df8301852c8cf808bffbb3d93f7e82'],
  ['skills/rona-coach/manifest.json', 'assets/rona-coach/manifest.json', '2d7dc02f4526511586f9c8f014c82ffc3ca1ec74f9d0dc20a0087889f8f9c97e'],
];

async function text(path) { return readFile(path, 'utf8'); }
async function hasSupportSources(candidate) {
  const checks = await Promise.all(supportSources.map(async ([, relative]) => {
    try {
      return (await lstat(join(candidate, relative))).isFile();
    } catch {
      return false;
    }
  }));
  return checks.every(Boolean);
}
async function resolveSupportRoot() {
  const explicit = process.env.RONA_SUPPORT_ROOT?.trim();
  if (explicit && !isAbsolute(explicit)) {
    throw new Error('RONA_SUPPORT_ROOT must be an absolute path');
  }
  const candidates = [
    ...(explicit ? [resolve(explicit)] : []),
    resolve(root, '..', 'rona-support'),
    resolve(root, '..', 'rona-support-coaching-fixes'),
  ];
  for (const candidate of candidates) {
    if (await hasSupportSources(candidate)) return candidate;
    if (explicit && candidate === resolve(explicit)) {
      throw new Error(`RONA_SUPPORT_ROOT does not contain the expected Support sources: ${candidate}`);
    }
  }
  throw new Error('Support sources not found; set RONA_SUPPORT_ROOT to an absolute Support repository path');
}
async function treeHash(directory) {
  const files = [];
  async function walk(path, relative = '') {
    for (const entry of (await readdir(path, { withFileTypes: true })).sort((a, b) => a.name.localeCompare(b.name))) {
      const child = join(path, entry.name), rel = join(relative, entry.name);
      if (entry.isDirectory()) await walk(child, rel); else files.push([rel, await readFile(child)]);
    }
  }
  await walk(directory);
  const hash = createHash('sha256');
  for (const [path, body] of files) hash.update(path).update('\0').update(body).update('\0');
  return hash.digest('hex');
}

test('legacy rona plugins remain byte-for-byte unchanged', async () => {
  assert.equal(await treeHash(join(root, 'plugins', 'rona')), '3b80cc9ea14d3760f3e4374b39b656717cdcbe8a0d9465c8172bf83b1d5307fa');
  assert.equal(await treeHash(join(root, 'plugins', 'rona-alpha')), '6959ca904a9393f5f44cdd7eca629d1f993b351ff4079721347d54f12c13984c');
});

test('standalone plugin has a distinct manifest and OAuth remote MCP', async () => {
  const manifest = JSON.parse(await text(join(plugin, '.claude-plugin', 'plugin.json')));
  const mcp = JSON.parse(await text(join(plugin, '.mcp.json')));
  assert.equal(manifest.name, 'rona-coach');
  assert.equal(mcp.mcpServers['rona-coach'].type, 'http');
  assert.match(mcp.mcpServers['rona-coach'].url, /^https:\/\/rona\.so\/api\/mcp\?launcher=coach/);
  assert.equal(JSON.stringify(mcp).includes('Authorization'), false);
});

test('skill implements native execution and excludes legacy generation tools', async () => {
  const skill = await text(join(plugin, 'skills', 'rona-coach', 'SKILL.md'));
  const sync = await text(join(plugin, 'skills', 'rona-coach', 'scripts', 'sync.mjs'));
  for (const name of ['sync_coaching_plan', 'start_coaching', 'update_coaching_state', 'submit_coaching_artifact', 'submit_coaching_evidence', 'complete_coaching']) {
    assert.ok(skill.includes(name), `missing ${name}`);
  }
  for (const forbidden of ['request_skill', 'check_skill_status', 'get_practice', 'claim_topic']) assert.equal(skill.includes(forbidden), false);
  for (const anchor of [
    '실제 자료', '명시적으로 동의', 'userReviewed', 'revision_conflict',
    'Stop', '맥락 대비', '개념과 이유 설명', '공동 실행', '결과 검증',
    '이해와 방향 확인', '다음 행동 연결', '더 설명해줘', '바로 실행해줘',
    '서로 다른 체크포인트를 한 응답에 묶지', 'description', '보충 설명',
    '가벼운 탐색', '업무 이해 1/4', '재료와 환경 2/4',
    '결과물과 사용 장면 3/4', '완료와 설명 수준 4/4',
    '승인 뒤 작업 온보딩', '이번에 만들 것', '행동 → 이유 → 실제 자료 → 통과 조건',
    '최종 결과물 전체 검증', '작업 과정 요약', 'AI 활용과 재사용 요약',
    'coaching_id', 'invalid-initial-plan',
    '업무 역할', '업무의 숙련도', 'AI 활용 경험', '사용자가 판단할 것과 확인 방법',
  ]) assert.ok(skill.includes(anchor), `missing coaching contract: ${anchor}`);
  assert.match(skill, /특정 승인 문구를 그대로 입력하거나 복창하게 하지 않는다/);
  assert.match(skill, /직전 질문이 다음 단계 진행 여부 하나였다면 `네`, `계속`, `좋아요`, `넘어가자`/);
  assert.match(sync, /syncPlanFile/);
});

test('standalone review skill is bundled beside coaching and reuses its review contract', async () => {
  const review = await text(join(plugin, 'skills', 'rona-review', 'SKILL.md'));
  assert.match(review, /^name: rona-review$/m);
  assert.match(review, /status: completed/);
  assert.match(review, /\.\.\/rona-coach\/references\/review\.md/);
  assert.match(review, /결과물을 수정하지 않는다/);
});

test('published coaching starts with purpose and does not interview for available time', async () => {
  const skill = await text(join(plugin, 'skills', 'rona-coach', 'SKILL.md'));
  const start = skill.split('## 시작과 재개')[1]?.split('## 맥락 인터뷰')[0] || '';
  const interview = skill.split('## 맥락 인터뷰')[1]?.split('## 방향과 실행 계획 합의')[0] || '';
  const questions = interview.split('정보가 부족하면')[0] || '';
  assert.match(start, /로나 코칭[\s\S]*실제 업무[\s\S]*결과물/);
  assert.match(start, /다음 업무에 다시 써요/);
  assert.match(start, /재개[\s\S]*소개[\s\S]*반복하지 않는다/);
  assert.match(questions, /사용할 실제 문서·파일·데이터/);
  assert.match(questions, /가용 시간은 기본 질문으로 묻지 않는다/);
});

test('hooks only restore context and persist pending local state, never author completion', async () => {
  const hooks = await text(join(plugin, 'hooks', 'hooks.json'));
  const link = await text(join(plugin, 'hooks', 'session-link.sh'));
  const flush = await text(join(plugin, 'hooks', 'flush-outbox.sh'));
  assert.match(hooks, /SessionStart/);
  assert.match(hooks, /Stop/);
  assert.doesNotMatch(link + flush, /complete_coaching|status["'= :]+completed|\/complete/);
  assert.match(link, /hookSpecificOutput/);
});

test('marketplace publishes rona-coach alongside existing entries', async () => {
  const marketplace = JSON.parse(await text(join(root, '.claude-plugin', 'marketplace.json')));
  assert.deepEqual(marketplace.plugins.map((item) => item.name), ['rona', 'rona-alpha', 'rona-coach']);
});

test('published descriptions and versions stay aligned', async () => {
  const description = '실제 업무 결과물을 만들고 검증하는 Rona 맞춤 코칭';
  const marketplace = JSON.parse(await text(join(root, '.claude-plugin', 'marketplace.json')));
  const listing = marketplace.plugins.find((item) => item.name === 'rona-coach');
  const manifest = JSON.parse(await text(join(plugin, '.claude-plugin', 'plugin.json')));
  const bundleManifest = JSON.parse(await text(join(plugin, 'skills', 'rona-coach', 'manifest.json')));
  const mcp = JSON.parse(await text(join(plugin, '.mcp.json')));
  const skill = await text(join(plugin, 'skills', 'rona-coach', 'SKILL.md'));

  assert.equal(listing.description, description);
  assert.equal(manifest.description, description);
  assert.match(skill, new RegExp(`^description: ${description}$`, 'm'));
  assert.equal(listing.version, manifest.version);
  assert.equal(bundleManifest.name, 'rona-coach');
  assert.equal(bundleManifest.version, manifest.version);
  assert.equal(mcp.mcpServers['rona-coach'].headers['X-Rona-Launcher-Version'], `coach-${manifest.version}`);
  assert.equal(manifest.version, '0.1.17');
  assert.equal(marketplace.metadata.version, '0.3.41');
});

test('published coaching sources stay byte-identical to the Support source', async () => {
  const supportRoot = await resolveSupportRoot();

  for (const [pluginRelative, supportRelative, expectedSha] of supportSources) {
    const [published, support] = await Promise.all([
      readFile(join(plugin, pluginRelative)),
      readFile(join(supportRoot, supportRelative)),
    ]);
    assert.deepEqual(published, support, `${pluginRelative} differs from Support`);
    assert.equal(createHash('sha256').update(published).digest('hex'), expectedSha);
  }
});
