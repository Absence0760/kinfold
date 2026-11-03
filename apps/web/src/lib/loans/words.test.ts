import { describe, expect, it } from 'vitest';
import { bankReliefNote, monthsWord, ordinal } from './words.ts';
import type { CertifiedCounsel } from '#lib/transparency/data.ts';

describe('words', () => {
	it('writes ordinals', () => {
		expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 28].map(ordinal)).toEqual([
			'1st',
			'2nd',
			'3rd',
			'4th',
			'11th',
			'12th',
			'13th',
			'21st',
			'22nd',
			'23rd',
			'28th'
		]);
	});

	it('writes months', () => {
		expect(monthsWord(1)).toBe('1 month');
		expect(monthsWord(3)).toBe('3 months');
	});
});

describe('bankReliefNote', () => {
	it('the certified agency is named with its credential and the 120-day note', () => {
		const counsel: CertifiedCounsel = {
			version: 1,
			agencyName: 'Pilot City Housing Counseling',
			contactUrl: 'https://pilotcity.example/housing-counseling',
			hudApprovedOn: '2026-01-01',
			certifiedUnder: '24 CFR part 214',
			effectiveFrom: '2026-01-01'
		};
		const note = bankReliefNote(counsel);
		expect(note).toContain('Pilot City Housing Counseling');
		expect(note).toContain('certified under 24 CFR part 214');
		expect(note).toContain('forbearance (a pause the bank agrees to)');
		expect(note).toContain('120 days');
		// Kinfold names a counselor rather than becoming one - the copy says so.
		expect(note).toContain('never becomes a counselor');
	});

	it('no certified agency in effect says so honestly, and keeps the early-bird note', () => {
		const note = bankReliefNote(null);
		expect(note).toContain('No certified agency is in effect yet');
		expect(note).toContain('120 days');
		// Nothing is named on behalf of a member who has no certified agency.
		expect(note.includes('Pilot City')).toBe(false);
	});
});
