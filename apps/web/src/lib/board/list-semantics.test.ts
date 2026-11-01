import { describe, expect, it } from 'vitest';

// Safari/VoiceOver stop exposing a list when its markers are removed with
// `list-style: none`, so the item count and the rotor stop are lost. Every
// list whose class resets the markers must put the semantics back with
// `role="list"`. Scoped to the member pages this guard was written with
// (board, loans, invites, review); widen SCOPE as other areas adopt it.

const SCOPE = ['/src/routes/app/board/', '/src/routes/app/loans/', '/src/routes/app/invite/', '/src/routes/app/review/', '/src/lib/invites/'];

const sources = import.meta.glob<string>('/src/**/*.svelte', { query: '?raw', import: 'default', eager: true });
const files = Object.entries(sources).filter(([file]) => SCOPE.some((d) => file.startsWith(d)));

describe('lists that reset their markers keep list semantics', () => {
	it('scans the scoped pages', () => {
		expect(files.length).toBeGreaterThan(10);
	});

	for (const [file, text] of files) {
		if (!/list-style:\s*none/.test(text)) continue;
		// Classes whose CSS rule resets the markers, e.g. `.cards { list-style: none }`.
		const reset = new Set(
			[...text.matchAll(/([^{}]+)\{[^}]*list-style:\s*none[^}]*\}/g)].flatMap((m) =>
				[...m[1].matchAll(/\.([\w-]+)\s*(?:,|$)/g)].map((c) => c[1])
			)
		);
		it(file, () => {
			const lists = (text.match(/<(ul|ol)\b[^>]*>/g) ?? []).filter((tag: string) =>
				(/class="([^"]*)"/.exec(tag)?.[1] ?? '').split(/\s+/).some((c) => reset.has(c))
			);
			expect(lists.length, `no list uses ${[...reset].join(', ')}`).toBeGreaterThan(0);
			for (const tag of lists) expect(tag, 'add role="list" to this list').toMatch(/role="list"/);
		});
	}
});
