<script lang="ts">
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { safeNext } from '#lib/auth/next.ts';
	import { dev } from '$app/env';
	import { DEMO_ACCOUNTS, DEMO_PASSWORD, demoSignInAllowed } from '#lib/auth/demo-accounts.ts';
	import { getSession, signIn } from '#lib/auth/session.ts';
	import { isConfigured, supabaseUrl } from '#lib/supabase/client.ts';

	const configured = isConfigured();
	// Back to the page that sent you here (an invite link, say), never off-site.
	const next = safeNext(page.url.searchParams.get('next'));
	// `dev &&` first: `dev` is a build-time constant, so a production build drops
	// the demo list (and its password) entirely.
	const showDemo = dev && demoSignInAllowed(dev, supabaseUrl);

	let email = $state('');
	let password = $state('');
	let error = $state('');
	let busy = $state<string | null>(null);

	$effect(() => {
		if (!configured) return;
		getSession().then((s): void => {
			if (s) goto(next, { replaceState: true });
		});
	});

	async function submit(asEmail: string, asPassword: string, key: string) {
		error = '';
		busy = key;
		try {
			await signIn(asEmail, asPassword);
			await goto(next);
		} catch (e) {
			error =
				e instanceof Error && /fetch/i.test(e.message)
					? "Can't reach the local backend. Start it with `pnpm dev:db:up`."
					: 'That email and password don’t match an account.';
		} finally {
			busy = null;
		}
	}
</script>

<svelte:head>
	<title>Sign in · Kinfold</title>
</svelte:head>

<main id="main" tabindex="-1" class="signin container">
	<a class="brand" href="/">
		<img src="/favicon.svg" alt="" width="30" height="30" />
		<span>Kinfold</span>
	</a>

	<h1>Sign in</h1>

	{#if !configured}
		<p class="notice" role="alert">
			The member area has no Supabase key. Start it with <code>pnpm dev:run:web</code>, which
			reads the key from the running local stack.
		</p>
	{:else}
		{#if error}
			<p class="notice" role="alert">{error}</p>
		{/if}

		{#if showDemo}
			<section class="demo" aria-labelledby="demo-heading">
				<h2 id="demo-heading">Demo accounts</h2>
				<p class="hint">Local development only. Seeded by <code>pnpm dev:db:reset</code>.</p>
				<ul>
					{#each DEMO_ACCOUNTS as account (account.email)}
						<li>
							<button
								type="button"
								class="demo-account"
								disabled={busy !== null}
								aria-busy={busy === account.email}
								onclick={() => submit(account.email, DEMO_PASSWORD, account.email)}
							>
								<span class="who">
									<strong>{account.name}</strong>
									<span class="roles">{account.roles}</span>
								</span>
								<span class="summary">{account.summary}</span>
								<span class="go" aria-hidden="true">
									{busy === account.email ? 'Signing in…' : 'Sign in →'}
								</span>
							</button>
						</li>
					{/each}
				</ul>
			</section>
		{/if}

		<form
			class="form"
			onsubmit={(e) => {
				e.preventDefault();
				submit(email, password, 'form');
			}}
		>
			{#if showDemo}<h2>Or with an email</h2>{/if}
			<label>
				Email
				<input type="email" autocomplete="email" required bind:value={email} />
			</label>
			<label>
				Password
				<input type="password" autocomplete="current-password" required bind:value={password} />
			</label>
			<button class="btn btn-primary" type="submit" disabled={busy !== null}>
				{busy === 'form' ? 'Signing in…' : 'Sign in'}
			</button>
		</form>
	{/if}
</main>

<style>
	.signin {
		max-width: 560px;
		padding-top: 48px;
		padding-bottom: 64px;
		display: grid;
		gap: 24px;
	}

	.brand {
		display: inline-flex;
		align-items: center;
		gap: 10px;
		font-weight: 700;
		font-size: 18px;
		color: var(--text);
		text-decoration: none;
		justify-self: start;
	}

	h1 {
		font-size: 32px;
	}

	h2 {
		font-size: 18px;
	}

	.hint {
		color: var(--muted);
		font-size: 14px;
		margin-top: 4px;
	}

	.notice {
		background: var(--warm-soft);
		color: var(--text);
		border: 1px solid var(--warm);
		border-radius: var(--radius);
		padding: 12px 16px;
	}

	.demo ul {
		list-style: none;
		padding: 0;
		margin: 14px 0 0;
		display: grid;
		gap: 10px;
	}

	.demo-account {
		width: 100%;
		display: grid;
		grid-template-columns: 1fr auto;
		gap: 4px 16px;
		text-align: left;
		padding: 14px 16px;
		background: var(--surface);
		color: var(--text);
		border: 1px solid var(--border);
		border-radius: var(--radius);
		font: inherit;
		cursor: pointer;
	}

	.demo-account:hover:not(:disabled) {
		border-color: var(--accent);
	}

	.demo-account:disabled {
		cursor: progress;
		opacity: 0.7;
	}

	.who {
		display: flex;
		flex-wrap: wrap;
		align-items: baseline;
		gap: 4px 10px;
	}

	.roles {
		color: var(--muted);
		font-size: 14px;
	}

	.summary {
		grid-column: 1;
		color: var(--muted);
		font-size: 14px;
	}

	.go {
		grid-column: 2;
		grid-row: 1 / span 2;
		align-self: center;
		color: var(--accent);
		font-weight: 600;
		font-size: 14px;
		white-space: nowrap;
	}

	.form {
		display: grid;
		gap: 14px;
		padding-top: 8px;
	}

	label {
		display: grid;
		gap: 6px;
		font-weight: 600;
		font-size: 14px;
	}

	input {
		font: inherit;
		padding: 10px 12px;
		border-radius: 10px;
		border: 1px solid var(--border);
		background: var(--surface);
		color: var(--text);
	}

	.form .btn {
		justify-self: start;
	}

	@media (max-width: 480px) {
		.demo-account {
			grid-template-columns: 1fr;
		}

		.go {
			grid-column: 1;
			grid-row: auto;
		}
	}
</style>
