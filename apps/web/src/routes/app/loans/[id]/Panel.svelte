<script lang="ts">
	import type { Snippet } from 'svelte';

	// Shared chrome for the loan actions: one card per action, with the form
	// controls, previews and confirmation steps styled the same way.
	let { id, title, intro, children }: { id: string; title: string; intro?: string; children: Snippet } = $props();
</script>

<section class="panel" aria-labelledby={id}>
	<h3 {id}>{title}</h3>
	{#if intro}<p class="intro">{intro}</p>{/if}
	{@render children()}
</section>

<style>
	.panel {
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius);
		padding: 18px 20px;
		display: grid;
		gap: 12px;
		min-width: 0;
	}

	h3 {
		font-size: 18px;
	}

	.intro {
		color: var(--muted);
		font-size: 15px;
	}

	.panel :global(form),
	.panel :global(.step) {
		display: grid;
		gap: 12px;
		min-width: 0;
	}

	.panel :global(.field) {
		display: grid;
		gap: 4px;
		justify-items: start;
	}

	.panel :global(.field > label:first-child),
	.panel :global(legend) {
		font-weight: 600;
		font-size: 15px;
	}

	.panel :global(fieldset) {
		border: 0;
		margin: 0;
		padding: 0;
		display: grid;
		gap: 8px;
		min-width: 0;
	}

	.panel :global(input:not([type='radio'])),
	.panel :global(select),
	.panel :global(textarea) {
		font: inherit;
		font-size: 16px;
		color: var(--text);
		background: var(--bg);
		border: 1px solid var(--border);
		border-radius: 8px;
		padding: 8px 10px;
		min-height: 44px;
		max-width: 100%;
	}

	.panel :global(textarea) {
		width: 100%;
	}

	.panel :global(.option) {
		display: flex;
		gap: 10px;
		align-items: flex-start;
		padding: 10px 12px;
		border: 1px solid var(--border);
		border-radius: 10px;
		font-size: 15px;
		cursor: pointer;
	}

	.panel :global(.option:has(input:checked)) {
		border-color: var(--accent);
		background: var(--accent-soft);
	}

	.panel :global(.option:has(input:disabled)) {
		cursor: not-allowed;
		opacity: 0.7;
	}

	.panel :global(.option input) {
		margin-top: 2px;
		flex: none;
		width: 20px;
		height: 20px;
		accent-color: var(--accent);
	}

	.panel :global(.option:has(input:focus-visible)) {
		outline: 3px solid var(--warm);
		outline-offset: 2px;
	}

	.panel :global(.hint),
	.panel :global(.sub) {
		color: var(--muted);
		font-size: 14px;
	}

	.panel :global(.sub) {
		display: block;
	}

	.panel :global(.problem) {
		color: var(--warm);
		font-weight: 600;
		font-size: 14px;
	}

	.panel :global(.preview) {
		background: var(--surface-2);
		border-radius: 10px;
		padding: 12px 14px;
		font-size: 15px;
		display: grid;
		gap: 6px;
		min-width: 0;
	}

	.panel :global(.preview ol),
	.panel :global(.preview ul),
	.panel :global(.terms) {
		margin: 0;
		padding-left: 20px;
		display: grid;
		gap: 2px;
	}

	.panel :global(.terms) {
		font-size: 15px;
		gap: 6px;
	}

	.panel :global(.confirm-title) {
		font-weight: 700;
		font-size: 16px;
	}

	.panel :global(.actions) {
		display: flex;
		flex-wrap: wrap;
		gap: 8px;
	}

	.panel :global(.btn) {
		padding: 9px 16px;
		font-size: 15px;
		min-height: 44px;
	}

	@media (max-width: 480px) {
		.panel :global(.actions .btn) {
			flex: 1 1 10rem;
		}
	}

	/* aria-disabled rather than disabled, so the button keeps focus and its reason
	   (aria-describedby) is still read; each handler guards the same state. */
	.panel :global(.btn[aria-disabled='true']) {
		opacity: 0.6;
		cursor: not-allowed;
	}

	.panel :global(.btn[aria-busy='true']) {
		cursor: progress;
	}

	/* Irreversible actions. --accent-contrast on --warm: 6.00:1 light (#fff on #a4471f),
	   6.75:1 dark (#0b1f16 on #e88a62). */
	.panel :global(.btn-warn) {
		background: var(--warm);
		border-color: var(--warm);
		color: var(--accent-contrast);
	}
</style>
