<script lang="ts">
	import { tick } from 'svelte';
	import { supabase } from '#lib/supabase/client.ts';
	import { addMonths, formatCents, formatDay } from '#lib/dashboard/format.ts';
	import { pauseFundLoan } from '#lib/loans/fund.ts';
	import { fundPauseProblem } from '#lib/loans/fund.ts';
	import type { FundLoanRow, FundInstallmentRow, FundPauseRow } from '#lib/loans/fund.ts';
	import { explainLoanError } from '#lib/loans/errors.ts';
	import { pushBack, pauseMonthsUsed, pauseMonthsLeft } from '#lib/loans/loan.ts';
	import { monthsWord } from '#lib/loans/words.ts';
	import Panel from '../../Panel.svelte';

	let {
		loan,
		installments,
		pauses,
		today,
		onchanged
	}: {
		loan: FundLoanRow;
		installments: FundInstallmentRow[];
		pauses: FundPauseRow[];
		today: string;
		onchanged: (message: string) => Promise<void>;
	} = $props();

	const REASON_MAX = 500;

	type Step = 'closed' | 'edit' | 'confirm' | 'sending';
	let step = $state<Step>('closed');
	let months = $state(1);
	let reason = $state('');
	let error = $state('');

	let openButton = $state<HTMLButtonElement>();
	let firstField = $state<HTMLSelectElement>();
	let confirmTitle = $state<HTMLElement>();

	const uid = $derived(`pause-${loan.id}`);
	const used = $derived(pauseMonthsUsed(pauses, today));
	const left = $derived(pauseMonthsLeft(loan.pause_months_per_year, used));
	const choices = $derived(Array.from({ length: left }, (_, i) => i + 1));
	const moved = $derived(pushBack(installments, months));
	const problem = $derived(
		fundPauseProblem(months, left) ??
			(reason.trim().length > REASON_MAX ? `Keep the note to ${REASON_MAX} characters or fewer.` : null)
	);
	const until = $derived(addMonths(today, months));

	async function open() {
		if (left < 1) return;
		months = Math.min(1, left);
		reason = '';
		error = '';
		step = 'edit';
		await tick();
		firstField?.focus();
	}

	async function close() {
		if (step === 'sending') return;
		step = 'closed';
		await tick();
		openButton?.focus();
	}

	async function goBack() {
		if (step === 'sending') return;
		step = 'edit';
		await tick();
		firstField?.focus();
	}

	async function review(e: SubmitEvent) {
		e.preventDefault();
		if (problem) return;
		step = 'confirm';
		await tick();
		confirmTitle?.focus();
	}

	async function save() {
		if (step === 'sending') return;
		step = 'sending';
		error = '';
		try {
			await pauseFundLoan(supabase(), loan.id, months);
			step = 'closed';
			await onchanged(`Paused for ${monthsWord(months)}. Every payment still to come moved back by the same time.`);
		} catch (err) {
			error = explainLoanError(err as { message?: string; code?: string });
			step = 'confirm';
			await tick();
			confirmTitle?.focus();
		}
	}
</script>

{#snippet movedList()}
	{#if moved.length > 0}
		<div class="preview" aria-live="polite">
			<p>
				{moved.length} payment{moved.length === 1 ? '' : 's'} move{moved.length === 1 ? 's' : ''} back by
				{monthsWord(months)}. The amounts and the total owed stay the same.
			</p>
			<details>
				<summary>See the new dates</summary>
				<ul>
					{#each moved as m (m.seq)}
						<li>Payment {m.seq} ({formatCents(m.amountCents)}): {formatDay(m.from)} → {formatDay(m.to)}</li>
					{/each}
				</ul>
			</details>
		</div>
	{/if}
{/snippet}

<Panel
	id="{uid}-h"
	title="Need a break from payments?"
	intro="You can pause without asking anyone, up to the allowance you agreed. There’s no fee, and you don’t owe a cent more."
>
	<p>
		<strong>{monthsWord(left)} of {monthsWord(loan.pause_months_per_year)}</strong> left in the last 12 months
		({used} used).
	</p>
	{#if step === 'closed'}
		{#if left < 1}
			<p class="hint" id="{uid}-none-left">No pause months are left right now. They come back as earlier pauses fall outside the last 12 months.</p>
		{/if}
		<div class="actions">
			<button
				type="button"
				class="btn btn-ghost"
				bind:this={openButton}
				onclick={open}
				aria-disabled={left < 1}
				aria-describedby={left < 1 ? `${uid}-none-left` : undefined}
			>
				Pause payments
			</button>
		</div>
	{:else if step === 'edit'}
		<form onsubmit={review} novalidate>
			<div class="field">
				<label for="{uid}-months">How long?</label>
				<select id="{uid}-months" bind:this={firstField} bind:value={months}>
					{#each choices as m (m)}
						<option value={m}>{monthsWord(m)}</option>
					{/each}
				</select>
			</div>
			<div class="field">
				<label for="{uid}-reason">A note for the lending Fund (optional)</label>
				<textarea
					id="{uid}-reason"
					rows="3"
					bind:value={reason}
					maxlength={REASON_MAX}
					aria-describedby="{uid}-reason-hint"
				></textarea>
				<span class="hint" id="{uid}-reason-hint">
					You don’t have to explain. The lending Fund can see this note. {reason.trim().length} of {REASON_MAX} characters.
				</span>
			</div>
			{@render movedList()}
			{#if problem}<p class="problem" id="{uid}-problem" role="alert">{problem}</p>{/if}
			<div class="actions">
				<button
					type="submit"
					class="btn btn-primary"
					aria-disabled={!!problem}
					aria-describedby={problem ? `${uid}-problem` : undefined}>Review the pause</button
				>
				<button type="button" class="btn btn-ghost" onclick={close}>Cancel</button>
			</div>
		</form>
	{:else}
		<div class="step" role="group" aria-labelledby="{uid}-confirm">
			<p class="confirm-title" id="{uid}-confirm" tabindex="-1" bind:this={confirmTitle}>
				Pause for {monthsWord(months)}?
			</p>
			<ul class="terms">
				<li>No payments are collected until about {formatDay(until)}. You can resume earlier whenever you like.</li>
				<li>Every payment still to come moves back {monthsWord(months)}, and stays moved even if you resume early.</li>
				<li>It uses {monthsWord(months)} of your allowance, leaving {monthsWord(left - months)} for the next 12 months.</li>
				<li>The lending Fund sees that the loan is paused{reason.trim() ? ', and your note' : ''}.</li>
			</ul>
			{@render movedList()}
			{#if error}<p class="problem" role="alert">{error}</p>{/if}
			<div class="actions">
				<button type="button" class="btn btn-primary" onclick={save} aria-disabled={step === 'sending'} aria-busy={step === 'sending'}>
					{step === 'sending' ? 'Pausing…' : `Pause for ${monthsWord(months)}`}
				</button>
				<button type="button" class="btn btn-ghost" onclick={goBack} aria-disabled={step === 'sending'}>
					Go back
				</button>
			</div>
		</div>
	{/if}
</Panel>
