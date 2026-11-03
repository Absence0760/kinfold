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
	import { supabase } from '#lib/supabase/client.ts';
	import { define } from '#lib/board/terms.ts';
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
			own = { state: 'ready', items: await loadOwnPeopleRequests(supabase(), data.viewerId) };
		} catch (err) {
			own = { state: 'error', message: why(err) };
		}
	}

	async function refreshSupporting() {
		supporting = { state: 'loading' };
		try {
			const rows = await loadSupporting(supabase(), data.viewerId);
			const views = await Promise.all(rows.map((r) => loadSupportView(supabase(), r.id, data.viewerId)));
			supporting = { state: 'ready', items: views.filter((v): v is SupportView => v != null) };
		} catch (err) {
			supporting = { state: 'error', message: why(err) };
		}
	}

	onMount(() => {
		refreshOwn();
		refreshSupporting();
	});

	let ownHeading = $state<HTMLElement>();
	let supportingHeading = $state<HTMLElement>();

	// Try again swaps the error block (and the button that had focus) for the
	// list; park focus on the section heading so keyboard users stay in place.
	async function retry(refresh: () => Promise<void>, heading: () => HTMLElement | undefined) {
		await refresh();
		await tick();
		heading()?.focus();
	}

	// One live region per page, mounted empty, whose text changes: a region
	// inserted already holding its text isn't reliably announced.
	const loadingText = $derived(
		[
			own.state === 'loading' ? 'Loading your requests…' : '',
			supporting.state === 'loading' ? 'Loading the requests you’ve been invited to…' : ''
		]
			.filter(Boolean)
			.join(' ')
	);

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
		invited you to. Help is a gift or a 0% loan, always paid straight to the payee: the shop,
		contractor or lender.
	</p>
	<details class="words">
		<summary>What “payee” and “the pool” mean</summary>
		<dl>
			<div>
				<dt>Payee</dt>
				<dd>{define('payee')}</dd>
			</div>
			<div>
				<dt>The pool</dt>
				<dd>{define('pool')}</dd>
			</div>
			<div>
				<dt>A run of the pool</dt>
				<dd>{define('poolRun')}</dd>
			</div>
		</dl>
	</details>
	<nav class="jump" aria-label="Sections">
		<a href="#own-heading">Your requests</a>
		<a href="#supporting-heading">Invited to</a>
	</nav>
</header>

<p class="visually-hidden" role="status">{loadingText}</p>

<div role="status">
	{#if confirmation}
		<p class="confirmation" tabindex="-1" bind:this={confirmationEl}>{confirmation}</p>
	{/if}
</div>

<section class="block" aria-labelledby="own-heading">
	<h2 id="own-heading" tabindex="-1" bind:this={ownHeading}>Your requests</h2>
	{#if own.state === 'loading'}
		<p class="muted" aria-hidden="true">Loading your requests…</p>
	{:else if own.state === 'error'}
		<div class="error" role="alert">
			<p>Couldn't load your requests. {own.message}</p>
			<button class="btn btn-ghost" type="button" onclick={() => retry(refreshOwn, () => ownHeading)}>
				Try again<span class="visually-hidden"> loading your requests</span>
			</button>
		</div>
	{:else if own.items.length === 0}
		<div class="empty">
			<p>
				You have no requests that family and friends can help with. Start one and choose “Family and
				friends” as who funds it, then come back here to invite people.
			</p>
			<a class="btn btn-primary" href="/app/requests/new">Ask for help</a>
		</div>
	{:else}
		<!-- list-style:none removes list semantics in Safari; the role puts them back. -->
		<!-- svelte-ignore a11y_no_redundant_roles -->
		<ul class="cards" role="list">
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
						title={r.title}
						headingLevel={4}
					/>
				</li>
			{/each}
		</ul>
	{/if}
</section>

<section class="block" aria-labelledby="supporting-heading">
	<h2 id="supporting-heading" tabindex="-1" bind:this={supportingHeading}>Invited to</h2>
	{#if supporting.state === 'loading'}
		<p class="muted" aria-hidden="true">Loading the requests you've been invited to…</p>
	{:else if supporting.state === 'error'}
		<div class="error" role="alert">
			<p>Couldn't load them. {supporting.message}</p>
			<button
				class="btn btn-ghost"
				type="button"
				onclick={() => retry(refreshSupporting, () => supportingHeading)}
			>
				Try again<span class="visually-hidden"> loading the requests you’ve been invited to</span>
			</button>
		</div>
	{:else if supporting.items.length === 0}
		<p class="empty">
			No one has invited you yet. When someone sends you an invite link, open it while signed in and
			accept it; the request then shows here.
		</p>
	{:else}
		<!-- svelte-ignore a11y_no_redundant_roles -->
		<ul class="cards" role="list">
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
		gap: 4px 20px;
		font-weight: 600;
	}

	.jump a {
		display: inline-flex;
		align-items: center;
		min-height: 44px;
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

	div.empty {
		display: grid;
		gap: 12px;
		justify-items: start;
	}

	.error .btn,
	.empty .btn {
		min-height: 44px;
	}

	.words summary {
		cursor: pointer;
		min-height: 44px;
		display: flex;
		align-items: center;
		font-weight: 600;
	}

	.words dl {
		margin: 4px 0 0;
		display: grid;
		gap: 10px;
	}

	.words dt {
		font-weight: 600;
	}

	.words dd {
		margin: 2px 0 0;
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
