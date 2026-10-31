<script lang="ts">
	import { formatUsd } from '#lib/core/format.ts';

	// A sample damage request, as it would appear on the members-only board.
	const request = {
		title: 'Rear-ended at a stop light',
		kind: 'Auto damage',
		amount: 2_840,
		score: 96,
		evidence: ['Police report', '6 photos', 'Shop estimate'],
		sources: [
			{ label: 'Community pool', amount: 2_040 },
			{ label: 'Two friends', amount: 800 }
		]
	};
	const raised = request.sources.reduce((sum, s) => sum + s.amount, 0);
</script>

<section class="hero">
	<div class="container hero-grid">
		<div>
			<p class="eyebrow">A member-owned cooperative</p>
			<h1>When life goes wrong, ask the people around you, not a profit margin.</h1>
			<p class="lead">
				Crashed your car? Need help with a home? Post a request, upload your evidence, and get a
				legitimacy score. Then your family, friends or the Kinfold community pay it. No interest. No
				late fees. Ever.
			</p>
			<div class="actions">
				<a class="btn btn-primary" href="#requests">How a request works</a>
				<a class="btn btn-ghost" href="#board">See the request board</a>
			</div>
		</div>

		<aside class="request-card" aria-label="Example request">
			<div class="row">
				<span class="kind">{request.kind}</span>
				<span class="score" title="Legitimacy score">{request.score}<small>%</small></span>
			</div>
			<h2>{request.title}</h2>
			<p class="amount">{formatUsd(request.amount)} requested</p>
			<ul class="evidence">
				{#each request.evidence as item (item)}
					<li>{item}</li>
				{/each}
			</ul>
			<div class="bar" role="img" aria-label="Fully funded">
				<span style:width="{(raised / request.amount) * 100}%"></span>
			</div>
			<ul class="sources">
				{#each request.sources as s (s.label)}
					<li><span>{s.label}</span><strong>{formatUsd(s.amount)}</strong></li>
				{/each}
			</ul>
			<p class="foot">Funded in 3 days. Paid straight to the repair shop.</p>
		</aside>
	</div>
</section>

<style>
	.hero {
		padding: 96px 0 88px;
		background:
			radial-gradient(1000px 400px at 85% 0%, var(--accent-soft), transparent 70%),
			radial-gradient(700px 300px at 0% 100%, var(--warm-soft), transparent 70%);
	}

	.hero-grid {
		display: grid;
		grid-template-columns: 1.3fr 1fr;
		gap: 56px;
		align-items: center;
	}

	h1 {
		font-size: clamp(36px, 5.4vw, 56px);
		letter-spacing: -0.02em;
	}

	.lead {
		color: var(--muted);
		font-size: 19px;
		margin-top: 20px;
		max-width: 560px;
	}

	.actions {
		display: flex;
		gap: 12px;
		margin-top: 32px;
		flex-wrap: wrap;
	}

	.request-card {
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: 20px;
		padding: 28px;
		box-shadow: var(--shadow);
	}

	.row {
		display: flex;
		justify-content: space-between;
		align-items: center;
	}

	.kind {
		font-size: 12px;
		font-weight: 700;
		padding: 3px 10px;
		border-radius: 999px;
		background: var(--warm-soft);
		color: var(--warm);
	}

	.score {
		font-size: 30px;
		font-weight: 800;
		color: var(--accent);
		letter-spacing: -0.02em;
	}

	.score small {
		font-size: 16px;
	}

	h2 {
		font-size: 22px;
		margin-top: 14px;
	}

	.amount {
		color: var(--muted);
		margin-top: 4px;
	}

	.evidence {
		list-style: none;
		padding: 0;
		margin: 16px 0 0;
		display: flex;
		flex-wrap: wrap;
		gap: 8px;
	}

	.evidence li {
		font-size: 13px;
		padding: 4px 10px;
		border-radius: 8px;
		background: var(--surface-2);
	}

	.bar {
		height: 8px;
		border-radius: 999px;
		background: var(--surface-2);
		margin: 22px 0 14px;
		overflow: hidden;
	}

	.bar span {
		display: block;
		height: 100%;
		background: var(--accent);
	}

	.sources {
		list-style: none;
		padding: 0;
		margin: 0;
		display: grid;
		gap: 6px;
		font-size: 15px;
	}

	.sources li {
		display: flex;
		justify-content: space-between;
	}

	.sources span {
		color: var(--muted);
	}

	.foot {
		margin-top: 16px;
		padding-top: 14px;
		border-top: 1px solid var(--border);
		font-size: 14px;
		color: var(--muted);
	}

	@media (max-width: 860px) {
		.hero {
			padding: 64px 0;
		}

		.hero-grid {
			grid-template-columns: 1fr;
			gap: 36px;
		}
	}
</style>
