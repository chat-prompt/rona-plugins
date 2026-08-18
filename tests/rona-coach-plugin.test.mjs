import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { join } from 'node:path';
import test from 'node:test';

const root = new URL('..', import.meta.url).pathname;
const plugin = join(root, 'plugins', 'rona-coach');

async function text(path) { return readFile(path, 'utf8'); }
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
  for (const name of ['start_coaching', 'get_coaching_state', 'update_coaching_state', 'submit_coaching_artifact', 'submit_coaching_evidence', 'complete_coaching']) {
    assert.ok(skill.includes(name), `missing ${name}`);
  }
  for (const forbidden of ['request_skill', 'check_skill_status', 'get_practice', 'claim_topic']) assert.equal(skill.includes(forbidden), false);
  for (const anchor of [
    '실제 자료', '명시적으로 동의', 'userReviewed', 'revision_conflict',
    'partial', 'blocked', 'Stop', '맥락 대비', '개념과 이유 설명',
    '공동 실행', '결과 검증', '이해와 방향 확인', '다음 행동 연결',
    '더 설명해줘', '바로 실행해줘', '다음에 다시 할 때',
    '서로 다른 체크포인트는 한 응답에 묶지', 'description',
    '체크포인트 설명 계약', '세션 용어 기준표', '말투와 문장 예시',
    '이번 체크포인트가 바꾸는 결과물 상태', 'AI 활용법은 다음 중 하나일 때', '보충 설명',
    'glossary', 'definition', 'analogy', 'introducedAt',
  ]) assert.ok(skill.includes(anchor), `missing coaching contract: ${anchor}`);
  assert.match(skill, /`네`[^\n]*`계속`[^\n]*(이해|만족)[^\n]*(추정하지|간주하지)/);
  assert.match(skill, /고정[^\n]*(주제|교안)[^\n]*(사용하지|재생하지|중심으로 두지)/);
  assert.match(skill, /\.rona\/coach-outbox\.json/);
  assert.match(sync, /syncPlanFile/);
});

test('published coaching starts with purpose and does not interview for available time', async () => {
  const skill = await text(join(plugin, 'skills', 'rona-coach', 'SKILL.md'));
  const start = skill.split('## 시작과 재개')[1]?.split('## 맥락 인터뷰')[0] || '';
  const interview = skill.split('## 맥락 인터뷰')[1]?.split('## 방향과 실행 계획 합의')[0] || '';
  const questions = interview.split('정보가 부족하면')[0] || '';
  assert.match(start, /로나 코칭[\s\S]*실제 업무[\s\S]*결과물/);
  assert.match(start, /혼자 다시 할 수 있는 방법/);
  assert.match(start, /재개[\s\S]*소개[\s\S]*반복하지 않는다/);
  assert.match(questions, /지금 가진 실제 자료/);
  assert.doesNotMatch(questions, /사용할 수 있는 시간|가용\s*시간|몇\s*시간/);
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
  const mcp = JSON.parse(await text(join(plugin, '.mcp.json')));
  const skill = await text(join(plugin, 'skills', 'rona-coach', 'SKILL.md'));

  assert.equal(listing.description, description);
  assert.equal(manifest.description, description);
  assert.match(skill, new RegExp(`^description: ${description}$`, 'm'));
  assert.equal(listing.version, manifest.version);
  assert.equal(mcp.mcpServers['rona-coach'].headers['X-Rona-Launcher-Version'], `coach-${manifest.version}`);
  assert.equal(manifest.version, '0.1.4');
  assert.equal(marketplace.metadata.version, '0.3.28');
});
