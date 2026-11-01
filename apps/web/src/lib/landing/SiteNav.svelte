<script lang="ts">
	import { dev } from '$app/env';
	import { navSections } from './sections.ts';

	// On phones the links live in a <details> menu, so it opens without
	// JavaScript on the prerendered page; picking a link closes it again.
	let menuOpen = $state(false);
</script>

<a class="skip-link" href="#main">Skip to content</a>

<header class="nav">
	<div class="container nav-inner">
		<a class="brand" href="/" aria-label="Kinfold home">
			<img src="/favicon.svg" alt="" width="30" height="30" />
			<span>Kinfold</span>
		</a>
		<nav class="links" aria-label="Sections">
			{#each navSections as s (s.id)}
				<a href="#{s.id}">{s.label}</a>
			{/each}
		</nav>
		<span class="badge">Design preview</span>
		<!-- The member area exists only against the local stack for now, so the
		     link is left out of the production build. -->
		{#if dev}
			<a class="signin" href="/signin">Sign in</a>
		{/if}
		<details class="menu" bind:open={menuOpen}>
			<summary aria-label="Menu">
				<svg width="22" height="22" viewBox="0 0 24 24" aria-hidden="true">
					{#if menuOpen}
						<path d="M6 6l12 12M18 6L6 18" />
					{:else}
						<path d="M4 7h16M4 12h16M4 17h16" />
					{/if}
				</svg>
			</summary>
			<nav aria-label="Sections, menu">
				{#each navSections as s (s.id)}
					<a href="#{s.id}" onclick={() => (menuOpen = false)}>{s.label}</a>
				{/each}
			</nav>
		</details>
	</div>
</header>

<style>
	.nav {
		position: sticky;
		top: 0;
		z-index: 10;
		background: color-mix(in srgb, var(--bg) 88%, transparent);
		backdrop-filter: blur(10px);
		border-bottom: 1px solid var(--border);
	}

	.nav-inner {
		display: flex;
		align-items: center;
		gap: 28px;
		height: var(--nav-h);
	}

	.brand {
		display: flex;
		align-items: center;
		gap: 10px;
		font-weight: 700;
		font-size: 19px;
		color: var(--text);
		text-decoration: none;
	}

	.links {
		display: flex;
		gap: 22px;
		margin-left: auto;
	}

	nav a {
		color: var(--muted);
		text-decoration: none;
		font-size: 15px;
		font-weight: 500;
	}

	nav a:hover {
		color: var(--text);
	}

	.badge {
		font-size: 12px;
		font-weight: 600;
		padding: 4px 10px;
		border-radius: 999px;
		background: var(--warm-soft);
		color: var(--warm);
		white-space: nowrap;
	}

	.signin {
		font-size: 15px;
		font-weight: 600;
		white-space: nowrap;
	}

	.menu {
		display: none;
	}

	summary {
		list-style: none;
		display: grid;
		place-items: center;
		width: 44px;
		height: 44px;
		border-radius: 10px;
		cursor: pointer;
		color: var(--text);
	}

	summary::-webkit-details-marker {
		display: none;
	}

	summary:hover {
		background: var(--surface-2);
	}

	summary path {
		fill: none;
		stroke: currentColor;
		stroke-width: 2;
		stroke-linecap: round;
	}

	.menu nav {
		position: absolute;
		left: 0;
		right: 0;
		top: var(--nav-h);
		display: grid;
		padding: 8px 20px 16px;
		background: var(--bg);
		border-bottom: 1px solid var(--border);
		box-shadow: var(--shadow);
	}

	.menu nav a {
		padding: 12px 0;
		font-size: 17px;
		color: var(--text);
		border-bottom: 1px solid var(--border);
	}

	.menu nav a:last-child {
		border-bottom: 0;
	}

	@media (max-width: 860px) {
		.links {
			display: none;
		}

		.badge {
			margin-left: auto;
		}

		.menu {
			display: block;
			margin-right: -10px;
		}

		.nav-inner {
			gap: 12px;
		}
	}
</style>
