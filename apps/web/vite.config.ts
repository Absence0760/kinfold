import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vitest/config';

export default defineConfig({
	plugins: [sveltekit()],

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
