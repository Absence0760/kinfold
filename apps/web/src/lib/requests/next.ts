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
	/**
	 * `stored: false` marks an evidence row whose file never reached storage
	 * (an upload that didn't finish); absent or true means it is there.
	 */
	evidence: readonly { redaction_status: RedactionStatus; stored?: boolean }[];
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

const pieces = (n: number) => (n === 1 ? '1 piece' : `${n} pieces`);

/** One thing still stopping `submit_request`, and whose move it is. */
export interface Blocker {
	text: string;
	/** `kinfold`: a step Kinfold has to take, with nothing for the member to do. */
	who: 'member' | 'kinfold';
}

/**
 * What still stops `submit_request`, in its order, leaving out the pool
 * checks (see `poolProblems`). Empty when it can be sent. Evidence still
 * waiting for automatic redaction is Kinfold's step, and is said to be.
 */
export function submitBlockerList(s: RequestState): Blocker[] {
	if (!canChangeEvidence(s)) return [];
	const out: Blocker[] = [];
	const member = (text: string) => out.push({ text, who: 'member' });
	if (!s.hasPayee) member(`Choose who should be paid: ${payeeWord(s.kind)}. The money goes to them, never to you.`);
	if (s.evidence.length === 0) {
		member('Add at least one piece of evidence.');
		return out;
	}
	const unfinished = s.evidence.filter((e) => e.stored === false).length;
	const stored = s.evidence.filter((e) => e.stored !== false);
	const count = (st: RedactionStatus) => stored.filter((e) => e.redaction_status === st).length;
	if (unfinished) {
		member(
			unfinished === 1
				? 'Remove the upload that didn’t finish, then add that file again.'
				: `Remove the ${unfinished} uploads that didn’t finish, then add those files again.`
		);
	}
	const rejected = count('rejected');
	if (rejected) member(`Remove ${pieces(rejected)} of evidence whose redacted copy wasn’t usable, and add a clearer copy.`);
	const toCheck = count('auto_done');
	if (toCheck) member(`Check the redacted copy of ${pieces(toCheck)} of evidence and confirm nothing private shows.`);
	const pending = count('pending');
	if (pending) {
		out.push({
			who: 'kinfold',
			text: `Waiting on Kinfold, not you: Kinfold has to blur private details in ${pieces(pending)} of evidence before the request can be submitted. That step isn’t switched on yet, so there’s nothing for you to do on ${pending === 1 ? 'it' : 'them'} for now.`
		});
	}
	return out;
}

/** The blockers as plain lines. */
export const submitBlockers = (s: RequestState): string[] => submitBlockerList(s).map((b) => b.text);

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
				now: 'This is a draft. Only you, and family or friends you invite to support it, can see it.',
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
				now: 'Your move: add evidence. Nothing has been refused; the evidence so far doesn’t back the request strongly enough yet.',
				steps: [
					'Read what’s missing: the reasons under the score, and any reviewer’s note, say what would help.',
					'Add that evidence, then press Submit again.',
					...submitBlockers(s),
					'It’s scored again. If the evidence still looks thin, a trained member reviewer looks at it. A score alone never refuses.'
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

/**
 * The note a reviewer wrote when they last asked for more evidence, if that is
 * the latest decision on the request: shown under "Where it is now" so the
 * member doesn't have to scroll to find what to add.
 */
export function reviewerAsk(reviews: readonly { decision: string; reason: string; created_at: string }[]): string | null {
	const latest = [...reviews].sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at))[0];
	return latest?.decision === 'needs_evidence' ? latest.reason : null;
}
