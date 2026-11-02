<script lang="ts">
	import { tick } from 'svelte';
	import { supabase } from '#lib/supabase/client.ts';
	import { explainDbError } from '#lib/review/errors.ts';
	import { NEEDS_DECISIONS, needsDecisionLabel, type NeedsDecision } from '#lib/review/labels.ts';
	import { recordNeedsDecision } from '#lib/review/queries.ts';
	import { needsOutcome } from '#lib/review/queue.ts';
	import { cleanReason, reasonCounter, reasonProblem } from '#lib/review/reason.ts';

	let { requestId, ondecided }: { requestId: string; ondecided: (message: string) => void } = $props();

	const id = $derived(`needs-${requestId}`);

	let answer = $state<NeedsDecision | ''>('');
	let reason = $state('');
	let tried = $state(false);
	let busy = $state(false);
	let error = $state('');
	let formEl = $state<HTMLFormElement | null>(null);
	let reasonEl = $state<HTMLTextAreaElement | null>(null);

	const answerError = $derived(tried && answer === '' ? 'Choose an answer.' : null);
	const reasonError = $derived(tried ? reasonProblem(reason) : null);

	async function submit(e: SubmitEvent) {
		e.preventDefault();
		if (busy) return;
		tried = true;
		error = '';
		if (answer === '' || reasonProblem(reason)) {
			// Send keyboard and screen-reader users to the first thing to fix.
			await tick();
			if (answer === '') formEl?.querySelector<HTMLInputElement>('input[type="radio"]')?.focus();
			else reasonEl?.focus();
			return;
		}
		busy = true;
		try {
			await recordNeedsDecision(supabase(), requestId, answer, cleanReason(reason));
			const message = needsOutcome(answer);
			// Start clean so the next edge case isn't pre-filled with this one.
			answer = '';
			reason = '';
			tried = false;
			ondecided(message);
		} catch (err) {
			error = explainDbError(err as { message?: string; code?: string });
		} finally {
		busy = false;
		}
	}
</script>

<form class="needs" onsubmit={submit} novalidate aria-labelledby="{id}-decide" bind:this={formEl}>
	<h4 id="{id}-decide">Needs decision</h4>
	<p class="note small">
		Only an answer at a person's own judgement, with a written reason. The published score is never edited.
	</p>
	<fieldset aria-describedby={answerError ? `${id}-answer-error` : undefined}>
		<legend class="visually-hidden">Answer</legend>
		{#each NEEDS_DECISIONS as option (option.value)}
			<label class="option" class:chosen={answer === option.value}>
				<input
					type="radio"
					name="{id}-answer"
					value={option.value}
				bind:group={answer}
				disabled={busy}
				/>
				<span>
					<strong>{needsDecisionLabel(option.value)}</strong>
					<span class="muted">{option.effect}</span>
				</span>
			</label>
		{/each}
		{#if answerError}
			<p class="field-error" id="{id}-answer-error">{answerError}</p>
		{:else}
			<span></span>
		{/if}
	</fieldset>

	<div class="reason">
		<label class="label" for="{id}-reason">Reason</label>
		<span class="muted hint" id="{id}-reason-hint">
			Say what the ranking got wrong — the applicant reads this answer without your name.
		</span>
	</div>
	<textarea
		id="{id}-reason"
	rows="4"
	bind:this={reasonEl}
	bind:value={reason}
	readonly={busy}
	aria-required="true"
	aria-invalid={reasonError ? 'true' : undefined}
	aria-describedby="{id}-reason-hint{reasonError ? ` ${id}-reason-error` : ''} {id}-reason-count"
	></textarea>
	<div class="under">
		{#if reasonError}
			<p class="field-error" id="{id}-reason-error">{reasonError}</p>
		{:else}
			<span></span>
		{/if}
		<span class="muted small" id="{id}-reason-count">{reasonCounter(reason)}</span>
	</div>

	{#if error}
		<p class="notice" role="alert">{error}</p>
	{/if}

	<button class="btn btn-primary" type="submit" aria-disabled={busy} aria-busy={busy}>
		{busy ? 'Saving…' : 'Record answer'}
	</button>
</form>

<style>
	.needs {
		justify-self: stretch;
	}

	.needs .option {
		justify-content: start;
	}
</style>
