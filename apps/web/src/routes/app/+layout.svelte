<script lang="ts">
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { signOut } from '#lib/auth/session.ts';

	let { data, children } = $props();

	const canReview = $derived(
		data.viewer.roles.includes('reviewer') || data.viewer.roles.includes('panel')
	);

	const links = $derived([
		{ href: '/app', label: 'Home' },
		{ href: '/app/board', label: 'Board' },
		{ href: '/app/loans', label: 'Loans' },
		{ href: '/app/invite', label: 'Invites' },
		...(canReview ? [{ href: '/app/review', label: 'Review' }] : [])
	]);

	function isCurrent(href: string) {
		return href === '/app' ? page.url.pathname === '/app' : page.url.pathname.startsWith(href);
	}

	async function leave() {
		await signOut();
		await goto('/signin');
	}
</script>

<a class="skip" href="#main">Skip to content</a>
<header class="app-nav">
	<div class="container inner">
		<a class="brand" href="/app">
			<img src="/favicon.svg" alt="" width="28" height="28" />
			<span>Kinfold</span>
		</a>
		<nav aria-label="Member area">
			{#each links as link (link.href)}
				<a href={link.href} aria-current={isCurrent(link.href) ? 'page' : undefined}>{link.label}</a>
			{/each}
		</nav>
		<div class="me">
			<span class="name">{data.viewer.member?.display_name ?? data.viewer.session.user.email}</span>
			<button type="button" class="btn btn-ghost small" onclick={leave}>Sign out</button>
		</div>
	</div>
</header>
<main id="main" class="container app-main">
	{@render children()}
</main>

<style>
	.skip {
		position: absolute;
		left: -9999px;
	}

	.skip:focus {
		left: 16px;
		top: 8px;
		z-index: 20;
		background: var(--surface);
		padding: 8px 12px;
		border-radius: 8px;
	}

	.app-nav {
		position: sticky;
		top: 0;
		z-index: 10;
		background: color-mix(in srgb, var(--bg) 88%, transparent);
		backdrop-filter: blur(10px);
		border-bottom: 1px solid var(--border);
	}

	.inner {
		display: flex;
		align-items: center;
		gap: 24px;
		min-height: 60px;
		flex-wrap: wrap;
	}

	.brand {
		display: inline-flex;
		align-items: center;
		gap: 8px;
		font-weight: 700;
		color: var(--text);
		text-decoration: none;
	}

	nav {
		display: flex;
		flex-wrap: wrap;
		gap: 4px;
		flex: 1;
	}

	nav a {
		color: var(--muted);
		text-decoration: none;
		font-weight: 600;
		font-size: 15px;
		padding: 6px 10px;
		border-radius: 8px;
	}

	nav a:hover {
		color: var(--text);
	}

	nav a[aria-current='page'] {
		color: var(--accent);
		background: var(--accent-soft);
	}

	.me {
		display: flex;
		align-items: center;
		gap: 12px;
	}

	.name {
		font-weight: 600;
		font-size: 15px;
	}

	.small {
		padding: 6px 14px;
		font-size: 14px;
	}

	.app-main {
		padding-top: 32px;
		padding-bottom: 64px;
	}

	@media (max-width: 560px) {
		.inner {
			gap: 8px 16px;
			padding-top: 8px;
			padding-bottom: 8px;
		}

		nav {
			order: 3;
			flex-basis: 100%;
		}

		.me {
			margin-left: auto;
		}

		.name {
			display: none;
		}
	}
</style>
