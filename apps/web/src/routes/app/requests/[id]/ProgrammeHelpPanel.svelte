<script lang="ts">
	import { programHelpHeading } from '#lib/requests/program-help.ts';
	let { lines } = $props();
	// The copy lives in the lib module so vitest can pin what this page offers a
	// member: it points at state and city programmes and administers none of
	// their paper (roadmap 3g; design.md, "Public money stays in the funder's name").
</script>

<div class="panel" data-testid="programme-help">
	<h3 class="inline">{programHelpHeading}</h3>
	<p class="fine">
		Help a state agency or a city offers is that programme's own money under its own rules, so Kinfold
		points at it rather than holding it:
	</p>
	<ul class="list">
		{#each lines as line}
			<li class="fine">
				<strong>{line.title}</strong>
				{line.body}
			</li>
		{/each}
	</ul>
</div>

<style>
	.panel {
		display: grid;
		gap: 8px;
	}

	.panel h3 {
		font-size: 15px;
	}

	.panel p,
	.panel li {
		gap: 0;
	}

	.panel strong {
		white-space: nowrap;
	}
</style>