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
		const lang = (document.documentElement.getAttribute('lang') || '').trim();
		if (!lang) {
			found.push('html: no lang attribute');
		} else if (!/^[a-z]{2,3}(-[a-z0-9]{2,3})*$/i.test(lang) || lang.toLowerCase() === 'und' || lang.toLowerCase() === 'zxx') {
			found.push(`html lang "${lang}": not a usable language tag - a reader's tools cannot switch languages`);
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
		// An inline icon SVG is a picture the alt rule cannot see: unless it is
		// hidden from readers (aria-hidden, role=presentation), it must name
		// itself - an aria-label or a <title> child - or it announces nothing.
		for (const svg of document.querySelectorAll('svg')) {
			const hidden = svg.getAttribute('aria-hidden') === 'true' || svg.getAttribute('role') === 'presentation';
			const name = (svg.getAttribute('aria-label') || '').trim();
			const title = svg.querySelector(':scope > title');
			if (!hidden && !name && !(title && (title.textContent || '').trim())) {
				found.push('svg: no accessible name and not hidden from readers: ' + (svg.getAttribute('class') || ''));
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
// reader at 200% zoom has the layout of a 320px-wide screen, and a page that
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

// The last assistive preference the site promises: people who ask their browser
// for reduced motion get a page that never animates and never smooth-scrolls.
async function motionProblems(page: Page) {
	// The evaluate callback is plain JS: Playwright serializes it into the page.
	const problems = await page.evaluate(() => {
		const found = [];
		for (const el of document.body.querySelectorAll('*')) {
			const style = getComputedStyle(el);
			if (style.visibility === 'hidden' || style.display === 'none') continue;
			if (style.animationName !== 'none' && style.animationDuration !== '0s') {
				found.push(`${el.tagName}.${(el.getAttribute('class') || '')} still animates: ${style.animationName} ${style.animationDuration}`);
			}
			// Transitions whose property can MOVE content are motion too. Not a
			// blanket transitionDuration check: a color hover transition is not
			// motion, so only these properties are accused. `all` counts as
			// motion - a page that wants any transition anywhere is scoping
			// sloppily, and the honest fix is naming the property at the source.
			const propList = (style.transitionProperty || 'all').split(', ');
			const durList = (style.transitionDuration || '0s').split(', ');
			for (let k = 0; k < propList.length; k += 1) {
				const dur = durList.length === 1 ? durList[0] : durList[k];
				if (dur === undefined || dur === '0s') continue;
				const p0 = propList[k];
				if (p0 === 'all' || p0 === 'width' || p0 === 'height' || p0 === 'transform' || p0 === 'left' || p0 === 'right' || p0 === 'top' || p0 === 'bottom') {
					found.push(`${el.tagName}.${(el.getAttribute('class') || '')} glides on ${p0} (${dur}): a transition that can move content is motion a reduced-motion reader asked to drop`);
				}
			}
		}
		// Smooth scrolling is motion a reduced-motion reader asked to drop; the
		// skip-link jump relies on it being instant.
		const root = getComputedStyle(document.documentElement);
		if (root.scrollBehavior === 'smooth') {
			found.push('html: scroll-behavior is smooth, so a jump glides instead of landing');
		}
		return found;
	});
	return problems;
}

// WCAG 2.4.11: a keyboard reader must SEE where focus is. The walk presses
// real Tab keys so :focus-visible matches the way a keyboard reader's does,
// and every stop must paint a ring.
// How many stops the Tab walk should make: elements a keyboard can reach.
// Two Chromium behaviours decide, both learned from the walk disagreeing
// with the count rather than guessed: a hidden ancestor matters but
// Chromium does not inherit display:none into a child's computed style
// (walk ancestors for it), and a closed <details> hides its contents
// without any display:none at all - the browser skips them on Tab, so
// counting them would accuse a walk that is behaving correctly.
async function reachableFocusables(page: Page) {
	return await page.evaluate(() => {
		let count = 0;
		for (const el of document.body.querySelectorAll('a[href], button, summary, input:not([type="hidden"]), textarea, select, [tabindex]:not([tabindex="-1"])')) {
			// Chromium does not inherit display:none into a child's computed
			// style, so an ancestor's hiding must be walked for, not read off the
			// element: exactly this is what makes Tab skip the element.
			let hidden = false;
			for (let p: Element | null = el; p; p = p.parentElement) {
				const style = getComputedStyle(p);
				if (style.display === 'none' || style.visibility === 'hidden') {
					hidden = true;
					break;
				}
			}
			if (hidden) continue;
			// A closed <details> hides its contents without display:none at all,
			// and the browser skips them on Tab. The summary itself IS a stop
			// (closest('details') matches it too - excluding it here undercounted
			// the walk by one), so the skip is for contents only.
			const holder = el.closest('details');
			if (holder && !holder.hasAttribute('open') && el.tagName !== 'SUMMARY') continue;
			// Mark the stop so later walks can ask "same element?" by probe id
			// instead of by name or pixel coords (focus styles move elements -
			// the skip link lifts out of its hideaway slot on focus).
			el.setAttribute('data-e2e-stop', String(count));
			count += 1;
		}
		return count;
	});
}

async function focusRingProblems(page: Page) {
	const reachable = await reachableFocusables(page);
	const found = [];
	for (let i = 0; i < reachable; i += 1) {
		await page.keyboard.press('Tab');
		const stop = await page.evaluate(() => {
			const el = document.activeElement;
			if (!el || el === document.body || el === document.documentElement) {
				return { fell: true, name: '' };
			}
			const style = getComputedStyle(el);
			const width = parseFloat(style.outlineWidth || '0');
			const ringed = style.outlineStyle !== 'none' && width >= 2;
			const cls = el.getAttribute('class');
			const name = cls ? `${el.tagName}.${cls}` : (el.id ? `${el.tagName}#${el.id}` : el.tagName);
			return { fell: false, name, ringed, width };
		});
		if (stop.fell) {
			found.push(`tab stop ${i + 1}: the walk left the page, so a stop was skipped`);
		} else if (!stop.ringed) {
			found.push(`tab stop at ${stop.name} shows no ring: outline ${stop.width}px`);
		}
	}
	return found;
}

// The Tab walk must CLOSE: after visiting every stop and the browser's own
// hop off the page, focus returns to the first stop. Focus stuck anywhere
// else is a keyboard trap (WCAG 2.1.2) or a count that disagrees with the
// walk - the rule catches undercount, while fell-out caught overcount.
async function keyboardTrapProblems(page: Page) {
	const reachable = await reachableFocusables(page);
	const stops = [];
	for (let i = 0; i < reachable + 2; i += 1) {
		await page.keyboard.press('Tab');
		const stop = await page.evaluate(() => {
			const el = document.activeElement;
			if (!el || el === document.body || el === document.documentElement) return null;
			const cls = el.getAttribute('class');
			const name = cls ? `${el.tagName}.${cls}` : (el.id ? `${el.tagName}#${el.id}` : el.tagName);
			return { name, stop: el.getAttribute('data-e2e-stop') };
		});
		stops.push(stop);
	}
	const first = stops[0];
	const last = stops[stops.length - 1];
	if (!first) {
		return ['the first Tab press never reached a stop: nothing on the page is keyboard-reachable'];
	}
	if (!last) {
		return ['the walk ended off the page and never came back: a keyboard trap holds focus'];
	}
	if (last.stop === null || last.stop !== first.stop) {
		return [`the walk ended at ${last.name} instead of returning to ${first.name}: focus is trapped or a stop was missed`];
	}
	return [];
}

// WCAG 2.4.3 (second shape): Tab has to follow the VISUAL reading order, not
// just the source order. The site forbids positive tabindex (the first shape,
// below), so the walk is source order - which a CSS reorder (flex `order`,
// grid placement) would silently break: the reader Tabbing downward suddenly
// jumps up the page. Compare the rects of consecutive stops.
async function visualFocusOrderProblems(page: Page) {
	const reachable = await reachableFocusables(page);
	const stops = [];
	for (let i = 0; i < reachable; i += 1) {
		await page.keyboard.press('Tab');
		const stop = await page.evaluate(() => {
			const el = document.activeElement;
			if (!el || el === document.body || el === document.documentElement) return null;
			const r = el.getBoundingClientRect();
			if (r.height === 0 || r.width === 0) return null;
			return { top: Math.round(r.top), left: Math.round(r.left), height: Math.round(r.height), stop: el.getAttribute('data-e2e-stop') };
		});
		if (stop !== null) stops.push(stop);
	}
	const found = [];
	for (let i = 1; i < stops.length; i += 1) {
		const prev = stops[i - 1];
		const next = stops[i];
		if (prev === null || next === null) continue;
		// Same line: tops overlap within a line's height. Moving LEFT on a
		// line breaks reading order; a jump UP the page does too.
		const sameLine = Math.abs(next.top - prev.top) < Math.max(prev.height, next.height);
		if (sameLine) {
			if (next.left < prev.left) {
				found.push(`focus moved LEFT along a line at stop ${i + 1}: reading order is broken`);
			}
		} else if (next.top < prev.top) {
			found.push(`focus jumped UP the page at stop ${i + 1} (from ${prev.top}px to ${next.top}px): a CSS reorder puts a later element above an earlier one`);
		}
	}
	return found;
}

// WCAG 2.4.3: Tab follows reading order. A positive tabindex rewires the
// walk away from it - a trap no page of ours should ship.
async function positiveTabindexProblems(page: Page) {
	return await page.evaluate(() => {
		const found = [];
		for (const el of document.body.querySelectorAll('[tabindex]')) {
			const value = parseInt(el.getAttribute('tabindex') || '', 10);
			if (value > 0) found.push(`${el.tagName} carries tabindex ${value}: a positive value rewires the Tab walk away from reading order`);
		}
		return found;
	});
}

// WCAG's contrast promise, the last half of the accessibility bullet: text a
// reader can see but cannot tell from its background is unreadable for low
// vision, so every run of text is measured against the colors the page paints.
// WCAG 2.4.4 link purpose: a screen reader can pull the page's links into a
// list read one at a time, so two links that announce the same name have to
// lead the reader to the same place.
async function linkPurposeProblems(page: Page) {
	return await page.evaluate(() => {
		const byName = new Map();
		const resolve = document.createElement('a');
		for (const el of document.body.querySelectorAll('a[href]')) {
			const style = getComputedStyle(el);
			if (style.display === 'none' || style.visibility === 'hidden') continue;
			const name = (el.getAttribute('aria-label') || el.textContent || '').trim();
			if (!name) continue;
			// Compare RESOLVED destinations: the menu writes `#how-it-works` while
			// a card writes `/#how-it-works`; the attribute strings differ, the
			// place a reader lands does not.
			resolve.setAttribute('href', el.getAttribute('href') || '');
			const seen = byName.get(name);
			if (seen === undefined) {
				byName.set(name, [resolve.href]);
			} else {
				seen.push(resolve.href);
			}
		}
		const found = [];
		for (const entry of byName.entries()) {
			const [name, hrefs] = entry;
			const distinct = [];
			for (const href of hrefs) {
				if (distinct.indexOf(href) === -1) distinct.push(href);
			}
			if (distinct.length > 1) {
				found.push(`link "${name}" leads to ${distinct.length} places: ${distinct.join(' and ')} - a link list conflates them`);
			}
		}
		return found;
	});
}

// WCAG 2.4.2 document title: a screen reader announces the page title when
// the page loads, so an empty, duplicated or missing title leaves the reader
// without a page identity. Pages that carry no content at all (the client-side
// fallback without JS) are unjudged, same precedent as the other rules -
// there is nothing to announce, and the rule's target is documents with content.
async function documentTitleProblems(page: Page) {
	return await page.evaluate(() => {
		const found = [];
		const titles = document.head.querySelectorAll('title');
		const own = titles.length + document.body.querySelectorAll('title').length;
		if (own > 1) found.push(`the document carries ${own} title elements: only one is read, the page ships ambiguity`);
		const title = (document.title || '').trim();
		if (!title) found.push('the document has no non-empty <title>: a screen reader announces nothing at page load');
		return found;
	});
}

async function contrastProblems(page: Page) {
	const problems = await page.evaluate(() => {
		const found = [];
		const parse = (c = '') => {
			const m = /rgba?\(([^)]*)\)/.exec(c);
			if (!m) return null;
			const n = m[1].split(',').map((x) => Number(x.trim()));
			return { r: n[0], g: n[1], b: n[2], a: n.length === 4 ? n[3] / 255 : 1 };
		};
		const channel = (v = 0) => {
			const s = v / 255;
			return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
		};
		const luminance = (c = { r: 0, g: 0, b: 0, a: 1 }) =>
			0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
		const composite = (top = { r: 0, g: 0, b: 0, a: 1 }, under = { r: 0, g: 0, b: 0, a: 1 }) => ({
			r: top.r * top.a + under.r * (1 - top.a),
			g: top.g * top.a + under.g * (1 - top.a),
			b: top.b * top.a + under.b * (1 - top.a),
			a: 1
		});
		// The page paints its background; every element's own background-color
		// stacks on top of its ancestors', and the element's own is the one its
		// text sits on.
		const backgroundOf = (el: Element) => {
			let acc = { r: 255, g: 255, b: 255, a: 1 };
			const stack = [];
			for (let p: Element | null = el; p; p = p.parentElement) {
				const bg = parse(getComputedStyle(p).backgroundColor);
				if (bg && bg.a > 0) stack.push(bg);
			}
			for (let i = stack.length - 1; i >= 0; i -= 1) acc = composite(stack[i], acc);
			return acc;
		};
		const opacityOf = (el: Element) => {
			let alpha = 1;
			for (let p: Element | null = el; p; p = p.parentElement) {
				alpha *= Number(getComputedStyle(p).opacity);
			}
			return alpha;
		};
		for (const el of document.body.querySelectorAll('*')) {
			// Only the element's own text runs: text inside a child belongs to
			// that child, which is measured with its own color.
			let text = '';
			for (const node of el.childNodes) {
				if (node.nodeType === 3) text += node.textContent;
			}
			text = text.trim();
			if (!text) continue;
			const style = getComputedStyle(el);
			if (style.visibility === 'hidden' || style.display === 'none') continue;
			const size = parseFloat(style.fontSize || '');
			if (!size) continue;
			const weight = Number(style.fontWeight || 400);
			// WCAG's thresholds: large print (18.67px, or 14px bold) may sit at 3:1.
			const threshold = (size >= 18.67 || (size >= 14 && weight >= 700)) ? 3 : 4.5;
			const inkRaw = parse(style.color);
			if (!inkRaw) continue;
			const bg = backgroundOf(el);
			const ink = composite({ ...inkRaw, a: inkRaw.a * opacityOf(el) }, bg);
			const one = luminance(ink);
			const two = luminance(bg);
			const ratio = (Math.max(one, two) + 0.05) / (Math.min(one, two) + 0.05);
			if (ratio < threshold) {
				found.push(`${el.tagName}.${(el.getAttribute('class') || '')} text at ${ratio.toFixed(2)}:1 needs ${threshold}:1: ${text.slice(0, 40)}`);
			}
		}
		return found;
	});
	return problems;
}

const prerenderedPublicRoutes = ['/', '/transparency'];

for (const route of publicRoutes) {
	test(`${route} keeps its text at a readable contrast`, async ({ page }) => {
		await gotoHydrated(page, route);
		expect(await contrastProblems(page)).toEqual([]);
	});
}


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
		test(`${route} keeps its text at a readable contrast without JavaScript`, async ({ page }) => {
			await page.goto(route);
			await page.waitForLoadState('networkidle');
			expect(await contrastProblems(page)).toEqual([]);
		});
		test(`${route} keeps one name for one destination without JavaScript`, async ({ page }) => {
			await page.goto(route);
			await page.waitForLoadState('networkidle');
			expect(await linkPurposeProblems(page)).toEqual([]);
		});
		test(`${route} carries a document title before any script runs`, async ({ page }) => {
			await page.goto(route);
			await page.waitForLoadState('networkidle');
			expect(await documentTitleProblems(page)).toEqual([]);
		});
	}
});

// A reduced-motion context is a browser setting, so it belongs to the whole
// pass: the same rule list reads the page the reader's preference produced.

for (const route of publicRoutes) {
	test(`${route} paints a focus ring at every keyboard stop`, async ({ page }) => {
		await gotoHydrated(page, route);
		expect(await focusRingProblems(page)).toEqual([]);
	});
}

// The design ships a dark scheme too (tokens via prefers-color-scheme), so
// contrast - the one rule that depends on what the page paints - has to hold
// in both. The browser setting is Playwright's, not a class swap.
for (const route of publicRoutes) {
	test(`${route} carries a descriptive document title`, async ({ page }) => {
		await gotoHydrated(page, route);
		expect(await documentTitleProblems(page)).toEqual([]);
	});
}

for (const route of publicRoutes) {
	test(`${route} announces one destination per link name`, async ({ page }) => {
		await gotoHydrated(page, route);
		expect(await linkPurposeProblems(page)).toEqual([]);
	});
}

for (const route of publicRoutes) {
	test(`${route}: the Tab walk has no trap and no positive tabindex`, async ({ page }) => {
		await gotoHydrated(page, route);
		const trap = await keyboardTrapProblems(page);
		const order = await positiveTabindexProblems(page);
		const visual = await visualFocusOrderProblems(page);
		expect([...trap, ...order, ...visual]).toEqual([]);
	});
}

// WCAG 2.4.2 wants titles that tell the surfaces apart: a reader with several
// tabs open (or a bookmark list) cannot tell identical titles apart.
test('public surfaces carry distinct titles', async ({ page }) => {
	const titles = [];
	for (const route of publicRoutes) {
		await gotoHydrated(page, route);
		titles.push(page.title());
	}
	expect(new Set(titles).size).toBe(titles.length);
});

test.describe('in dark mode', () => {
	test.use({ colorScheme: 'dark' });
	for (const route of publicRoutes) {
		test(`${route} keeps its text readable in dark mode`, async ({ page }) => {
			await gotoHydrated(page, route);
			expect(await contrastProblems(page)).toEqual([]);
		});
	}
	for (const route of prerenderedPublicRoutes) {
		test(`${route} keeps its text readable in dark mode before any script runs`, async ({ page }) => {
			await page.goto(route);
			await page.waitForLoadState('networkidle');
			expect(await contrastProblems(page)).toEqual([]);
		});
	}
});

test.describe('with reduced motion', () => {
	test.use({ reducedMotion: 'reduce' });
	for (const route of publicRoutes) {
		test(`${route} never animates with reduced motion`, async ({ page }) => {
			await gotoHydrated(page, route);
			expect(await motionProblems(page)).toEqual([]);
		});
	}
	for (const route of prerenderedPublicRoutes) {
		test(`${route} never animates with reduced motion before any script runs`, async ({ page }) => {
			await page.goto(route);
			await page.waitForLoadState('networkidle');
			expect(await motionProblems(page)).toEqual([]);
		});
	}
});
