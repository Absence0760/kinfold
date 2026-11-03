import { describe, expect, it } from 'vitest';
import { Constants } from '../../../../backend/supabase/database.types.ts';
import { programHelpHeading, programHelpLines, type ProgramHelpLine } from './program-help.ts';
import { type RequestKind } from '#lib/dashboard/labels.ts';

describe('programHelpLines', () => {
	it('only the down-payment kind gets pointers, everything else gets nothing', () => {
		for (const kind of Constants.public.Enums.request_kind) {
			const lines = programHelpLines(kind);
			if (kind === 'down_payment') {
				expect(lines).toHaveLength(3);
				expect(lines.every((l: ProgramHelpLine) => l.title !== '' && l.body !== '')).toBe(true);
			} else {
				expect(lines).toEqual([]);
			}
		}
	});

	it('the copy prices nothing and keeps every programme money in its own name', () => {
		// design.md, "Public money stays in the funder's name": programme money
		// reaches a household under that programme's own note and lien, so no line
		// may offer the member an amount, a rate, or a fee for the pointing.
		for (const l of programHelpLines('down_payment')) {
			const text = `${l.title} ${l.body}`;
			expect(text).not.toMatch(/\d+(\.\d+)?\s*(dollars|USD|cents)/);
			// A percentage may only ever be the Fund's own zero-interest loans
			// ("0% loans"), never a share, a rate or a fee for the pointing.
			// Rule citations (24 CFR 92.503) carry digits but no amount.
			expect(text).not.toMatch(/(?!0%)\d+(\.\d+)?%/);
			expect(text).not.toMatch(/you (pay|owe|charged)/i);
			expect(text).not.toMatch(/we charge/i);
		}
	});

	it('the panel says Kinfold administers no programme paper', () => {
		// The sentence roadmap 3g asks for: every public lien stays in the funder's
		// own name, and Kinfold never administers HOME or CDBG paper.
		const [, cityLine, lastLine] = programHelpLines('down_payment');
		expect(cityLine.title).toContain('HOME');
		expect(cityLine.body).toContain('never administers HOME or CDBG paper');
		expect(cityLine.body).toContain('24 CFR 92.503');
		expect(cityLine.body).toContain('24 CFR 92.220');
		expect(cityLine.body).toContain('that ask goes to the city, not to this page');
		const [agencyLine] = programHelpLines('down_payment');
		expect(agencyLine.body).toContain('never becomes the agency');
		// Programme money and Fund money stay two pots, and the page says it.
		expect(lastLine.body).toContain('never joins the Fund’s money');
		expect(lastLine.body).toContain('funder keeps its own name');
	});

	it('down-payment money stays with the state agency, HOME/CDBG and the recorded gap', () => {
		const all = programHelpLines('down_payment').map((l) => `${l.title} ${l.body}`).join(' ');
		// All three lines the design names for the Home Fund's first priorities, and
		// the third is the schema's own subtraction (`request_recoveries`).
		for (const phrase of [
			'state housing finance agency',
			'HOME',
			'CDBG',
			'income limits',
			'recorded with the request'
		]) {
			// Lower-cased once so a sentence-initial capital still matches.
			expect(all.toLowerCase()).toContain(phrase.toLowerCase());
		}
	});
});