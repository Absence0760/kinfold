import { describe, expect, it } from 'vitest';
import component from './SavingsCalculator.svelte?raw';

// The calculator's results panel puts --accent-contrast text on --accent, and
// on translucent --accent-contrast tints over it. WCAG 1.4.3 needs 4.5:1 for
// its 13-14px lines. This recomputes every pair from the real tokens, light and
// dark, so a token or tint change that breaks it fails here, not in an audit.

// Vitest strips CSS imports (even `?raw`), and this workspace has no Node
// types, so read the token file through Node's own module loader.
type Fs = { readFileSync: (path: URL, encoding: 'utf8') => string };
const fs = (globalThis as unknown as { process: { getBuiltinModule: (id: string) => Fs } }).process.getBuiltinModule(
	'node:fs'
);
const css = fs.readFileSync(new URL('../../app.css', import.meta.url), 'utf8');
const style = component.slice(component.indexOf('<style>'));

type Rgb = [number, number, number];

function token(block: string, name: string): Rgb {
	const m = new RegExp(`--${name}:\\s*#([0-9a-f]{6})`, 'i').exec(block);
	if (!m) throw new Error(`token --${name} not found`);
	const h = m[1];
	return [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16)) as Rgb;
}

const light = css.slice(css.indexOf(':root'));
const dark = css.slice(css.indexOf('prefers-color-scheme: dark'));

const channel = (c: number) => {
	const s = c / 255;
	return s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
};
const luminance = ([r, g, b]: Rgb) => 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
const ratio = (a: Rgb, b: Rgb) => {
	const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
	return (hi + 0.05) / (lo + 0.05);
};
/** `color-mix(in srgb, top p%, transparent)` painted over `under`. */
const over = (top: Rgb, p: number, under: Rgb): Rgb => top.map((c, i) => c * p + under[i] * (1 - p)) as Rgb;

/** Every tint of --accent-contrast the results panel paints, as a fraction. */
const tints = [...style.matchAll(/color-mix\(in srgb, var\(--accent-contrast\) (\d+)%, transparent\)/g)].map(
	(m) => Number(m[1]) / 100
);

describe('SavingsCalculator results contrast', () => {
	it('fades no text with opacity', () => {
		expect(style).not.toMatch(/opacity\s*:/);
	});

	it('finds the panel tints it checks', () => {
		expect(tints.length).toBeGreaterThan(0);
	});

	for (const [scheme, block] of [
		['light', light],
		['dark', dark]
	] as const) {
		it(`keeps every text pair at 4.5:1 or more in ${scheme}`, () => {
			const accent = token(block, 'accent');
			const text = token(block, 'accent-contrast');
			expect(ratio(text, accent)).toBeGreaterThanOrEqual(4.5);
			for (const p of tints) expect(ratio(text, over(text, p, accent)), `${p * 100}% tint`).toBeGreaterThanOrEqual(4.5);
		});
	}

	it('matches the ratios stated in the component', () => {
		const r = (block: string, p: number) =>
			Math.round(ratio(token(block, 'accent-contrast'), over(token(block, 'accent-contrast'), p, token(block, 'accent'))) * 100) / 100;
		expect([r(light, 0), r(dark, 0)]).toEqual([6.41, 8.26]);
		expect([r(light, 0.1), r(dark, 0.1)]).toEqual([5.12, 6.93]);
	});
});
