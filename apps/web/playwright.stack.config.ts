import { defineConfig, devices } from '@playwright/test';

// End-to-end tests of the member area (/signin's form, /app/*) against the
// local Supabase stack (docs/STACK.md "End-to-end tests"). Kept apart from
// playwright.config.ts so the public-site run still needs no Docker.
//
// Run through `pnpm test:web:e2e:stack` (bin/e2e-stack.sh): it resets the
// database to seed.sql and exports the stack's publishable key for the build.
// The specs change seeded data, so they run in one worker, file by file, in
// name order, and each spec only changes rows no other spec reads.
declare const process: { env: Record<string, string | undefined> };
const isCI = !!process.env.CI;

if (!process.env.PUBLIC_SUPABASE_ANON_KEY) {
	throw new Error(
		'No PUBLIC_SUPABASE_ANON_KEY: run these through `pnpm test:web:e2e:stack`, which resets the stack and reads its key.'
	);
}

export default defineConfig({
	testDir: './e2e-stack',
	fullyParallel: false,
	forbidOnly: isCI,
	// A flaky test is a bug in the app or the test (root CLAUDE.md).
	retries: 0,
	workers: 1,
	reporter: isCI ? [['list'], ['html', { open: 'never', outputFolder: 'playwright-report-stack' }]] : 'list',
	use: {
		// 7791, not 7790: this build carries the stack key, so it must never be
		// mistaken for (or reused as) the public run's unconfigured server.
		baseURL: 'http://localhost:7791',
		trace: 'retain-on-failure'
	},
	projects: [
		{ name: 'desktop', use: { ...devices['Desktop Chrome'] } },
		// One phone pass over the read-only flows (`*.read.spec.ts`): a member
		// on a phone is the common case, and the member nav rewraps under 560px.
		// The flows that change data run once, on desktop, so a second project
		// can't find its rows already changed by the first.
		{ name: 'phone', use: { ...devices['Pixel 7'] }, testMatch: /\.read\.spec\.ts$/ }
	],
	webServer: {
		command: 'pnpm build && pnpm preview --port 7791',
		url: 'http://localhost:7791',
		// Always a fresh build: a server left on 7791 may carry an older key.
		reuseExistingServer: false,
		stdout: 'ignore',
		stderr: 'pipe'
	}
});
