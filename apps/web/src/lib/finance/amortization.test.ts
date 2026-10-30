import { describe, expect, it } from 'vitest';
import { compareSavings, monthlyPayment, totalInterest } from './amortization';

describe('monthlyPayment', () => {
	it('matches the standard 30-year example in docs/design.md', () => {
		// $400,000 at 6.5% over 30 years ≈ $2,528/month.
		expect(monthlyPayment(400_000, 6.5, 30)).toBeCloseTo(2528.27, 1);
	});

	it('repays principal evenly at 0%', () => {
		expect(monthlyPayment(36_000, 0, 3)).toBe(1000);
	});

	it('is zero for no principal or no term', () => {
		expect(monthlyPayment(0, 6.5, 30)).toBe(0);
		expect(monthlyPayment(100_000, 6.5, 0)).toBe(0);
	});
});

describe('totalInterest', () => {
	it('is roughly $510k on the design example', () => {
		expect(totalInterest(400_000, 6.5, 30)).toBeCloseTo(510_177, -1);
	});

	it('is zero at 0%', () => {
		expect(totalInterest(50_000, 0, 10)).toBeCloseTo(0, 6);
	});
});

describe('compareSavings', () => {
	it('saves the interest on the zero-interest share', () => {
		const r = compareSavings({ loanAmount: 400_000, annualRatePct: 6.5, years: 30, zeroInterestAmount: 30_000 });
		expect(r.withKinfold.bankPrincipal).toBe(370_000);
		expect(r.interestSaved).toBeCloseTo(totalInterest(30_000, 6.5, 30), 6);
		expect(r.interestSaved).toBeGreaterThan(0);
	});

	it('never charges interest on the family share', () => {
		const r = compareSavings({ loanAmount: 100_000, annualRatePct: 7, years: 15, zeroInterestAmount: 100_000 });
		expect(r.withKinfold.interest).toBe(0);
		expect(r.withKinfold.monthly).toBeCloseTo(100_000 / 180, 6);
	});

	it('clamps a zero-interest share larger than the loan', () => {
		const r = compareSavings({ loanAmount: 50_000, annualRatePct: 6, years: 10, zeroInterestAmount: 80_000 });
		expect(r.withKinfold.bankPrincipal).toBe(0);
		expect(r.interestSaved).toBeCloseTo(r.bankOnly.interest, 6);
	});

	it('treats a negative share as none', () => {
		const r = compareSavings({ loanAmount: 50_000, annualRatePct: 6, years: 10, zeroInterestAmount: -5 });
		expect(r.interestSaved).toBe(0);
	});
});
