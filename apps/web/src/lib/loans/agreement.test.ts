import { describe, expect, it } from 'vitest';
import {
	afterSigningText,
	lenderSignPoints,
	lentToText,
	planDetail,
	REPAY_ON_SALE_UNAVAILABLE,
	securityText
} from './agreement.ts';

describe('planDetail', () => {
	it('says forgive-the-rest gives up the whole remaining balance, as a gift', () => {
		const t = planDetail('forgive', false);
		expect(t).toMatch(/gives up the whole balance still owed/);
		expect(t).toMatch(/counts as the lender’s gift/);
	});

	it('explains why repay on sale is unavailable for an unsecured loan', () => {
		expect(planDetail('repay_on_sale', false)).toBe(REPAY_ON_SALE_UNAVAILABLE);
		expect(REPAY_ON_SALE_UNAVAILABLE).toMatch(/unsecured/);
		expect(planDetail('repay_on_sale', true)).toMatch(/lien stays on the home/);
	});

	it('describes mediation', () => {
		expect(planDetail('mediate', false)).toMatch(/neutral mediator/);
	});
});

describe('securityText', () => {
	it('always says something, and an unsecured loan says there is no lien', () => {
		expect(securityText({ secured: false, lien_recorded_at: null })).toMatch(/^Unsecured: there’s no lien on any property\./);
	});

	it('words a secured loan by whether the lien is recorded', () => {
		expect(securityText({ secured: true, lien_recorded_at: null })).toMatch(/not recorded with the county yet/);
		expect(securityText({ secured: true, lien_recorded_at: '2026-03-04T00:00:00Z' })).toMatch(/recorded with the county on/);
	});
});

describe('lenderSignPoints', () => {
	const points = lenderSignPoints({ principal_cents: 3_000_000, request_id: 'r1' });

	it('says the partner collects the amount once every loan on the request is signed', () => {
		expect(points[0]).toMatch(/collect \$30,000 from you once the whole request is pledged and every loan on it is signed/);
	});

	it('says it can’t be cancelled, could be lost, and Kinfold doesn’t guarantee repayment', () => {
		expect(points.join(' ')).toMatch(/can’t cancel it/);
		expect(points.join(' ')).toMatch(/could lose some or all/);
		expect(points.join(' ')).toMatch(/doesn’t guarantee/);
	});

	it('handles a loan with no request', () => {
		expect(lenderSignPoints({ principal_cents: 100, request_id: null })[0]).toBe(
			'Signing lets the payment partner collect $1 from you.'
		);
	});
});

describe('afterSigningText', () => {
	it('names only what exists, never a new agreement', () => {
		const t = afterSigningText(3);
		expect(t).not.toMatch(/new agreement/);
		expect(t).toMatch(/pauses/);
		expect(t).toMatch(/forgive/);
		expect(afterSigningText(0)).not.toMatch(/pauses/);
	});
});

describe('lentToText', () => {
	it('uses the lender’s own invite label, or nothing', () => {
		expect(lentToText('aunt or uncle')).toBe(' to the member who invited you as their aunt or uncle');
		expect(lentToText(null)).toBe('');
	});
});
