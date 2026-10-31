import type { RequestKind, Tone } from '#lib/dashboard/labels.ts';
import type { Database } from '../../../../backend/supabase/database.types.ts';

type Enums = Database['public']['Enums'];
export type EvidenceKind = Enums['evidence_kind'];
export type RedactionStatus = Enums['redaction_status'];

export const EVIDENCE_KINDS: readonly { kind: EvidenceKind; label: string }[] = [
	{ kind: 'photo', label: 'Photo' },
	{ kind: 'police_report', label: 'Police or incident report' },
	{ kind: 'estimate', label: 'Estimate or quote' },
	{ kind: 'invoice', label: 'Invoice or final bill' },
	{ kind: 'statement', label: 'Statement (loan, mortgage or bank)' },
	{ kind: 'contract', label: 'Contract (purchase or loan)' },
	{ kind: 'other', label: 'Something else' }
];

export const evidenceKindLabel = (kind: EvidenceKind): string =>
	EVIDENCE_KINDS.find((k) => k.kind === kind)?.label ?? kind;

/** What usually backs each kind of request (docs/design.md, "Upload evidence"). */
export function evidenceSuggestions(kind: RequestKind): string {
	switch (kind) {
		case 'car_damage':
		case 'car_deductible':
			return 'Photos of the damage, the police or incident report, the shop’s estimate, and the other driver’s insurer details if there are any.';
		case 'home_repair':
			return 'Photos of the damage, the contractor’s quote, and proof you own the home.';
		case 'down_payment':
		case 'mortgage_gap':
			return 'The purchase contract or mortgage statement, and proof of income.';
		case 'loan_payoff':
			return 'The loan statement showing the balance and the rate.';
	}
}

export interface RedactionText {
	label: string;
	hint: string;
	tone: Tone;
}

/** A piece of evidence's redaction status in words. Never by colour alone. */
export function redactionText(status: RedactionStatus): RedactionText {
	switch (status) {
		case 'pending':
			return {
				label: 'Waiting for redaction',
				hint: 'Kinfold blurs faces, plates, names, addresses and account numbers before anyone else sees it. The redaction step isn’t switched on yet, so this waits here for now.',
				tone: 'progress'
			};
		case 'auto_done':
			return {
				label: 'Check the redacted copy',
				hint: 'Look at the redacted copy. If nothing private is left showing, confirm it.',
				tone: 'action'
			};
		case 'confirmed':
			return { label: 'Redaction confirmed', hint: 'You checked the redacted copy and confirmed it.', tone: 'done' };
		case 'rejected':
			return {
				label: 'Redaction not accepted',
				hint: 'The redacted copy wasn’t good enough to use. Remove this piece and add a clearer one.',
				tone: 'closed'
			};
	}
}

/** Files the evidence upload accepts: photos and PDFs. */
export const ACCEPTED_TYPES = ['image/jpeg', 'image/png', 'image/heic', 'image/heif', 'image/webp', 'application/pdf'];
/** The storage server's per-file limit (config.toml `file_size_limit`). */
export const MAX_BYTES = 50 * 1024 * 1024;

export function fileProblem(file: { size: number; type: string }): string | null {
	if (file.size === 0) return 'That file is empty. Choose another.';
	if (!ACCEPTED_TYPES.includes(file.type)) return 'Upload a photo (JPEG, PNG, HEIC or WebP) or a PDF.';
	if (file.size > MAX_BYTES) return 'That file is over 50 MB. Upload a smaller copy.';
	return null;
}

/**
 * Where an original is stored in the private `evidence-original` bucket. The
 * first folder must be the member's id: the storage policy and the evidence
 * row's check both require it. The file's own name isn't kept (it can carry a
 * name or an address); only a safe extension is.
 */
export function evidencePath(memberId: string, requestId: string, objectId: string, fileName: string): string {
	const ext = /\.([a-z0-9]{1,8})$/i.exec(fileName)?.[1]?.toLowerCase() ?? 'bin';
	return `${memberId}/${requestId}/${objectId}.${ext}`;
}

/** Lower-case hex SHA-256, the form `evidence.sha256` checks for. */
export async function sha256Hex(data: ArrayBuffer | Uint8Array<ArrayBuffer>): Promise<string> {
	const digest = await crypto.subtle.digest('SHA-256', data);
	return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}
