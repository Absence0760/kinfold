<script lang="ts">
	import { tick } from 'svelte';
	import { formatDay } from '#lib/dashboard/format.ts';
	import type { RequestKind } from '#lib/dashboard/labels.ts';
	import { addEvidence, confirmRedaction, evidenceLink, removeEvidence, type EvidenceRow } from '#lib/requests/data.ts';
	import {
		ACCEPTED_TYPES,
		EVIDENCE_KINDS,
		SEND_WHAT_YOU_HAVE,
		evidenceAlternatives,
		evidenceKindLabel,
		evidenceNames,
		evidenceSuggestions,
		redactionText,
		type EvidenceKind
	} from '#lib/requests/evidence.ts';
	import {
		makeQueue,
		nextWaiting,
		queueItemText,
		queueSummary,
		retryFailed,
		type QueueItem
	} from '#lib/requests/upload-queue.ts';
	import Badge from '../Badge.svelte';

	let {
		evidence,
		requestId,
		uid,
		kind,
		editable,
		onreload
	}: {
		evidence: EvidenceRow[];
		requestId: string;
		uid: string;
		kind: RequestKind;
		/** Evidence can be added and removed (draft or needs evidence). */
		editable: boolean;
		/**
		 * Re-read the request without moving focus or announcing anything: this
		 * panel announces in its own live region and keeps focus where the
		 * member is, so an upload never throws them back to the top of the page.
		 */
		onreload: () => Promise<void>;
	} = $props();

	const base = $props.id();
	const names = $derived(evidenceNames(evidence));
	const nameOf = (e: EvidenceRow) => names.get(e.id) ?? evidenceKindLabel(e.kind);
	const alternatives = $derived(evidenceAlternatives(kind));

	let busy = $state<string | null>(null);
	let rowError = $state<{ id: string; message: string } | null>(null);
	let links = $state<Record<string, { url: string; which: string }>>({});
	let removing = $state<string | null>(null);
	/** What the last action did, read out by the panel's own live region. */
	let announce = $state('');

	async function focusId(id: string) {
		await tick();
		document.getElementById(id)?.focus();
	}

	async function askRemove(id: string) {
		if (busy) return;
		removing = id;
		await focusId(`${base}-${id}-confirm`);
	}

	async function keepIt(id: string) {
		removing = null;
		await focusId(`${base}-${id}-remove`);
	}

	async function open(e: EvidenceRow, which: 'original' | 'redacted') {
		if (busy) return;
		rowError = null;
		busy = `${e.id}-${which}`;
		try {
			const path = which === 'original' ? e.original_path : e.redacted_path;
			if (!path) throw new Error('There’s no redacted copy yet.');
			const url = await evidenceLink(which === 'original' ? 'evidence-original' : 'evidence-redacted', path);
			links = { ...links, [e.id]: { url, which } };
			await focusId(`${base}-${e.id}-link`);
		} catch (err) {
			rowError = { id: e.id, message: err instanceof Error ? err.message : 'The file couldn’t be opened.' };
		} finally {
			busy = null;
		}
	}

	async function confirm(e: EvidenceRow) {
		if (busy) return;
		rowError = null;
		busy = `${e.id}-confirm`;
		const name = nameOf(e);
		try {
			await confirmRedaction(e.id);
			await onreload();
			announce = `Redaction confirmed for ${name}.`;
			// The confirm button is gone now; the row's heading stays.
			await focusId(`${base}-${e.id}-h`);
		} catch (err) {
			rowError = { id: e.id, message: err instanceof Error ? err.message : 'The redaction wasn’t confirmed.' };
		} finally {
			busy = null;
		}
	}

	async function remove(e: EvidenceRow) {
		if (busy) return;
		rowError = null;
		busy = `${e.id}-remove`;
		const name = nameOf(e);
		try {
			await removeEvidence(e.id);
			removing = null;
			await onreload();
			announce = `Removed ${name}.`;
			// The row is gone; land on the section heading, not the top of the page.
			await focusId(`${base}-h`);
		} catch (err) {
			rowError = { id: e.id, message: err instanceof Error ? err.message : 'It wasn’t removed.' };
		} finally {
			busy = null;
		}
	}

	// --- adding ----------------------------------------------------------------
	let newKind = $state<EvidenceKind>('photo');
	let files = $state<File[]>([]);
	let queue = $state<QueueItem[]>([]);
	let fileInput = $state<HTMLInputElement>();
	let addProblem = $state<string | null>(null);
	let adding = $state(false);

	const failedCount = $derived(queue.filter((q) => q.status === 'failed').length);
	const waitingCount = $derived(queue.filter((q) => q.status === 'waiting').length);

	function pick(e: Event) {
		const input = e.currentTarget as HTMLInputElement;
		files = [...(input.files ?? [])];
		queue = makeQueue(files);
		addProblem = null;
		announce = '';
	}

	async function add(e: SubmitEvent) {
		e.preventDefault();
		if (adding) return;
		if (failedCount > 0 && waitingCount === 0) queue = retryFailed(queue);
		if (queue.length === 0) {
			addProblem = 'Choose one or more files to upload.';
			fileInput?.focus();
			return;
		}
		if (nextWaiting(queue) === -1) {
			addProblem = 'None of the chosen files can be uploaded. Choose others.';
			fileInput?.focus();
			return;
		}
		addProblem = null;
		adding = true;
		const kindNow = newKind;
		let uploaded = 0;
		try {
			// One file at a time: on a weak connection each one gets the whole line.
			for (let i = nextWaiting(queue); i !== -1; i = nextWaiting(queue)) {
				queue[i].status = 'uploading';
				announce = queueSummary(queue);
				try {
					await addEvidence(uid, requestId, kindNow, files[i]);
					queue[i].status = 'done';
					uploaded++;
				} catch (err) {
					queue[i].status = 'failed';
					queue[i].message = err instanceof Error ? err.message : 'The upload didn’t go through.';
				}
			}
			if (uploaded > 0) await onreload();
			announce = queueSummary(queue);
			if (queue.every((q) => q.status === 'done')) {
				// All in: start the next batch from a clean picker.
				files = [];
				queue = [];
				if (fileInput) fileInput.value = '';
				announce = `Uploaded ${uploaded === 1 ? 'the file' : `all ${uploaded} files`} as ${evidenceKindLabel(kindNow).toLowerCase()}. ${uploaded === 1 ? 'It’s' : 'They’re'} stored privately and wait for Kinfold to redact them.`;
			}
		} finally {
			adding = false;
		}
	}
</script>

<section class="block" aria-labelledby="{base}-h">
	<h2 id="{base}-h" tabindex="-1">Evidence</h2>
	<p class="note">
		Your originals are private: only you, the scorer and reviewers can open them. What anyone else
		sees is a redacted copy, with faces, plates, names, addresses and account numbers blurred, and
		only after you’ve checked it.
	</p>
	<p class="visually-hidden" role="status">{announce}</p>

	{#snippet checklist()}
		<p>What usually helps: {evidenceSuggestions(kind)}</p>
		<ul class="alts">
			{#each alternatives as alt (alt)}<li>{alt}</li>{/each}
		</ul>
		<p>{SEND_WHAT_YOU_HAVE}</p>
	{/snippet}

	{#if evidence.length === 0}
		<div class="empty">
			<p><strong>No evidence yet.</strong></p>
			{@render checklist()}
		</div>
	{:else}
		<!-- list-style:none removes list semantics in Safari; the role puts them back. -->
		<!-- svelte-ignore a11y_no_redundant_roles -->
		<ul class="list" role="list">
			{#each evidence as e (e.id)}
				{@const r = redactionText(e.redaction_status)}
				{@const name = nameOf(e)}
				<li class="item">
					<div class="item-head">
						<h3 id="{base}-{e.id}-h" tabindex="-1">{name}</h3>
						{#if e.stored}
							<Badge tone={r.tone} label={r.label} />
						{:else}
							<Badge tone="action" label="Upload didn’t finish" />
						{/if}
					</div>
					<p class="meta">
						Added {formatDay(e.created_at)} ·
						{e.captured_in_app ? 'taken in the Kinfold app' : 'uploaded from your files'}
					</p>
					{#if e.stored}
						<p class="hint">{r.hint}</p>
					{:else}
						<p class="hint">
							This upload stopped before the file arrived, so there’s nothing behind it. Remove it, then
							add the file again.
						</p>
					{/if}
					<div class="actions">
						{#if e.stored}
							<button
								type="button"
								class="btn btn-ghost small"
								onclick={() => open(e, 'original')}
								aria-disabled={busy !== null ? 'true' : undefined}
							>
								{busy === `${e.id}-original` ? 'Opening…' : 'Get a link to your original'}<span class="visually-hidden">: {name}</span>
							</button>
						{/if}
						{#if e.redacted_path}
							<button
								type="button"
								class="btn btn-ghost small"
								onclick={() => open(e, 'redacted')}
								aria-disabled={busy !== null ? 'true' : undefined}
							>
								{busy === `${e.id}-redacted` ? 'Opening…' : 'Get a link to the redacted copy'}<span class="visually-hidden">: {name}</span>
							</button>
						{/if}
						{#if e.redaction_status === 'auto_done'}
							<button
								type="button"
								class="btn btn-primary small"
								onclick={() => confirm(e)}
								aria-disabled={busy !== null ? 'true' : undefined}
							>
								{busy === `${e.id}-confirm` ? 'Confirming…' : 'I checked it: nothing private shows'}<span class="visually-hidden">: {name}</span>
							</button>
						{/if}
						{#if editable && removing !== e.id}
							<button
								type="button"
								class="btn btn-ghost small"
								id="{base}-{e.id}-remove"
								onclick={() => askRemove(e.id)}
								aria-disabled={busy !== null ? 'true' : undefined}
							>
								Remove<span class="visually-hidden">: {name}</span>
							</button>
						{/if}
					</div>
					{#if links[e.id]}
						<p class="link-line">
							<a id="{base}-{e.id}-link" href={links[e.id].url} target="_blank" rel="noopener noreferrer">
								Open the {links[e.id].which === 'original' ? 'original' : 'redacted copy'}<span class="visually-hidden"> of {name}</span> (new tab)
							</a>
							<span class="hint">The link works for 5 minutes.</span>
						</p>
					{/if}
					{#if removing === e.id}
						<div class="confirm" role="group" aria-labelledby="{base}-{e.id}-confirm-q" id="{base}-{e.id}-confirm" tabindex="-1">
							<p id="{base}-{e.id}-confirm-q">Remove {name} from the request?</p>
							<div class="actions">
								<button
									type="button"
									class="btn btn-primary small"
									onclick={() => remove(e)}
									aria-disabled={busy !== null ? 'true' : undefined}
								>
									{busy === `${e.id}-remove` ? 'Removing…' : 'Yes, remove it'}
								</button>
								<button type="button" class="btn btn-ghost small" onclick={() => keepIt(e.id)}>Keep it</button>
							</div>
						</div>
					{/if}
					{#if rowError?.id === e.id}
						<p class="problem" role="alert">{rowError.message}</p>
					{/if}
				</li>
			{/each}
		</ul>
	{/if}

	{#if editable}
		<form class="add" onsubmit={add} novalidate>
			<h3>Add evidence</h3>
			{#if evidence.length > 0}<div class="hint">{@render checklist()}</div>{/if}
			<label for="{base}-kind">What it is</label>
			<p class="hint" id="{base}-kind-hint">Applies to every file you choose this time. Add other kinds in another round.</p>
			<select id="{base}-kind" bind:value={newKind} aria-describedby="{base}-kind-hint" disabled={adding}>
				{#each EVIDENCE_KINDS as k (k.kind)}<option value={k.kind}>{k.label}</option>{/each}
			</select>
			<label for="{base}-file">Files</label>
			<input
				id="{base}-file"
				type="file"
				multiple
				accept={[...ACCEPTED_TYPES, '.heic', '.heif'].join(',')}
				bind:this={fileInput}
				onchange={pick}
				disabled={adding}
				aria-describedby="{base}-file-hint{addProblem ? ` ${base}-file-problem` : ''}"
				aria-invalid={addProblem ? 'true' : undefined}
			/>
			<p class="hint" id="{base}-file-hint">
				Photos or PDFs, up to 50 MB each. You can choose several at once; they upload one after another.
				Each is stored privately and only shared after it’s redacted and you’ve checked it.
			</p>
			{#if addProblem}<p class="problem" id="{base}-file-problem" role="alert">{addProblem}</p>{/if}

			{#if queue.length}
				<!-- svelte-ignore a11y_no_redundant_roles -->
				<ul class="queue" role="list" aria-label="Chosen files">
					{#each queue as q (q.key)}
						<li class:bad={q.status === 'failed' || q.status === 'skipped'}>
							<span class="q-name">{q.name}</span>
							<span class="q-status">{queueItemText(q)}</span>
						</li>
					{/each}
				</ul>
			{/if}

			<div class="actions">
				<button type="submit" class="btn btn-primary small" aria-disabled={adding ? 'true' : undefined}>
					{#if adding}
						Uploading…
					{:else if failedCount > 0 && waitingCount === 0}
						Try the {failedCount === 1 ? 'file' : `${failedCount} files`} that didn’t upload again
					{:else}
						Upload
					{/if}
				</button>
			</div>
			{#if adding}<p class="hint">Keep this page open until it finishes. Large files can take a minute.</p>{/if}
		</form>
	{/if}
</section>

<style>
	.block {
		margin-top: 40px;
	}

	h2 {
		font-size: 22px;
	}

	.note,
	.hint,
	.meta {
		color: var(--muted);
		font-size: 14px;
		margin: 0;
	}

	.note {
		font-size: 15px;
		margin-top: 6px;
		max-width: 680px;
	}

	.hint {
		color: var(--text);
		font-size: 15px;
	}

	div.hint {
		display: grid;
		gap: 6px;
	}

	.empty,
	.item,
	.add {
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius);
		padding: 16px 18px;
	}

	.empty {
		margin-top: 16px;
		border-style: dashed;
		display: grid;
		gap: 6px;
		color: var(--muted);
	}

	.empty strong {
		color: var(--text);
	}

	.alts {
		margin: 0;
		padding-left: 20px;
		display: grid;
		gap: 4px;
	}

	.list {
		list-style: none;
		margin: 16px 0 0;
		padding: 0;
		display: grid;
		gap: 12px;
	}

	.item {
		display: grid;
		gap: 6px;
	}

	.item-head {
		display: flex;
		flex-wrap: wrap;
		justify-content: space-between;
		gap: 8px 16px;
	}

	h3 {
		font-size: 17px;
	}

	.actions {
		display: flex;
		flex-wrap: wrap;
		gap: 8px;
		margin-top: 4px;
	}

	.btn.small {
		min-height: 44px;
		padding: 8px 14px;
		font-size: 14px;
	}

	.btn[aria-disabled='true'],
	select:disabled,
	input:disabled {
		opacity: 0.6;
		cursor: progress;
	}

	.link-line {
		display: flex;
		flex-wrap: wrap;
		gap: 4px 12px;
		margin: 0;
		font-size: 15px;
	}

	.link-line a {
		display: inline-flex;
		align-items: center;
		min-height: 44px;
	}

	.link-line .hint {
		color: var(--muted);
		font-size: 14px;
		align-self: center;
	}

	.confirm {
		background: var(--surface-2);
		border-radius: 10px;
		padding: 10px 12px;
	}

	.problem {
		margin: 0;
		font-size: 14px;
		font-weight: 600;
		padding-left: 10px;
		border-left: 4px solid var(--warm);
	}

	.add {
		margin-top: 16px;
		display: grid;
		gap: 6px;
		max-width: 680px;
	}

	.add label {
		font-weight: 700;
		margin-top: 6px;
	}

	select,
	input[type='file'] {
		font: inherit;
		color: var(--text);
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: 10px;
		padding: 10px 12px;
		width: 100%;
		min-width: 0;
		min-height: 44px;
	}

	[aria-invalid='true'] {
		border-color: var(--warm);
		border-width: 2px;
	}

	.queue {
		list-style: none;
		margin: 6px 0 0;
		padding: 0;
		display: grid;
		gap: 6px;
		font-size: 15px;
	}

	.queue li {
		display: grid;
		gap: 2px;
		padding: 8px 10px;
		border-left: 4px solid var(--accent);
		background: var(--surface-2);
		border-radius: 6px;
	}

	.queue li.bad {
		border-left-color: var(--warm);
	}

	.q-name {
		font-weight: 600;
		overflow-wrap: anywhere;
	}

	.q-status {
		color: var(--muted);
		font-size: 14px;
	}

	@media (max-width: 400px) {
		.empty,
		.item,
		.add {
			padding: 14px;
		}
	}
</style>
