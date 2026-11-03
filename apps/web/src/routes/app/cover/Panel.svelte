<script lang="ts">
	// Shared chrome for the cover console's cards: one card per action, styled
	// like the loan console's panels.
	import type { Snippet } from 'svelte';

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
	}
</style>
