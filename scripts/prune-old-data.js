'use strict';
// Deletes CGM entries/treatments/devicestatus older than RETENTION_DAYS.
// Run on the VM (via .github/workflows/prune-db.yml) so the connection
// comes from the IP already whitelisted in MongoDB Atlas.
const { MongoClient } = require('mongodb');

const RETENTION_DAYS = 90;
const cutoffMs = Date.now() - RETENTION_DAYS * 24 * 60 * 60 * 1000;
const cutoffIso = new Date(cutoffMs).toISOString();

const TARGETS = [
  { collection: 'entries', field: 'date', cutoff: cutoffMs },
  { collection: 'treatments', field: 'created_at', cutoff: cutoffIso },
  { collection: 'devicestatus', field: 'created_at', cutoff: cutoffIso },
];

async function main() {
  const uri = process.env.MONGODB_URI;
  if (!uri) {
    throw new Error('MONGODB_URI is not set in the environment');
  }

  const client = new MongoClient(uri);
  await client.connect();
  const db = client.db();

  console.log(`Pruning records older than ${RETENTION_DAYS} days (cutoff ${cutoffIso})`);
  for (const { collection, field, cutoff } of TARGETS) {
    const result = await db.collection(collection).deleteMany({ [field]: { $lt: cutoff } });
    console.log(`${collection}: deleted ${result.deletedCount}`);
  }

  await client.close();
}

main().catch((err) => {
  console.error('Prune job failed:', err);
  process.exit(1);
});
