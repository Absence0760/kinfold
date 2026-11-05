import { expect, test } from '@playwright/test';
import { DEMO_PASSWORD, people, signIn, type Person } from './helpers.ts';

// Getting in and out of the member area: the first thing every member does.
// Read-only (a sign-in changes no rows), so it runs on desktop and phone.

for (const who of Object.keys(people) as Person[]) {
	test(`${who} signs in with the form and lands on their own home`, async ({ page }) => {
		await signIn(page, who);
		await expect(page).toHaveTitle(/Kinfold/);
		await expect(page.getByRole('navigation', { name: 'Member area' })).toBeVisible();
	});
}

test('a wrong password is refused in plain words and stays on sign-in', async ({ page }) => {
	await page.goto('/signin');
	await page.getByLabel('Email').fill(people.maria.email);
	await page.getByLabel('Password').fill(DEMO_PASSWORD + '-wrong');
	await page.getByRole('button', { name: 'Sign in', exact: true }).click();
	await expect(page.getByRole('alert')).toHaveText(
		'That email and password don’t match an account. Check both and try again.'
	);
	await expect(page).toHaveURL(/\/signin$/);
	await expect(page.getByLabel('Password')).toHaveAttribute('aria-invalid', 'true');
});

test('a member page asked for while signed out is where sign-in returns them', async ({ page }) => {
	await page.goto('/app/loans');
	await expect(page).toHaveURL(/\/signin\?next=%2Fapp%2Floans$/);
	await signIn(page, 'maria', page.url());
	await expect(page).toHaveURL(/\/app\/loans$/);
	await expect(page.getByRole('heading', { level: 1, name: 'Your loans' })).toBeVisible();
});

test('signing out ends the session: the member area sends them back to sign-in', async ({ page }) => {
	await signIn(page, 'sam');
	await page.getByRole('button', { name: 'Sign out' }).click();
	await expect(page).toHaveURL(/\/signin$/);
	await page.goto('/app');
	await expect(page).toHaveURL(/\/signin$/);
	await expect(page.getByLabel('Email')).toBeVisible();
});

test('only reviewers are offered the review console', async ({ page }) => {
	const nav = page.getByRole('navigation', { name: 'Member area' });
	await signIn(page, 'sam');
	await expect(nav.getByRole('link', { name: 'Home' })).toBeVisible();
	await expect(nav.getByRole('link', { name: 'Review' })).toHaveCount(0);

	await page.getByRole('button', { name: 'Sign out' }).click();
	await expect(page).toHaveURL(/\/signin$/);
	await signIn(page, 'james');
	await nav.getByRole('link', { name: 'Review' }).click();
	await expect(page.getByRole('heading', { level: 1, name: 'Review' })).toBeVisible();
	await expect(page.getByRole('heading', { name: 'Review queue' })).toBeVisible();
});
