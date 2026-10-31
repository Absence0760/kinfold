<script lang="ts">
	import '../app.css';
	import SiteNav from '#lib/landing/SiteNav.svelte';
	import SiteFooter from '#lib/landing/SiteFooter.svelte';

	let { children } = $props();
</script>

<SiteNav />
<main>
	{@render children()}
</main>
<SiteFooter />
