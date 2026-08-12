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
  for (const name of ['start_coaching', 'get_coaching_state', 'update_coaching_state', 'submit_coaching_artifact', 'submit_coaching_evidence', 'complete_coaching']) {
    assert.ok(skill.includes(name), `missing ${name}`);
  }
  for (const forbidden of ['request_skill', 'check_skill_status', 'get_practice', 'claim_topic']) assert.equal(skill.includes(forbidden), false);
  for (const anchor of ['실제 자료', '명시적으로 동의', 'userReviewed', 'revision_conflict', 'partial', 'blocked', 'Stop']) assert.ok(skill.includes(anchor));
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
