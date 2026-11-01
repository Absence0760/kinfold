<script lang="ts">
	import { tick } from 'svelte';
	import { supabase } from '#lib/supabase/client.ts';
	import { explainDbError } from '#lib/review/errors.ts';
	import {
		REVIEW_DECISIONS,
		decidedLabel,
		evidenceLabel,
		formatCents,
		formatDay,
		isReviewable,
		kindLabel,
		redactionLabel,
		statusLabel,
		type ReviewDecision
	} from '#lib/review/labels.ts';
	import { recordReview } from '#lib/review/queries.ts';
	import { reviewOutcome, type QueueItem } from '#lib/review/queue.ts';
	import { cleanReason, reasonCounter, reasonProblem } from '#lib/review/reason.ts';
	import ScoreBlock from './ScoreBlock.svelte';

	let { item, ondecided }: { item: QueueItem; ondecided: (message: string) => void } = $props();

	const r = $derived(item.request);
	const id = $derived(`req-${item.request.id}`);

	let decision = $state<ReviewDecision | ''>('');
	let reason = $state('');
	let tried = $state(false);
	let busy = $state(false);
	let error = $state('');
	let formEl = $state<HTMLFormElement | null>(null);
	let reasonEl = $state<HTMLTextAreaElement | null>(null);

	const reasonError = $derived(tried ? reasonProblem(reason) : null);
	const decisionError = $derived(tried && decision === '' ? 'Choose a decision.' : null);
	const submitLabel = $derived(decision === 'refuse' ? 'Refuse this request' : 'Record decision');

	async function submit(e: SubmitEvent) {
		e.preventDefault();
		if (busy) return;
		tried = true;
		error = '';
		if (decision === '' || reasonProblem(reason)) {
			// Send keyboard and screen-reader users to the first thing to fix.
			await tick();
			if (decision === '') formEl?.querySelector<HTMLInputElement>('input[type="radio"]')?.focus();
			else reasonEl?.focus();
			return;
		}
		busy = true;
		try {
			const next = await recordReview(supabase(), r.id, decision, cleanReason(reason));
			const message = reviewOutcome(decision, next);
			// Escalate and needs-evidence keep the request in the queue: start
			// the form clean so the next review isn't pre-filled with this one.
			decision = '';
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

<article class="card" aria-labelledby="{id}-title">
	<header class="head">
		<div>
			<p class="eyebrow">{kindLabel(r.kind)}</p>
			<h3 id="{id}-title">{formatCents(r.amount_cents)}</h3>
		</div>
		<span class="status" data-status={r.status}>{statusLabel(r.status)}</span>
	</header>

	<dl class="facts">
		<div>
			<dt>Incident</dt>
			<dd>{formatDay(r.incident_on)}</dd>
		</div>
		{#if r.submitted_at}
			<div>
				<dt>Submitted</dt>
				<dd>{formatDay(r.submitted_at)}</dd>
			</div>
		{/if}
	</dl>

	<section aria-labelledby="{id}-summary">
		<h4 id="{id}-summary">Redacted summary</h4>
		{#if r.public_summary}
			<p>{r.public_summary}</p>
		{:else}
			<p class="muted">No redacted summary yet.</p>
		{/if}
	</section>

	<ScoreBlock score={item.score} {id} />

	<section aria-labelledby="{id}-evidence">
		<h4 id="{id}-evidence">Evidence</h4>
		{#if item.evidence.length === 0}
			<p class="muted">No evidence is visible to reviewers for this request.</p>
		{:else}
			<ul class="evidence">
				{#each item.evidence as ev (ev.id)}
					<li>
						<strong>{evidenceLabel(ev.kind)}</strong>
						<span class="muted">
							{redactionLabel(ev.redaction_status)}{ev.captured_in_app ? ' · taken in the app' : ''}
							· {formatDay(ev.created_at)}
						</span>
					</li>
				{/each}
			</ul>
		{/if}
	</section>

	{#if item.myReviews.length > 0}
		<section aria-labelledby="{id}-mine">
			<h4 id="{id}-mine">Your earlier reviews</h4>
			<ul class="history">
				{#each item.myReviews as rv, i (i)}
					<li>
						<strong>{decidedLabel(rv.decision)}</strong>
						<span class="muted">{formatDay(rv.created_at)}</span>
						<p>{rv.reason}</p>
					</li>
				{/each}
			</ul>
		</section>
	{/if}

	{#if isReviewable(r.status)}
		<form class="decide" onsubmit={submit} novalidate aria-labelledby="{id}-decide" bind:this={formEl}>
			<h4 id="{id}-decide">Your decision</h4>
			<fieldset aria-describedby={decisionError ? `${id}-decision-error` : undefined}>
				<legend class="visually-hidden">Decision</legend>
				{#each REVIEW_DECISIONS as option (option.value)}
					<label class="option" class:chosen={decision === option.value}>
						<input
							type="radio"
							name="{id}-decision"
							value={option.value}
							bind:group={decision}
							disabled={busy}
						/>
						<span>
							<strong>{option.label}</strong>
							<span class="muted">{option.effect}</span>
						</span>
					</label>
				{/each}
				{#if decisionError}
					<p class="field-error" id="{id}-decision-error">{decisionError}</p>
				{/if}
			</fieldset>

			<div class="reason">
				<label class="label" for="{id}-reason">Reason</label>
				<span class="muted hint" id="{id}-reason-hint">
					The member reads this, without your name. Say what the evidence shows or what's missing.
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
				{busy ? 'Saving…' : submitLabel}
			</button>
		</form>
	{:else if r.status === 'refused'}
		<p class="note">Refused. Only an upheld appeal can reopen it; the panel decides appeals.</p>
	{/if}
</article>

<style>
	.card {
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius);
		box-shadow: var(--shadow);
		padding: 20px;
		display: grid;
		gap: 16px;
	}

	.head {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		gap: 12px;
	}

	.head .eyebrow {
		margin-bottom: 4px;
	}

	h3 {
		font-size: 24px;
	}

	h4 {
		font-size: 15px;
		margin: 0 0 4px;
	}

	.status {
		font-size: 13px;
		font-weight: 600;
		padding: 4px 10px;
		border-radius: 999px;
		background: var(--accent-soft);
		color: var(--accent);
		white-space: nowrap;
	}

	.status[data-status='refused'] {
		background: var(--warm-soft);
		color: var(--warm);
	}

	.facts {
		display: flex;
		flex-wrap: wrap;
		gap: 8px 24px;
		margin: 0;
	}

	.facts dt {
		font-size: 13px;
		color: var(--muted);
	}

	.facts dd {
		margin: 0;
		font-weight: 600;
	}

	.muted {
		color: var(--muted);
	}

	.small {
		font-size: 13px;
	}

	.evidence,
	.history {
		margin: 0;
		padding: 0;
		list-style: none;
		display: grid;
		gap: 8px;
	}

	.evidence li {
		display: flex;
		flex-wrap: wrap;
		gap: 4px 10px;
	}

	.history p {
		margin-top: 2px;
	}

	.decide {
		border-top: 1px solid var(--border);
		padding-top: 16px;
		display: grid;
		gap: 10px;
	}

	fieldset {
		border: 0;
		margin: 0;
		padding: 0;
		display: grid;
		gap: 8px;
	}

	.option {
		min-height: 44px;
		display: flex;
		gap: 12px;
		align-items: flex-start;
		padding: 10px 12px;
		border: 1px solid var(--border);
		border-radius: 10px;
		cursor: pointer;
	}

	.option.chosen {
		border-color: var(--accent);
		background: var(--accent-soft);
	}

	.option input {
		margin-top: 5px;
		accent-color: var(--accent);
	}

	.option > span {
		display: grid;
	}

	.option .muted {
		font-size: 14px;
	}

	.reason {
		display: grid;
		gap: 2px;
		margin-top: 6px;
	}

	.label {
		font-weight: 600;
	}

	.hint {
		font-size: 14px;
	}

	textarea {
		width: 100%;
		font: inherit;
		color: var(--text);
		background: var(--bg);
		border: 1px solid var(--border);
		border-radius: 10px;
		padding: 10px 12px;
		resize: vertical;
	}

	textarea[aria-invalid='true'] {
		border-color: var(--warm);
	}

	.under {
		display: flex;
		justify-content: space-between;
		gap: 12px;
	}

	.field-error {
		color: var(--warm);
		font-size: 14px;
		font-weight: 600;
	}

	.notice {
		background: var(--warm-soft);
		color: var(--text);
		border-left: 4px solid var(--warm);
		padding: 10px 14px;
		border-radius: 8px;
	}

	.note {
		background: var(--surface-2);
		padding: 10px 14px;
		border-radius: 8px;
		color: var(--muted);
	}

	.btn {
		justify-self: start;
	}

	.btn {
		min-height: 44px;
		justify-content: center;
	}

	.btn[aria-disabled='true'] {
		opacity: 0.6;
		cursor: wait;
	}

	@media (max-width: 480px) {
		.card {
			padding: 16px;
		}

		.btn {
			justify-self: stretch;
			justify-content: center;
		}
	}
</style>
