// Dev-only loader for domain mocks.
// `import.meta.env.DEV` is statically replaced at build time, so in production
// builds the dynamic import below becomes dead code and Rollup excludes
// domainMocks.ts from the bundle entirely (mock data never ships to prod).
export async function loadDomainMocks() {
  if (!import.meta.env.DEV) {
    throw new Error('mocks are dev-only');
  }
  return import('./domainMocks');
}
