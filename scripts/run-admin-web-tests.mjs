import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const vitest = fileURLToPath(new URL('../node_modules/vitest/vitest.mjs', import.meta.url));
const webRoot = fileURLToPath(new URL('../apps/admin_web/', import.meta.url));
const shardCount = 4;
// Windows CI and low-disk developer machines can time out while starting two
// jsdom fork workers at once. Keep the bounded shards, but run them serially.
const concurrency = 1;

function runShard(index) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [vitest, 'run', '--maxWorkers=1', `--shard=${index}/${shardCount}`], {
      cwd: webRoot,
      env: process.env,
      stdio: 'inherit',
    });

    child.on('error', reject);
    child.on('exit', (code, signal) => {
      if (signal) reject(new Error(`Vitest shard ${index}/${shardCount} stopped by ${signal}.`));
      else if (code !== 0) reject(new Error(`Vitest shard ${index}/${shardCount} failed with exit code ${code}.`));
      else resolve();
    });
  });
}

for (let start = 1; start <= shardCount; start += concurrency) {
  const batch = [];
  for (let index = start; index < Math.min(start + concurrency, shardCount + 1); index += 1) {
    batch.push(runShard(index));
  }
  await Promise.all(batch);
}
