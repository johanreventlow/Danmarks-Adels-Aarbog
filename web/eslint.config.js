// Kun react-hooks-reglerne (review 37 W10): rules-of-hooks = error, exhaustive-deps = warn.
// Ingen generel stilguide — TypeScript-parseren er her for at kunne læse .ts/.tsx.
import reactHooks from 'eslint-plugin-react-hooks';
import tseslint from 'typescript-eslint';

export default [
  { ignores: ['dist/**', 'node_modules/**', 'e2e/**', 'scripts/**', '*.config.*'] },
  {
    files: ['src/**/*.{ts,tsx}'],
    languageOptions: { parser: tseslint.parser, parserOptions: { ecmaFeatures: { jsx: true } } },
    plugins: { 'react-hooks': reactHooks },
    rules: {
      'react-hooks/rules-of-hooks': 'error',
      'react-hooks/exhaustive-deps': 'warn',
    },
  },
];
