<script lang="ts">
	import { tick } from 'svelte';
	import { amountCents, amountEcho } from '#lib/requests/amount.ts';
	import { fundingLabel, payeeWord, poolName, poolRule, type FundingMode, type RequestKind } from '#lib/dashboard/labels.ts';
	import { createDraft, proposePayee, updateDraft, type FormContext, type PayeeRow } from '#lib/requests/data.ts';
	import { poolProblems, poolRulesText, usesPool } from '#lib/requests/eligibility.ts';
	import {
		DESCRIPTION_MAX,
		FUNDING_MODES,
		REQUEST_KINDS,
		TITLE_MAX,
		US_STATES,
		charCount,
		fundForKind,
		isCarKind,
		latestIncidentDate,
		payeeKindLabel,
		payeeKindsFor,
		validateDraft,
		validatePayee,
		type DraftField,
		type DraftInput,
		type DraftProblems,
		type PayeeKind
	} from '#lib/requests/form.ts';

	let {
		ctx,
		uid,
		region,
		initial,
		requestId = null,
		createdAt = undefined,
		onsaved,
		oncancel = undefined
	}: {
		ctx: FormContext;
		uid: string;
		/** The member's own state: the default for a payee they add. */
		region: string;
		initial: DraftInput;
		/** Set when editing an existing draft. */
		requestId?: string | null;
		createdAt?: string;
		onsaved: (id: string) => void;
		oncancel?: () => void;
	} = $props();

	// The form edits its own copy; the initial values only seed it.
	// svelte-ignore state_referenced_locally
	let form = $state<DraftInput>({ ...initial });
	let problems = $state<DraftProblems>({});
	let saving = $state(false);
	let saveError = $state<string | null>(null);
	// Seeded once; a payee the member adds joins this list.
	// svelte-ignore state_referenced_locally
	let payees = $state<PayeeRow[]>([...ctx.payees]);

	const uidBase = $props.id();
	const id = (f: string) => `${uidBase}-${f}`;
	let errorBox = $state<HTMLElement>();

	const kind = $derived(form.kind as RequestKind);
	/** False until the member picks what the help is for; the pool and payee depend on it. */
	const chosen = $derived(REQUEST_KINDS.some((k) => k.kind === form.kind));
	const funding = $derived(form.funding as FundingMode);
	const latest = $derived(latestIncidentDate(new Date(), createdAt));
	// Payees that fit this kind of request come first; the rest stay choosable,
	// since nothing in the backend ties a payee's kind to a request's.
	const payeeKinds = $derived<PayeeKind[]>(
		chosen ? payeeKindsFor(kind) : ['repair_shop', 'contractor', 'lender', 'seller', 'title_company']
	);
	const fittingPayees = $derived(payees.filter((p) => payeeKinds.includes(p.kind)));
	const otherPayees = $derived(payees.filter((p) => !payeeKinds.includes(p.kind)));
	const cars = $derived(ctx.assets.filter((a) => a.kind === 'vehicle'));
	const settings = $derived(ctx.settings.find((s) => s.fund === fundForKind(kind)) ?? null);
	const warnings = $derived(
		!chosen
			? []
			: poolProblems(
			{
				kind,
				funding,
				amountCents: amountCents(form.amount),
				incidentOn: form.incidentOn || null,
				assetId: form.assetId || null
			},
			{ settings, coverageStartedOn: ctx.coverageStartedOn, assets: ctx.assets }
		)
	);

	function fundingName(mode: FundingMode): string {
		if (mode === 'both') return 'Both';
		if (!chosen) return mode === 'pool' ? 'The community pool' : 'Family and friends';
		return fundingLabel(mode, kind);
	}

	function fundingHint(mode: FundingMode): string {
		if (!chosen && mode !== 'people')
			return 'The repair fund for cars, or the Home Fund for homes. Choose what the help is for to see its rules.';
		switch (mode) {
			case 'people':
				return 'You invite the people you choose. They give, or lend at zero interest with no late fees. No waiting period, and it never goes on the board.';
			case 'pool':
				return poolRulesText(kind, settings);
			case 'both':
				return `Your people and ${poolName(kind)} together. The pool ${poolRule(kind)} at its run; your people can cover the rest.`;
		}
	}

	const payeeOption = (p: PayeeRow) =>
		`${p.legal_name} (${p.region})${p.status === 'verified' ? '' : ' · waiting for Kinfold to verify'}`;

	const describedBy = (f: DraftField, ...extra: string[]) =>
		[...extra, problems[f] ? id(`${f}-problem`) : ''].filter(Boolean).join(' ') || undefined;

	async function save(e: SubmitEvent) {
		e.preventDefault();
		if (saving) return;
		saveError = null;
		const r = validateDraft(form, latest);
		if (!r.ok) {
			problems = r.problems;
			await tick();
			const first = (['kind', 'funding', 'title', 'amount', 'incidentOn', 'description'] as const).find(
				(f) => r.problems[f]
			);
			if (first) document.getElementById(id(first))?.focus();
			return;
		}
		problems = {};
		saving = true;
		try {
			if (requestId) {
				await updateDraft(requestId, r.values);
				onsaved(requestId);
			} else {
				onsaved(await createDraft(uid, r.values));
			}
		} catch (err) {
			saveError = err instanceof Error ? err.message : 'The draft wasn’t saved. Try again.';
			await tick();
			errorBox?.focus();
		} finally {
			saving = false;
		}
	}

	// --- adding a payee that isn't listed -------------------------------------------
	let adding = $state(false);
	let newPayee = $state({ kind: '', legalName: '', region: '' });
	let payeeProblems = $state<Record<string, string>>({});
	let payeeError = $state<string | null>(null);
	let payeeSaving = $state(false);
	let payeeNotice = $state<string | null>(null);

	async function openAdd() {
		adding = true;
		payeeNotice = null;
		newPayee = { kind: payeeKinds[0], legalName: '', region };
		await tick();
		document.getElementById(id('payee-name'))?.focus();
	}

	async function closeAdd() {
		adding = false;
		payeeProblems = {};
		payeeError = null;
		await tick();
		document.getElementById(id('payeeId'))?.focus();
	}

	/** Enter in the business name adds the business; it must not save the whole draft. */
	function nameKey(e: KeyboardEvent) {
		if (e.key !== 'Enter') return;
		e.preventDefault();
		if (!payeeSaving) addPayee();
	}

	async function addPayee() {
		if (payeeSaving) return;
		payeeError = null;
		const r = validatePayee(newPayee);
		if (!r.ok) {
			payeeProblems = r.problems;
			await tick();
			const first = r.problems.legalName ? 'payee-name' : r.problems.region ? 'payee-region' : 'payee-kind';
			document.getElementById(id(first))?.focus();
			return;
		}
		payeeProblems = {};
		payeeSaving = true;
		try {
			const p = await proposePayee(uid, r.values);
			payees = [...payees, p];
			form.payeeId = p.id;
			adding = false;
			payeeNotice = `Added ${p.legal_name}. Kinfold checks the business and its bank details before any money is pledged or paid to it.`;
			await tick();
			document.getElementById(id('payeeId'))?.focus();
		} catch (err) {
			payeeError = err instanceof Error ? err.message : 'The business wasn’t added. Try again.';
		} finally {
			payeeSaving = false;
		}
	}
</script>

<form class="form" onsubmit={save} novalidate>
	<fieldset aria-describedby={problems.kind ? id('kind-problem') : undefined}>
		<legend>What is the help for?</legend>
		<div class="choices">
			{#each REQUEST_KINDS as k (k.kind)}
				<label class="choice">
					<input
						type="radio"
						name={id('kind')}
						id={k.kind === REQUEST_KINDS[0].kind ? id('kind') : undefined}
						value={k.kind}
						bind:group={form.kind}
						aria-describedby={id(`kind-${k.kind}`)}
					/>
					<span>
						<strong>{k.label}</strong>
						<span class="hint" id={id(`kind-${k.kind}`)}>{k.hint}</span>
					</span>
				</label>
			{/each}
		</div>
		{#if problems.kind}<p class="problem" id={id('kind-problem')}>{problems.kind}</p>{/if}
	</fieldset>

	<fieldset aria-describedby={problems.funding ? id('funding-problem') : undefined}>
		<legend>Who are you asking?</legend>
		<div class="choices">
			{#each FUNDING_MODES as mode (mode)}
				<label class="choice">
					<input
						type="radio"
						name={id('funding')}
						id={mode === 'people' ? id('funding') : undefined}
						value={mode}
						bind:group={form.funding}
						aria-describedby={id(`funding-${mode}`)}
					/>
					<span>
						<strong>{fundingName(mode)}</strong>
						<span class="hint" id={id(`funding-${mode}`)}>{fundingHint(mode)}</span>
					</span>
				</label>
			{/each}
		</div>
		{#if problems.funding}<p class="problem" id={id('funding-problem')}>{problems.funding}</p>{/if}
		{#if warnings.length}
			<div class="warn" role="note" aria-labelledby={id('pool-warn')}>
				<p id={id('pool-warn')}><strong>The pool may not be able to help with this:</strong></p>
				<ul>
					{#each warnings as w (w)}<li>{w}</li>{/each}
				</ul>
				<p class="hint">You can still save the draft. These are checked again when you submit.</p>
			</div>
		{/if}
	</fieldset>

	<div class="field">
		<label for={id('title')}>Title</label>
		<p class="hint" id={id('title-hint')}>
			A few words for you and the reviewer. Family or friends you invite to support the request see it
			too. It never goes on the board; a redacted summary does.
		</p>
		<input
			id={id('title')}
			bind:value={form.title}
			maxlength={TITLE_MAX * 2}
			autocomplete="off"
			aria-invalid={problems.title ? 'true' : undefined}
			aria-describedby={describedBy('title', id('title-hint'), id('title-count'))}
		/>
		<p class="count" id={id('title-count')}>{charCount(form.title.trim())} of {TITLE_MAX} characters</p>
		{#if problems.title}<p class="problem" id={id('title-problem')}>{problems.title}</p>{/if}
	</div>

	<div class="field">
		<label for={id('description')}>What happened <span class="opt">(optional)</span></label>
		<p class="hint" id={id('description-hint')}>
			Read by you, the scorer, the reviewer, and family or friends you invite to support the
			request. It never goes on the board. Include anything that helps explain the evidence, but
			leave out other people’s names, plates and addresses: the evidence can show those privately.
		</p>
		<textarea
			id={id('description')}
			bind:value={form.description}
			rows="5"
			aria-invalid={problems.description ? 'true' : undefined}
			aria-describedby={describedBy('description', id('description-hint'), id('description-count'))}
		></textarea>
		<p class="count" id={id('description-count')}>
			{charCount(form.description.trim()).toLocaleString('en-US')} of {DESCRIPTION_MAX.toLocaleString('en-US')} characters
		</p>
		{#if problems.description}<p class="problem" id={id('description-problem')}>{problems.description}</p>{/if}
	</div>

	<div class="row">
		<div class="field">
			<label for={id('amount')}>How much you need</label>
			<p class="hint" id={id('amount-hint')}>In dollars, as on the estimate or bill. Use a dot for cents, like 1,250.50.</p>
			<div class="money">
				<span aria-hidden="true">$</span>
				<input
					id={id('amount')}
					bind:value={form.amount}
					inputmode="decimal"
					autocomplete="off"
					aria-invalid={problems.amount ? 'true' : undefined}
					aria-describedby={describedBy('amount', id('amount-hint'), id('amount-echo'))}
				/>
			</div>
			<!-- What the form understood, so "12,50" can't silently become $1,250. -->
			<p class="count" id={id('amount-echo')}>{amountEcho(form.amount) ?? ''}</p>
			{#if problems.amount}<p class="problem" id={id('amount-problem')}>{problems.amount}</p>{/if}
		</div>

		<div class="field">
			<label for={id('incidentOn')}>When it happened</label>
			<p class="hint" id={id('incidentOn-hint')}>The day of the damage, or the date on the bill.</p>
			<input
				id={id('incidentOn')}
				type="date"
				bind:value={form.incidentOn}
				max={latest}
				aria-invalid={problems.incidentOn ? 'true' : undefined}
				aria-describedby={describedBy('incidentOn', id('incidentOn-hint'))}
			/>
			{#if problems.incidentOn}<p class="problem" id={id('incidentOn-problem')}>{problems.incidentOn}</p>{/if}
		</div>
	</div>

	<div class="field">
		<label for={id('payeeId')}>Who should be paid</label>
		<p class="hint" id={id('payeeId-hint')}>
			The money goes to {chosen ? payeeWord(kind) : 'the business or lender'}, never to you. You can save the draft without one and add it
			before you submit.
		</p>
		<select id={id('payeeId')} bind:value={form.payeeId} aria-describedby={id('payeeId-hint')}>
			<option value="">Not chosen yet</option>
			{#if fittingPayees.length}
				<optgroup label={`${payeeKinds.map(payeeKindLabel).join(', ')}`}>
					{#each fittingPayees as p (p.id)}
						<option value={p.id}>{payeeOption(p)}</option>
					{/each}
				</optgroup>
			{/if}
			{#if otherPayees.length}
				<optgroup label="Other businesses">
					{#each otherPayees as p (p.id)}
						<option value={p.id}>{payeeOption(p)}</option>
					{/each}
				</optgroup>
			{/if}
		</select>
		{#if payeeNotice}<p class="ok" role="status">{payeeNotice}</p>{/if}
		{#if !adding}
			<button type="button" class="btn btn-ghost small" onclick={openAdd}>Not listed? Add the business</button>
		{:else}
			<div class="sub-form" role="group" aria-labelledby={id('payee-add')}>
				<p id={id('payee-add')}><strong>Add the business to be paid</strong></p>
				<p class="hint">
					Kinfold checks the business and its bank details before anything is pledged or paid to it.
					You can still submit the request meanwhile.
				</p>
				{#if payeeKinds.length > 1}
					<label for={id('payee-kind')}>Kind of business</label>
					<select
						id={id('payee-kind')}
						bind:value={newPayee.kind}
						aria-invalid={payeeProblems.kind ? 'true' : undefined}
						aria-describedby={payeeProblems.kind ? id('payee-kind-problem') : undefined}
					>
						{#each payeeKinds as pk (pk)}<option value={pk}>{payeeKindLabel(pk)}</option>{/each}
					</select>
				{/if}
				<label for={id('payee-name')}>Business name</label>
				<input
					id={id('payee-name')}
					bind:value={newPayee.legalName}
					onkeydown={nameKey}
					autocomplete="off"
					aria-invalid={payeeProblems.legalName ? 'true' : undefined}
					aria-describedby={payeeProblems.legalName ? id('payee-name-problem') : undefined}
				/>
				{#if payeeProblems.legalName}<p class="problem" id={id('payee-name-problem')}>{payeeProblems.legalName}</p>{/if}
				<label for={id('payee-region')}>State</label>
				<select
					id={id('payee-region')}
					bind:value={newPayee.region}
					aria-invalid={payeeProblems.region ? 'true' : undefined}
					aria-describedby={payeeProblems.region ? id('payee-region-problem') : undefined}
				>
					{#each US_STATES as [code, name] (code)}<option value={code}>{name}</option>{/each}
				</select>
				{#if payeeProblems.region}<p class="problem" id={id('payee-region-problem')}>{payeeProblems.region}</p>{/if}
				{#if payeeProblems.kind}<p class="problem" id={id('payee-kind-problem')}>{payeeProblems.kind}</p>{/if}
				{#if payeeError}<p class="problem" role="alert">{payeeError}</p>{/if}
				<div class="actions">
					<button type="button" class="btn btn-primary small" onclick={addPayee} disabled={payeeSaving}>
						{payeeSaving ? 'Adding…' : 'Add business'}
					</button>
					<button type="button" class="btn btn-ghost small" onclick={closeAdd} disabled={payeeSaving}>Cancel</button>
				</div>
			</div>
		{/if}
	</div>

	{#if isCarKind(kind)}
		<div class="field">
			{#if cars.length === 0}
				<p class="label">Which car</p>
			{:else}
				<label for={id('assetId')}>Which car</label>
			{/if}
			<p class="hint" id={id('assetId-hint')}>
				{usesPool(funding)
					? 'The repair fund only helps with a car registered with Kinfold.'
					: 'Optional when only family and friends are paying.'}
			</p>
			{#if cars.length === 0}
				<p class="empty-note" id={id('assetId')} tabindex="-1">
					You haven’t registered a car with Kinfold. Family and friends can still help; the repair fund
					only helps with registered cars.
				</p>
			{:else}
				<select id={id('assetId')} bind:value={form.assetId} aria-describedby={id('assetId-hint')}>
					<option value="">Not chosen</option>
					{#each cars as c (c.id)}<option value={c.id}>{c.description}</option>{/each}
				</select>
			{/if}
		</div>
	{/if}

	{#if saveError}
		<div class="problem-box" role="alert" tabindex="-1" bind:this={errorBox}>
			<p><strong>The draft wasn’t saved.</strong> {saveError}</p>
		</div>
	{/if}

	<div class="actions">
		<button type="submit" class="btn btn-primary" aria-disabled={saving ? 'true' : undefined}>
			{saving ? 'Saving your draft…' : requestId ? 'Save changes' : 'Save draft'}
		</button>
		{#if oncancel}
			<button type="button" class="btn btn-ghost" onclick={oncancel} disabled={saving}>Cancel</button>
		{/if}
	</div>
	<span class="visually-hidden" role="status">{saving ? 'Saving your draft…' : ''}</span>
	<p class="hint">
		Saving keeps it as a draft that only you, and family or friends you invite to support it, can see.
		Nothing is sent for scoring until you submit it.
	</p>
</form>

<style>
	.form {
		display: grid;
		gap: 24px;
		max-width: 680px;
	}

	fieldset {
		border: 0;
		margin: 0;
		padding: 0;
		min-width: 0;
	}

	legend,
	label,
	.label {
		font-weight: 700;
		font-size: 16px;
		margin: 0;
	}

	legend {
		padding: 0;
		margin-bottom: 10px;
	}

	.choices {
		display: grid;
		gap: 8px;
	}

	.choice {
		display: flex;
		gap: 12px;
		align-items: flex-start;
		font-weight: 400;
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: 10px;
		padding: 12px 14px;
		cursor: pointer;
		min-height: 44px;
	}

	.choice:has(input:checked) {
		border-color: var(--accent);
		box-shadow: inset 0 0 0 1px var(--accent);
	}

	.choice input {
		margin-top: 4px;
		flex: none;
		width: 18px;
		height: 18px;
		accent-color: var(--accent);
	}

	.choice strong {
		display: block;
	}

	.field {
		display: grid;
		gap: 6px;
		min-width: 0;
	}

	.row {
		display: grid;
		gap: 24px;
		grid-template-columns: repeat(auto-fit, minmax(min(100%, 14rem), 1fr));
	}

	input:not([type='radio']),
	select,
	textarea {
		font: inherit;
		min-height: 44px;
		color: var(--text);
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: 10px;
		padding: 10px 12px;
		width: 100%;
		min-width: 0;
	}

	textarea {
		resize: vertical;
	}

	[aria-invalid='true'] {
		border-color: var(--warm);
		border-width: 2px;
	}

	.money {
		display: flex;
		align-items: center;
		gap: 8px;
	}

	.money span {
		font-weight: 700;
	}

	.hint,
	.count {
		color: var(--muted);
		font-size: 14px;
		font-weight: 400;
		margin: 0;
	}

	.opt {
		font-weight: 400;
		color: var(--muted);
	}

	.problem {
		color: var(--text);
		font-size: 14px;
		font-weight: 600;
		margin: 0;
		padding-left: 10px;
		border-left: 4px solid var(--warm);
	}

	.problem::before {
		content: 'Fix: ';
	}

	.problem-box {
		background: var(--warm-soft);
		border-left: 4px solid var(--warm);
		border-radius: 10px;
		padding: 12px 14px;
	}

	.warn {
		margin-top: 12px;
		background: var(--warm-soft);
		border-left: 4px solid var(--warm);
		border-radius: 10px;
		padding: 12px 14px;
		font-size: 15px;
	}

	.warn ul {
		margin: 6px 0;
		padding-left: 20px;
	}

	.ok {
		font-size: 14px;
		margin: 0;
		padding-left: 10px;
		border-left: 4px solid var(--accent);
	}

	.empty-note {
		margin: 0;
		font-size: 15px;
		background: var(--surface-2);
		border-radius: 10px;
		padding: 10px 12px;
	}

	.sub-form {
		display: grid;
		gap: 6px;
		background: var(--surface-2);
		border-radius: 10px;
		padding: 14px;
		margin-top: 4px;
	}

	.sub-form label {
		font-size: 15px;
		margin-top: 6px;
	}

	.actions {
		display: flex;
		flex-wrap: wrap;
		gap: 10px;
		margin-top: 4px;
	}

	.btn.small {
		padding: 8px 16px;
		min-height: 44px;
		font-size: 14px;
		justify-self: start;
	}

	.btn {
		min-height: 44px;
	}

	.btn:disabled,
	.btn[aria-disabled='true'] {
		opacity: 0.6;
		cursor: progress;
	}
</style>
