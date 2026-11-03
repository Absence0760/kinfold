<script lang="ts">
	import { tick } from 'svelte';
	import { supabase } from '#lib/supabase/client.ts';
	import { formatCents, formatDay } from '#lib/dashboard/format.ts';
	import { fundRestructureProblem, fundSplit } from '#lib/loans/fund.ts';
	import { restructureFundLoan } from '#lib/loans/fund.ts';
	import type { FundLoanRow } from '#lib/loans/fund.ts';
	import { explainLoanError } from '#lib/loans/errors.ts';
	import Panel from '../../Panel.svelte';

	let { loan, outstandingCents, restructureWaiting, today, onchanged }: {
		loan: FundLoanRow;
		outstandingCents: number;
		restructureWaiting: boolean;
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
	let firstInput = $state<HTMLInputElement>();
	let confirmTitle = $state<HTMLElement>();

	const uid = $derived(`restructure-${loan.id}`);
	const months = $derived(/^\d{1,4}$/.test(monthsText.trim()) ? Number(monthsText.trim()) : NaN);
	const firstProblem = $derived(
		!/^\d{4}-\d{2}-\d{2}$/.test(first)
			? 'Pick the date of the first payment.'
			: first < today
				? 'Pick a date from today on: payments don’t go back in time.'
				: null
	);
	const problem = $derived(fundRestructureProblem(loan.status, loan.schedule, months, outstandingCents, restructureWaiting, first, today));
	const rows = $derived(problem === null || firstProblem !== null ? [] : fundSplit(outstandingCents, months, first));
	const total = $derived(rows.reduce((sum, r) => sum + r.amountCents, 0));

	async function open() {
		if (step === 'sending') return;
		step = 'edit';
		await tick();
		monthsInput?.focus();
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
		monthsInput?.focus();
	}

	async function review(e: SubmitEvent) {
		e.preventDefault();
		tried = true;
		if (problem) { monthsInput?.focus(); return; }
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
			await restructureFundLoan(supabase(), loan.id, months, first);
			step = 'closed';
			await onchanged(`Ask staged: ${rows.length} payments from ${formatDay(rows[0].dueOn)}. The lending Fund applies it at its servicing event.`);
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
	title="Ask for a new schedule"
	intro="Only what is still owed gets re-spread. Payments already made stay exactly as they were."
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
					inputmode="numeric"
					autocomplete="off"
					size="6"
					aria-required="true"
					aria-invalid={tried && problem ? 'true' : undefined}
					aria-describedby="{uid}-months-hint{tried && problem ? ` ${uid}-months-problem` : ''}"
				/>
				<span class="hint" id="{uid}-months-hint">1 to 480. 12 is one year.</span>
				{#if tried && problem}<span class="problem" id="{uid}-months-problem" role="alert">{problem}</span>{/if}
			</div>
			<div class="field">
				<label for="{uid}-first">First payment no earlier than</label>
				<input
					id="{uid}-first"
					bind:this={firstInput}
					type="date"
					aria-required="true"
					bind:value={first}
					min={today}
					aria-invalid={tried && firstProblem ? 'true' : undefined}
					aria-describedby="{uid}-first-hint{tried && firstProblem ? ` ${uid}-first-problem` : ''}"
				/>
				<span class="hint" id="{uid}-first-hint">One payment each month from this date on.</span>
				{#if tried && firstProblem}<span class="problem" id="{uid}-first-problem" role="alert">{firstProblem}</span>{/if}
			</div>
			{@render preview()}
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
				<li>The lending Fund applies it at its servicing event; you don’t need to sign again.</li>
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
