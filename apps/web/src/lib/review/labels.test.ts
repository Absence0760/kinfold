import { describe, expect, it } from 'vitest';
import { Constants } from '../../../../backend/supabase/database.types';
import {
	auditWord,
	accountWord,
	fundWord,
	REVIEW_DECISIONS,
	decidedLabel,
	decisionLabel,
	evidenceLabel,
	formatCents,
	formatDay,
	isReviewable,
	kindLabel,
	redactionLabel,
	reviewAccess,
	statusLabel
} from './labels';

const E = Constants.public.Enums;

describe('reviewAccess', () => {
	it('reads the reviewer and panel roles', () => {
		expect(reviewAccess(['reviewer'])).toEqual({ reviewer: true, panel: false });
		expect(reviewAccess(['panel'])).toEqual({ reviewer: false, panel: true });
		expect(reviewAccess(['reviewer', 'panel'])).toEqual({ reviewer: true, panel: true });
		expect(reviewAccess(['admin'])).toEqual({ reviewer: false, panel: false });
		expect(reviewAccess([])).toEqual({ reviewer: false, panel: false });
	});
});

describe('REVIEW_DECISIONS', () => {
	it('offers every decision record_review accepts, once', () => {
		expect(REVIEW_DECISIONS.map((d) => d.value).sort()).toEqual([...E.review_decision].sort());
	});

	it('says refusing can be appealed', () => {
		expect(REVIEW_DECISIONS.find((d) => d.value === 'refuse')?.effect).toMatch(/appeal/);
	});

	it('labels each decision in both tenses', () => {
		for (const d of E.review_decision) {
			expect(decisionLabel(d)).not.toBe(d);
			expect(decidedLabel(d)).toBeTruthy();
		}
	});
});

describe('labels cover every enum value', () => {
	it.each([
		['request_status', E.request_status, statusLabel],
		['request_kind', E.request_kind, kindLabel],
		['evidence_kind', E.evidence_kind, evidenceLabel],
		['redaction_status', E.redaction_status, redactionLabel]
	] as const)('%s', (_name, values, label) => {
		for (const v of values) {
			const text = (label as (x: string) => string)(v);
			expect(text, v).toBeTruthy();
			expect(text, v).not.toBe(v);
		}
	});
});

describe('auditWord', () => {
	it('a known trail action reads in console words', () => {
		expect(auditWord('claim.denied')).toBe('A claim was denied');
		expect(auditWord('cover_choices.set')).toBe('A cover plan was chosen');
	});

	it('an action the words list does not know yet reads as its own name', () => {
		expect(auditWord('loan_paused.set')).toBe('loan paused set');
	});
});

describe('isReviewable', () => {
	it('matches the states record_review accepts', () => {
		const ok = E.request_status.filter(isReviewable);
		expect(ok.sort()).toEqual(['funded', 'in_review', 'needs_evidence', 'open']);
	});

	it('never lets a reviewer re-decide a refusal', () => {
		expect(isReviewable('refused')).toBe(false);
	});
});

describe('formatCents', () => {
	it('shows exact dollars and cents', () => {
		expect(formatCents(185000)).toBe('$1,850.00');
		expect(formatCents(72001)).toBe('$720.01');
		expect(formatCents(5)).toBe('$0.05');
	});
});

describe('formatDay', () => {
	it('keeps a calendar date on its day in any time zone', () => {
		expect(formatDay('2026-10-01')).toBe('Oct 1, 2026');
	});

	it('formats timestamps and tolerates missing or bad input', () => {
		expect(formatDay('2026-10-22T12:00:00Z')).toMatch(/Oct 2[12], 2026/);
		expect(formatDay(null)).toBe('');
		expect(formatDay('not a date')).toBe('');
	});
});

describe('accountWord', () => {
	it('names the fund-level accounts the ledger alerts can sit on', () => {
		expect(accountWord('available')).toBe('the pool\u2019s money');
		expect(accountWord('partner_cash')).toBe('money from the payment partner');
		expect(accountWord('reserve')).toBe('the reserve held back for the next run');
		expect(accountWord('committed')).toBe('money committed to funded requests');
		expect(accountWord('paid_out')).toBe('money paid out to payees');
		expect(accountWord('dues')).toBe('dues money');
		expect(accountWord('premiums')).toBe('premiums the cooperative has paid');
	});

	it('an unknown account reads as its own name', () => {
		expect(accountWord('some_new_account')).toBe('some new account');
	});
});

describe('fundWord', () => {
	it('names the funds a difference can be recorded against', () => {
		expect(fundWord('protection')).toBe('the repair fund');
		expect(fundWord('home_fund')).toBe('the Home Fund');
		expect(fundWord('people')).toBe('the people fund');
	});
});
