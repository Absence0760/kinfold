<script lang="ts">
	import type { Tone } from '#lib/dashboard/labels.ts';

	// Same look as the badges on the member home: the label always says the
	// status in words, and the icon differs by tone, so colour is never alone.
	let { tone, label }: { tone: Tone; label: string } = $props();
</script>

<span class="badge {tone}">
	<svg viewBox="0 0 12 12" width="12" height="12" aria-hidden="true">
		{#if tone === 'action'}
			<path d="M6 1 11 10H1z" />
		{:else if tone === 'progress'}
			<circle cx="6" cy="6" r="4.5" fill="none" stroke-width="2" />
		{:else if tone === 'done'}
			<path d="M2 6.5 5 9.5 10 3" fill="none" stroke-width="2" />
		{:else}
			<rect x="2" y="5" width="8" height="2" />
		{/if}
	</svg>
	{label}
</span>

<style>
	.badge {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		padding: 3px 10px;
		border-radius: 999px;
		font-size: 13px;
		font-weight: 700;
		white-space: nowrap;
		border: 1px solid currentColor;
		align-self: flex-start;
	}

	.badge svg {
		fill: currentColor;
		stroke: currentColor;
		flex: none;
	}

	/* --warm on --warm-soft is under 4.5:1 for small text, so the words stay
	   --text and only the border and icon carry the warm colour. */
	.badge.action {
		color: var(--text);
		background: var(--warm-soft);
		border-color: var(--warm);
	}

	.badge.action svg {
		fill: var(--warm);
		stroke: var(--warm);
	}

	.badge.progress {
		color: var(--accent);
		background: var(--accent-soft);
	}

	.badge.done {
		color: var(--accent-contrast);
		background: var(--accent);
		border-color: var(--accent);
	}

	.badge.closed {
		color: var(--muted);
		background: var(--surface-2);
	}
</style>
