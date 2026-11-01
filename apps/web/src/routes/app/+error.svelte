<script lang="ts">
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { errorPageCopy } from '#lib/auth/errors.ts';

	// A member page's load failed. Rendered inside app/+layout.svelte, so the
	// member nav (and <main>) stay; a failure in the layout itself shows
	// routes/+error.svelte instead.
	const copy = $derived(errorPageCopy(page.status, page.error?.message));
	const onHome = $derived(page.url.pathname === '/app');
	let retrying = $state(false);
	let heading = $state<HTMLElement>();

	async function retry() {
		if (retrying) return;
		retrying = true;
		try {
			await goto(page.url.href, { replaceState: true, invalidateAll: true });
		} finally {
			retrying = false;
			heading?.focus();
		}
	}
</script>

<svelte:head>
	<title>{copy.title} · Kinfold</title>
</svelte:head>

<div class="box" role={copy.retry ? 'alert' : undefined}>
	<h1 bind:this={heading} tabindex="-1">{copy.title}</h1>
	<p>{copy.body}</p>
	<div class="actions">
		{#if copy.retry}
			<button type="button" class="btn btn-primary" onclick={retry} aria-disabled={retrying}>
				{retrying ? 'Trying again…' : 'Try again'}
			</button>
		{/if}
		{#if !onHome}
			<a class="btn btn-ghost" href="/app">Go to your home</a>
		{/if}
	</div>
</div>

<style>
	.box {
		max-width: 620px;
		display: grid;
		gap: 14px;
		justify-items: start;
		background: var(--surface);
		border: 1px solid var(--warm);
		border-radius: var(--radius);
		padding: 20px;
	}

	h1 {
		font-size: clamp(24px, 5vw, 30px);
	}

	h1:focus {
		outline: none;
	}

	p {
		color: var(--muted);
	}

	.actions {
		display: flex;
		flex-wrap: wrap;
		gap: 10px;
	}

	.actions button[aria-disabled='true'] {
		opacity: 0.7;
		cursor: progress;
	}
</style>
