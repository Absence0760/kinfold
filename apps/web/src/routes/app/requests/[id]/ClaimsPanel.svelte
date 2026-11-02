<script lang="ts">
	import { formatCents, formatDay } from '#lib/dashboard/format.ts';
	import { appealClaim, claimStatusText, type ClaimRow } from '#lib/requests/claims.ts';
	import { supabase } from '#lib/supabase/client.ts';
	import Badge from '../Badge.svelte';
	import type { Tone } from '#lib/dashboard/labels.ts';

	let { claims, onrefresh }: {
		claims: ClaimRow[];
		onrefresh: (message: string) => Promise<void>;
	} = $props();

	const base = $props.id();
	let reason = $state('');
	let problem = $state<string | null>(null);
	let sending = $state(false);
	let textarea = $state<HTMLTextAreaElement>();

	// Only a person can deny a claim, and only the requester can appeal it —
	// so at most one denied claim can be appealed at a time.
	// svelte-ignore state_referenced_locally
	const denied = $derived(claims.find((c) => c.status === 'denied'));

	const toneOf = (status: string): Tone => (({ recorded: 'progress', paid: 'done', denied: 'closed' })[status] ?? 'progress') as Tone;

	/** Send the appeal of a denied claim; the schema decides and explains why not. */
	async function send(e: SubmitEvent) {
		e.preventDefault();
		if (sending || !denied) return;
		sending = true;
		try {
			const out = await appealClaim(supabase(), denied.id, reason);
			if (!out.appealed) {
				problem = out.message ?? 'The appeal did not go through.';
				textarea?.focus();
				return;
			}
			reason = '';
			await onrefresh('Your appeal was sent. The claim stays denied until a person decides on the appeal.');
		} catch (err) {
			problem = err instanceof Error ? err.message : 'The appeal wasn’t sent. Try again.';
		} finally {
			sending = false;
		}
	}
</script>

<section class="block" aria-labelledby="{base}-h">
	<h2 id="{base}-h">Insured claims</h2>
	<p class="note">
		Your dues buy premiums on the group car cover. A covered claim is paid in full to the shop —
		less the share agreed with you — inside the state's deadlines. The score decides scrutiny, never
		how much is paid.
	</p>
	<!-- list-style:none removes list semantics in Safari; the role puts them back. -->
	<!-- svelte-ignore a11y_no_redundant_roles -->
	<ul class="list" role="list">
		{#each claims as c (c.id)}
			<li class="item">
				<div class="item-head">
					<p class="meta">
						{formatCents(c.paid_cents)} to the shop · {formatCents(c.gross_cents)} gross,
						your share {formatCents(c.member_share_cents)} · recorded {formatDay(c.recorded_at)}
					</p>
				<Badge tone={toneOf(c.status)} label={claimStatusText(c.status)} />
				</div>
				{#if c.status === 'denied' && c.reason}
					<blockquote>{c.reason}</blockquote>
					<p class="hint">The denial is a person's words; a denial pays nothing.</p>
				{:else if c.status === 'recorded'}
					<p class="hint">The insurer confirms the payment when the money moves.</p>
				{:else}
					<p class="hint">Paid — the shop got this money; Kinfold never holds it.</p>
				{/if}
			</li>
		{/each}
	</ul>

	{#if denied}
		<form class="form" onsubmit={send} novalidate>
			<p>
				You can appeal a denial: write what the person who denied it may have missed. A denial pays
				nothing — the claim stays recorded until the appeal is decided.
			</p>
			<label for="{base}-reason">Why the claim should stand</label>
			<p class="hint" id="{base}-hint">At least 10 characters. Only you, the requester, can appeal.</p>
			<textarea
				id="{base}-reason"
				rows="5"
				bind:value={reason}
				bind:this={textarea}
				aria-describedby="{base}-hint{problem ? ` ${base}-problem` : ''}"
				aria-invalid={problem ? 'true' : undefined}
			></textarea>
			{#if problem}<p class="problem" id="{base}-problem" role="alert">{problem}</p>{/if}
			<div>
				<button type="submit" class="btn btn-primary" aria-disabled={sending ? 'true' : undefined}>
					{sending ? 'Sending…' : 'Appeal this claim'}
				</button>
			</div>
			<p class="hint" role="status">{#if sending}Sending. Keep this page open.{/if}</p>
		</form>
	{:else if denied}
		<p class="hint">This denial's appeal was already filed or decided.</p>
	{/if}
</section>

<style>
	.block {
		justify-self: start;
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

	.item-head {
		display: flex;
		flex-wrap: wrap;
		justify-content: space-between;
		gap: 8px 16px;
	}

	.meta,
	.hint {
		color: var(--muted);
		font-size: 14px;
		margin: 0;
	}

	.btn {
		min-height: 44px;
	}
</style>
