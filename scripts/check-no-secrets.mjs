import { readFile, readdir } from 'node:fs/promises';
import { extname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const excludedDirectories = new Set([
  '.git', 'node_modules', 'dist', 'build', '.dart_tool', '.idea', '.vscode', '.claude',
]);
const allowedExtensions = new Set([
  '.ts', '.tsx', '.js', '.mjs', '.dart', '.sql', '.json', '.yaml', '.yml',
  '.toml', '.sh', '.py', '.properties', '.gradle', '.xml', '.html', '.css',
  '.ps1',
]);
const allowedFiles = new Set(['Dockerfile']);
// Firebase's Android client configuration is packaged into the APK by design;
// its API key identifies the Firebase project but does not grant privileged
// server access. Keep scanning this file for every other secret pattern.
const publicGoogleApiKeyFiles = new Set([
  'apps/mobile_flutter/android/app/google-services.json',
]);
const findings = [];
const patterns = [
  ['private-key', /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/],
  ['github-token', /\b(?:ghp|gho|ghu|ghs|ghr|github_pat)_[A-Za-z0-9_]{20,}\b/],
  ['aws-access-key', /\bAKIA[0-9A-Z]{16}\b/],
  ['google-api-key', /\bAIza[0-9A-Za-z_-]{30,}\b/],
  ['stripe-live-key', /\b(?:sk|rk)_live_[0-9A-Za-z]{16,}\b/],
  ['supabase-secret-key', /\bsb_secret_[0-9A-Za-z_-]{20,}\b/],
  ['jwt-service-token', /\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\b/],
  ['hardcoded-secret-assignment', /(?:SUPABASE_SERVICE_ROLE_KEY|DATABASE_PASSWORD|PUSH_PROVIDER_TOKEN|CRON_SECRET)\s*[:=]\s*["'](?!YOUR_|generate-|<|\$\{|\$\(|process\.|Deno\.env)[^"']{16,}["']/],
  // audit REL-02: catch *_PEPPER / *_SECRET / *_TOKEN assignments; allow
  // documented dev placeholders (local-dev-…, change-in-prod, YOUR_, generate-)
  // and env-reference forms (process.env / Deno.env / ${…}).
  ['hardcoded-pepper-or-secret', /\b[A-Z0-9_]*(?:PEPPER|SECRET|TOKEN|PASSWORD)\s*[:=]\s*["'](?!YOUR_|generate-|<|\$\{|\$\(|process\.|Deno\.env|local-dev|change-in-prod|placeholder)[^"']{16,}["']/],
];

async function walk(directory) {
  let entries;
  try {
    entries = await readdir(directory, { withFileTypes: true });
  } catch (err) {
    if (err?.code === 'ENOENT' || err?.code === 'EPERM') return;
    throw err;
  }
  for (const entry of entries) {
    if (entry.isDirectory() && excludedDirectories.has(entry.name)) continue;
    const fullPath = join(directory, entry.name);
    if (entry.isDirectory()) {
      await walk(fullPath);
      continue;
    }
    if (!allowedExtensions.has(extname(entry.name)) && !allowedFiles.has(entry.name)) continue;
    let source;
    try {
      source = await readFile(fullPath, 'utf8');
    } catch (err) {
      if (err?.code === 'ENOENT') continue;
      throw err;
    }
    const relativePath = relative(root, fullPath).replaceAll('\\', '/');
    for (const [kind, pattern] of patterns) {
      if (kind === 'google-api-key' && publicGoogleApiKeyFiles.has(relativePath)) continue;
      const match = source.match(pattern);
      if (match) findings.push({ kind, file: relativePath, preview: match[0].slice(0, 32) });
    }
  }
}

await walk(root);
if (findings.length) {
  console.error('Potential committed secrets found:');
  for (const finding of findings) console.error(`- ${finding.kind}: ${finding.file} (${finding.preview}…)`);
  process.exit(1);
}
console.log('Secret scan passed: no high-confidence committed credentials found.');
