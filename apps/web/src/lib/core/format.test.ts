import { describe, expect, it } from 'vitest';
import { formatUsd, formatUsdShort } from './format';

describe('formatUsd', () => {
	it('rounds to whole dollars with separators', () => {
		expect(formatUsd(2528.27)).toBe('$2,528');
	});
});

describe('formatUsdShort', () => {
	it('uses k for thousands and M for millions', () => {
		expect(formatUsdShort(510_177)).toBe('$510k');
		expect(formatUsdShort(1_250_000)).toBe('$1.3M');
		expect(formatUsdShort(2_000_000)).toBe('$2M');
		expect(formatUsdShort(950)).toBe('$950');
	});
});
