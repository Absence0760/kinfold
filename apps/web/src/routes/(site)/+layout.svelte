<script lang="ts">
	import SiteNav from '#lib/landing/SiteNav.svelte';
	import SiteFooter from '#lib/landing/SiteFooter.svelte';

	let { children } = $props();
</script>

<SiteNav />
<main id="main">
	{@render children()}
</main>
<SiteFooter />
