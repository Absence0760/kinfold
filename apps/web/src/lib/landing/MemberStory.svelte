<script lang="ts">
	const steps = [
		{ when: 'Day one', text: 'Maria rents and has a thin credit file. She joins Kinfold and a Protection Circle.' },
		{
			when: 'Buying',
			text: 'Her aunt wants to help but fears losing her savings. Kinfold sets up a $30,000 zero-interest family loan, recorded on the home, with circle cover.'
		},
		{ when: 'Moving in', text: 'A smaller bank mortgage means Maria pays thousands less in interest.' },
		{
			when: 'Year two',
			text: "Maria is laid off. Her circle covers four months of payments. Her aunt keeps getting repaid, and nobody has a hard conversation."
		},
		{
			when: 'Year four',
			text: 'Her on-time record opens the Community Fund. She swaps an expensive car loan for a zero-interest one.'
		},
		{ when: 'Today', text: 'Maria pays into the fund herself, helping the next family.' }
	];
</script>

<section class="section" id="story">
	<div class="container story">
		<div>
			<p class="eyebrow">A member's journey</p>
			<h2 class="section-title">The pieces protect each other.</h2>
			<p class="section-lead">
				Protection makes lending safe. Repayment builds a record that replaces a credit score. That
				record opens help to people banks overlook, and repaid money funds the next family.
			</p>
		</div>
		<ol>
			{#each steps as step (step.when)}
				<li>
					<span class="when">{step.when}</span>
					<p>{step.text}</p>
				</li>
			{/each}
		</ol>
	</div>
</section>

<style>
	.story {
		display: grid;
		grid-template-columns: 1fr 1.2fr;
		gap: 56px;
		align-items: start;
	}

	ol {
		list-style: none;
		margin: 0;
		padding: 0;
		position: relative;
	}

	ol::before {
		content: '';
		position: absolute;
		left: 7px;
		top: 8px;
		bottom: 8px;
		width: 2px;
		background: var(--border);
	}

	li {
		position: relative;
		padding: 0 0 26px 36px;
	}

	li::before {
		content: '';
		position: absolute;
		left: 0;
		top: 5px;
		width: 16px;
		height: 16px;
		border-radius: 50%;
		background: var(--surface);
		border: 3px solid var(--accent);
	}

	li:last-child::before {
		background: var(--warm);
		border-color: var(--warm);
	}

	.when {
		font-size: 13px;
		font-weight: 700;
		color: var(--accent);
		text-transform: uppercase;
		letter-spacing: 0.06em;
	}

	li p {
		margin-top: 2px;
	}

	@media (max-width: 860px) {
		.story {
			grid-template-columns: 1fr;
			gap: 32px;
		}
	}
</style>
