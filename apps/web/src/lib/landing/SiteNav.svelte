<script lang="ts">
	const links = [
		{ href: '#requests', label: 'How it works' },
		{ href: '#board', label: 'Requests' },
		{ href: '#calculator', label: 'Savings' },
		{ href: '#principles', label: 'Principles' },
		{ href: '#roadmap', label: 'Roadmap' }
	];
</script>

<header class="nav">
	<div class="container nav-inner">
		<a class="brand" href="/" aria-label="Kinfold home">
			<img src="/favicon.svg" alt="" width="30" height="30" />
			<span>Kinfold</span>
		</a>
		<nav aria-label="Sections">
			{#each links as link (link.href)}
				<a href={link.href}>{link.label}</a>
			{/each}
		</nav>
		<span class="badge">Design preview</span>
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
		height: 64px;
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

	nav {
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

	@media (max-width: 760px) {
		nav {
			display: none;
		}

		.badge {
			margin-left: auto;
		}
	}
</style>
