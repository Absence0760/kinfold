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
