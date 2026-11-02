<script lang="ts">
	import { tick } from 'svelte';
	import { invalidate } from '$app/navigation';
	import { page } from '$app/state';
	import { formatCents, formatDay } from '#lib/dashboard/format.ts';
	import { fundingLabel, payeeWord, requestKindLabel, requestStatusText } from '#lib/dashboard/labels.ts';
	import {
		confirmSummary,
		submitRequest,
		updateDraft,
		withdrawRequest,
		type FormContext,
		type RequestDetail,
		type ReviewRow
	} from '#lib/requests/data.ts';
	import { poolProblems, usesPool } from '#lib/requests/eligibility.ts';
	import { asPeopleOnly, draftToInput, fundForKind, payeeKindLabel } from '#lib/requests/form.ts';
	import { payoutText } from '#lib/requests/payout.ts';
	import { minScoreFor, reviewSinceScore, scoreBand } from '#lib/requests/score-band.ts';
	import {
		appealState,
		canChangeEvidence,
		canConfirmSummary,
		canEdit,
		canWithdraw,
		reviewerAsk,
		submitBlockerList,
		whatHappensNext,
		type Blocker,
		type RequestState
	} from '#lib/requests/next.ts';
	import Badge from '../Badge.svelte';
	import RequestForm from '../RequestForm.svelte';
	import AppealPanel from './AppealPanel.svelte';
	import ClaimsPanel from './ClaimsPanel.svelte';
	import EvidencePanel from './EvidencePanel.svelte';
	import InvitePanel from '#lib/invites/InvitePanel.svelte';

	let { data } = $props();

	// undefined while the first read is in flight; null when it isn't the member's.
	let detail = $state<RequestDetail | null | undefined>(undefined);
	let ctx = $state<FormContext | null>(null);
	let loadError = $state<string | null>(null);
	let retrying = $state(false);

	// Keep what's on screen while an action re-reads, so nothing flashes.
	$effect(() => {
		const p = data.detail;
		loadError = null;
		p.then(
			(v) => {
				if (data.detail === p) detail = v;
			},
			(e: unknown) => {
				if (data.detail === p) loadError = e instanceof Error ? e.message : 'Unknown error';
			}
		);
	});
	$effect(() => {
		const p = data.ctx;
		p.then(
			(v) => {
				if (data.ctx === p) ctx = v;
			},
			// Without it, only the early pool warnings are missing; submit still checks.
			() => {}
		);
	});

	const uid = $derived(data.viewer.session.user.id);
	const active = $derived(data.viewer.member?.status === 'active');

	const r = $derived(detail?.request ?? null);
	const rs = $derived<RequestState | null>(
		detail && r
			? {
					status: r.status,
					kind: r.kind,
					funding: r.funding,
					hasPayee: r.payee_id != null,
					evidence: detail.evidence,
					publicSummary: r.public_summary,
					summaryConfirmed: r.public_summary_confirmed_at != null,
					appeals: detail.appeals,
					refusals: detail.events.filter((e) => e.to_status === 'refused').length
				}
			: null
	);
	const status = $derived(r ? requestStatusText(r.status, r.kind, r.funding) : null);
	const next = $derived(rs ? whatHappensNext(rs) : null);
	const pool = $derived(
		r && ctx && canChangeEvidence(r)
			? poolProblems(
					{ kind: r.kind, funding: r.funding, amountCents: r.amount_cents, incidentOn: r.incident_on, assetId: r.asset_id },
					{
						settings: ctx.settings.find((s) => s.fund === fundForKind(r.kind)) ?? null,
						coverageStartedOn: ctx.coverageStartedOn,
						assets: ctx.assets
					}
				)
			: []
	);
	const blockers = $derived<Blocker[]>(
		rs && canChangeEvidence(rs)
			? [
					...(active
						? []
						: [{ who: 'member' as const, text: 'Verify your identity first. Kinfold checks every member once before a request can go out.' }]),
					...submitBlockerList(rs),
					...pool.map((text) => ({ who: 'member' as const, text }))
				]
			: []
	);
	// Kinfold's own pending steps go last, under their own heading, so the
	// member's list is only what they can do.
	const memberBlockers = $derived(blockers.filter((b) => b.who === 'member'));
	const kinfoldBlockers = $derived(blockers.filter((b) => b.who === 'kinfold'));
	// The pool can't take this draft as it stands; family and friends can.
	const canSwitchToPeople = $derived(r != null && r.status === 'draft' && r.funding !== 'people' && pool.length > 0);
	const ask = $derived(r?.status === 'needs_evidence' && detail ? reviewerAsk(detail.reviews) : null);
	const appeal = $derived(rs ? appealState(rs) : 'not_refused');
	// No status line until the fund's minimum is read (and none if that read
	// fails): just the score and its reasons, never a guessed minimum. The
	// member's reviews say whether a person has decided yet.
	const minScore = $derived(r && ctx ? minScoreFor(ctx.settings, fundForKind(r.kind)) : null);
	const band = $derived(
		detail?.score && r && minScore != null
			? scoreBand(detail.score.score, {
					status: r.status,
					minScore,
					review: reviewSinceScore(detail.reviews, detail.score.scoredAt)
				})
			: null
	);

	// --- confirmations ------------------------------------------------------------------
	// svelte-ignore state_referenced_locally
	let notice = $state<string | null>(
		page.url.searchParams.get('saved') ? 'Draft saved. Add your evidence next, then submit it.' : null
	);
	let noticeBox = $state<HTMLElement>();
	let actionError = $state<string | null>(null);
	let errorBox = $state<HTMLElement>();
	let busy = $state<'submit' | 'withdraw' | 'summary' | 'switch' | null>(null);
	let confirmingWithdraw = $state(false);

	async function askWithdraw(open: boolean) {
		if (open && busy) return;
		confirmingWithdraw = open;
		await tick();
		document.getElementById(open ? 'withdraw-confirm' : 'withdraw-btn')?.focus();
	}
	let editing = $state(false);

	/** Open the edit form with focus on its heading; Cancel returns focus to "Edit draft". */
	async function setEditing(open: boolean) {
		if (open && (busy || !ctx)) return;
		editing = open;
		await tick();
		document.getElementById(open ? 'edit-h' : 'edit-btn')?.focus();
	}

	function submit() {
		// aria-disabled keeps the button (and its reasons) in the Tab order, so
		// the guard lives here.
		if (busy || blockers.length > 0 || !r) return;
		const id = r.id;
		act('submit', () => submitRequest(id), 'Submitted. Your evidence is being read and scored; the result will show here.');
	}

	function switchToPeople() {
		if (busy || !r) return;
		const values = asPeopleOnly(r);
		act('switch', () => updateDraft(r.id, values), 'Switched to family and friends. The pool’s limits no longer apply to this draft.');
	}

	$effect(() => {
		if (notice && noticeBox) noticeBox.focus();
	});

	/** Re-read the request, then announce what changed and move focus to it. */
	async function refresh(message: string) {
		await invalidate('app:request');
		try {
			await data.detail;
		} catch {
			// The error state shows it.
		}
		notice = null;
		await tick();
		notice = message;
		await tick();
		noticeBox?.focus();
	}

	/** Re-read quietly: the evidence panel announces and places focus itself. */
	async function reload() {
		await invalidate('app:request');
		try {
			await data.detail;
		} catch {
			// The error state shows it.
		}
		await tick();
	}

	async function act(kind: NonNullable<typeof busy>, fn: () => Promise<void>, message: string) {
		if (busy) return;
		actionError = null;
		busy = kind;
		try {
			await fn();
			confirmingWithdraw = false;
			await refresh(message);
		} catch (err) {
			actionError = err instanceof Error ? err.message : 'That didn’t go through. Try again.';
			await tick();
			errorBox?.focus();
		} finally {
			busy = null;
		}
	}

	async function retry() {
		if (retrying) return;
		retrying = true;
		try {
			await invalidate('app:request');
			await data.detail.catch(() => {});
		} finally {
			retrying = false;
			// The retry button goes with the error block. Every state below has
			// one h1 with this id; park focus there, as Home does.
			await tick();
			document.getElementById('request-h1')?.focus();
		}
	}

	const decisionLabels: Record<ReviewRow['decision'], string> = {
		approve: 'Approved',
		needs_evidence: 'Asked for more evidence',
		refuse: 'Declined',
		escalate: 'Passed to another reviewer'
	};

	const when = (at: string) =>
		new Date(at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
</script>

<svelte:head>
	<title>{r ? r.title : 'Your request'} · Kinfold</title>
</svelte:head>

<p class="back"><a href="/app">← Your home</a></p>

{#if loadError && detail === undefined}
	<div class="panel error" role="alert">
		<h1 id="request-h1" tabindex="-1">We couldn’t load this request</h1>
		<p>{loadError} Nothing on your request has changed.</p>
		<button type="button" class="btn btn-primary" onclick={retry} aria-disabled={retrying ? 'true' : undefined}>
			{retrying ? 'Trying again…' : 'Try again'}
		</button>
	</div>
{:else if detail === undefined}
	<div class="loading" role="status">
		<span class="visually-hidden">Loading your request…</span>
		{#each [1, 2, 3] as i (i)}<div class="skeleton" aria-hidden="true"></div>{/each}
	</div>
{:else if !data.viewer.member}
	<!-- No members row: RLS hides every request, so "not found" would mislead.
	     Same wording as Home, which can't fix it either, so no link back to it. -->
	<section class="panel" aria-labelledby="request-h1">
		<h1 id="request-h1" tabindex="-1">Your member profile isn’t set up yet</h1>
		<p>
			You’re signed in, but this account doesn’t have a Kinfold member profile yet, so requests
			aren’t open to you. A profile can’t be created from this page yet.
		</p>
		<p>
			Membership is by invitation for now. Ask the member who invited you to contact the Kinfold
			team, who will finish setting up your profile. Then sign in again.
		</p>
	</section>
{:else if detail === null || !r || !rs || !status || !next}
	<div class="panel">
		<h1 id="request-h1" tabindex="-1">We couldn’t find this request</h1>
		<p>
			It isn’t on your account. If it’s a relative’s request, open the invite link they sent you.
			Your own requests are listed on your home page.
		</p>
		<a class="btn btn-ghost" href="/app">See your requests</a>
	</div>
{:else}
	<header class="page-head">
		<p class="eyebrow">Your request</p>
		<div class="title-row">
			<h1 id="request-h1" tabindex="-1">{r.title}</h1>
			<Badge tone={status.tone} label={status.label} />
		</div>
		<dl class="facts">
			<div><dt>For</dt><dd>{requestKindLabel(r.kind)}</dd></div>
			<div><dt>Asking</dt><dd>{fundingLabel(r.funding, r.kind)}</dd></div>
			<div><dt>Amount</dt><dd><strong>{formatCents(r.amount_cents)}</strong></dd></div>
			<div><dt>Happened</dt><dd>{formatDay(r.incident_on)}</dd></div>
			<div>
				<dt>Paid to</dt>
				<dd>
					{#if detail.payee}
						{detail.payee.legal_name} ({payeeKindLabel(detail.payee.kind).toLowerCase()}, {detail.payee.region})
						{#if detail.payee.status !== 'verified'}
							<span class="sub">Waiting for Kinfold to verify the business. Pledges open once it’s verified.</span>
						{/if}
					{:else}
						Not chosen yet
					{/if}
				</dd>
			</div>
			{#if detail.asset}
				<div><dt>Car</dt><dd>{detail.asset.description}</dd></div>
			{/if}
		</dl>
	</header>

	{#if notice}
		<p class="notice" role="status" tabindex="-1" bind:this={noticeBox}>{notice}</p>
	{/if}

	{#if editing && ctx}
		<section class="block" aria-labelledby="edit-h">
			<h2 id="edit-h" tabindex="-1">Edit your draft</h2>
			<RequestForm
				{ctx}
				{uid}
				region={data.viewer.member?.region ?? 'CA'}
				initial={draftToInput(r)}
				requestId={r.id}
				createdAt={r.created_at}
				onsaved={async () => {
					editing = false;
					await refresh('Changes saved.');
				}}
				oncancel={() => setEditing(false)}
			/>
		</section>
	{:else}
		<section class="block now" aria-labelledby="now-h">
			<h2 id="now-h">Where it is now</h2>
			<p class="now-line">{next.now}</p>
			{#if ask}
				<div class="ask">
					<p><strong>What the reviewer asked for:</strong></p>
					<blockquote>{ask}</blockquote>
				</div>
			{/if}
			<h3 class="small-h">What happens next</h3>
			<ol class="steps">
				{#each next.steps as step (step)}<li>{step}</li>{/each}
			</ol>

			{#if canChangeEvidence(rs) && blockers.length}
				<div class="blockers" role="note" aria-labelledby="blockers-h">
					<p id="blockers-h"><strong>Before this can be submitted:</strong></p>
					{#if memberBlockers.length}
						<ul id="blockers-list">{#each memberBlockers as b (b.text)}<li>{b.text}</li>{/each}</ul>
					{/if}
					{#if kinfoldBlockers.length}
						<ul id="blockers-kinfold" class="kinfold">
							{#each kinfoldBlockers as b (b.text)}<li>{b.text}</li>{/each}
						</ul>
					{/if}
					{#if canSwitchToPeople}
						<p class="switch-note">
							Family and friends don’t have the pool’s limits. You can switch this draft to ask only them,
							and change it back later while it’s still a draft.
						</p>
						<button
							type="button"
							class="btn btn-ghost"
							onclick={switchToPeople}
							aria-disabled={busy !== null ? 'true' : undefined}
						>
							{busy === 'switch' ? 'Switching…' : 'Switch to family and friends'}
						</button>
					{/if}
				</div>
			{/if}

			{#if actionError}
				<p class="problem-box" role="alert" tabindex="-1" bind:this={errorBox}>{actionError}</p>
			{/if}

			<div class="actions">
				{#if canChangeEvidence(rs)}
					<!-- aria-disabled, not disabled: the button stays in the Tab order and
					     its reasons are read on focus. `submit` guards the click. -->
					<button
						type="button"
						class="btn btn-primary"
						aria-disabled={busy !== null || blockers.length > 0 ? 'true' : undefined}
						aria-describedby={blockers.length
							? ['blockers-h', memberBlockers.length ? 'blockers-list' : '', kinfoldBlockers.length ? 'blockers-kinfold' : '']
									.filter(Boolean)
									.join(' ')
							: undefined}
						onclick={submit}
					>
						{busy === 'submit' ? 'Submitting…' : r.status === 'draft' ? 'Submit request' : 'Submit again'}
					</button>
				{/if}
				{#if canEdit(rs)}
					<button
						id="edit-btn"
						type="button"
						class="btn btn-ghost"
						aria-disabled={busy !== null || !ctx ? 'true' : undefined}
						onclick={() => setEditing(true)}
					>
						Edit draft
					</button>
				{/if}
				{#if canWithdraw(rs) && !confirmingWithdraw}
					<button
						id="withdraw-btn"
						type="button"
						class="btn btn-ghost"
						aria-disabled={busy !== null ? 'true' : undefined}
						onclick={() => askWithdraw(true)}
					>
						Withdraw
					</button>
				{/if}
			</div>

			{#if confirmingWithdraw}
				<div class="confirm" id="withdraw-confirm" tabindex="-1" role="group" aria-labelledby="withdraw-h">
					<p id="withdraw-h"><strong>Withdraw this request?</strong></p>
					<p>
						It stops here. Any pledges are released and nobody is charged. You can’t undo this, but you can
						start a new request.
					</p>
					<div class="actions">
						<button
							type="button"
							class="btn btn-primary"
							aria-disabled={busy !== null ? 'true' : undefined}
							onclick={() => act('withdraw', () => withdrawRequest(r.id), 'Withdrawn. Any pledges were released.')}
						>
							{busy === 'withdraw' ? 'Withdrawing…' : 'Yes, withdraw it'}
						</button>
						<button type="button" class="btn btn-ghost" onclick={() => askWithdraw(false)}>Keep it</button>
					</div>
				</div>
			{/if}
		</section>
	{/if}

	<section class="block" aria-labelledby="score-h">
		<h2 id="score-h">Evidence score</h2>
		<p class="note">How well the evidence backs the request, out of 100. It measures the evidence, not you.</p>
		{#if detail.score}
			<div class="panel score">
				<p class="score-line"><span class="score-num">{detail.score.score}</span> <span>out of 100</span></p>
				{#if band}
					<p class="band" class:needs={band.tone === 'needs-evidence'}>
						<strong>{band.status}</strong> <span class="band-range">(band {band.label})</span>
						<span class="band-detail">{band.detail}</span>
					</p>
				{/if}
				<p class="sub">A score explains the evidence; it isn’t a verdict. A person can still look at it.</p>
				{#if detail.score.reasons.length}
					<p class="why">Why this score:</p>
					<ul class="reasons">{#each detail.score.reasons as reason, i (i)}<li>{reason}</li>{/each}</ul>
				{:else}
					<p class="why">No reasons were recorded with this score.</p>
				{/if}
				<p class="fine">
					A low score sends a request to a person or asks for more evidence; it never refuses one on its
					own. Scored {when(detail.score.scoredAt)} by {detail.score.model} {detail.score.modelVersion}.
				</p>
			</div>
		{:else}
			<p class="panel empty">
				{r.status === 'scoring'
					? 'Being scored now. The score and the reasons for it will show here.'
					: 'Not scored yet. It’s scored once you submit it.'}
			</p>
		{/if}
	</section>

	{#if detail.reviews.length}
		<section class="block" aria-labelledby="reviews-h">
			<h2 id="reviews-h">What reviewers decided</h2>
			<p class="note">
				Reviewers are trained members from another state. Their names aren’t shown, so each decision
				stays about the evidence.
			</p>
			<!-- list-style:none removes list semantics in Safari; the role puts them back. -->
			<!-- svelte-ignore a11y_no_redundant_roles -->
			<ul class="list" role="list">
				{#each detail.reviews as rv, i (i)}
					<li class="panel">
						<p><strong>{decisionLabels[rv.decision]}</strong> <span class="sub-inline">· {when(rv.created_at)}</span></p>
						<blockquote>{rv.reason}</blockquote>
					</li>
				{/each}
			</ul>
		</section>
	{/if}

	{#if detail.claims.length}
		<ClaimsPanel claims={detail.claims} onrefresh={refresh} />
	{/if}

	{#if r.status === 'refused' || detail.appeals.length}
		<AppealPanel requestId={r.id} status={appeal} appeals={detail.appeals} onfiled={refresh} />
	{/if}

	<section class="block" aria-labelledby="words-h">
		<h2 id="words-h">What you wrote, and what others see</h2>
		<div class="two">
			<div class="panel">
				<h3 class="small-h">Not on the board</h3>
				<p class="sub">
					Read by you, the scorer, reviewers, and family or friends you invite to support this request.
					Leave other people’s names, plates and addresses out of it.
				</p>
				<p class="private-title"><strong>{r.title}</strong></p>
				{#if r.description}
					<p class="desc">{r.description}</p>
				{:else}
					<p class="sub">No description.</p>
				{/if}
			</div>
			<div class="panel">
				<h3 class="small-h">On the members-only board</h3>
				{#if !usesPool(r.funding)}
					<p>
						Nothing. Requests only family and friends pay for don’t go on the board, so there’s no
						public summary.
					</p>
				{:else if !r.public_summary}
					<p>
						Nothing yet. Once your evidence is redacted, Kinfold writes a short summary with names, places
						and dates taken out. You’ll read it here and confirm it before it goes anywhere.
					</p>
				{:else}
					<p class="sub">This exact text:</p>
					<blockquote class="summary">{r.public_summary}</blockquote>
					<p class="sub">
						Only verified members see the board. Beside this summary it shows the kind of request, the
						amount (exact while it’s being funded, then a range), the score in tens, your state (or a
						wider region where few members live), and the month. Never your name, your town or the exact
						date.
					</p>
					{#if r.public_summary_confirmed_at}
						<p class="ok">
							You confirmed it on {when(r.public_summary_confirmed_at)}. If the summary changes, you’ll be
							asked again.
						</p>
					{:else if canConfirmSummary(rs)}
						<button
							type="button"
							class="btn btn-primary"
							aria-disabled={busy !== null ? 'true' : undefined}
							onclick={() =>
								act('summary', () => confirmSummary(r.id), 'Summary confirmed. It can now show on the members-only board.')}
						>
							{busy === 'summary' ? 'Confirming…' : 'This is fine to show members'}
						</button>
						<p class="sub">If something here could identify you, don’t confirm it: it stays off the board until you do.</p>
					{/if}
				{/if}
			</div>
		</div>
	</section>

	{#if detail.payouts.length}
		{@const payee = detail.payee?.legal_name ?? payeeWord(r.kind)}
		<section class="block" aria-labelledby="payouts-h">
			<h2 id="payouts-h">Payment to {payee}</h2>
			<p class="note">The payment partner sends the money straight to {payee}. Kinfold never holds it, and it never goes to you.</p>
			<!-- svelte-ignore a11y_no_redundant_roles -->
			<ul class="list" role="list">
				{#each detail.payouts as p (p.id)}
					{@const t = payoutText(p, payee)}
					<li class="panel">
						<div class="title-row">
							<p><strong>{formatCents(p.amount_cents)}</strong></p>
							<Badge tone={t.tone} label={t.label} />
						</div>
						<p>{t.line}</p>
					</li>
				{/each}
			</ul>
		</section>
	{/if}

	<EvidencePanel
		evidence={detail.evidence}
		requestId={r.id}
		{uid}
		kind={r.kind}
		editable={canChangeEvidence(rs)}
		onreload={reload}
	/>

	<!-- Family and friends: create_invite works until the request closes. -->
	{#if r.funding !== 'pool' && !['withdrawn', 'expired', 'refused', 'paid'].includes(r.status)}
		<section class="block invite-slot">
			<InvitePanel requestId={r.id} kind={r.kind} status={r.status} amountCents={r.amount_cents} headingLevel={2} />
		</section>
	{/if}

	{#if detail.events.length}
		<section class="block" aria-labelledby="history-h">
			<h2 id="history-h">History</h2>
			<!-- svelte-ignore a11y_no_redundant_roles -->
			<ol class="history" role="list">
				{#each detail.events as ev (ev.id)}
					<li>
						<span class="when">{when(ev.at)}</span>
						{ev.from_status == null
							? 'Started as a draft'
							: requestStatusText(ev.to_status, r.kind, r.funding).label}
					</li>
				{/each}
			</ol>
			<p class="fine">Money only ever goes to {payeeWord(r.kind)}, never to you.</p>
		</section>
	{/if}
{/if}

<style>
	.back {
		margin: 0 0 16px;
		font-size: 15px;
	}

	.back a {
		color: var(--accent);
		display: inline-flex;
		align-items: center;
		min-height: 44px;
	}

	.page-head {
		margin-bottom: 8px;
	}

	.title-row {
		display: flex;
		flex-wrap: wrap;
		align-items: flex-start;
		justify-content: space-between;
		gap: 8px 16px;
	}

	h1 {
		font-size: clamp(26px, 5vw, 36px);
		flex: 1 1 14rem;
		overflow-wrap: anywhere;
	}

	.block {
		margin-top: 36px;
	}

	.block h2 {
		font-size: 22px;
	}

	.small-h {
		font-size: 13px;
		font-weight: 700;
		letter-spacing: 0.06em;
		text-transform: uppercase;
		color: var(--muted);
		margin: 14px 0 4px;
	}

	.facts {
		margin: 16px 0 0;
		display: grid;
		gap: 10px 24px;
		grid-template-columns: repeat(auto-fit, minmax(min(100%, 12rem), 1fr));
	}

	.facts dt {
		color: var(--muted);
		font-size: 13px;
		font-weight: 700;
		letter-spacing: 0.04em;
		text-transform: uppercase;
	}

	.facts dd {
		margin: 2px 0 0;
		font-size: 15px;
		overflow-wrap: anywhere;
	}

	.sub {
		display: block;
		color: var(--muted);
		font-size: 14px;
		margin: 0;
	}

	.sub-inline {
		color: var(--muted);
		font-size: 14px;
	}

	.note {
		color: var(--muted);
		font-size: 15px;
		margin-top: 6px;
		max-width: 680px;
	}

	.panel {
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius);
		padding: 16px 18px;
		margin-top: 12px;
		display: grid;
		gap: 8px;
		align-content: start;
	}

	.panel.error {
		border-color: var(--warm);
		justify-items: start;
	}

	.panel.empty {
		border-style: dashed;
		color: var(--muted);
	}

	.now-line {
		margin-top: 6px;
		font-size: 17px;
		max-width: 680px;
	}

	.steps {
		margin: 0;
		padding-left: 22px;
		display: grid;
		gap: 4px;
		max-width: 680px;
	}

	.blockers,
	.problem-box,
	.notice,
	.confirm {
		max-width: 680px;
		border-radius: 10px;
		padding: 12px 14px;
		margin-top: 14px;
	}

	.blockers,
	.problem-box {
		background: var(--warm-soft);
		border-left: 4px solid var(--warm);
	}

	.blockers ul {
		margin: 6px 0 0;
		padding-left: 20px;
	}

	/* Kinfold's own pending step: set apart from the member's to-dos. */
	.blockers ul.kinfold {
		margin-top: 10px;
		padding: 8px 12px 8px 30px;
		background: var(--surface);
		border-radius: 8px;
		color: var(--muted);
	}

	.switch-note {
		margin: 10px 0 8px;
		font-size: 15px;
	}

	.ask {
		max-width: 680px;
		margin-top: 12px;
		display: grid;
		gap: 6px;
	}

	.notice {
		background: var(--accent-soft);
		border-left: 4px solid var(--accent);
		font-weight: 600;
		margin-top: 20px;
	}

	.confirm {
		background: var(--surface-2);
		display: grid;
		gap: 6px;
	}

	.actions {
		display: flex;
		flex-wrap: wrap;
		gap: 10px;
		margin-top: 16px;
	}

	.btn {
		min-height: 44px;
	}

	.btn[aria-disabled='true'] {
		opacity: 0.6;
		cursor: not-allowed;
	}

	.score-line {
		display: flex;
		align-items: center;
		gap: 10px;
	}

	.score-num {
		font-size: 30px;
		font-weight: 800;
		color: var(--text);
		line-height: 1;
	}

	/* Status in words, so the colour is never the only signal. Warm only below the minimum. */
	.band {
		padding-left: 10px;
		border-left: 4px solid var(--border);
	}

	.band.needs {
		border-left-color: var(--warm);
	}

	.band.needs strong {
		color: var(--warm);
	}

	.band-range {
		color: var(--muted);
	}

	.band-detail {
		display: block;
		font-size: 15px;
	}

	.why {
		font-weight: 600;
		font-size: 15px;
	}

	.reasons {
		margin: 0;
		padding-left: 20px;
	}

	.fine {
		color: var(--muted);
		font-size: 14px;
		margin-top: 10px;
	}

	.list {
		list-style: none;
		margin: 0;
		padding: 0;
	}

	blockquote {
		margin: 0;
		padding-left: 12px;
		border-left: 3px solid var(--border);
		overflow-wrap: anywhere;
		white-space: pre-line;
	}

	blockquote.summary {
		font-size: 17px;
		border-left-color: var(--accent);
	}

	.two {
		display: grid;
		gap: 12px;
		grid-template-columns: repeat(auto-fit, minmax(min(100%, 18rem), 1fr));
	}

	.two .small-h {
		margin-top: 0;
	}

	.desc {
		white-space: pre-line;
		overflow-wrap: anywhere;
	}

	.private-title {
		overflow-wrap: anywhere;
	}

	.ok {
		padding-left: 10px;
		border-left: 4px solid var(--accent);
		font-size: 15px;
	}

	.history {
		list-style: none;
		margin: 12px 0 0;
		padding: 0;
		display: grid;
		gap: 6px;
		font-size: 15px;
	}

	.when {
		display: inline-block;
		min-width: 8.5em;
		color: var(--muted);
	}

	@media (max-width: 400px) {
		.when {
			display: block;
			min-width: 0;
		}
	}

	.loading {
		display: grid;
		gap: 14px;
	}

	@media (max-width: 400px) {
		.panel {
			padding: 14px;
		}
	}
</style>
