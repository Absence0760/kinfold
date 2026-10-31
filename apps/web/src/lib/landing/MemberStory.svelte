<script lang="ts">
	const steps = [
		{ when: 'Day one', text: 'Maria rents and has a thin credit file. She joins Kinfold and pays 1% of her earnings into the community pool.' },
		{
			when: 'Buying',
			text: 'She posts a home request and shares it with family. Her aunt lends $30,000 at zero interest, with a written agreement recorded on the home.'
		},
		{ when: 'Moving in', text: 'A smaller bank mortgage means Maria pays thousands less in interest.' },
		{
			when: 'Year two',
			text: 'Someone rear-ends her car. She posts a damage request with photos and the police report, scores 96%, and the pool pays the shop in three days.'
		},
		{
			when: 'Year four',
			text: 'Her on-time repayments to her aunt build a record that replaces a credit score, and open the Community Home Fund for a roof repair.'
		},
		{ when: 'Today', text: 'Maria points her monthly payment at home requests, helping the next family.' }
	];
</script>

<section class="section" id="story">
	<div class="container story">
		<div>
			<p class="eyebrow">A member's journey</p>
			<h2 class="section-title">One record, built by helping each other.</h2>
			<p class="section-lead">
				Every request you post, every payment you make and every loan you repay adds to one record.
				That record replaces a credit score and opens help to people banks overlook.
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
