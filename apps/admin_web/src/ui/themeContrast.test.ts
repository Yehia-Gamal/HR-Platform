// @vitest-environment node
// @vitest-environment node
/// <reference types="node" />

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const css = readFileSync(resolve(import.meta.dirname, '../../../../packages/design-tokens/theme.css'), 'utf8');
const darkBlock = css.match(/\[data-theme='dark'\]\s*\{([\s\S]*?)\}/)?.[1] ?? '';

function token(name: string) {
  const value = darkBlock.match(new RegExp(`--${name}:\\s*(#[0-9a-fA-F]{6})`))?.[1];
  if (!value) throw new Error(`Missing dark theme token: ${name}`);
  return value;
}

function luminance(hex: string) {
  const channels = hex
    .slice(1)
    .match(/../g)!
    .map((value) => parseInt(value, 16) / 255);
  const linear = channels.map((value) => (value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4));
  return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2];
}

function contrast(foreground: string, background: string) {
  const [a, b] = [luminance(foreground), luminance(background)].sort((x, y) => y - x);
  return (a + 0.05) / (b + 0.05);
}

describe('dark design tokens', () => {
  it.each([
    ['brand-primary', 'surface'],
    ['brand-primary', 'brand-primary-soft'],
    ['success', 'success-soft'],
    ['warning', 'warning-soft'],
    ['danger', 'danger-soft'],
    ['info', 'info-soft'],
  ])('%s remains readable on %s', (foreground, background) => {
    expect(contrast(token(foreground), token(background))).toBeGreaterThanOrEqual(4.5);
  });

  it('keeps primary actions readable', () => {
    expect(contrast(token('action-primary-fg'), token('action-primary-bg'))).toBeGreaterThanOrEqual(4.5);
  });
});
