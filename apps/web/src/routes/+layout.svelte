<script lang="ts">
	import { onMount } from 'svelte';
	import '../app.css';

	let { children } = $props();

	// The prerendered HTML is readable before the app hydrates, but the
	// controls (sliders, the phone menu's close-on-pick) only work after.
	// `<html data-hydrated>` marks that moment, so the e2e tests wait on a real
	// signal instead of a sleep.
	onMount(() => {
		document.documentElement.dataset.hydrated = 'true';
	});
</script>

{@render children()}
