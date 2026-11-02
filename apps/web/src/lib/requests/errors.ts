import { formatCents } from '#lib/dashboard/format.ts';
import { requestKindLabel, type RequestKind } from '#lib/dashboard/labels.ts';

/** The parts of a PostgrestError, StorageError or thrown error this needs. */
export interface DbError {
	code?: string;
	message?: string;
}

/** Raised by the data layer when an update matched no row the member may change. */
export const NOT_EDITABLE = 'request is not an editable draft';
/** Raised by the data layer when an evidence delete matched no row. */
export const EVIDENCE_LOCKED = 'evidence can no longer be removed';

/**
 * A refusal from the request functions and tables, in plain words: what
 * happened and what to do next. The functions raise readable messages for
 * each rule; this says each one the way a member in a bad week would want to
 * hear it. Anything unrecognised is passed through rather than hidden.
 */
export function explainRequestError(error: DbError | null | undefined): string {
	const message = error?.message ?? '';
	const code = error?.code ?? '';

	// --- submit_request -------------------------------------------------------
	if (/^request not found$/i.test(message))
		return 'We couldn’t find this request on your account. Go back to your home and open it from there.';
	if (/verify your identity/i.test(message))
		return 'Verify your identity first. Kinfold checks every member once before a request can go out.';
	if (/only drafts and requests needing evidence can be submitted/i.test(message))
		return 'This request has already been sent. Refresh the page to see where it is.';
	if (/name who should be paid/i.test(message))
		return 'Choose who should be paid first: the shop, contractor, lender or seller. The money goes to them, never to you.';
	if (/the payee does not fit this request/i.test(message))
		return 'The business you named doesn’t fit this request: cars go to a repair shop, a home repair to a contractor, and home money to a lender, seller or title company. Pick the one that pays it, then submit again.';
	if (/add at least one piece of evidence/i.test(message))
		return 'Add at least one piece of evidence first, like a photo or an estimate.';
	if (/confirm the redacted copy of every piece of evidence/i.test(message))
		return 'Every piece of evidence needs its redacted copy checked and confirmed by you before the request can go out.';

	const notCovered = /community pool does not cover (\w+) requests/i.exec(message)?.[1];
	if (notCovered)
		return `The community pool doesn’t cover ${kindWords(notCovered)} requests yet. Ask family and friends instead.`;
	const cap = /pool pays at most (\d+) cents/i.exec(message)?.[1];
	if (cap)
		return `The pool pays at most ${formatCents(Number(cap))} per request. Lower the amount, or ask family and friends for it.`;
	const waitCover = /pool cover starts (\d+) days after your first payment/i.exec(message)?.[1];
	if (waitCover)
		return `Pool cover starts ${waitCover} days after your first dues payment, and this happened before then. Ask family and friends instead.`;
	const waitCar = /vehicle must be registered with Kinfold (\d+) days/i.exec(message)?.[1];
	if (waitCar)
		return `For the pool to help, the car must have been registered with Kinfold at least ${waitCar} days before it happened. Choose the right car, or ask family and friends.`;

	// --- withdraw, redaction, summary, appeal ------------------------------------
	if (/can no longer be withdrawn/i.test(message))
		return 'This request can’t be withdrawn now. Once it’s fully pledged, a person handles any change. Refresh to see its status.';
	if (/evidence not found or not ready to confirm/i.test(message))
		return 'This redacted copy isn’t ready to confirm, or it’s already confirmed. Refresh the page.';
	if (/no public summary to confirm/i.test(message))
		return 'There’s no public summary to confirm yet. It’s written once your evidence has been redacted.';
	if (/only a refused request of yours can be appealed/i.test(message))
		return 'Only a request a person has declined can be appealed, and this one isn’t declined now. Refresh the page.';
	if (/refusal has already been appealed/i.test(message))
		return 'You’ve already appealed this decision. Each refusal can be appealed once; the panel’s answer will show here.';

	// --- table checks -------------------------------------------------------------
	if (message === NOT_EDITABLE)
		return 'This request isn’t a draft any more, so it can’t be changed here. Refresh to see where it is.';
	if (message === EVIDENCE_LOCKED)
		return 'Evidence can be removed only while a request is a draft or needs more evidence. Refresh the page.';
	if (/requests_title_check/.test(message)) return 'The title must be 1 to 120 characters.';
	if (/requests_description_check/.test(message)) return 'The description can be up to 5,000 characters.';
	if (/requests_amount_cents_check/.test(message)) return 'The amount must be more than $0.';
	if (/"requests_check"/.test(message))
		return 'The date it happened can’t be later than the day you started this request.';
	if (/requests_(payee|asset)_id_fkey/.test(message))
		return 'That payee or car isn’t available any more. Choose again.';
	if (/appeals_reason_check/.test(message)) return 'Your appeal must be 10 to 2,000 characters.';
	if (/payees_legal_name_check/.test(message)) return 'The business name must be 1 to 200 characters.';
	if (/payees_region_check/.test(message)) return 'Choose the state the business is in.';
	if (/evidence_original_path_key|already exists|Duplicate/i.test(message))
		return 'That file was already uploaded. Refresh the page.';
	if (/evidence_sha256_check/.test(message)) return 'The file couldn’t be fingerprinted. Try uploading it again.';
	if (/row-level security/i.test(message) && /"evidence"|"objects"/.test(message))
		return 'Evidence can be added only while a request is a draft or needs more evidence.';
	if (/row-level security/i.test(message) && /"payees"/.test(message))
		return 'That payee couldn’t be added. Sign in again and retry.';
	if (/row-level security/i.test(message))
		return 'Only drafts can be changed, and only by the member who started them.';

	// --- transport ------------------------------------------------------------------
	if (code === 'PGRST301' || /jwt expired/i.test(message)) return 'Your session has ended. Sign in again, then retry.';
	if (/failed to fetch|networkerror|fetch failed|load failed/i.test(message))
		return 'Can’t reach the server. Check your connection and try again. Nothing was saved.';

	return message ? `The server refused this: “${message}”` : 'Something went wrong and nothing was saved. Try again.';
}

function kindWords(kind: string): string {
	const label: string | undefined = requestKindLabel(kind as RequestKind);
	return label ? label.toLowerCase() : kind.replaceAll('_', ' ');
}
