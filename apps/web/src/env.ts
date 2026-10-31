import { defineEnvVars } from '@sveltejs/kit/env';

/**
 * Environment variables (Kit 3's `src/env.ts`; read through `$app/env/public`).
 *
 * Both are public and static: the member area is a browser-only SPA, so the
 * values are inlined at build time. Defaults point at the local stack so a fresh
 * clone runs with nothing set. The URL comes from the committed
 * `.env.development`; the publishable key is NOT written to any file:
 * `bin/dev-run-web.sh` reads it out of `supabase status` at launch, and a
 * production build gets it from the deploy pipeline.
 */
export const variables = defineEnvVars({
	PUBLIC_SUPABASE_URL: {
		public: true,
		static: true,
		description: 'Supabase API URL. Local stack by default (docs/STACK.md).',
		schema: (value) => value || 'http://127.0.0.1:54721'
	},
	PUBLIC_SUPABASE_ANON_KEY: {
		public: true,
		static: true,
		description: 'Supabase publishable key. Empty means the member area shows a setup message.',
		schema: (value) => value ?? ''
	}
});
