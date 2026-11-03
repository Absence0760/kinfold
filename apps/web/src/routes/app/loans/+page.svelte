<script lang="ts">
	import { tick } from 'svelte';
	import { invalidate } from '$app/navigation';
	import { formatCents, formatDay } from '#lib/dashboard/format.ts';
	import { loanStatusText } from '#lib/dashboard/labels.ts';
	import { fundLoanStatusText } from '#lib/loans/fund.ts';
	import type { FundLoanSummary } from '#lib/loans/fund.ts';
	import type { LoanListItem } from '#lib/loans/data.ts';
	import Badge from './Badge.svelte';

	let { data } = $props();

	let retrying = $state(false);
	let heading = $state<HTMLElement>();

	async function retry() {
		if (retrying) return;
		retrying = true;
		try {
			await invalidate('app:loans');
			await data.loans.catch(() => undefined);
		} finally {
			retrying = false;
			// The error block (and the button that had focus) is replaced; park focus on the page heading.
			await tick();
			heading?.focus();
		}
	}

	// Where the load stands, for the one live region below. It's mounted (empty)
	// before the data arrives and only its text changes, so screen readers
	// announce both "loading" and "loaded"; a region inserted already holding
	// its text isn't reliably announced.
	let phase = $state<'loading' | 'ready' | 'failed'>('loading');
	$effect(() => {
		let live = true;
		phase = 'loading';
		data.loans.then(
			() => live && (phase = 'ready'),
			() => live && (phase = 'failed')
		);
		return () => {
			live = false;
		};
	});
	const liveText = $derived(
		retrying ? 'Reloading your loans…' : phase === 'loading' ? 'Loading your loans…' : phase === 'ready' ? 'Your loans have loaded.' : ''
	);

	// The load returns one slot holding [family loans, Fund loans].
	const family = (pair: [LoanListItem[], FundLoanSummary[]]) => pair[0];
	const fund = (pair: [LoanListItem[], FundLoanSummary[]]) => pair[1];
	const borrowed = (loans: LoanListItem[]) => loans.filter((l) => l.role === 'borrower');
	const lent = (loans: LoanListItem[]) => loans.filter((l) => l.role === 'lender');
</script>

<svelte:head>
	<title>Your loans · Kinfold</title>
</svelte:head>

<header class="page-head">
	<p class="eyebrow">Loans</p>
	<h1 bind:this={heading} tabindex="-1">Your loans</h1>
	<p class="lead">
		Loans between you and the family and friends you invited. Every one is zero interest with no late
		fees: you repay exactly what was lent, and a missed payment starts a conversation, never a charge.
		The lending Fund lends the same way \u2014 0%, no credit check, and it never forecloses.
	</p>
</header>

{#snippet list(items: LoanListItem[], heading: string, id: string, empty: string)}
	<section class="block" aria-labelledby={id}>
		<h2 {id}>{heading}</h2>
		{#if items.length === 0}
			<p class="empty">{empty}</p>
		{:else}
			<!-- list-style:none removes list semantics in Safari; the role puts them back. -->
			<!-- svelte-ignore a11y_no_redundant_roles -->
			<ul class="cards" role="list">
				{#each items as l (l.loan.id)}
					{@const st = loanStatusText(l.loan.status)}
					<li>
						<a class="card" href="/app/loans/{l.loan.id}">
							<div class="card-head">
								<h3>
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
								<p class="behind"><strong>Behind by {formatCents(l.behindCents)}.</strong> No fee, ever.</p>
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

{#snippet fundList(items: FundLoanSummary[], heading: string, id: string, empty: string)}
	<section class="block" aria-labelledby={id}>
		<h2 {id}>{heading}</h2>
		{#if items.length === 0}
			<p class="empty">{empty}</p>
		{:else}
			<!-- svelte-ignore a11y_no_redundant_roles -->
			<ul class="cards" role="list">
				{#each items as f (f.loan.id)}
					{@const st = fundLoanStatusText(f.loan.status)}
					<li>
						<div class="card-head">
							<h3>You borrowed {formatCents(f.loan.principal_cents)} from the lending Fund</h3>
							<Badge tone={st.tone} label={st.label} />
						</div>
						<p class="line">
							<strong>{formatCents(f.outstandingCents)}</strong> left to repay
							{#if f.next}
								· next {formatCents(f.next.owedCents)} on {formatDay(f.next.dueOn)}
							{:else if f.shareCents > 0}
								· up to {formatCents(f.shareCents)} a month, sized from your income
							{/if}
						</p>
						{#if f.loan.lien_bps > 0}
							<p class="meta">Its lien sits behind the bank’s and behind any public-assistance liens, and all the liens together stay at or below 105% of the home’s value.</p>
						{/if}
					</li>
				{/each}
			</ul>
		{/if}
	</section>
{/snippet}

<p class="visually-hidden" role="status">{liveText}</p>

{#await data.loans}
	<div class="loading" aria-hidden="true">
		{#each [1, 2] as i (i)}
			<div class="skeleton" aria-hidden="true"></div>
		{/each}
	</div>
{:then pair}
	{#if family(pair).length === 0 && fund(pair).length === 0}
		<div class="empty big">
			<p><strong>No loans yet.</strong></p>
			<p>
				When someone you invited lends toward one of your requests, or you lend toward theirs, the loan
				shows here. You’ll agree the payment day and schedule together, both sign, and track every
				installment from either side.
			</p>
			<p>
				A loan starts with a request: ask for help, then invite family and friends, who can give or
				lend at 0%. The lending Fund lends the same way — 0%, with no credit check — to members whose
				home needs it, and it never forecloses.
			</p>
			<div class="cta">
				<a class="btn btn-primary" href="/app/requests/new">Ask for help</a>
				<a class="btn btn-ghost" href="/app/invite">Invite someone</a>
			</div>
		</div>
	{:else}
		{@render list(
			borrowed(family(pair)),
			'Money you borrowed',
			'borrowed-h',
			'You haven’t borrowed from anyone through Kinfold.'
		)}
		{@render list(lent(family(pair)), 'Money you lent', 'lent-h', 'You haven’t lent to anyone through Kinfold.')}
		{@render fundList(fund(pair), 'Money the lending Fund lent you', 'fund-h', 'The lending Fund hasn’t lent you anything yet.')}
	{/if}
{:catch}
	<div class="error" role="alert">
		<h2>We couldn’t load your loans</h2>
		<p>Check your connection and try again. Nothing on your loans has changed.</p>
		<button type="button" class="btn btn-primary" onclick={retry} aria-disabled={retrying}>
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

	.card:focus-visible {
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
		font-variant-numeric: tabular-nums;
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
		padding-block: 8px;
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

	.error .btn,
	.cta .btn {
		min-height: 44px;
	}

	.cta {
		display: flex;
		flex-wrap: wrap;
		gap: 8px;
		margin-top: 4px;
	}

	.btn[aria-disabled='true'] {
		opacity: 0.6;
		cursor: progress;
	}
</style>
