import { describe, expect, it } from 'vitest';
import { Constants } from '../../../../backend/supabase/database.types.ts';
import {
	EVIDENCE_KINDS,
	MAX_BYTES,
	evidenceAlternatives,
	evidenceKindLabel,
	evidenceNames,
	evidencePath,
	evidenceSuggestions,
	evidenceType,
	fileProblem,
	originalFolders,
	redactionText,
	sha256Hex,
	unfinishedUploads
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

	it('says waiting for redaction is Kinfold’s step, not the member’s', () => {
		const t = redactionText('pending');
		expect(t.label).toBe('Waiting on Kinfold');
		expect(t.hint).toMatch(/^Kinfold’s step, not yours/);
		expect(t.hint).toMatch(/nothing for you to do/);
	});

	it('suggests evidence, and what to send instead, for every request kind', () => {
		for (const k of Constants.public.Enums.request_kind) {
			expect(evidenceSuggestions(k)).toBeTruthy();
			expect(evidenceAlternatives(k).length, k).toBeGreaterThan(0);
		}
	});

	it('offers a way through without a police report or a deed', () => {
		expect(evidenceAlternatives('car_damage').join(' ')).toMatch(/No police report\?/);
		expect(evidenceAlternatives('car_deductible').join(' ')).toMatch(/No police report\?/);
		expect(evidenceAlternatives('home_repair').join(' ')).toMatch(/property tax bill/);
	});

	it('asks for the insurer’s claim letter on a deductible request', () => {
		expect(evidenceSuggestions('car_deductible')).toMatch(/claim letter/);
		expect(evidenceSuggestions('car_damage')).not.toMatch(/claim letter/);
	});
});

describe('evidenceNames', () => {
	it('numbers repeated kinds in list order and leaves single ones plain', () => {
		const names = evidenceNames([
			{ id: 'a', kind: 'photo' },
			{ id: 'b', kind: 'estimate' },
			{ id: 'c', kind: 'photo' }
		]);
		expect([...names.values()]).toEqual(['Photo 1', 'Estimate or quote', 'Photo 2']);
		expect(new Set(names.values()).size).toBe(3);
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
		expect(fileProblem({ size: 1000, type: 'image/jpeg', name: 'a.jpg' })).toBe(null);
		expect(fileProblem({ size: MAX_BYTES, type: 'application/pdf', name: 'a.pdf' })).toBe(null);
		expect(fileProblem({ size: MAX_BYTES + 1, type: 'application/pdf', name: 'a.pdf' })).toMatch(/50 MB/);
		expect(fileProblem({ size: 0, type: 'image/png', name: 'a.png' })).toMatch(/empty/);
		expect(fileProblem({ size: 10, type: 'text/html', name: 'a.html' })).toMatch(/photo/);
	});

	it('accepts a HEIC photo whose browser-reported type is empty, by its extension', () => {
		expect(fileProblem({ size: 1000, type: '', name: 'IMG_0042.HEIC' })).toBe(null);
		expect(fileProblem({ size: 1000, type: '', name: 'scan.heif' })).toBe(null);
		expect(fileProblem({ size: 1000, type: '', name: 'notes.txt' })).toMatch(/photo/);
		expect(fileProblem({ size: 1000, type: '', name: 'no-extension' })).toMatch(/photo/);
	});
});

describe('evidenceType', () => {
	it('trusts a reported type, and falls back on the extension only when there is none', () => {
		expect(evidenceType({ type: 'image/png', name: 'x.heic' })).toBe('image/png');
		expect(evidenceType({ type: 'text/plain', name: 'x.jpg' })).toBe(null);
		expect(evidenceType({ type: '', name: 'x.HEIC' })).toBe('image/heic');
		expect(evidenceType({ type: '', name: 'x.jpeg' })).toBe('image/jpeg');
		expect(evidenceType({ type: '', name: 'x.exe' })).toBe(null);
	});
});

describe('unfinishedUploads', () => {
	const rows = [
		{ id: 'e1', original_path: 'm1/r1/a.jpg' },
		{ id: 'e2', original_path: 'm1/r1/b.jpg' },
		{ id: 'e3', original_path: 'm1/r2/c.jpg' }
	];

	it('lists the folders to check once each', () => {
		expect(originalFolders(rows.map((r) => r.original_path))).toEqual(['m1/r1', 'm1/r2']);
	});

	it('marks rows whose file is missing from a listed folder', () => {
		const listed = new Map([['m1/r1', new Set(['a.jpg'])]]);
		expect([...unfinishedUploads(rows, listed)]).toEqual(['e2']);
	});

	it('marks nothing in a folder that couldn’t be listed', () => {
		expect(unfinishedUploads(rows, new Map()).size).toBe(0);
	});
});

describe('sha256Hex', () => {
	it('is the lower-case hex form the evidence check accepts', async () => {
		const hex = await sha256Hex(new TextEncoder().encode('abc'));
		expect(hex).toBe('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
		expect(hex).toMatch(/^[0-9a-f]{64}$/);
	});
});
