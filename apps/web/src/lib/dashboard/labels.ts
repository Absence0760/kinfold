import type { Database } from '../../../../backend/supabase/database.types.ts';

type Enums = Database['public']['Enums'];
export type RequestKind = Enums['request_kind'];
export type RequestStatus = Enums['request_status'];
export type FundingMode = Enums['funding_mode'];
export type LoanStatus = Enums['loan_status'];
export type DefaultPlan = Enums['default_plan'];

/**
 * How a status reads at a glance. The tone only picks a colour and an icon;
 * the label always says it in words, so nothing relies on colour alone.
 */
export type Tone = 'action' | 'progress' | 'done' | 'closed';

export interface StatusText {
	label: string;
	hint: string;
	tone: Tone;
}

const kindLabels: Record<RequestKind, string> = {
	car_damage: 'Car damage',
	car_deductible: 'Car insurance deductible',
	home_repair: 'Home repair',
	down_payment: 'Down payment',
	mortgage_gap: 'Mortgage gap',
	loan_payoff: 'Loan payoff'
};

export const requestKindLabel = (kind: RequestKind): string => kindLabels[kind];

const isCar = (kind: RequestKind) => kind === 'car_damage' || kind === 'car_deductible';

/** The pooled fund a request of this kind draws on (mirrors `fund_for_kind`). */
export const poolName = (kind: RequestKind): string => (isCar(kind) ? 'the repair fund' : 'the Home Fund');

/**
 * How that fund chooses what to pay, to follow its name: the repair fund pays
 * by legitimacy-score band; the Home Fund is meant to choose by a published
 * needs formula plus the score (design.md § Product 3), which isn't live yet,
 * so it gets neither a band claim nor a formula claim.
 */
export const poolRule = (kind: RequestKind): string =>
	isCar(kind) ? 'pays by score band' : 'chooses under its needs formula, which isn’t live yet';

/** Who a request's money goes to, in words. */
export const payeeWord = (kind: RequestKind): string =>
	isCar(kind) ? 'the shop' : kind === 'home_repair' ? 'the contractor' : 'the lender or seller';

export function fundingLabel(funding: FundingMode, kind: RequestKind): string {
	switch (funding) {
		case 'people':
			return 'Family and friends';
		case 'pool':
			return capitalise(poolName(kind));
		case 'both':
			return `Family, friends and ${poolName(kind)}`;
	}
}

/** A request's status in plain words, with what happens next. */
export function requestStatusText(status: RequestStatus, kind: RequestKind, funding: FundingMode): StatusText {
	switch (status) {
		case 'draft':
			return { label: 'Draft', hint: 'Not sent yet. Add your evidence, check the redactions, then submit.', tone: 'action' };
		case 'scoring':
			return { label: 'Checking evidence', hint: 'We’re reading your evidence. This usually takes minutes.', tone: 'progress' };
		case 'needs_evidence':
			return {
				label: 'Needs more evidence',
				hint: 'Nothing has been refused. Add more evidence and submit again.',
				tone: 'action'
			};
		case 'in_review':
			return { label: 'With a person', hint: 'A reviewer is looking at it. You’ll hear back here.', tone: 'progress' };
		case 'open':
			return {
				label: funding === 'pool' ? `Waiting for ${poolName(kind)}` : 'Open for help',
				hint:
					funding === 'people'
						? 'Family and friends you invited can pledge to it.'
						: `It’s on the members’ board, and ${poolName(kind)} ${poolRule(kind)} at its next run.`,
				tone: 'progress'
			};
		case 'funded':
			return {
				label: 'Fully pledged',
				hint: `The money is being collected, then paid straight to ${payeeWord(kind)}.`,
				tone: 'progress'
			};
		case 'paid':
			return { label: `Paid to ${payeeWord(kind)}`, hint: 'Done. The money went to the payee, not to you.', tone: 'done' };
		case 'refused':
			return {
				label: 'Not approved',
				hint: 'A person made this decision and wrote down why. You can appeal it once, to someone new.',
				tone: 'closed'
			};
		case 'withdrawn':
			return { label: 'Withdrawn', hint: 'You withdrew it. Any pledges were released.', tone: 'closed' };
		case 'expired':
			return { label: 'Expired', hint: 'It ran out of time. Any pledges were released.', tone: 'closed' };
	}
}

/** Lower sorts first: things needing the member, then live ones, then finished. */
export function requestSortRank(status: RequestStatus): number {
	const tone = requestStatusText(status, 'car_damage', 'people').tone;
	return { action: 0, progress: 1, done: 2, closed: 3 }[tone];
}

export function loanStatusText(status: LoanStatus): StatusText {
	switch (status) {
		case 'proposed':
			return { label: 'Waiting for signatures', hint: 'Both of you sign once the terms and schedule are set.', tone: 'action' };
		case 'signed':
			return {
				label: 'Signed',
				hint: 'Repayments start once the request is paid and the money has reached the payee.',
				tone: 'progress'
			};
		case 'active':
			return { label: 'Being repaid', hint: 'Monthly, with no interest and no late fees.', tone: 'progress' };
		case 'paused':
			return { label: 'Paused', hint: 'Repayments are on hold. The total owed hasn’t changed.', tone: 'progress' };
		case 'repaid':
			return { label: 'Repaid in full', hint: 'Every installment is paid.', tone: 'done' };
		case 'forgiven':
			return { label: 'Forgiven', hint: 'The rest was forgiven as a gift.', tone: 'done' };
		case 'defaulted':
			return { label: 'Closed under the agreed plan', hint: 'Repayment stopped, and the plan you both picked applied.', tone: 'closed' };
		case 'cancelled':
			return { label: 'Cancelled', hint: 'The request ended unpaid, so no money moved.', tone: 'closed' };
	}
}

const planLabels: Record<DefaultPlan, string> = {
	forgive: 'the lender forgives the rest as a gift',
	repay_on_sale: 'the rest is repaid if the home is sold or refinanced',
	mediate: 'you both go to a mediator'
};

/** The plan both sides agreed at signing, as the end of "If repayments stop, …". */
export const defaultPlanText = (plan: DefaultPlan): string => planLabels[plan];

function capitalise(s: string): string {
	return s.charAt(0).toUpperCase() + s.slice(1);
}
