<script lang="ts">
	import { tick } from 'svelte';
	import {
		amountText,
		countText,
		filterItems,
		fundLabel,
		kindLabel,
		kindsPresent,
		monthLabel,
		payeeLabel,
		progress,
		shortTitle,
		SORT_LABELS,
		sortItems,
		statusLabel,
		type BoardItem,
		type KindFilter,
		type SortOrder,
		type StatusFilter
	} from '#lib/board/board.ts';
	import { loadBoard } from '#lib/board/data.ts';
	import { explainBoardError } from '#lib/board/errors.ts';
	import { define, TERMS, type Term } from '#lib/board/terms.ts';
	import { poolRule } from '#lib/dashboard/labels.ts';
	import { fundForKind } from '#lib/requests/form.ts';
	import { boardBand, scoreBandLabel } from '#lib/requests/score-band.ts';
	import PledgeForm from './PledgeForm.svelte';

	let { data } = $props();

	// The load's promise, replaced on retry.
	let request = $state<Promise<BoardItem[]>>(Promise.resolve([]));
	let items = $state<BoardItem[] | null>(null);
	let failed = $state<string | null>(null);

	let kind = $state<KindFilter>('all');
	let status = $state<StatusFilter>('open');
	let order = $state<SortOrder>('newest');

	function watch(p: Promise<BoardItem[]>) {
		request = p;
		items = null;
		failed = null;
		p.then(
			(v) => {
				if (request === p) items = v;
			},
			(e: unknown) => {
				// Never the raw database message: say what happened and what to do next.
				if (request === p) failed = explainBoardError(e as { code?: string; message?: string });
			}
		);
	}

	$effect(() => watch(data.board));

	let heading = $state<HTMLElement>();

	// Try again replaces the error block (and the button that had focus) with the
	// loading state, then the board: park focus on the page heading once it settles.
	async function retry() {
		const p = loadBoard(data.viewerId);
		watch(p);
		await p.catch(() => undefined);
		await tick();
		heading?.focus();
	}

	const kinds = $derived(items ? kindsPresent(items) : []);
	const shown = $derived(items ? sortItems(filterItems(items, kind, status), order) : []);
	const openCount = $derived(items ? items.filter((i) => i.status === 'open').length : 0);

	// One live region, mounted before the data arrives, whose text changes: a
	// region inserted already holding its text isn't reliably announced.
	const liveText = $derived(
		!data.active || failed
			? ''
			: items === null
				? 'Loading the board…'
				: items.length === 0
					? 'No requests on the board right now.'
					: countText(shown.length, status, kind, openCount)
	);

	// The words this page uses before it explains them, in the order they appear.
	const WORDS: Term[] = ['pool', 'repairFund', 'homeFund', 'poolRun', 'payee', 'redacted'];
	const capital = (s: string) => `${s[0].toUpperCase()}${s.slice(1)}`;

	// Cards where this member just pledged. Their form stays mounted so the thank-you note
	// (and focus) isn't removed when the pledge covers what was left.
	let pledged = $state<Record<string, true>>({});

	function setRaised(id: string, cents: number | null) {
		pledged[id] = true;
		if (!items) return;
		items = items.map((i) => (i.id === id ? { ...i, raisedCents: cents } : i));
	}
</script>

<svelte:head>
	<title>Board · Kinfold</title>
</svelte:head>

<header class="head">
	<h1 bind:this={heading} tabindex="-1">Request board</h1>
	<p class="lead">
		Requests from verified members that ask the pool for help. Each shows a redacted summary the
		member checked and confirmed, the state or region, and the month, never names or towns. Money
		goes to the payee, the shop or lender named on the request, never to the member.
	</p>
	<details class="explain words">
		<summary>What these words mean</summary>
		<dl>
			{#each WORDS as t (t)}
				<div>
					<dt>{capital(TERMS[t].word)}</dt>
					<dd>{define(t)}</dd>
				</div>
			{/each}
		</dl>
	</details>
</header>

<p class="visually-hidden" role="status">{liveText}</p>

{#if !data.active}
	<div class="notice">
		<p class="notice-title">The board opens once your membership is verified.</p>
		<p>
			Only verified members can see other members' requests. When your identity check is done,
			this page fills in.
		</p>
	</div>
{:else if failed}
	<div class="notice" role="alert">
		<p class="notice-title">The board didn't load.</p>
		<p>{failed}</p>
		<button type="button" class="btn btn-ghost small" onclick={retry}>Try again</button>
	</div>
{:else if items === null}
	<div class="loading" aria-hidden="true">
		{#each [1, 2, 3] as i (i)}
			<div class="skeleton" aria-hidden="true"></div>
		{/each}
	</div>
{:else if items.length === 0}
	<div class="notice">
		<p class="notice-title">No requests on the board right now.</p>
		<p>
			A member's request shows here once its evidence has been checked and the member has approved
			the summary other members see, with private details blurred out. Requests stay for 12 months
			after they close.
		</p>
		<p>Need help yourself? Start a request, or invite family and friends to one.</p>
		<div class="cta">
			<a class="btn btn-primary small" href="/app/requests/new">Ask for help</a>
			<a class="btn btn-ghost small" href="/app/invite">Invite someone</a>
		</div>
	</div>
{:else}
	<form class="controls" aria-label="Filter and sort the board" onsubmit={(e) => e.preventDefault()}>
		<label>
			<span>Type</span>
			<select bind:value={kind}>
				<option value="all">All types</option>
				{#each kinds as k (k)}
					<option value={k}>{kindLabel(k)}</option>
				{/each}
			</select>
		</label>
		<label>
			<span>Show</span>
			<select bind:value={status}>
				<option value="open">Asking now</option>
				<option value="all">Last 12 months</option>
			</select>
		</label>
		<label>
			<span>Sort</span>
			<select bind:value={order}>
				{#each Object.entries(SORT_LABELS) as [value, label] (value)}
					<option {value}>{label}</option>
				{/each}
			</select>
		</label>
	</form>

	<!-- Announced by the live region above the board; this copy is for reading. -->
	<p class="count">{countText(shown.length, status, kind, openCount)}</p>

	{#if shown.length === 0}
		<div class="notice">
			<p class="notice-title">Nothing matches.</p>
			<p>
				{status === 'open'
					? 'No request of this type is asking right now. Try "Last 12 months" to see ones already funded.'
					: 'No request of this type in the last 12 months.'}
			</p>
		</div>
	{:else}
		<!-- list-style:none removes list semantics in Safari; the role puts them back. -->
		<!-- svelte-ignore a11y_no_redundant_roles -->
		<ul class="board" role="list">
			{#each shown as item (item.id)}
				{@const p = progress(item)}
				{@const band = item.scoreBand != null ? boardBand(item.scoreBand, fundForKind(item.kind), item.minScore) : null}
				<li class={item.status}>
					<div class="top">
						<span class="kind">{kindLabel(item.kind)}</span>
						<span class="status">{statusLabel(item.status)}</span>
						{#if item.own}<span class="own">Your request</span>{/if}
					</div>

					<h2 class="summary">{item.summary}</h2>

					<dl class="facts">
						<div class="amount">
							<dt>{item.amountCents != null ? 'Asking for' : 'Amount'}</dt>
							<dd>{amountText(item)}</dd>
						</div>
						{#if item.scoreBand != null}
							<div class="band">
								<dt>Legitimacy score</dt>
								<dd>{scoreBandLabel(item.scoreBand)}</dd>
								{#if band}
									<dd class="band-status">{band.status}</dd>
									<dd class="band-detail">{band.detail}</dd>
								{/if}
							</div>
						{/if}
						<div>
							<dt>Where</dt>
							<dd>{item.area ?? 'Not shown'}</dd>
						</div>
						<div>
							<dt>Posted</dt>
							<dd>{monthLabel(item.monthOf)}</dd>
						</div>
					</dl>

					{#if item.status === 'open'}
						{#if p}
							<div class="progress">
								<div class="bar" aria-hidden="true">
									<span style:width="{p.percent}%"></span>
								</div>
								<p class="progress-text">{p.text} ({p.percent}%).</p>
							</div>
						{:else}
							<p class="progress-text">Progress isn't available right now.</p>
						{/if}
					{/if}

					<p class="paid-to">
						Asks the pool: {fundLabel(item.kind)} {poolRule(item.kind)}, and members can give on top.
						Paid to {payeeLabel(item.kind)}, never to the member.
					</p>

					{#if item.status === 'open'}
						<div class="give">
							{#if item.own}
								<p class="aside">
									This is your request, so you can't pledge to it. Family and friends you invite
									can give, or lend at 0%.
								</p>
							{:else if item.takingPledges === false}
								<p class="aside">
									Gifts open once this request's payee has been verified. Kinfold checks the shop or
									lender once before money can move.
								</p>
							{:else if p && (p.leftCents > 0 || pledged[item.id])}
								<PledgeForm
									{item}
									name={shortTitle(item.summary)}
									leftCents={p.leftCents}
									onpledged={(cents) => setRaised(item.id, cents)}
								/>
								{#if p.leftCents > 0}
									<p class="aside">
										From the board you can give. Lending at 0% is only for family and friends the
										member invites.
									</p>
								{/if}
							{:else if p}
								<p class="aside">Fully pledged. Thank you to everyone who gave.</p>
							{/if}
						</div>
					{/if}
				</li>
			{/each}
		</ul>
	{/if}

	<details class="explain">
		<summary>What the legitimacy score means</summary>
		<p>
			The legitimacy score, 0 to 100, measures how well a request's evidence supports it: photos
			that match the estimate, report dates that line up. It isn't a judgement of the person. The
			board shows it in 10-point bands. The community repair fund fills the highest band first, every
			request in it at the same time, then moves down as far as its minimum score. The Community Home
			Fund will choose by a published needs formula, which isn’t live yet, not by band. A request
			under its fund's current minimum relies on gifts. A score never refuses a request; only a person can, in writing, with an appeal.
		</p>
	</details>
{/if}

<style>
	.head {
		max-width: 680px;
	}

	h1 {
		font-size: clamp(26px, 5vw, 34px);
	}

	.lead {
		margin-top: 10px;
		color: var(--muted);
	}

	.small {
		min-height: 44px;
		justify-content: center;
		padding: 8px 18px;
		font-size: 14px;
	}

	.notice {
		margin-top: 24px;
		display: grid;
		gap: 8px;
		justify-items: start;
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius);
		padding: 18px 20px;
		max-width: 680px;
	}

	.notice-title {
		font-weight: 700;
	}

	.loading {
		margin-top: 24px;
		display: grid;
		gap: 12px;
	}

	/* Roughly one request card tall. */
	.loading .skeleton {
		height: 180px;
	}

	.controls {
		margin-top: 24px;
		display: flex;
		flex-wrap: wrap;
		gap: 12px 16px;
	}

	.controls label {
		display: grid;
		gap: 4px;
		font-size: 13px;
		font-weight: 600;
		color: var(--muted);
		flex: 1 1 140px;
		max-width: 240px;
	}

	select {
		font: inherit;
		font-size: 15px;
		color: var(--text);
		background: var(--surface);
		border: 1px solid var(--field-border);
		border-radius: 8px;
		padding: 8px 10px;
		min-height: 44px;
	}

	.count {
		margin-top: 16px;
		font-size: 14px;
		color: var(--muted);
	}

	.board {
		list-style: none;
		margin: 12px 0 0;
		padding: 0;
		display: grid;
		gap: 12px;
	}

	.board li {
		display: grid;
		gap: 12px;
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius);
		padding: 16px;
		min-width: 0;
	}

	.top {
		display: flex;
		flex-wrap: wrap;
		gap: 8px;
		align-items: center;
	}

	.kind {
		font-size: 13px;
		font-weight: 700;
		color: var(--warm);
		text-transform: uppercase;
		letter-spacing: 0.06em;
		margin-right: auto;
	}

	.status,
	.own {
		font-size: 12px;
		font-weight: 700;
		padding: 3px 10px;
		border-radius: 999px;
		background: var(--surface-2);
		color: var(--muted);
		white-space: nowrap;
	}

	/* Body text on the soft fill, for a calmer chip. (--warm on --warm-soft would also
	   pass: 4.95:1 light, 5.65:1 dark.) */
	.open .status {
		background: var(--warm-soft);
		color: var(--text);
	}

	.funded .status,
	.paid .status {
		background: var(--accent-soft);
		color: var(--accent);
	}

	.own {
		background: var(--accent);
		color: var(--accent-contrast);
	}

	.summary {
		font-weight: 600;
		font-size: 17px;
		line-height: 1.35;
		margin: 0;
		overflow-wrap: anywhere;
	}

	.cta {
		display: flex;
		flex-wrap: wrap;
		gap: 8px;
	}

	.words dl {
		margin: 8px 0 0;
		display: grid;
		gap: 10px;
	}

	.words dt {
		font-weight: 600;
		color: var(--text);
	}

	.words dd {
		margin: 2px 0 0;
		color: var(--muted);
	}

	.facts {
		margin: 0;
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: 10px 16px;
	}

	.facts dt {
		font-size: 12px;
		color: var(--muted);
	}

	.facts dd {
		margin: 0;
		font-weight: 600;
		overflow-wrap: anywhere;
		font-variant-numeric: tabular-nums;
	}

	.amount {
		grid-column: 1 / -1;
	}

	/* The band's status in words, neutral for every band: a board request is already open, funded or paid. */
	.band {
		grid-column: 1 / -1;
	}

	.facts .band-status {
		font-weight: 700;
	}

	.facts .band-detail {
		font-weight: 400;
		font-size: 14px;
		color: var(--muted);
	}

	.amount dd {
		font-size: 22px;
		line-height: 1.2;
	}

	.bar {
		height: 8px;
		border-radius: 999px;
		background: var(--surface-2);
		overflow: hidden;
	}

	.bar span {
		display: block;
		height: 100%;
		background: var(--accent);
	}

	.progress-text {
		margin-top: 6px;
		font-size: 14px;
	}

	.paid-to,
	.aside {
		font-size: 13px;
		color: var(--muted);
	}

	.give {
		display: grid;
		gap: 8px;
		justify-items: start;
	}

	.give :global(.panel) {
		justify-self: stretch;
	}

	.explain {
		margin-top: 24px;
		max-width: 680px;
	}

	.head .words {
		margin-top: 12px;
	}

	.explain {
		font-size: 15px;
	}

	.explain summary {
		cursor: pointer;
		padding: 10px 0;
		font-weight: 600;
	}

	.explain p {
		margin-top: 8px;
		color: var(--muted);
	}

	@media (min-width: 720px) {
		.board li {
			padding: 18px 22px;
		}

		.facts {
			grid-template-columns: repeat(4, minmax(0, 1fr));
		}

		.amount {
			grid-column: auto;
		}
	}
</style>
