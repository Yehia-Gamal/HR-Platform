// Dev-only loader for Association Projects mocks.
// `import.meta.env.DEV` is statically replaced at build time, so in production
// builds the dynamic import below becomes dead code and Rollup excludes
// projectMocks.ts from the bundle entirely (mock data never ships to prod).
export async function loadProjectMocks() {
  if (!import.meta.env.DEV) {
    throw new Error('projectMocks are dev-only');
  }
  return import('./projectMocks');
}
