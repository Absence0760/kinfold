<script lang="ts">
	import { goto, invalidate } from '$app/navigation';
	import { page } from '$app/state';
	import { loadProblem } from '#lib/auth/errors.ts';
	import { signinUrl } from '#lib/auth/next.ts';
	import { clearLocalSession } from '#lib/auth/session.ts';
	import { formatCents, formatDay } from '#lib/dashboard/format.ts';
	import {
		defaultPlanText,
		fundingLabel,
		loanStatusText,
		requestKindLabel,
		requestStatusText,
		type Tone
	} from '#lib/dashboard/labels.ts';
	import { greeting } from '#lib/dashboard/home.ts';
	import { showsRaised } from '#lib/dashboard/requests.ts';
	import { scoreBand } from '#lib/requests/score-band.ts';

	let { data } = $props();

	const member = $derived(data.viewer.member);
	let retrying = $state(false);
	let leaving = $state(false);
	let heading = $state<HTMLElement>();

	async function retry() {
		if (retrying) return;
		retrying = true;
		try {
			await invalidate('app:home');
		} finally {
			retrying = false;
			// The error block (and the button that had focus) is replaced; park focus on the page heading.
			heading?.focus();
		}
	}

	// The server rejected the session: retrying would fail the same way, so
	// drop it on this device and sign in again, coming back here after.
	async function signInAgain() {
		if (leaving) return;
		leaving = true;
		try {
			await clearLocalSession();
			await goto(signinUrl(page.url));
		} finally {
			leaving = false;
		}
	}

	// A member with no profile sees the setup note instead of the home, so the
	// home's reads (which RLS answers with nothing) have no reader; mark them
	// handled rather than leave an unhandled rejection in the console.
	$effect(() => {
		if (!member) data.home.catch(() => {});
	});

	const pct = (part: number, whole: number) => (whole > 0 ? Math.min(100, Math.round((part / whole) * 100)) : 0);
	const months = (n: number) => `${n} month${n === 1 ? '' : 's'}`;
</script>

<svelte:head>
	<title>Your home · Kinfold</title>
</svelte:head>

{#snippet badge(tone: Tone, label: string)}
	<span class="badge {tone}">
		<svg viewBox="0 0 12 12" width="12" height="12" aria-hidden="true">
			{#if tone === 'action'}
				<path d="M6 1 11 10H1z" />
			{:else if tone === 'progress'}
				<circle cx="6" cy="6" r="4.5" fill="none" stroke-width="2" />
			{:else if tone === 'done'}
				<path d="M2 6.5 5 9.5 10 3" fill="none" stroke-width="2" />
			{:else}
				<rect x="2" y="5" width="8" height="2" />
			{/if}
		</svg>
		{label}
	</span>
{/snippet}

<header class="page-head">
	<p class="eyebrow">Your home</p>
	<h1 bind:this={heading} tabindex="-1">{greeting(member?.display_name)}</h1>
	<p class="lead">Your requests, the loans you’ve taken or given, and your private giving record.</p>
</header>

{#if !member}
	<!-- Signed in, but no members row. Creating one in the app is a pending
	     product decision, so say what's missing and who can fix it, with no
	     link that would lead back here. -->
	<section class="setup" aria-labelledby="setup-h">
		<h2 id="setup-h">Your member profile isn’t set up yet</h2>
		<p>
			You’re signed in, but this account doesn’t have a Kinfold member profile yet, so asking for
			help, lending and the members’ board aren’t open to you. A profile can’t be created from this
			page yet.
		</p>
		<p>
			Membership is by invitation for now. Ask the member who invited you to contact the Kinfold
			team, who will finish setting up your profile. Then sign in again.
		</p>
	</section>
{:else}
{#await data.home}
	<div class="loading" role="status" aria-busy="true">
		<span class="visually-hidden">Loading your home…</span>
		{#each [1, 2, 3] as i (i)}
			<div class="skeleton" aria-hidden="true"></div>
		{/each}
	</div>
{:then home}
	<section class="block" aria-labelledby="requests-h">
		<div class="block-head split">
			<h2 id="requests-h">Your requests</h2>
			<a class="btn btn-primary" href="/app/requests/new">Ask for help</a>
		</div>
		{#if home.requests.length === 0}
			<div class="empty">
				<p><strong>You haven’t asked for help yet.</strong></p>
				<p>
					When your car is hit or your home needs a repair, a request goes here. You’ll see its
					legitimacy score and why, how much has been raised, and when the shop or lender is paid.
				</p>
			</div>
		{:else}
			<ul class="cards">
				{#each home.requests as r (r.id)}
					{@const st = requestStatusText(r.status, r.kind, r.funding)}
					<li>
						<article class="card" aria-labelledby="req-{r.id}">
							<div class="card-head">
								<h3 id="req-{r.id}"><a href="/app/requests/{r.id}">{r.title}</a></h3>
								{@render badge(st.tone, st.label)}
							</div>
							<p class="meta">
								{requestKindLabel(r.kind)} · {fundingLabel(r.funding, r.kind)} · asked for
								<strong>{formatCents(r.amount_cents)}</strong>
							</p>
							<p class="hint">{st.hint}</p>

							{#if showsRaised(r)}
								<div class="raised">
									<p>
										Raised <strong>{formatCents(r.raisedCents)}</strong> of {formatCents(r.amount_cents)}
									</p>
									<div class="bar" aria-hidden="true">
										<span style:width="{pct(r.raisedCents, r.amount_cents)}%"></span>
									</div>
								</div>
							{/if}

							{#if r.score}
								<!-- Home doesn't read reviews, so the line follows the status alone, never today's minimum. -->
								{@const band = scoreBand(r.score.score, { status: r.status, minScore: null })}
								<section class="score" aria-label="Legitimacy score">
									<p class="score-line">
										<span class="score-num">{r.score.score}</span>
										<span>
											<strong>Legitimacy score</strong> out of 100
											<span class="sub">How well the evidence backs the request</span>
										</span>
									</p>
									{#if band}
										<p class="band" class:needs={band.tone === 'needs-evidence'}>
											<strong>{band.status}</strong> <span class="band-range">(band {band.label})</span>
											<span class="band-detail">{band.detail}</span>
										</p>
									{/if}
									{#if r.score.reasons.length}
										<p class="why">Why this score:</p>
										<ul class="reasons">
											{#each r.score.reasons as reason, i (i)}
												<li>{reason}</li>
											{/each}
										</ul>
									{:else}
										<p class="why">No reasons were recorded with this score.</p>
									{/if}
									<p class="fine">
										A score measures the evidence, not you. A low score sends a request to a person; it never
										refuses one on its own. Scored {formatDay(r.score.scoredAt)} by {r.score.model}
										{r.score.modelVersion}.
									</p>
								</section>
							{:else if r.status === 'scoring'}
								<p class="fine">Your legitimacy score and its reasons will show here.</p>
							{/if}
						</article>
					</li>
				{/each}
			</ul>
		{/if}
	</section>

	<section class="block" aria-labelledby="loans-h">
		<h2 id="loans-h">Loans</h2>
		<p class="section-note">Zero interest, no late fees. Missed payments start a conversation, never a charge.</p>
		{#if home.loans.length === 0}
			<div class="empty">
				<p><strong>No loans yet.</strong></p>
				<p>
					When family or friends lend toward one of your requests, or you lend toward theirs, the
					schedule and the next installment show here, for both of you.
				</p>
				<div class="next">
					<a class="btn btn-primary" href="/app/requests/new">Ask for help</a>
					<a class="btn btn-ghost" href="/app/invite">Invite someone</a>
				</div>
			</div>
		{:else}
			<ul class="cards">
				{#each home.loans as l (l.loan.id)}
					{@const st = loanStatusText(l.loan.status)}
					<li>
						<article class="card" aria-labelledby="loan-{l.loan.id}">
							<div class="card-head">
								<h3 id="loan-{l.loan.id}">
									<a href="/app/loans/{l.loan.id}">
									{#if l.role === 'borrower'}
										You borrowed {formatCents(l.loan.principal_cents)}{l.lenderRelationship
											? ` from your ${l.lenderRelationship}`
											: ''}
									{:else}
										You lent {formatCents(l.loan.principal_cents)}
									{/if}
									</a>
								</h3>
								{@render badge(st.tone, st.label)}
							</div>
							{#if l.requestTitle}
								<p class="meta">Toward “{l.requestTitle}”</p>
							{/if}
							<p class="hint">{st.hint}</p>

							{#if l.behindCents > 0}
								<p class="behind" role="note">
									<strong>Behind by {formatCents(l.behindCents)}</strong>{l.pauseMonthsLeft > 0
										? ' · pause available'
										: ' · talk to each other about a new schedule'}
								</p>
							{/if}

							<dl class="facts">
								{#if l.next}
									<div>
										<dt>{l.installmentsPaid === 0 ? 'First installment' : 'Next installment'}</dt>
										<dd>
											<strong>{formatCents(l.next.owedCents)}</strong> on {formatDay(l.next.dueOn)}
											<span class="sub">{l.next.seq} of {l.installmentCount}</span>
										</dd>
									</div>
								{/if}
								<div>
									<dt>{l.role === 'borrower' ? 'Left to repay' : 'Still to come back to you'}</dt>
									<dd>
										<strong>{formatCents(l.remainingCents)}</strong> of {formatCents(l.loan.principal_cents)}
									</dd>
								</div>
								{#if l.paidCents > 0}
									<div>
										<dt>Repaid so far</dt>
										<dd>{formatCents(l.paidCents)}</dd>
									</div>
								{/if}
								{#if l.forgivenCents > 0}
									<div>
										<dt>Forgiven as a gift</dt>
										<dd>{formatCents(l.forgivenCents)}</dd>
									</div>
								{/if}
								<div>
									<dt>Pauses</dt>
									<dd>
										{#if l.pausedUntil}
											Paused until {formatDay(l.pausedUntil)}.
										{/if}
										{months(l.pauseMonthsLeft)} of {months(l.loan.pause_months_per_year)} left this year
									</dd>
								</div>
								<div>
									<dt>If repayments stop</dt>
									<dd>Agreed at signing: {defaultPlanText(l.loan.default_plan)}.</dd>
								</div>
							</dl>
						</article>
					</li>
				{/each}
			</ul>
		{/if}
	</section>

	<section class="block" aria-labelledby="giving-h">
		<div class="block-head">
			<h2 id="giving-h">Your giving record</h2>
			<span class="private">
				<svg viewBox="0 0 12 12" width="12" height="12" aria-hidden="true">
					<rect x="2" y="5.5" width="8" height="5.5" rx="1" />
					<path d="M4 5.5V4a2 2 0 0 1 4 0v1.5" fill="none" stroke-width="1.5" />
				</svg>
				Only you can see this
			</span>
		</div>
		<p class="section-note">
			What you’ve put in and what you’ve received. It never ranks, slows or refuses anyone’s request,
			yours included, and reviewers never see it.
		</p>
		{#if home.giving.empty}
			<div class="empty">
				<p><strong>Nothing here yet.</strong></p>
				<p>
					Your monthly membership dues (a small share of what you earn, nothing below a floor, which
					pays for the group car cover), the gifts and loans you give, and any help you receive add up
					here once the payment partner has collected the money.
				</p>
				<div class="next">
					<a class="btn btn-ghost" href="/app/invite">Invite someone</a>
				</div>
			</div>
		{:else}
			<div class="ledger">
				<div class="side">
					<h3>You’ve put in <strong>{formatCents(home.giving.givenCents)}</strong></h3>
					<dl>
						{#each home.giving.given as line (line.label)}
							<div><dt>{line.label}</dt><dd>{formatCents(line.cents)}</dd></div>
						{/each}
					</dl>
				</div>
				<div class="side">
					<h3>You’ve received <strong>{formatCents(home.giving.receivedCents)}</strong></h3>
					<dl>
						{#each home.giving.received as line (line.label)}
							<div><dt>{line.label}</dt><dd>{formatCents(line.cents)}</dd></div>
						{/each}
					</dl>
				</div>
			</div>
			{#if home.giving.pledgedGiftCents + home.giving.pledgedLoanCents > 0}
				<p class="fine">
					Pledged and not collected yet:
					{[
						home.giving.pledgedGiftCents ? `${formatCents(home.giving.pledgedGiftCents)} as gifts` : '',
						home.giving.pledgedLoanCents ? `${formatCents(home.giving.pledgedLoanCents)} as loans` : ''
					]
						.filter(Boolean)
						.join(' and ')}. It counts once the payment partner collects it.
				</p>
			{/if}
		{/if}
	</section>

	{#if home.reliability}
		{@const rel = home.reliability}
		<section class="block" aria-labelledby="reliability-h">
			<h2 id="reliability-h">Your reliability record</h2>
			<p class="section-note">
				Kinfold’s replacement for a credit score: the payments you’ve kept up with.
			</p>
			<dl class="facts wide">
				<div>
					<dt>Member since</dt>
					<dd>{formatDay(rel.member_since)}</dd>
				</div>
				<div>
					<dt>Monthly dues paid</dt>
					<dd>{months(rel.subscription_payments)}</dd>
				</div>
				<div>
					<dt>Loan installments</dt>
					<dd>
						{#if rel.installments_due === 0}
							None due yet
						{:else}
							{rel.installments_paid_on_time} paid of {rel.installments_due} due so far
						{/if}
					</dd>
				</div>
				<div>
					<dt>Requests paid</dt>
					<dd>{rel.requests_paid}</dd>
				</div>
			</dl>
		</section>
	{/if}
{:catch err}
	{@const problem = loadProblem(err, 'your home')}
	<div class="error" role="alert">
		<h2>{problem.title}</h2>
		<p>{problem.body}</p>
		{#if problem.detail}
			<p class="fine">What the server said: “{problem.detail}”</p>
		{/if}
		{#if problem.kind === 'session'}
			<button type="button" class="btn btn-primary" onclick={signInAgain} aria-disabled={leaving}>
				{leaving ? 'Signing out…' : 'Sign in again'}
			</button>
		{:else}
			<button type="button" class="btn btn-primary" onclick={retry} aria-disabled={retrying}>
				{retrying ? 'Trying again…' : 'Try again'}
			</button>
		{/if}
	</div>
{/await}
{/if}

<style>
	.page-head {
		margin-bottom: 32px;
	}

	h1 {
		font-size: clamp(28px, 5vw, 38px);
		overflow-wrap: anywhere;
	}

	h1:focus {
		outline: none;
	}

	.lead {
		color: var(--muted);
		margin-top: 8px;
		max-width: 620px;
	}

	.block {
		margin-top: 40px;
	}

	.block h2 {
		font-size: 22px;
	}

	.block-head {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 8px 12px;
	}

	.section-note {
		color: var(--muted);
		font-size: 15px;
		margin-top: 6px;
		max-width: 680px;
	}

	.cards {
		list-style: none;
		margin: 16px 0 0;
		padding: 0;
		display: grid;
		gap: 14px;
	}

	.card,
	.empty,
	.ledger .side,
	.error,
	.setup {
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius);
		padding: 18px 20px;
	}

	.empty {
		margin-top: 16px;
		display: grid;
		gap: 6px;
		color: var(--muted);
		border-style: dashed;
	}

	.empty strong {
		color: var(--text);
	}

	.next {
		display: flex;
		flex-wrap: wrap;
		gap: 10px;
		margin-top: 8px;
	}

	.setup {
		display: grid;
		gap: 10px;
		max-width: 680px;
		border-left: 4px solid var(--warm);
	}

	.setup h2 {
		font-size: 20px;
	}

	.card-head {
		display: flex;
		flex-wrap: wrap;
		align-items: flex-start;
		justify-content: space-between;
		gap: 8px 16px;
	}

	.card h3 {
		font-size: 18px;
		flex: 1 1 14rem;
		overflow-wrap: anywhere;
	}

	.meta {
		color: var(--muted);
		font-size: 15px;
		margin-top: 6px;
	}

	.meta strong {
		color: var(--text);
		font-variant-numeric: tabular-nums;
	}

	.hint {
		font-size: 15px;
		margin-top: 6px;
	}

	.badge {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		padding: 3px 10px;
		border-radius: 999px;
		font-size: 13px;
		font-weight: 700;
		white-space: nowrap;
		border: 1px solid currentColor;
	}

	.badge svg {
		fill: currentColor;
		stroke: currentColor;
		flex: none;
	}

	/* --warm on --warm-soft is under 4.5:1 for small text, so the words stay
	   --text and only the border and icon carry the warm colour. */
	.badge.action {
		color: var(--text);
		background: var(--warm-soft);
		border-color: var(--warm);
	}

	.badge.action svg {
		fill: var(--warm);
		stroke: var(--warm);
	}

	.badge.progress {
		color: var(--accent);
		background: var(--accent-soft);
	}

	.badge.done {
		color: var(--accent-contrast);
		background: var(--accent);
		border-color: var(--accent);
	}

	.badge.closed {
		color: var(--muted);
		background: var(--surface-2);
	}

	.raised {
		margin-top: 14px;
		font-size: 15px;
	}

	.bar {
		height: 8px;
		margin-top: 6px;
		border-radius: 999px;
		background: var(--surface-2);
		overflow: hidden;
	}

	.bar span {
		display: block;
		height: 100%;
		background: var(--accent);
	}

	.score {
		margin-top: 16px;
		padding-top: 14px;
		border-top: 1px solid var(--border);
	}

	.score-line {
		display: flex;
		align-items: center;
		gap: 12px;
		font-size: 15px;
	}

	.score-num {
		font-size: 30px;
		font-weight: 800;
		color: var(--text);
		font-variant-numeric: tabular-nums;
		line-height: 1;
		min-width: 2.2ch;
	}

	.sub {
		display: block;
		color: var(--muted);
		font-size: 14px;
	}

	/* Status in words, so the colour is never the only signal. Warm only below the minimum. */
	.band {
		margin-top: 10px;
		padding-left: 10px;
		border-left: 4px solid var(--border);
		font-size: 15px;
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
		font-size: 14px;
	}

	.why {
		margin-top: 10px;
		font-weight: 600;
		font-size: 15px;
	}

	.reasons {
		margin: 4px 0 0;
		padding-left: 20px;
		font-size: 15px;
	}

	.fine {
		color: var(--muted);
		font-size: 14px;
		margin-top: 10px;
	}

	.behind {
		margin-top: 12px;
		padding: 10px 14px;
		border-radius: 10px;
		background: var(--warm-soft);
		border-left: 4px solid var(--warm);
		font-size: 15px;
	}

	.facts {
		margin: 14px 0 0;
		display: grid;
		gap: 10px 24px;
		grid-template-columns: repeat(auto-fit, minmax(min(100%, 15rem), 1fr));
	}

	.facts.wide {
		margin-top: 16px;
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius);
		padding: 18px 20px;
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
		font-variant-numeric: tabular-nums;
	}

	.private {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		font-size: 13px;
		font-weight: 700;
		color: var(--text);
		background: var(--surface-2);
		border: 1px solid var(--border);
		border-radius: 999px;
		padding: 3px 10px;
	}

	.private svg {
		fill: currentColor;
		stroke: currentColor;
	}

	.ledger {
		margin-top: 16px;
		display: grid;
		gap: 14px;
		grid-template-columns: repeat(auto-fit, minmax(min(100%, 18rem), 1fr));
	}

	.ledger h3 {
		font-size: 16px;
		font-weight: 600;
	}

	.ledger h3 strong {
		display: block;
		font-size: 26px;
		margin-top: 2px;
	}

	.ledger dl {
		margin: 12px 0 0;
		display: grid;
		gap: 6px;
	}

	.ledger dl div {
		display: flex;
		justify-content: space-between;
		gap: 12px;
		font-size: 15px;
		border-top: 1px solid var(--border);
		padding-top: 6px;
	}

	.ledger dt {
		color: var(--muted);
	}

	.ledger dd {
		margin: 0;
		font-variant-numeric: tabular-nums;
	}

	.loading {
		display: grid;
		gap: 14px;
	}

	.error {
		display: grid;
		gap: 10px;
		justify-items: start;
		border-color: var(--warm);
	}

	.error h2 {
		font-size: 20px;
	}

	.error button[aria-disabled='true'] {
		opacity: 0.7;
		cursor: progress;
		pointer-events: none;
	}

	@media (max-width: 400px) {
		.card,
		.empty,
		.ledger .side,
		.error,
		.setup,
		.facts.wide {
			padding: 14px 14px;
		}
	}

	.block-head.split {
		justify-content: space-between;
	}

	.card h3 a {
		display: inline-flex;
		align-items: center;
		min-height: 44px;
		color: inherit;
		text-decoration: underline;
		text-decoration-color: var(--border);
		text-underline-offset: 3px;
	}

	.card h3 a:hover {
		text-decoration-color: var(--accent);
	}
</style>
