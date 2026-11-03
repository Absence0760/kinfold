import { describe, expect, it } from 'vitest';
import { agencyLine, counselorAsks, publicHelpCounselLine, publicHelpHeading } from './public-help.ts';
import type { CertifiedCounsel } from '#lib/transparency/data.ts';

describe('publicHelpHeading', () => {
	it('names the help as public and beside the gap', () => {
		expect(publicHelpHeading).toBe('Public help alongside this gap');
	});
});

describe('publicHelpCounselLine', () => {
	it('names no agency until one stands certified, pointing at the public list', () => {
		// null merges "no agency certified yet" with "the published read failed".
		const line = publicHelpCounselLine(null);
		expect(line).toContain('Nonprofit agencies certified by the government');
		expect(line).toContain('forbearance (a pause the bank agrees to)');
		expect(line).toContain('loan modification (easier terms)');
		expect(line).toContain('hud.gov');
		expect(line).toContain('Kinfold never becomes a counselor itself');
	});

	it('names the certified agency with its credential and the bank deciding', () => {
		const counsel: CertifiedCounsel = {
			version: 1,
			agencyName: 'Pilot City Housing Counseling',
			contactUrl: 'https://pilotcity.example/housing-counseling',
			hudApprovedOn: '2026-01-01',
			certifiedUnder: '24 CFR part 214',
			effectiveFrom: '2026-01-01'
		};
		const line = publicHelpCounselLine(counsel);
		expect(line).toContain('Pilot City Housing Counseling');
		expect(line).toContain('certified under 24 CFR part 214');
		expect(line).toContain('HUD-approved on Jan 1, 2026');
		expect(line).toContain('you go to them, never through Kinfold');
		expect(line).toContain('never asks one on your behalf');
	});

describe('agencyLine', () => {
	it('names the agency with the credential the row carries', () => {
		const counsel: CertifiedCounsel = {
			version: 1,
			agencyName: 'Pilot City Housing Counseling',
			contactUrl: 'https://pilotcity.example/housing-counseling',
			hudApprovedOn: '2026-01-01',
			certifiedUnder: '24 CFR part 214',
			effectiveFrom: '2026-01-01',
		};
		const line = agencyLine(counsel);
		expect(line).toContain('the agency the Fund partners with');
		expect(line).toContain('certified under 24 CFR part 214');
		expect(line).toContain('HUD-approved on Jan 1, 2026');
	});
});

	it('stays about help, not pricing', () => {
		const empty = publicHelpCounselLine(null);
		expect(/\d/.test(empty)).toBe(false);
	});
});