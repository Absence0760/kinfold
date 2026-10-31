import { describe, expect, it } from 'vitest';
import { safeNext, signinUrl } from './next';

describe('safeNext', () => {
	it('keeps paths inside the member area', () => {
		expect(safeNext('/app/invite/abc')).toBe('/app/invite/abc');
		expect(safeNext('/app?tab=loans')).toBe('/app?tab=loans');
		expect(safeNext('/app')).toBe('/app');
	});

	it('falls back to /app for anything else', () => {
		for (const bad of [null, undefined, '', '/', '/signin', '/apple', '//evil.example', 'https://evil.example/app', '/app\\..\\x']) {
			expect(safeNext(bad)).toBe('/app');
		}
	});
});

describe('signinUrl', () => {
	it('carries the page and its query through sign-in', () => {
		expect(signinUrl(new URL('http://localhost/app/invite/t1?x=1'))).toBe(
			'/signin?next=%2Fapp%2Finvite%2Ft1%3Fx%3D1'
		);
		expect(signinUrl(new URL('http://localhost/app'))).toBe('/signin');
	});
});
