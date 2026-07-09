#!/usr/bin/env node
// Emit a CSV file as multi-row INSERT statements on stdout:
//   node csv_to_inserts.mjs <table> <file.csv> [--batch <n>]
//
// Replaces psql's \copy for bulk loads: COPY FROM STDIN desynchronizes the
// pglite-socket protocol, while plain INSERTs work over any connection
// (Docker TCP, pglite-socket, unix socket). The header row is skipped; every
// value is emitted as a quoted text literal (CSV NULL-ness is not
// distinguishable from empty string, so staging tables should be all-TEXT and
// the downstream SQL transform should NULLIF/cast). RFC 4180: quoted fields
// may contain commas, doubled quotes, and newlines (county_weights is JSON).
// Assumes quotes only open at the start of a field (strict RFC 4180); a stray
// quote mid-field flips into quoted mode rather than being rejected.
import { readFileSync } from 'node:fs'

/** Parse CSV text into rows of string fields. Blank lines are skipped. */
export function parseCsv(text) {
  const rows = []
  let row = []
  let field = ''
  let inQuotes = false
  const endRow = () => {
    // a lone newline (nothing accumulated) is a blank line, not a 1-field row
    if (row.length > 0 || field !== '') {
      row.push(field)
      rows.push(row)
    }
    field = ''
    row = []
  }
  for (let i = 0; i < text.length; i++) {
    const c = text[i]
    if (inQuotes) {
      if (c === '"') {
        if (text[i + 1] === '"') {
          field += '"'
          i++
        } else {
          inQuotes = false
        }
      } else {
        field += c
      }
    } else if (c === '"') {
      inQuotes = true
    } else if (c === ',') {
      row.push(field)
      field = ''
    } else if (c === '\n' || c === '\r') {
      if (c === '\r' && text[i + 1] === '\n') i++
      endRow()
    } else {
      field += c
    }
  }
  endRow()
  return rows
}

/** Quote a value as a SQL text literal ('' doubles embedded quotes). */
export function quote(v) {
  return `'${v.replaceAll("'", "''")}'`
}

/**
 * Build INSERT statements from parsed CSV rows (header row skipped). Throws
 * on a row whose field count differs from the header's; the error message
 * carries the 1-based file line number (header = line 1).
 */
export function buildInserts(table, rows, batchSize = 1000) {
  if (!/^[A-Za-z_][A-Za-z0-9_.]*$/.test(table)) {
    throw new Error(`unsafe table name: ${table}`)
  }
  if (!Number.isInteger(batchSize) || batchSize <= 0) {
    throw new Error(`invalid batch size: ${batchSize}`)
  }
  if (rows.length < 2) return '' // header only, or empty
  const width = rows[0].length
  const out = []
  for (let i = 1; i < rows.length; i += batchSize) {
    const batch = rows.slice(i, i + batchSize).map((r, j) => {
      if (r.length !== width) {
        throw new Error(`row ${i + j + 1} has ${r.length} fields, expected ${width}`)
      }
      return `(${r.map(quote).join(',')})`
    })
    out.push(`INSERT INTO ${table} VALUES\n${batch.join(',\n')};\n`)
  }
  return out.join('')
}

// CLI entry point (skipped when imported by tests)
if (process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href) {
  const args = process.argv.slice(2)
  const batchIdx = args.indexOf('--batch')
  const batchSize = batchIdx !== -1 ? Number(args.splice(batchIdx, 2)[1]) : 1000
  const [table, file] = args
  if (!table || !file) {
    console.error('usage: csv_to_inserts.mjs <table> <file.csv> [--batch <n>]')
    process.exit(1)
  }
  try {
    process.stdout.write(buildInserts(table, parseCsv(readFileSync(file, 'utf8')), batchSize))
  } catch (err) {
    console.error(err.message)
    process.exit(1)
  }
}
