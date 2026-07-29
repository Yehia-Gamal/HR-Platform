const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const publishableKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string | undefined;

const VALID_ENVIRONMENTS = ['development', 'staging', 'production'] as const;
type AppEnvironment = (typeof VALID_ENVIRONMENTS)[number];

const rawBuild = Number(import.meta.env.VITE_APP_BUILD ?? 10);
const rawEnv = ((import.meta.env.VITE_APP_ENVIRONMENT as string | undefined)?.trim() || 'production');

export const env = {
  supabaseUrl: url?.trim() ?? '',
  supabasePublishableKey: publishableKey?.trim() ?? '',
  devMocksEnabled:
    import.meta.env.DEV && import.meta.env.VITE_ENABLE_DEV_MOCKS === 'true',
  appVersion: (import.meta.env.VITE_APP_VERSION as string | undefined)?.trim() || '0.10.0',
  appBuild: Number.isFinite(rawBuild) ? rawBuild : 10,
  appEnvironment: (VALID_ENVIRONMENTS.includes(rawEnv as AppEnvironment) ? rawEnv : 'production') as AppEnvironment,
};

export const hasSupabaseConfig = Boolean(
  env.supabaseUrl && env.supabasePublishableKey,
);
