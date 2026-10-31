import adapter from '@sveltejs/adapter-static';
import { sveltekit } from '@sveltejs/kit/vite';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';
import { defineConfig } from 'vitest/config';

export default defineConfig({
	// SvelteKit 3 takes its config here; svelte.config.js is no longer read,
	// and the old `$lib` alias is the `#lib/*` subpath import in package.json.
	// Static only — no Node server. Unlike project-stocks (an auth-gated SPA),
	// this is a public marketing site, so every route is prerendered to real
	// HTML at build time (`src/routes/+layout.ts`): readable without JavaScript
	// and indexable by search engines. S3 + CloudFront can serve `build/` as-is.
	plugins: [
		sveltekit({
			preprocess: vitePreprocess(),
			// fallback: the member area (/signin, /app/*) is a browser-only SPA,
			// served from 200.html for any path that wasn't prerendered.
			adapter: adapter({ precompress: false, fallback: '200.html' })
		})
	],

	// 7790 is this project's web port (docs/STACK.md) — clear of project-stocks'
	// 7777. strictPort so a second instance fails loudly instead of drifting.
	server: { port: 7790, strictPort: true },
	preview: { port: 7790, strictPort: true },

	test: {
		// Tests live beside the module they cover, so the glob has to recurse.
		include: ['src/**/*.{test,spec}.{js,ts}'],
		environment: 'node'
	}
});
