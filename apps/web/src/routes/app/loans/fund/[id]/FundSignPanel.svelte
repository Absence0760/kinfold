<script lang="ts">
	import { tick } from 'svelte';
	import { supabase } from '#lib/supabase/client.ts';
	import { formatCents } from '#lib/dashboard/format.ts';
	import { signFundLoan } from '#lib/loans/fund.ts';
	import type { FundLoanRow } from '#lib/loans/fund.ts';
	import { explainLoanError } from '#lib/loans/errors.ts';
	import Panel from '../../Panel.svelte';

	let { loan, outstandingCents, onchanged }: {
		loan: FundLoanRow;
		outstandingCents: number;
		onchanged: (message: string) => Promise<void>;
	} = $props();

	type Step = 'closed' | 'confirm' | 'sending';
	let step = $state<Step>('closed');
	let error = $state('');
	let openButton = $state<HTMLButtonElement>();
	let confirmTitle = $state<HTMLElement>();

	async function open() {
		error = '';
		step = 'confirm';
		await tick();
		confirmTitle?.focus();
	}

	async function close() {
		if (step === 'sending') return;
		step = 'closed';
		await tick();
		openButton?.focus();
	}

	async function sign() {
		if (step === 'sending') return;
		step = 'sending';
		error = '';
		try {
			await signFundLoan(supabase(), loan.id);
			step = 'closed';
			await onchanged('Signed. Payments start when the lending partner disburses the loan.');
		} catch (err) {
			error = explainLoanError(err as { message?: string; code?: string });
			step = 'confirm';
			await tick();
			confirmTitle?.focus();
		}
	}
</script>

<Panel
	id="sign-{loan.id}-h"
	title="Your side of the agreement"
	intro="The lending Fund signs at once; you sign your own side here."
>
	{#if step === 'closed'}
		<div class="actions">
			<button type="button" class="btn btn-ghost" bind:this={openButton} onclick={open}>Sign this loan</button>
		</div>
	{:else}
		<div class="step" role="group" aria-labelledby="sign-{loan.id}-confirm">
			<p class="confirm-title" id="sign-{loan.id}-confirm" tabindex="-1" bind:this={confirmTitle}>
				Sign this loan?
			</p>
			<ul class="terms">
				<li>You agree to repay {formatCents(outstandingCents)} to the lending Fund, with no interest added.</li>
				<li>Payments are collected on the loan’s schedule, and only once the lending partner disburses the money.</li>
				<li>You can pause and ask for a new schedule later; signing doesn’t lock you into payments.</li>
			</ul>
			{#if error}<p class="problem" role="alert">{error}</p>{/if}
			<div class="actions">
				<button type="button" class="btn btn-primary" onclick={sign} aria-disabled={step === 'sending'} aria-busy={step === 'sending'}>
					{step === 'sending' ? 'Signing…' : 'Sign this loan'}
				</button>
				<button type="button" class="btn btn-ghost" onclick={close} aria-disabled={step === 'sending'}>Not now</button>
			</div>
		</div>
	{/if}
</Panel>
