<script lang="ts">
	import { formatDay } from '#lib/dashboard/format.ts';
	import { inspectionWord, type InspectionRow } from '#lib/requests/inspections.ts';
	import Badge from '../Badge.svelte';
	import type { Tone } from '#lib/dashboard/labels.ts';

	let { inspections, needs, onrefresh }: { inspections: InspectionRow[]; needs: boolean; onrefresh: (message: string) => void } = $props();

	const toneOf = (result: string): Tone => (({ clear: 'done', issue_found: 'closed', inconclusive: 'progress' })[result] ?? 'progress') as Tone;

	const clearSeen = $derived(inspections.some((i) => i.result === 'clear'));
</script>

<div class="inspections">
	{#if inspections.length}
		<ul class="visits" role="list">
			{#each inspections as visit}
				<li>
					<Badge label={inspectionWord(visit.result)} tone={toneOf(visit.result)} />
					<span class="muted">{formatDay(visit.inspected_at)}</span>
					{#if visit.note}<p>{visit.note}</p>{/if}
				</li>
			{/each}
		</ul>
	{:else if needs}
		<p class="note">
			This request is large enough that the partner sends someone to visit the shop in person. Money won\u2019t move
			until a visit reports the damage as described — the visit is the partner\u2019s, not something you file.
		</p>
	{:else}
		<p class="empty">No in-person visit needed or made.</p>
	{/if}
	{#if needs && !clearSeen}
		<p class="muted">Until a visit finds the damage as described, funding and payout stay short.</p>
	{/if}
</div>
