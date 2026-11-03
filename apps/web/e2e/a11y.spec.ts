import { expect, test } from '@playwright/test';
import type { Page } from '@playwright/test';
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
//
// The fourth "route" is not a route: any unknown path answers with the error
// page through the static adapter's 200.html fallback, and a mistyped link
// lands a reader there like any visitor - so the error page is an audited
// public surface too.

const publicRoutes = ['/', '/transparency', '/signin', '/no-such-page-anywhere'];

async function overflowReports(page: Page) {
	const overflows = await page.evaluate(() => {
		const wide = [];
		const viewport = window.innerWidth;
		// The promise itself, in the words WCAG states it: the document must
		// not scroll sideways to be read.
		if (document.documentElement.scrollWidth > viewport + 1) {
			wide.push(`the page scrolls ${document.documentElement.scrollWidth - viewport}px sideways at ${viewport}px`);
		}
		// Named culprits, but only real ones: an element inside a container
		// that clips it (or inside a closed menu, which keeps its layout but
		// shows nothing) never causes the page to scroll, so flagging one
		// would accuse a page that a reader can already use.
		for (const el of document.body.querySelectorAll('*')) {
			const holder = el.closest('details');
			if (holder && !holder.hasAttribute('open')) continue;
			const right = el.getBoundingClientRect().right;
			if (right > viewport + 1) {
				let clipped = false;
				for (let p = el.parentElement; p; p = p.parentElement) {
					const style = getComputedStyle(p);
					if (style.display === 'none' || style.visibility === 'hidden') {
						clipped = true;
						break;
					}
					if (style.overflowX === 'hidden' || style.overflowX === 'clip' || style.overflowX === 'scroll' || style.overflowX === 'auto') {
						clipped = true;
						break;
					}
				}
				if (!clipped) {
					wide.push(`${el.tagName}.${(el.getAttribute('class') || '')} sticks ${Math.round(right - viewport)}px past the edge`);
				}
			}
		}
		return wide;
	});
	return overflows;
}

async function screenReaderProblems(page: Page) {
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
		// A duplicate id is invalid HTML, and it breaks the one control a reader
		// relies on to jump in: a fragment link resolves to whichever element the
		// browser picks, not the one intended.
		const idCount = new Map();
		for (const el of document.querySelectorAll('[id]')) {
			idCount.set(el.id, (idCount.get(el.id) || 0) + 1);
		}
		for (const id of idCount.keys()) {
			const count = idCount.get(id) || 0;
			if (count > 1) {
				found.push(`id "${id}" sits on ${count} elements`);
			}
		}
		// A skip link must land somewhere: an in-page fragment with no target
		// leaves the reader tabbing through the whole page instead.
		for (const a of document.querySelectorAll('a[href^="#"]')) {
			const target = (a.getAttribute('href') || '').slice(1);
			if (target !== '' && !document.getElementById(target)) {
				found.push(`skip link: #${target} has no element on the page`);
			}
		}
		// A keyboard reader's first tab must be the skip link: if anything else
		// takes focus first, the reader walks the whole menu before they can jump.
		const focusable = document.querySelectorAll(
			'a[href], button, input:not([type="hidden"]), textarea, select, [tabindex]'
		);
		for (const el of focusable) {
			if (el.classList.contains('skip-link')) {
				if (el !== focusable[0]) {
					found.push('skip link: something else takes focus before it: ' + focusable[0].tagName + '.' + focusable[0].className);
				}
				break;
			}
		}
		return found;
	});
	return problems;
}


// WCAG's reflow promise, which is the roadmap's "large text from day one": a
// reader at 200%% zoom has the layout of a 320px-wide screen, and a page that
// answers it with a sideways scroll makes them drag diagonally to read a line.
for (const route of publicRoutes) {
	test(`${route} reflows at 320 CSS px without a sideways scroll`, async ({ page }) => {
		// WCAG's reflow rule is what the roadmap's "large text from day one"
		// promises: a reader at 200% zoom has the layout of a 320px-wide screen,
		// and a page that answers it with a sideways scroll makes them drag
		// diagonally to finish a line. The viewport is resized instead of zoomed,
		// because the layout question is the same and a fixed viewport meta would
		// be caught by the other audit rule.
		await page.setViewportSize({ width: 320, height: 640 });
		await gotoHydrated(page, route);
		expect(await overflowReports(page)).toEqual([]);
	});
}

for (const route of publicRoutes) {
	// The evaluate callback is plain JS: Playwright serializes it into the page,
	// so no TypeScript annotations may appear inside it.
	test(`${route} is navigable by a screen reader`, async ({ page }) => {
		// Audit the hydrated document: panels swap in at hydrate, and the audit
		// must see what a reader actually sees.
		await gotoHydrated(page, route);
		expect(await screenReaderProblems(page)).toEqual([]);
	});
}

const prerenderedPublicRoutes = ['/', '/transparency'];

// The same promise has to hold for the copy a reader gets when JavaScript is
// blocked - reader mode, a blocked tracker, a script-free browser: for the
// prerendered public pages, the static adapter's HTML is what lands on their
// wire before any script runs, and screen readers work on that copy. Only the
// prerendered pages join this pass; sign-in and the error fallback are
// client-side rendered, so without JS they carry no content to audit.
test.describe('with JavaScript blocked', () => {
	test.use({ javaScriptEnabled: false });
	for (const route of prerenderedPublicRoutes) {
		test(`${route} is navigable by a screen reader without JavaScript`, async ({ page }) => {
			await page.goto(route);
			await page.waitForLoadState('networkidle');
			expect(await screenReaderProblems(page)).toEqual([]);
		});
		test(`${route} reflows at 320 CSS px without JavaScript`, async ({ page }) => {
			await page.setViewportSize({ width: 320, height: 640 });
			await page.goto(route);
			await page.waitForLoadState('networkidle');
			expect(await overflowReports(page)).toEqual([]);
		});
	}
});
