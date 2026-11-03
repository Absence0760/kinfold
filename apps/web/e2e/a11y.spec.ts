import { expect, test } from '@playwright/test';
import { gotoHydrated } from './helpers.ts';

// The roadmap's accessibility bullet ("the member app is usable with a screen
// reader and large text from day one, because people post requests on their
// worst days") gets teeth: a screen reader walks the document the way these
// rules do - it announces the page's language, navigates by headings, names
// every control, and skips what's decorative. CI has no stack, so the member
// area redirects to /signin and this audit covers the public surfaces (landing,
// transparency, sign-in); it grows to the consoles once a configured stack runs
// them. Rules collect named problems, so a failure points at the element, not a
// role count.

const publicRoutes = ['/', '/transparency', '/signin'];

for (const route of publicRoutes) {
	// The evaluate callback is plain JS: Playwright serializes it into the page,
	// so no TypeScript annotations may appear inside it.
	test(`${route} is navigable by a screen reader`, async ({ page }) => {
		// Audit the hydrated document: panels swap in at hydrate, and the audit
		// must see what a reader actually sees.
		await gotoHydrated(page, route);
		const problems = await page.evaluate(() => {
			const found = [];
			if (!document.documentElement.getAttribute('lang')) {
				found.push('html: no lang attribute');
			}
			if (!document.querySelector('head meta[name="viewport"]')) {
				found.push('head: no viewport meta, so large text cannot reflow');
			}
			const heads = [...document.querySelectorAll('h1, h2, h3, h4, h5, h6')]
				.map((h) => Number(h.tagName[1]));
			if (heads.length === 0 || heads[0] !== 1) {
				found.push('headings: no h1 to anchor the outline');
			}
			for (let i = 1; i < heads.length; i += 1) {
				if (heads[i] > heads[i - 1] + 1) {
					found.push(`headings: h${heads[i - 1]} jumps to h${heads[i]}`);
				}
			}
			for (const img of document.querySelectorAll('img')) {
				if (img.getAttribute('alt') === null) {
					found.push('img: no alt, a reader hears nothing: ' + (img.src || img.id || ''));
				}
			}
			// Every control must announce itself: a button or a link whose only
			// content is an icon leaves the reader with no idea what it does.
			for (const btn of document.querySelectorAll('button')) {
				const name = (btn.textContent || '').trim() || (btn.getAttribute('aria-label') || '').trim();
				if (!name) {
					found.push('button: no name a reader can hear');
				}
			}
			for (const a of document.querySelectorAll('a')) {
				const name = (a.textContent || '').trim() || (a.getAttribute('aria-label') || '').trim();
				if (!name) {
					found.push('link: no name a reader can hear: ' + (a.href || ''));
				}
			}
			// Form fields must carry a label the reader can hear: either one
			// wired by id, one wrapped around the field, or the field's own
			// label attribute. A bare field is a mystery button.
			for (const field of document.querySelectorAll('input')) {
				if (field.getAttribute('type') === 'hidden') {
					continue;
				}
				const labelled = (field.getAttribute('aria-label') || '').trim();
				const wired = field.id !== '' && [...document.querySelectorAll('label')]
					.some((l) => l.htmlFor === field.id);
				if (!labelled && !wired && !field.closest('label')) {
					found.push('input: a reader gets no name for this field');
				}
			}
			return found;
		});
		expect(problems).toEqual([]);
	});
}

