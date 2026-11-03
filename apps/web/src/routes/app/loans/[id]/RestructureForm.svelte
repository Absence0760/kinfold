<script lang="ts">
	import { tick } from 'svelte';
	import { supabase } from '#lib/supabase/client.ts';
	import { addMonths, formatCents, formatDay } from '#lib/dashboard/format.ts';
	import { describeSplit, firstDueOn, MAX_MONTHS, planSchedule, scheduleProblem, scheduleTotal } from '#lib/loans/schedule.ts';
	import { ordinal } from '#lib/loans/words.ts';
	import { restructureLoan } from '#lib/loans/data.ts';
	import { explainLoanError } from '#lib/loans/errors.ts';
	import type { LoanDetailRow } from '#lib/loans/loan.ts';
	import Panel from '../Panel.svelte';

	let { loan, owedCents, today, onchanged }: {
		loan: LoanDetailRow;
		owedCents: number;
		today: string;
		onchanged: (message: string) => Promise<void>;
	} = $props();

	// Staging writes an ask; the other side signing is what moves money.
	type Step = 'closed' | 'edit' | 'confirm' | 'sending';
	let step = $state<Step>('closed');
	let monthsText = $state('12');
	let first = $state('');
	let tried = $state(false);
	let error = $state('');

	let openButton = $state<HTMLButtonElement>();
	let monthsInput = $state<HTMLInputElement>();
	let firstInput = $state<HTMLInputElement>();
	let confirmTitle = $state<HTMLElement>();

	const uid = $derived(`restructure-${loan.id}`);
	const tomorrow = $derived(addMonths(today, 1));
	const months = $derived(/^\d{1,4}$/.test(monthsText.trim()) ? Number(monthsText.trim()) : NaN);
	const monthsProblem = $derived(scheduleProblem(owedCents, months));
	const firstProblem = $derived(
		!/^\d{4}-\d{2}-\d{2}$/.test(first)
			? 'Pick the date of the first payment.'
			: first < tomorrow
				? 'Pick a date after today: payments don\u2019t go back in time.'
				: null
	);
	// The payment-day snap the schema applies, shown so the preview matches the save.
	const shownFirst = $derived(first && !firstProblem ? firstDueOn(first, loan.payment_day) : first);
	const rows = $derived(monthsProblem || firstProblem ? [] : planSchedule(owedCents, months, shownFirst, loan.payment_day));
	const total = $derived(scheduleTotal(rows));

	const ANNOUNCE_DELAY_MS = 600;
	let announcement = $state('');
	let announceTimer: ReturnType<typeof setTimeout> | undefined;

	function queueAnnouncement() {
		clearTimeout(announceTimer);
		announceTimer = setTimeout(() => {
			announcement =
				(monthsProblem ?? firstProblem ?? '') ||
				(rows.length === 0
					? ''
					: `${describeSplit(rows, formatCents)}, total ${formatCents(total)}.`);
		}, ANNOUNCE_DELAY_MS);
	}

	$effect(() => () => clearTimeout(announceTimer));

	async function open() {
		if (step === 'sending') return;
		announcement = '';
		step = 'edit';
		await tick();
		monthsInput?.focus();
	}

	async function close() {
		// The buttons stay focusable while sending (aria-disabled), so guard here.
		if (step === 'sending') return;
		announcement = '';
		step = 'closed';
		await tick();
		openButton?.focus();
	}

	async function goBack() {
		if (step === 'sending') return;
		announcement = '';
		step = 'edit';
		await tick();
		monthsInput?.focus();
	}

	async function review(e: SubmitEvent) {
		e.preventDefault();
		tried = true;
		if (monthsProblem) { monthsInput?.focus(); return; }
		if (firstProblem) { firstInput?.focus(); return; }
		if (rows.length === 0) return;
		step = 'confirm';
		await tick();
		confirmTitle?.focus();
	}

	async function save() {
		if (step === 'sending') return;
		step = 'sending';
		error = '';
		try {
			await restructureLoan(supabase(), loan.id, months, first);
			step = 'closed';
			await onchanged(`Restructure staged: ${rows.length} payments from ${formatDay(rows[0].dueOn)}. ` +
				`It takes effect once the other side signs on it.`);
		} catch (err) {
			error = explainLoanError(err as { message?: string; code?: string });
			step = 'confirm';
			await tick();
			confirmTitle?.focus();
		}
	}
</script>

{#snippet preview()}
	<div class="preview" id="{uid}-preview">
		{#if rows.length === 0}
			<p>Enter the number of payments and the first date to see the plan.</p>
		{:else}
			<p><strong>{describeSplit(rows, formatCents)}</strong>, on the {ordinal(loan.payment_day)} of each month.</p>
			<p>
				From {formatDay(rows[0].dueOn)} to {formatDay(rows[rows.length - 1].dueOn)}. Total
				<strong>{formatCents(total)}</strong>: every cent still owed, with nothing new added.
			</p>
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
	title="Change the rest of the schedule"
	intro="Payments already made stay put; only what is still owed gets re-spread. This stages an ask the other side has to sign."
>
	{#if step === 'closed'}
		<div class="actions">
			<button type="button" class="btn btn-ghost" bind:this={openButton} onclick={open}>Propose a new schedule</button>
		</div>
	{:else if step === 'edit'}
		<form onsubmit={review} novalidate>
			<div class="field">
				<label for="{uid}-months">Payments still to come</label>
				<input
					id="{uid}-months"
					bind:this={monthsInput}
					bind:value={monthsText}
					oninput={queueAnnouncement}
					inputmode="numeric"
					autocomplete="off"
					size="6"
					aria-required="true"
					aria-invalid={tried && monthsProblem ? 'true' : undefined}
					aria-describedby="{uid}-months-hint{tried && monthsProblem ? ` ${uid}-months-problem` : ''}"
				/>
				<span class="hint" id="{uid}-months-hint">1 to {MAX_MONTHS}. 12 is one year.</span>
				{#if tried && monthsProblem}<span class="problem" id="{uid}-months-problem" role="alert">{monthsProblem}</span>{/if}
			</div>
			<div class="field">
				<label for="{uid}-first">First payment no earlier than</label>
				<input
					id="{uid}-first"
					bind:this={firstInput}
					type="date"
					aria-required="true"
					bind:value={first}
					onchange={queueAnnouncement}
					min={tomorrow}
					aria-invalid={tried && firstProblem ? 'true' : undefined}
					aria-describedby="{uid}-first-hint{tried && firstProblem ? ` ${uid}-first-problem` : ''}"
				/>
				<span class="hint" id="{uid}-first-hint">
					It lands on the next {ordinal(loan.payment_day)} on or after this date.
				</span>
				{#if tried && firstProblem}<span class="problem" id="{uid}-first-problem" role="alert">{firstProblem}</span>{/if}
			</div>
			{@render preview()}
			<p class="visually-hidden" role="status">{announcement}</p>
			<div class="actions">
				<button type="submit" class="btn btn-primary">Review the plan</button>
				<button type="button" class="btn btn-ghost" onclick={close}>Cancel</button>
			</div>
		</form>
	{:else}
		<div class="step" role="group" aria-labelledby="{uid}-confirm">
			<p class="confirm-title" id="{uid}-confirm" tabindex="-1" bind:this={confirmTitle}>Stage this new schedule?</p>
			<ul class="terms">
				<li>Payments already made stay exactly as they were; this only re-spreads what is still owed.</li>
				<li>The total owed does not change, and no interest or fees are added.</li>
				<li>The other side has to sign on it before anything moves.</li>
			</ul>
			{@render preview()}
			{#if error}<p class="problem" role="alert">{error}</p>{/if}
			<div class="actions">
				<button type="button" class="btn btn-primary" onclick={save} aria-disabled={step === 'sending'} aria-busy={step === 'sending'}>
					{step === 'sending' ? 'Staging…' : 'Stage the new schedule'}
				</button>
				<button type="button" class="btn btn-ghost" onclick={goBack} aria-disabled={step === 'sending'}>
					Go back
				</button>
			</div>
		</div>
	{/if}
</Panel>
