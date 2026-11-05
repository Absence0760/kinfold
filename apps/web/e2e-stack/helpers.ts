import { expect, type Page } from '@playwright/test';

// The seeded demo people (apps/backend/supabase/seed.sql). The shared dev
// password grants access to nothing outside a throwaway local container, which
// is why the seed and the sign-in page's demo list both commit it.
export const people = {
	maria: { email: 'maria@test.com', name: 'Maria' }, // CA member: draft b1, funded b3 with sam's loan, refused b6 under appeal
	sam: { email: 'sam@test.com', name: 'Sam' }, // CA member: maria's brother and lender; b2 on the board, b5 needing evidence
	james: { email: 'james@test.com', name: 'James' }, // NY reviewer: may review the CA requests
	priya: { email: 'priya@test.com', name: 'Priya' } // TX appeal panel: paid b4
} as const;
export type Person = keyof typeof people;
export const DEMO_PASSWORD = 'testtest';

/** Seeded request ids (seed.sql "requests"). */
export const requests = {
	b1: '00000000-0000-0000-0000-0000000000b1',
	b3: '00000000-0000-0000-0000-0000000000b3',
	b5: '00000000-0000-0000-0000-0000000000b5',
	b6: '00000000-0000-0000-0000-0000000000b6'
} as const;

/** Sign in through the real form, and wait for the member home to greet them. */
export async function signIn(page: Page, who: Person, path = '/signin'): Promise<void> {
	await page.goto(path);
	await page.getByLabel('Email').fill(people[who].email);
	await page.getByLabel('Password').fill(DEMO_PASSWORD);
	await page.getByRole('button', { name: 'Sign in', exact: true }).click();
	if (path === '/signin') {
		await expect(page).toHaveURL(/\/app$/);
		await expect(page.getByRole('heading', { level: 1, name: `Hello, ${people[who].name}` })).toBeVisible();
	}
}
