const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const publishableKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string | undefined;

export const env = {
  supabaseUrl: url?.trim() ?? '',
  supabasePublishableKey: publishableKey?.trim() ?? '',
  devMocksEnabled:
    import.meta.env.DEV && import.meta.env.VITE_ENABLE_DEV_MOCKS === 'true',
  appVersion: (import.meta.env.VITE_APP_VERSION as string | undefined)?.trim() || '0.10.0',
  appBuild: Number(import.meta.env.VITE_APP_BUILD ?? 10),
  appEnvironment: ((import.meta.env.VITE_APP_ENVIRONMENT as string | undefined)?.trim() || 'production') as 'development' | 'staging' | 'production',
};

export const hasSupabaseConfig = Boolean(
  env.supabaseUrl && env.supabasePublishableKey,
);
