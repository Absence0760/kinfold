import { describe, expect, it } from 'vitest';
import {
	appealReasonProblem,
	asPeopleOnly,
	charCount,
	draftToInput,
	isIsoDate,
	latestIncidentDate,
	fundForKind,
	isCarKind,
	payeeKindsFor,
	REQUEST_KINDS,
	validateDraft,
	validatePayee,
	type DraftInput
} from './form';

const good: DraftInput = {
	kind: 'car_damage',
	funding: 'people',
	title: '  Rear bumper after a crash  ',
	description: 'Hit at a light.',
	amount: '1,250.50',
	incidentOn: '2026-10-20',
	payeeId: '',
	assetId: 'car-1'
};

describe('asPeopleOnly', () => {
	it('changes only who is asked, and keeps no extra row columns', () => {
		const row = {
			kind: 'car_damage' as const,
			funding: 'both' as const,
			title: 'Bumper',
			description: '',
			amount_cents: 90000,
			incident_on: '2026-10-20',
			payee_id: 'p1',
			asset_id: null,
			status: 'draft',
			member_id: 'm1'
		};
		const { status: _s, member_id: _m, ...draft } = row;
		expect(asPeopleOnly(row)).toEqual({ ...draft, funding: 'people' });
	});
});

describe('validateDraft', () => {
	it('turns a good draft into the row, dollars into cents', () => {
		expect(validateDraft(good, '2026-10-31')).toEqual({
			ok: true,
			values: {
				kind: 'car_damage',
				funding: 'people',
				title: 'Rear bumper after a crash',
				description: 'Hit at a light.',
				amount_cents: 125050,
				incident_on: '2026-10-20',
				payee_id: null,
				asset_id: 'car-1'
			}
		});
	});

	it('drops the car on a home request', () => {
		const r = validateDraft({ ...good, kind: 'home_repair' }, '2026-10-31');
		expect(r.ok && r.values.asset_id).toBe(null);
	});

	it('requires a title of 1 to 120 characters, as the table does', () => {
		const blank = validateDraft({ ...good, title: '   ' }, '2026-10-31');
		expect(blank.ok === false && blank.problems.title).toMatch(/short title/);
		expect(validateDraft({ ...good, title: 'x'.repeat(120) }, '2026-10-31').ok).toBe(true);
		const long = validateDraft({ ...good, title: 'x'.repeat(121) }, '2026-10-31');
		expect(long.ok === false && long.problems.title).toMatch(/120 characters. It’s 121/);
	});

	it('counts characters the way Postgres does, not UTF-16 units', () => {
		expect(charCount('🚗')).toBe(1);
		expect(validateDraft({ ...good, title: '🚗'.repeat(120) }, '2026-10-31').ok).toBe(true);
	});

	it('caps the description at 5,000 characters', () => {
		expect(validateDraft({ ...good, description: 'a'.repeat(5000) }, '2026-10-31').ok).toBe(true);
		const r = validateDraft({ ...good, description: 'a'.repeat(5001) }, '2026-10-31');
		expect(r.ok === false && r.problems.description).toMatch(/5,000/);
	});

	it('needs an amount above zero in dollars and cents', () => {
		for (const amount of ['', '0', '0.00', '-5', '12.345', 'abc']) {
			expect(validateDraft({ ...good, amount }, '2026-10-31').ok, amount).toBe(false);
		}
		const r = validateDraft({ ...good, amount: '$2,400' }, '2026-10-31');
		expect(r.ok && r.values.amount_cents).toBe(240000);
	});

	it('refuses a comma decimal instead of reading 12,50 as $1,250', () => {
		const r = validateDraft({ ...good, amount: '12,50' }, '2026-10-31');
		expect(r.ok).toBe(false);
		expect(r.ok === false && r.problems.amount).toMatch(/dot for cents/);
	});

	it('refuses an incident date after the latest the table accepts', () => {
		expect(validateDraft({ ...good, incidentOn: '2026-10-31' }, '2026-10-31').ok).toBe(true);
		const r = validateDraft({ ...good, incidentOn: '2026-11-01' }, '2026-10-31');
		expect(r.ok === false && r.problems.incidentOn).toMatch(/can’t be later/);
		expect(validateDraft({ ...good, incidentOn: '2026-02-30' }, '2026-10-31').ok).toBe(false);
		expect(validateDraft({ ...good, incidentOn: '' }, '2026-10-31').ok).toBe(false);
	});

	it('rejects unknown kinds and funding', () => {
		const r = validateDraft({ ...good, kind: 'boat', funding: 'bank' }, '2026-10-31');
		expect(r.ok === false && Object.keys(r.problems).sort()).toEqual(['funding', 'kind']);
	});

	it('round-trips a stored draft through the form', () => {
		const r = validateDraft(good, '2026-10-31');
		if (!r.ok) throw new Error('expected ok');
		expect(validateDraft(draftToInput(r.values), '2026-10-31')).toEqual(r);
		expect(draftToInput({ ...r.values, amount_cents: 240000 }).amount).toBe('2400');
	});
});

describe('latestIncidentDate', () => {
	it('is the UTC day the draft was started, for an edit', () => {
		expect(latestIncidentDate(new Date('2026-10-31T12:00:00Z'), '2026-10-25T23:30:00Z')).toBe('2026-10-25');
	});

	it('is never later than today in UTC, which the database uses', () => {
		expect(latestIncidentDate(new Date('2026-10-31T12:00:00Z')) <= '2026-10-31').toBe(true);
	});
});

describe('isIsoDate', () => {
	it('accepts real dates only', () => {
		expect(isIsoDate('2024-02-29')).toBe(true);
		expect(isIsoDate('2026-02-29')).toBe(false);
		expect(isIsoDate('10/31/2026')).toBe(false);
	});
});

describe('payeeKindsFor', () => {
	it('names the payee that fits the request', () => {
		expect(payeeKindsFor('car_deductible')).toEqual(['repair_shop']);
		expect(payeeKindsFor('home_repair')).toEqual(['contractor']);
		expect(payeeKindsFor('down_payment')).toEqual(['lender', 'seller', 'title_company']);
	});
});

describe('validatePayee', () => {
	it('checks the columns the payees table checks', () => {
		expect(validatePayee({ kind: 'contractor', legalName: ' Bay Roofing ', region: 'CA' })).toEqual({
			ok: true,
			values: { kind: 'contractor', legal_name: 'Bay Roofing', region: 'CA' }
		});
		const bad = validatePayee({ kind: 'bank', legalName: '', region: 'ca' });
		expect(bad.ok === false && Object.keys(bad.problems).sort()).toEqual(['kind', 'legalName', 'region']);
		expect(validatePayee({ kind: 'lender', legalName: 'x'.repeat(201), region: 'NY' }).ok).toBe(false);
	});
});

describe('appealReasonProblem', () => {
	it('matches the 10 to 2,000 character check', () => {
		expect(appealReasonProblem('too short')).toMatch(/at least 10/);
		expect(appealReasonProblem('Ten chars!')).toBe(null);
		expect(appealReasonProblem('x'.repeat(2000))).toBe(null);
		expect(appealReasonProblem('x'.repeat(2001))).toMatch(/2,000/);
	});
});

describe('fundForKind', () => {
	// The mapping is what decides which fund's rules price a request: the
	// fund's own minimum score, band, inspection floor and waiting period. The
	// schema side is pinned by pgTAP `fund_for_kind_test`.
	it('the two car kinds draw on the protection fund', () => {
		expect(fundForKind('car_damage')).toBe('protection');
		expect(fundForKind('car_deductible')).toBe('protection');
	});

	it('every other kind draws on the repair fund', () => {
		expect(fundForKind('home_repair')).toBe('home_fund');
		expect(fundForKind('down_payment')).toBe('home_fund');
		expect(fundForKind('mortgage_gap')).toBe('home_fund');
		expect(fundForKind('loan_payoff')).toBe('home_fund');
	});

	it('the fund and the car test never disagree', () => {
		for (const { kind } of REQUEST_KINDS) {
			expect(isCarKind(kind)).toBe(fundForKind(kind) === 'protection');
		}
	});
});
