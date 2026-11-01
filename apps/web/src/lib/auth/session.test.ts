import { beforeEach, describe, expect, it, vi } from 'vitest';
import { LoadError } from './errors.ts';

type Res = { data: unknown; error: { message: string; code?: string } | null; status: number };

const state: { session: unknown; sessionError: unknown; members: Res; roles: Res } = {
	session: null,
	sessionError: null,
	members: { data: null, error: null, status: 200 },
	roles: { data: [], error: null, status: 200 }
};

function chain(result: () => Res) {
	const c: Record<string, unknown> = {};
	for (const m of ['select', 'eq']) c[m] = () => c;
	c.maybeSingle = () => Promise.resolve(result());
	c.then = (ok: (v: Res) => unknown, bad: (e: unknown) => unknown) => Promise.resolve(result()).then(ok, bad);
	return c;
}

// The real client needs the build-time env; this stands in for it.
vi.mock('#lib/supabase/client.ts', () => ({
	supabase: () => ({
		auth: {
			getSession: async () => ({ data: { session: state.session }, error: state.sessionError })
		},
		from: (table: string) => chain(() => (table === 'members' ? state.members : state.roles))
	})
}));

const { getSession, loadViewer } = await import('./session.ts');

const session = { user: { id: 'u1', email: 'maria@example.test' } };

beforeEach(() => {
	state.session = session;
	state.sessionError = null;
	state.members = { data: { id: 'u1', display_name: 'Maria' }, error: null, status: 200 };
	state.roles = { data: [{ role: 'member' }], error: null, status: 200 };
});

describe('loadViewer', () => {
	it('returns null when signed out', async () => {
		state.session = null;
		expect(await loadViewer()).toBeNull();
	});

	it('returns the member row and roles', async () => {
		const viewer = await loadViewer();
		expect(viewer?.member).toEqual({ id: 'u1', display_name: 'Maria' });
		expect(viewer?.roles).toEqual(['member']);
	});

	it('reports a missing member row as member: null', async () => {
		state.members = { data: null, error: null, status: 200 };
		expect((await loadViewer())?.member).toBeNull();
	});

	it('throws instead of reporting "no profile" when the member read fails', async () => {
		state.members = { data: null, error: { message: 'TypeError: Failed to fetch', code: '' }, status: 0 };
		const err = await loadViewer().catch((e: unknown) => e);
		expect(err).toBeInstanceOf(LoadError);
		expect(err).toMatchObject({ what: 'your member profile', status: 0 });
	});

	it('throws when the roles read fails', async () => {
		state.roles = { data: null, error: { message: 'JWT expired', code: 'PGRST301' }, status: 401 };
		await expect(loadViewer()).rejects.toMatchObject({ what: 'your member roles', code: 'PGRST301', status: 401 });
	});
});

describe('getSession', () => {
	it('throws when refreshing failed because the network did, so offline never reads as signed out', async () => {
		state.session = null;
		state.sessionError = Object.assign(new Error('Failed to fetch'), { name: 'AuthRetryableFetchError', status: 0 });
		await expect(getSession()).rejects.toThrow('Failed to fetch');
	});

	it('treats any other auth error as signed out', async () => {
		state.session = null;
		state.sessionError = Object.assign(new Error('Invalid Refresh Token'), { name: 'AuthApiError', status: 400 });
		expect(await getSession()).toBeNull();
	});
});
