// Shared PGlite factory for OpenComps: one place that knows which extensions
// the schema needs, plus the adapter that lets tinbase drive a PGlite we own.
import { PGlite } from '@electric-sql/pglite'
import { citext } from '@electric-sql/pglite/contrib/citext'
import { pg_trgm } from '@electric-sql/pglite/contrib/pg_trgm'
import { btree_gist } from '@electric-sql/pglite/contrib/btree_gist'
import { postgis } from '@electric-sql/pglite-postgis'
import { pgtap } from '@electric-sql/pglite-pgtap'

/**
 * Create a PGlite instance with every extension the OpenComps schema and its
 * pgTAP suite rely on. Omit dataDir for an in-memory database.
 */
export async function createOpenCompsDb({ dataDir } = {}) {
  const db = new PGlite({
    dataDir,
    extensions: { citext, pg_trgm, btree_gist, postgis, pgtap },
  })
  await db.waitReady
  return db
}

/** Adapt a PGlite instance (or transaction) to tinbase's DbEngine interface. */
export function makeEngine(db) {
  return {
    async query(sql, params) {
      const res = await db.query(sql, params)
      return { rows: res.rows, affectedRows: res.affectedRows ?? 0 }
    },
    async exec(sql) {
      await db.exec(sql)
    },
    transaction(fn) {
      return db.transaction((tx) => fn(makeEngine(tx)))
    },
    async listen(channel, cb) {
      return db.listen(channel, cb)
    },
    close: () => db.close(),
  }
}
