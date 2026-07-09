#!/usr/bin/env node
// OpenComps dev server on tinbase: PGlite with PostGIS, the schema applied as
// a tracked migration, the Supabase-compatible HTTP surface (REST / Auth /
// Storage / Studio), and the raw Postgres wire protocol over TCP for psql.
//
//   pnpm dev             persisted database in .tinbase/pglite/
//   pnpm dev -- --memory ephemeral in-memory database
//
// Ports: TINBASE_PORT (HTTP, default 54321), PGLITE_PORT (psql, default 55432).
import { randomBytes } from 'node:crypto'
import { mkdir, readdir, readFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { createBackend } from 'tinbase'
import { serve } from 'tinbase/node'
import { PGLiteSocketServer } from '@electric-sql/pglite-socket'
import { createOpenCompsDb, makeEngine } from './lib/opencomps_pglite.mjs'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const HTTP_PORT = Number(process.env.TINBASE_PORT ?? 54321)
const PG_PORT = Number(process.env.PGLITE_PORT ?? 55432)
const IN_MEMORY = process.argv.includes('--memory') || process.env.OPENCOMPS_MEMORY === '1'
const DATA_DIR = IN_MEMORY ? undefined : path.join(ROOT, '.tinbase', 'pglite')

// A per-run random secret: tinbase's built-in default secret is public (it's
// in the npm package), and the HTTP surface answers CORS from any origin, so
// signing with the default would let any webpage forge a service_role key
// against this server while it runs.
const JWT_SECRET = process.env.TINBASE_JWT_SECRET ?? randomBytes(32).toString('hex')

// Every supabase/migrations/*.sql, sorted by filename; tinbase applies the
// ones not yet recorded in supabase_migrations.schema_migrations.
const migDir = path.join(ROOT, 'supabase', 'migrations')
const migrations = await Promise.all(
  (await readdir(migDir))
    .filter((f) => f.endsWith('.sql'))
    .sort()
    .map(async (name) => ({
      name: name.replace(/\.sql$/, ''),
      sql: await readFile(path.join(migDir, name), 'utf8'),
    }))
)

let db, backend, http, socket
let closing = false
async function shutdown(code = 0) {
  if (closing) return
  closing = true
  await socket?.stop().catch(() => {})
  await http?.close().catch(() => {})
  await backend?.close().catch(() => {})
  if (!backend) await db?.close().catch(() => {})
  process.exit(code)
}
// Registered before any resource exists so a Ctrl-C mid-startup still cleans
// up (a persisted PGlite dataDir can otherwise be left with a stale lock).
process.on('SIGINT', () => shutdown(0))
process.on('SIGTERM', () => shutdown(0))

try {
  if (DATA_DIR) await mkdir(DATA_DIR, { recursive: true })
  db = await createOpenCompsDb({ dataDir: DATA_DIR })
  backend = await createBackend({ engine: makeEngine(db), migrations, jwtSecret: JWT_SECRET })

  // tinbase starts cron/pg_net workers unconditionally; OpenComps uses
  // neither, and their periodic ticks share PGlite's single session with any
  // open psql transaction (seed/load scripts) - stop the background traffic.
  backend.cron.stop()
  backend.net.stop()

  http = await serve(backend, { port: HTTP_PORT })
  socket = new PGLiteSocketServer({ db, port: PG_PORT, host: '127.0.0.1' })
  await socket.start()
} catch (err) {
  console.error('dev server failed to start:', err)
  await shutdown(1)
}

console.log(`
OpenComps dev server (${IN_MEMORY ? 'in-memory' : DATA_DIR})
  REST      http://127.0.0.1:${HTTP_PORT}/rest/v1/
  Studio    http://127.0.0.1:${HTTP_PORT}/_/
  psql      postgres://postgres@127.0.0.1:${PG_PORT}/postgres
  anon key:         ${backend.anonKey}
  service_role key: ${backend.serviceRoleKey}

Keys are signed with a per-run random secret (set TINBASE_JWT_SECRET for
stable keys across restarts).
Next steps: pnpm load-zips && pnpm seed
`)
