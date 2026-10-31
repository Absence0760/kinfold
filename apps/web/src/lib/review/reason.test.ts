import { describe, expect, it } from 'vitest';
import { REASON_MAX, REASON_MIN, cleanReason, reasonCounter, reasonProblem } from './reason';

describe('reasonProblem', () => {
	it('asks for a reason when empty or only whitespace', () => {
		expect(reasonProblem('')).toMatch(/Write the reason/);
		expect(reasonProblem('   \n ')).toMatch(/Write the reason/);
	});

	it('counts the trimmed text against the minimum, as the database will see it', () => {
		// 13 characters with the padding, 9 without: the database would refuse it.
		expect(reasonProblem('  too short  ')).toBe('Write at least 10 characters (1 more).');
	});

	it('accepts the exact bounds and refuses one past them', () => {
		expect(reasonProblem('a'.repeat(REASON_MIN))).toBe(null);
		expect(reasonProblem('a'.repeat(REASON_MIN - 1))).toBe('Write at least 10 characters (1 more).');
		expect(reasonProblem('a'.repeat(REASON_MAX))).toBe(null);
		expect(reasonProblem('a'.repeat(REASON_MAX + 1))).toBe('Keep it to 2,000 characters (1 over).');
	});
});

describe('cleanReason and reasonCounter', () => {
	it('trims what will be saved and counts it', () => {
		expect(cleanReason('  photos match  ')).toBe('photos match');
		expect(reasonCounter('  photos match  ')).toBe('12 / 2,000');
	});
});
