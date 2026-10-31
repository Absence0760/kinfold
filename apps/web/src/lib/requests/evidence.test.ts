import { describe, expect, it } from 'vitest';
import { Constants } from '../../../../backend/supabase/database.types.ts';
import {
	EVIDENCE_KINDS,
	MAX_BYTES,
	evidenceKindLabel,
	evidencePath,
	evidenceSuggestions,
	fileProblem,
	redactionText,
	sha256Hex
} from './evidence';

describe('evidence labels', () => {
	it('labels every evidence kind in the enum', () => {
		expect(EVIDENCE_KINDS.map((k) => k.kind).sort()).toEqual([...Constants.public.Enums.evidence_kind].sort());
		expect(evidenceKindLabel('police_report')).toBe('Police or incident report');
	});

	it('words every redaction status, never just a colour', () => {
		for (const s of Constants.public.Enums.redaction_status) {
			const t = redactionText(s);
			expect(t.label).not.toBe('');
			expect(t.hint).not.toBe('');
		}
		expect(redactionText('pending').hint).toMatch(/isn’t switched on yet/);
	});

	it('suggests evidence for every request kind', () => {
		for (const k of Constants.public.Enums.request_kind) expect(evidenceSuggestions(k)).toBeTruthy();
	});
});

describe('evidencePath', () => {
	it('puts the file in the member’s own folder and drops its name', () => {
		expect(evidencePath('m1', 'r1', 'o1', 'Maria Lopez 123 Main St.JPG')).toBe('m1/r1/o1.jpg');
		expect(evidencePath('m1', 'r1', 'o1', 'no-extension')).toBe('m1/r1/o1.bin');
		expect(evidencePath('m1', 'r1', 'o1', 'x.verylongextension')).toBe('m1/r1/o1.bin');
	});
});

describe('fileProblem', () => {
	it('takes photos and PDFs up to the storage limit', () => {
		expect(fileProblem({ size: 1000, type: 'image/jpeg' })).toBe(null);
		expect(fileProblem({ size: MAX_BYTES, type: 'application/pdf' })).toBe(null);
		expect(fileProblem({ size: MAX_BYTES + 1, type: 'application/pdf' })).toMatch(/50 MB/);
		expect(fileProblem({ size: 0, type: 'image/png' })).toMatch(/empty/);
		expect(fileProblem({ size: 10, type: 'text/html' })).toMatch(/photo/);
	});
});

describe('sha256Hex', () => {
	it('is the lower-case hex form the evidence check accepts', async () => {
		const hex = await sha256Hex(new TextEncoder().encode('abc'));
		expect(hex).toBe('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
		expect(hex).toMatch(/^[0-9a-f]{64}$/);
	});
});
