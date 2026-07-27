// @vitest-environment node
// @vitest-environment node
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const styles = readFileSync(resolve(import.meta.dirname, '../styles.css'), 'utf8');

describe('touch target design contracts', () => {
  it.each([
    ['icon buttons', /\.icon-button\s*\{[^}]*width:\s*2\.75rem;[^}]*height:\s*2\.75rem;/s],
    ['sidebar links', /\.sidebar-link\s*\{[^}]*min-height:\s*44px;/s],
    ['logout', /\.sidebar-logout\s*\{[^}]*min-height:\s*44px;/s],
    ['filter chips', /\.filter-chip\s*\{[^}]*min-height:\s*44px;/s],
    ['password visibility', /\.password-visibility-button\s*\{[^}]*width:\s*44px;[^}]*height:\s*44px;/s],
  ])('%s remain at least 44px', (_, contract) => {
    expect(styles).toMatch(contract);
  });
});
