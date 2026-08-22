// Supabase Edge Functions Shared Contracts Bridge
// Re-exports schemas and types from @ahla/shared-contracts for Deno runtime.
//
// ملاحظة مهمة: نشير إلى dist/index.js (النسخة المبنية) وليس src/index.ts،
// لأن Deno لا يحوّل استيرادات './x.js' داخل كود TS المصدر إلى x.ts —
// فيفشل البناء بخطأ "failed to read file ... .js: no such file or directory".
// يجب تشغيل `npm run build --workspace @ahla/shared-contracts` قبل
// `supabase functions deploy` أو `supabase start` (CI يبنيه ضمن check:all).

export * from '../../../packages/shared-contracts/dist/index.js';
