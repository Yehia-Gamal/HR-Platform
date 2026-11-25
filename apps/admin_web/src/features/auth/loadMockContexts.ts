// Dev-only loader for mock Auth personas.
// `import.meta.env.DEV` is statically replaced at build time, so in production
// builds the dynamic import below becomes dead code and Rollup excludes
// mockContexts.ts from the bundle entirely (mock personas never ship to prod).
export async function loadMockContexts() {
  if (!import.meta.env.DEV) {
    throw new Error('mockContexts are dev-only');
  }
  return import('./mockContexts');
}
