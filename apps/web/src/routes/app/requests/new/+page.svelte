<script lang="ts">
	import { tick } from 'svelte';
	import { goto, invalidate } from '$app/navigation';
	import type { DraftInput } from '#lib/requests/form.ts';
	import RequestForm from '../RequestForm.svelte';

	let { data } = $props();

	const blank: DraftInput = {
		kind: '',
		funding: 'people',
		title: '',
		description: '',
		amount: '',
		incidentOn: '',
		payeeId: '',
		assetId: ''
	};

	const active = $derived(data.viewer.member?.status === 'active');
	let retrying = $state(false);

	let heading = $state<HTMLElement>();

	async function retry() {
		if (retrying) return;
		retrying = true;
		try {
			await invalidate('app:request-form');
		} finally {
			retrying = false;
			// The retry button goes with the error block; park focus on the
			// heading (as Home does) instead of letting it fall to <body>.
			await tick();
			heading?.focus();
		}
	}
</script>

<svelte:head>
	<title>Ask for help · Kinfold</title>
</svelte:head>

<header class="page-head">
	<p class="eyebrow">New request</p>
	<h1 tabindex="-1" bind:this={heading}>Ask for help</h1>
	<p class="lead">
		Start a draft. Only you, and family or friends you invite to support it, can see it until you
		submit. Then add your evidence, check what will be blurred out, and send it.
	</p>
	<ol class="path" aria-label="How a request works">
		<li><strong>Draft</strong> what you need and who should be paid.</li>
		<li><strong>Add evidence</strong>: photos, estimates, bills.</li>
		<li><strong>Submit</strong>. It gets a evidence score: how well the evidence backs the request.</li>
		<li><strong>Get help</strong> from your people or the pool, paid straight to the payee.</li>
	</ol>
</header>

{#if data.viewer.member && !active}
	<p class="note" role="note">
		You can start a draft now. You’ll need to finish verifying your identity before you can submit it.
	</p>
{/if}

{#if !data.viewer.member}
	<!-- Signed in, but no members row. Same wording as the home page, and no
	     "back home" button: home can't fix it either, so a link would loop. -->
	<section class="error" aria-labelledby="setup-h">
		<h2 id="setup-h">Your member profile isn’t set up yet</h2>
		<p>
			You’re signed in, but this account doesn’t have a Kinfold member profile yet, so a request
			can’t be started. A profile can’t be created from this page yet.
		</p>
		<p>
			Membership is by invitation for now. Ask the member who invited you to contact the Kinfold
			team, who will finish setting up your profile. Then sign in again.
		</p>
	</section>
{:else}
	{#await data.ctx}
		<div class="loading" role="status">
			<span class="visually-hidden">Loading the request form…</span>
			<div class="skeleton" aria-hidden="true"></div>
		</div>
	{:then ctx}
		<RequestForm
			{ctx}
			uid={data.viewer.session.user.id}
			region={data.viewer.member.region}
			initial={blank}
			onsaved={(id) => goto(`/app/requests/${id}?saved=1`)}
			oncancel={() => goto('/app')}
		/>
	{:catch err}
		<div class="error" role="alert">
			<h2>We couldn’t load the form</h2>
			<p>{err instanceof Error ? err.message : 'Check your connection and try again.'} Nothing was saved.</p>
			<button type="button" class="btn btn-primary" onclick={retry} aria-disabled={retrying ? 'true' : undefined}>
				{retrying ? 'Trying again…' : 'Try again'}
			</button>
		</div>
	{/await}
{/if}

<style>
	.page-head {
		margin-bottom: 28px;
	}

	h1 {
		font-size: clamp(28px, 5vw, 38px);
	}

	.lead {
		color: var(--muted);
		margin-top: 8px;
		max-width: 620px;
	}

	.path {
		margin: 16px 0 0;
		padding-left: 22px;
		display: grid;
		gap: 4px;
		font-size: 15px;
		max-width: 620px;
	}

	.note {
		max-width: 680px;
		margin: 0 0 24px;
		background: var(--warm-soft);
		border-left: 4px solid var(--warm);
		border-radius: 10px;
		padding: 12px 14px;
	}

	.error {
		display: grid;
		gap: 10px;
		justify-items: start;
		max-width: 680px;
		background: var(--surface);
		border: 1px solid var(--warm);
		border-radius: var(--radius);
		padding: 18px 20px;
	}

	.error h2 {
		font-size: 20px;
	}

	.skeleton {
		height: 420px;
		max-width: 680px;
	}

</style>
