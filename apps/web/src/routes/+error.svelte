<script lang="ts">
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { errorPageCopy } from '#lib/auth/errors.ts';

	// Shown when a page outside the member area fails, a link is dead, or the
	// member area's own layout couldn't load the account (routes/app/+layout.ts
	// sets a plain message). Errors inside a member page use app/+error.svelte,
	// which keeps the member nav.
	const copy = $derived(errorPageCopy(page.status, page.error?.message));
	let retrying = $state(false);
	let heading = $state<HTMLElement>();

	async function retry() {
		if (retrying) return;
		retrying = true;
		try {
			// Re-run every load for this URL; on success this page is replaced.
			await goto(page.url.href, { replaceState: true, invalidateAll: true });
		} finally {
			retrying = false;
			// Still failing: the button that had focus was re-rendered, so
			// park focus on the heading, which the alert re-announces from.
			heading?.focus();
		}
	}
</script>

<svelte:head>
	<title>{copy.title} · Kinfold</title>
</svelte:head>

<main id="main" tabindex="-1" class="wrap">
	<div class="box" role={copy.retry ? 'alert' : undefined}>
		<a class="lockup" href="/" aria-label="Kinfold home">
			<img src="/favicon.svg" alt="" width="32" height="32" />
			<span>Kinfold</span>
		</a>
		<h1 bind:this={heading} tabindex="-1">{copy.title}</h1>
		<p>{copy.body}</p>
		<!-- The site is a design preview everywhere a reader can land: landing and
             transparency carry the nav badge, but this page is standalone, so it
             states the status itself - otherwise a mistyped link reads as a live
             site that happens to be missing. -->
		<p class="status" role="note"><strong>Design preview.</strong> Kinfold isn’t open yet.</p>
		<div class="actions">
			{#if copy.retry}
				<button type="button" class="btn btn-primary" onclick={retry} aria-disabled={retrying}>
					{retrying ? 'Trying again…' : 'Try again'}
				</button>
			{/if}
			<a class="btn btn-ghost" href="/">Go to the Kinfold home page</a>
		</div>
	</div>
</main>

<style>
	.wrap {
		min-height: 100vh;
		min-height: 100dvh;
		display: flex;
		align-items: flex-start;
		justify-content: center;
		padding: clamp(24px, 10vh, 96px) 16px 40px;
		background: var(--bg);
	}

	.box {
		width: 100%;
		max-width: 520px;
		display: grid;
		gap: 16px;
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius);
		padding: 24px;
	}

	.lockup {
		display: inline-flex;
		align-items: center;
		gap: 10px;
		justify-self: start;
		min-height: 44px;
		font-weight: 700;
		font-size: 19px;
		color: var(--text);
		text-decoration: none;
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

	.status {
		margin-top: 4px;
		font-size: 13px;
	}

	.actions button[aria-disabled='true'] {
		opacity: 0.7;
		cursor: progress;
	}
</style>
