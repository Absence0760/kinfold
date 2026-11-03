<script lang="ts">
	import { tick } from 'svelte';
	import { supabase } from '#lib/supabase/client.ts';
	import { setCoverPlan } from '#lib/cover/data.ts';
	import { explainCoverError } from '#lib/cover/errors.ts';
	import { formatCents } from '#lib/dashboard/format.ts';
	import Panel from './Panel.svelte';

	let { rates, onchanged }: {
		rates: { vehicle_class: string; plan: string; premium_cents: number; cap_cents: number }[];
		onchanged: (message: string) => Promise<void>;
	} = $props();

	const planWord = (plan: string) => (plan === 'standard' ? 'Standard' : 'Basic');

	/** What each plan would cost for THIS member's classed vehicles. */
	const options = $derived(
		['basic', 'standard'].map((plan) => {
			const filed = rates.filter((r) => r.plan === plan);
			const premium = filed.reduce((sum, r) => sum + r.premium_cents, 0);
			const cap = filed.length === 0 ? 0 : Math.min(...filed.map((r) => r.cap_cents));
			return {
				plan,
				label: planWord(plan),
				figures: filed.length === 0 ? 'no filed rate for your vehicles yet' : `${formatCents(premium)} premium · up to ${formatCents(cap)} per claim`,
			};
		})
	);

	type Step = 'closed' | 'confirm' | 'sending';
	let step = $state<Step>('closed');
	let chosen = $state('');
	let error = $state('');
	let openButton = $state<HTMLButtonElement>();
	let confirmTitle = $state<HTMLElement>();

	async function open() {
		error = '';
		step = 'confirm';
		await tick();
		confirmTitle?.focus();
	}

	async function close() {
		// The buttons stay focusable while sending (aria-disabled), so guard here.
		if (step === 'sending') return;
		step = 'closed';
		chosen = '';
		await tick();
		openButton?.focus();
	}

	async function send() {
		if (step === 'sending' || chosen === '') return;
		step = 'sending';
		error = '';
		try {
			await setCoverPlan(supabase(), chosen);
			const message = `Your plan is now ${planWord(chosen)}. The premiums the cooperative pays for your vehicles follow from that.`;
			step = 'closed';
			chosen = '';
			await onchanged(message);
		} catch (err) {
			error = explainCoverError(err as { message?: string; code?: string });
			// The failed choice stays put so the member can try again.
			step = 'confirm';
			await tick();
			confirmTitle?.focus();
		}
	}

	function pick(plan: string) {
		if (step === 'sending') return;
		chosen = plan;
	}
</script>

<Panel
	id="cover-plan-h"
	title="Choose your cover plan"
	intro="You only choose WHICH filed set of rates applies to your vehicles; the rates themselves are the partner insurer’s filed terms, and the premium money comes from dues."
>
	{#if step === 'closed'}
		<div class="actions">
			<button type="button" class="btn btn-ghost" bind:this={openButton} onclick={open}>Choose a plan</button>
		</div>
	{:else}
		<div class="step" role="group" aria-labelledby="cover-plan-confirm">
			<p class="confirm-title" id="cover-plan-confirm" tabindex="-1" bind:this={confirmTitle}>Which plan applies to your vehicles?</p>
			<!-- list-style:none removes list semantics in Safari; the role puts them back. -->
			<!-- svelte-ignore a11y_no_redundant_roles -->
			<ol class="options" role="list">
				{#each options as o}
					<li>
						<strong>{o.label}</strong>
						<span class="muted">{o.figures}</span>
						<button type="button" class="btn btn-ghost" onclick={() => pick(o.plan)} aria-disabled={step === 'sending'}>
							{o.label}
						</button>
					</li>
				{/each}
			</ol>
			{#if error}<p class="problem" role="alert">{error}</p>{/if}
			<div class="actions">
				<button type="button" class="btn btn-primary" onclick={send} aria-disabled={step === 'sending' || chosen === ''} aria-busy={step === 'sending'}>
					{step === 'sending' ? 'Saving…' : chosen === '' ? 'Pick a plan first' : `Use ${planWord(chosen)}`}
				</button>
				<button type="button" class="btn btn-ghost" onclick={close} aria-disabled={step === 'sending'}>Not now</button>
		 </div>
	</div>
	{/if}
</Panel>
