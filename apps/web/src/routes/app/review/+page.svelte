<script lang="ts">
	import { onMount, tick } from 'svelte';
	import { supabase } from '#lib/supabase/client.ts';
	import { define } from '#lib/board/terms.ts';
	import { explainDbError } from '#lib/review/errors.ts';
	import { loadAppeals, loadAuditTail, loadLedgerDifferences, loadPoolRuns, loadQueue, loadStandingClaims } from '#lib/review/queries.ts';
	import { auditWord, formatCents, accountWord, fundWord } from '#lib/review/labels.ts';
	import { formatDay } from '#lib/dashboard/format.ts';
	import type { AppealItem, QueueItem } from '#lib/review/queue.ts';
	import type { StandingClaim } from '#lib/review/queries.ts';
	import type { AuditRow, LedgerDifference, PoolRun } from '#lib/review/queries.ts';
	import QueueCard from './QueueCard.svelte';
	import ClaimCard from './ClaimCard.svelte';
	import AppealCard from './AppealCard.svelte';

	let { data } = $props();

	type Loaded<T> =
		| { state: 'loading' }
		| { state: 'ready'; items: T[] }
		| { state: 'error'; message: string };

	const viewerId = $derived(data.viewer.session.user.id);

	let queue = $state<Loaded<QueueItem>>({ state: 'loading' });
	let appeals = $state<Loaded<AppealItem>>({ state: 'loading' });
	let claims = $state<Loaded<StandingClaim>>({ state: 'loading' });
	let trail = $state<Loaded<AuditRow>>({ state: 'loading' });
	let differences = $state<Loaded<LedgerDifference>>({ state: 'loading' });
	let runs = $state<Loaded<PoolRun>>({ state: 'loading' });
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

	async function refreshTrail() {
		try {
			trail = { state: 'ready', items: await loadAuditTail(supabase()) };
		} catch (err) {
			trail = { state: 'error', message: explainDbError(err as { message?: string }) };
		}
	}

	async function refreshDifferences() {
		try {
			differences = { state: 'ready', items: await loadLedgerDifferences(supabase()) };
		} catch (err) {
			differences = { state: 'error', message: explainDbError(err as { message?: string }) };
		}
	}

	async function refreshRuns() {
		try {
			runs = { state: 'ready', items: await loadPoolRuns(supabase()) };
		} catch (err) {
			runs = { state: 'error', message: explainDbError(err as { message?: string }) };
		}
	}

	async function refreshClaims() {
		try {
			claims = { state: 'ready', items: await loadStandingClaims(supabase()) };
		} catch (err) {
			claims = { state: 'error', message: explainDbError(err as { message?: string }) };
		}
	}

	onMount(() => {
		if (data.access.reviewer) refreshQueue();
		if (data.access.panel) refreshAppeals();
		if (data.access.reviewer) refreshClaims();
		if (data.access.reviewer) refreshTrail();
		if (data.access.reviewer) refreshDifferences();
		if (data.access.reviewer) refreshRuns();
	});

	async function decided(message: string, refresh: () => Promise<void>) {
		confirmation = message;
		await refresh();
		// The card just decided may have left the list; put focus on the
		// confirmation so keyboard and screen-reader users aren't dropped.
		await tick();
		confirmationEl?.focus();
	}

	let queueHeading = $state<HTMLElement>();
	let appealsHeading = $state<HTMLElement>();
	let claimsHeading = $state<HTMLElement>();

	// Try again swaps the error block (and the button that had focus) for the
	// list; park focus on the section heading so keyboard users stay in place.
	async function retryQueue() {
		queue = { state: 'loading' };
		await refreshQueue();
		await tick();
		queueHeading?.focus();
	}

	async function retryAppeals() {
		appeals = { state: 'loading' };
		await refreshAppeals();
		await tick();
		appealsHeading?.focus();
	}

	async function retryClaims() {
		claims = { state: 'loading' };
		await refreshClaims();
		await tick();
		claimsHeading?.focus();
	}

	// One live region, mounted empty, whose text changes: a region inserted
	// already holding its text isn't reliably announced.
	const loadingText = $derived(
		[
			data.access.reviewer && queue.state === 'loading' ? 'Loading the queue…' : '',
			data.access.panel && appeals.state === 'loading' ? 'Loading appeals…' : '',
			data.access.reviewer && claims.state === 'loading' ? 'Loading claims…' : '',
			data.access.reviewer && trail.state === 'loading' ? 'Reading the trail…' : '',
			data.access.reviewer && differences.state === 'loading' ? 'Reading the alerts…' : '',
			data.access.reviewer && runs.state === 'loading' ? 'Reading the reserves…' : ''
		]
			.filter(Boolean)
			.join(' ')
	);

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
		The evidence score advises; only a person's decision, with a written reason, can refuse a
		request. You see redacted evidence, never originals.
	</p>
	<p class="define"><strong>Redacted:</strong> {define('redacted')}</p>
	{#if data.access.reviewer && data.access.panel}
		<nav class="jump" aria-label="Sections">
			<a href="#queue-heading">Review queue</a>
			<a href="#appeals-heading">Appeals</a>
		</nav>
	{/if}
</header>

<p class="visually-hidden" role="status">{loadingText}</p>

<div role="status">
	{#if confirmation}
		<p class="confirmation" tabindex="-1" bind:this={confirmationEl}>{confirmation}</p>
	{/if}
</div>

{#if data.access.reviewer}
	<section class="block" aria-labelledby="queue-heading">
		<div class="block-head">
			<h2 id="queue-heading" tabindex="-1" bind:this={queueHeading}>Review queue</h2>
			{#if queue.state === 'ready'}
				<p class="muted">{count(queue.items.length, 'request', 'requests')}</p>
			{/if}
		</div>
		{#if queue.state === 'loading'}
			<div aria-hidden="true">
				<p class="muted">Loading the queue…</p>
				<div class="skeleton" aria-hidden="true"></div>
			</div>
		{:else if queue.state === 'error'}
			<div class="error" role="alert">
				<p>Couldn't load the queue. {queue.message}</p>
				<button class="btn btn-ghost" type="button" onclick={retryQueue}>
					Try again<span class="visually-hidden"> loading the queue</span>
				</button>
			</div>
		{:else if queue.items.length === 0}
			<p class="empty">Nothing is waiting for a reviewer. Requests appear here when they need a person: a low evidence score, a fraud flag or an upheld appeal.</p>
		{:else}
<!-- list-style:none removes list semantics in Safari; the role puts them back. -->
			<!-- svelte-ignore a11y_no_redundant_roles -->
			<ul class="cards" role="list">
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
			<h2 id="appeals-heading" tabindex="-1" bind:this={appealsHeading}>Appeals</h2>
			{#if appeals.state === 'ready'}
				<p class="muted">{count(appeals.items.length, 'open appeal', 'open appeals')}</p>
			{/if}
		</div>
		{#if appeals.state === 'loading'}
			<div aria-hidden="true">
				<p class="muted">Loading appeals…</p>
				<div class="skeleton" aria-hidden="true"></div>
			</div>
		{:else if appeals.state === 'error'}
			<div class="error" role="alert">
				<p>Couldn't load appeals. {appeals.message}</p>
				<button class="btn btn-ghost" type="button" onclick={retryAppeals}>
					Try again<span class="visually-hidden"> loading appeals</span>
				</button>
			</div>
		{:else if appeals.items.length === 0}
			<p class="empty">No open appeals. When a member appeals a refusal, it shows here.</p>
		{:else}
<!-- list-style:none removes list semantics in Safari; the role puts them back. -->
			<!-- svelte-ignore a11y_no_redundant_roles -->
			<ul class="cards" role="list">
				{#each appeals.items as item (item.appeal.id)}
					<li><AppealCard {item} ondecided={(m) => decided(m, refreshAppeals)} /></li>
				{/each}
			</ul>
		{/if}
	</section>
{/if}

{#if data.access.reviewer}
	<section class="block" aria-labelledby="claims-heading">
		<div class="block-head">
			<h2 id="claims-heading" tabindex="-1" bind:this={claimsHeading}>Claim decisions</h2>
			{#if claims.state === 'ready'}
				<p class="muted">{count(claims.items.length, 'standing claim', 'standing claims')}</p>
			{/if}
		</div>
		{#if claims.state === 'loading'}
			<div aria-hidden="true">
				<p class="muted">Loading claims…</p>
				<div class="skeleton" aria-hidden="true"></div>
			</div>
		{:else if claims.state === 'error'}
			<div class="error" role="alert">
				<p>Couldn't load claims. {claims.message}</p>
				<button class="btn btn-ghost" type="button" onclick={retryClaims}>
					Try again<span class="visually-hidden"> loading claims</span>
				</button>
			</div>
		{:else if claims.items.length === 0}
			<p class="empty">No standing claims. Insurer claims appear here when a request you may review has one waiting.</p>
		{:else}
			<!-- list-style:none removes list semantics in Safari; the role puts them back. -->
			<!-- svelte-ignore a11y_no_redundant_roles -->
			<ul class="cards" role="list">
				{#each claims.items as item (item.id)}
					<li><ClaimCard claim={item} ondecided={(m) => decided(m, refreshClaims)} /></li>
				{/each}
			</ul>
		{/if}
	</section>

	<section class="block" aria-labelledby="trail-heading">
		<h2 id="trail-heading">Recent on the trail</h2>
		{#if trail.state === 'loading'}
			<p class="muted">Reading the trail…</p>
		{:else if trail.state === 'error'}
			<p class="muted">Couldn't load the trail. {trail.message}</p>
		{:else if trail.items.length === 0}
			<p class="muted">The trail is quiet — no recorded actions to show.</p>
		{:else}
			<!-- list-style:none removes list semantics in Safari; the role puts them back. -->
			<!-- svelte-ignore a11y_no_redundant_roles -->
			<ul class="cards" role="list">
				{#each trail.items as entry}
					<li><strong>{auditWord(entry.action)}</strong><span class="muted">· {formatDay(entry.at)}</span></li>
				{/each}
			</ul>
		{/if}
	</section>

	<section class="block" aria-labelledby="diff-heading">
		<h2 id="diff-heading">Differences on the books</h2>
		<p class="muted">
			Each line is a fund-level account where the partner's statement and the ledger's own books
			disagree. Nothing here moves money; a difference waits for a person's eyes.
		</p>
		{#if differences.state === 'loading'}
			<p class="muted">Reading the alerts…</p>
		{:else if differences.state === 'error'}
			<p class="muted">Couldn't load the alerts. {differences.message}</p>
		{:else if differences.items.length === 0}
			<p class="muted">Nothing to reconcile — every statement matched the books.</p>
		{:else}
			<!-- list-style:none removes list semantics in Safari; the role puts them back. -->
			<!-- svelte-ignore a11y_no_redundant_roles -->
			<ul class="cards" role="list">
				{#each differences.items as alert}
					<li>
						<strong>{fundWord(alert.fund)} · {accountWord(alert.code)}</strong>
						<span class="muted">
							· statement {formatCents(alert.statementCents)}, books {formatCents(alert.ledgerCents)}
							· {formatDay(alert.at)}
						</span>
					</li>
				{/each}
			</ul>
		{/if}
		<!-- The reconciliation itself is the service's (functions/reconcile): the console
		only shows the alert the schema recorded, never a client-side comparison. -->
	</section>

	<section class="block" aria-labelledby="reserve-heading">
		<h2 id="reserve-heading">What each fund's latest run left in reserve</h2>
		<p class="muted">
			Each line is one fund's money as its latest weekly allocation run saw it: what the
			run paid, and what it left in reserve for the next band. Reading these changes
			nothing; a thin reserve waits for a person's eyes, not for a decision here.
		</p>
		{#if runs.state === 'loading'}
			<p class="muted">Reading the reserves…</p>
		{:else if runs.state === 'error'}
			<p class="muted">Couldn't load the runs. {runs.message}</p>
		{:else if runs.items.length === 0}
			<p class="muted">No allocation run has been recorded yet.</p>
		{:else}
			<!-- list-style:none removes list semantics in Safari; the role puts them back. -->
			<!-- svelte-ignore a11y_no_redundant_roles -->
			<ul class="cards" role="list">
				{#each runs.items as run}
					<li>
						<strong>{fundWord(run.fund)}</strong>
						<span class="muted">
							paid {formatCents(run.allocatedCents)} · reserve {formatCents(run.reserveCents)}
							of {formatCents(run.availableCents)} · {run.algorithmVersion} · {formatDay(run.at)}
						</span>
					</li>
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

	.lead,
	.define {
		color: var(--muted);
	}

	.define strong {
		color: var(--text);
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

	.skeleton {
		height: 160px;
		margin-top: 8px;
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

	.error .btn {
		min-height: 44px;
		justify-content: center;
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
