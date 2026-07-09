#!/usr/bin/env node
// Throwaway pgTAP test server: a fresh in-memory PGlite (PostGIS + pgTAP)
// with the OpenComps schema applied, served over TCP so psql can run the
// suite. One instance per test run replaces the old drop/recreate of
// opencomps_test - PGlite has no CREATE DATABASE.
import { readFile } from 'node:fs/promises'
import { parseArgs } from 'node:util'
import { PGLiteSocketServer } from '@electric-sql/pglite-socket'
import { createOpenCompsDb } from './lib/opencomps_pglite.mjs'

const { values } = parseArgs({
  options: {
    schema: { type: 'string' },
    port: { type: 'string', default: '55433' },
  },
})
if (!values.schema) {
  console.error('usage: test_server.mjs --schema <path/to/schema.sql> [--port <n>]')
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
  await db.exec(await readFile(values.schema, 'utf8'))
  server = new PGLiteSocketServer({ db, port: Number(values.port), host: '127.0.0.1' })
  await server.start()
} catch (err) {
  console.error('test server failed to start:', err)
  await shutdown(1)
}

console.log(`READY postgres://postgres@127.0.0.1:${values.port}/postgres`)
