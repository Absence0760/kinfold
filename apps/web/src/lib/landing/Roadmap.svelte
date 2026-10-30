<script lang="ts">
	const phases = [
		{
			name: 'Family loans',
			when: 'Months 0 to 9',
			scope: 'Documents, tracking, gift letters and mortgage-partner matching. No money held.',
			gate: 'Legal review passed and 100 families active'
		},
		{
			name: 'Protection pilot',
			when: 'Months 9 to 18',
			scope: 'One circle, job-loss cover only, with a licensed partner.',
			gate: 'Claims paid smoothly and a credit union partner signed'
		},
		{
			name: 'Home Fund pilot',
			when: 'Months 18 to 30',
			scope: 'One city, a credit union partner, and matching funds.',
			gate: '25 fund loans repaying on time'
		},
		{
			name: 'Grow',
			when: 'Year 3 onward',
			scope: 'More cover types and regions, then shared-equity homes.',
			gate: null
		}
	];
</script>

<section class="section" id="roadmap">
	<div class="container">
		<p class="eyebrow">Roadmap</p>
		<h2 class="section-title">Each step starts only when the last one proves safe.</h2>
		<p class="section-lead">
			We start with what helps without holding anyone's money, and add pooled money only once each
			phase has earned it.
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
