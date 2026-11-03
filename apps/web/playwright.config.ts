import { defineConfig, devices } from '@playwright/test';

// End-to-end tests for the public, prerendered site (docs/STACK.md).
// They run against the production build served by `vite preview`, so they see
// exactly the HTML that ships, not the dev server's on-demand modules.
//
// The stack-dependent member-area flow (/signin's form and session check, /app/*) needs
// the local Supabase stack and is not covered here; see docs/STACK.md "End-to-end tests".
// /signin's no-stack ENTRY and the member area's no-stack redirect to it are covered
// (`e2e/signin.spec.ts`, `e2e/member-entry.spec.ts`), because neither path needs a stack.
// This file runs in Node, but the workspace has no @types/node (it would make
// Node globals typecheck in browser code under src/), so declare the one we use.
declare const process: { env: Record<string, string | undefined> };
const isCI = !!process.env.CI;

export default defineConfig({
	testDir: './e2e',
	fullyParallel: true,
	forbidOnly: isCI,
	// A flaky test is a bug in the app or the test: fix it, never retry it away
	// (root CLAUDE.md "Fix bugs at the source").
	retries: 0,
	workers: isCI ? 1 : undefined,
	reporter: isCI ? [['list'], ['html', { open: 'never' }]] : 'list',
	use: {
		baseURL: 'http://localhost:7790',
		trace: 'retain-on-failure'
	},
	projects: [
		// `*.desktop.spec.ts` runs only here, `*.phone.spec.ts` only on the
		// phone; every other spec runs on both.
		{ name: 'desktop', use: { ...devices['Desktop Chrome'] }, testIgnore: /\.phone\.spec\.ts$/ },
		// Pixel 7 is 412px wide, under the 860px breakpoint where the nav
		// collapses into the "Menu" <details>.
		{ name: 'phone', use: { ...devices['Pixel 7'] }, testIgnore: /\.desktop\.spec\.ts$/ }
	],
	webServer: {
		command: 'pnpm build && pnpm preview',
		url: 'http://localhost:7790',
		reuseExistingServer: !isCI,
		stdout: 'ignore',
		stderr: 'pipe'
	}
});
