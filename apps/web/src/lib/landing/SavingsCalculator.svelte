<script lang="ts">
	import { compareSavings } from '#lib/finance/amortization.ts';
	import { formatUsd } from '#lib/core/format.ts';

	let loanAmount = $state(400_000);
	let rate = $state(6.5);
	let years = $state(30);
	let familyAmount = $state(30_000);

	const result = $derived(
		compareSavings({ loanAmount, annualRatePct: rate, years, zeroInterestAmount: familyAmount })
	);
	const savedPerMonth = $derived(result.bankOnly.monthly - result.withKinfold.monthly);
</script>

<section class="section" id="calculator">
	<div class="container">
		<p class="eyebrow">Savings calculator</p>
		<h2 class="section-title">Every dollar your family lends is a dollar the bank can't charge interest on.</h2>
		<p class="section-lead">
			Move the sliders. The zero-interest share is repaid over the same term as the mortgage, so
			your family gets back exactly what they lent.
		</p>

		<div class="calc">
			<div class="inputs">
				<label>
					<span>Home loan needed <strong>{formatUsd(loanAmount)}</strong></span>
					<input type="range" min="50000" max="1000000" step="5000" bind:value={loanAmount} />
				</label>
				<label>
					<span>Bank interest rate <strong>{rate.toFixed(2)}%</strong></span>
					<input type="range" min="2" max="10" step="0.05" bind:value={rate} />
				</label>
				<label>
					<span>Term <strong>{years} years</strong></span>
					<input type="range" min="10" max="30" step="5" bind:value={years} />
				</label>
				<label>
					<span>From family and community, at 0% <strong>{formatUsd(Math.min(familyAmount, loanAmount))}</strong></span>
					<input type="range" min="0" max={loanAmount} step="1000" bind:value={familyAmount} />
				</label>
			</div>

			<div class="results" aria-live="polite">
				<div class="result-main">
					<p class="label">Interest you keep in the family</p>
					<p class="big">{formatUsd(result.interestSaved)}</p>
				</div>
				<div class="compare">
					<div>
						<p class="label">Bank only</p>
						<p class="value">{formatUsd(result.bankOnly.monthly)}<small>/mo</small></p>
						<p class="sub">{formatUsd(result.bankOnly.interest)} interest</p>
					</div>
					<div class="with">
						<p class="label">With Kinfold</p>
						<p class="value">{formatUsd(result.withKinfold.monthly)}<small>/mo</small></p>
						<p class="sub">{formatUsd(result.withKinfold.interest)} interest</p>
					</div>
				</div>
				<p class="note">
					{#if savedPerMonth > 0.5}
						{formatUsd(savedPerMonth)} less every month.
					{:else}
						Add a family or community share to see the difference.
					{/if}
					An illustration only, not an offer or a quote.
				</p>
			</div>
		</div>
	</div>
</section>

<style>
	.calc {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 32px;
		margin-top: 40px;
	}

	.inputs {
		display: grid;
		gap: 26px;
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius);
		padding: 28px;
	}

	label {
		display: grid;
		gap: 10px;
	}

	label span {
		display: flex;
		justify-content: space-between;
		gap: 12px;
		color: var(--muted);
		font-size: 15px;
	}

	label strong {
		color: var(--text);
		font-variant-numeric: tabular-nums;
	}

	input[type='range'] {
		width: 100%;
		accent-color: var(--accent);
	}

	.results {
		background: var(--accent);
		color: var(--accent-contrast);
		border-radius: var(--radius);
		padding: 28px;
		display: flex;
		flex-direction: column;
		gap: 24px;
	}

	.label {
		font-size: 14px;
		opacity: 0.85;
	}

	.big {
		font-size: clamp(44px, 6vw, 64px);
		font-weight: 800;
		letter-spacing: -0.03em;
		line-height: 1.1;
		font-variant-numeric: tabular-nums;
	}

	.compare {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 12px;
	}

	.compare > div {
		background: color-mix(in srgb, var(--accent-contrast) 12%, transparent);
		border-radius: 10px;
		padding: 14px 16px;
	}

	.compare .with {
		background: color-mix(in srgb, var(--accent-contrast) 22%, transparent);
	}

	.value {
		font-size: 24px;
		font-weight: 700;
		font-variant-numeric: tabular-nums;
	}

	.value small {
		font-size: 14px;
		font-weight: 500;
		opacity: 0.85;
	}

	.sub {
		font-size: 13px;
		opacity: 0.85;
	}

	.note {
		font-size: 13px;
		opacity: 0.85;
		margin-top: auto;
	}

	@media (max-width: 860px) {
		.calc {
			grid-template-columns: 1fr;
		}
	}
</style>
