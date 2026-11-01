<script lang="ts">
	import { tick } from 'svelte';
	import { parseDollars } from '#lib/board/board.ts';
	import { formatCents, formatDay } from '#lib/dashboard/format.ts';
	import { loanStatusText, payeeWord, requestKindLabel } from '#lib/dashboard/labels.ts';
	import { pledge, type SupportView } from './data.ts';
	import { explainInviteError } from './errors.ts';
	import {
		GIFT_EXCLUSION_CENTS,
		leftCents,
		pledgeAmountProblem,
		pledgeGate,
		quickAmounts,
		relationshipLabel
	} from './invites.ts';

	let {
		view,
		verified,
		headingLevel = 2,
		onpledged
	}: {
		view: SupportView;
		/** Whether the viewer is a verified (active) member: lending needs it. */
		verified: boolean;
		headingLevel?: 2 | 3;
		onpledged: (message: string) => void | Promise<void>;
	} = $props();

	const r = $derived(view.request);
	const uid = $derived(`support-${r.id}`);
	const h = $derived(`h${headingLevel}`);
	const sub = $derived(`h${headingLevel + 1}`);
	const payee = $derived(view.payeeName ?? payeeWord(r.kind));
	const left = $derived(view.raisedCents == null ? null : leftCents(r.amount_cents, view.raisedCents));
	const gate = $derived(
		left == null
			? ({ open: false, reason: 'We couldn’t load how much has been pledged, so pledging is paused. Refresh to try again.' } as const)
			: pledgeGate({ status: r.status, kind: r.kind, payeeVerified: view.payeeVerified, leftCents: left })
	);
	const livePledges = $derived(view.myPledges.filter((p) => p.status === 'pledged' || p.status === 'captured'));

	type Step = 'amount' | 'confirm' | 'sending';
	let step = $state<Step>('amount');
	let source = $state<'gift' | 'loan'>('gift');
	let typed = $state('');
	let touched = $state(false);
	let error = $state<string | null>(null);

	let confirmHeading = $state<HTMLElement>();
	let amountInput = $state<HTMLInputElement>();

	const cents = $derived(parseDollars(typed));
	const problem = $derived(left == null ? null : pledgeAmountProblem(cents, left));

	function pick(c: number) {
		typed = (c / 100).toFixed(c % 100 === 0 ? 0 : 2);
		touched = true;
	}

	async function review(e: SubmitEvent) {
		e.preventDefault();
		touched = true;
		if (problem || cents == null) return;
		if (source === 'loan' && !verified) return;
		step = 'confirm';
		error = null;
		await tick();
		confirmHeading?.focus();
	}

	async function back() {
		if (step === 'sending') return;
		step = 'amount';
		await tick();
		amountInput?.focus();
	}

	async function send() {
		// aria-disabled keeps the buttons focusable while sending, so guard here.
		if (cents == null || step === 'sending') return;
		step = 'sending';
		error = null;
		try {
			await pledge(r.id, cents, source);
			const message =
				source === 'gift'
					? `Thank you. You pledged a gift of ${formatCents(cents)}. Nothing is collected until the whole request is pledged.`
					: `Thank you. You offered to lend ${formatCents(cents)} at 0%. Next, set the monthly schedule together and both sign it on the Loans page. Nothing is collected until then.`;
			typed = '';
			touched = false;
			step = 'amount';
			await onpledged(message);
		} catch (err) {
			error = explainInviteError(err as { message?: string; code?: string });
			step = 'confirm';
			await tick();
			confirmHeading?.focus();
		}
	}
</script>

<article class="support" aria-labelledby="{uid}-heading">
	<p class="eyebrow">
		{requestKindLabel(r.kind)}{#if view.relationship}&nbsp;· you were invited as their {view.relationship}{/if}
	</p>
	<svelte:element this={h} id="{uid}-heading" class="title">{r.title}</svelte:element>
	{#if r.description}
		<p class="description">{r.description}</p>
	{/if}

	<dl class="facts">
		<div>
			<dt>Asking for</dt>
			<dd>{formatCents(r.amount_cents)}</dd>
		</div>
		<div>
			<dt>Pledged so far</dt>
			<dd>{view.raisedCents == null ? 'Not shown' : formatCents(view.raisedCents)}</dd>
		</div>
		{#if left != null && r.status === 'open'}
			<div>
				<dt>Still needed</dt>
				<dd>{formatCents(left)}</dd>
			</div>
		{/if}
		<div>
			<dt>Paid to</dt>
			<dd>{view.payeeName ?? `${payeeWord(r.kind)} (not verified yet)`}</dd>
		</div>
		<div>
			<dt>Happened on</dt>
			<dd>{formatDay(r.incident_on)}</dd>
		</div>
	</dl>

	{#if livePledges.length || view.myLoans.length}
		<div class="mine">
			<svelte:element this={sub} class="sub">What you've pledged</svelte:element>
			<ul>
				{#each livePledges as p, i (i)}
					<li>
						{p.source === 'gift' ? 'A gift of' : 'A 0% loan of'}
						{formatCents(p.amount_cents)}{p.status === 'captured' ? ', collected' : ', waiting to be collected'}
					</li>
				{/each}
			</ul>
			{#if view.myLoans.length}
				<ul>
					{#each view.myLoans as loan (loan.id)}
						<li>
							Loan of {formatCents(loan.principal_cents)}: {loanStatusText(loan.status).label}.
							{loanStatusText(loan.status).hint}
						</li>
					{/each}
				</ul>
				<p><a href="/app/loans">See your loans, set the schedule and sign</a></p>
			{/if}
			<p class="muted">Your pledges are part of your private giving record. Only you can see it.</p>
		</div>
	{/if}

	{#if !gate.open}
		<p class="note">{gate.reason}</p>
	{:else if left != null && (step === 'amount')}
		<form class="panel" onsubmit={review} novalidate>
			<fieldset>
				<legend>How would you like to help?</legend>
				<label class="option">
					<input type="radio" name="{uid}-source" value="gift" bind:group={source} />
					<span><strong>Give.</strong> A gift: it's never paid back.</span>
				</label>
				<label class="option">
					<input type="radio" name="{uid}-source" value="loan" bind:group={source} />
					<span>
						<strong>Lend at 0%.</strong> Paid back monthly with no interest and no late fees, on a
						schedule you both agree and sign.
					</span>
				</label>
			</fieldset>
			{#if source === 'loan' && !verified}
				<p class="problem" id="{uid}-needs-verify" role="alert">
					Lending needs a verified identity, so the loan papers are legally sound. You can give now,
					or finish verifying and come back to this page to lend.
				</p>
			{/if}

			<label for="{uid}-amount">How much?</label>
			<div class="quick" role="group" aria-label="Quick amounts">
				{#each quickAmounts(left) as c (c)}
					<button type="button" class="chip" onclick={() => pick(c)}>
						{c === left ? `All that's left, ${formatCents(c)}` : formatCents(c)}
					</button>
				{/each}
			</div>
			<div class="field">
				<span aria-hidden="true">$</span>
				<input
					id="{uid}-amount"
					bind:this={amountInput}
					bind:value={typed}
					onblur={() => (touched = typed !== '' || touched)}
					inputmode="decimal"
					autocomplete="off"
					aria-describedby="{uid}-hint{touched && problem ? ` ${uid}-problem` : ''}"
					aria-invalid={touched && problem ? 'true' : undefined}
				/>
			</div>
			<p class="hint" id="{uid}-hint">Up to {formatCents(left)}, what this request still needs.</p>
			{#if touched && problem}
				<p class="problem" id="{uid}-problem" role="alert">{problem}</p>
			{/if}
			<div class="actions">
				<!-- aria-disabled, not disabled: the button stays in the Tab order so its reason is read. -->
				<button
					type="submit"
					class="btn btn-primary small"
					aria-disabled={source === 'loan' && !verified}
					aria-describedby={source === 'loan' && !verified ? `${uid}-needs-verify` : undefined}
				>
					Review<span class="visually-hidden"> your help for “{r.title}”</span>
				</button>
			</div>
		</form>
	{:else if left != null && cents != null}
		<div class="panel" role="group" aria-labelledby="{uid}-confirm">
			<p class="confirm-title" id="{uid}-confirm" tabindex="-1" bind:this={confirmHeading}>
				{source === 'gift' ? `Give ${formatCents(cents)}?` : `Lend ${formatCents(cents)} at 0%?`}
			</p>
			<ul class="terms">
				<li>
					The money goes to {payee}, not to the member and not to Kinfold. The payment partner
					collects it and pays {payee} directly.
				</li>
				<li>
					Nothing is collected until the whole {formatCents(r.amount_cents)} is pledged{source === 'loan'
						? ' and every loan behind it is signed'
						: ''}. If the request closes unpaid, your pledge is released.
				</li>
				{#if source === 'gift'}
					<li>A gift is never paid back.</li>
					{#if cents > GIFT_EXCLUSION_CENTS}
						<li>
							Giving one person more than {formatCents(GIFT_EXCLUSION_CENTS)} in a year means filing a
							gift-tax return (IRS Form 709). Tax is rarely due.
						</li>
					{/if}
				{:else}
					<li>
						No interest and no late fees, ever. Next you both agree a monthly schedule, pick what
						happens if repayments stop, and sign, on the <a href="/app/loans">Loans</a> page.
					</li>
					<li>Only lend what you could manage without if it were never repaid.</li>
				{/if}
			</ul>
			{#if error}
				<p class="problem" role="alert">{error}</p>
			{/if}
			<div class="actions">
				<button
					type="button"
					class="btn btn-primary small"
					onclick={send}
					aria-disabled={step === 'sending'}
					aria-busy={step === 'sending'}
				>
					{step === 'sending' ? 'Pledging…' : source === 'gift' ? `Pledge ${formatCents(cents)}` : `Offer the loan`}<span
						class="visually-hidden"> to “{r.title}”</span
					>
				</button>
				<button type="button" class="btn btn-ghost small" onclick={back} aria-disabled={step === 'sending'}>
					Change<span class="visually-hidden"> your help for “{r.title}”</span>
				</button>
			</div>
		</div>
	{/if}
</article>

<style>
	.support {
		display: grid;
		gap: 14px;
		padding: 18px;
		border: 1px solid var(--border);
		border-radius: 12px;
		background: var(--surface);
		min-width: 0;
	}

	.eyebrow {
		margin: 0;
	}

	.title {
		font-size: 22px;
		overflow-wrap: anywhere;
	}

	.sub {
		font-size: 16px;
	}

	.description {
		white-space: pre-line;
		overflow-wrap: anywhere;
	}

	.facts {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
		gap: 10px 16px;
		margin: 0;
	}

	.facts dt {
		font-size: 13px;
		color: var(--muted);
	}

	.facts dd {
		margin: 0;
		font-weight: 600;
		overflow-wrap: anywhere;
	}

	.mine {
		display: grid;
		gap: 6px;
	}

	.mine ul {
		margin: 0;
		padding-left: 18px;
	}

	.muted,
	.hint,
	.note {
		color: var(--muted);
	}

	.note {
		padding: 12px 14px;
		border-radius: 10px;
		background: var(--surface-2);
		color: var(--text);
	}

	.hint {
		font-size: 13px;
	}

	.panel {
		display: grid;
		gap: 10px;
		padding: 14px;
		border-radius: 10px;
		background: var(--surface-2);
	}

	fieldset {
		border: 0;
		margin: 0;
		padding: 0;
		display: grid;
		gap: 8px;
	}

	legend,
	label[for],
	.confirm-title {
		font-weight: 600;
	}

	legend {
		margin-bottom: 4px;
	}

	.option {
		display: flex;
		gap: 10px;
		align-items: flex-start;
		padding: 12px;
		min-height: 44px;
		border: 1px solid var(--border);
		border-radius: 8px;
		background: var(--surface);
		cursor: pointer;
	}

	.option input {
		margin-top: 2px;
		flex: none;
		width: 20px;
		height: 20px;
		accent-color: var(--accent);
	}

	.option:focus-within {
		outline: 3px solid var(--warm);
		outline-offset: 2px;
	}

	.quick {
		display: flex;
		flex-wrap: wrap;
		gap: 8px;
	}

	.chip {
		font: inherit;
		font-size: 14px;
		padding: 6px 14px;
		min-height: 44px;
		border-radius: 999px;
		border: 1px solid var(--border);
		background: var(--surface);
		color: var(--text);
		cursor: pointer;
	}

	.field {
		display: flex;
		align-items: center;
		gap: 6px;
		max-width: 220px;
		background: var(--surface);
		border: 1px solid var(--field-border);
		border-radius: 8px;
		padding: 0 10px;
	}

	.field input {
		font: inherit;
		border: 0;
		background: transparent;
		color: var(--text);
		padding: 8px 0;
		min-height: 42px;
		width: 100%;
		min-width: 0;
	}

	.field:focus-within {
		outline: 3px solid var(--warm);
		outline-offset: 2px;
	}

	.field input:focus-visible {
		outline: none;
	}

	/* --warm text on --surface-2 is just under 4.5:1 in light mode, so the
	   words use --text and the warm colour carries the edge. */
	.problem {
		font-size: 14px;
		color: var(--text);
		font-weight: 600;
		border-left: 4px solid var(--warm);
		padding-left: 10px;
	}

	.terms {
		margin: 0;
		padding-left: 18px;
		font-size: 14px;
		display: grid;
		gap: 4px;
	}

	.actions {
		display: flex;
		flex-wrap: wrap;
		gap: 8px;
	}

	.small {
		padding: 8px 16px;
		font-size: 14px;
		min-height: 44px;
		justify-content: center;
	}

	.btn[aria-disabled='true'] {
		opacity: 0.6;
		cursor: not-allowed;
	}
</style>
