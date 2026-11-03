<script lang="ts">
	import { tick } from 'svelte';
	import { supabase } from '#lib/supabase/client.ts';
	import { classCoverVehicle } from '#lib/cover/data.ts';
	import { explainCoverError } from '#lib/cover/errors.ts';
	import Panel from './Panel.svelte';

	let { assetId, classes, onchanged }: {
		assetId: string;
		classes: string[];
		onchanged: (message: string) => Promise<void>;
	} = $props();

	const classWord = (c: string) =>
		({ micro_car: 'Micro-car', sedan: 'Sedan', suv: 'SUV', pickup: 'Pickup', van: 'Van' })[c] ?? c;

	type Step = 'closed' | 'confirm' | 'sending';
	let step = $state<Step>('closed');
	let chosen = $state('');
	let error = $state('');
	let openButton = $state<HTMLButtonElement>();
	let confirmTitle = $state<HTMLElement>();

	async function open() {
		error = '';
		chosen = '';
		step = 'confirm';
		await tick();
		confirmTitle?.focus();
	}

	async function close() {
		if (step === 'sending') return;
		step = 'closed';
		chosen = '';
		await tick();
		openButton?.focus();
	}

	function pick(c: string) {
		if (step === 'sending') return;
		chosen = c;
	}

	async function send() {
		if (step === 'sending' || chosen === '') return;
		step = 'sending';
		error = '';
		try {
			await classCoverVehicle(supabase(), assetId, chosen);
			step = 'closed';
			await onchanged(`The class on this vehicle is now ${classWord(chosen)}. Its premium follows the filed rate for that class.`);
		} catch (err) {
			error = explainCoverError(err as { message?: string; code?: string });
			step = 'confirm';
			await tick();
			confirmTitle?.focus();
		}
	}
</script>

<Panel
	id="cover-class-{assetId}"
	title="State the class on this vehicle"
	intro="The rating-law class decides which filed premium applies. Only the owner states it, and it changes nothing about the vehicle itself."
>
	{#if step === 'closed'}
		<div class="actions">
			<button type="button" class="btn btn-ghost" bind:this={openButton} onclick={open}>State the class</button>
		</div>
	{:else}
		<div class="step" role="group" aria-labelledby="cover-class-{assetId}-confirm">
			<p class="confirm-title" id="cover-class-{assetId}-confirm" tabindex="-1" bind:this={confirmTitle}>Which rating-law class is it?</p>
			<!-- list-style:none removes list semantics in Safari; the role puts them back. -->
			<!-- svelte-ignore a11y_no_redundant_roles -->
			<ul class="options" role="list">
				{#each classes as c}
					<li>
						<button type="button" class="btn btn-ghost" onclick={() => pick(c)} aria-disabled={step === 'sending'}>
							{classWord(c)}
						</button>
					</li>
				{/each}
			</ul>
			{#if error}<p class="problem" role="alert">{error}</p>{/if}
			<div class="actions">
				<button type="button" class="btn btn-primary" onclick={send} aria-disabled={step === 'sending' || chosen === ''} aria-busy={step === 'sending'}>
					{step === 'sending' ? 'Saving…' : chosen === '' ? 'Pick a class first' : `Class it ${classWord(chosen)}`}
				</button>
				<button type="button" class="btn btn-ghost" onclick={close} aria-disabled={step === 'sending'}>Not now</button>
			</div>
		</div>
	{/if}
</Panel>
