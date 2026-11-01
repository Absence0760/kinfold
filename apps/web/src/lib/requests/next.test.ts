import { describe, expect, it } from 'vitest';
import { Constants } from '../../../../backend/supabase/database.types.ts';
import {
	appealState,
	canChangeEvidence,
	canConfirmSummary,
	canEdit,
	canWithdraw,
	reviewerAsk,
	submitBlockerList,
	submitBlockers,
	whatHappensNext,
	type RequestState
} from './next';

const draft: RequestState = {
	status: 'draft',
	kind: 'home_repair',
	funding: 'people',
	hasPayee: false,
	evidence: [{ redaction_status: 'pending' }],
	publicSummary: null,
	summaryConfirmed: false,
	appeals: [],
	refusals: 0
};

describe('what the member can do, by status', () => {
	it('edits only drafts (the "members edit drafts" policy)', () => {
		for (const status of Constants.public.Enums.request_status) {
			expect(canEdit({ status }), status).toBe(status === 'draft');
		}
	});

	it('changes evidence until scoring (the evidence policies)', () => {
		for (const status of Constants.public.Enums.request_status) {
			expect(canChangeEvidence({ status }), status).toBe(status === 'draft' || status === 'needs_evidence');
		}
	});

	it('withdraws where withdraw_request allows', () => {
		for (const status of Constants.public.Enums.request_status) {
			expect(canWithdraw({ status }), status).toBe(['draft', 'needs_evidence', 'open'].includes(status));
		}
	});
});

describe('submitBlockers (mirrors submit_request)', () => {
	it('lists a missing payee, and says evidence waiting for redaction is Kinfold’s step', () => {
		const out = submitBlockerList(draft);
		expect(out).toHaveLength(2);
		expect(out[0]).toEqual({ who: 'member', text: expect.stringMatching(/the contractor/) });
		expect(out[1].who).toBe('kinfold');
		expect(out[1].text).toMatch(/^Waiting on Kinfold, not you/);
		expect(out[1].text).toMatch(/1 piece of evidence/);
		expect(out[1].text).toMatch(/isn’t switched on yet/);
		expect(out[1].text).toMatch(/nothing for you to do on it/);
		expect(out[1].text).not.toMatch(/by you/);
	});

	it('words each evidence state as its own step, member steps before Kinfold’s', () => {
		const out = submitBlockerList({
			...draft,
			hasPayee: true,
			evidence: [
				{ redaction_status: 'pending' },
				{ redaction_status: 'pending' },
				{ redaction_status: 'auto_done' },
				{ redaction_status: 'rejected' },
				{ redaction_status: 'confirmed' },
				{ redaction_status: 'pending', stored: false }
			]
		});
		expect(out.map((b) => b.who)).toEqual(['member', 'member', 'member', 'kinfold']);
		expect(out[0].text).toMatch(/Remove the upload that didn’t finish/);
		expect(out[1].text).toMatch(/Remove 1 piece .* wasn’t usable/);
		expect(out[2].text).toMatch(/Check the redacted copy of 1 piece/);
		// The unfinished upload isn't counted as waiting for Kinfold.
		expect(out[3].text).toMatch(/2 pieces of evidence/);
		expect(out[3].text).toMatch(/on them for now/);
	});

	it('counts several unfinished uploads', () => {
		const out = submitBlockers({
			...draft,
			hasPayee: true,
			evidence: [
				{ redaction_status: 'pending', stored: false },
				{ redaction_status: 'pending', stored: false }
			]
		});
		expect(out).toEqual(['Remove the 2 uploads that didn’t finish, then add those files again.']);
	});

	it('asks for evidence when there is none', () => {
		expect(submitBlockers({ ...draft, hasPayee: true, evidence: [] })).toEqual(['Add at least one piece of evidence.']);
	});

	it('is empty when ready, and after it has been sent', () => {
		const ready = { ...draft, hasPayee: true, evidence: [{ redaction_status: 'confirmed' as const }] };
		expect(submitBlockers(ready)).toEqual([]);
		expect(submitBlockers({ ...draft, status: 'open' })).toEqual([]);
	});
});

describe('appealState (one appeal per refusal, as file_appeal counts)', () => {
	const refused = { status: 'refused' as const, appeals: [], refusals: 1 };

	it('allows one appeal per refusal', () => {
		expect(appealState(refused)).toBe('can_appeal');
		expect(appealState({ ...refused, appeals: [{ status: 'open' }] })).toBe('appeal_open');
		expect(appealState({ ...refused, appeals: [{ status: 'denied' }] })).toBe('appeal_used');
	});

	it('allows a new appeal after an upheld appeal leads to a second refusal', () => {
		expect(appealState({ ...refused, appeals: [{ status: 'upheld' }], refusals: 2 })).toBe('can_appeal');
	});

	it('is not offered unless refused', () => {
		expect(appealState({ ...refused, status: 'in_review' })).toBe('not_refused');
	});
});

describe('canConfirmSummary', () => {
	it('asks only where the request goes on the board, and only once per summary', () => {
		const s = { funding: 'pool' as const, publicSummary: 'Roof leak after a storm.', summaryConfirmed: false };
		expect(canConfirmSummary(s)).toBe(true);
		expect(canConfirmSummary({ ...s, funding: 'both' })).toBe(true);
		expect(canConfirmSummary({ ...s, funding: 'people' })).toBe(false);
		expect(canConfirmSummary({ ...s, summaryConfirmed: true })).toBe(false);
		expect(canConfirmSummary({ ...s, publicSummary: null })).toBe(false);
	});
});

describe('whatHappensNext', () => {
	it('says something for every status', () => {
		for (const status of Constants.public.Enums.request_status) {
			const n = whatHappensNext({ ...draft, status });
			expect(n.now, status).not.toBe('');
			expect(n.steps.length, status).toBeGreaterThan(0);
		}
	});

	it('leads a draft with what still stops it', () => {
		const n = whatHappensNext(draft);
		// Invited supporters can read the request row, drafts included (the
		// "supporters read requests they back" policy), so the copy says so.
		expect(n.now).toMatch(/Only you, and family or friends you invite/);
		expect(n.now).not.toMatch(/Nobody else/);
		expect(n.steps[0]).toMatch(/Choose who should be paid/);
	});

	it('says a ready draft is ready', () => {
		const n = whatHappensNext({ ...draft, hasPayee: true, evidence: [{ redaction_status: 'confirmed' }] });
		expect(n.steps[0]).toMatch(/ready/);
	});

	it('never calls needing evidence a refusal', () => {
		expect(whatHappensNext({ ...draft, status: 'needs_evidence' }).now).toMatch(/Nothing has been refused/);
	});

	it('says whose turn it is when more evidence is needed: the member’s, then a reviewer’s', () => {
		const n = whatHappensNext({ ...draft, status: 'needs_evidence', hasPayee: true, evidence: [] });
		expect(n.now).toMatch(/^Your move: add evidence/);
		expect(n.steps[1]).toMatch(/press Submit again/);
		expect(n.steps.at(-1)).toMatch(/trained member reviewer looks at it/);
		expect(n.steps.at(-1)).toMatch(/never refuses/);
	});

	it('says a person refused, and how the appeal stands', () => {
		const base = { ...draft, status: 'refused' as const, refusals: 1 };
		expect(whatHappensNext(base).now).toMatch(/A person declined/);
		expect(whatHappensNext(base).steps[0]).toMatch(/appeal once/);
		expect(whatHappensNext({ ...base, appeals: [{ status: 'open' }] }).steps[0]).toMatch(/with the member panel/);
	});

	it('says money goes to the payee, not the member', () => {
		const n = whatHappensNext({ ...draft, kind: 'car_damage', status: 'funded' });
		expect(n.steps.join(' ')).toMatch(/straight to the shop/);
		expect(n.steps.join(' ')).toMatch(/never to you/);
	});

	it('asks to confirm the summary before an open pool request reaches the board', () => {
		const open = { ...draft, status: 'open' as const, funding: 'pool' as const };
		expect(whatHappensNext(open).steps.join(' ')).toMatch(/Confirm the public summary/);
		expect(whatHappensNext({ ...open, summaryConfirmed: true }).steps.join(' ')).toMatch(/on the members-only board/);
		expect(whatHappensNext({ ...open, funding: 'people' }).steps.join(' ')).toMatch(/Invite family and friends/);
	});
});

describe('reviewerAsk', () => {
	const at = (d: string) => `2026-10-${d}T12:00:00Z`;

	it('is the latest note when the latest decision asked for evidence', () => {
		expect(
			reviewerAsk([
				{ decision: 'escalate', reason: 'Second opinion.', created_at: at('01') },
				{ decision: 'needs_evidence', reason: 'Add the shop’s estimate.', created_at: at('03') }
			])
		).toBe('Add the shop’s estimate.');
	});

	it('is null when a later decision replaced it, or there are no reviews', () => {
		expect(
			reviewerAsk([
				{ decision: 'needs_evidence', reason: 'Add the estimate.', created_at: at('01') },
				{ decision: 'approve', reason: 'Estimate matches.', created_at: at('04') }
			])
		).toBe(null);
		expect(reviewerAsk([])).toBe(null);
	});
});
