<script lang="ts">
	import { monthlyPayment, totalInterest } from '$lib/finance/amortization';
	import { formatUsd, formatUsdShort } from '$lib/core/format';

	// The design doc's reference mortgage: $400,000 at 6.5% over 30 years.
	const principal = 400_000;
	const rate = 6.5;
	const years = 30;
	const interest = totalInterest(principal, rate, years);
	const monthly = monthlyPayment(principal, rate, years);
</script>

<section class="hero">
	<div class="container hero-grid">
		<div>
			<p class="eyebrow">A member-owned cooperative</p>
			<h1>Help your family buy a home, without paying a bank for the privilege.</h1>
			<p class="lead">
				Kinfold lets families and communities lend to each other at zero interest, and protect each
				other when life goes wrong. One membership. No interest. No late fees. Ever.
			</p>
			<div class="actions">
				<a class="btn btn-primary" href="#calculator">See what you'd save</a>
				<a class="btn btn-ghost" href="#products">How it works</a>
			</div>
		</div>

		<aside class="stat-card" aria-label="Interest on a typical mortgage">
			<p class="stat-label">A typical {formatUsdShort(principal)} mortgage at {rate}% costs</p>
			<p class="stat-value">{formatUsdShort(interest)}</p>
			<p class="stat-label">in interest over {years} years.</p>
			<hr />
			<p class="stat-foot">
				That's {formatUsd(monthly)} a month, and more than the house itself. Kinfold keeps that
				money in your family.
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
		font-size: clamp(36px, 5.4vw, 58px);
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

	.stat-card {
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: 20px;
		padding: 32px;
		box-shadow: var(--shadow);
	}

	.stat-label {
		color: var(--muted);
		font-size: 15px;
	}

	.stat-value {
		font-size: 72px;
		font-weight: 800;
		color: var(--warm);
		line-height: 1.05;
		letter-spacing: -0.03em;
		margin: 6px 0;
	}

	hr {
		border: none;
		border-top: 1px solid var(--border);
		margin: 22px 0;
	}

	.stat-foot {
		font-size: 15px;
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
