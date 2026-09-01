#!/usr/bin/env node
import { readFileSync } from 'node:fs';

const MAX_REVIEW_CHARS = 200_000;
const MASK_CHUNK_CHARS = 4_000;
const patterns = [
  [/-----BEGIN [A-Z0-9 ]+-----[\s\S]*?-----END [A-Z0-9 ]+-----/g, '███'],
  [/[A-Za-z0-9._%+-]+\s*[@＠]\s*[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g, '███'],
  [/[A-Za-z0-9._%+-]+\s*(?:\(at\)|\[at\]|\sat\s)\s*[A-Za-z0-9.-]+\.[A-Za-z]{2,}/gi, '███'],
  [/(sk-|ghp_|gho_|ghs_|xoxb-|xoxp-|xapp-|AIza|glpat-|AKIA)[A-Za-z0-9_-]{20,}/g, '███'],
  [/eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/g, '███'],
  [/(?<![\d+])\+82[-.\s]?1[0-9][-.\s]?[0-9]{3,4}[-.\s]?[0-9]{4}(?!\d)/g, '███'],
  [/(?<![\d+])01[0-9][-.\s]?[0-9]{3,4}[-.\s]?[0-9]{4}(?!\d)/g, '███'],
  [/(?<!\d)[0-9]{1,3}(?:\.[0-9]{1,3}){3}(?!\d)/g, '███'],
  [/(?<!\d)[0-9]{6}-[1-4][0-9]{6}(?!\d)/g, '███'],
  [/(?<![A-Za-z0-9])[A-Z][0-9]{8}(?!\d)/g, '███'],
  [/(?<![A-Za-z0-9_])\/(?:Users|home|private|tmp|var\/folders)\/[^\s<>"']+/g, '███'],
  [/(?<![A-Za-z0-9_])[A-Za-z]:\\(?:[^\s<>"']+\\)*[^\s<>"']+/g, '███'],
];

const input = readFileSync(0, 'utf8');
if (input.length > MAX_REVIEW_CHARS) {
  console.error('review exceeds 200000 characters');
  process.exit(1);
}

const chunks = input
  .split(/(\n{2,})/)
  .flatMap((block) => block.length <= MASK_CHUNK_CHARS
    ? [block]
    : block.match(new RegExp(`[\\s\\S]{1,${MASK_CHUNK_CHARS}}`, 'g')) ?? []);
let maskedCount = 0;
const masked = chunks.map((chunk) => {
  for (const [pattern, replacement] of patterns) {
    chunk = chunk.replace(pattern, () => {
      maskedCount += 1;
      return replacement;
    });
  }
  return chunk;
}).join('');

process.stdout.write(masked);
process.stderr.write(`MASKED_COUNT=${maskedCount}\n`);
