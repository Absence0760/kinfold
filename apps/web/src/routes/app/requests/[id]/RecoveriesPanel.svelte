<script lang="ts">
	import { tick } from 'svelte';
	import { supabase } from '#lib/supabase/client.ts';
	import { explainRequestError } from '#lib/requests/errors.ts';
	import { formatCents, formatDay } from '#lib/dashboard/format.ts';
	import { recordRecovery, recoveryLabel, recoveryTotalCents, type RecoveryRow } from '#lib/requests/recoveries.ts';
	import { parseDollars } from '#lib/board/board.ts';
	import Badge from '../Badge.svelte';
	import type { Tone } from '#lib/dashboard/labels.ts';

	let { requestId, recoveries, onadded }: { requestId: string; recoveries: RecoveryRow[]; onadded: (message: string) => void } = $props();

	const uid = 'recoveries';

	let source = $state('');
	let amount = $state('');
	let date = $state('');
	let note = $state('');
	let tried = $state(false);
	let busy = $state(false);
	let error = $state('');
	let formEl = $state<HTMLFormElement | null>(null);
	let sourceSelect = $state<HTMLSelectElement | null>(null);
	let amountInput = $state<HTMLInputElement | null>(null);
	let dateInput = $state<HTMLInputElement | null>(null);

	const cents = $derived(parseDollars(amount));
	const dateOk = $derived(/^\d{4}-\d{2}-\d{2}$/.test(date));
	const problem = $derived(tried ? amountProblem() : null);

	function amountProblem(): string | null {
		if (source === '') return 'Choose what the money came from.';
		if (cents === null) return 'Enter the amount in dollars, like 400 or 25.50.';
		if (!dateOk) return 'Enter the day it moved as YYYY-MM-DD.';
		return null;
	}

	async function submit(e: SubmitEvent) {
		e.preventDefault();
		if (busy) return;
		tried = true;
		error = '';
		const problemNow = amountProblem();
		if (problemNow || cents === null) {
			await tick();
			if (source === '') sourceSelect?.focus();
			else if (cents === null) amountInput?.focus();
			else dateInput?.focus();
			return;
		}
		busy = true;
		try {
			// The schema checks the same bounds; a partner-confirmed money is
			// written by the service later.
			await recordRecovery(supabase(), requestId, source, cents, date, note.trim() === '' ? null : note.trim());
			source = '';
			amount = '';
			date = '';
			note = '';
			tried = false;
			onadded('Recorded. Pledge caps and the pool run subtract this money from what is still needed.');
		} catch (err) {
			error = explainRequestError(err as { message?: string; code?: string });
		} finally {
			busy = false;
		}
	}
</script>

<div class="recoveries">
	{#if recoveries.length}
		<ul class="recorded" role="list">
			{#each recoveries as row}
				<li>{formatCents(row.amount_cents)} as {recoveryLabel(row.source)} on {row.on}</li>
			{/each}
		</ul>
		<p class="muted">Total for the same damage: {formatCents(recoveryTotalCents(recoveries))}. It is money that moved outside Kinfold; funding, payout caps and refunds still look only at pledges and payouts.</p>
	{:else}
		<p class="empty">No other money recorded yet. If the damage was partly covered by another insurer, a programme or your own deductible, record it — the pledges asked for drop by it.</p>
	{/if}
	<form class="record" onsubmit={submit} novalidate bind:this={formEl}>
		<label for="{uid}-source">The money came from</label>
		<select bind:value={source} bind:this={sourceSelect} disabled={busy}>
			<option value="own_cover">my own deductible cover</option>
			<option value="insurance">another insurer's claim</option>
			<option value="fema">a federal disaster programme</option>
			<option value="sba">the Small Business Administration</option>
			<option value="state">a state programme</option>
			<option value="charity">a charity fund</option>
			<option value="other">something else</option>
		</select>
		<label for="{uid}-amount">Amount (dollars)</label>
		<input type="text" id="{uid}-amount" bind:value={amount} bind:this={amountInput} disabled={busy} autocomplete="off" />
		<label for="{uid}-date">The day it moved (YYYY-MM-DD)</label>
		<input type="text" id="{uid}-date" bind:value={date} bind:this={dateInput} disabled={busy} autocomplete="off" />
		<label for="{uid}-note">A note (optional)</label>
		<input type="text" id="{uid}-note" bind:value={note} disabled={busy} autocomplete="off" />
		{#if problem}<p class="problem" id="{uid}-problem" role="alert">{problem}</p>{/if}
		<div>
			<button type="submit" class="btn btn-primary" aria-disabled={busy ? 'true' : undefined}>
				{busy ? 'Recording…' : 'Record this money'}
			</button>
		</div>
		{#if error}<p class="problem" role="alert">{error}</p>{/if}
	</form>
</div>
