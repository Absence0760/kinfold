<script lang="ts">
	import { tick } from 'svelte';
	import { supabase } from '#lib/supabase/client.ts';
	import { formatCents, formatDay } from '#lib/dashboard/format.ts';
	import { resumeLoan } from '#lib/loans/data.ts';
	import { explainLoanError } from '#lib/loans/errors.ts';
	import Panel from './Panel.svelte';

	let {
		loanId,
		pausedUntil,
		next,
		onchanged
	}: {
		loanId: string;
		pausedUntil: string | null;
		next: { dueOn: string; owedCents: number } | null;
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
		// The buttons stay focusable while sending (aria-disabled), so guard here.
		if (step === 'sending') return;
		step = 'closed';
		await tick();
		openButton?.focus();
	}

	async function resume() {
		if (step === 'sending') return;
		step = 'sending';
		error = '';
		try {
			await resumeLoan(supabase(), loanId);
			step = 'closed';
			await onchanged('Payments resumed on the moved-back dates.');
		} catch (err) {
			error = explainLoanError(err as { message?: string; code?: string });
			step = 'confirm';
			await tick();
			confirmTitle?.focus();
		}
	}
</script>

<Panel
	id="resume-{loanId}-h"
	title="Ready to start again?"
	intro={pausedUntil
		? `The pause ends on its own on ${formatDay(pausedUntil)}. You can resume earlier.`
		: 'You can resume whenever you like.'}
>
	{#if step === 'closed'}
		<div class="actions">
			<button type="button" class="btn btn-ghost" bind:this={openButton} onclick={open}>Resume payments now</button>
		</div>
	{:else}
		<div class="step" role="group" aria-labelledby="resume-{loanId}-confirm">
			<p class="confirm-title" id="resume-{loanId}-confirm" tabindex="-1" bind:this={confirmTitle}>
				Resume payments now?
			</p>
			<ul class="terms">
				<li>
					Payments are collected again on their moved-back dates{next
						? `, starting with ${formatCents(next.owedCents)} on ${formatDay(next.dueOn)}`
						: ''}.
				</li>
				<li>The dates don’t move forward again, so resuming early never makes a payment due sooner.</li>
				<li>Pause months you’ve used still count toward this year’s allowance.</li>
			</ul>
			{#if error}<p class="problem" role="alert">{error}</p>{/if}
			<div class="actions">
				<button type="button" class="btn btn-primary" onclick={resume} aria-disabled={step === 'sending'} aria-busy={step === 'sending'}>
					{step === 'sending' ? 'Resuming…' : 'Resume payments'}
				</button>
				<button type="button" class="btn btn-ghost" onclick={close} aria-disabled={step === 'sending'}>Stay paused</button>
			</div>
		</div>
	{/if}
</Panel>
