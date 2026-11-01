import { expect, test, type Page } from '@playwright/test';
import { navSections } from '../src/lib/landing/sections.ts';
import { gotoHydrated } from './helpers.ts';

// Phone project only (see playwright.config.ts).

test.use({ reducedMotion: 'reduce' });

const desktopLinks = (page: Page) => page.getByRole('navigation', { name: 'Sections', exact: true });
const menuLinks = (page: Page) => page.getByRole('navigation', { name: 'Sections, menu' });

test('the section links collapse into a menu that closes after a pick', async ({ page }) => {
	await gotoHydrated(page, '/');
	const summary = page.getByLabel('Menu', { exact: true });
	const details = page.locator('details.menu');

	await expect(desktopLinks(page)).toBeHidden();
	await expect(summary).toBeVisible();
	await expect(menuLinks(page)).toBeHidden();

	await summary.click();
	await expect(details).toHaveAttribute('open', '');
	const links = menuLinks(page).getByRole('link');
	await expect(links).toHaveText(navSections.map((s) => s.label));
	for (const link of await links.all()) await expect(link).toBeVisible();

	const target = navSections[3];
	await menuLinks(page).getByRole('link', { name: target.label }).click();
	await expect(page).toHaveURL(new RegExp(`#${target.id}$`));
	await expect(details).not.toHaveAttribute('open');
	await expect(menuLinks(page)).toBeHidden();
	await expect(page.locator(`#${target.id} h2`)).toBeInViewport();
});

test('Escape closes the menu and returns focus to its button', async ({ page }) => {
	await gotoHydrated(page, '/');
	const summary = page.getByLabel('Menu', { exact: true });
	const details = page.locator('details.menu');

	await summary.click();
	await expect(details).toHaveAttribute('open', '');
	await menuLinks(page).getByRole('link').first().focus();
	await page.keyboard.press('Escape');
	await expect(details).not.toHaveAttribute('open');
	await expect(summary).toBeFocused();
});

test('tabbing out of the open menu closes it', async ({ page }) => {
	await gotoHydrated(page, '/');
	const details = page.locator('details.menu');

	await page.getByLabel('Menu', { exact: true }).click();
	await expect(details).toHaveAttribute('open', '');
	await menuLinks(page).getByRole('link').last().focus();
	await page.keyboard.press('Tab');
	await expect(details).not.toHaveAttribute('open');
});

test.describe('without JavaScript', () => {
	test.use({ javaScriptEnabled: false });

	test('the menu still opens (it is a <details>)', async ({ page }) => {
		await page.goto('/');
		await expect(page.locator('html')).not.toHaveAttribute('data-hydrated');
		await expect(desktopLinks(page)).toBeHidden();

		await page.getByLabel('Menu', { exact: true }).click();
		await expect(page.locator('details.menu')).toHaveAttribute('open', '');
		await expect(menuLinks(page).getByRole('link')).toHaveText(navSections.map((s) => s.label));

		const target = navSections[0];
		await menuLinks(page).getByRole('link', { name: target.label }).click();
		await expect(page).toHaveURL(new RegExp(`#${target.id}$`));
	});
});
