import { expect, test } from '@playwright/test';
import { navSections } from '../src/lib/landing/sections.ts';

// Desktop project only (see playwright.config.ts).

// Jump instantly (the site honours prefers-reduced-motion), so the scroll
// position is final as soon as the click lands.
test.use({ reducedMotion: 'reduce' });

for (const { id, label } of navSections) {
	test(`"${label}" link scrolls #${id} into view below the sticky header`, async ({ page }) => {
		await page.goto('/');
		const header = page.locator('header.nav');
		const heading = page.locator(`#${id} h2`);

		await page.getByRole('navigation', { name: 'Sections', exact: true }).getByRole('link', { name: label }).click();
		await expect(page).toHaveURL(new RegExp(`#${id}$`));
		await expect(heading).toBeInViewport();

		const geometry = await page.evaluate(
			({ id }) => {
				const header = document.querySelector('header.nav')!.getBoundingClientRect();
				const section = document.getElementById(id)!.getBoundingClientRect();
				const heading = document.querySelector(`#${id} h2`)!.getBoundingClientRect();
				const atBottom =
					Math.ceil(window.scrollY + window.innerHeight) >= document.documentElement.scrollHeight;
				return { headerBottom: header.bottom, sectionTop: section.top, headingTop: heading.top, atBottom };
			},
			{ id }
		);

		// The heading is never hidden under the header…
		expect(geometry.headingTop).toBeGreaterThanOrEqual(geometry.headerBottom);
		// …and the section lands right below it, unless the page ran out of room
		// to scroll. Scroll offsets are whole pixels while layout is fractional,
		// so "right below" means within a pixel, never a pixel or more under it.
		if (!geometry.atBottom) {
			expect(Math.abs(geometry.sectionTop - geometry.headerBottom)).toBeLessThan(1);
		}
		await expect(header).toBeInViewport();
	});
}
