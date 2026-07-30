import js from '@eslint/js';
import tseslint from 'typescript-eslint';
import reactHooks from 'eslint-plugin-react-hooks';

export default tseslint.config(
  {
    ignores: ['node_modules/**', 'dist/**', '.claude/**', 'supabase/functions/**'],
  },

  {
    files: ['apps/admin_web/src/**/*.{ts,tsx}'],
    extends: [js.configs.recommended, ...tseslint.configs.recommended],
    plugins: {
      'react-hooks': reactHooks,
    },
    rules: {
      '@typescript-eslint/no-explicit-any': 'warn',
      'no-console': ['error', { allow: ['error', 'warn'] }],
      'react-hooks/rules-of-hooks': 'error',
      'react-hooks/exhaustive-deps': 'warn',
      'no-dangerouslySetInnerHTML': 'off',
    },
  },

  {
    files: ['apps/admin_web/src/**/*.{ts,tsx}'],
    rules: {
      'no-restricted-properties': [
        'error',
        {
          object: '',
          property: 'dangerouslySetInnerHTML',
          message: 'dangerouslySetInnerHTML is forbidden for security reasons.',
        },
      ],
      'no-restricted-syntax': [
        'error',
        {
          selector: 'JSXAttribute[name.name="dangerouslySetInnerHTML"]',
          message: 'dangerouslySetInnerHTML is forbidden for security reasons.',
        },
      ],
    },
  },
);
