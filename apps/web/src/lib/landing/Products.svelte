<script lang="ts">
	const products = [
		{
			tag: 'Phase 1',
			name: 'Family & Friends Loans',
			lead: 'Turn an informal family loan into a clear, documented, low-stress arrangement.',
			points: [
				'Plain-language agreement, with a lien recorded on the home',
				'Shared balance, automatic payments, gentle reminders',
				'Tax minimum-rate handled and forgiven as a gift',
				'Gift letters your mortgage lender will accept'
			],
			holds: 'Money moves directly between relatives.'
		},
		{
			tag: 'Phase 2',
			name: 'Mutual Protection Circles',
			lead: 'Members pool a small monthly amount and cover each other when life goes wrong.',
			points: [
				'Covers home payments after job loss or illness',
				'A family loan is forgiven if the borrower dies',
				'Claims paid on simple evidence, appeal to a member panel',
				'Unused money comes back to members each year'
			],
			holds: 'Reserves held by a licensed mutual insurer.'
		},
		{
			tag: 'Phase 3',
			name: 'Community Home Fund',
			lead: 'Zero-interest help for people with no wealthy family to borrow from.',
			points: [
				'Keeps families in their homes when a gap opens',
				'Down payment help that shrinks the bank mortgage',
				'Chosen by a published needs formula, never by popularity',
				'Every repaid dollar goes to the next family'
			],
			holds: 'Money held by a partner credit union.'
		}
	];
</script>

<section class="section section-alt" id="products">
	<div class="container">
		<p class="eyebrow">How it works</p>
		<h2 class="section-title">One membership. Three ways to help each other.</h2>
		<p class="section-lead">
			You see one app. Behind it, each product is run by whoever is licensed to hold that kind of
			money, and the money pools never mix, so a bad year in one can't drain another.
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
