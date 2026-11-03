import type { Database } from '../../../../backend/supabase/database.types.ts';

type Enums = Database['public']['Enums'];
export type ReviewDecision = Enums['review_decision'];
export type RequestStatus = Enums['request_status'];
export type RequestKind = Enums['request_kind'];
export type EvidenceKind = Enums['evidence_kind'];
export type RedactionStatus = Enums['redaction_status'];
export type MemberRole = Enums['member_role'];

/** What the review console shows to a member, by role. */
export function reviewAccess(roles: readonly MemberRole[]): { reviewer: boolean; panel: boolean } {
	return { reviewer: roles.includes('reviewer'), panel: roles.includes('panel') };
}

export interface DecisionOption {
	value: ReviewDecision;
	label: string;
	/** What happens to the request, in one line. */
	effect: string;
}

/** The decisions `record_review` accepts, in the order the form offers them. */
/** The `needs_decision` enum (20261102470000_needs_review.sql), written out because
 * it is newer than the generated types. */
export type NeedsDecision = 'needs' | 'not_needs';

export interface NeedsDecisionOption {
	value: NeedsDecision;
	label: string;
	effect: string;
}

/** The answers `record_needs_decision` accepts, in the order the form offers them. */
export const NEEDS_DECISIONS: readonly NeedsDecisionOption[] = [
	{
		value: 'needs',
		label: 'Needs the Fund\u2019s help',
		effect: 'Records your answer beside the ranking. The score itself never changes.'
	},
	{
		value: 'not_needs',
		label: 'Public help covers it',
		effect: 'Records your answer beside the ranking. The score itself never changes.'
	}
];

/** A trail action in console words; unknown actions read as their own name. */
export function auditWord(action: string): string {
	const words: Record<string, string> = {
		'claim.recorded': 'A claim was recorded',
		'claim.denied': 'A claim was denied',
		'fraud_signal.recorded': 'A fraud signal was recorded',
		'covered_assets.class': 'A vehicle class was stated',
		'cover_choices.set': 'A cover plan was chosen',
		'audit_log.read': 'The trail was read',
	};
	return words[action] ?? action.replaceAll('.', ' ').replaceAll('_', ' ');
}

export function needsDecisionLabel(decision: NeedsDecision): string {
	return NEEDS_DECISIONS.find((o) => o.value === decision)?.label ?? decision;
}

export const REVIEW_DECISIONS: readonly DecisionOption[] = [
	{ value: 'approve', label: 'Approve', effect: 'Opens the request for funding.' },
	{
		value: 'needs_evidence',
		label: 'Ask for more evidence',
		effect: 'Sends it back to the member. Say what is missing.'
	},
	{
		value: 'escalate',
		label: 'Escalate',
		effect: 'Keeps it in review for a second reviewer.'
	},
	{
		value: 'refuse',
		label: 'Refuse',
		effect: 'Turns the request down. The member can appeal to the panel.'
	}
];

export function decisionLabel(decision: ReviewDecision): string {
	return REVIEW_DECISIONS.find((d) => d.value === decision)?.label ?? decision;
}

/** Past tense, for the record of what was decided. */
const DECIDED: Record<ReviewDecision, string> = {
	approve: 'Approved',
	needs_evidence: 'Asked for more evidence',
	escalate: 'Escalated',
	refuse: 'Refused'
};

export function decidedLabel(decision: ReviewDecision): string {
	return DECIDED[decision];
}

const STATUS: Record<RequestStatus, string> = {
	draft: 'Draft',
	scoring: 'Being scored',
	needs_evidence: 'Needs more evidence',
	in_review: 'In review',
	open: 'Open for funding',
	funded: 'Funded',
	paid: 'Paid',
	refused: 'Refused',
	withdrawn: 'Withdrawn',
	expired: 'Expired'
};

export function statusLabel(status: RequestStatus): string {
	return STATUS[status];
}

/** The states `record_review` accepts. A refusal is reopened only by an upheld appeal. */
const REVIEWABLE: readonly RequestStatus[] = ['in_review', 'needs_evidence', 'open', 'funded'];

export function isReviewable(status: RequestStatus): boolean {
	return REVIEWABLE.includes(status);
}

const KIND: Record<RequestKind, string> = {
	car_damage: 'Car damage',
	car_deductible: 'Car deductible',
	home_repair: 'Home repair',
	down_payment: 'Down payment',
	mortgage_gap: 'Mortgage gap',
	loan_payoff: 'Loan payoff'
};

export function kindLabel(kind: RequestKind): string {
	return KIND[kind] ?? kind;
}

const EVIDENCE: Record<EvidenceKind, string> = {
	photo: 'Photo',
	police_report: 'Police report',
	estimate: 'Estimate',
	invoice: 'Invoice',
	statement: 'Statement',
	contract: 'Contract',
	other: 'Other document'
};

export function evidenceLabel(kind: EvidenceKind): string {
	return EVIDENCE[kind] ?? kind;
}

const REDACTION: Record<RedactionStatus, string> = {
	pending: 'Redaction pending',
	auto_done: 'Redacted, awaiting member check',
	confirmed: 'Redacted and confirmed',
	rejected: 'Redaction rejected'
};

export function redactionLabel(status: RedactionStatus): string {
	return REDACTION[status];
}

const cents = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' });

/** Exact dollars and cents from integer cents, e.g. `$1,850.00`. */
export function formatCents(amountCents: number): string {
	return cents.format(amountCents / 100);
}

const day = new Intl.DateTimeFormat('en-US', {
	month: 'short',
	day: 'numeric',
	year: 'numeric',
	timeZone: 'UTC'
});
const dayLocal = new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', year: 'numeric' });

/**
 * A calendar date (`2026-10-22`) or a timestamp as `Oct 22, 2026`. A bare date
 * is read as UTC so it never shifts a day in a western time zone.
 */
export function formatDay(value: string | null): string {
	if (!value) return '';
	if (/^\d{4}-\d{2}-\d{2}$/.test(value)) return day.format(new Date(`${value}T00:00:00Z`));
	const d = new Date(value);
	return Number.isNaN(d.getTime()) ? '' : dayLocal.format(d);
}

/** A ledger account code in console words; an unknown code reads as its own name. */
export function accountWord(code: string): string {
	const words: Record<string, string> = {
		partner_cash: 'money from the payment partner',
		available: 'the pool\u2019s money',
		reserve: 'the reserve held back for the next run',
		committed: 'money committed to funded requests',
		paid_out: 'money paid out to payees',
		dues: 'dues money',
		premiums: 'premiums the cooperative has paid'
	};
	return words[code] ?? code.replaceAll('_', ' ');
}

/** A fund in console words. */
export function fundWord(fund: string): string {
	const words: Record<string, string> = {
		protection: 'the repair fund',
		home_fund: 'the Home Fund',
		people: 'the people fund'
	};
	return words[fund] ?? fund.replaceAll('_', ' ');
}
