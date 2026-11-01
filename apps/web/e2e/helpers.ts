import { expect, type Page } from '@playwright/test';

/** Open a page and wait until the app has hydrated (`<html data-hydrated>`, set in the root layout). */
export async function gotoHydrated(page: Page, path: string): Promise<void> {
	await page.goto(path);
	await expect(page.locator('html')).toHaveAttribute('data-hydrated', 'true');
}
