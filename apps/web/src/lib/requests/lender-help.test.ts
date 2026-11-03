import { describe, expect, it } from 'vitest';
import { Constants } from '../../../../backend/supabase/database.types.ts';
import { fairLenderHeading, fairLenderLines, type FairLenderLine } from './lender-help.ts';
import { type RequestKind } from '#lib/dashboard/labels.ts';

describe('fairLenderLines', () => {
	it('only the mortgage kinds get pointers, and car and home kinds get nothing', () => {
		for (const kind of Constants.public.Enums.request_kind) {
			const lines = fairLenderLines(kind);
			if (kind === 'mortgage_gap' || kind === 'down_payment') {
				expect(lines).toHaveLength(3);
				expect(lines.every((l: FairLenderLine) => l.title !== '' && l.body !== '')).toBe(true);
			} else {
				expect(lines).toEqual([]);
			}
		}
	});

	it('the copy never prices the introduction to a lender', () => {
		// RESPA section 8 bans referral fees outright, so no line may hand over an
		// amount, a percentage, or a fee the member would pay for the pointing.
		for (const kind of ['mortgage_gap', 'down_payment'] as RequestKind[]) {
			for (const l of fairLenderLines(kind)) {
				const text = `${l.title} ${l.body}`;
				expect(text).not.toMatch(/\d+(%|\s*(dollars|USD))/);
				expect(text).not.toMatch(/you pay/);
				expect(text).not.toMatch(/we charge/i);
			}
			const feeLine = fairLenderLines(kind)[1];
			expect(feeLine.title).toContain('costs you a fee');
			expect(feeLine.body).toContain('no referral fees');
			expect(feeLine.body).toContain('does not undo the ban');
			expect(feeLine.body).toContain('it prices nothing');
		}
	});

	it('the pointers name the lender of record and say Kinfold is not one', () => {
		const [first, , third] = fairLenderLines('mortgage_gap');
		expect(first.body).toContain('lender of record');
		expect(first.body).toContain('never becomes anyone\u2019s lender of record');
		expect(first.body).not.toContain('we will introduce');
		expect(third.body).toContain('counted before you ask');
		expect(fairLenderHeading).toBe('A fair lender for the mortgage');
	});
});
