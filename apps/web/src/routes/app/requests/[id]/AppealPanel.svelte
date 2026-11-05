<script lang="ts">
	import { supabase } from '#lib/supabase/client.ts';
	import { formatDay } from '#lib/dashboard/format.ts';
	import { fileAppeal, type AppealRow } from '#lib/requests/data.ts';
	import { APPEAL_MAX, appealReasonProblem, charCount } from '#lib/requests/form.ts';
	import type { AppealState } from '#lib/requests/next.ts';
	import Badge from '../Badge.svelte';

	let {
		requestId,
		status,
		appeals,
		onfiled
	}: {
		requestId: string;
		status: AppealState;
		appeals: AppealRow[];
		onfiled: (message: string) => Promise<void>;
	} = $props();

	const base = $props.id();
	let reason = $state('');
	let problem = $state<string | null>(null);
	let sending = $state(false);
	let textarea = $state<HTMLTextAreaElement>();

	const appealText = {
		open: { label: 'With the panel', tone: 'progress' as const },
		upheld: { label: 'Upheld: sent back to review', tone: 'done' as const },
		denied: { label: 'Not upheld', tone: 'closed' as const }
	};

	async function send(e: SubmitEvent) {
		e.preventDefault();
		if (sending) return;
		problem = appealReasonProblem(reason);
		if (problem) {
			textarea?.focus();
			return;
		}
		sending = true;
		try {
			await fileAppeal(supabase(), requestId, reason.trim());
			reason = '';
			await onfiled('Your appeal was sent to the member panel. Their decision will show on this page.');
		} catch (err) {
			problem = err instanceof Error ? err.message : 'The appeal wasn’t sent. Try again.';
		} finally {
			sending = false;
		}
	}
</script>

<section class="block" aria-labelledby="{base}-h">
	<h2 id="{base}-h">Appeal</h2>

	{#if appeals.length > 0}
		<!-- list-style:none removes list semantics in Safari; the role puts them back. -->
		<!-- svelte-ignore a11y_no_redundant_roles -->
		<ul class="list" role="list">
			{#each appeals as a (a.id)}
				<li class="item">
					<div class="item-head">
						<p class="meta">You appealed on {formatDay(a.created_at)}</p>
						<Badge tone={appealText[a.status].tone} label={appealText[a.status].label} />
					</div>
					<blockquote>{a.reason}</blockquote>
					{#if a.decided_at}
						<p class="meta">Decided {formatDay(a.decided_at)}.</p>
					{/if}
					{#if a.decision_note}
						<!-- The panel's written reason: a refusal is explained in plain
						     language (design.md), and the panelist's name is never shown. -->
						<p class="meta">The panel’s reason:</p>
						<blockquote class="decision">{a.decision_note}</blockquote>
					{/if}
				</li>
			{/each}
		</ul>
	{/if}

	{#if status === 'can_appeal'}
		<form class="form" onsubmit={send} novalidate>
			<p>
				You can appeal this decision once. A member panel reads your appeal and decides. The reviewer
				who declined it isn’t on the panel for it. If they uphold your appeal, the request goes back to
				a reviewer.
			</p>
			<label for="{base}-reason">Why should the panel look again?</label>
			<p class="hint" id="{base}-hint">
				Explain in writing what the reviewer may have missed. Files can’t be added to a refused request,
				so if you have a document you couldn’t upload, say what it shows. If the panel upholds your
				appeal, the reviewer it goes back to can ask you for more evidence. 10 to {APPEAL_MAX.toLocaleString('en-US')} characters.
			</p>
			<textarea
				id="{base}-reason"
				rows="5"
				bind:value={reason}
				bind:this={textarea}
				aria-describedby="{base}-hint {base}-count{problem ? ` ${base}-problem` : ''}"
				aria-invalid={problem ? 'true' : undefined}
			></textarea>
			<p class="hint" id="{base}-count">{charCount(reason.trim()).toLocaleString('en-US')} of {APPEAL_MAX.toLocaleString('en-US')} characters</p>
			{#if problem}<p class="problem" id="{base}-problem" role="alert">{problem}</p>{/if}
			<div>
				<button type="submit" class="btn btn-primary" aria-disabled={sending ? 'true' : undefined}>
					{sending ? 'Sending your appeal…' : 'Send appeal'}
				</button>
			</div>
			<p class="hint" role="status">{#if sending}Sending. Keep this page open.{/if}</p>
		</form>
	{:else if status === 'appeal_used' && appeals.length > 0}
		<p class="hint">Each refusal can be appealed once, and this one has been decided.</p>
	{/if}
</section>

<style>
	.block {
		margin-top: 40px;
	}

	h2 {
		font-size: 22px;
	}

	.list {
		list-style: none;
		margin: 16px 0 0;
		padding: 0;
		display: grid;
		gap: 12px;
	}

	.item,
	.form {
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius);
		padding: 16px 18px;
		display: grid;
		gap: 8px;
		max-width: 680px;
	}

	.form {
		margin-top: 16px;
	}

	.item-head {
		display: flex;
		flex-wrap: wrap;
		justify-content: space-between;
		gap: 8px 16px;
	}

	blockquote {
		margin: 0;
		padding-left: 12px;
		border-left: 3px solid var(--border);
		overflow-wrap: anywhere;
		white-space: pre-line;
	}

	.meta,
	.hint {
		color: var(--muted);
		font-size: 14px;
		margin: 0;
	}

	label {
		font-weight: 700;
	}

	textarea {
		font: inherit;
		color: var(--text);
		background: var(--surface);
		border: 1px solid var(--field-border);
		border-radius: 10px;
		padding: 10px 12px;
		width: 100%;
		resize: vertical;
	}

	[aria-invalid='true'] {
		border-color: var(--warm);
		border-width: 2px;
	}

	.problem {
		margin: 0;
		font-size: 14px;
		font-weight: 600;
		padding-left: 10px;
		border-left: 4px solid var(--warm);
	}

	.btn {
		min-height: 44px;
	}

	textarea {
		min-height: 44px;
	}

	.btn[aria-disabled='true'] {
		opacity: 0.6;
		cursor: progress;
	}
</style>
