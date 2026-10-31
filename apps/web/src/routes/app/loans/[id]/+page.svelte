<script lang="ts">
	import { tick } from 'svelte';
	import { invalidate } from '$app/navigation';
	import { formatCents, formatDay, localToday } from '#lib/dashboard/format.ts';
	import { defaultPlanText, loanStatusText, type DefaultPlan } from '#lib/dashboard/labels.ts';
	import { summarizeLoan } from '#lib/dashboard/loans.ts';
	import type { LoanDetail } from '#lib/loans/data.ts';
	import {
		forgivenInYear,
		formatBps,
		installmentState,
		installmentText,
		loanActions,
		pauseMonthsLeft,
		pauseMonthsUsed,
		sideOf,
		signatures
	} from '#lib/loans/loan.ts';
	import { monthsWord, ordinal } from '#lib/loans/words.ts';
	import Badge from '../Badge.svelte';
	import ForgiveForm from './ForgiveForm.svelte';
	import PauseForm from './PauseForm.svelte';
	import ResumePanel from './ResumePanel.svelte';
	import ScheduleForm from './ScheduleForm.svelte';
	import SignPanel from './SignPanel.svelte';
	import TermsForm from './TermsForm.svelte';

	let { data } = $props();

	const today = localToday();

	// Keep showing the loan while it reloads after an action, so the page
	// doesn't flash back to a skeleton and lose the reader's place.
	let detail = $state<LoanDetail | null | undefined>(undefined);
	let failed = $state(false);
	let retrying = $state(false);
	$effect(() => {
		let live = true;
		data.detail.then(
			(d) => {
				if (!live) return;
				detail = d;
				failed = false;
			},
			() => {
				if (live) failed = true;
			}
		);
		return () => {
			live = false;
		};
	});

	let notice = $state('');
	let noticeEl = $state<HTMLElement>();

	async function refresh() {
		await invalidate('app:loan');
		// Wait for the reload itself, so the confirmation lands on fresh figures.
		try {
			detail = await data.detail;
			failed = false;
		} catch {
			failed = true;
		}
	}

	async function changed(message: string) {
		await refresh();
		notice = message;
		await tick();
		noticeEl?.focus();
	}

	async function retry() {
		retrying = true;
		try {
			await refresh();
		} finally {
			retrying = false;
		}
	}

	const view = $derived.by(() => {
		if (!detail) return null;
		const { loan, installments, pauses, forgiveness, missed } = detail;
		const side = sideOf(loan, data.uid);
		const summary = summarizeLoan(loan, data.uid, { installments, pauses, forgiveness, missed }, today);
		const missedSeqs = new Set(missed.map((m) => m.seq));
		const used = pauseMonthsUsed(pauses, today);
		const left = pauseMonthsLeft(loan.pause_months_per_year, used);
		const scheduled = installments.reduce((a, i) => a + i.amount_cents, 0);
		const signed = signatures(loan, side);
		const actions = loanActions({
			status: loan.status,
			side,
			youSigned: signed.you !== null,
			scheduleMatchesPrincipal: scheduled === loan.principal_cents,
			pauseMonthsLeft: left,
			outstandingCents: summary.remainingCents
		});
		return {
			...detail,
			side,
			summary,
			missedSeqs,
			used,
			left,
			scheduled,
			signed,
			actions,
			status: loanStatusText(loan.status)
		};
	});

	const taxYear = Number(today.slice(0, 4));

	const planDetail: Record<DefaultPlan, string> = {
		forgive: 'Whatever is left becomes a gift from the lender, recorded for that tax year. Nothing more is owed.',
		repay_on_sale:
			'The lien stays on the home and what’s left is repaid when it’s sold or refinanced. Nobody forces a sale.',
		mediate: 'A neutral mediator helps you both agree what happens next. Nothing is decided for you.'
	};
</script>

<svelte:head>
	<title>Loan · Kinfold</title>
</svelte:head>

<p class="back"><a href="/app/loans"><span aria-hidden="true">←</span> All your loans</a></p>

{#if failed && !detail}
	<div class="box error" role="alert">
		<h1>We couldn’t load this loan</h1>
		<p>Check your connection and try again. Nothing on the loan has changed.</p>
		<button type="button" class="btn btn-primary" onclick={retry} disabled={retrying}>
			{retrying ? 'Trying again…' : 'Try again'}
		</button>
	</div>
{:else if detail === undefined}
	<div role="status" class="loading">
		<span class="visually-hidden">Loading the loan…</span>
		<div class="skeleton tall" aria-hidden="true"></div>
		<div class="skeleton" aria-hidden="true"></div>
	</div>
{:else if detail === null || !view}
	<div class="box">
		<h1>Loan not found</h1>
		<p>
			This loan doesn’t exist, or it’s between other people. Only the borrower and the lender can see a loan.
		</p>
		<p><a href="/app/loans">Go to your loans</a></p>
	</div>
{:else}
	{@const l = view.loan}
	{@const s = view.summary}
	<header class="page-head">
		<p class="eyebrow">{view.side === 'borrower' ? 'Money you borrowed' : 'Money you lent'}</p>
		<div class="title-row">
			<h1>
				{#if view.side === 'borrower'}
					You borrowed {formatCents(l.principal_cents)}{view.lenderRelationship
						? ` from your ${view.lenderRelationship}`
						: ''}
				{:else}
					You lent {formatCents(l.principal_cents)}
				{/if}
			</h1>
			<Badge tone={view.status.tone} label={view.status.label} />
		</div>
		{#if view.requestTitle}<p class="meta">Toward “{view.requestTitle}”</p>{/if}
		<p class="lead">{view.status.hint}</p>
	</header>

	{#if notice}
		<p class="notice" role="status" tabindex="-1" bind:this={noticeEl}>{notice}</p>
	{/if}
	{#if failed}
		<p class="notice warn" role="alert">
			We couldn’t refresh the loan, so what’s shown may be out of date.
			<button type="button" class="link" onclick={retry} disabled={retrying}>Try again</button>
		</p>
	{/if}

	<dl class="facts box">
		<div>
			<dt>{view.side === 'borrower' ? 'Left to repay' : 'Still to come back to you'}</dt>
			<dd><strong>{formatCents(s.remainingCents)}</strong> of {formatCents(l.principal_cents)}</dd>
		</div>
		{#if s.next}
			<div>
				<dt>{s.installmentsPaid === 0 ? 'First payment' : 'Next payment'}</dt>
				<dd>
					<strong>{formatCents(s.next.owedCents)}</strong> on {formatDay(s.next.dueOn)}
					<span class="sub">Payment {s.next.seq} of {s.installmentCount}</span>
				</dd>
			</div>
		{/if}
		<div>
			<dt>Repaid so far</dt>
			<dd>{formatCents(s.paidCents)}</dd>
		</div>
		{#if s.forgivenCents > 0}
			<div>
				<dt>Forgiven as a gift</dt>
				<dd>{formatCents(s.forgivenCents)}</dd>
			</div>
		{/if}
		{#if s.behindCents > 0}
			<div>
				<dt>Behind</dt>
				<dd>
					<strong>{formatCents(s.behindCents)}</strong>
					<span class="sub">No fee, ever. {view.side === 'borrower' ? 'A pause or a new schedule can help.' : 'A gentle word or a pause may help.'}</span>
				</dd>
			</div>
		{/if}
		{#if s.pausedUntil}
			<div>
				<dt>Paused until</dt>
				<dd>{formatDay(s.pausedUntil)}</dd>
			</div>
		{/if}
	</dl>

	<section class="block" aria-labelledby="agreement-h">
		<h2 id="agreement-h">The agreement, in plain words</h2>
		<dl class="terms-list box">
			<div>
				<dt>Amount lent</dt>
				<dd>{formatCents(l.principal_cents)}{l.request_id ? ', paid straight to the payee of the request, not to the borrower' : ''}.</dd>
			</div>
			<div>
				<dt>Interest and fees</dt>
				<dd>
					<strong>None.</strong> 0% interest and no late fees, ever. The borrower repays exactly
					{formatCents(l.principal_cents)} and not a cent more, and can repay early at any time.
				</dd>
			</div>
			<div>
				<dt>Payments</dt>
				<dd>
					{#if view.installments.length > 0}
						{view.installments.length} monthly payment{view.installments.length === 1 ? '' : 's'} on the
						{ordinal(l.payment_day)}, collected by the payment partner. Kinfold never holds the money.
					{:else}
						On the {ordinal(l.payment_day)} of each month. No schedule has been set yet.
					{/if}
				</dd>
			</div>
			<div>
				<dt>Pauses</dt>
				<dd>
					{#if l.pause_months_per_year === 0}
						No pauses without asking.
					{:else}
						The borrower can pause up to {monthsWord(l.pause_months_per_year)} in any 12 without asking. A pause
						moves the payments still to come later; it never changes the total owed.
					{/if}
				</dd>
			</div>
			<div>
				<dt>If repayments stop for good</dt>
				<dd>
					{#if l.status === 'defaulted' && l.defaulted_at}
						Repayments stopped on {formatDay(l.defaulted_at)}, and the plan you agreed applied:
						{defaultPlanText(l.default_plan)}.
					{:else}
						Agreed {l.status === 'proposed' ? 'when you sign' : 'at signing'}: {defaultPlanText(l.default_plan)}.
					{/if}
					<span class="sub">{planDetail[l.default_plan]}</span>
					<span class="sub">
						Neither of you triggers this in the app. A missed payment starts a conversation (a reminder and an
						offer to pause), not a default; Kinfold’s loan servicing applies the plan only if repayments stop for
						good.
					</span>
				</dd>
			</div>
			{#if l.secured}
				<div>
					<dt>Security</dt>
					<dd>
						Secured by a lien on the home.
						{l.lien_recorded_at
							? `Recorded with the county on ${formatDay(l.lien_recorded_at)}.`
							: 'Not recorded with the county yet.'}
					</dd>
				</div>
			{/if}
			{#if l.imputed_rate_bps !== null}
				<div>
					<dt>IRS minimum rate (tax paperwork only)</dt>
					<dd>
						{#if l.imputed_rate_bps > 0}
							US tax law treats a family loan over $10,000 at no interest as if it charged the IRS minimum rate,
							here {formatBps(l.imputed_rate_bps)} a year. Kinfold calculates it only for the paperwork, where the
							interest not charged is recorded as a gift from the lender. <strong>Nobody pays it.</strong> The
							loan stays at 0%.
						{:else}
							Kinfold checked the IRS minimum-rate rule for this loan, and nothing needs reporting. The loan is
							0% interest either way.
						{/if}
					</dd>
				</div>
			{/if}
			<div>
				<dt>Signatures</dt>
				<dd>
					{l.borrower_signed_at ? `Borrower signed ${formatDay(l.borrower_signed_at)}` : 'Borrower: not signed yet'}.
					{l.lender_signed_at ? `Lender signed ${formatDay(l.lender_signed_at)}` : 'Lender: not signed yet'}.
				</dd>
			</div>
		</dl>
	</section>

	{#if view.actions.length > 0}
		<section class="block" aria-labelledby="actions-h">
			<h2 id="actions-h">{l.status === 'proposed' ? 'Agree the loan' : 'What you can do'}</h2>
			<div class="panels">
				{#if view.actions.includes('set_terms')}
					<TermsForm
						loan={l}
						installments={view.installments}
						anySigned={!!(l.borrower_signed_at || l.lender_signed_at)}
						onchanged={changed}
					/>
				{/if}
				{#if view.actions.includes('set_schedule')}
					<ScheduleForm
						loan={l}
						hasSchedule={view.installments.length > 0}
						anySigned={!!(l.borrower_signed_at || l.lender_signed_at)}
						{today}
						onchanged={changed}
					/>
				{/if}
				{#if l.status === 'proposed'}
					<SignPanel
						loan={l}
						side={view.side}
						signed={view.signed}
						installments={view.installments}
						scheduleMatches={view.scheduled === l.principal_cents}
						onchanged={changed}
					/>
				{/if}
				{#if view.actions.includes('resume')}
					<ResumePanel loanId={l.id} pausedUntil={s.pausedUntil} next={s.next} onchanged={changed} />
				{/if}
				{#if view.actions.includes('pause')}
					<PauseForm
						loan={l}
						installments={view.installments}
						used={view.used}
						left={view.left}
						{today}
						onchanged={changed}
					/>
				{/if}
				{#if view.actions.includes('forgive')}
					<ForgiveForm
						loan={l}
						outstandingCents={s.remainingCents}
						forgivenThisYearCents={forgivenInYear(view.forgiveness, taxYear)}
						{taxYear}
						onchanged={changed}
					/>
				{/if}
			</div>
		</section>
	{:else if l.status === 'signed'}
		<p class="aside box">
			You’ve both signed. Nothing can be paused or forgiven until repayments start, which happens once the
			request is paid and the money has reached the payee.
		</p>
	{:else if view.side === 'borrower' && (l.status === 'active' || l.status === 'paused') && view.left === 0}
		<p class="aside box">
			This year’s pause months are used up. If you need more time, talk to your lender about a new schedule.
		</p>
	{/if}

	<section class="block" aria-labelledby="schedule-h">
		<h2 id="schedule-h">Schedule</h2>
		{#if view.installments.length === 0}
			<p class="box empty">
				No schedule yet. {l.status === 'proposed' ? 'Set one above: it has to add up to exactly the amount lent before you sign.' : ''}
			</p>
		{:else}
			<div class="box table-wrap">
				<table>
					<caption>
						{view.installments.length} payment{view.installments.length === 1 ? '' : 's'} adding up to
						{formatCents(view.scheduled)}{view.scheduled === l.principal_cents ? ', exactly the amount lent' : ''}
					</caption>
					<thead>
						<tr>
							<th scope="col">No.</th>
							<th scope="col">Due</th>
							<th scope="col">Amount</th>
							<th scope="col">Status</th>
						</tr>
					</thead>
					<tbody>
						{#each view.installments as i (i.seq)}
							{@const st = installmentText(installmentState(i, l.status, view.missedSeqs.has(i.seq), today))}
							<tr>
								<td>{i.seq}</td>
								<td>{formatDay(i.due_on)}</td>
								<td>
									{formatCents(i.amount_cents)}
									{#if i.paid_cents > 0 && i.paid_cents < i.amount_cents}
										<span class="sub">{formatCents(i.paid_cents)} paid</span>
									{/if}
								</td>
								<td><Badge tone={st.tone} label={st.label} /></td>
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
			<p class="fine">
				“Missed” means more than 10 days late. It’s never charged for. “Due” is today or past, within those 10
				days.
			</p>
			{#if s.forgivenCents > 0 && s.remainingCents > 0}
				<p class="fine">
					{formatCents(s.forgivenCents)} has been forgiven, so {formatCents(s.remainingCents)} is left to repay in
					total, not the {formatCents(view.scheduled - s.paidCents)} the payments still listed add up to.
				</p>
			{/if}
		{/if}
	</section>

	{#if view.pauses.length > 0}
		<section class="block" aria-labelledby="pauses-h">
			<h2 id="pauses-h">Pauses</h2>
			<ul class="history box">
				{#each view.pauses as p (p.id)}
					<li>
						<strong>{monthsWord(p.months)}</strong> from {formatDay(p.started_on)}
						{#if p.reason}<span class="sub">Note: {p.reason}</span>{/if}
					</li>
				{/each}
			</ul>
		</section>
	{/if}

	{#if view.forgiveness.length > 0}
		<section class="block" aria-labelledby="forgiven-h">
			<h2 id="forgiven-h">Forgiven as gifts</h2>
			<ul class="history box">
				{#each view.forgiveness as f (f.id)}
					<li>
						<strong>{formatCents(f.amount_cents)}</strong> on {formatDay(f.created_at)}
						<span class="sub">A gift for tax year {f.tax_year}, recorded for the gift letter.</span>
					</li>
				{/each}
			</ul>
		</section>
	{/if}
{/if}

<style>
	.back {
		margin-bottom: 16px;
		font-size: 15px;
	}

	.page-head {
		margin-bottom: 20px;
	}

	.title-row {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 8px 16px;
	}

	h1 {
		font-size: clamp(26px, 5vw, 36px);
		overflow-wrap: anywhere;
	}

	.meta {
		color: var(--muted);
		margin-top: 6px;
		overflow-wrap: anywhere;
	}

	.lead {
		margin-top: 8px;
		max-width: 640px;
	}

	.block {
		margin-top: 32px;
	}

	.block h2 {
		font-size: 22px;
		margin-bottom: 12px;
	}

	.box {
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius);
		padding: 18px 20px;
	}

	.error,
	.box:has(> h1) {
		display: grid;
		gap: 10px;
		justify-items: start;
	}

	.empty {
		color: var(--muted);
		border-style: dashed;
	}

	.notice {
		margin: 0 0 16px;
		padding: 12px 16px;
		border-radius: 10px;
		background: var(--accent-soft);
		border-left: 4px solid var(--accent);
		font-weight: 600;
	}

	.notice.warn {
		background: var(--warm-soft);
		border-left-color: var(--warm);
		font-weight: 400;
	}

	.link {
		font: inherit;
		background: none;
		border: 0;
		padding: 0;
		color: var(--accent);
		text-decoration: underline;
		cursor: pointer;
	}

	.facts {
		margin: 0;
		display: grid;
		gap: 12px 24px;
		grid-template-columns: repeat(auto-fit, minmax(min(100%, 13rem), 1fr));
	}

	.facts dt,
	.terms-list dt {
		color: var(--muted);
		font-size: 13px;
		font-weight: 700;
		letter-spacing: 0.04em;
		text-transform: uppercase;
	}

	.facts dd,
	.terms-list dd {
		margin: 2px 0 0;
		font-size: 15px;
	}

	.terms-list {
		margin: 0;
		display: grid;
		gap: 14px;
	}

	.sub {
		display: block;
		color: var(--muted);
		font-size: 14px;
		margin-top: 2px;
	}

	.panels {
		display: grid;
		gap: 14px;
		grid-template-columns: repeat(auto-fit, minmax(min(100%, 22rem), 1fr));
		align-items: start;
	}

	.aside {
		margin-top: 24px;
		font-size: 15px;
	}

	.table-wrap {
		padding: 8px 12px;
		overflow-x: auto;
	}

	table {
		width: 100%;
		border-collapse: collapse;
		font-size: 15px;
	}

	caption {
		text-align: left;
		color: var(--muted);
		font-size: 14px;
		padding: 8px 4px;
	}

	th,
	td {
		text-align: left;
		padding: 8px 4px;
		border-top: 1px solid var(--border);
		vertical-align: top;
	}

	th {
		font-size: 13px;
		color: var(--muted);
		font-weight: 700;
	}

	td:first-child,
	th:first-child {
		width: 2.5em;
	}

	.fine {
		color: var(--muted);
		font-size: 14px;
		margin-top: 10px;
	}

	.history {
		list-style: none;
		margin: 0;
		display: grid;
		gap: 10px;
	}

	.history li {
		overflow-wrap: anywhere;
	}

	.loading {
		display: grid;
		gap: 14px;
	}

	.skeleton {
		height: 120px;
		border-radius: var(--radius);
		background: var(--surface-2);
	}

	.skeleton.tall {
		height: 200px;
	}

	.visually-hidden {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip-path: inset(50%);
		white-space: nowrap;
	}

	@media (max-width: 380px) {
		.box {
			padding: 14px;
		}

		th,
		td {
			padding: 8px 2px;
		}
	}
</style>
