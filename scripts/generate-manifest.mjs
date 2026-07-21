import { createHash } from 'node:crypto';
import { readdir, readFile, stat, writeFile } from 'node:fs/promises';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const ignored = new Set(['node_modules', '.git', 'dist', 'build', '.dart_tool', 'BUILD_MANIFEST.json']);
const rows = [];

async function walk(directory) {
  for (const name of await readdir(directory)) {
    if (ignored.has(name)) continue;
    const full = join(directory, name);
    const info = await stat(full);
    if (info.isDirectory()) await walk(full);
    else {
      const content = await readFile(full);
      rows.push({
        path: relative(root, full),
        size: content.byteLength,
        sha256: createHash('sha256').update(content).digest('hex'),
      });
    }
  }
}

await walk(root);
rows.sort((a, b) => a.path.localeCompare(b.path));
await writeFile(
  join(root, 'BUILD_MANIFEST.json'),
  JSON.stringify({ generatedAt: new Date().toISOString(), files: rows }, null, 2),
);
console.log(`Manifest written with ${rows.length} files.`);
