<script lang="ts">
	import { tick } from 'svelte';
	import { acceptInvite, loadSupportView, type SupportView } from '#lib/invites/data.ts';
	import { explainInviteError } from '#lib/invites/errors.ts';
	import SupportPanel from '#lib/invites/SupportPanel.svelte';

	let { data } = $props();

	type State =
		| { step: 'ready' }
		| { step: 'accepting' }
		| { step: 'refused'; message: string }
		| { step: 'loading'; requestId: string }
		| { step: 'shown'; view: SupportView }
		| { step: 'load-error'; requestId: string; message: string };

	let phase = $state<State>({ step: 'ready' });
	let confirmation = $state('');
	let confirmationEl = $state<HTMLParagraphElement>();
	let resultEl = $state<HTMLElement>();

	async function accept() {
		// aria-disabled keeps the button focusable while accepting, so guard here.
		if (phase.step === 'accepting') return;
		phase = { step: 'accepting' };
		try {
			const requestId = await acceptInvite(data.token);
			confirmation = 'You’ve accepted the invite. Here’s the request.';
			await show(requestId);
		} catch (err) {
			phase = { step: 'refused', message: explainInviteError(err as { message?: string; code?: string }) };
			await tick();
			resultEl?.focus();
		}
	}

	async function show(requestId: string) {
		phase = { step: 'loading', requestId };
		try {
			const view = await loadSupportView(requestId, data.viewerId);
			phase = view
				? { step: 'shown', view }
				: { step: 'load-error', requestId, message: 'The request is no longer available to you.' };
		} catch (err) {
			phase = { step: 'load-error', requestId, message: explainInviteError(err as { message?: string; code?: string }) };
		}
		await tick();
		(confirmationEl ?? resultEl)?.focus();
	}

	async function pledged(message: string) {
		confirmation = message;
		if (phase.step === 'shown') await show(phase.view.request.id);
	}
</script>

<svelte:head>
	<title>Your invite · Kinfold</title>
	<meta name="referrer" content="no-referrer" />
</svelte:head>

<header class="intro">
	<p class="eyebrow">Family &amp; friends</p>
	<h1>You've been invited to help</h1>
	<p class="lead">
		Someone you know asked for help with a repair or a home cost, and sent you this private link. If
		you accept, you'll see their request and can choose to give, lend at 0%, or do nothing at all.
	</p>
</header>

<!-- Mounted empty; only its text changes, so loading is announced. -->
<p class="visually-hidden" role="status">
	{phase.step === 'accepting' ? 'Accepting the invite…' : phase.step === 'loading' ? 'Loading the request…' : ''}
</p>

<div role="status">
	{#if confirmation}
		<p class="confirmation" tabindex="-1" bind:this={confirmationEl}>{confirmation}</p>
	{/if}
</div>

{#if !data.wellFormed}
	<div class="error block" role="alert">
		<p>
			This link looks incomplete. Invite links end in a long code of letters and numbers; it may have
			been cut off when it was copied. Open the full link from the message you were sent, or ask
			for it again.
		</p>
	</div>
{:else if !data.hasMember}
	<div class="error block" role="alert">
		<p><strong>Your member profile isn’t set up yet.</strong></p>
		<p>
			You’re signed in, but this account doesn’t have a Kinfold member profile yet, so you can’t
			accept this invite. A profile can’t be created from this page yet.
		</p>
		<p>
			Membership is by invitation for now. Ask the member who sent you this link to contact the
			Kinfold team, who will finish setting up your profile. Then sign in again and open this link:
			it still works if nobody else has used it and it’s less than 30 days old.
		</p>
	</div>
{:else if phase.step === 'ready' || phase.step === 'accepting'}
	<section class="block card" aria-labelledby="what-heading" aria-busy={phase.step === 'accepting'}>
		<h2 id="what-heading">What accepting means</h2>
		<ul class="terms">
			<li>You'll see the request: what happened, how much is needed and who gets paid.</li>
			<li>
				You can <strong>give</strong> (a gift, never paid back) or <strong>lend at 0%</strong> (no
				interest, no late fees, a monthly schedule you both sign). Or nothing: accepting doesn't
				commit you to anything.
			</li>
			<li>
				Money only ever goes to the shop, contractor or lender doing the work, never to the member
				and never to Kinfold. Nothing is collected until the whole amount is pledged.
			</li>
			<li>
				If you lend, the schedule and what happens if repayments stop (forgive it, repay it when the home is sold if the loan is secured, or
				talk it through) are agreed and signed by both of you. There is never interest or a late fee.
			</li>
			<li>What you give is private. The member sees your pledge; no one else does, and no one is ranked.</li>
			<li>The link works once, for you. Accepting uses it up.</li>
		</ul>
		<div>
			<button
				type="button"
				class="btn btn-primary"
				onclick={accept}
				aria-disabled={phase.step === 'accepting'}
				aria-busy={phase.step === 'accepting'}
			>
				{phase.step === 'accepting' ? 'Accepting…' : 'Accept the invite'}
			</button>
		</div>
		{#if !data.verified}
			<p class="muted">
				You can accept and give now. Lending needs a verified identity first.
			</p>
		{/if}
	</section>
{:else if phase.step === 'refused'}
	<div class="error block" role="alert" tabindex="-1" bind:this={resultEl}>
		<p>{phase.message}</p>
		<p><a href="/app/invite">See the requests you've accepted</a></p>
	</div>
{:else if phase.step === 'loading'}
	<p class="muted block" aria-hidden="true">Loading the request…</p>
{:else if phase.step === 'load-error'}
	{@const id = phase.requestId}
	<div class="error block" role="alert" tabindex="-1" bind:this={resultEl}>
		<p>Your invite was accepted, but the request didn't load. {phase.message}</p>
		<button type="button" class="btn btn-ghost" onclick={() => show(id)}>Try again</button>
		<p>It's also listed under <a href="/app/invite">Invites</a>.</p>
	</div>
{:else}
	<div class="block">
		<SupportPanel view={phase.view} verified={data.verified} onpledged={pledged} />
		<p class="muted after">
			You'll find this request again under <a href="/app/invite">Invites</a>.
		</p>
	</div>
{/if}

<style>
	.intro {
		display: grid;
		gap: 10px;
		max-width: 720px;
	}

	.intro .eyebrow {
		margin-bottom: 0;
	}

	h1 {
		font-size: clamp(28px, 4vw, 36px);
	}

	h2 {
		font-size: 20px;
	}

	.lead,
	.muted {
		color: var(--muted);
	}

	.block {
		margin-top: 32px;
		max-width: 760px;
	}

	.card {
		display: grid;
		gap: 14px;
		padding: 18px;
		border: 1px solid var(--border);
		border-radius: 12px;
		background: var(--surface);
	}

	.terms {
		margin: 0;
		padding-left: 18px;
		display: grid;
		gap: 6px;
	}

	.confirmation {
		margin-top: 24px;
		background: var(--accent-soft);
		color: var(--text);
		border-left: 4px solid var(--accent);
		padding: 12px 16px;
		border-radius: 8px;
		max-width: 720px;
	}

	.error {
		background: var(--warm-soft);
		border-left: 4px solid var(--warm);
		border-radius: 8px;
		padding: 12px 16px;
		display: grid;
		gap: 10px;
		justify-items: start;
	}

	.after {
		margin-top: 12px;
	}

	.btn {
		min-height: 44px;
		justify-content: center;
	}

	.btn[aria-disabled='true'] {
		opacity: 0.6;
		cursor: progress;
	}
</style>
