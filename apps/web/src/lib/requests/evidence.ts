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

/**
 * A distinct name for each piece of evidence, in list order: the kind, plus a
 * number when there is more than one of that kind ("Photo 1", "Photo 2"). It
 * heads each row and ends each row button's accessible name, so a screen
 * reader's button list can tell "Remove: Photo 1" from "Remove: Photo 2".
 */
export function evidenceNames(rows: readonly { id: string; kind: EvidenceKind }[]): Map<string, string> {
	const total = new Map<EvidenceKind, number>();
	for (const r of rows) total.set(r.kind, (total.get(r.kind) ?? 0) + 1);
	const seen = new Map<EvidenceKind, number>();
	const out = new Map<string, string>();
	for (const r of rows) {
		const n = (seen.get(r.kind) ?? 0) + 1;
		seen.set(r.kind, n);
		out.set(r.id, (total.get(r.kind) ?? 0) > 1 ? `${evidenceKindLabel(r.kind)} ${n}` : evidenceKindLabel(r.kind));
	}
	return out;
}

/** What usually backs each kind of request (docs/design.md, "Upload evidence"). */
export function evidenceSuggestions(kind: RequestKind): string {
	switch (kind) {
		case 'car_damage':
			return 'Photos of the damage, the police or incident report, the shop’s estimate, and the other driver’s insurer details if there are any.';
		case 'car_deductible':
			return 'Your insurer’s claim letter or adjuster’s estimate showing the deductible, photos of the damage, the shop’s estimate, and the police or incident report if there is one.';
		case 'home_repair':
			return 'Photos of the damage, the contractor’s quote, and proof you own the home.';
		case 'down_payment':
		case 'mortgage_gap':
			return 'The purchase contract or mortgage statement, and proof of income.';
		case 'loan_payoff':
			return 'The loan statement showing the balance and the rate.';
	}
}

/**
 * What to send instead when a usual piece is missing. These are other ways of
 * showing the same facts, not new rules: the score measures how well the
 * evidence backs the request, and a low one only asks for more (design.md
 * principle 8), so thin evidence is never a dead end.
 */
export function evidenceAlternatives(kind: RequestKind): string[] {
	const noReport =
		'No police report? Many small crashes don’t get one. Say so under “What happened”, and add what you do have: dated photos of the damage and the scene, the other driver’s details or a message from them, or a note from someone who saw it.';
	switch (kind) {
		case 'car_damage':
			return [noReport];
		case 'car_deductible':
			return [
				noReport,
				'No claim letter yet? A screenshot of the claim in your insurer’s app or website showing the claim number and your deductible works too.'
			];
		case 'home_repair':
			return [
				'No deed to hand? A property tax bill, a mortgage statement, or your homeowner’s insurance page with your name and the address also shows you own the home.'
			];
		case 'down_payment':
		case 'mortgage_gap':
			return [
				'Proof of income can be pay stubs, a benefits award letter, or bank statements showing the deposits. Benefits count like any other income.'
			];
		case 'loan_payoff':
			return ['Can’t download a statement? A screenshot of the lender’s page showing the balance and the rate works too.'];
	}
}

/** Said beside every checklist: a missing piece never stops a member asking. */
export const SEND_WHAT_YOU_HAVE = 'Send what you have. A low score only asks for more evidence; it never refuses a request.';

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
				label: 'Waiting on Kinfold',
				hint: 'Kinfold’s step, not yours: before anyone else sees it, Kinfold blurs faces, plates, names, addresses and account numbers. That step isn’t switched on yet, so this waits with Kinfold for now. There’s nothing for you to do on it.',
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

/** The accepted type for each file extension, for browsers that report none. */
const TYPE_BY_EXTENSION: Record<string, string> = {
	jpg: 'image/jpeg',
	jpeg: 'image/jpeg',
	png: 'image/png',
	heic: 'image/heic',
	heif: 'image/heif',
	webp: 'image/webp',
	pdf: 'application/pdf'
};

/**
 * The file's type if the upload accepts it, else null. Some browsers report
 * an empty type for HEIC photos; then the extension decides, so a member isn't
 * told to upload "a HEIC" right after choosing one.
 */
export function evidenceType(file: { type: string; name: string }): string | null {
	if (file.type) return ACCEPTED_TYPES.includes(file.type) ? file.type : null;
	const ext = /\.([a-z0-9]+)$/i.exec(file.name)?.[1]?.toLowerCase();
	return (ext && TYPE_BY_EXTENSION[ext]) || null;
}

export function fileProblem(file: { size: number; type: string; name: string }): string | null {
	if (file.size === 0) return 'That file is empty. Choose another.';
	if (!evidenceType(file)) return 'Upload a photo (JPEG, PNG, HEIC or WebP) or a PDF.';
	if (file.size > MAX_BYTES) return 'That file is over 50 MB. Upload a smaller copy.';
	return null;
}

const splitPath = (path: string): [folder: string, name: string] => {
	const i = path.lastIndexOf('/');
	return [path.slice(0, i), path.slice(i + 1)];
};

/** The storage folders to list to check a request's originals are there. */
export const originalFolders = (paths: readonly string[]): string[] => [...new Set(paths.map((p) => splitPath(p)[0]))];

/**
 * Evidence rows whose original isn't in storage: an upload that stopped after
 * its row was written (the tab closed, the signal dropped). Only folders that
 * were listed count; a folder that couldn't be listed marks nothing, so a
 * failed check never calls a real upload unfinished.
 */
export function unfinishedUploads(
	rows: readonly { id: string; original_path: string }[],
	listed: ReadonlyMap<string, ReadonlySet<string>>
): Set<string> {
	const out = new Set<string>();
	for (const r of rows) {
		const [folder, name] = splitPath(r.original_path);
		const names = listed.get(folder);
		if (names && !names.has(name)) out.add(r.id);
	}
	return out;
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
