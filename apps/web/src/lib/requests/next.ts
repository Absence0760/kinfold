import { payeeWord, poolName, poolRule, type FundingMode, type RequestKind, type RequestStatus } from '#lib/dashboard/labels.ts';
import type { Database } from '../../../../backend/supabase/database.types.ts';
import type { RedactionStatus } from './evidence.ts';
import { usesPool } from './eligibility.ts';

export type AppealStatus = Database['public']['Enums']['appeal_status'];

/** What the detail page knows about one of the member's own requests. */
export interface RequestState {
	status: RequestStatus;
	kind: RequestKind;
	funding: FundingMode;
	hasPayee: boolean;
	evidence: readonly { redaction_status: RedactionStatus }[];
	publicSummary: string | null;
	summaryConfirmed: boolean;
	/** The member's appeals on this request, oldest first. */
	appeals: readonly { status: AppealStatus }[];
	/** How many times it has moved into `refused` (from request_events). */
	refusals: number;
}

export const canEdit = (s: Pick<RequestState, 'status'>): boolean => s.status === 'draft';

/** Evidence can be added or removed until it is scored (the evidence policies). */
export const canChangeEvidence = (s: Pick<RequestState, 'status'>): boolean =>
	s.status === 'draft' || s.status === 'needs_evidence';

export const canWithdraw = (s: Pick<RequestState, 'status'>): boolean =>
	s.status === 'draft' || s.status === 'needs_evidence' || s.status === 'open';

/**
 * What still stops `submit_request`, in its order, leaving out the pool
 * checks (see `poolProblems`). Empty when it can be sent.
 */
export function submitBlockers(s: RequestState): string[] {
	if (!canChangeEvidence(s)) return [];
	const out: string[] = [];
	if (!s.hasPayee) out.push(`Choose who should be paid: ${payeeWord(s.kind)}. The money goes to them, never to you.`);
	if (s.evidence.length === 0) out.push('Add at least one piece of evidence.');
	else if (s.evidence.some((e) => e.redaction_status !== 'confirmed'))
		out.push('Every piece of evidence needs its redacted copy checked and confirmed by you.');
	return out;
}

/**
 * Where the request's appeal stands. One appeal per refusal: a request
 * refused, appealed, upheld and refused again can be appealed again
 * (mirrors `file_appeal`, which counts appeals against refusals).
 */
export type AppealState = 'not_refused' | 'can_appeal' | 'appeal_open' | 'appeal_used';

export function appealState(s: Pick<RequestState, 'status' | 'appeals' | 'refusals'>): AppealState {
	if (s.status !== 'refused') return 'not_refused';
	if (s.appeals.some((a) => a.status === 'open')) return 'appeal_open';
	return s.appeals.length < s.refusals ? 'can_appeal' : 'appeal_used';
}

/** The public summary only matters where the request goes on the members-only board. */
export const canConfirmSummary = (s: Pick<RequestState, 'funding' | 'publicSummary' | 'summaryConfirmed'>): boolean =>
	usesPool(s.funding) && s.publicSummary != null && !s.summaryConfirmed;

export interface NextStep {
	/** One line: where it is now. */
	now: string;
	/** What happens next, in order. */
	steps: string[];
}

/** The request's status as "where it is, and what happens next". */
export function whatHappensNext(s: RequestState): NextStep {
	const payee = payeeWord(s.kind);
	const pool = poolName(s.kind);
	const funders =
		s.funding === 'people' ? 'family and friends you invite' : s.funding === 'pool' ? pool : `your people and ${pool}`;

	switch (s.status) {
		case 'draft': {
			const blockers = submitBlockers(s);
			return {
				now: 'This is a draft. Nobody else can see it yet.',
				steps: [
					...(blockers.length ? blockers : ['Everything’s ready. Submit it when you are.']),
					'When you submit, your evidence is read and given a legitimacy score, usually within minutes.',
					`A good score opens it for help from ${funders}. A low one asks for more evidence; it never refuses.`
				]
			};
		}
		case 'scoring':
			return {
				now: 'Your evidence is being read and scored.',
				steps: [
					'This usually takes minutes. The score and its reasons will show here.',
					`A good score opens it for help from ${funders}. A low score asks you for more evidence, and a person looks at it.`
				]
			};
		case 'needs_evidence':
			return {
				now: 'Nothing has been refused. The evidence so far doesn’t back the request strongly enough yet.',
				steps: [
					'Read the reasons under the score: they say what’s missing.',
					'Add the missing evidence, check its redacted copy, then submit again.',
					...submitBlockers(s)
				]
			};
		case 'in_review':
			return {
				now: 'A trained member reviewer is looking at it.',
				steps: [
					'They’re from another state, never yours, and they write down the reason for their decision.',
					'They can approve it, ask for more evidence, or, only as a person, decline it. You can appeal a refusal.'
				]
			};
		case 'open':
			return {
				now: `It’s open for help from ${funders}.`,
				steps: [
					...(s.funding !== 'pool'
						? ['Invite family and friends to give or lend at zero interest. Only people you invite can lend.']
						: []),
					...(usesPool(s.funding)
						? [
								s.summaryConfirmed
									? `It’s on the members-only board, and ${pool} ${poolRule(s.kind)} at its next run.`
									: 'Confirm the public summary below so it can go on the members-only board.'
							]
						: []),
					`Once it’s fully pledged, the money is collected and paid straight to ${payee}.`
				]
			};
		case 'funded':
			return {
				now: 'It’s fully pledged.',
				steps: [
					'The payment partner collects the pledges. Kinfold never holds the money.',
					`It’s paid straight to ${payee} against their final invoice, never to you.`
				]
			};
		case 'paid':
			return { now: `Done. The money was paid to ${payee}.`, steps: ['Any family loans now repay monthly, with no interest and no late fees.'] };
		case 'refused': {
			const appeal = appealState(s);
			return {
				now: 'A person declined this request and wrote down why. A score alone never refuses.',
				steps:
					appeal === 'can_appeal'
						? ['You can appeal once. A member panel, not the reviewer who decided, reads your appeal and decides.']
						: appeal === 'appeal_open'
							? ['Your appeal is with the member panel. Their decision will show here.']
							: ['This refusal has been appealed and decided. Any pledges were released.']
			};
		}
		case 'withdrawn':
			return { now: 'You withdrew this request.', steps: ['Any pledges were released, and nobody was charged.'] };
		case 'expired':
			return { now: 'This request ran out of time.', steps: ['Any pledges were released. You can start a new request.'] };
	}
}
