import { rpcNew } from '#lib/supabase/client.ts';
import type { Db } from '#lib/supabase/client.ts';
import type { ReviewDecision, RequestStatus } from './labels.ts';
import {
	buildAppeals,
	buildQueue,
	type AppealItem,
	type AppealRow,
	type EvidenceRow,
	type QueueItem,
	type QueueRequestRow,
	type ReviewRow,
	type ScoreRow
} from './queue.ts';

/**
 * Reads and writes for the review console. Everything goes through RLS as the
 * signed-in member: the queue is whatever the database lets a reviewer read,
 * and every decision is a security definer RPC that re-checks role, region and
 * self-review. Only the columns the console shows are selected; evidence never
 * includes `original_path` or `redacted_path`.
 */

const REQUEST_COLUMNS =
	'id, kind, status, amount_cents, public_summary, current_score, incident_on, submitted_at';
const SCORE_COLUMNS = 'request_id, score, reasons, model_version, created_at';
const EVIDENCE_COLUMNS = 'id, request_id, kind, redaction_status, captured_in_app, created_at';

/** States a reviewer's RLS policy shows: waiting for a person, or refused. */
const QUEUE_STATES: RequestStatus[] = ['in_review', 'needs_evidence', 'refused'];

function fail(error: { message: string; code?: string } | null): void {
	if (error) throw error;
}

/** Requests the database says this viewer may not review (region or self). */
async function loadReviewFlags(db: Db, ids: string[]): Promise<string[]> {
	if (ids.length === 0) return [];
	// `review_flags` is newer than the generated database types; see rpcNew.
	const { data, error } = await rpcNew(db, 'review_flags', { p_requests: ids });
	fail(error);
	const flags = (data ?? {}) as Record<string, boolean>;
	return ids.filter((id) => flags[id] === false);
}

export async function loadQueue(db: Db, viewerId: string): Promise<QueueItem[]> {
	const requests = await db
		.from('requests')
		.select(REQUEST_COLUMNS)
		.neq('member_id', viewerId)
		.in('status', QUEUE_STATES)
		.order('submitted_at', { ascending: true });
	fail(requests.error);
	const rows = (requests.data ?? []) as QueueRequestRow[];
	if (rows.length === 0) return [];

	const ids = rows.map((r) => r.id);
	const [scores, evidence, reviews, blocked] = await Promise.all([
		db.from('scores').select(SCORE_COLUMNS).in('request_id', ids),
		db.from('evidence').select(EVIDENCE_COLUMNS).in('request_id', ids),
		db
			.from('reviews')
			.select('request_id, decision, reason, created_at')
			.eq('reviewer_id', viewerId)
			.in('request_id', ids),
		loadReviewFlags(db, ids)
	]);
	fail(scores.error);
	fail(evidence.error);
	fail(reviews.error);
	return buildQueue(
		rows,
		(scores.data ?? []) as ScoreRow[],
		(evidence.data ?? []) as EvidenceRow[],
		(reviews.data ?? []) as ReviewRow[],
		// `review_flags` is newer than the generated types; see rpcNew.
		(blocked as string[])
	);
}

export async function loadAppeals(db: Db, viewerId: string): Promise<AppealItem[]> {
	const appeals = await db
		.from('appeals')
		.select('id, request_id, reason, status, created_at')
		.eq('status', 'open')
		.neq('member_id', viewerId)
		.order('created_at', { ascending: true });
	fail(appeals.error);
	const rows = (appeals.data ?? []) as AppealRow[];
	if (rows.length === 0) return [];

	const ids = [...new Set(rows.map((a) => a.request_id))];
	// The panel reads full review rows on requests that aren't its own. The
	// request and its score come back only if another role lets this member
	// read them; a panel-only member gets none, and the page says so.
	const [reviews, requests, scores] = await Promise.all([
		db
			.from('reviews')
			.select('request_id, decision, reason, created_at, reviewer_id')
			.in('request_id', ids),
		db.from('requests').select(REQUEST_COLUMNS).in('id', ids),
		db.from('scores').select(SCORE_COLUMNS).in('request_id', ids)
	]);
	fail(reviews.error);
	fail(requests.error);
	fail(scores.error);
	return buildAppeals(
		rows,
		(reviews.data ?? []) as ReviewRow[],
		(requests.data ?? []) as QueueRequestRow[],
		(scores.data ?? []) as ScoreRow[],
		viewerId
	);
}

/** Record a review. Returns the request's status afterwards. */
export async function recordReview(
	db: Db,
	requestId: string,
	decision: ReviewDecision,
	reason: string
): Promise<RequestStatus> {
	const { data, error } = await db.rpc('record_review', {
		p_request: requestId,
		p_decision: decision,
		p_reason: reason
	});
	fail(error);
	return data as RequestStatus;
}

/** Record a panel decision on an appeal. The reason is stored with it. */
export async function decideAppeal(db: Db, appealId: string, uphold: boolean, reason: string): Promise<void> {
	// The reason argument is newer than the generated types; see rpcNew.
	const { error } = await rpcNew(db, 'decide_appeal', {
		p_appeal: appealId,
		p_uphold: uphold,
		p_reason: reason
	});
	fail(error);
}
