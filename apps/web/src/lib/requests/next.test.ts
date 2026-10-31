import { describe, expect, it } from 'vitest';
import { Constants } from '../../../../backend/supabase/database.types.ts';
import {
	appealState,
	canChangeEvidence,
	canConfirmSummary,
	canEdit,
	canWithdraw,
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
	it('lists a missing payee and unconfirmed redactions', () => {
		const out = submitBlockers(draft);
		expect(out).toHaveLength(2);
		expect(out[0]).toMatch(/the contractor/);
		expect(out[1]).toMatch(/confirmed by you/);
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
		expect(n.now).toMatch(/Nobody else can see it/);
		expect(n.steps[0]).toMatch(/Choose who should be paid/);
	});

	it('says a ready draft is ready', () => {
		const n = whatHappensNext({ ...draft, hasPayee: true, evidence: [{ redaction_status: 'confirmed' }] });
		expect(n.steps[0]).toMatch(/ready/);
	});

	it('never calls needing evidence a refusal', () => {
		expect(whatHappensNext({ ...draft, status: 'needs_evidence' }).now).toMatch(/Nothing has been refused/);
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
