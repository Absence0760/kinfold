<script lang="ts">
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

	async function retry() {
		retrying = true;
		try {
			await invalidate('app:request-form');
		} finally {
			retrying = false;
		}
	}
</script>

<svelte:head>
	<title>Ask for help · Kinfold</title>
</svelte:head>

<header class="page-head">
	<p class="eyebrow">New request</p>
	<h1>Ask for help</h1>
	<p class="lead">
		Start a draft. Only you can see it until you submit. Then add your evidence, check what will be
		blurred out, and send it.
	</p>
	<ol class="path" aria-label="How a request works">
		<li><strong>Draft</strong> what you need and who should be paid.</li>
		<li><strong>Add evidence</strong>: photos, estimates, bills.</li>
		<li><strong>Submit</strong>. It gets a legitimacy score: how well the evidence backs the request.</li>
		<li><strong>Get help</strong> from your people or the pool, paid straight to the payee.</li>
	</ol>
</header>

{#if data.viewer.member && !active}
	<p class="note" role="note">
		You can start a draft now. You’ll need to finish verifying your identity before you can submit it.
	</p>
{/if}

{#if !data.viewer.member}
	<div class="error" role="alert">
		<h2>Finish joining first</h2>
		<p>Your member profile isn’t set up yet, so a request can’t be started.</p>
		<a class="btn btn-ghost" href="/app">Back to your home</a>
	</div>
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
			<button type="button" class="btn btn-primary" onclick={retry} disabled={retrying}>
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
		border-radius: var(--radius);
		background: var(--surface-2);
		animation: pulse 1.4s ease-in-out infinite;
	}

	@keyframes pulse {
		50% {
			opacity: 0.55;
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.skeleton {
			animation: none;
		}
	}

	.visually-hidden {
		position: absolute;
		width: 1px;
		height: 1px;
		margin: -1px;
		overflow: hidden;
		clip: rect(0 0 0 0);
		white-space: nowrap;
	}
</style>
