<script lang="ts">
	import { untrack } from 'svelte';
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
	const shown = $derived(Math.min(familyAmount, loanAmount));

	// Screen readers get one short summary that settles after the sliders stop
	// moving, instead of every figure re-read on each step of a drag.
	const summary = $derived(
		`You avoid paying the bank ${formatUsd(result.interestSaved)} of interest. Monthly payment ${formatUsd(result.withKinfold.monthly)} with Kinfold, ${formatUsd(result.bankOnly.monthly)} with the bank only.`
	);
	let announcement = $state(untrack(() => summary));
	$effect(() => {
		const next = summary;
		const timer = setTimeout(() => (announcement = next), 700);
		return () => clearTimeout(timer);
	});
</script>

<section class="section" id="calculator">
	<div class="container">
		<p class="eyebrow">Savings calculator</p>
		<h2 class="section-title">Every dollar your family lends is a dollar the bank can't charge interest on.</h2>
		<p class="section-lead">
			Move the sliders. The zero-interest share is repaid over the same term as the mortgage, so
			your family gets back exactly what they lent. Where tax law requires a minimum rate on a family loan, Kinfold shows it and arranges for it to be forgiven as a gift. Your bank's rules still apply, and a repayable family loan can affect whether you qualify.
		</p>

		<div class="calc">
			<div class="inputs">
				<label>
					<span>Home loan needed <strong aria-hidden="true">{formatUsd(loanAmount)}</strong></span>
					<input
						type="range"
						min="50000"
						max="1000000"
						step="5000"
						bind:value={loanAmount}
						aria-valuetext={formatUsd(loanAmount)}
					/>
				</label>
				<label>
					<span>Bank interest rate <strong aria-hidden="true">{rate.toFixed(2)}%</strong></span>
					<input
						type="range"
						min="2"
						max="10"
						step="0.05"
						bind:value={rate}
						aria-valuetext="{rate.toFixed(2)}%"
					/>
				</label>
				<label>
					<span>Term <strong aria-hidden="true">{years} years</strong></span>
					<input
						type="range"
						min="10"
						max="30"
						step="5"
						bind:value={years}
						aria-valuetext="{years} years"
					/>
				</label>
				<label>
					<span>From family or friends, at 0% <strong aria-hidden="true">{formatUsd(shown)}</strong></span>
					<input
						type="range"
						min="0"
						max={loanAmount}
						step="1000"
						bind:value={familyAmount}
						aria-valuetext={formatUsd(shown)}
					/>
				</label>
			</div>

			<div class="results">
				<p class="visually-hidden" aria-live="polite" aria-atomic="true">{announcement}</p>
				<div class="result-main">
					<p class="label">Interest you don't pay the bank</p>
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
						Add a family or friends share to see the difference.
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
		min-height: 44px;
		margin: 0;
		accent-color: var(--accent);
	}

	/* Contrast (WCAG 1.4.3), --accent-contrast text, computed from the tokens:
	   on --accent: 6.41:1 light, 8.26:1 dark; on the 10% panels below: 5.12:1
	   light, 6.93:1 dark. No text here is faded with opacity, which is what took
	   the small lines under 4.5:1 before. SavingsCalculator.contrast.test.ts
	   recomputes these from app.css. */
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
	}

	.big {
		font-size: clamp(36px, 6vw, 64px);
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
		background: color-mix(in srgb, var(--accent-contrast) 10%, transparent);
		border-radius: 10px;
		padding: 14px 16px;
	}

	/* "With Kinfold" stands out by an outline and weight, not a lighter tint
	   (a 22% tint took its small text to 3.9:1). The ring is 6.41:1 / 8.26:1
	   against the accent fill. */
	.compare .with {
		box-shadow: inset 0 0 0 2px var(--accent-contrast);
	}

	.compare .with .label {
		font-weight: 700;
	}

	.value {
		font-size: 24px;
		font-weight: 700;
		font-variant-numeric: tabular-nums;
	}

	.value small {
		font-size: 14px;
		font-weight: 500;
	}

	.sub {
		font-size: 13px;
	}

	.note {
		font-size: 13px;
		margin-top: auto;
	}

	@media (max-width: 860px) {
		.calc {
			grid-template-columns: 1fr;
		}
	}

	@media (max-width: 480px) {
		.inputs,
		.results {
			padding: 20px;
		}

		.compare {
			grid-template-columns: 1fr;
		}
	}
</style>
