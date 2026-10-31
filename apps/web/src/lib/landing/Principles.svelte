<script lang="ts">
	const principles = [
		{ title: 'No interest, ever', text: 'Members repay what they borrowed and nothing more.' },
		{ title: 'Lenders are protected too', text: "Nobody lends money they can't afford to lose." },
		{ title: 'No profit from hardship', text: 'No late fees. A missed payment starts a plan, not a charge.' },
		{ title: 'Evidence, not popularity', text: 'The pool pays by legitimacy score and need, never by who goes viral.' },
		{ title: 'The home comes first', text: 'Foreclosure is the very last resort, after every other option.' },
		{ title: 'Public, except you', text: 'Requests, scores, payouts and fees are public. Personal details never are.' },
		{ title: 'Members own it', text: 'One member, one vote. Surplus goes back to members.' },
		{ title: 'AI advises, people decide', text: 'Every score is explained. Only a person can turn a request down, and you can appeal.' }
	];
</script>

<section class="section section-alt" id="principles">
	<div class="container">
		<p class="eyebrow">Our principles</p>
		<h2 class="section-title">Written into our bylaws, not just our marketing.</h2>
		<p class="section-lead">
			Every feature has to pass all eight. Changing any of them takes a supermajority vote of every
			member.
		</p>
		<div class="grid">
			{#each principles as p, i (p.title)}
				<article>
					<span class="num">{String(i + 1).padStart(2, '0')}</span>
					<h3>{p.title}</h3>
					<p>{p.text}</p>
				</article>
			{/each}
		</div>
	</div>
</section>

<style>
	.grid {
		display: grid;
		grid-template-columns: repeat(4, 1fr);
		gap: 16px;
		margin-top: 40px;
	}

	article {
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius);
		padding: 22px;
	}

	.num {
		font-size: 13px;
		font-weight: 700;
		color: var(--warm);
	}

	h3 {
		font-size: 17px;
		margin: 8px 0 6px;
	}

	p {
		color: var(--muted);
		font-size: 15px;
	}

	@media (max-width: 960px) {
		.grid {
			grid-template-columns: repeat(2, 1fr);
		}
	}

	@media (max-width: 560px) {
		.grid {
			grid-template-columns: 1fr;
		}
	}
</style>
