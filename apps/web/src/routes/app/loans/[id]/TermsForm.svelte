<script lang="ts">
	import { tick } from 'svelte';
	import { supabase } from '#lib/supabase/client.ts';
	import { formatDay } from '#lib/dashboard/format.ts';
	import { defaultPlanText, type DefaultPlan } from '#lib/dashboard/labels.ts';
	import { setLoanTerms } from '#lib/loans/data.ts';
	import { explainLoanError } from '#lib/loans/errors.ts';
	import type { InstallmentRow, LoanDetailRow } from '#lib/loans/loan.ts';
	import { MAX_PAYMENT_DAY, moveToPaymentDay } from '#lib/loans/schedule.ts';
	import { ordinal } from '#lib/loans/words.ts';
	import Panel from './Panel.svelte';

	let {
		loan,
		installments,
		anySigned,
		onchanged
	}: {
		loan: LoanDetailRow;
		installments: InstallmentRow[];
		anySigned: boolean;
		onchanged: (message: string) => Promise<void>;
	} = $props();

	type Step = 'closed' | 'edit' | 'confirm' | 'sending';
	let step = $state<Step>('closed');
	let day = $state(1);
	let pauses = $state(3);
	let plan = $state<DefaultPlan>('mediate');
	let error = $state('');

	let openButton = $state<HTMLButtonElement>();
	let firstField = $state<HTMLSelectElement>();
	let confirmTitle = $state<HTMLElement>();

	const uid = $derived(`terms-${loan.id}`);
	const days = Array.from({ length: MAX_PAYMENT_DAY }, (_, i) => i + 1);
	const months = Array.from({ length: 13 }, (_, i) => i);
	const plans: { value: DefaultPlan; title: string; detail: string }[] = [
		{
			value: 'mediate',
			title: 'Go to a mediator',
			detail: 'A neutral mediator helps you agree what happens next. Nothing is decided for you.'
		},
		{
			value: 'forgive',
			title: 'Forgive the rest as a gift',
			detail: 'Whatever is left becomes a gift from the lender. Nothing more is owed.'
		},
		{
			value: 'repay_on_sale',
			title: 'Repay when the home is sold or refinanced',
			detail: 'Only for loans secured by a lien on the home. Nobody forces a sale.'
		}
	];

	const moved = $derived(
		installments.length > 0
			? {
					first: moveToPaymentDay(installments[0].due_on, day),
					last: moveToPaymentDay(installments[installments.length - 1].due_on, day)
				}
			: null
	);
	const changed = $derived(
		day !== loan.payment_day || pauses !== loan.pause_months_per_year || plan !== loan.default_plan
	);

	async function open() {
		day = loan.payment_day;
		pauses = loan.pause_months_per_year;
		plan = loan.default_plan;
		error = '';
		step = 'edit';
		await tick();
		firstField?.focus();
	}

	async function close() {
		step = 'closed';
		await tick();
		openButton?.focus();
	}

	async function goBack() {
		step = 'edit';
		await tick();
		firstField?.focus();
	}

	async function review(e: SubmitEvent) {
		e.preventDefault();
		if (!changed) return;
		step = 'confirm';
		await tick();
		confirmTitle?.focus();
	}

	async function save() {
		if (step === 'sending') return;
		step = 'sending';
		error = '';
		try {
			await setLoanTerms(supabase(), loan.id, day, pauses, plan);
			step = 'closed';
			await onchanged(
				anySigned ? 'Terms saved. The signatures were cleared, so you both sign again.' : 'Terms saved.'
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
	title="Terms"
	intro="Either of you can propose the terms. Any change clears both signatures, so nothing is agreed until you have both signed the same version."
>
	{#if step === 'closed'}
		<div class="actions">
			<button type="button" class="btn btn-ghost" bind:this={openButton} onclick={open}>Change the terms</button>
		</div>
	{:else if step === 'edit'}
		<form onsubmit={review} novalidate>
			<div class="field">
				<label for="{uid}-day">Payment day</label>
				<select id="{uid}-day" bind:this={firstField} bind:value={day} aria-describedby="{uid}-day-hint">
					{#each days as d (d)}
						<option value={d}>The {ordinal(d)} of each month</option>
					{/each}
				</select>
				<span class="hint" id="{uid}-day-hint">
					The day the payment partner collects each installment. Pick one just after the borrower’s payday.
				</span>
			</div>

			<div class="field">
				<label for="{uid}-pauses">Pause allowance</label>
				<select id="{uid}-pauses" bind:value={pauses} aria-describedby="{uid}-pause-hint">
					{#each months as m (m)}
						<option value={m}>{m === 0 ? 'No pauses' : `Up to ${m} month${m === 1 ? '' : 's'} a year`}</option>
					{/each}
				</select>
				<span class="hint" id="{uid}-pause-hint">
					How many months in any 12 the borrower can pause without asking. A pause moves payments later; it
					never adds to what’s owed.
				</span>
			</div>

			<fieldset>
				<legend>If repayments stop for good</legend>
				{#each plans as p (p.value)}
					{@const blocked = p.value === 'repay_on_sale' && !loan.secured}
					<label class="option">
						<input type="radio" name="{uid}-plan" value={p.value} bind:group={plan} disabled={blocked} />
						<span>
							<strong>{p.title}</strong>
							<span class="sub">{blocked ? 'Not available: this loan isn’t secured by a lien.' : p.detail}</span>
						</span>
					</label>
				{/each}
			</fieldset>

			{#if moved}
				<div class="preview" aria-live="polite">
					<p>
						The schedule keeps its months and amounts and moves to the {ordinal(day)}: first payment
						{formatDay(moved.first)}, last {formatDay(moved.last)}.
					</p>
				</div>
			{/if}

			{#if !changed}<p class="hint" id="{uid}-nochange">Change something to save new terms.</p>{/if}
			<div class="actions">
				<button type="submit" class="btn btn-primary" disabled={!changed} aria-describedby={changed ? undefined : `${uid}-nochange`}>Review the new terms</button>
				<button type="button" class="btn btn-ghost" onclick={close}>Cancel</button>
			</div>
		</form>
	{:else}
		<div class="step" role="group" aria-labelledby="{uid}-confirm">
			<p class="confirm-title" id="{uid}-confirm" tabindex="-1" bind:this={confirmTitle}>Save these terms?</p>
			<ul class="terms">
				<li>Payments on the {ordinal(day)} of each month.</li>
				<li>{pauses === 0 ? 'No pauses without asking.' : `Up to ${pauses} pause month${pauses === 1 ? '' : 's'} a year, without asking.`}</li>
				<li>If repayments stop for good, {defaultPlanText(plan)}.</li>
				<li>Still zero interest and no late fees. The total to repay doesn’t change.</li>
				{#if anySigned}
					<li><strong>This clears the signatures already given.</strong> You both sign again.</li>
				{/if}
			</ul>
			{#if error}<p class="problem" role="alert">{error}</p>{/if}
			<div class="actions">
				<button type="button" class="btn btn-primary" onclick={save} disabled={step === 'sending'} aria-busy={step === 'sending'}>
					{step === 'sending' ? 'Saving…' : 'Save the terms'}
				</button>
				<button type="button" class="btn btn-ghost" onclick={goBack} disabled={step === 'sending'}>
					Go back
				</button>
			</div>
		</div>
	{/if}
</Panel>
