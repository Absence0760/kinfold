<script lang="ts">
	import { tick } from 'svelte';
	import { supabase } from '#lib/supabase/client.ts';
	import { parseDollars } from '#lib/board/board.ts';
	import { formatCents } from '#lib/dashboard/format.ts';
	import { forgiveLoan } from '#lib/loans/data.ts';
	import { explainLoanError } from '#lib/loans/errors.ts';
	import {
		forgiveProblem,
		GIFT_EXCLUSION_CENTS,
		GIFT_EXCLUSION_YEAR,
		type LoanDetailRow
	} from '#lib/loans/loan.ts';
	import Panel from '../Panel.svelte';

	let {
		loan,
		outstandingCents,
		forgivenThisYearCents,
		taxYear,
		onchanged
	}: {
		loan: LoanDetailRow;
		outstandingCents: number;
		forgivenThisYearCents: number;
		taxYear: number;
		onchanged: (message: string) => Promise<void>;
	} = $props();

	type Step = 'closed' | 'edit' | 'confirm' | 'sending';
	let step = $state<Step>('closed');
	let choice = $state<'rest' | 'part'>('part');
	let typed = $state('');
	let tried = $state(false);
	let error = $state('');

	let openButton = $state<HTMLButtonElement>();
	let firstField = $state<HTMLInputElement>();
	let confirmTitle = $state<HTMLElement>();

	const uid = $derived(`forgive-${loan.id}`);
	const cents = $derived(choice === 'rest' ? outstandingCents : parseDollars(typed));
	const problem = $derived(forgiveProblem(cents, outstandingCents));
	const yearTotal = $derived(forgivenThisYearCents + (cents ?? 0));
	// The exclusion figure is the 2026 one; later years need the new figure.
	const overExclusion = $derived(taxYear === GIFT_EXCLUSION_YEAR && yearTotal > GIFT_EXCLUSION_CENTS);
	const isAll = $derived(cents === outstandingCents);

	async function open() {
		choice = 'part';
		typed = '';
		tried = false;
		error = '';
		step = 'edit';
		await tick();
		firstField?.focus();
	}

	async function close() {
		// The buttons stay focusable while sending (aria-disabled), so guard here.
		if (step === 'sending') return;
		step = 'closed';
		await tick();
		openButton?.focus();
	}

	async function goBack() {
		// The buttons stay focusable while sending (aria-disabled), so guard here.
		if (step === 'sending') return;
		step = 'edit';
		await tick();
		firstField?.focus();
	}

	async function review(e: SubmitEvent) {
		e.preventDefault();
		tried = true;
		if (problem) {
			firstField?.focus();
			return;
		}
		step = 'confirm';
		await tick();
		confirmTitle?.focus();
	}

	async function save() {
		if (step === 'sending') return;
		if (cents == null) return;
		step = 'sending';
		error = '';
		try {
			await forgiveLoan(supabase(), loan.id, cents, taxYear);
			step = 'closed';
			await onchanged(
				isAll
					? `You forgave the rest, ${formatCents(cents)}. The loan is closed and nothing more is owed.`
					: `You forgave ${formatCents(cents)}. It’s recorded as a gift for ${taxYear}.`
			);
		} catch (err) {
			error = explainLoanError(err as { message?: string; code?: string });
			step = 'confirm';
			await tick();
			confirmTitle?.focus();
		}
	}
</script>

<Panel
	id="{uid}-h"
	title="Forgive some or all of it"
	intro="You can turn part or all of what’s left into a gift at any time. Forgiven money is never asked for again."
>
	{#if step === 'closed'}
		<p>Still to come back to you: <strong>{formatCents(outstandingCents)}</strong>.</p>
		<div class="actions">
			<button type="button" class="btn btn-ghost" bind:this={openButton} onclick={open}>Forgive an amount</button>
		</div>
	{:else if step === 'edit'}
		<form onsubmit={review} novalidate>
			<fieldset>
				<legend>How much?</legend>
				<label class="option">
					<input type="radio" name="{uid}-choice" value="part" bind:group={choice} />
					<span><strong>Part of it</strong><span class="sub">The borrower keeps repaying the rest.</span></span>
				</label>
				<label class="option">
					<input type="radio" name="{uid}-choice" value="rest" bind:group={choice} />
					<span>
						<strong>All of what’s left, {formatCents(outstandingCents)}</strong>
						<span class="sub">The loan closes. Nothing more is collected.</span>
					</span>
				</label>
			</fieldset>
			{#if choice === 'part'}
				<div class="field">
					<label for="{uid}-amount">Amount to forgive, in dollars</label>
					<input
						id="{uid}-amount"
						bind:this={firstField}
						bind:value={typed}
						inputmode="decimal"
						autocomplete="off"
						size="10"
						aria-required="true"
						aria-invalid={tried && problem ? 'true' : undefined}
						aria-describedby="{uid}-hint{tried && problem ? ` ${uid}-problem` : ''}"
					/>
					<span class="hint" id="{uid}-hint">Up to {formatCents(outstandingCents)}, like 100 or 49.50.</span>
					{#if tried && problem}<span class="problem" id="{uid}-problem" role="alert">{problem}</span>{/if}
				</div>
			{/if}
			<div class="actions">
				<button type="submit" class="btn btn-primary">Review</button>
				<button type="button" class="btn btn-ghost" onclick={close}>Cancel</button>
			</div>
		</form>
	{:else}
		<div class="step" role="group" aria-labelledby="{uid}-confirm">
			<p class="confirm-title" id="{uid}-confirm" tabindex="-1" bind:this={confirmTitle}>
				Forgive {formatCents(cents ?? 0)}{isAll ? ', everything that’s left' : ''}?
			</p>
			<ul class="terms">
				<li>
					<strong>This can’t be undone.</strong>
					{isAll
						? 'The loan closes and the borrower owes nothing more.'
						: `The borrower will owe ${formatCents(outstandingCents - (cents ?? 0))} instead of ${formatCents(outstandingCents)}.`}
				</li>
				<li>
					It’s recorded as your gift to the borrower for tax year {taxYear}. Kinfold keeps this record for the
					gift letter, which states the amount, that no repayment is expected, and your relationship. A mortgage
					lender may ask the borrower for one.
				</li>
				<li>
					{#if overExclusion}
						<strong>Gift-tax return:</strong> with this, you’ll have forgiven {formatCents(yearTotal)} in
						{taxYear}, over the {formatCents(GIFT_EXCLUSION_CENTS)} yearly limit per person. You’d file a gift-tax
						return (IRS Form 709). Tax is rarely due, but check with a tax adviser.
					{:else}
						Up to {formatCents(GIFT_EXCLUSION_CENTS)} a year per person ({GIFT_EXCLUSION_YEAR} limit) needs no
						gift-tax return. You’ll have forgiven {formatCents(yearTotal)} on this loan in {taxYear}; count other
						gifts to the same person too.
					{/if}
				</li>
				<li>No money moves. Forgiving only lowers what the borrower repays.</li>
			</ul>
			{#if error}<p class="problem" role="alert">{error}</p>{/if}
			<div class="actions">
				<button type="button" class="btn btn-warn" onclick={save} aria-disabled={step === 'sending'} aria-busy={step === 'sending'}>
					{step === 'sending' ? 'Saving…' : `Forgive ${formatCents(cents ?? 0)}`}
				</button>
				<button type="button" class="btn btn-ghost" onclick={goBack} aria-disabled={step === 'sending'}>
					Go back
				</button>
			</div>
		</div>
	{/if}
</Panel>
