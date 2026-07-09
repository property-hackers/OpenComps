// Unit tests for the CSV -> INSERT generator. Run with: node --test scripts/lib/
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { parseCsv, quote, buildInserts } from './csv_to_inserts.mjs'

test('parseCsv: plain rows', () => {
  assert.deepEqual(parseCsv('a,b\n1,2\n3,4\n'), [['a', 'b'], ['1', '2'], ['3', '4']])
})

test('parseCsv: quoted field with embedded comma', () => {
  assert.deepEqual(parseCsv('city,state\n"Atlanta, GA",GA\n'), [['city', 'state'], ['Atlanta, GA', 'GA']])
})

test('parseCsv: doubled quotes unescape (JSON payload like county_weights)', () => {
  assert.deepEqual(parseCsv('w\n"{""13121"": 98.6}"\n'), [['w'], ['{"13121": 98.6}']])
})

test('parseCsv: embedded newline inside quoted field', () => {
  assert.deepEqual(parseCsv('note\n"line1\nline2"\n'), [['note'], ['line1\nline2']])
})

test('parseCsv: CRLF line endings', () => {
  assert.deepEqual(parseCsv('a,b\r\n1,2\r\n'), [['a', 'b'], ['1', '2']])
})

test('parseCsv: blank lines and trailing blank lines are skipped', () => {
  assert.deepEqual(parseCsv('a,b\n1,2\n\n'), [['a', 'b'], ['1', '2']])
  assert.deepEqual(parseCsv('a,b\n\n1,2\n\n\n'), [['a', 'b'], ['1', '2']])
})

test('parseCsv: no trailing newline still emits the last row', () => {
  assert.deepEqual(parseCsv('a,b\n1,2'), [['a', 'b'], ['1', '2']])
})

test('parseCsv: empty fields survive as empty strings', () => {
  assert.deepEqual(parseCsv('a,b,c\n1,,3\n'), [['a', 'b', 'c'], ['1', '', '3']])
})

test('quote: doubles single quotes', () => {
  assert.equal(quote("O'Fallon"), "'O''Fallon'")
  assert.equal(quote(''), "''")
})

test('buildInserts: single batch output shape', () => {
  const sql = buildInserts('t', [['a', 'b'], ['1', "O'x"]])
  assert.equal(sql, "INSERT INTO t VALUES\n('1','O''x');\n")
})

test('buildInserts: batching splits on exact boundary and remainder', () => {
  const rows = [['h'], ['1'], ['2'], ['3'], ['4']]
  assert.equal((buildInserts('t', rows, 2).match(/INSERT INTO/g) || []).length, 2)
  assert.equal((buildInserts('t', rows, 4).match(/INSERT INTO/g) || []).length, 1)
  assert.equal((buildInserts('t', rows, 3).match(/INSERT INTO/g) || []).length, 2)
})

test('buildInserts: header-only or empty input emits nothing', () => {
  assert.equal(buildInserts('t', [['a', 'b']]), '')
  assert.equal(buildInserts('t', []), '')
})

test('buildInserts: ragged row reports the real file line number', () => {
  const rows = parseCsv('a,b\n1,2\n1,2,3\n')
  assert.throws(() => buildInserts('t', rows), /row 3 has 3 fields, expected 2/)
})

test('buildInserts: ragged row deep in a later batch still numbered correctly', () => {
  const rows = [['h', 'h2'], ...Array.from({ length: 1500 }, () => ['x', 'y'])]
  rows[1200] = ['only-one']
  assert.throws(() => buildInserts('t', rows), /row 1201 has 1 fields, expected 2/)
})

test('buildInserts: rejects unsafe table names', () => {
  assert.throws(() => buildInserts('t; DROP TABLE users; --', [['a'], ['1']]), /unsafe table name/)
})

test('buildInserts: rejects invalid batch sizes', () => {
  assert.throws(() => buildInserts('t', [['a'], ['1']], 0), /invalid batch size/)
  assert.throws(() => buildInserts('t', [['a'], ['1']], NaN), /invalid batch size/)
})
