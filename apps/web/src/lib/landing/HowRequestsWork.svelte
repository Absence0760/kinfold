<script lang="ts">
	const steps = [
		{
			title: 'Post a request',
			text: 'Say what happened and what it costs: car damage after a crash, or help with a down payment, a mortgage gap or a loan.'
		},
		{
			title: 'Upload evidence',
			text: 'Photos, a police report, a repair estimate, a loan statement. Kinfold blurs names, plates and faces, and you check it before anything reaches the board.'
		},
		{
			title: 'Get a legitimacy score',
			text: 'An AI model checks the evidence and explains its score. A low score asks for more evidence; only a person can turn a request down.'
		},
		{
			title: 'Get paid',
			text: 'Your cover, the community, your people, or all three. Money goes straight to the repair shop or lender, never through a middleman taking a cut.'
		}
	];

	const funders = [
		{
			title: 'Your people',
			text: 'Share the request with family and friends. They can give it, or lend it at zero interest with a written agreement and repayment tracking.'
		},
		{
			title: 'The community',
			text: 'Members pay dues of a small share of their earnings, which buy deductible cover that pays every covered claim in full. A gift-funded repair fund helps with the rest, highest-scoring requests first.'
		}
	];

	const fraud = [
		'The shop or lender is paid directly, so a high quote can’t be swapped for a cheap repair',
		'Photo metadata, damage patterns and police reports are cross-checked',
		'Staged crashes show up as patterns across requests, people and vehicles',
		'Identity is verified once; there are no anonymous requests'
	];
</script>

<section class="section" id="requests">
	<div class="container">
		<p class="eyebrow">How a request works</p>
		<h2 class="section-title">One way to ask for help, whatever went wrong.</h2>
		<p class="section-lead">
			Insurance claims and home loans work the same way on Kinfold. The only difference is whether
			the money is a gift, an insured payout, a repair grant, or a zero-interest loan you pay back.
		</p>

		<ol class="steps">
			{#each steps as step, i (step.title)}
				<li>
					<span class="num">{i + 1}</span>
					<h3>{step.title}</h3>
					<p>{step.text}</p>
				</li>
			{/each}
		</ol>

		<div class="lower">
			<div class="funders">
				<h3 class="sub">Who pays</h3>
				{#each funders as f (f.title)}
					<article>
						<h4>{f.title}</h4>
						<p>{f.text}</p>
					</article>
				{/each}
			</div>
			<div class="fraud">
				<h3 class="sub">Built against fraud</h3>
				<ul>
					{#each fraud as item (item)}
						<li>{item}</li>
					{/each}
				</ul>
			</div>
		</div>
	</div>
</section>

<style>
	.steps {
		list-style: none;
		margin: 40px 0 0;
		padding: 0;
		display: grid;
		grid-template-columns: repeat(4, 1fr);
		gap: 16px;
	}

	.steps li {
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius);
		padding: 24px;
	}

	.num {
		display: inline-grid;
		place-items: center;
		width: 30px;
		height: 30px;
		border-radius: 50%;
		background: var(--accent);
		color: var(--accent-contrast);
		font-weight: 700;
		font-size: 14px;
	}

	.steps h3 {
		font-size: 18px;
		margin: 14px 0 6px;
	}

	.steps p,
	.funders p {
		color: var(--muted);
		font-size: 15px;
	}

	.lower {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 20px;
		margin-top: 20px;
	}

	.funders,
	.fraud {
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius);
		padding: 24px 28px;
	}

	.fraud {
		border-left: 4px solid var(--warm);
	}

	.sub {
		font-size: 13px;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--accent);
		margin-bottom: 12px;
	}

	.fraud .sub {
		color: var(--warm);
	}

	.funders article + article {
		margin-top: 14px;
	}

	h4 {
		font-size: 17px;
		margin-bottom: 2px;
	}

	.fraud ul {
		margin: 0;
		padding-left: 18px;
		display: grid;
		gap: 8px;
		font-size: 15px;
	}

	@media (max-width: 960px) {
		.steps {
			grid-template-columns: repeat(2, 1fr);
		}

		.lower {
			grid-template-columns: 1fr;
		}
	}

	@media (max-width: 560px) {
		.steps {
			grid-template-columns: 1fr;
		}
	}
</style>
