import { describe, expect, it } from 'vitest';
import { navSections } from './sections.ts';

// Every landing component's source, so the test sees the ids the page renders.
const sources = import.meta.glob<string>('./*.svelte', {
	query: '?raw',
	import: 'default',
	eager: true
});
const sectionIds = Object.values(sources)
	.flatMap((src) => [...src.matchAll(/<section[^>]*\bid="([^"]+)"/g)])
	.map((m) => m[1]);

describe('nav sections', () => {
	it('every nav link targets a section that exists', () => {
		for (const s of navSections) expect(sectionIds, `#${s.id}`).toContain(s.id);
	});

	it('has no duplicate ids or labels', () => {
		expect(new Set(navSections.map((s) => s.id)).size).toBe(navSections.length);
		expect(new Set(navSections.map((s) => s.label)).size).toBe(navSections.length);
	});
});
