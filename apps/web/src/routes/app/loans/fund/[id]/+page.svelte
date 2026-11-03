<script lang="ts">
	import { tick } from 'svelte';
	import { invalidate } from '$app/navigation';
	import { formatCents, formatDay, localToday } from '#lib/dashboard/format.ts';
	import { fundLoanMissed, fundLoanStatusText, loadFundLoan, pauseEnd, fundLoanActions } from '#lib/loans/fund.ts';
	import type { FundLoanDetail } from '#lib/loans/fund.ts';
	import { pauseMonthsUsed, pauseMonthsLeft } from '#lib/loans/loan.ts';
	import { monthsWord } from '#lib/loans/words.ts';
	import Badge from '../../Badge.svelte';
	import FundPauseForm from './FundPauseForm.svelte';
	import FundResumePanel from './FundResumePanel.svelte';
	import FundRestructureForm from './FundRestructureForm.svelte';
	import FundSignPanel from './FundSignPanel.svelte';
	import FairLendingPanel from './FairLendingPanel.svelte';

	let { data } = $props();

	const today = localToday();

	// Keep showing the loan while it reloads after an action, so the page
	// doesn't flash back to a skeleton and lose the reader's place.
	let detail = $state<FundLoanDetail | null | undefined>(undefined);
	let failed = $state(false);
	let retrying = $state(false);
	let reloading = $state(false);
	$effect(() => {
		let live = true;
		data.detail.then(
			(d) => {
				if (!live) return;
				detail = d;
				failed = false;
			},
			() => {
				if (live) failed = true;
			}
		);
		return () => {
			live = false;
		};
	});

	let notice = $state('');
	let noticeEl = $state<HTMLElement>();
	let updatingEl = $state<HTMLElement>();

	async function refresh() {
		reloading = true;
		try {
			await invalidate('app:fund-loan');
			// Wait for the reload itself, so the confirmation lands on fresh figures.
			detail = await data.detail;
			failed = false;
		} catch {
			failed = true;
		} finally {
			reloading = false;
		}
	}

	async function changed(message: string) {
		notice = '';
		await tick();
		updatingEl?.focus();
		await refresh();
		notice = message;
		await tick();
		noticeEl?.focus();
	}

	let heading = $state<HTMLElement>();

	async function retry() {
		if (retrying) return;
		retrying = true;
		try {
			await refresh();
		} finally {
			retrying = false;
			await tick();
			heading?.focus();
		}
	}

	const loadText = $derived(
		retrying ? 'Trying again\u2026' : detail === undefined && !failed ? 'Loading the loan\u2026' : ''
	);
	const view = $derived.by(() => {
		if (!detail) return null;
		const { loan, pauses, installments, missed, outstandingCents } = detail;
		const pausedUntil = pauseEnd(pauses, loan.id);
		const used = pauseMonthsUsed(pauses, today);
		const left = pauseMonthsLeft(loan.pause_months_per_year, used);
		const unpaid = installments.filter((i) => i.paid_cents < i.amount_cents);
		const openAsk = detail.restructure;
		const actions = fundLoanActions(loan.status, outstandingCents, left, loan.schedule, openAsk !== null);
		const late = fundLoanMissed(missed);
		return {
			loan,
			installments,
			unpaid,
			late,
			openAsk,
			pausedUntil,
			used,
			left,
			actions,
			status: fundLoanStatusText(loan.status)
		};
	});
</script>

<svelte:head>
	<title>Fund loan · Kinfold</title>
</svelte:head>

<p class="back"><a href="/app/loans"><span aria-hidden="true">←</span> All your loans</a></p>

<p class="visually-hidden" role="status">{loadText}</p>

{#if failed && !detail}
	<div class="box error" role="alert">
		<h1 bind:this={heading} tabindex="-1">We couldn\u2019t load this loan</h1>
		<p>Check your connection and try again. Nothing on the loan has changed.</p>
		<button type="button" class="btn btn-primary" onclick={retry} aria-disabled={retrying}>
			{retrying ? 'Trying again\u2026' : 'Try again'}
		</button>
	</div>
{:else if detail === undefined}
	<div class="loading" aria-hidden="true">
		<div class="skeleton tall" aria-hidden="true"></div>
		<div class="skeleton" aria-hidden="true"></div>
	</div>
{:else if detail === null || !view}
	<div class="box">
		<h1 bind:this={heading} tabindex="-1">Fund loan not found</h1>
		<p>
			This loan doesn\u2019t exist, or it isn\u2019t yours. Only the borrower can see a loan the lending Fund took out.
		</p>
		<p><a href="/app/loans">Go to your loans</a></p>
	</div>
{:else}
	{@const l = view.loan}
	{@const unpaid = view.unpaid}
	<header class="page-head">
		<p class="eyebrow">Money the lending Fund lent you</p>
		<div class="title-row">
			<h1 bind:this={heading} tabindex="-1">
				You borrowed {formatCents(l.principal_cents)} from the lending Fund
			</h1>
			<Badge tone={view.status.tone} label={view.status.label} />
		</div>
		<p class="lead">
			The lending Fund lends the same way as everyone else: 0%, no credit check, and it never forecloses.
		</p>
	</header>
	<p class="visually-hidden" role="status" tabindex="-1" bind:this={updatingEl}>{reloading ? 'Updating the loan\u2026' : ''}</p>
	{#if notice}
		<p class="notice" role="status" tabindex="-1" bind:this={noticeEl}>{notice}</p>
	{/if}
	{#if failed}
		<p class="notice warn" role="alert">
			We couldn\u2019t refresh the loan, so what\u2019s shown may be out of date.
			<button type="button" class="link" onclick={retry} aria-disabled={retrying}>Try again</button>
		</p>
	{/if}

	<dl class="facts box">
		<div>
			<dt>Left to repay</dt>
			<dd><strong>{formatCents(detail.outstandingCents)}</strong> of {formatCents(l.principal_cents)}</dd>
		</div>
		{#if l.schedule === 'monthly' && view.unpaid.length > 0}
			<div>
				<dt>Next payment</dt>
				<dd>
					<strong>{formatCents(view.unpaid[0].amount_cents - view.unpaid[0].paid_cents)}</strong> on
					{formatDay(view.unpaid[0].due_on)}
				</dd>
			</div>
		{:else if l.schedule === 'income'}
			<div>
				<dt>Payments</dt>
				<dd>
					Sized from your income every month, capped by the schema \u2014 payments fall off automatically
					if your income does.
				</dd>
			</div>
		{/if}
		{#if view.pausedUntil && l.status === 'paused'}
			<div>
				<dt>Paused until</dt>
				<dd>{formatDay(view.pausedUntil)} \u2014 the money still owed hasn\u2019t changed.</dd>
			</div>
		{/if}
		{#if view.openAsk}
			<div>
				<dt>A new schedule you asked for</dt>
				<dd>
					{monthsWord(view.openAsk.months)} from {formatDay(view.openAsk.first_due)} \u2014 the lending
					Fund applies it at its servicing event, and the money still owed never changes.
				</dd>
			</div>
		{:else}
			{#if view.installments.length > 0 && l.schedule === 'monthly'}
				<div>
					<dt>Schedule</dt>
					<dd>{view.installments.length} monthly payments. The amounts add up to exactly what was lent: no interest, nothing lost to rounding.</dd>
				</div>
			{/if}
		{/if}
		{#if view.late.count > 0}
			<div>
				<dt>Payment dates that ran out</dt>
				<dd>
					{view.late.count} of your monthly payments are more than ten days late and unpaid
					- {formatCents(view.late.owedCents)} still owed on just those. Nothing is charged for a
					late payment: it starts a conversation with the lending Fund (a reminder and the pause
					offer), and money already owed never changes because of it.
				</dd>
			</div>
		{/if}
		{#if l.lien_bps > 0}
			<div>
				<dt>Lien</dt>
				<dd>A lien of {l.lien_bps / 1000}% of the home\u2019s value sits behind the bank\u2019s and any public-assistance liens; all liens together stay at or below 105%.</dd>
			</div>
		{/if}
	</dl>

	{#if view.actions.sign}
		<FundSignPanel loan={l} outstandingCents={detail.outstandingCents} onchanged={changed} />
	{/if}
	{#if view.actions.pause}
		<FundPauseForm loan={l} installments={view.installments} pauses={detail.pauses} today={today} onchanged={changed} />
	{/if}
	{#if view.actions.resume}
		<FundResumePanel loanId={l.id} pausedUntil={view.pausedUntil} next={view.unpaid[0] ? { dueOn: view.unpaid[0].due_on, owedCents: view.unpaid[0].amount_cents - view.unpaid[0].paid_cents } : null} onchanged={changed} />
	{/if}
	{#if view.actions.restructure}
		<FundRestructureForm loan={l} outstandingCents={detail.outstandingCents} restructureWaiting={view.openAsk !== null} today={today} onchanged={changed} />
	{/if}
	<FairLendingPanel loan={l} onchanged={changed} />
{/if}
<style>
	.back {
		margin-bottom: 16px;
		font-size: 15px;
	}

	.page-head {
		margin-bottom: 20px;
	}

	.title-row {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 8px 16px;
	}

	h1 {
		font-size: clamp(26px, 5vw, 36px);
		font-weight: 700;
		line-height: 1.15;
		margin: 0;
		text-align: left;
		color: var(--text);
	}

	.lead {
		margin-top: 8px;
		max-width: 640px;
	}

	.box {
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius);
		padding: 18px 20px;
	}

	.error,
	.box:has(> h1) {
		display: grid;
		gap: 10px;
		justify-items: start;
	}

	.notice {
		margin: 0 0 16px;
		padding: 12px 16px;
		border-radius: 10px;
		background: var(--accent-soft);
		border-left: 4px solid var(--accent);
		font-weight: 600;
	}

	.notice.warn {
		background: var(--warm-soft);
		border-left-color: var(--warm);
		font-weight: 400;
	}

	.notice:focus-visible {
		outline-offset: 2px;
	}

	.link {
		display: inline-flex;
		align-items: center;
		min-height: 44px;
		padding-inline: 4px;
		font: inherit;
		background: none;
		border: 0;
		color: var(--accent);
		text-decoration: underline;
		cursor: pointer;
	}

	.facts {
		margin: 0;
		display: grid;
		gap: 12px 24px;
		grid-template-columns: repeat(auto-fit, minmax(min(100%, 13rem), 1fr));
	}

	.facts dt {
		color: var(--muted);
		font-size: 13px;
		font-weight: 700;
		letter-spacing: 0.04em;
		text-transform: uppercase;
	}

	.facts > div:first-child dd strong {
		display: block;
		font-size: 26px;
		line-height: 1.2;
	}

	.facts dd {
		margin: 2px 0 0;
		font-size: 15px;
	}

	.loading {
		display: grid;
		gap: 14px;
	}

	.error .btn {
		min-height: 44px;
	}

	.skeleton.tall {
		height: 200px;
	}

	@media (max-width: 380px) {
		.box {
			padding: 14px;
		}
	}
</style>
