import { describe, expect, it } from 'vitest';
import { explainCoverError } from './errors.ts';

describe('explainCoverError', () => {
	it('an unrecognised rule passes through rather than hiding', () => {
		expect(explainCoverError({ message: 'a rule nobody wrote before', code: '23514' }))
				.toEqual('a rule nobody wrote before');
	});

	it('a door with nothing to say answers with nothing', () => {
		expect(explainCoverError(null)).toEqual('');
	});

	it('the class is stated by the member who owns the vehicle', () => {
		expect(explainCoverError({
			message: 'the class is stated by the member who owns the vehicle',
			code: '42501'
		})).toEqual('The class on a vehicle is stated by the member who owns it.');
	});

	it('an asset that isn\u2019t the member\u2019s answers with the schema\u2019s words', () => {
		expect(explainCoverError({ message: 'asset not found, not yours, already removed, or not a vehicle' }))
				.toEqual('That vehicle isn\u2019t yours to class, it was retired, or it isn\u2019t a vehicle.');
	});
});
