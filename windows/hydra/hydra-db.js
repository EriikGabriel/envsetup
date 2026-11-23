// Reads and writes the settings of Hydra Launcher in its LevelDB (hydra-db),
// for windows/hydra-settings.ps1. Hydra keeps its themes in the sublevel
// "themes" (keys "!themes!<id>") and the preferences in the root keys
// "userPreferences" and "language", every value as JSON.
//
//   node hydra-db.js export <db> <out.json> <secrets.json>
//       the active theme (or all themes), the preferences and the language;
//       keys, tokens and passwords go to <secrets.json>, not to <out.json>
//   node hydra-db.js import <db> <in.json> [<secrets.json>]
//       writes them back (Hydra must be closed): the themes are added or
//       replaced, the saved active one is made the only active one, and the
//       saved preferences are merged over the ones already there
//   node hydra-db.js check <db> <in.json>
//       exit 1 when the saved active theme is not the active one in <db>
//
// The login (auth, user) and the library are never read or written.
const { ClassicLevel } = require('classic-level');
const fs = require('fs');

const SECRET = /key|token|password|secret/i;
const read = (f) => JSON.parse(fs.readFileSync(f, 'utf8'));
const write = (f, v) => fs.writeFileSync(f, JSON.stringify(v, null, 2) + '\n');

async function getJson(db, key) {
  try { return JSON.parse(await db.get(key)); } catch (e) { return undefined; }
}

// The value as stored (the language is a bare string, not JSON).
async function getRaw(db, key) {
  try { return await db.get(key); } catch (e) { return undefined; }
}

async function themes(db) {
  const out = [];
  for await (const [, v] of db.iterator({ gte: '!themes!', lt: '!themes"' })) {
    try { out.push(JSON.parse(v)); } catch (e) { /* not a theme */ }
  }
  return out;
}

async function main() {
  const [cmd, dbPath, file, secretsFile] = process.argv.slice(2);
  const db = new ClassicLevel(dbPath, { valueEncoding: 'utf8', createIfMissing: cmd === 'import' });
  await db.open();
  try {
    if (cmd === 'export') {
      const prefs = (await getJson(db, 'userPreferences')) || {};
      const clean = {}, secrets = {};
      for (const [k, v] of Object.entries(prefs)) (SECRET.test(k) ? secrets : clean)[k] = v;
      const all = await themes(db);
      write(file, {
        language: await getRaw(db, 'language'),
        activeTheme: (all.find((t) => t.isActive) || {}).name || null,
        themes: all,
        userPreferences: clean,
      });
      write(secretsFile, { userPreferences: secrets });
      console.log(`exported ${all.length} theme(s), ${Object.keys(clean).length} preferences, ${Object.keys(secrets).length} secret(s)`);
    } else if (cmd === 'import') {
      const saved = read(file);
      const secrets = secretsFile && fs.existsSync(secretsFile) ? read(secretsFile) : { userPreferences: {} };
      const ops = [];
      const savedIds = new Set(saved.themes.map((t) => t.id));
      if (saved.activeTheme) {
        for (const t of await themes(db)) {
          if (!savedIds.has(t.id) && t.isActive) ops.push({ type: 'put', key: `!themes!${t.id}`, value: JSON.stringify({ ...t, isActive: false }) });
        }
      }
      for (const t of saved.themes) {
        ops.push({ type: 'put', key: `!themes!${t.id}`, value: JSON.stringify({ ...t, isActive: t.name === saved.activeTheme }) });
      }
      const prefs = { ...((await getJson(db, 'userPreferences')) || {}), ...saved.userPreferences, ...(secrets.userPreferences || {}) };
      ops.push({ type: 'put', key: 'userPreferences', value: JSON.stringify(prefs) });
      if (saved.language) ops.push({ type: 'put', key: 'language', value: saved.language });
      await db.batch(ops);
      console.log(`imported ${saved.themes.length} theme(s) (active: ${saved.activeTheme || 'none'}) and ${Object.keys(prefs).length} preferences`);
    } else if (cmd === 'check') {
      const saved = read(file);
      const active = ((await themes(db)).find((t) => t.isActive) || {}).name || null;
      if (active !== (saved.activeTheme || null)) { console.log(`active theme: ${active || 'none'}, saved: ${saved.activeTheme}`); process.exitCode = 1; }
    } else {
      throw new Error(`unknown command ${cmd}`);
    }
  } finally {
    await db.close();
  }
}

main().catch((e) => { console.error(e.message); process.exit(2); });
