<script lang="ts">
	import { onMount, tick } from 'svelte';
	import { formatCents } from '#lib/dashboard/format.ts';
	import { requestKindLabel, requestStatusText } from '#lib/dashboard/labels.ts';
	import {
		loadOwnPeopleRequests,
		loadSupportView,
		loadSupporting,
		type OwnedRequest,
		type SupportView
	} from '#lib/invites/data.ts';
	import { explainInviteError } from '#lib/invites/errors.ts';
	import InvitePanel from '#lib/invites/InvitePanel.svelte';
	import SupportPanel from '#lib/invites/SupportPanel.svelte';

	let { data } = $props();

	type Loaded<T> = { state: 'loading' } | { state: 'ready'; items: T[] } | { state: 'error'; message: string };

	let own = $state<Loaded<OwnedRequest>>({ state: 'loading' });
	let supporting = $state<Loaded<SupportView>>({ state: 'loading' });
	let confirmation = $state('');
	let confirmationEl = $state<HTMLParagraphElement>();

	const why = (err: unknown) => explainInviteError(err as { message?: string; code?: string });

	async function refreshOwn() {
		own = { state: 'loading' };
		try {
			own = { state: 'ready', items: await loadOwnPeopleRequests(data.viewerId) };
		} catch (err) {
			own = { state: 'error', message: why(err) };
		}
	}

	async function refreshSupporting() {
		try {
			const rows = await loadSupporting(data.viewerId);
			const views = await Promise.all(rows.map((r) => loadSupportView(r.id, data.viewerId)));
			supporting = { state: 'ready', items: views.filter((v): v is SupportView => v != null) };
		} catch (err) {
			supporting = { state: 'error', message: why(err) };
		}
	}

	onMount(() => {
		refreshOwn();
		refreshSupporting();
	});

	async function pledged(message: string) {
		confirmation = message;
		await refreshSupporting();
		await tick();
		confirmationEl?.focus();
	}
</script>

<svelte:head>
	<title>Invites · Kinfold</title>
</svelte:head>

<header class="intro">
	<p class="eyebrow">Family &amp; friends</p>
	<h1>Invites</h1>
	<p class="lead">
		Ask the people you know for help with your own requests, and see the requests others have
		invited you to. Help is a gift or a 0% loan, always paid straight to the shop, contractor or
		lender.
	</p>
	<nav class="jump" aria-label="Sections">
		<a href="#own-heading">Your requests</a>
		<a href="#supporting-heading">Invited to</a>
	</nav>
</header>

<div role="status">
	{#if confirmation}
		<p class="confirmation" tabindex="-1" bind:this={confirmationEl}>{confirmation}</p>
	{/if}
</div>

<section class="block" aria-labelledby="own-heading">
	<h2 id="own-heading">Your requests</h2>
	{#if own.state === 'loading'}
		<p class="muted" role="status">Loading your requests…</p>
	{:else if own.state === 'error'}
		<div class="error" role="alert">
			<p>Couldn't load your requests. {own.message}</p>
			<button class="btn btn-ghost" type="button" onclick={refreshOwn}>Try again</button>
		</div>
	{:else if own.items.length === 0}
		<p class="empty">
			You have no requests that family and friends can help with. When you start one and choose
			“Family and friends” as who funds it, you can invite people here.
		</p>
	{:else}
		<ul class="cards">
			{#each own.items as r (r.id)}
				{@const st = requestStatusText(r.status, r.kind, r.funding)}
				<li class="owned">
					<div class="owned-head">
						<p class="eyebrow">{requestKindLabel(r.kind)} · {formatCents(r.amount_cents)}</p>
						<h3>{r.title}</h3>
						<p class="muted"><strong>{st.label}.</strong> {st.hint}</p>
					</div>
					<InvitePanel
						requestId={r.id}
						kind={r.kind}
						status={r.status}
						amountCents={r.amount_cents}
						headingLevel={3}
					/>
				</li>
			{/each}
		</ul>
	{/if}
</section>

<section class="block" aria-labelledby="supporting-heading">
	<h2 id="supporting-heading">Invited to</h2>
	{#if supporting.state === 'loading'}
		<p class="muted" role="status">Loading the requests you've been invited to…</p>
	{:else if supporting.state === 'error'}
		<div class="error" role="alert">
			<p>Couldn't load them. {supporting.message}</p>
			<button class="btn btn-ghost" type="button" onclick={refreshSupporting}>Try again</button>
		</div>
	{:else if supporting.items.length === 0}
		<p class="empty">
			No one has invited you yet. When someone sends you an invite link, open it while signed in and
			accept it; the request then shows here.
		</p>
	{:else}
		<ul class="cards">
			{#each supporting.items as view (view.request.id)}
				<li>
					<SupportPanel {view} verified={data.verified} headingLevel={3} onpledged={pledged} />
				</li>
			{/each}
		</ul>
	{/if}
</section>

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
		font-size: 22px;
		scroll-margin-top: 80px;
	}

	h3 {
		font-size: 18px;
		overflow-wrap: anywhere;
	}

	.lead,
	.muted {
		color: var(--muted);
	}

	.jump {
		display: flex;
		flex-wrap: wrap;
		gap: 16px;
		font-weight: 600;
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

	.block {
		margin-top: 40px;
		display: grid;
		gap: 16px;
		max-width: 760px;
	}

	.cards {
		list-style: none;
		margin: 0;
		padding: 0;
		display: grid;
		gap: 24px;
	}

	.owned {
		display: grid;
		gap: 12px;
	}

	.owned-head {
		display: grid;
		gap: 4px;
	}

	.owned-head .eyebrow {
		margin: 0;
	}

	.empty {
		background: var(--surface);
		border: 1px dashed var(--border);
		border-radius: var(--radius);
		padding: 20px;
		color: var(--muted);
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
</style>
