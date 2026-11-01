import { latestScores, type RequestScore } from '#lib/dashboard/requests.ts';
import { supabase } from '#lib/supabase/client.ts';
import type { Database } from '../../../../backend/supabase/database.types.ts';
import type { AssetRow, FundSettings } from './eligibility.ts';
import { EVIDENCE_LOCKED, NOT_EDITABLE, explainRequestError, type DbError } from './errors.ts';
import {
	evidencePath,
	evidenceType,
	originalFolders,
	sha256Hex,
	unfinishedUploads,
	type EvidenceKind
} from './evidence.ts';
import type { DraftValues, PayeeKind } from './form.ts';

type Tables = Database['public']['Tables'];
export type RequestRow = Tables['requests']['Row'];
export type PayeeRow = Pick<Tables['payees']['Row'], 'id' | 'kind' | 'legal_name' | 'region' | 'status'>;
export type EvidenceRow = Pick<
	Tables['evidence']['Row'],
	'id' | 'kind' | 'original_path' | 'redacted_path' | 'redaction_status' | 'captured_in_app' | 'created_at'
> & {
	/** False when the original never reached storage (an upload that didn't finish). */
	stored: boolean;
};
export type PayoutRow = Pick<Tables['payouts']['Row'], 'id' | 'status' | 'amount_cents' | 'sent_at' | 'created_at'>;
export type AppealRow = Pick<Tables['appeals']['Row'], 'id' | 'reason' | 'status' | 'created_at' | 'decided_at'>;
export type EventRow = Pick<Tables['request_events']['Row'], 'id' | 'from_status' | 'to_status' | 'at'>;
export interface ReviewRow {
	decision: Database['public']['Enums']['review_decision'];
	reason: string;
	created_at: string;
}

/** An error whose message is already in plain words; `cause` keeps the original. */
export class RequestError extends Error {
	constructor(error: DbError) {
		super(explainRequestError(error));
		this.name = 'RequestError';
		this.cause = error;
	}
}

function fail(error: DbError): never {
	throw new RequestError(error);
}

const PAYEE_COLUMNS = 'id, kind, legal_name, region, status';
const ASSET_COLUMNS = 'id, kind, description, registered_on, removed_on';

export interface FormContext {
	settings: FundSettings[];
	payees: PayeeRow[];
	assets: AssetRow[];
	coverageStartedOn: string | null;
}

/**
 * What the request form needs, read as the member under RLS: the published
 * fund rules, the payees they may name (verified ones and their own
 * proposals), their own cars, and when their pool cover began.
 */
export async function loadFormContext(uid: string): Promise<FormContext> {
	const db = supabase();
	const [settings, payees, assets, coverage] = await Promise.all([
		db.from('fund_settings').select('fund, kinds, max_request_cents, waiting_days, min_score'),
		db.from('payees').select(PAYEE_COLUMNS).order('legal_name'),
		db.from('covered_assets').select(ASSET_COLUMNS).eq('member_id', uid).is('removed_on', null).order('registered_on'),
		db.rpc('coverage_started_on', { p_member: uid })
	]);
	for (const r of [settings, payees, assets, coverage]) if (r.error) fail(r.error);
	return {
		settings: settings.data ?? [],
		payees: payees.data ?? [],
		assets: assets.data ?? [],
		coverageStartedOn: (coverage.data as string | null) ?? null
	};
}

export interface RequestDetail {
	request: RequestRow;
	payee: PayeeRow | null;
	asset: AssetRow | null;
	score: RequestScore | null;
	evidence: EvidenceRow[];
	appeals: AppealRow[];
	reviews: ReviewRow[];
	events: EventRow[];
	/** Payouts to the payee, oldest first (the "owners read payouts" policy). */
	payouts: PayoutRow[];
}

/**
 * Which of a request's evidence rows have no original in storage. The member
 * may list their own folder of `evidence-original` ("members read their
 * originals"). A folder that can't be listed marks nothing.
 */
async function findUnfinished(rows: readonly { id: string; original_path: string }[]): Promise<Set<string>> {
	if (rows.length === 0) return new Set();
	const bucket = supabase().storage.from('evidence-original');
	const listed = new Map<string, Set<string>>();
	await Promise.all(
		originalFolders(rows.map((r) => r.original_path)).map(async (folder) => {
			const { data, error } = await bucket.list(folder, { limit: 1000 });
			if (!error && data) listed.set(folder, new Set(data.map((o) => o.name)));
		})
	);
	return unfinishedUploads(rows, listed);
}

/** One of the member's own requests with everything the detail page shows, or null. */
export async function loadRequest(id: string): Promise<RequestDetail | null> {
	const db = supabase();
	const req = await db.from('requests').select('*').eq('id', id).maybeSingle();
	if (req.error) {
		// A malformed id is "not found", not a server error.
		if (req.error.code === '22P02') return null;
		fail(req.error);
	}
	if (!req.data) return null;
	const r = req.data;

	const [payee, asset, scores, evidence, appeals, reviews, events, payouts] = await Promise.all([
		r.payee_id ? db.from('payees').select(PAYEE_COLUMNS).eq('id', r.payee_id).maybeSingle() : null,
		r.asset_id ? db.from('covered_assets').select(ASSET_COLUMNS).eq('id', r.asset_id).maybeSingle() : null,
		db.from('scores').select('request_id, score, reasons, model, model_version, created_at').eq('request_id', id),
		db
			.from('evidence')
			.select('id, kind, original_path, redacted_path, redaction_status, captured_in_app, created_at')
			.eq('request_id', id)
			.order('created_at'),
		db.from('appeals').select('id, reason, status, created_at, decided_at').eq('request_id', id).order('created_at'),
		db.rpc('my_request_reviews', { p_request: id }),
		db.from('request_events').select('id, from_status, to_status, at').eq('request_id', id).order('id'),
		db.from('payouts').select('id, status, amount_cents, sent_at, created_at').eq('request_id', id).order('created_at')
	]);
	for (const res of [payee, asset, scores, evidence, appeals, reviews, events, payouts]) if (res?.error) fail(res.error);

	// Only evidence that can still change can be removed and re-added, so only
	// there is an unfinished upload worth finding.
	const rows = evidence.data ?? [];
	const unfinished = r.status === 'draft' || r.status === 'needs_evidence' ? await findUnfinished(rows) : new Set<string>();

	return {
		request: r,
		payee: payee?.data ?? null,
		asset: asset?.data ?? null,
		score: latestScores(scores.data ?? []).get(id) ?? null,
		evidence: rows.map((e) => ({ ...e, stored: !unfinished.has(e.id) })),
		appeals: appeals.data ?? [],
		reviews: reviews.data ?? [],
		events: events.data ?? [],
		payouts: payouts.data ?? []
	};
}

/** Start a draft (the "members create drafts" policy). Returns its id. */
export async function createDraft(uid: string, values: DraftValues): Promise<string> {
	const { data, error } = await supabase()
		.from('requests')
		.insert({ member_id: uid, ...values })
		.select('id')
		.single();
	if (error) fail(error);
	return data.id;
}

/** Change a draft (the "members edit drafts" policy). Fails if it isn't a draft any more. */
export async function updateDraft(id: string, values: DraftValues): Promise<void> {
	const { data, error } = await supabase().from('requests').update(values).eq('id', id).select('id');
	if (error) fail(error);
	if (!data || data.length === 0) fail({ message: NOT_EDITABLE });
}

/** Propose a payee (the "members propose payees" policy). Kinfold verifies it later. */
export async function proposePayee(
	uid: string,
	values: { kind: PayeeKind; legal_name: string; region: string }
): Promise<PayeeRow> {
	const { data, error } = await supabase()
		.from('payees')
		.insert({ ...values, proposed_by: uid })
		.select(PAYEE_COLUMNS)
		.single();
	if (error) fail(error);
	return data;
}

/**
 * Add one piece of evidence: the row first (its policy checks the request is
 * still a draft or needs evidence), then the file into the member's own
 * folder of the private `evidence-original` bucket. If the upload fails the
 * row is removed again. If the tab dies between the two (or that removal
 * fails), `loadRequest` finds the row with no file and marks it `stored:
 * false`, and the page asks the member to remove it and add the file again.
 *
 * The row goes first on purpose: the other order would leave an original the
 * member can't delete (there is no storage delete policy) whenever the row is
 * refused. Gallery uploads are marked `captured_in_app = false`; in-app
 * capture with content credentials comes with the mobile app.
 */
export async function addEvidence(uid: string, requestId: string, kind: EvidenceKind, file: File): Promise<void> {
	const db = supabase();
	const contentType = evidenceType(file) ?? file.type;
	const sha256 = await sha256Hex(new Uint8Array(await file.arrayBuffer()));
	const path = evidencePath(uid, requestId, crypto.randomUUID(), file.name);

	const row = await db
		.from('evidence')
		.insert({ request_id: requestId, kind, original_path: path, sha256, captured_in_app: false })
		.select('id')
		.single();
	if (row.error) fail(row.error);

	const up = await db.storage.from('evidence-original').upload(path, file, { contentType, upsert: false });
	if (up.error) {
		await db.from('evidence').delete().eq('id', row.data.id);
		fail(up.error);
	}
}

/** Remove a piece of evidence before scoring (the "members remove evidence" policy). */
export async function removeEvidence(id: string): Promise<void> {
	const { data, error } = await supabase().from('evidence').delete().eq('id', id).select('id');
	if (error) fail(error);
	if (!data || data.length === 0) fail({ message: EVIDENCE_LOCKED });
}

/** A five-minute link to the member's own original or redacted copy. */
export async function evidenceLink(bucket: 'evidence-original' | 'evidence-redacted', path: string): Promise<string> {
	const { data, error } = await supabase().storage.from(bucket).createSignedUrl(path, 300);
	if (error || !data) {
		throw new Error(
			/not found|Object not found/i.test(error?.message ?? '')
				? 'That file isn’t in storage. It may not have finished uploading.'
				: explainRequestError(error)
		);
	}
	return data.signedUrl;
}

async function rpc(fn: () => PromiseLike<{ error: DbError | null }>): Promise<void> {
	const { error } = await fn();
	if (error) fail(error);
}

export const submitRequest = (id: string) => rpc(() => supabase().rpc('submit_request', { p_request: id }));
export const withdrawRequest = (id: string) => rpc(() => supabase().rpc('withdraw_request', { p_request: id }));
export const confirmSummary = (id: string) => rpc(() => supabase().rpc('confirm_public_summary', { p_request: id }));
export const confirmRedaction = (id: string) => rpc(() => supabase().rpc('confirm_redaction', { p_evidence: id }));
export const fileAppeal = (id: string, reason: string) =>
	rpc(() => supabase().rpc('file_appeal', { p_request: id, p_reason: reason }));
