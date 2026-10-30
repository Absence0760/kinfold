import adapter from '@sveltejs/adapter-static';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

/**
 * Static only — no Node server. Unlike project-stocks (an auth-gated SPA), this
 * is a public marketing site, so every route is prerendered to real HTML at
 * build time (`src/routes/+layout.ts`): readable without JavaScript and
 * indexable by search engines. S3 + CloudFront can serve `build/` as-is.
 *
 * @type {import('@sveltejs/kit').Config}
 */
export default {
	preprocess: vitePreprocess(),
	kit: {
		adapter: adapter({ precompress: false })
	}
};
