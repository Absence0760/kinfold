import { expect, test, type Page } from '@playwright/test';
import { formatCents } from '../src/lib/dashboard/format.ts';
import { appealOutcome, reviewOutcome } from '../src/lib/review/queue.ts';
import { requests, signIn } from './helpers.ts';

// The Stage 1 money path, end to end, across three members:
//   1. james (NY reviewer) approves sam's needs-evidence request b5, which opens it;
//   2. sam invites a family member to it with a private link;
//   3. maria accepts the link and gives the whole amount, which fully pledges it;
//   4. sam sees it fully pledged, and that the money goes to the contractor, never to them.
// Then the appeal path on b6: priya (TX panel) denies maria's appeal and maria
// reads the decision. Each step needs the one before, so the file runs
// serially, on desktop only (it writes), against a freshly reset seed.

test.describe.configure({ mode: 'serial' });

const B5_CENTS = 120000;
const B5_TITLE = 'Burst pipe under the bathroom';
const PAYEE = 'Golden Gate Contracting (dev)';
let inviteUrl = '';

async function signOut(page: Page) {
	await page.getByRole('button', { name: 'Sign out' }).click();
	await expect(page).toHaveURL(/\/signin$/);
}

test('a reviewer outside the region approves a request, which opens it for help', async ({ page }) => {
	await signIn(page, 'james');
	await page.goto('/app/review');
	const card = page.getByRole('article', { name: `Home repair, ${formatCents(B5_CENTS)}` });
	await expect(card).toBeVisible();
	await card.getByRole('radio', { name: /^Approve/ }).check();
	await card.getByLabel('Reason').fill('The photo shows the burst pipe and the shop is verified; the quote can follow.');
	await card.getByRole('button', { name: /^Record decision/ }).click();
	await expect(page.locator('.confirmation')).toHaveText(reviewOutcome('approve', 'open'));
	// An open request has left the review queue.
	await expect(card).toHaveCount(0);
});

test('the requester makes a private invite link for a family member', async ({ page }) => {
	await signIn(page, 'sam');
	await page.goto(`/app/requests/${requests.b5}`);
	await expect(page.getByRole('heading', { level: 1, name: B5_TITLE })).toBeVisible();
	await expect(page.locator('.title-row')).toContainText('Open for help');
	await page.getByLabel('Who are you inviting?').selectOption('sister');
	await page.getByRole('button', { name: /^Make an invite link/ }).click();
	await expect(page.getByText('Your link for your sister is ready')).toBeVisible();
	inviteUrl = await page.getByLabel('Invite link').inputValue();
	expect(inviteUrl).toMatch(/^http:\/\/localhost:7791\/app\/invite\/[^/]+$/);
});

test('the invited member accepts and gives the whole amount, paid to the contractor', async ({ page }) => {
	expect(inviteUrl, 'the previous test made the link').not.toBe('');
	const amount = formatCents(B5_CENTS);
	await signIn(page, 'maria');
	await page.goto(inviteUrl);
	await expect(page.getByRole('heading', { level: 1, name: "You've been invited to help" })).toBeVisible();
	await page.getByRole('button', { name: 'Accept the invite' }).click();
	await expect(page.getByText('You’ve accepted the invite. Here’s the request.')).toBeVisible();

	const support = page.locator('article.support');
	await expect(support.getByRole('heading', { name: B5_TITLE })).toBeVisible();
	await expect(support).toContainText(PAYEE);
	await support.getByRole('radio', { name: /^Give\./ }).check();
	await support.getByRole('button', { name: `All that's left, ${amount}` }).click();
	await support.getByRole('button', { name: /^Review/ }).click();
	await expect(support.getByText(`Give ${amount}?`)).toBeVisible();
	await support.getByRole('button', { name: new RegExp(`^Pledge ${amount.replace('$', '\\$')}`) }).click();

	await expect(
		page.getByText(`Thank you. You pledged a gift of ${amount}. Nothing is collected until the whole request is pledged.`)
	).toBeVisible();
	await expect(support).toContainText(`A gift of ${amount}, waiting to be collected`);
});

test('the requester sees it fully pledged, with the money going to the contractor', async ({ page }) => {
	await signIn(page, 'sam');
	await page.goto(`/app/requests/${requests.b5}`);
	await expect(page.locator('.title-row')).toContainText('Fully pledged');
	await expect(page.locator('dl.facts')).toContainText(PAYEE);
	await signOut(page);
});

test('the appeal panel denies an appeal with a written reason', async ({ page }) => {
	await signIn(page, 'priya');
	await page.goto('/app/review');
	await expect(page.getByRole('heading', { name: 'Appeals' })).toBeVisible();
	const card = page.locator('article').filter({ has: page.getByRole('heading', { name: /^Appeal filed/ }) });
	await expect(card).toHaveCount(1);
	await card.getByRole('radio', { name: /^Deny the appeal/ }).check();
	await card.getByLabel('Reason').fill('The estimate covers a full rear panel; the photos the member sent show only a door scrape.');
	await card.getByRole('button', { name: /^Record decision/ }).click();
	await expect(page.locator('.confirmation')).toHaveText(appealOutcome(false));
	await expect(card).toHaveCount(0);
});

test('the member reads the panel’s decision on their own request', async ({ page }) => {
	await signIn(page, 'maria');
	await page.goto(`/app/requests/${requests.b6}`);
	await expect(page.getByRole('heading', { level: 1, name: 'Scraped in a parking garage' })).toBeVisible();
	await expect(page.locator('.title-row')).toContainText('Not approved');
	await expect(page.getByText('the photos the member sent show only a door scrape', { exact: false })).toBeVisible();
});
