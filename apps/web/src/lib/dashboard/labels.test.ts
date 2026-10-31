import { describe, expect, it } from 'vitest';
import type { Database } from '../../../../backend/supabase/database.types.ts';
import {
	defaultPlanText,
	fundingLabel,
	loanStatusText,
	requestKindLabel,
	requestSortRank,
	requestStatusText
} from './labels.ts';

type Enums = Database['public']['Enums'];
const REQUEST_STATUSES: Enums['request_status'][] = [
	'draft', 'scoring', 'needs_evidence', 'in_review', 'open', 'funded', 'paid', 'refused', 'withdrawn', 'expired'
];
const LOAN_STATUSES: Enums['loan_status'][] = [
	'proposed', 'signed', 'active', 'paused', 'repaid', 'forgiven', 'defaulted', 'cancelled'
];
const KINDS: Enums['request_kind'][] = [
	'car_damage', 'car_deductible', 'home_repair', 'down_payment', 'mortgage_gap', 'loan_payoff'
];

/**
 * Copy the domain rules forbid on a member's screen: any interest, fee or
 * penalty that isn't stated as absent ("no interest", "zero interest").
 */
const charges = (text: string) =>
	/interest|late fee|penalt|credit score/i.test(text.replace(/\b(no|zero) (interest|late fees)\b/gi, ''));

describe('status copy', () => {
	it('labels every request status in words, with a hint', () => {
		for (const s of REQUEST_STATUSES) {
			const t = requestStatusText(s, 'car_damage', 'pool');
			expect(t.label.length).toBeGreaterThan(2);
			expect(t.hint.length).toBeGreaterThan(10);
			expect(charges(t.label + ' ' + t.hint)).toBe(false);
			expect(t.label).not.toMatch(/_/);
		}
	});

	it('never presents a low score or missing evidence as a refusal', () => {
		const t = requestStatusText('needs_evidence', 'home_repair', 'people');
		expect(t.label).not.toMatch(/refus|reject|denied|declin/i);
		expect(t.tone).toBe('action');
	});

	it('says a refusal was a person’s decision and can be appealed', () => {
		const t = requestStatusText('refused', 'car_damage', 'pool');
		expect(t.hint).toMatch(/person/);
		expect(t.hint).toMatch(/appeal/);
	});

	it('names the right pooled fund for the kind', () => {
		expect(requestStatusText('open', 'car_damage', 'pool').label).toBe('Waiting for the repair fund');
		expect(requestStatusText('open', 'down_payment', 'pool').label).toBe('Waiting for the Home Fund');
		expect(fundingLabel('both', 'home_repair')).toBe('Family, friends and the Home Fund');
		expect(fundingLabel('pool', 'car_deductible')).toBe('The repair fund');
	});

	it('pays the payee, never the member', () => {
		expect(requestStatusText('paid', 'car_damage', 'pool').label).toBe('Paid to the shop');
		expect(requestStatusText('paid', 'down_payment', 'people').label).toBe('Paid to the lender or seller');
	});

	it('labels every loan status, with no interest or fee language', () => {
		for (const s of LOAN_STATUSES) {
			const t = loanStatusText(s);
			expect(t.label.length).toBeGreaterThan(2);
			expect(charges(t.label + ' ' + t.hint)).toBe(false);
		}
		expect(loanStatusText('active').hint).toMatch(/no interest and no late fees/);
		expect(charges('a 5% late fee applies')).toBe(true);
	});

	it('labels every kind and default plan', () => {
		for (const k of KINDS) expect(requestKindLabel(k)).toMatch(/^[A-Z]/);
		expect(defaultPlanText('forgive')).toMatch(/forgives/);
		expect(defaultPlanText('repay_on_sale')).toMatch(/sold or refinanced/);
		expect(defaultPlanText('mediate')).toMatch(/mediator/);
	});
});

describe('requestSortRank', () => {
	it('orders needs-you, then in progress, then done, then closed', () => {
		expect(requestSortRank('draft')).toBeLessThan(requestSortRank('open'));
		expect(requestSortRank('open')).toBeLessThan(requestSortRank('paid'));
		expect(requestSortRank('paid')).toBeLessThan(requestSortRank('refused'));
	});
});
