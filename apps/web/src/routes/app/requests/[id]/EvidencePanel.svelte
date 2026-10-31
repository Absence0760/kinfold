<script lang="ts">
	import { tick } from 'svelte';
	import { formatDay } from '#lib/dashboard/format.ts';
	import type { RequestKind } from '#lib/dashboard/labels.ts';
	import { addEvidence, confirmRedaction, evidenceLink, removeEvidence, type EvidenceRow } from '#lib/requests/data.ts';
	import {
		ACCEPTED_TYPES,
		EVIDENCE_KINDS,
		evidenceKindLabel,
		evidenceSuggestions,
		fileProblem,
		redactionText,
		type EvidenceKind
	} from '#lib/requests/evidence.ts';
	import Badge from '../Badge.svelte';

	let {
		evidence,
		requestId,
		uid,
		kind,
		editable,
		onchanged
	}: {
		evidence: EvidenceRow[];
		requestId: string;
		uid: string;
		kind: RequestKind;
		/** Evidence can be added and removed (draft or needs evidence). */
		editable: boolean;
		/** Called after a change, with a confirmation to announce. */
		onchanged: (message: string) => Promise<void>;
	} = $props();

	const base = $props.id();
	let busy = $state<string | null>(null);
	let rowError = $state<{ id: string; message: string } | null>(null);
	let links = $state<Record<string, { url: string; which: string }>>({});
	let removing = $state<string | null>(null);

	async function open(e: EvidenceRow, which: 'original' | 'redacted') {
		rowError = null;
		busy = `${e.id}-${which}`;
		try {
			const path = which === 'original' ? e.original_path : e.redacted_path;
			if (!path) throw new Error('There’s no redacted copy yet.');
			const url = await evidenceLink(which === 'original' ? 'evidence-original' : 'evidence-redacted', path);
			links = { ...links, [e.id]: { url, which } };
			await tick();
			document.getElementById(`${base}-${e.id}-link`)?.focus();
		} catch (err) {
			rowError = { id: e.id, message: err instanceof Error ? err.message : 'The file couldn’t be opened.' };
		} finally {
			busy = null;
		}
	}

	async function confirm(e: EvidenceRow) {
		rowError = null;
		busy = `${e.id}-confirm`;
		try {
			await confirmRedaction(e.id);
			await onchanged(`Redaction confirmed for the ${evidenceKindLabel(e.kind).toLowerCase()}.`);
		} catch (err) {
			rowError = { id: e.id, message: err instanceof Error ? err.message : 'The redaction wasn’t confirmed.' };
		} finally {
			busy = null;
		}
	}

	async function remove(e: EvidenceRow) {
		rowError = null;
		busy = `${e.id}-remove`;
		try {
			await removeEvidence(e.id);
			removing = null;
			await onchanged(`Removed the ${evidenceKindLabel(e.kind).toLowerCase()}.`);
		} catch (err) {
			rowError = { id: e.id, message: err instanceof Error ? err.message : 'It wasn’t removed.' };
		} finally {
			busy = null;
		}
	}

	// --- adding ----------------------------------------------------------------
	let newKind = $state<EvidenceKind>('photo');
	let file = $state<File | null>(null);
	let fileInput = $state<HTMLInputElement>();
	let addProblem = $state<string | null>(null);
	let adding = $state(false);

	function pick(e: Event) {
		const input = e.currentTarget as HTMLInputElement;
		file = input.files?.[0] ?? null;
		addProblem = file ? fileProblem(file) : null;
	}

	async function add(e: SubmitEvent) {
		e.preventDefault();
		if (!file) {
			addProblem = 'Choose a file to upload.';
			fileInput?.focus();
			return;
		}
		addProblem = fileProblem(file);
		if (addProblem) {
			fileInput?.focus();
			return;
		}
		adding = true;
		try {
			await addEvidence(uid, requestId, newKind, file);
			const label = evidenceKindLabel(newKind).toLowerCase();
			file = null;
			if (fileInput) fileInput.value = '';
			await onchanged(`Uploaded the ${label}. It’s stored privately and waits for redaction.`);
		} catch (err) {
			addProblem = err instanceof Error ? err.message : 'The upload didn’t go through. Try again.';
		} finally {
			adding = false;
		}
	}
</script>

<section class="block" aria-labelledby="{base}-h">
	<h2 id="{base}-h">Evidence</h2>
	<p class="note">
		Your originals are private: only you, the scorer and reviewers can open them. What anyone else
		sees is a redacted copy, with faces, plates, names, addresses and account numbers blurred, and
		only after you’ve checked it.
	</p>

	{#if evidence.length === 0}
		<div class="empty">
			<p><strong>No evidence yet.</strong></p>
			<p>What usually helps: {evidenceSuggestions(kind)}</p>
		</div>
	{:else}
		<ul class="list">
			{#each evidence as e (e.id)}
				{@const r = redactionText(e.redaction_status)}
				<li class="item">
					<div class="item-head">
						<h3>{evidenceKindLabel(e.kind)}</h3>
						<Badge tone={r.tone} label={r.label} />
					</div>
					<p class="meta">
						Added {formatDay(e.created_at)} ·
						{e.captured_in_app ? 'taken in the Kinfold app' : 'uploaded from your files'}
					</p>
					<p class="hint">{r.hint}</p>
					<div class="actions">
						<button type="button" class="btn btn-ghost small" onclick={() => open(e, 'original')} disabled={busy !== null}>
							{busy === `${e.id}-original` ? 'Opening…' : 'Get a link to your original'}
						</button>
						{#if e.redacted_path}
							<button type="button" class="btn btn-ghost small" onclick={() => open(e, 'redacted')} disabled={busy !== null}>
								{busy === `${e.id}-redacted` ? 'Opening…' : 'Get a link to the redacted copy'}
							</button>
						{/if}
						{#if e.redaction_status === 'auto_done'}
							<button type="button" class="btn btn-primary small" onclick={() => confirm(e)} disabled={busy !== null}>
								{busy === `${e.id}-confirm` ? 'Confirming…' : 'I checked it: nothing private shows'}
							</button>
						{/if}
						{#if editable && removing !== e.id}
							<button type="button" class="btn btn-ghost small" onclick={() => (removing = e.id)} disabled={busy !== null}>
								Remove
							</button>
						{/if}
					</div>
					{#if links[e.id]}
						<p class="link-line">
							<a id="{base}-{e.id}-link" href={links[e.id].url} target="_blank" rel="noopener noreferrer">
								Open the {links[e.id].which === 'original' ? 'original' : 'redacted copy'} (new tab)
							</a>
							<span class="hint">The link works for 5 minutes.</span>
						</p>
					{/if}
					{#if removing === e.id}
						<div class="confirm" role="group" aria-label="Remove this evidence?">
							<p>Remove this {evidenceKindLabel(e.kind).toLowerCase()} from the request?</p>
							<div class="actions">
								<button type="button" class="btn btn-primary small" onclick={() => remove(e)} disabled={busy !== null}>
									{busy === `${e.id}-remove` ? 'Removing…' : 'Yes, remove it'}
								</button>
								<button type="button" class="btn btn-ghost small" onclick={() => (removing = null)}>Keep it</button>
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
			{#if evidence.length > 0}<p class="hint">What usually helps: {evidenceSuggestions(kind)}</p>{/if}
			<label for="{base}-kind">What it is</label>
			<select id="{base}-kind" bind:value={newKind}>
				{#each EVIDENCE_KINDS as k (k.kind)}<option value={k.kind}>{k.label}</option>{/each}
			</select>
			<label for="{base}-file">File</label>
			<input
				id="{base}-file"
				type="file"
				accept={ACCEPTED_TYPES.join(',')}
				bind:this={fileInput}
				onchange={pick}
				aria-describedby="{base}-file-hint{addProblem ? ` ${base}-file-problem` : ''}"
				aria-invalid={addProblem ? 'true' : undefined}
			/>
			<p class="hint" id="{base}-file-hint">
				A photo or a PDF, up to 50 MB. Uploads from your files are marked as such; photos taken in
				the Kinfold app (coming with the phone app) count for more, because they can be checked as
				unedited.
			</p>
			{#if addProblem}<p class="problem" id="{base}-file-problem" role="alert">{addProblem}</p>{/if}
			<div class="actions">
				<button type="submit" class="btn btn-primary small" disabled={adding}>
					{adding ? 'Uploading…' : 'Upload'}
				</button>
			</div>
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
		padding: 8px 14px;
		font-size: 14px;
	}

	.btn:disabled {
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

	.link-line .hint {
		color: var(--muted);
		font-size: 14px;
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
	}

	[aria-invalid='true'] {
		border-color: var(--warm);
		border-width: 2px;
	}

	@media (max-width: 400px) {
		.empty,
		.item,
		.add {
			padding: 14px;
		}
	}
</style>
