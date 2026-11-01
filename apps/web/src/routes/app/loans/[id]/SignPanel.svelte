<script lang="ts">
	import { tick } from 'svelte';
	import { supabase } from '#lib/supabase/client.ts';
	import { formatCents, formatDay } from '#lib/dashboard/format.ts';
	import { defaultPlanText } from '#lib/dashboard/labels.ts';
	import { signLoan } from '#lib/loans/data.ts';
	import { explainLoanError } from '#lib/loans/errors.ts';
	import type { InstallmentRow, LoanDetailRow, Side, Signatures } from '#lib/loans/loan.ts';
	import { monthsWord, ordinal } from '#lib/loans/words.ts';
	import Panel from './Panel.svelte';

	let {
		loan,
		side,
		signed,
		installments,
		scheduleMatches,
		onchanged
	}: {
		loan: LoanDetailRow;
		side: Side;
		signed: Signatures;
		installments: InstallmentRow[];
		scheduleMatches: boolean;
		onchanged: (message: string) => Promise<void>;
	} = $props();

	type Step = 'closed' | 'confirm' | 'sending';
	let step = $state<Step>('closed');
	let error = $state('');
	let openButton = $state<HTMLButtonElement>();
	let confirmTitle = $state<HTMLElement>();

	const uid = $derived(`sign-${loan.id}`);
	const them = $derived(side === 'borrower' ? 'your lender' : 'the borrower');
	const youRepay = $derived(side === 'borrower');

	async function open() {
		error = '';
		step = 'confirm';
		await tick();
		confirmTitle?.focus();
	}

	async function close() {
		// The buttons stay focusable while sending (aria-disabled), so guard here.
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
			const next = await signLoan(supabase(), loan.id);
			step = 'closed';
			await onchanged(
				next === 'signed'
					? 'You both signed. The loan starts once the request is paid and the money reaches the payee.'
					: `You signed. Now it’s ${them}’s turn.`
			);
		} catch (err) {
			error = explainLoanError(err as { message?: string; code?: string });
			step = 'confirm';
			await tick();
			confirmTitle?.focus();
		}
	}
</script>

<Panel id="{uid}-h" title="Signatures" intro="The loan is agreed only once you have both signed the same terms and schedule.">
	<ul class="terms">
		<li>
			<strong>You:</strong>
			{signed.you ? `signed ${formatDay(signed.you)}` : 'not signed yet'}
		</li>
		<li>
			<strong>{side === 'borrower' ? 'Your lender' : 'The borrower'}:</strong>
			{signed.them ? `signed ${formatDay(signed.them)}` : 'not signed yet'}
		</li>
	</ul>

	{#if signed.you}
		<p class="hint">You’ve signed. If either of you changes the terms or schedule, both signatures are cleared.</p>
	{:else if !scheduleMatches}
		<p class="hint">Set a repayment schedule first. It has to add up to exactly the amount lent before anyone signs.</p>
	{:else if step === 'closed'}
		<div class="actions">
			<button type="button" class="btn btn-primary" bind:this={openButton} onclick={open}>Read and sign</button>
		</div>
	{:else}
		{@const last = installments[installments.length - 1]}
		<div class="step" role="group" aria-labelledby="{uid}-confirm">
			<p class="confirm-title" id="{uid}-confirm" tabindex="-1" bind:this={confirmTitle}>Sign this loan?</p>
			<p>By signing, you agree that:</p>
			<ul class="terms">
				<li>
					{youRepay ? 'You repay' : 'The borrower repays you'} <strong>{formatCents(loan.principal_cents)}</strong>, exactly what
					was lent, in {installments.length} monthly payment{installments.length === 1 ? '' : 's'} on the
					{ordinal(loan.payment_day)}, from {formatDay(installments[0].due_on)} to {formatDay(last.due_on)}.
				</li>
				<li>There is no interest and there are no late fees, ever. Repaying early is always allowed.</li>
				<li>
					{loan.pause_months_per_year === 0
						? 'There are no pauses without asking.'
						: `The borrower can pause up to ${monthsWord(loan.pause_months_per_year)} in any 12 without asking. A pause moves payments later and never adds to the total.`}
				</li>
				<li>If repayments stop for good, {defaultPlanText(loan.default_plan)}.</li>
				<li>After you both sign, the terms are fixed. Changing them needs a new agreement between you.</li>
			</ul>
			{#if error}<p class="problem" role="alert">{error}</p>{/if}
			<div class="actions">
				<button type="button" class="btn btn-primary" onclick={sign} aria-disabled={step === 'sending'} aria-busy={step === 'sending'}>
					{step === 'sending' ? 'Signing…' : 'Sign the loan'}
				</button>
				<button type="button" class="btn btn-ghost" onclick={close} aria-disabled={step === 'sending'}>Not yet</button>
			</div>
		</div>
	{/if}
</Panel>
