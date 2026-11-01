import { describe, expect, it } from 'vitest';
import { BoardLoadError, explainBoardError } from './errors.ts';

describe('explainBoardError', () => {
	it('tells a member whose session ended to sign in again', () => {
		expect(explainBoardError({ code: 'PGRST301', message: 'JWT expired' })).toMatch(/session has ended.*Sign in/);
		expect(explainBoardError({ message: 'JWT expired' })).toMatch(/session has ended/);
	});

	it('explains a permission refusal without the database wording', () => {
		const msg = explainBoardError({ code: '42501', message: 'permission denied for view board_requests' });
		expect(msg).toMatch(/Only verified members/);
		expect(msg).not.toMatch(/board_requests|permission denied/);
	});

	it('explains a lost connection', () => {
		expect(explainBoardError({ message: 'TypeError: Failed to fetch' })).toMatch(/Can’t reach Kinfold/);
		expect(explainBoardError({ message: 'Load failed' })).toMatch(/Can’t reach Kinfold/);
	});

	it('never shows an unknown database message', () => {
		const raw = 'column board_requests.secret does not exist';
		const msg = explainBoardError({ code: '42703', message: raw });
		expect(msg).not.toContain('board_requests');
		expect(msg).toMatch(/Try again/);
		expect(explainBoardError(null)).toMatch(/Try again/);
		expect(explainBoardError(undefined)).toMatch(/Try again/);
	});

	it('reads the code kept on a BoardLoadError', () => {
		const err = new BoardLoadError({ code: 'PGRST301', message: 'JWT expired' });
		expect(err).toBeInstanceOf(Error);
		expect(err.code).toBe('PGRST301');
		expect(explainBoardError(err)).toMatch(/session has ended/);
	});
});
