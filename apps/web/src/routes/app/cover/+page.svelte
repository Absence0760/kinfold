<script lang="ts">
	import { invalidate } from '$app/navigation';
	import { formatCents } from '#lib/dashboard/format.ts';
	import { explainCoverError } from '#lib/cover/errors.ts';
	import type { CoverDetail } from '#lib/cover/data.ts';
	import ClassVehicle from './ClassVehicle.svelte';
	import ChoosePlan from './ChoosePlan.svelte';

	let { data } = $props();

	/** The rating-law classes the schema accepts. */
	const CLASSES = ['micro_car', 'sedan', 'suv', 'pickup', 'van'];

	// Keep showing the cover while it reloads after an action, like the loan
	// console does: the promise resolves into state instead of flashing.
	let cover = $state<CoverDetail | null>(null);
	let failed = $state(false);
	$effect(() => {
		let live = true;
		data.cover.then(
			(c) => {
				if (!live) return;
				cover = c;
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

	let heading = $state<HTMLElement>();
	let message = $state('');

	/** The vehicles with no class stated yet, oldest first. */
	const unclassed = $derived((cover?.assets ?? []).filter((a) => a.vehicle_class === null));

	async function onchanged(text: string) {
		message = text;
		try {
			await invalidate('app:cover');
			cover = await data.cover;
		} catch (err) {
			message = explainCoverError(err as { message?: string; code?: string });
		}
	}
</script>

<svelte:head>
	<title>Your car cover · Kinfold</title>
</svelte:head>

<header class="page-head">
	<p class="eyebrow">Membership</p>
	<h1 tabindex="-1" bind:this={heading}>Your car cover</h1>
	<p class="lead">
		The cooperative pays premiums on a group car policy, from dues money. You choose the plan that
		applies to your vehicles and state the rating-law class on each of them; the premium money itself
		goes to the partner insurer and is never held here.
	</p>
</header>

{#if cover}

<section class="block" aria-labelledby="cover-vehicles-h">
	<h2 id="cover-vehicles-h">Your covered vehicles</h2>
	{#if cover.assets.length === 0}
		<p class="muted">No vehicle is enrolled in the cover yet. A covered vehicle carries a rating-law class.</p>
	{:else}
		<!-- list-style:none removes list semantics in Safari; the role puts them back. -->
		<!-- svelte-ignore a11y_no_redundant_roles -->
		<ul class="assets" role="list">
			{#each cover.assets as a}
				<li><strong>{a.vehicle_class ?? 'no class stated yet'}</strong> · {a.description}</li>
			{/each}
		</ul>
	{/if}
</section>

<section class="block" aria-labelledby="cover-rates-h">
	<h2 id="cover-rates-h">The filed rates that apply to you</h2>
	{#if cover.filed.length === 0}
		<p class="muted">No filed rate matches your vehicles yet — premiums are only taken on classed vehicles.</p>
	{:else}
		<!-- list-style:none removes list semantics in Safari; the role puts them back. -->
		<!-- svelte-ignore a11y_no_redundant_roles -->
		<ul class="rates" role="list">
			{#each cover.filed as r}
				<li>
					<strong>{r.vehicle_class} · {r.plan}</strong>
					<span class="muted">{formatCents(r.premium_cents)} premium · up to {formatCents(r.cap_cents)} per claim</span>
				</li>
			{/each}
		</ul>
	{/if}
	<p class="section-note">Premiums for this member: {formatCents(cover.premiumCents)} a year, paid in full.</p>
</section>

{#if message}<p class="note" role="status">{message}</p>{/if}

{#if unclassed.length > 0}
	<ClassVehicle assetId={unclassed[0].id} classes={CLASSES} onchanged={onchanged} />
{:else}
	<ChoosePlan rates={cover.filed} onchanged={onchanged} />
{/if}
{/if}

<style>
	.page-head {
		margin-bottom: 32px;
	}

	h1 {
		font-size: clamp(28px, 5vw, 38px);
		overflow-wrap: anywhere;
	}

	.lead {
		color: var(--muted);
		margin-top: 8px;
		max-width: 620px;
	}

	.block {
		margin-top: 32px;
	}

	.block h2 {
		font-size: 22px;
	}

	.assets,
	.rates {
		list-style: none;
		margin: 12px 0 0;
		padding: 0;
		display: grid;
		gap: 8px;
	}

	.section-note {
		color: var(--muted);
		font-size: 15px;
		margin-top: 8px;
	}

	.note {
		margin-top: 16px;
		padding: 12px 16px;
		border: 1px dashed var(--border);
		border-radius: var(--radius);
		display: grid;
		gap: 6px;
	}
</style>
