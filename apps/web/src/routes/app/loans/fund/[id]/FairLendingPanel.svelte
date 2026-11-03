<script lang="ts">
	import { tick } from 'svelte';
	import { supabase } from '#lib/supabase/client.ts';
	import { offerFundLoanSelfTest, fundSelfTestProblem } from '#lib/loans/fund.ts';
	import type { FundLoanRow } from '#lib/loans/fund.ts';
	import { explainLoanError } from '#lib/loans/errors.ts';
	import Panel from '../../Panel.svelte';

	let { loan, onchanged }: {
		loan: FundLoanRow;
		onchanged: (message: string) => Promise<void>;
	} = $props();

	type Step = 'closed' | 'edit' | 'confirm' | 'sending';
	let step = $state<Step>('closed');
	let purpose = $state(false);
	let use = $state(false);
	let limit = $state(false);
	let retain = $state(false);
	let race = $state('Not reported');
	let ethnicity = $state('Not reported');
	let sex = $state('Not reported');
	let error = $state('');

	let openButton = $state<HTMLButtonElement>();
	let firstField = $state<HTMLInputElement>();
	let confirmTitle = $state<HTMLElement>();

	const uid = $derived(`fair-${loan.id}`);
	const acknowledged = $derived(purpose && use && limit && retain);
	const problem = $derived(fundSelfTestProblem(acknowledged));

	async function open() {
		purpose = false;
		use = false;
		limit = false;
		retain = false;
		race = 'Not reported';
		ethnicity = 'Not reported';
		sex = 'Not reported';
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

	async function offer() {
		if (step === 'sending') return;
		step = 'sending';
		error = '';
		try {
			await offerFundLoanSelfTest(supabase(), loan.id, acknowledged, race, ethnicity, sex);
			step = 'closed';
			await onchanged('Offered. The auditor keeps these answers; nothing else reads them.');
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
	title="Fair-lending self-test (voluntary)"
	intro="Fair-lending law says no one may be asked for race, ethnicity or sex — except on the government monitoring form for loans secured by the home, which the credit union fills, or here, if you choose to offer it yourself. It decides nothing about this loan; it only lets the lending Fund audit its own fairness."
>
	{#if step === 'closed'}
		<div class="actions">
			<button type="button" class="btn btn-ghost" bind:this={openButton} onclick={open}>
				Offer the self-test
			</button>
		</div>
	{:else if step === 'edit'}
		<form onsubmit={review} novalidate>
			<fieldset class="disclosures">
				<div class="field">
					<label for="{uid}-purpose">The collection’s purpose: the lending Fund keeps these answers only to audit that its lending serves every group fairly.</label>
					<input type="checkbox" id="{uid}-purpose" bind:checked={purpose} bind:this={firstField} />
				</div>
				<div class="field">
					<label for="{uid}-use">How they are collected: you type them here yourself. Nothing is looked up or estimated about you.</label>
					<input type="checkbox" id="{uid}-use" bind:checked={use} />
				</div>
				<div class="field">
					<label for="{uid}-limit">Their limits: the answers never decide whether you get a loan, how it is priced, or whether it is approved.</label>
					<input type="checkbox" id="{uid}-limit" bind:checked={limit} />
				</div>
				<div class="field">
					<label for="{uid}-retain">Keeping them: kept up to five years after you offer them, for the audit. Ask the auditor and they can be deleted sooner.</label>
					<input type="checkbox" id="{uid}-retain" bind:checked={retain} />
				</div>
			</fieldset>
			<div class="field">
				<label for="{uid}-race">Race</label>
				<select id="{uid}-race" bind:value={race}>
					<option value="Asian">Asian</option>
					<option value="Black">Black or African American</option>
					<option value="Hispanic">Hispanic or Latino American</option>
					<option value="American Indian">American Indian or Alaskan Native</option>
					<option value="White">White or European American</option>
					<option value="Not reported">Prefer not to say</option>
				</select>
			</div>
			<div class="field">
				<label for="{uid}-ethnicity">Ethnicity</label>
				<select id="{uid}-ethnicity" bind:value={ethnicity}>
					<option value="Hispanic or Latino">Hispanic or Latino</option>
					<option value="Not Hispanic or Latino">Not Hispanic or Latino</option>
					<option value="Not reported">Prefer not to say</option>
			</select>
			</div>
			<div class="field">
				<label for="{uid}-sex">Sex</label>
				<select id="{uid}-sex" bind:value={sex}>
					<option value="Male">Male</option>
					<option value="Female">Female</option>
					<option value="Not reported">Prefer not to say</option>
			</select>
			</div>
			{#if problem}<p class="problem" id="{uid}-problem" role="alert">{problem}</p>{/if}
			<div class="actions">
				<button type="submit" class="btn btn-primary" aria-disabled={!!problem} aria-describedby={problem ? `${uid}-problem` : undefined}>
					Review the self-test
				</button>
				<button type="button" class="btn btn-ghost" onclick={close}>Cancel</button>
			</div>
		</form>
	{:else}
		<div class="step" role="group" aria-labelledby="{uid}-confirm">
			<p class="confirm-title" id="{uid}-confirm" tabindex="-1" bind:this={confirmTitle}>
				Offer the self-test on this loan?
			</p>
			<ul class="terms">
				<li>The lending Fund’s auditor keeps your answers for up to five years; the scorer, reviewers and panel never see them.</li>
				<li>Federal loan reports answer "Do Not Know" for this data until the credit union’s monitoring form says otherwise, so your offer is not federally reported.</li>
				<li>One offer per loan; it cannot be changed, only kept.</li>
			</ul>
			{#if error}<p class="problem" role="alert">{error}</p>{/if}
			<div class="actions">
				<button type="button" class="btn btn-primary" onclick={offer} aria-disabled={step === 'sending'} aria-busy={step === 'sending'}>
					{step === 'sending' ? 'Offering…' : 'Offer the self-test'}
				</button>
				<button type="button" class="btn btn-ghost" onclick={goBack} aria-disabled={step === 'sending'}>
					Go back
				</button>
			</div>
		</div>
	{/if}
</Panel>

<style>
	/* Compact checkboxes inside the disclosure rows: Panel's global rule sizes
	   text inputs, so override for checkboxes only. */
	input[type='checkbox'] {
		width: 20px;
		height: 20px;
		min-height: 20px;
		margin: 0;
		padding: 0;
		accent-color: var(--accent);
	}

</style>
