<script lang="ts">
	import { allocatePool, type AllocationStatus } from '#lib/requests/allocation.ts';
	import { formatUsd } from '#lib/core/format.ts';

	// Sample damage requests. Illustration only.
	const requests = [
		{ id: 'r1', title: 'Rear-ended at a stop light', amount: 2_840, funded: 800, score: 96 },
		{ id: 'r2', title: 'Hail damage to roof and hood', amount: 1_950, funded: 0, score: 93 },
		{ id: 'r3', title: 'Hit a deer on the highway', amount: 3_400, funded: 0, score: 91 },
		{ id: 'r4', title: 'Parking-lot scrape, other driver paid half', amount: 1_560, funded: 780, score: 84 },
		{ id: 'r5', title: 'Side-swiped, other driver left', amount: 2_200, funded: 0, score: 81 },
		{ id: 'r6', title: 'Flood damage after a storm', amount: 5_600, funded: 0, score: 74 },
		{ id: 'r7', title: 'Single-car crash, no photos yet', amount: 6_900, funded: 0, score: 52 }
	];

	const labels: Record<AllocationStatus, string> = {
		funded: 'Funded',
		partial: 'Partly funded',
		waiting: 'Waiting',
		'needs-review': 'Needs more evidence'
	};

	let pool = $state(8_000);
	const result = $derived(allocatePool(requests, pool));
	const grants = $derived(new Map(result.allocations.map((a) => [a.id, a])));
</script>

<section class="section section-alt" id="board">
	<div class="container">
		<p class="eyebrow">The request board</p>
		<h2 class="section-title">Ranked by evidence, not by who tells the saddest story.</h2>
		<p class="section-lead">
			The board is visible to verified members only, and shows each request's state or region and
			month, never names or towns. The community repair fund, paid for by gifts, fills the highest
			band first (90% and up), every request in it at the same time, then moves down. Below 70%, a
			person reviews it and asks for more evidence. Insured cover is different: a covered claim is
			always paid in full. Move the slider to see how this month's repair fund is shared out.
		</p>

		<label class="pool">
			<span>This month's repair fund <strong>{formatUsd(pool)}</strong></span>
			<input type="range" min="0" max="25000" step="500" bind:value={pool} />
		</label>

		<ul class="board" aria-live="polite">
			{#each requests as r (r.id)}
				{@const a = grants.get(r.id)!}
				{@const raised = r.funded + a.grant}
				<li class={a.status}>
					<span class="score">{r.score}%</span>
					<div class="body">
						<p class="title">{r.title}</p>
						<div class="bar">
							<span class="friends" style:width="{(r.funded / r.amount) * 100}%"></span>
							<span class="pool-share" style:width="{(a.grant / r.amount) * 100}%"></span>
						</div>
						<p class="meta">
							{formatUsd(raised)} of {formatUsd(r.amount)}
							{#if r.funded > 0}· {formatUsd(r.funded)} from friends{/if}
							{#if a.grant > 0}· {formatUsd(a.grant)} from the fund{/if}
						</p>
					</div>
					<span class="status">{labels[a.status]}</span>
				</li>
			{/each}
		</ul>
		<p class="note">
			Illustration only. Bands, thresholds and amounts are design targets, not live data. Left in
			the fund: {formatUsd(result.remainingPool)}.
		</p>
	</div>
</section>

<style>
	.pool {
		display: grid;
		gap: 8px;
		margin-top: 32px;
		max-width: 520px;
	}

	.pool span {
		display: flex;
		justify-content: space-between;
		font-size: 15px;
	}

	input[type='range'] {
		accent-color: var(--accent);
	}

	.board {
		list-style: none;
		margin: 24px 0 0;
		padding: 0;
		display: grid;
		gap: 10px;
	}

	.board li {
		display: grid;
		grid-template-columns: 64px 1fr 150px;
		gap: 16px;
		align-items: center;
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius);
		padding: 16px 20px;
	}

	.score {
		font-size: 22px;
		font-weight: 800;
		color: var(--accent);
	}

	.needs-review .score {
		color: var(--muted);
	}

	.title {
		font-weight: 600;
	}

	.bar {
		display: flex;
		height: 7px;
		border-radius: 999px;
		background: var(--surface-2);
		margin: 8px 0 6px;
		overflow: hidden;
	}

	.friends {
		background: var(--warm);
	}

	.pool-share {
		background: var(--accent);
		transition: width 0.2s ease;
	}

	.meta {
		font-size: 13px;
		color: var(--muted);
	}

	.status {
		justify-self: end;
		font-size: 12px;
		font-weight: 700;
		padding: 4px 10px;
		border-radius: 999px;
		background: var(--surface-2);
		color: var(--muted);
		white-space: nowrap;
	}

	.funded .status {
		background: var(--accent-soft);
		color: var(--accent);
	}

	.partial .status {
		background: var(--warm-soft);
		color: var(--warm);
	}

	.note {
		margin-top: 14px;
		font-size: 13px;
		color: var(--muted);
	}

	@media (max-width: 640px) {
		.board li {
			grid-template-columns: 48px 1fr;
		}

		.status {
			grid-column: 2;
			justify-self: start;
		}
	}
</style>
