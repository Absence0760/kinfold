<script lang="ts">
	import { invalidate } from '$app/navigation';
	import { formatCents, formatDay } from '#lib/dashboard/format.ts';
	import { loanStatusText } from '#lib/dashboard/labels.ts';
	import type { LoanListItem } from '#lib/loans/data.ts';
	import Badge from './Badge.svelte';

	let { data } = $props();

	let retrying = $state(false);
	async function retry() {
		retrying = true;
		try {
			await invalidate('app:loans');
		} finally {
			retrying = false;
		}
	}

	const borrowed = (loans: LoanListItem[]) => loans.filter((l) => l.role === 'borrower');
	const lent = (loans: LoanListItem[]) => loans.filter((l) => l.role === 'lender');
</script>

<svelte:head>
	<title>Your loans · Kinfold</title>
</svelte:head>

<header class="page-head">
	<p class="eyebrow">Loans</p>
	<h1>Your loans</h1>
	<p class="lead">
		Loans between you and the family and friends you invited. Every one is zero interest with no late
		fees: you repay exactly what was lent, and a missed payment starts a conversation, never a charge.
	</p>
</header>

{#snippet list(items: LoanListItem[], heading: string, id: string, empty: string)}
	<section class="block" aria-labelledby={id}>
		<h2 {id}>{heading}</h2>
		{#if items.length === 0}
			<p class="empty">{empty}</p>
		{:else}
			<ul class="cards">
				{#each items as l (l.loan.id)}
					{@const st = loanStatusText(l.loan.status)}
					<li>
						<a class="card" href="/app/loans/{l.loan.id}" aria-labelledby="loan-{l.loan.id}">
							<div class="card-head">
								<h3 id="loan-{l.loan.id}">
									{#if l.role === 'borrower'}
										You borrowed {formatCents(l.loan.principal_cents)}{l.lenderRelationship
											? ` from your ${l.lenderRelationship}`
											: ''}
									{:else}
										You lent {formatCents(l.loan.principal_cents)}
									{/if}
								</h3>
								<Badge tone={st.tone} label={st.label} />
							</div>
							{#if l.requestTitle}
								<p class="meta">Toward “{l.requestTitle}”</p>
							{/if}
							<p class="line">
								<strong>{formatCents(l.remainingCents)}</strong>
								{l.role === 'borrower' ? 'left to repay' : 'still to come back to you'}
								{#if l.next}
									· next {formatCents(l.next.owedCents)} on {formatDay(l.next.dueOn)}
								{/if}
							</p>
							{#if l.behindCents > 0}
								<p class="behind"><strong>Behind by {formatCents(l.behindCents)}</strong> · no fee, ever</p>
							{/if}
							{#if l.loan.status === 'proposed'}
								<p class="line">Terms, schedule and both signatures are still to agree.</p>
							{/if}
							<span class="more">See the agreement and schedule <span aria-hidden="true">→</span></span>
						</a>
					</li>
				{/each}
			</ul>
		{/if}
	</section>
{/snippet}

{#await data.loans}
	<div class="loading" role="status">
		<span class="visually-hidden">Loading your loans…</span>
		{#each [1, 2] as i (i)}
			<div class="skeleton" aria-hidden="true"></div>
		{/each}
	</div>
{:then loans}
	{#if loans.length === 0}
		<div class="empty big">
			<p><strong>No loans yet.</strong></p>
			<p>
				When someone you invited lends toward one of your requests, or you lend toward theirs, the loan
				shows here. You’ll agree the payment day and schedule together, both sign, and track every
				installment from either side.
			</p>
			<p><a href="/app">Back to your home</a></p>
		</div>
	{:else}
		{@render list(
			borrowed(loans),
			'Money you borrowed',
			'borrowed-h',
			'You haven’t borrowed from anyone through Kinfold.'
		)}
		{@render list(lent(loans), 'Money you lent', 'lent-h', 'You haven’t lent to anyone through Kinfold.')}
	{/if}
{:catch}
	<div class="error" role="alert">
		<h2>We couldn’t load your loans</h2>
		<p>Check your connection and try again. Nothing on your loans has changed.</p>
		<button type="button" class="btn btn-primary" onclick={retry} disabled={retrying}>
			{retrying ? 'Trying again…' : 'Try again'}
		</button>
	</div>
{/await}

<style>
	.page-head {
		margin-bottom: 24px;
	}

	h1 {
		font-size: clamp(28px, 5vw, 38px);
	}

	.lead {
		color: var(--muted);
		margin-top: 8px;
		max-width: 640px;
	}

	.block {
		margin-top: 32px;
	}

	.block h2 {
		font-size: 22px;
	}

	.cards {
		list-style: none;
		margin: 14px 0 0;
		padding: 0;
		display: grid;
		gap: 14px;
	}

	.card,
	.empty,
	.error {
		display: block;
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius);
		padding: 18px 20px;
	}

	.card {
		color: var(--text);
		text-decoration: none;
	}

	.card:hover {
		border-color: var(--accent);
	}

	.empty {
		margin-top: 14px;
		color: var(--muted);
		border-style: dashed;
	}

	.empty.big {
		display: grid;
		gap: 8px;
	}

	.empty strong {
		color: var(--text);
	}

	.card-head {
		display: flex;
		flex-wrap: wrap;
		align-items: flex-start;
		justify-content: space-between;
		gap: 8px 16px;
	}

	.card h3 {
		font-size: 18px;
		flex: 1 1 14rem;
		overflow-wrap: anywhere;
	}

	.meta {
		color: var(--muted);
		font-size: 15px;
		margin-top: 6px;
		overflow-wrap: anywhere;
	}

	.line {
		font-size: 15px;
		margin-top: 8px;
	}

	.behind {
		margin-top: 10px;
		padding: 8px 12px;
		border-radius: 10px;
		background: var(--warm-soft);
		border-left: 4px solid var(--warm);
		font-size: 15px;
	}

	.more {
		display: inline-block;
		margin-top: 12px;
		color: var(--accent);
		font-weight: 600;
		font-size: 15px;
	}

	.error {
		display: grid;
		gap: 10px;
		justify-items: start;
	}

	.loading {
		display: grid;
		gap: 14px;
	}

	.skeleton {
		height: 120px;
		border-radius: var(--radius);
		background: var(--surface-2);
	}

	.visually-hidden {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip-path: inset(50%);
		white-space: nowrap;
	}
</style>
