<script lang="ts">
	import { fairLenderHeading } from '#lib/requests/lender-help.ts';
	let { lines } = $props();
	// The copy lives in the lib module so vitest can pin what this page offers a member:
	// it points at a fair lender of record and prices nothing (RESPA section 8).
</script>

<div class="panel" data-testid="fair-lender">
	<h3 class="inline">{fairLenderHeading}</h3>
	<p class="fine">
		Anything the bank still owes you sits with a lender, so Kinfold points you at a fair one rather
		than holding that mortgage:
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
