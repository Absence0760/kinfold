<script lang="ts">
	import { onMount, tick } from 'svelte';
	import { formatCents } from '#lib/dashboard/format.ts';
	import { payeeWord, type RequestKind, type RequestStatus } from '#lib/dashboard/labels.ts';
	import { canInvite, createInvite, loadOwnerPanel, revokeInvite, type OwnerPanelData } from './data.ts';
	import { explainInviteError } from './errors.ts';
	import {
		checkRelationship,
		inviteLink,
		inviteState,
		inviteStateText,
		pledgeText,
		relationshipLabel,
		RELATIONSHIP_MAX,
		RELATIONSHIPS
	} from './invites.ts';

	let {
		requestId,
		kind,
		status,
		amountCents,
		title,
		headingLevel = 2
	}: {
		requestId: string;
		kind: RequestKind;
		status: RequestStatus;
		amountCents: number;
		/** The request's title, added (visually hidden) to button names when several panels share a page. */
		title?: string;
		headingLevel?: 2 | 3 | 4;
	} = $props();

	const forTitle = $derived(title ? ` for “${title}”` : '');

	const uid = $derived(`invite-${requestId}`);
	const h = $derived(`h${headingLevel}`);
	const sub = $derived(`h${headingLevel + 1}`);

	type Loaded = { state: 'loading' } | { state: 'ready'; data: OwnerPanelData } | { state: 'error'; message: string };
	let panel = $state<Loaded>({ state: 'loading' });

	let choice = $state('');
	let other = $state('');
	let touched = $state(false);
	let creating = $state(false);
	let createError = $state<string | null>(null);
	let cancelling = $state(false);
	let revokeError = $state<string | null>(null);
	let link = $state<{ url: string; relationship: string } | null>(null);
	let copied = $state<'idle' | 'copied' | 'failed'>('idle');
	let canShare = $state(false);

	let linkHeading = $state<HTMLElement>();
	let panelHeading = $state<HTMLElement>();
	let linkInput = $state<HTMLInputElement>();

	const relationshipInput = $derived(choice === 'other' ? other : choice);
	const checked = $derived(checkRelationship(relationshipInput));
	const problem = $derived('problem' in checked ? checked.problem : null);

	async function refresh() {
		try {
			panel = { state: 'ready', data: await loadOwnerPanel(requestId) };
		} catch (err) {
			panel = { state: 'error', message: explainInviteError(err as { message?: string; code?: string }) };
		}
	}

	onMount(() => {
		canShare = typeof navigator !== 'undefined' && typeof navigator.share === 'function';
		refresh();
	});

	// Try again swaps the error block (and its focused button) for the lists;
	// keep keyboard users in this panel by focusing its heading.
	async function retry() {
		await refresh();
		await tick();
		panelHeading?.focus();
	}

	async function make(e: SubmitEvent) {
		e.preventDefault();
		// aria-disabled keeps the button focusable while a link is made, so guard here.
		if (creating) return;
		touched = true;
		if (!('value' in checked)) return;
		creating = true;
		createError = null;
		copied = 'idle';
		try {
			const token = await createInvite(requestId, checked.value);
			link = { url: inviteLink(window.location.origin, token), relationship: checked.value };
			choice = '';
			other = '';
			touched = false;
			await tick();
			linkHeading?.focus();
			refresh();
		} catch (err) {
			createError = explainInviteError(err as { message?: string; code?: string });
		} finally {
			creating = false;
		}
	}

	// Cancelling one of your own waiting links: it stops working for anyone who
	// opens it later. Refresh then keeps focus in this panel.
	async function cancel(inviteId: string) {
		if (cancelling) return;
		cancelling = true;
		revokeError = null;
		try {
			await revokeInvite(inviteId);
			await tick();
			await refresh();
		} catch (err) {
			revokeError = explainInviteError(err as { message?: string; code?: string });
		} finally {
			cancelling = false;
		}
		await tick();
		panelHeading?.focus();
	}

	async function copy() {
		if (!link) return;
		try {
			await navigator.clipboard.writeText(link.url);
			copied = 'copied';
		} catch {
			// No clipboard access (an insecure origin, or the browser said no):
			// select the text so the member can copy it themselves.
			linkInput?.select();
			copied = 'failed';
		}
	}

	async function share() {
		if (!link) return;
		try {
			await navigator.share({ title: 'Help with a request on Kinfold', url: link.url });
		} catch {
			// Closing the share sheet is not an error; the link and Copy button are still there.
		}
	}

	function count(n: number, one: string, many: string) {
		return `${n} ${n === 1 ? one : many}`;
	}
</script>

<section class="invites" aria-labelledby="{uid}-heading">
	<svelte:element this={h} id="{uid}-heading" class="title" tabindex="-1" bind:this={panelHeading}
		>Invite family and friends</svelte:element
	>
	<p class="lead">
		Send a private link to someone you know. Once they accept, they can see this request and
		<strong>give</strong> (a gift, never paid back) or <strong>lend at 0%</strong>: no interest and no
		late fees, on a monthly schedule you both agree and sign, along with what happens if repayments stop. Every dollar goes to {payeeWord(kind)},
		never to you or to Kinfold, and nothing is collected until the whole amount is pledged and any
		loans are signed.
	</p>

	{#if canInvite(status)}
		<form class="make" onsubmit={make} novalidate>
			<label for="{uid}-who">Who are you inviting?</label>
			<select
				id="{uid}-who"
				bind:value={choice}
				aria-describedby="{uid}-who-hint{touched && problem ? ` ${uid}-problem` : ''}{createError ? ` ${uid}-create-error` : ''}"
				aria-invalid={touched && problem && choice !== 'other' ? 'true' : undefined}
			>
				<option value="" disabled>Choose one</option>
				{#each RELATIONSHIPS as r (r)}
					<option value={r}>{relationshipLabel(r)}</option>
				{/each}
				<option value="other">Someone else…</option>
			</select>
			{#if choice === 'other'}
				<label for="{uid}-other">How are they related to you?</label>
				<input
					id="{uid}-other"
					bind:value={other}
					maxlength={RELATIONSHIP_MAX}
					autocomplete="off"
					aria-describedby="{uid}-who-hint{touched && problem ? ` ${uid}-problem` : ''}"
					aria-invalid={touched && problem ? 'true' : undefined}
				/>
			{/if}
			<p class="hint" id="{uid}-who-hint">
				They'll see this word, and so will you in the list below. It doesn't change what they can do.
			</p>
			{#if touched && problem}
				<p class="problem" id="{uid}-problem" role="alert">{problem}</p>
			{/if}
			{#if createError}
				<p class="problem" id="{uid}-create-error" role="alert">{createError}</p>
			{/if}
			<div>
				<button type="submit" class="btn btn-primary small" aria-disabled={creating} aria-busy={creating}>
					{creating ? 'Making link…' : 'Make an invite link'}<span class="visually-hidden">{forTitle}</span>
				</button>
			</div>
		</form>
	{:else}
		<p class="note">This request has closed, so you can't invite anyone new to it.</p>
	{/if}

	{#if link}
		<div class="link" role="group" aria-labelledby="{uid}-link-heading">
			<p class="link-title" id="{uid}-link-heading" tabindex="-1" bind:this={linkHeading}>
				Your link for your {link.relationship} is ready
			</p>
			<label for="{uid}-link" class="visually-hidden">Invite link</label>
			<div class="link-row">
				<input id="{uid}-link" readonly value={link.url} bind:this={linkInput} onfocus={(e) => e.currentTarget.select()} />
				<button type="button" class="btn btn-ghost small" onclick={copy}>
					{copied === 'copied' ? 'Copied' : 'Copy link'}<span class="visually-hidden">{forTitle}</span>
				</button>
				{#if canShare}
					<button type="button" class="btn btn-ghost small" onclick={share}>
						Share…<span class="visually-hidden">{forTitle}</span>
					</button>
				{/if}
			</div>
			<p class="hint" role="status">
				{#if copied === 'copied'}
					Copied. Paste it into a text or email to them.
				{:else if copied === 'failed'}
					Couldn't copy automatically. The link is selected: copy it with your keyboard or a long press.
				{/if}
			</p>
			<ul class="terms">
				<li>Send it only to them: whoever opens it first with a Kinfold account joins.</li>
				<li>It works once and lasts 30 days.</li>
				<li>We only show it now. If you lose it, make a new one.</li>
				<li>You can cancel a link until someone joins it; after that it's used up.</li>
			</ul>
		</div>
	{/if}

	<!-- Mounted empty; only its text changes, so loading is announced. -->
	<p class="visually-hidden" role="status">{panel.state === 'loading' ? 'Loading who you’ve invited…' : ''}</p>
	{#if panel.state === 'loading'}
		<p class="muted" aria-hidden="true">Loading who you've invited…</p>
	{:else if panel.state === 'error'}
		<div class="error" role="alert">
			<p>Couldn't load your invites. {panel.message}</p>
			<button type="button" class="btn btn-ghost small" onclick={retry}>
				Try again<span class="visually-hidden"> loading your invites{forTitle}</span>
			</button>
		</div>
	{:else}
		{@const s = panel.data.support}
		<div class="group">
			<svelte:element this={sub} class="sub">People helping</svelte:element>
			<p class="muted">
				Pledged so far: {formatCents(s.raisedCents)} of {formatCents(amountCents)}. Listed in the order
				they joined; nobody is ranked by what they give.
			</p>
			{#if s.supporters.length === 0}
				<p class="empty">No one has accepted an invite yet.</p>
			{:else}
				<!-- list-style:none removes list semantics in Safari; the role puts them back. -->
				<!-- svelte-ignore a11y_no_redundant_roles -->
				<ul class="rows" role="list">
					{#each s.supporters as line (line.memberId)}
						{@const name = panel.data.supportNames.get(line.memberId)}
						<li>
							<span class="who">{relationshipLabel(line.relationship)}{#if name}: {name}{/if}</span>
							<span>{pledgeText(line)}</span>
						</li>
					{/each}
				</ul>
			{/if}
			{#if s.otherGiftCents > 0}
				<p class="muted">Gifts from members who found it on the board: {formatCents(s.otherGiftCents)}.</p>
			{/if}
			{#if s.poolCents > 0}
				<p class="muted">From the pool: {formatCents(s.poolCents)}.</p>
			{/if}
			{#if s.supporters.some((l) => l.loanCents > 0)}
				<p class="muted">Loan terms and signatures are on the <a href="/app/loans">Loans</a> page.</p>
			{/if}
		</div>

		<div class="group">
			<svelte:element this={sub} class="sub">Invite links</svelte:element>
			{#if panel.data.invites.length === 0}
				<p class="empty">You haven't made any invite links for this request.</p>
			{:else}
				<p class="muted">{count(panel.data.invites.length, 'link', 'links')} made.</p>
				<!-- list-style:none removes list semantics in Safari; the role puts them back. -->
				<!-- svelte-ignore a11y_no_redundant_roles -->
				{#if revokeError}
					<p class="problem" role="alert">{revokeError}</p>
				{/if}
				<ul class="rows" role="list">
					{#each panel.data.invites as invite (invite.id)}
						<li>
							<span class="who">{relationshipLabel(invite.relationship)}</span>
							<span class="state" data-state={inviteState(invite)}>{inviteStateText(invite)}</span>
							{#if inviteState(invite) === 'waiting'}
								<button
									type="button"
									class="btn btn-ghost small"
									onclick={() => cancel(invite.id)}
									aria-disabled={cancelling}
									aria-busy={cancelling}
								>
									Cancel link<span class="visually-hidden">{forTitle}</span>
								</button>
							{/if}
						</li>
					{/each}
				</ul>
			{/if}
		</div>
	{/if}
</section>

<style>
	.invites {
		display: grid;
		gap: 14px;
		padding: 18px;
		border: 1px solid var(--border);
		border-radius: 12px;
		background: var(--surface);
		min-width: 0;
	}

	.title {
		font-size: 20px;
	}

	.sub {
		font-size: 16px;
	}

	.lead,
	.muted,
	.hint,
	.empty,
	.note {
		color: var(--muted);
	}

	.hint {
		font-size: 13px;
	}

	.make,
	.link,
	.group {
		display: grid;
		gap: 8px;
	}

	label,
	.link-title {
		font-weight: 600;
	}

	select,
	input {
		font: inherit;
		color: var(--text);
		background: var(--surface);
		border: 1px solid var(--field-border);
		border-radius: 8px;
		padding: 8px 10px;
		min-height: 44px;
		max-width: 100%;
		min-width: 0;
	}

	select {
		max-width: 280px;
	}

	select:focus-visible,
	input:focus-visible {
		outline: 3px solid var(--warm);
		outline-offset: 2px;
	}

	.link {
		padding: 14px;
		border-radius: 10px;
		background: var(--surface-2);
	}

	.link-row {
		display: flex;
		flex-wrap: wrap;
		gap: 8px;
	}

	.link-row input {
		flex: 1 1 200px;
		font-size: 14px;
	}

	.terms {
		margin: 0;
		padding-left: 18px;
		font-size: 14px;
		display: grid;
		gap: 4px;
	}

	.rows {
		list-style: none;
		margin: 0;
		padding: 0;
		display: grid;
		gap: 6px;
	}

	.rows li {
		display: flex;
		flex-wrap: wrap;
		justify-content: space-between;
		gap: 4px 12px;
		padding: 8px 0;
		border-bottom: 1px solid var(--border);
	}

	.who {
		font-weight: 600;
	}

	.state[data-state='waiting'] {
		color: var(--muted);
	}

	.problem {
		font-size: 14px;
		color: var(--warm);
		font-weight: 600;
	}

	.error {
		display: grid;
		gap: 8px;
		justify-items: start;
	}

	.small {
		padding: 8px 16px;
		font-size: 14px;
		min-height: 44px;
		justify-content: center;
	}

	.btn[aria-disabled='true'] {
		opacity: 0.6;
		cursor: progress;
	}

</style>
