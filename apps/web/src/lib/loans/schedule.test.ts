import fc from 'fast-check';
import { describe, expect, it } from 'vitest';
import { formatCents } from '#lib/dashboard/format.ts';
import { dayAfter, describeSplit, firstDueOn, moveToPaymentDay, planSchedule, scheduleProblem, scheduleTotal } from './schedule.ts';

describe('planSchedule mirrors set_loan_schedule', () => {
	it('splits the seed loan into 7 × $100 on the 15th', () => {
		const rows = planSchedule(70000, 7, '2026-11-15', 15);
		expect(rows.map((r) => r.amountCents)).toEqual(Array(7).fill(10000));
		expect(rows.map((r) => r.dueOn)).toEqual([
			'2026-11-15',
			'2026-12-15',
			'2027-01-15',
			'2027-02-15',
			'2027-03-15',
			'2027-04-15',
			'2027-05-15'
		]);
	});

	it('gives the remainder to the last installment', () => {
		const rows = planSchedule(100000, 3, '2026-11-01', 1);
		expect(rows.map((r) => r.amountCents)).toEqual([33333, 33333, 33334]);
		expect(scheduleTotal(rows)).toBe(100000);
	});

	it('starts in the next month when the first date is past the payment day', () => {
		expect(firstDueOn('2026-11-20', 15)).toBe('2026-12-15');
		expect(firstDueOn('2026-11-15', 15)).toBe('2026-11-15');
		expect(firstDueOn('2026-11-02', 15)).toBe('2026-11-15');
		expect(firstDueOn('2026-12-31', 28)).toBe('2027-01-28');
	});

	it('refuses what the database refuses', () => {
		expect(scheduleProblem(70000, 0)).toMatch(/1 to 480/);
		expect(scheduleProblem(70000, 481)).toMatch(/1 to 480/);
		expect(scheduleProblem(70000, 2.5)).toMatch(/1 to 480/);
		expect(scheduleProblem(5, 6)).toMatch(/more installments than there are cents/);
		expect(scheduleProblem(6, 6)).toBeNull();
		expect(planSchedule(5, 6, '2026-11-01', 1)).toEqual([]);
		expect(planSchedule(0, 1, '2026-11-01', 1)).toEqual([]);
	});

	it('moves an installment to a new payment day in the same month', () => {
		expect(moveToPaymentDay('2026-11-15', 1)).toBe('2026-11-01');
		expect(moveToPaymentDay('2027-02-03', 28)).toBe('2027-02-28');
	});

	it('finds the day after, across month and year ends', () => {
		expect(dayAfter('2026-10-31')).toBe('2026-11-01');
		expect(dayAfter('2026-12-31')).toBe('2027-01-01');
		expect(dayAfter('2028-02-28')).toBe('2028-02-29');
	});

	it('describes the split in words', () => {
		expect(describeSplit(planSchedule(70000, 7, '2026-11-15', 15), formatCents)).toBe('7 monthly payments of $100');
		expect(describeSplit(planSchedule(100000, 3, '2026-11-01', 1), formatCents)).toBe(
			'2 monthly payments of $333.33, then $333.34'
		);
		expect(describeSplit(planSchedule(500, 1, '2026-11-01', 1), formatCents)).toBe('One payment of $5');
		expect(describeSplit([], formatCents)).toBe('');
	});
});

describe('planSchedule properties', () => {
	const date = fc
		.record({
			y: fc.integer({ min: 2026, max: 2040 }),
			m: fc.integer({ min: 1, max: 12 }),
			d: fc.integer({ min: 1, max: 28 })
		})
		.map(({ y, m, d }) => `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`);
	const input = fc.record({
		principal: fc.integer({ min: 1, max: 1_000_000_000 }),
		months: fc.integer({ min: 1, max: 480 }),
		first: date,
		day: fc.integer({ min: 1, max: 28 })
	});

	it('always sums to exactly the principal: no interest, nothing lost to rounding', () => {
		fc.assert(
			fc.property(input, ({ principal, months, first, day }) => {
				const rows = planSchedule(principal, months, first, day);
				if (scheduleProblem(principal, months)) return rows.length === 0;
				return rows.length === months && scheduleTotal(rows) === principal;
			}),
			{ numRuns: 2000 }
		);
	});

	it('uses whole cents above zero, equal until a last one that is never smaller', () => {
		fc.assert(
			fc.property(input, ({ principal, months, first, day }) => {
				const amounts = planSchedule(principal, months, first, day).map((r) => r.amountCents);
				const each = amounts[0];
				return (
					amounts.every((a) => Number.isInteger(a) && a > 0) &&
					amounts.slice(0, -1).every((a) => a === each) &&
					(amounts.length === 0 || amounts[amounts.length - 1] >= each)
				);
			})
		);
	});

	it('puts every installment on the payment day, a month apart, never before the date asked', () => {
		const monthIndex = (d: string) => Number(d.slice(0, 4)) * 12 + Number(d.slice(5, 7));
		fc.assert(
			fc.property(input, ({ principal, months, first, day }) => {
				const rows = planSchedule(principal, months, first, day);
				return rows.every(
					(r, i) =>
						Number(r.dueOn.slice(8)) === day &&
						r.dueOn >= first &&
						(i === 0 || monthIndex(r.dueOn) - monthIndex(rows[i - 1].dueOn) === 1)
				);
			})
		);
	});
});
