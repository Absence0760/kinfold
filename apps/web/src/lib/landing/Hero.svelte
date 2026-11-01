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
			{ label: 'Deductible cover', amount: 1_000 },
			{ label: 'Repair fund', amount: 1_040 },
			{ label: 'Two friends', amount: 800 }
		]
	};
	const raised = request.sources.reduce((sum, s) => sum + s.amount, 0);
</script>

<section class="hero">
	<div class="container hero-grid">
		<div>
			<p class="status" role="note">
				<strong>Design preview.</strong> Kinfold isn't operating yet. Nothing here is an offer.
			</p>
			<p class="eyebrow">A member-owned cooperative, being built</p>
			<h1>When life goes wrong, ask the people around you, not a profit margin.</h1>
			<p class="lead">
				Crashed your car? Need help with a home? Post a request, upload your evidence, and get a
				legitimacy score. Then your family and friends pay it, and later the Kinfold community too.
				No interest. No late fees. Ever.
			</p>
			<p class="fine">
				Membership will be by invitation while Kinfold is in design. Where tax law requires a
				minimum rate on a family loan, Kinfold calculates and shows it, and sets it up to be
				forgiven as a gift.
			</p>
			<div class="actions">
				<a class="btn btn-primary" href="#requests">How a request works</a>
				<a class="btn btn-ghost" href="#board">See the request board</a>
			</div>
		</div>

		<aside class="request-card" aria-label="Example request">
			<div class="row">
				<span class="tag">Example · Phase 2</span>
				<span class="kind">{request.kind}</span>
			</div>
			<p class="score">
				<span class="score-label">Legitimacy score</span>
				<span class="score-value"
					><strong>{request.score}</strong> out of 100</span
				>
			</p>
			<p class="gloss">
				An evidence score: how complete and consistent the evidence is. It never decides whether
				you get help; only a person can say no.
			</p>
			<p class="card-title">{request.title}</p>
			<p class="amount">{formatUsd(request.amount)} requested</p>
			<ul class="evidence" aria-label="Evidence uploaded">
				{#each request.evidence as item (item)}
					<li>{item}</li>
				{/each}
			</ul>
			<div class="bar" role="img"
				aria-label="Fully funded: {formatUsd(raised)} of {formatUsd(request.amount)}">
				<span style:width="{(raised / request.amount) * 100}%"></span>
			</div>
			<ul class="sources" aria-label="Where the money came from">
				{#each request.sources as s (s.label)}
					<li><span>{s.label}</span><strong>{formatUsd(s.amount)}</strong></li>
				{/each}
			</ul>
			<p class="foot">
				Made-up example: funded in 3 days, paid straight to the repair shop. Deductible cover would
				pay the part of the bill you pay first. Separate from the sample board below, so the
				figures differ.
			</p>
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

	.status {
		display: inline-block;
		margin: 0 0 20px;
		padding: 10px 14px;
		border-left: 4px solid var(--warm);
		border-radius: 0 8px 8px 0;
		background: var(--warm-soft);
		font-size: 15px;
		max-width: 560px;
	}

	.fine {
		color: var(--muted);
		font-size: 14px;
		margin-top: 16px;
		max-width: 560px;
	}

	.row {
		display: flex;
		flex-wrap: wrap;
		gap: 8px;
		align-items: center;
	}

	.tag {
		font-size: 12px;
		font-weight: 700;
		padding: 3px 10px;
		border-radius: 999px;
		background: var(--surface-2);
		border: 1px solid var(--border);
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
		display: flex;
		flex-wrap: wrap;
		align-items: baseline;
		gap: 4px 12px;
		margin-top: 14px;
	}

	.score-label {
		font-size: 13px;
		font-weight: 700;
		color: var(--muted);
	}

	.score-value {
		font-size: 16px;
		font-weight: 700;
		color: var(--accent);
	}

	.score-value strong {
		font-size: 30px;
		font-weight: 800;
		letter-spacing: -0.02em;
	}

	.gloss {
		font-size: 13px;
		color: var(--muted);
		margin-top: 2px;
	}

	.card-title {
		font-size: 22px;
		font-weight: 700;
		line-height: 1.2;
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
		gap: 12px;
	}

	.sources strong {
		font-variant-numeric: tabular-nums;
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

	@media (max-width: 420px) {
		.request-card {
			padding: 20px;
		}
	}
</style>
