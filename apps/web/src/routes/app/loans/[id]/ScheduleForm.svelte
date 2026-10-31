<script lang="ts">
	import { tick } from 'svelte';
	import { supabase } from '#lib/supabase/client.ts';
	import { addMonths, formatCents, formatDay } from '#lib/dashboard/format.ts';
	import { setLoanSchedule } from '#lib/loans/data.ts';
	import { explainLoanError } from '#lib/loans/errors.ts';
	import type { LoanDetailRow } from '#lib/loans/loan.ts';
	import { dayAfter, describeSplit, MAX_MONTHS, planSchedule, scheduleProblem, scheduleTotal } from '#lib/loans/schedule.ts';
	import { ordinal } from '#lib/loans/words.ts';
	import Panel from './Panel.svelte';

	let {
		loan,
		hasSchedule,
		anySigned,
		today,
		onchanged
	}: {
		loan: LoanDetailRow;
		hasSchedule: boolean;
		anySigned: boolean;
		today: string;
		onchanged: (message: string) => Promise<void>;
	} = $props();

	type Step = 'closed' | 'edit' | 'confirm' | 'sending';
	let step = $state<Step>('closed');
	let monthsText = $state('12');
	let first = $state('');
	let tried = $state(false);
	let error = $state('');

	let openButton = $state<HTMLButtonElement>();
	let monthsInput = $state<HTMLInputElement>();
	let confirmTitle = $state<HTMLElement>();

	const uid = $derived(`schedule-${loan.id}`);
	const tomorrow = $derived(dayAfter(today));
	const months = $derived(/^\d{1,3}$/.test(monthsText.trim()) ? Number(monthsText.trim()) : NaN);
	const monthsProblem = $derived(scheduleProblem(loan.principal_cents, months));
	const firstProblem = $derived(
		!/^\d{4}-\d{2}-\d{2}$/.test(first)
			? 'Pick the date of the first payment.'
			: first < tomorrow
				? 'Pick a date after today.'
				: null
	);
	const rows = $derived(monthsProblem || firstProblem ? [] : planSchedule(loan.principal_cents, months, first, loan.payment_day));
	const total = $derived(scheduleTotal(rows));

	async function open() {
		error = '';
		tried = false;
		if (!first) first = addMonths(today, 1);
		step = 'edit';
		await tick();
		monthsInput?.focus();
	}

	async function close() {
		step = 'closed';
		await tick();
		openButton?.focus();
	}

	async function review(e: SubmitEvent) {
		e.preventDefault();
		tried = true;
		if (monthsProblem || firstProblem || rows.length === 0) return;
		step = 'confirm';
		await tick();
		confirmTitle?.focus();
	}

	async function save() {
		step = 'sending';
		error = '';
		try {
			await setLoanSchedule(supabase(), loan.id, months, first);
			step = 'closed';
			await onchanged(
				anySigned ? 'Schedule saved. The signatures were cleared, so you both sign again.' : 'Schedule saved.'
			);
		} catch (err) {
			error = explainLoanError(err as { message?: string; code?: string });
			step = 'confirm';
		}
	}
</script>

{#snippet preview()}
	<div class="preview" aria-live="polite" id="{uid}-preview">
		{#if rows.length === 0}
			<p>Enter the number of payments and the first date to see the schedule.</p>
		{:else}
			<p><strong>{describeSplit(rows, formatCents)}</strong>, on the {ordinal(loan.payment_day)} of each month.</p>
			<p>
				From {formatDay(rows[0].dueOn)} to {formatDay(rows[rows.length - 1].dueOn)}. Total
				<strong>{formatCents(total)}</strong>: exactly the {formatCents(loan.principal_cents)} lent, with no
				interest added.
			</p>
			{#if rows.length > 1 && rows[0].amountCents !== rows[rows.length - 1].amountCents}
				<p class="hint">The last payment is a little larger so the total comes out to the exact cent.</p>
			{/if}
			<details>
				<summary>See every payment</summary>
				<ol>
					{#each rows as r (r.seq)}
						<li>{formatDay(r.dueOn)}: {formatCents(r.amountCents)}</li>
					{/each}
				</ol>
			</details>
		{/if}
	</div>
{/snippet}

<Panel
	id="{uid}-h"
	title="Repayment schedule"
	intro="Equal monthly payments on the payment day, the last one taking any leftover cents. Either of you can set it; saving clears both signatures."
>
	{#if step === 'closed'}
		<div class="actions">
			<button type="button" class="btn {hasSchedule ? 'btn-ghost' : 'btn-primary'}" bind:this={openButton} onclick={open}>
				{hasSchedule ? 'Change the schedule' : 'Set the schedule'}
			</button>
		</div>
	{:else if step === 'edit'}
		<form onsubmit={review} novalidate>
			<label class="field">
				<span>Number of monthly payments</span>
				<input
					bind:this={monthsInput}
					bind:value={monthsText}
					inputmode="numeric"
					autocomplete="off"
					size="6"
					aria-invalid={tried && monthsProblem ? 'true' : undefined}
					aria-describedby="{uid}-months-hint{tried && monthsProblem ? ` ${uid}-months-problem` : ''}"
				/>
				<span class="hint" id="{uid}-months-hint">1 to {MAX_MONTHS}. 12 is one year.</span>
				{#if tried && monthsProblem}<span class="problem" id="{uid}-months-problem">{monthsProblem}</span>{/if}
			</label>

			<label class="field">
				<span>First payment no earlier than</span>
				<input
					type="date"
					bind:value={first}
					min={tomorrow}
					aria-invalid={tried && firstProblem ? 'true' : undefined}
					aria-describedby="{uid}-first-hint{tried && firstProblem ? ` ${uid}-first-problem` : ''}"
				/>
				<span class="hint" id="{uid}-first-hint">
					The first payment lands on the next {ordinal(loan.payment_day)} on or after this date. Repayments only
					start once the money has reached the payee.
				</span>
				{#if tried && firstProblem}<span class="problem" id="{uid}-first-problem">{firstProblem}</span>{/if}
			</label>

			{@render preview()}

			<div class="actions">
				<button type="submit" class="btn btn-primary">Review the schedule</button>
				<button type="button" class="btn btn-ghost" onclick={close}>Cancel</button>
			</div>
		</form>
	{:else}
		<div class="step" role="group" aria-labelledby="{uid}-confirm">
			<p class="confirm-title" id="{uid}-confirm" tabindex="-1" bind:this={confirmTitle}>Save this schedule?</p>
			{@render preview()}
			<ul class="terms">
				{#if hasSchedule}<li>It replaces the current schedule.</li>{/if}
				{#if anySigned}<li><strong>It clears the signatures already given.</strong> You both sign again.</li>{/if}
				<li>No interest and no late fees: the payments add up to exactly what was lent.</li>
			</ul>
			{#if error}<p class="problem" role="alert">{error}</p>{/if}
			<div class="actions">
				<button type="button" class="btn btn-primary" onclick={save} disabled={step === 'sending'} aria-busy={step === 'sending'}>
					{step === 'sending' ? 'Saving…' : 'Save the schedule'}
				</button>
				<button type="button" class="btn btn-ghost" onclick={() => (step = 'edit')} disabled={step === 'sending'}>
					Go back
				</button>
			</div>
		</div>
	{/if}
</Panel>
