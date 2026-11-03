<script lang="ts">
	import { tick } from 'svelte';
	import { supabase } from '#lib/supabase/client.ts';
	import { signLoanRestructure } from '#lib/loans/data.ts';
	import { explainLoanError } from '#lib/loans/errors.ts';
	import { formatCents, formatDay } from '#lib/dashboard/format.ts';
	import { monthsWord } from '#lib/loans/words.ts';
	import Panel from './Panel.svelte';

	let { ask, owedCents, onchanged }: {
		ask: { loan_id: string; months: number; first_due: string };
		owedCents: number;
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

	async function sign() {
		if (step === 'sending') return;
		step = 'sending';
		error = '';
		try {
			await signLoanRestructure(supabase(), ask.loan_id);
			step = 'closed';
			await onchanged(`Signed: the unpaid ${formatCents(owedCents)} now re-spreads over ${monthsWord(ask.months)}.`);
		} catch (err) {
			error = explainLoanError(err as { message?: string; code?: string });
			step = 'confirm';
			await tick();
			confirmTitle?.focus();
		}
	}
</script>

<Panel
	id="sign-{ask.loan_id}-h"
	title="Sign on the restructure?"
	intro="The other side staged a new schedule for what is still owed. Signing agrees to it; nothing moves until you do."
>
	{#if step === 'closed'}
		<div class="actions">
			<button type="button" class="btn btn-ghost" bind:this={openButton} onclick={open}>Sign on it</button>
		</div>
	{:else}
		<div class="step" role="group" aria-labelledby="sign-{ask.loan_id}-confirm">
			<p class="confirm-title" id="sign-{ask.loan_id}-confirm" tabindex="-1" bind:this={confirmTitle}>Sign on this restructure?</p>
			<ul class="terms">
				<li>Payments already made stay put; only what is still owed moves.</li>
				<li>The new plan spreads it over {monthsWord(ask.months)} payments from {formatDay(ask.first_due)}, total owed unchanged.</li>
				<li>Signing is your agreement: the record will show you both signed on it.</li>
			</ul>
			{#if error}<p class="problem" role="alert">{error}</p>{/if}
			<div class="actions">
				<button type="button" class="btn btn-primary" onclick={sign} aria-disabled={step === 'sending'} aria-busy={step === 'sending'}>
					{step === 'sending' ? 'Signing…' : 'Sign on the restructure'}
				</button>
				<button type="button" class="btn btn-ghost" onclick={close} aria-disabled={step === 'sending'}>
					Not now
				</button>
			</div>
		</div>
	{/if}
</Panel>
