import { describe, expect, it } from 'vitest';
import { monthsWord, ordinal } from './words.ts';

describe('words', () => {
	it('writes ordinals', () => {
		expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 28].map(ordinal)).toEqual([
			'1st',
			'2nd',
			'3rd',
			'4th',
			'11th',
			'12th',
			'13th',
			'21st',
			'22nd',
			'23rd',
			'28th'
		]);
	});

	it('writes months', () => {
		expect(monthsWord(1)).toBe('1 month');
		expect(monthsWord(3)).toBe('3 months');
	});
});
