<script lang="ts">
	const basics = [
		{ title: 'Monthly', text: 'Equal installments on a payday you choose.' },
		{ title: 'Automatic', text: 'Collected for you, so nobody has to ask for the money.' },
		{ title: 'Zero interest', text: 'You pay back what you borrowed, never a cent more.' },
		{ title: 'No late fees', text: 'Not now, not ever, in any part of Kinfold.' }
	];

	const ladder = [
		{
			title: 'A reminder, not a fee',
			text: 'A missed payment starts a friendly reminder and a 10-day grace period. Never a fee.'
		},
		{
			title: 'Pause',
			text: 'Pause up to 3 months a year, no permission needed. The schedule moves back; the total never changes.'
		},
		{
			title: 'Restructure',
			text: 'Lower payments over a longer term, once both sides agree.'
		},
		{
			title: 'Ask for help',
			text: 'Post a hardship request so friends or the pool can cover installments.'
		},
		{
			title: 'Forgive part',
			text: 'The lender can forgive part of the loan as a gift. Kinfold does the gift paperwork.'
		},
		{
			title: 'The plan you chose',
			text: 'If it truly can’t be repaid, the plan both sides picked at signing applies: forgive the rest, repay from the home’s sale or refinance (secured loans; nobody forces a sale), or a mediator.'
		}
	];

	const mortgageHelp = [
		'Bridge missed payments with a zero-interest Home Fund loan',
		'Connect you to a HUD-approved housing counselor for forbearance or a loan modification',
		'If selling is the only way out, sell before foreclosure so the family keeps its equity'
	];
</script>

<section class="section section-alt" id="repay">
	<div class="container">
		<p class="eyebrow">Paying it back</p>
		<h2 class="section-title">How paying it back works.</h2>
		<p class="section-lead">
			A Kinfold loan is a promise between people, not a product sold to you. It is built to bend
			when life does, without ever costing more.
		</p>

		<ul class="basics">
			{#each basics as b (b.title)}
				<li>
					<h3>{b.title}</h3>
					<p>{b.text}</p>
				</li>
			{/each}
		</ul>

		<h3 class="sub ladder-title">If you can't pay</h3>
		<ol class="ladder">
			{#each ladder as step, i (step.title)}
				<li>
					<span class="num">{i + 1}</span>
					<h4>{step.title}</h4>
					<p>{step.text}</p>
				</li>
			{/each}
		</ol>

		<div class="lower">
			<div class="mortgage">
				<h3 class="sub">Mortgages</h3>
				<p>
					Kinfold doesn't hold your mortgage, so your bank's rules apply. What Kinfold can do:
				</p>
				<ul>
					{#each mortgageHelp as item (item)}
						<li>{item}</li>
					{/each}
				</ul>
			</div>
			<div class="record">
				<h3 class="sub">Your giving record</h3>
				<p>
					See what you've paid in, given, lent and received. It's private to you, and it's never
					used to rank or refuse a request. How often you claim can raise your own share of a
					future request, never your place in line.
				</p>
			</div>
		</div>
	</div>
</section>

<style>
	.basics {
		list-style: none;
		margin: 40px 0 0;
		padding: 0;
		display: grid;
		grid-template-columns: repeat(4, 1fr);
		gap: 16px;
	}

	.basics li,
	.ladder li {
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius);
		padding: 24px;
	}

	.basics h3 {
		font-size: 18px;
		margin-bottom: 6px;
	}

	.basics p,
	.ladder p,
	.lower p {
		color: var(--muted);
		font-size: 15px;
	}

	.ladder-title {
		margin-top: 40px;
	}

	.ladder {
		list-style: none;
		margin: 0;
		padding: 0;
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: 16px;
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

	h4 {
		font-size: 17px;
		margin: 14px 0 6px;
	}

	.lower {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 20px;
		margin-top: 20px;
	}

	.mortgage,
	.record {
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius);
		padding: 24px 28px;
	}

	.mortgage {
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

	.mortgage .sub {
		color: var(--warm);
	}

	.mortgage ul {
		margin: 12px 0 0;
		padding-left: 18px;
		display: grid;
		gap: 8px;
		font-size: 15px;
	}

	@media (max-width: 960px) {
		.basics,
		.ladder {
			grid-template-columns: repeat(2, 1fr);
		}

		.lower {
			grid-template-columns: 1fr;
		}
	}

	@media (max-width: 560px) {
		.basics,
		.ladder {
			grid-template-columns: 1fr;
		}
	}
</style>
