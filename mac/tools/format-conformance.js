#!/usr/bin/env node
/**
 * The entry format, checked against the shared fixtures.
 *
 * `spec/fixtures/` holds one Markdown file per awkward case and the parse each
 * one must produce. The Swift side reads exactly the same files in
 * `ios/Tests/VerifyFormat.swift`. Two implementations of one on-disk format
 * will drift unless something makes them answer the same questions, and every
 * cross-device bug this app has had came from that drift.
 *
 * Every fixture is parsed with a fallback id of 2026-09-08-143000, so a file
 * without an `id:` line reports the id its filename would have given it.
 *
 *   node tools/format-conformance.js
 */

'use strict';

const fs = require('fs');
const path = require('path');

const { _internals } = require('../src/journal');
const { parse, serialize } = _internals;

const FIXTURES = path.join(__dirname, '..', '..', 'spec', 'fixtures');
const FALLBACK_ID = '2026-09-08-143000';

const pass = [];
const fail = [];

function check(name, ok, detail) {
  (ok ? pass : fail).push(name);
  console.log(`${ok ? '  ok  ' : ' FAIL '} ${name}${detail ? '  — ' + detail : ''}`);
}

function compare(name, expected, actual) {
  for (const key of ['id', 'date', 'title', 'body']) {
    if (expected[key] !== actual[key]) {
      return check(`${name}: ${key}`, false,
        `expected ${JSON.stringify(expected[key])}, got ${JSON.stringify(actual[key])}`);
    }
  }
  for (const key of ['tags', 'photos']) {
    if (JSON.stringify(expected[key]) !== JSON.stringify(actual[key])) {
      return check(`${name}: ${key}`, false,
        `expected ${JSON.stringify(expected[key])}, got ${JSON.stringify(actual[key])}`);
    }
  }
  check(name, true);
}

if (!fs.existsSync(FIXTURES)) {
  console.error('No fixtures at ' + FIXTURES);
  process.exit(1);
}

const cases = fs.readdirSync(FIXTURES).filter((f) => f.endsWith('.md')).sort();
console.log(`Entry format conformance — ${cases.length} fixtures\n`);

for (const file of cases) {
  const name = path.basename(file, '.md');
  const raw = fs.readFileSync(path.join(FIXTURES, file), 'utf8');
  const expected = JSON.parse(fs.readFileSync(path.join(FIXTURES, name + '.json'), 'utf8'));
  compare(name, expected, parse(raw, FALLBACK_ID));
}

// Serialising a parsed entry and parsing it again must not change anything.
// This is what keeps an entry safe to open and re-save on either device.
console.log('');
for (const file of cases) {
  const name = path.basename(file, '.md');
  const raw = fs.readFileSync(path.join(FIXTURES, file), 'utf8');
  const once = parse(raw, FALLBACK_ID);
  const twice = parse(serialize(once), FALLBACK_ID);
  compare(`${name} (round trip)`, once, twice);
}

console.log(`\n${pass.length} passed, ${fail.length} failed`);
if (fail.length) { console.log('failed: ' + fail.join(', ')); process.exit(1); }
