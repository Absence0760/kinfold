import { describe, expect, it } from 'vitest';
import { addMonths, formatCents, formatDay, localToday } from './format.ts';

describe('formatCents', () => {
	it('shows whole dollars without cents', () => {
		expect(formatCents(100000)).toBe('$1,000');
		expect(formatCents(0)).toBe('$0');
	});

	it('never rounds a payment that has cents', () => {
		expect(formatCents(9950)).toBe('$99.50');
		expect(formatCents(1)).toBe('$0.01');
	});

	it('rejects fractional cents', () => {
		expect(() => formatCents(10.5)).toThrow(RangeError);
	});
});

describe('formatDay', () => {
	it('formats a date column without shifting it by timezone', () => {
		expect(formatDay('2026-11-15')).toBe('Nov 15, 2026');
		expect(formatDay('2027-01-01')).toBe('Jan 1, 2027');
	});
});

describe('localToday', () => {
	it('uses the local calendar date', () => {
		expect(localToday(new Date(2026, 9, 31, 23, 30))).toBe('2026-10-31');
	});
});

describe('addMonths', () => {
	it('adds calendar months', () => {
		expect(addMonths('2026-11-15', 3)).toBe('2027-02-15');
		expect(addMonths('2026-11-15', -12)).toBe('2025-11-15');
	});

	it('clamps to the last day of a short month, like Postgres', () => {
		expect(addMonths('2027-01-31', 1)).toBe('2027-02-28');
		expect(addMonths('2028-01-31', 1)).toBe('2028-02-29');
	});
});
