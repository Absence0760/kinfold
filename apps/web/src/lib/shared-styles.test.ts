import { describe, expect, it } from 'vitest';

// Utilities defined once in src/app.css. A component that redefines one drifts
// from the rest (an old copy here missed `padding: 0` and `border: 0`), so
// components use the global class instead of copying it.
const shared = ['visually-hidden', 'skip-link'];

const sources = import.meta.glob<string>('/src/**/*.svelte', {
	query: '?raw',
	import: 'default',
	eager: true
});

describe('shared style utilities', () => {
	it('are not redefined in any component', () => {
		for (const [file, src] of Object.entries(sources)) {
			for (const name of shared) {
				expect(src, `${file} redefines .${name}`).not.toMatch(new RegExp(`^\\s*\\.${name}\\s*\\{`, 'm'));
			}
		}
	});

	it('skeleton animation is defined once', () => {
		for (const [file, src] of Object.entries(sources)) {
			expect(src, `${file} defines its own pulse keyframes`).not.toMatch(/@keyframes pulse/);
		}
	});
});

// Form fields need a ≥3:1 outline (WCAG 1.4.11); --border (≈1.3:1) is for card
// edges. Every input, select, textarea or .field rule draws its border with
// --field-border instead.
describe('form field outlines', () => {
	it('never use the low-contrast card border', () => {
		for (const [file, src] of Object.entries(sources)) {
			const css = src.slice(Math.max(0, src.indexOf('<style>')));
			for (const [, selector, body] of css.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
				if (!/(^|[\s,>(])(input|select|textarea)\b|\.field\b/.test(selector.trim())) continue;
				expect(body, `${file}: ${selector.trim()} uses --border`).not.toMatch(/border(-color)?\s*:[^;]*var\(--border\)/);
			}
		}
	});
});
