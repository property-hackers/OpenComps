#!/usr/bin/env node
// Throwaway pgTAP test server: a fresh in-memory PGlite (PostGIS + pgTAP)
// with the OpenComps schema applied, served over TCP so psql can run the
// suite. One instance per test run replaces the old drop/recreate of
// opencomps_test - PGlite has no CREATE DATABASE.
import { readFile, readdir } from 'node:fs/promises'
import { join } from 'node:path'
import { parseArgs } from 'node:util'
import { PGLiteSocketServer } from '@electric-sql/pglite-socket'
import { createOpenCompsDb } from './lib/opencomps_pglite.mjs'

const MIGRATIONS_DIR = new URL('../supabase/migrations', import.meta.url).pathname

const { values } = parseArgs({
  options: {
    schema: { type: 'string', multiple: true },
    port: { type: 'string', default: '55433' },
  },
})

// Default: every supabase/migrations/*.sql in timestamp order (the same
// order tinbase applies them); --schema <path> overrides.
const schemaFiles = values.schema?.length
  ? values.schema
  : (await readdir(MIGRATIONS_DIR))
      .filter((f) => f.endsWith('.sql'))
      .sort()
      .map((f) => join(MIGRATIONS_DIR, f))
if (schemaFiles.length === 0) {
  console.error('no migrations found; usage: test_server.mjs [--schema <path>]... [--port <n>]')
  process.exit(1)
}

let db, server
let closing = false
async function shutdown(code = 0) {
  if (closing) return
  closing = true
  await server?.stop().catch(() => {})
  await db?.close().catch(() => {})
  process.exit(code)
}
process.on('SIGINT', () => shutdown(0))
process.on('SIGTERM', () => shutdown(0))

try {
  db = await createOpenCompsDb()
  for (const file of schemaFiles) {
    await db.exec(await readFile(file, 'utf8'))
  }
  server = new PGLiteSocketServer({ db, port: Number(values.port), host: '127.0.0.1' })
  await server.start()
} catch (err) {
  console.error('test server failed to start:', err)
  await shutdown(1)
}

console.log(`READY postgres://postgres@127.0.0.1:${values.port}/postgres`)
