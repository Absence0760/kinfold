<script lang="ts">
	import type { ScoreView } from '#lib/review/queue.ts';

	let { score, id }: { score: ScoreView | null; id: string } = $props();
</script>

<section class="score" aria-labelledby="{id}-score">
	<h4 id="{id}-score">Legitimacy score</h4>
	{#if score}
		<p class="value"><strong>{score.score}</strong><span> / 100</span></p>
		{#if score.reasons.length > 0}
			<ul class="reasons" aria-label="Why this score">
				{#each score.reasons as reason, i (i)}
					<li>{reason}</li>
				{/each}
			</ul>
		{:else}
			<p class="muted">This score came without reasons. Don't lean on it.</p>
		{/if}
		<p class="muted small">Model version {score.modelVersion}. The score advises; it never refuses.</p>
	{:else}
		<p class="muted">Not scored yet.</p>
	{/if}
</section>

<style>
	.score {
		background: var(--surface-2);
		border-radius: 10px;
		padding: 14px 16px;
		display: grid;
		gap: 6px;
	}

	h4 {
		font-size: 13px;
		font-weight: 700;
		letter-spacing: 0.06em;
		text-transform: uppercase;
		color: var(--muted);
		margin: 0;
	}

	.value strong {
		font-size: 28px;
		line-height: 1;
	}

	.value span {
		color: var(--muted);
	}

	.reasons {
		margin: 0;
		padding-left: 20px;
	}

	.muted {
		color: var(--muted);
	}

	.small {
		font-size: 13px;
	}
</style>
