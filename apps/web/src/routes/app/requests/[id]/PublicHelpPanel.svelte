<script lang="ts">
	import type { CertifiedCounsel } from '#lib/transparency/data.ts';
	import { publicHelpCounselLine, publicHelpHeading } from '#lib/requests/public-help.ts';

	// The published agency (housing_counsel) read beside a mortgage gap's help:
	// when a certified agency stands, the panel names it rather than pointing at
	// counselors in general. A failed read is this affordance's to explain - the
	// request and its figures never depend on it.
	let { counsel, problem }: { counsel: CertifiedCounsel | null; problem: string | null } = $props();
</script>

<div class="panel" data-testid="public-help">
	<h3 class="inline">{publicHelpHeading}</h3>
	{#if problem}<p class="problem" role="alert">{problem}</p>{/if}
	<p class="fine">
		A mortgage gap is money the bank can help without anyone re-paying it, so Kinfold points you at
		the public help that sits beside it rather than taking their money:
	</p>
	<ul class="list">
		<li class="fine">
			<strong>HUD-approved housing counselors.</strong>
			{publicHelpCounselLine(counsel)}
			{#if counsel}
				<a href={counsel.contactUrl}>{counsel.agencyName}</a>.
			{/if}
		</li>
		<li class="fine">
			<strong>State and federal repair help</strong> when keeping the home needs work: FEMA,
			SBA and USDA disaster-rebuilding help, and the state housing finance agency where it
			offers grants. Any of that money moves outside the Fund and under that programme’s own
			terms — it never joins this request.
		</li>
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