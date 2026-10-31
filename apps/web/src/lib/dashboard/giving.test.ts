import { describe, expect, it } from 'vitest';
import { givingSummary } from './giving.ts';

const record = {
	subscriptions_paid_cents: 18600,
	gifts_given_cents: 2500,
	lent_cents: 0,
	received_from_pool_cents: 72000,
	received_from_people_cents: 0,
	requests_paid: 1
};

describe('givingSummary', () => {
	it('totals each side separately', () => {
		const s = givingSummary(record, []);
		expect(s.givenCents).toBe(21100);
		expect(s.receivedCents).toBe(72000);
		expect(s.empty).toBe(false);
	});

	it('carries no net figure, ratio or rank', () => {
		const keys = Object.keys(givingSummary(record, [])).sort();
		expect(keys).toEqual(
			['empty', 'given', 'givenCents', 'pledgedGiftCents', 'pledgedLoanCents', 'received', 'receivedCents'].sort()
		);
	});

	it('shows the member’s own pledges that haven’t been collected yet', () => {
		const s = givingSummary(
			{ ...record, subscriptions_paid_cents: 0, gifts_given_cents: 0, received_from_pool_cents: 0 },
			[
				{ source: 'gift', amount_cents: 30000, status: 'pledged' },
				{ source: 'loan', amount_cents: 70000, status: 'pledged' },
				{ source: 'gift', amount_cents: 999, status: 'captured' }, // already in gifts_given_cents
				{ source: 'gift', amount_cents: 500, status: 'released' }
			]
		);
		expect(s.pledgedGiftCents).toBe(30000);
		expect(s.pledgedLoanCents).toBe(70000);
		expect(s.empty).toBe(false);
	});

	it('is empty when there is nothing on either side', () => {
		expect(givingSummary(null, []).empty).toBe(true);
	});
});
