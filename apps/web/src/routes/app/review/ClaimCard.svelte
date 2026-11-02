<script lang="ts">
	import { tick } from 'svelte';
	import { supabase } from '#lib/supabase/client.ts';
	import { explainDbError } from '#lib/review/errors.ts';
	import { formatCents } from '#lib/review/labels.ts';
	import { decideClaim } from '#lib/review/queries.ts';
	import type { StandingClaim } from '#lib/review/queries.ts';
	import { cleanReason, reasonCounter, reasonProblem } from '#lib/review/reason.ts';

	let { claim, ondecided }: { claim: StandingClaim; ondecided: (message: string) => void } = $props();

	const id = $derived(`claim-${claim.id}`);

	let reason = $state('');
	let tried = $state(false);
	let busy = $state(false);
	let error = $state('');
	let formEl = $state<HTMLFormElement | null>(null);
	let reasonEl = $state<HTMLTextAreaElement | null>(null);

	const reasonError = $derived(tried ? reasonProblem(reason) : null);

	async function submit(e: SubmitEvent) {
		e.preventDefault();
		if (busy) return;
		tried = true;
		error = '';
		if (reasonProblem(reason)) {
			await tick();
			reasonEl?.focus();
			return;
		}
		busy = true;
		try {
			// One decision, two records: the refusal and the denial land together.
			await decideClaim(supabase(), claim.id, cleanReason(reason));
			ondecided('Claim denied. The refusal and the denial were recorded as one decision; a denial pays nothing.');
		} catch (err) {
			error = explainDbError(err as { message?: string; code?: string });
			await tick();
			return;
		} finally {
			busy = false;
		}
		reason = '';
		tried = false;
	}
</script>

<article class="card" aria-labelledby="{id}-title">
	<header>
		<h3 id="{id}-title">Standing claim on a request you may review</h3>
		<p class="eyebrow">
			{formatCents(claim.paid_cents)} to the shop · {formatCents(claim.gross_cents)} gross,
			member's share {formatCents(claim.member_share_cents)}
		</p>
	</header>
	<p class="note">
		A standing claim waits for the insurer's payment or a person's denial. Denying closes
		the claim and records the refusal of its request in the same step — the money stays nothing.
	</p>
	<form class="decide" onsubmit={submit} novalidate bind:this={formEl}>
		<label for="{id}-reason">Why the claim should be denied</label>
		<p class="hint" id="{id}-hint" class:hidden={reasonError !== null}>
			Write what the evidence shows. The member reads it. {reasonCounter(reason)}
		</p>
		<textarea
			id="{id}-reason"
			rows="5"
			bind:value={reason}
			bind:this={reasonEl}
			aria-describedby="{id}-hint{reasonError ? ` ${id}-reason-error` : ''}"
			aria-invalid={reasonError ? 'true' : undefined}
		></textarea>
		{#if reasonError}<p class="problem" id="{id}-reason-error" role="alert">{reasonError}</p>{/if}
		<div>
			<button type="submit" class="btn btn-primary" aria-disabled={busy ? 'true' : undefined}>
				{busy ? 'Recording…' : 'Deny this claim'}
			</button>
		</div>
		<p class="hint" role="status">{#if busy}Recording the refusal and the denial. Keep this page open.{/if}</p>
	</form>
</article>
