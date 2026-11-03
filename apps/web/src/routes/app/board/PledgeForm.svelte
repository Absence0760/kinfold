<script lang="ts">
	import { tick } from 'svelte';
	import {
		formatCents,
		parseDollars,
		payeeLabel,
		pledgeAmountProblem,
		quickAmounts,
		type BoardItem
	} from '#lib/board/board.ts';
	import { supabase } from '#lib/supabase/client.ts';
	import { loadRaised, pledgeGift } from '#lib/board/data.ts';

	let {
		item,
		name,
		leftCents,
		onpledged
	}: {
		item: BoardItem;
		/** A short form of the request's summary, added (visually hidden) to each button's name. */
		name: string;
		leftCents: number;
		onpledged: (raisedCents: number | null) => void;
	} = $props();

	type Step = 'closed' | 'amount' | 'confirm' | 'sending' | 'done';
	let step = $state<Step>('closed');
	let typed = $state('');
	let touched = $state(false);
	let error = $state<string | null>(null);
	let pledgedCents = $state(0);

	let amountInput = $state<HTMLInputElement>();
	let confirmHeading = $state<HTMLElement>();
	let doneNote = $state<HTMLElement>();
	let openButton = $state<HTMLButtonElement>();

	const cents = $derived(parseDollars(typed));
	const problem = $derived(pledgeAmountProblem(cents, leftCents));
	const uid = $derived(`pledge-${item.id}`);

	async function open() {
		step = 'amount';
		error = null;
		await tick();
		amountInput?.focus();
	}

	async function cancel() {
		if (step === 'sending') return;
		step = 'closed';
		typed = '';
		touched = false;
		error = null;
		await tick();
		openButton?.focus();
	}

	function pick(c: number) {
		typed = (c / 100).toFixed(c % 100 === 0 ? 0 : 2);
		touched = true;
	}

	async function change() {
		if (step === 'sending') return;
		step = 'amount';
		await tick();
		amountInput?.focus();
	}

	async function review(e: SubmitEvent) {
		e.preventDefault();
		touched = true;
		if (problem || cents == null) return;
		step = 'confirm';
		await tick();
		confirmHeading?.focus();
	}

	async function send() {
		// aria-disabled keeps the buttons focusable while sending, so guard here instead.
		if (cents == null || step === 'sending') return;
		step = 'sending';
		error = null;
		try {
			await pledgeGift(supabase(), item.id, cents);
			pledgedCents = cents;
			step = 'done';
			onpledged(await loadRaised(supabase(), item.id));
			await tick();
			doneNote?.focus();
		} catch (err) {
			error = err instanceof Error ? err.message : 'The pledge did not go through.';
			step = 'confirm';
			await tick();
			confirmHeading?.focus();
		}
	}
</script>

{#if step === 'closed'}
	<button type="button" class="btn btn-primary small" bind:this={openButton} onclick={open}>
		Pledge a gift<span class="visually-hidden"> to “{name}”</span>
	</button>
{:else if step === 'amount'}
	<form class="panel" onsubmit={review} novalidate>
		<label for="{uid}-amount">How much would you like to give?</label>
		<div class="quick" role="group" aria-label="Quick amounts">
			{#each quickAmounts(leftCents) as c (c)}
				<button type="button" class="chip" onclick={() => pick(c)}>
					{c === leftCents ? `The rest, ${formatCents(c)}` : formatCents(c)}
				</button>
			{/each}
		</div>
		<div class="field">
			<span aria-hidden="true">$</span>
			<input
				id="{uid}-amount"
				bind:this={amountInput}
				bind:value={typed}
				onblur={() => (touched = typed !== '' || touched)}
				inputmode="decimal"
				autocomplete="off"
				aria-describedby="{uid}-hint{touched && problem ? ` ${uid}-problem` : ''}"
				aria-errormessage={touched && problem ? `${uid}-problem` : undefined}
				aria-invalid={touched && problem ? 'true' : undefined}
			/>
		</div>
		<p class="hint" id="{uid}-hint">Up to {formatCents(leftCents)}, what this request still needs.</p>
		{#if touched && problem}
			<p class="problem" id="{uid}-problem" role="alert">{problem}</p>
		{/if}
		<div class="actions">
			<button type="submit" class="btn btn-primary small">
				Review pledge<span class="visually-hidden"> to “{name}”</span>
			</button>
			<button type="button" class="btn btn-ghost small" onclick={cancel}>
				Cancel<span class="visually-hidden"> the pledge to “{name}”</span>
			</button>
		</div>
	</form>
{:else if step === 'confirm' || step === 'sending'}
	<div class="panel" role="group" aria-labelledby="{uid}-confirm" aria-busy={step === 'sending'}>
		<p class="confirm-title" id="{uid}-confirm" tabindex="-1" bind:this={confirmHeading}>
			Give {formatCents(cents ?? 0)} to this request?
		</p>
		<ul class="terms">
			<li>It's a gift, not a loan: it isn't paid back.</li>
			<li>
				The money goes to {payeeLabel(item.kind)}, not to the member. Kinfold never holds it; the
				payment partner collects your gift and pays them directly.
			</li>
			<li>Your gift isn't shown on the board, and who gave never changes a request's place.</li>
		</ul>
		{#if error}
			<p class="problem" role="alert">{error}</p>
		{/if}
		<!-- Mounted with the panel and empty, so the text change is announced. -->
		<p class="visually-hidden" role="status">{step === 'sending' ? 'Sending your pledge…' : ''}</p>
		<div class="actions">
			<button
				type="button"
				class="btn btn-primary small"
				onclick={send}
				aria-disabled={step === 'sending'}
				aria-busy={step === 'sending'}
			>
				{step === 'sending' ? 'Pledging…' : `Pledge ${formatCents(cents ?? 0)}`}<span class="visually-hidden">
					to “{name}”</span
				>
			</button>
			<button type="button" class="btn btn-ghost small" onclick={change} aria-disabled={step === 'sending'}>
				Change amount<span class="visually-hidden"> for “{name}”</span>
			</button>
			<button type="button" class="btn btn-ghost small" onclick={cancel} aria-disabled={step === 'sending'}>
				Cancel<span class="visually-hidden"> the pledge to “{name}”</span>
			</button>
		</div>
	</div>
{:else}
	<p class="done" tabindex="-1" bind:this={doneNote} role="status">
		Thank you. You pledged {formatCents(pledgedCents)}. It's kept in your own giving record, which
		only you can see.
	</p>
{/if}

<style>
	.small {
		min-height: 44px;
		justify-content: center;
		padding: 8px 18px;
		font-size: 14px;
	}

	.btn[aria-disabled='true'] {
		opacity: 0.6;
		cursor: progress;
	}

	.panel {
		display: grid;
		gap: 10px;
		padding: 14px;
		border-radius: 10px;
		background: var(--surface-2);
	}

	label,
	.confirm-title {
		font-weight: 600;
	}

	.quick {
		display: flex;
		flex-wrap: wrap;
		gap: 8px;
	}

	.chip {
		font: inherit;
		font-size: 14px;
		padding: 8px 14px;
		min-height: 44px;
		border-radius: 999px;
		border: 1px solid var(--border);
		background: var(--surface);
		color: var(--text);
		cursor: pointer;
	}

	.field {
		display: flex;
		align-items: center;
		gap: 6px;
		max-width: 220px;
		background: var(--surface);
		border: 1px solid var(--field-border);
		border-radius: 8px;
		padding: 0 10px;
	}

	.field input {
		font: inherit;
		border: 0;
		background: transparent;
		color: var(--text);
		padding: 10px 0;
		min-height: 44px;
		box-sizing: border-box;
		font-variant-numeric: tabular-nums;
		width: 100%;
		min-width: 0;
	}

	.field:focus-within {
		outline: 3px solid var(--warm);
		outline-offset: 2px;
	}

	.field input:focus-visible {
		outline: none;
	}

	.hint {
		font-size: 13px;
		color: var(--muted);
	}

	.problem {
		font-size: 14px;
		color: var(--text);
		font-weight: 600;
		border-left: 4px solid var(--warm);
		padding-left: 10px;
	}

	.terms {
		margin: 0;
		padding-left: 18px;
		font-size: 14px;
		display: grid;
		gap: 4px;
	}

	.actions {
		display: flex;
		flex-wrap: wrap;
		gap: 8px;
	}

	.done {
		font-size: 14px;
		color: var(--text);
		border-left: 4px solid var(--accent);
		padding-left: 10px;
		font-weight: 600;
	}
</style>
