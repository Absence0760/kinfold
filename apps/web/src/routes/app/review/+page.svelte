<script lang="ts">
	import { onMount, tick } from 'svelte';
	import { supabase } from '#lib/supabase/client.ts';
	import { explainDbError } from '#lib/review/errors.ts';
	import { loadAppeals, loadQueue } from '#lib/review/queries.ts';
	import type { AppealItem, QueueItem } from '#lib/review/queue.ts';
	import QueueCard from './QueueCard.svelte';
	import AppealCard from './AppealCard.svelte';

	let { data } = $props();

	type Loaded<T> =
		| { state: 'loading' }
		| { state: 'ready'; items: T[] }
		| { state: 'error'; message: string };

	const viewerId = $derived(data.viewer.session.user.id);

	let queue = $state<Loaded<QueueItem>>({ state: 'loading' });
	let appeals = $state<Loaded<AppealItem>>({ state: 'loading' });
	let confirmation = $state('');
	let confirmationEl = $state<HTMLParagraphElement | null>(null);

	async function refreshQueue() {
		try {
			queue = { state: 'ready', items: await loadQueue(supabase(), viewerId) };
		} catch (err) {
			queue = { state: 'error', message: explainDbError(err as { message?: string }) };
		}
	}

	async function refreshAppeals() {
		try {
			appeals = { state: 'ready', items: await loadAppeals(supabase(), viewerId) };
		} catch (err) {
			appeals = { state: 'error', message: explainDbError(err as { message?: string }) };
		}
	}

	onMount(() => {
		if (data.access.reviewer) refreshQueue();
		if (data.access.panel) refreshAppeals();
	});

	async function decided(message: string, refresh: () => Promise<void>) {
		confirmation = message;
		await refresh();
		// The card just decided may have left the list; put focus on the
		// confirmation so keyboard and screen-reader users aren't dropped.
		await tick();
		confirmationEl?.focus();
	}

	function count(n: number, one: string, many: string) {
		return `${n} ${n === 1 ? one : many}`;
	}
</script>

<svelte:head>
	<title>Review · Kinfold</title>
</svelte:head>

<header class="intro">
	<p class="eyebrow">Review console</p>
	<h1>Review</h1>
	<p class="lead">
		The legitimacy score advises; only a person's decision, with a written reason, can refuse a
		request. You see redacted evidence, never originals.
	</p>
	{#if data.access.reviewer && data.access.panel}
		<nav class="jump" aria-label="Sections">
			<a href="#queue-heading">Review queue</a>
			<a href="#appeals-heading">Appeals</a>
		</nav>
	{/if}
</header>

<div role="status">
	{#if confirmation}
		<p class="confirmation" tabindex="-1" bind:this={confirmationEl}>{confirmation}</p>
	{/if}
</div>

{#if data.access.reviewer}
	<section class="block" aria-labelledby="queue-heading">
		<div class="block-head">
			<h2 id="queue-heading">Review queue</h2>
			{#if queue.state === 'ready'}
				<p class="muted">{count(queue.items.length, 'request', 'requests')}</p>
			{/if}
		</div>
		{#if queue.state === 'loading'}
			<p class="muted" role="status">Loading the queue…</p>
		{:else if queue.state === 'error'}
			<div class="error" role="alert">
				<p>Couldn't load the queue. {queue.message}</p>
				<button class="btn btn-ghost" type="button" onclick={refreshQueue}>Try again</button>
			</div>
		{:else if queue.items.length === 0}
			<p class="empty">Nothing is waiting for a reviewer. Requests appear here when they need a person: a low legitimacy score, a fraud flag or an upheld appeal.</p>
		{:else}
			<ul class="cards">
				{#each queue.items as item (item.request.id)}
					<li><QueueCard {item} ondecided={(m) => decided(m, refreshQueue)} /></li>
				{/each}
			</ul>
		{/if}
	</section>
{/if}

{#if data.access.panel}
	<section class="block" aria-labelledby="appeals-heading">
		<div class="block-head">
			<h2 id="appeals-heading">Appeals</h2>
			{#if appeals.state === 'ready'}
				<p class="muted">{count(appeals.items.length, 'open appeal', 'open appeals')}</p>
			{/if}
		</div>
		{#if appeals.state === 'loading'}
			<p class="muted" role="status">Loading appeals…</p>
		{:else if appeals.state === 'error'}
			<div class="error" role="alert">
				<p>Couldn't load appeals. {appeals.message}</p>
				<button class="btn btn-ghost" type="button" onclick={refreshAppeals}>Try again</button>
			</div>
		{:else if appeals.items.length === 0}
			<p class="empty">No open appeals. When a member appeals a refusal, it shows here.</p>
		{:else}
			<ul class="cards">
				{#each appeals.items as item (item.appeal.id)}
					<li><AppealCard {item} ondecided={(m) => decided(m, refreshAppeals)} /></li>
				{/each}
			</ul>
		{/if}
	</section>
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

	.lead {
		color: var(--muted);
	}

	.jump {
		display: flex;
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

	.block-head {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: 12px;
		flex-wrap: wrap;
	}

	h2 {
		font-size: 22px;
		scroll-margin-top: 80px;
	}

	.muted {
		color: var(--muted);
	}

	.cards {
		list-style: none;
		margin: 0;
		padding: 0;
		display: grid;
		gap: 20px;
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
