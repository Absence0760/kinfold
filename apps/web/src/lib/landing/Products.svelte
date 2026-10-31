<script lang="ts">
	const products = [
		{
			tag: 'Phase 1',
			name: 'Ask your people',
			lead: 'Share a request with family and friends: a car repair, a down payment, help with a loan.',
			points: [
				'They give it, or lend it at zero interest',
				'Plain-language agreement, with a lien on the home for big loans',
				'Shared balance, automatic repayments, gentle reminders',
				'Gift letters your mortgage lender will accept'
			],
			holds: 'Money moves between people through a payment partner. Kinfold never holds it.'
		},
		{
			tag: 'Phase 2',
			name: 'Community protection',
			lead: 'Damage requests paid from a pool everyone pays into. Starting with cars.',
			points: [
				'Pay a small share of your earnings, nothing if you earn little',
				'Choose where your monthly payment goes',
				'Members-only board, ranked by legitimacy score',
				'Repair shop paid directly, so quotes can’t be gamed'
			],
			holds: 'Pool held by a licensed partner, never mixed with loan money.'
		},
		{
			tag: 'Phase 3',
			name: 'Community Home Fund',
			lead: 'Zero-interest home help for people with no wealthy family to ask.',
			points: [
				'Keeps families in their homes when a gap opens',
				'Down payment help that shrinks the bank mortgage',
				'Same request and evidence, scored on need too',
				'Every repaid dollar goes to the next family'
			],
			holds: 'Money held by a partner credit union.'
		}
	];
</script>

<section class="section" id="products">
	<div class="container">
		<p class="eyebrow">What you can ask for</p>
		<h2 class="section-title">One membership. Three places help can come from.</h2>
		<p class="section-lead">
			You see one app and one request form. Behind it, each kind of money is held by whoever is
			licensed to hold it, and the pools never mix, so a bad year for car claims can't drain the
			home fund.
		</p>

		<div class="grid">
			{#each products as p (p.name)}
				<article class="card">
					<span class="tag">{p.tag}</span>
					<h3>{p.name}</h3>
					<p class="lead">{p.lead}</p>
					<ul>
						{#each p.points as point (point)}
							<li>{point}</li>
						{/each}
					</ul>
					<p class="holds">{p.holds}</p>
				</article>
			{/each}
		</div>

		<div class="mortgage">
			<div>
				<h3>And your mortgage?</h3>
				<p>
					Kinfold doesn't write first mortgages. We make yours smaller, protect the payments, and
					match you with fair lenders, starting with credit unions and community lenders.
				</p>
			</div>
		</div>
	</div>
</section>

<style>
	.grid {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: 20px;
		margin-top: 44px;
	}

	.card {
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius);
		padding: 28px;
		display: flex;
		flex-direction: column;
		box-shadow: var(--shadow);
	}

	.tag {
		align-self: flex-start;
		font-size: 12px;
		font-weight: 700;
		padding: 3px 10px;
		border-radius: 999px;
		background: var(--accent-soft);
		color: var(--accent);
	}

	h3 {
		font-size: 21px;
		margin-top: 16px;
	}

	.lead {
		color: var(--muted);
		margin-top: 8px;
	}

	ul {
		margin: 20px 0 0;
		padding: 0;
		list-style: none;
		display: grid;
		gap: 10px;
	}

	li {
		position: relative;
		padding-left: 26px;
		font-size: 15px;
	}

	li::before {
		content: '';
		position: absolute;
		left: 0;
		top: 7px;
		width: 14px;
		height: 8px;
		border-left: 2.5px solid var(--accent);
		border-bottom: 2.5px solid var(--accent);
		transform: rotate(-45deg);
	}

	.holds {
		margin-top: auto;
		padding-top: 20px;
		font-size: 13px;
		color: var(--muted);
		border-top: 1px dashed var(--border);
	}

	.mortgage {
		margin-top: 20px;
		background: var(--surface);
		border: 1px solid var(--border);
		border-left: 4px solid var(--warm);
		border-radius: var(--radius);
		padding: 24px 28px;
	}

	.mortgage h3 {
		margin: 0 0 6px;
		font-size: 19px;
	}

	.mortgage p {
		color: var(--muted);
		max-width: 760px;
	}

	@media (max-width: 960px) {
		.grid {
			grid-template-columns: 1fr;
		}
	}
</style>
