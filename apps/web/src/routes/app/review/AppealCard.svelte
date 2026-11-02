<script lang="ts">
	import { tick } from 'svelte';
	import { supabase } from '#lib/supabase/client.ts';
	import { explainDbError } from '#lib/review/errors.ts';
	import { decidedLabel, formatCents, formatDay, kindLabel } from '#lib/review/labels.ts';
	import { decideAppeal } from '#lib/review/queries.ts';
	import { appealOutcome, type AppealItem } from '#lib/review/queue.ts';
	import { cleanReason, reasonCounter, reasonProblem } from '#lib/review/reason.ts';
	import ScoreBlock from './ScoreBlock.svelte';

	let { item, ondecided }: { item: AppealItem; ondecided: (message: string) => void } = $props();

	const a = $derived(item.appeal);
	const id = $derived(`appeal-${item.appeal.id}`);

	let choice = $state<'uphold' | 'deny' | ''>('');
	let reason = $state('');
	let tried = $state(false);
	let busy = $state(false);
	let error = $state('');
	let formEl = $state<HTMLFormElement | null>(null);
	let reasonEl = $state<HTMLTextAreaElement | null>(null);

	const choiceError = $derived(tried && choice === '' ? 'Choose uphold or deny.' : null);
	const reasonError = $derived(tried ? reasonProblem(reason) : null);

	async function submit(e: SubmitEvent) {
		e.preventDefault();
		if (busy) return;
		tried = true;
		error = '';
		if (choice === '' || reasonProblem(reason)) {
			await tick();
			if (choice === '') formEl?.querySelector<HTMLInputElement>('input[type="radio"]')?.focus();
			else reasonEl?.focus();
			return;
		}
		busy = true;
		try {
			// A decision is written down in, like every other decision.
			const uphold = choice === 'uphold';
			await decideAppeal(supabase(), a.id, uphold, cleanReason(reason));
			choice = '';
			reason = '';
			tried = false;
			ondecided(appealOutcome(uphold));
		} catch (err) {
			error = explainDbError(err as { message?: string; code?: string });
		} finally {
			busy = false;
		}
	}
</script>

<article class="card" aria-labelledby="{id}-title">
	<header>
		<p class="eyebrow">
			{item.request ? `${kindLabel(item.request.kind)} · ${formatCents(item.request.amount_cents)}` : 'Appeal'}
		</p>
		<h3 id="{id}-title">Appeal filed {formatDay(a.created_at)}</h3>
	</header>

	<section aria-labelledby="{id}-refusal">
		<h4 id="{id}-refusal">The refusal</h4>
		{#if item.refusal}
			<blockquote>{item.refusal.reason}</blockquote>
			<p class="muted small">Refused {formatDay(item.refusal.created_at)}</p>
		{:else}
			<p class="muted">The refusal isn't visible to you.</p>
		{/if}
	</section>

	<section aria-labelledby="{id}-why">
		<h4 id="{id}-why">The member's appeal</h4>
		<blockquote>{a.reason}</blockquote>
	</section>

	{#if item.request}
		<section aria-labelledby="{id}-summary">
			<h4 id="{id}-summary">Redacted summary</h4>
			<p>{item.request.public_summary ?? 'No redacted summary yet.'}</p>
		</section>
		<ScoreBlock score={item.score} {id} />
	{:else}
		<p class="note">The request's details and legitimacy score aren't shared with the panel.</p>
	{/if}

	{#if item.history.length > 1}
		<details>
			<summary>All reviews on this request ({item.history.length})</summary>
<!-- list-style:none removes list semantics in Safari; the role puts them back. -->
			<!-- svelte-ignore a11y_no_redundant_roles -->
			<ul class="history" role="list">
				{#each item.history as rv, i (i)}
					<li>
						<strong>{decidedLabel(rv.decision)}</strong>
						<span class="muted">{formatDay(rv.created_at)}</span>
						<p>{rv.reason}</p>
					</li>
				{/each}
			</ul>
		</details>
	{/if}

	{#if item.viewerReviewed}
		<p class="note">You reviewed this request, so another panel member decides the appeal.</p>
	{:else}
		<form class="decide" onsubmit={submit} novalidate bind:this={formEl}>
			<fieldset aria-describedby={choiceError ? `${id}-choice-error` : undefined}>
				<legend>Your decision</legend>
				<label class="option" class:chosen={choice === 'uphold'}>
					<input type="radio" name="{id}-choice" value="uphold" bind:group={choice} disabled={busy} />
					<span>
						<strong>Uphold the appeal</strong>
						<span class="muted">The request goes back to review for a fresh decision.</span>
					</span>
				</label>
				<label class="option" class:chosen={choice === 'deny'}>
					<input type="radio" name="{id}-choice" value="deny" bind:group={choice} disabled={busy} />
					<span>
						<strong>Deny the appeal</strong>
						<span class="muted">The refusal stands.</span>
					</span>
				</label>
				{#if choiceError}
					<p class="field-error" id="{id}-choice-error">{choiceError}</p>
				{/if}
			</fieldset>

			<div class="reason">
				<label class="label" for="{id}-reason">Reason</label>
				<span class="muted hint" id="{id}-reason-hint">
					Another panel member reads this, without your name. Say what you weighed.
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
				{busy ? 'Saving…' : 'Record decision'}<span class="visually-hidden">
					on the appeal filed {formatDay(a.created_at)}{item.request
						? `, ${kindLabel(item.request.kind)}, ${formatCents(item.request.amount_cents)}`
						: ''}</span
				>
			</button>
		</form>
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

	header .eyebrow {
		margin-bottom: 4px;
	}

	h3 {
		font-size: 20px;
	}

	h4 {
		font-size: 15px;
		margin: 0 0 4px;
	}

	blockquote {
		margin: 0;
		padding: 8px 14px;
		border-left: 3px solid var(--border);
		background: var(--surface-2);
		border-radius: 0 8px 8px 0;
		white-space: pre-line;
	}

	.muted {
		color: var(--muted);
	}

	.small {
		font-size: 13px;
		margin-top: 4px;
	}

	details summary {
		min-height: 44px;
		display: flex;
		align-items: center;
		cursor: pointer;
		font-weight: 600;
	}

	.history {
		margin: 8px 0 0;
		padding: 0;
		list-style: none;
		display: grid;
		gap: 8px;
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

	legend {
		font-weight: 600;
		margin-bottom: 8px;
		padding: 0;
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

	.field-error {
		color: var(--warm);
		font-size: 14px;
		font-weight: 600;
	}

	.reason {
		display : grid;
		gap : 2px;
		margin-top : 6px;
	}

	.label {
		font-weight : 600;
	}

	.hint {
		font-size : 14px;
	}

	textarea {
		width : 100%;
		font : inherit;
		color : var(--text);
		background : var(--bg);
		border : 1px solid var(--field-border);
		border-radius : 10px;
		padding : 10px 12px;
		resize : vertical;
	}

	textarea[aria-invalid='true'] {
		border-color : var(--warm);
	}

	.under {
		display : flex;
		justify-content : space-between;
		gap : 12px;
	}
	.notice {
		background: var(--warm-soft);
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
