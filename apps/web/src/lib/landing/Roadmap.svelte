<script lang="ts">
	const phases = [
		{
			name: 'Requests between people',
			when: 'Months 0 to 9',
			scope: 'The member app, evidence and scoring; family and friends pay as gifts or zero-interest loans. Car damage and home help. No pooled money.',
			gate: 'Legal review passed, 500 requests scored, reviewers agree with the score 9 times in 10'
		},
		{
			name: 'Community car cover',
			when: 'Months 9 to 18',
			scope: 'Dues based on earnings pay for deductible cover from a licensed partner insurer, alongside a gift-funded repair fund and zero-interest repair loans. One state.',
			gate: 'Claims paid on time, fraud below target, books reconcile daily'
		},
		{
			name: 'Home Fund',
			when: 'Months 18 to 30',
			scope: 'Zero-interest home loans through a credit union, mortgage-gap bridging, and matching funds.',
			gate: '25 fund loans repaying on time'
		},
		{
			name: 'Grow',
			when: 'Year 3 onward',
			scope: "More cover types and states, a members' own reciprocal insurer, and shared-equity homes.",
			gate: null
		}
	];
</script>

<section class="section section-alt" id="roadmap">
	<div class="container">
		<p class="eyebrow">Roadmap</p>
		<h2 class="section-title">Each step starts only when the last one proves safe.</h2>
		<p class="section-lead">
			We start with requests paid by people you know, which holds nobody's money, and add the
			community pool only once scoring has proved fair.
		</p>
		<ol class="phases">
			{#each phases as phase, i (phase.name)}
				<li class:current={i === 0}>
					<span class="step">Phase {i + 1}{i === 0 ? ' · now' : ''}</span>
					<h3>{phase.name}</h3>
					<p class="when">{phase.when}</p>
					<p>{phase.scope}</p>
					{#if phase.gate}
						<p class="gate"><span>Gate</span>{phase.gate}</p>
					{/if}
				</li>
			{/each}
		</ol>
	</div>
</section>

<style>
	.phases {
		list-style: none;
		margin: 40px 0 0;
		padding: 0;
		display: grid;
		grid-template-columns: repeat(4, 1fr);
		gap: 16px;
	}

	li {
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius);
		padding: 24px;
		display: flex;
		flex-direction: column;
		gap: 6px;
	}

	li.current {
		border: 2px solid var(--accent);
		background: var(--accent-soft);
	}

	.step {
		font-size: 12px;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--accent);
	}

	h3 {
		font-size: 19px;
	}

	.when {
		color: var(--muted);
		font-size: 14px;
		margin-bottom: 6px;
	}

	.gate {
		margin-top: auto;
		padding-top: 14px;
		border-top: 1px dashed var(--border);
		font-size: 14px;
		color: var(--muted);
	}

	.gate span {
		display: block;
		font-weight: 700;
		color: var(--warm);
		font-size: 12px;
		text-transform: uppercase;
		letter-spacing: 0.06em;
	}

	@media (max-width: 960px) {
		.phases {
			grid-template-columns: repeat(2, 1fr);
		}
	}

	@media (max-width: 560px) {
		.phases {
			grid-template-columns: 1fr;
		}
	}
</style>
