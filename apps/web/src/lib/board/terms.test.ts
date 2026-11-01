import { describe, expect, it } from 'vitest';
import { define, TERMS, type Term } from './terms.ts';

const all = Object.keys(TERMS) as Term[];

describe('TERMS', () => {
	it('defines every term in a sentence or two that fits on a phone screen', () => {
		for (const t of all) {
			const { word, means } = TERMS[t];
			expect(word.length, t).toBeGreaterThan(0);
			expect(means.length, t).toBeGreaterThan(40);
			expect(means.length, t).toBeLessThanOrEqual(260);
			expect(means, t).toMatch(/\.$/);
			expect(define(t)).toBe(means);
		}
	});

	it('keeps the domain rules in the wording', () => {
		// Pay the payee, never the member.
		expect(define('payee')).toMatch(/never goes to the member/);
		// The app never holds member money; pools stay apart from family loans.
		expect(define('pool')).toMatch(/never Kinfold/);
		expect(define('pool')).toMatch(/apart from loans/);
		// The repair fund is gift-funded, never from dues, and pays by band.
		expect(define('repairFund')).toMatch(/never dues/);
		expect(define('repairFund')).toMatch(/band/);
		// The Home Fund lends without interest and its formula isn't live.
		expect(define('homeFund')).toMatch(/without interest/);
		expect(define('homeFund')).toMatch(/isn’t live yet/);
		// Originals stay private; lower bands wait rather than being refused.
		expect(define('redacted')).toMatch(/original stays private/i);
		expect(define('poolRun')).toMatch(/rather than being refused/);
	});

	it('never mentions interest charges or late fees as something that happens', () => {
		for (const t of all) {
			expect(define(t), t).not.toMatch(/late fee|interest rate|APR/i);
		}
	});
});
