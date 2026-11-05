/**
 * One-click demo sign-in for local development.
 *
 * These are the people `apps/backend/supabase/seed.sql` creates. Their shared
 * password grants access to nothing outside a Supabase container on this laptop,
 * which is why it can be committed (CLAUDE.md, local-dev env). Keep this list in
 * step with the seed's header comment.
 */
export interface DemoAccount {
	email: string;
	name: string;
	roles: string;
	summary: string;
}

export const DEMO_PASSWORD = 'testtest';

export const DEMO_ACCOUNTS: readonly DemoAccount[] = [
	{
		email: 'maria@test.com',
		name: 'Maria',
		roles: 'Member · CA',
		summary: 'A draft home repair, and a car deductible funded by her brother with a 0% loan.'
	},
	{
		email: 'sam@test.com',
		name: 'Sam',
		roles: 'Member · CA',
		summary: 'Maria’s brother and lender. Has an open car damage request on the board.'
	},
	{
		email: 'james@test.com',
		name: 'James',
		roles: 'Member + reviewer · NY',
		summary: 'Reviews requests from other states, so he can review Maria and Sam.'
	},
	{
		email: 'priya@test.com',
		name: 'Priya',
		roles: 'Member + appeal panel · TX',
		summary: 'A car damage request already paid from the community pool.'
	},
	{
		email: 'kofi@test.com',
		name: 'Kofi',
		roles: 'Member + reviewer · IL',
		summary: 'A second reviewer, with a Home Fund repair half granted by the pool and a Home Fund loan.'
	},
	{
		email: 'ben@test.com',
		name: 'Ben',
		roles: 'Member · TN',
		summary: 'Lends to several friends at 0%: loans on time, paused, behind, repaid and defaulted.'
	},
	{
		email: 'nora@test.com',
		name: 'Nora',
		roles: 'New member · PA',
		summary: 'Joined three days ago; her identity check hasn’t come back yet.'
	}
];

/** Hosts that can only be a developer's own machine. */
const LOOPBACK_HOSTS = new Set(['localhost', '127.0.0.1', '::1']);

/**
 * Whether demo sign-in may be offered.
 *
 * Needs a dev build AND a loopback Supabase URL. The host check is what stops a
 * dev build accidentally pointed at a real project from sending the seeded
 * credentials to it; the dev check keeps the list out of production bundles.
 */
export function demoSignInAllowed(isDev: boolean, supabaseUrl: string): boolean {
	if (!isDev) return false;
	let host: string;
	try {
		host = new URL(supabaseUrl).hostname;
	} catch {
		return false;
	}
	if (host.startsWith('[') && host.endsWith(']')) host = host.slice(1, -1);
	return LOOPBACK_HOSTS.has(host);
}
