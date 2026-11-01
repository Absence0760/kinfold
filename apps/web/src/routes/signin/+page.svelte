<script lang="ts">
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { safeNext } from '#lib/auth/next.ts';
	import { dev } from '$app/env';
	import { DEMO_ACCOUNTS, DEMO_PASSWORD, demoSignInAllowed } from '#lib/auth/demo-accounts.ts';
	import { classifySignInError, notConfiguredNotice, signInNotice, type Notice } from '#lib/auth/errors.ts';
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
	let error = $state<Notice | null>(null);
	// Only a wrong email or password marks the fields invalid; a dropped
	// connection or a rate limit isn't the member's typing.
	let badCredentials = $state(false);
	const missingKey = notConfiguredNotice(dev);
	let busy = $state<string | null>(null);

	$effect(() => {
		if (!configured) return;
		// Already signed in: skip the form. If the session can't be checked
		// (offline), stay on the form; signing in will say what's wrong.
		getSession().then(
			(s): void => {
				if (s) goto(next, { replaceState: true });
			},
			() => {}
		);
	});

	async function submit(asEmail: string, asPassword: string, key: string) {
		if (busy !== null) return;
		error = null;
		badCredentials = false;
		busy = key;
		try {
			await signIn(asEmail, asPassword);
			await goto(next);
		} catch (e) {
			// Wrong password, too many tries, unconfirmed email and a dropped
			// connection each get their own words; pnpm commands only in dev.
			error = signInNotice(e, dev);
			badCredentials = classifySignInError(e) === 'invalid-credentials';
		} finally {
			busy = null;
		}
	}
</script>

<svelte:head>
	<title>Sign in · Kinfold</title>
</svelte:head>

<div class="auth">
	<main id="main" tabindex="-1" class="side-form">
		<div class="form-box">
			<a class="lockup" href="/" aria-label="Kinfold home">
				<img src="/favicon.svg" alt="" width="36" height="36" />
				<span>Kinfold</span>
			</a>

			<h1>Sign in</h1>
			<p class="intro">Welcome back. Your requests, loans and private giving record are here.</p>

			{#if !configured}
				<p class="notice" role="alert">
					{missingKey.text}{#if missingKey.command}{' '}<code>{missingKey.command}</code>{/if}
				</p>
			{:else}
				{#if error}
					<p class="notice" role="alert" id="signin-error">
						{error.text}{#if error.command}{' '}<code>{error.command}</code>.{/if}
					</p>
				{/if}

				<form
					class="form"
					aria-busy={busy === 'form'}
					onsubmit={(e) => {
						e.preventDefault();
						submit(email, password, 'form');
					}}
				>
					<label>
						Email
						<input
							type="email"
							autocomplete="email"
							autocapitalize="off"
							spellcheck="false"
							required
							bind:value={email}
							readonly={busy !== null}
							aria-invalid={badCredentials ? 'true' : undefined}
							aria-describedby={error ? 'signin-error' : undefined}
						/>
					</label>
					<label>
						Password
						<input
							type="password"
							autocomplete="current-password"
							required
							bind:value={password}
							readonly={busy !== null}
							aria-invalid={badCredentials ? 'true' : undefined}
							aria-describedby={error ? 'signin-error' : undefined}
						/>
					</label>
					<button class="btn btn-primary" type="submit" aria-disabled={busy !== null}>
						{busy === 'form' ? 'Signing in…' : 'Sign in'}
					</button>
				</form>

				<!-- No sign-up yet: membership is invitation-only while that
				     product decision is pending. -->
				<p class="join">
					<strong>New to Kinfold?</strong> Joining is by invitation for now. If a member sent you an
					invitation link, open that link to join.
				</p>

				<!-- Dev only, and kept out of the way: a collapsed strip under the
				     form, so the page reads like the real sign-in. -->
				{#if showDemo}
					<details class="demo">
						<summary>Dev: sign in as a demo account</summary>
						<p class="hint">Seeded by <code>pnpm dev:db:reset</code>. Local development only.</p>
						<ul>
							{#each DEMO_ACCOUNTS as account (account.email)}
								<li>
									<span class="who">
										<strong>{account.name}</strong>
										<span class="roles">{account.roles}</span>
										<span class="summary">{account.summary}</span>
									</span>
									<button
										type="button"
										class="use"
										aria-disabled={busy !== null}
										aria-busy={busy === account.email}
										onclick={() => submit(account.email, DEMO_PASSWORD, account.email)}
									>
										{busy === account.email ? 'Signing in…' : 'Use'}<span class="visually-hidden">
											{busy === account.email ? '' : ` ${account.name}'s account`}</span
										>
									</button>
								</li>
							{/each}
						</ul>
					</details>
				{/if}
			{/if}
		</div>
	</main>

	<!-- After the form in the DOM so the page's h1 comes first; shown on the left. -->
	<aside class="panel-brand" aria-label="About Kinfold">
		<svg class="art" viewBox="0 0 400 300" preserveAspectRatio="xMidYMax slice" aria-hidden="true">
			<!-- Overlapping folds: many hands holding one load. -->
			<path class="fold f1" d="M-20 300 L120 150 L260 300Z" />
			<path class="fold f2" d="M80 300 L230 120 L380 300Z" />
			<path class="fold f3" d="M200 300 L330 170 L460 300Z" />
			<path class="roof" d="M196 172 L230 140 L264 172" />
			<rect class="door" x="221" y="200" width="18" height="30" rx="2" />
		</svg>
		<div class="copy">
			<p class="kicker">Kinfold</p>
			<h2>Help paid by people, not profit.</h2>
			<ul>
				<li>No interest and no late fees, ever.</li>
				<li>Kinfold never holds your money. Requests pay the shop or lender.</li>
				<li>Scores explain the evidence. Only a person can say no.</li>
			</ul>
		</div>
	</aside>
</div>

<style>
	.auth {
		display: grid;
		grid-template-columns: minmax(0, 55fr) minmax(0, 45fr);
		min-height: 100vh;
		min-height: 100dvh;
	}

	/* Contrast on the light ground (--accent-soft): heading and bullets use
	   --text (≥12:1), the kicker --accent 5.4:1; dark: --accent 6.5:1. */
	.panel-brand {
		order: -1;
		position: sticky;
		top: 0;
		max-height: 100dvh;
		overflow: hidden;
		background: var(--accent-soft);
		color: var(--text);
	}

	.art {
		position: absolute;
		inset: auto 0 0 0;
		width: 100%;
		height: 60%;
	}

	.fold {
		fill: var(--accent);
	}

	.f1 {
		opacity: 0.18;
	}

	.f2 {
		opacity: 0.3;
	}

	.f3 {
		opacity: 0.14;
	}

	.roof {
		fill: none;
		stroke: var(--warm);
		stroke-width: 6;
		stroke-linecap: round;
		stroke-linejoin: round;
	}

	.door {
		fill: var(--warm);
		opacity: 0.85;
	}

	.copy {
		position: relative;
		max-width: 30rem;
		padding: clamp(24px, 6vh, 64px) clamp(24px, 5vw, 64px);
	}

	.kicker {
		margin-bottom: 12px;
		font-weight: 700;
		font-size: 14px;
		letter-spacing: 0.12em;
		text-transform: uppercase;
		color: var(--accent);
	}

	.copy h2 {
		font-size: clamp(26px, 2.6vw, 36px);
		line-height: 1.15;
		margin-bottom: 20px;
	}

	.copy ul {
		list-style: none;
		margin: 0;
		padding: 0;
		display: grid;
		gap: 10px;
	}

	.copy li {
		position: relative;
		padding-left: 22px;
	}

	.copy li::before {
		content: '';
		position: absolute;
		left: 0;
		top: 0.55em;
		width: 8px;
		height: 8px;
		border-radius: 50%;
		background: var(--accent);
	}

	/* The form starts on the brand copy's top line, so the title doesn't jump
	   when an error appears above the form. */
	.side-form {
		display: flex;
		align-items: flex-start;
		justify-content: center;
		padding: clamp(24px, 6vh, 64px) 20px 40px;
		background: var(--surface);
	}

	.form-box {
		width: 100%;
		max-width: 440px;
		display: grid;
		gap: 20px;
	}

	.lockup {
		display: inline-flex;
		align-items: center;
		gap: 10px;
		justify-self: start;
		font-weight: 700;
		font-size: 21px;
		color: var(--text);
		text-decoration: none;
		margin-bottom: 8px;
	}

	h1 {
		font-size: 30px;
	}

	.intro {
		color: var(--muted);
		margin-top: -12px;
	}

	.hint {
		color: var(--muted);
		font-size: 14px;
	}

	.join {
		color: var(--muted);
		font-size: 15px;
	}

	.join strong {
		color: var(--text);
	}

	.notice {
		background: var(--warm-soft);
		color: var(--text);
		border: 1px solid var(--warm);
		border-radius: var(--radius);
		padding: 12px 16px;
	}

	.form {
		display: grid;
		gap: 14px;
	}

	label {
		display: grid;
		gap: 6px;
		font-weight: 600;
		font-size: 15px;
	}

	input {
		font: inherit;
		min-height: 44px;
		padding: 10px 12px;
		border-radius: 10px;
		border: 1px solid var(--field-border);
		background: var(--surface);
		color: var(--text);
	}

	input[aria-invalid='true'] {
		border-color: var(--warm);
	}

	.form .btn {
		width: 100%;
		margin-top: 6px;
		font-size: 16px;
	}

	.form .btn[aria-disabled='true'],
	.use[aria-disabled='true'] {
		opacity: 0.7;
		cursor: progress;
	}

	/* Dev shortcut: small, dashed, collapsed. */
	.demo {
		border: 1px dashed var(--border);
		border-radius: var(--radius);
		background: var(--surface-2);
		color: var(--muted);
		font-size: 14px;
	}

	.demo summary {
		cursor: pointer;
		padding: 10px 14px;
		min-height: 44px;
		display: flex;
		align-items: center;
		font-weight: 600;
	}

	.demo[open] summary {
		border-bottom: 1px dashed var(--border);
	}

	.demo .hint {
		padding: 10px 14px 0;
	}

	.demo ul {
		list-style: none;
		margin: 0;
		padding: 6px 14px 10px;
		display: grid;
	}

	.demo li {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 12px;
		padding: 6px 0;
	}

	.demo li + li {
		border-top: 1px solid var(--border);
	}

	.who {
		display: flex;
		flex-wrap: wrap;
		align-items: baseline;
		gap: 0 8px;
		min-width: 0;
	}

	.who strong {
		color: var(--text);
		font-weight: 600;
	}

	.summary {
		flex-basis: 100%;
	}

	.use {
		flex: none;
		min-height: 44px;
		min-width: 44px;
		padding: 6px 12px;
		border: 1px solid var(--border);
		border-radius: 999px;
		background: var(--surface);
		color: var(--text);
		font: inherit;
		font-weight: 600;
		cursor: pointer;
	}

	.use:hover:not([aria-disabled='true']) {
		border-color: var(--accent);
	}

	/* Phones: the panel is a short band, so the title and first field stay
	   above the keyboard. */
	@media (max-width: 900px) {
		.auth {
			grid-template-columns: minmax(0, 1fr);
			grid-template-rows: auto 1fr;
		}

		.panel-brand {
			position: relative;
			height: 84px;
		}

		.art {
			height: 100%;
		}

		.copy {
			display: none;
		}

		.side-form {
			padding-top: 24px;
		}
	}
</style>
