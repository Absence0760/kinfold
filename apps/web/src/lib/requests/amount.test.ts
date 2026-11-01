import { describe, expect, it } from 'vitest';
import { amountCents, amountEcho, parseAmount } from './amount';

describe('parseAmount', () => {
	it('reads US amounts into cents', () => {
		expect(amountCents('1250')).toBe(125000);
		expect(amountCents('$1,250')).toBe(125000);
		expect(amountCents('$ 1,250.5')).toBe(125050);
		expect(amountCents('1250.50')).toBe(125050);
		expect(amountCents('12,345,678.09')).toBe(1234567809);
		expect(amountCents('  0.01 ')).toBe(1);
	});

	it('never reads a comma decimal as thousands', () => {
		for (const s of ['12,50', '12,5', '0,50', '1.200,00', '1.234.567,8']) {
			const r = parseAmount(s);
			expect(r.ok, s).toBe(false);
			expect(!r.ok && r.problem, s).toMatch(/dot for cents/);
		}
	});

	it('refuses commas that are not between thousands', () => {
		for (const s of ['1,25,000', '12,3456', ',500', '1,250,', '1,2345.00']) {
			const r = parseAmount(s);
			expect(r.ok, s).toBe(false);
			expect(!r.ok && r.problem, s).toMatch(/between thousands/);
		}
	});

	it('refuses empty, zero, negative, too many decimals and words', () => {
		expect(parseAmount('')).toEqual({ ok: false, problem: expect.stringMatching(/how much/) });
		expect(parseAmount('0')).toEqual({ ok: false, problem: expect.stringMatching(/above zero/) });
		expect(parseAmount('0.00').ok).toBe(false);
		for (const s of ['-5', '12.345', 'abc', '1e5', '12.', '.5', '99999999999999999999']) {
			expect(parseAmount(s).ok, s).toBe(false);
		}
	});
});

describe('amountEcho', () => {
	it('says what was understood, or nothing', () => {
		expect(amountEcho('1,250')).toBe('That’s $1,250.');
		expect(amountEcho('12.5')).toBe('That’s $12.50.');
		expect(amountEcho('12,50')).toBe(null);
		expect(amountEcho('')).toBe(null);
	});
});
