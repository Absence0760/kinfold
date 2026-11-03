<script lang="ts">
	import { formatCents } from '#lib/dashboard/format.ts';
	import { shareWord } from '#lib/transparency/data.ts';

	let { books, quarters, problem, formulas, formulaProblem, grants, grantProblem } = $props();
</script>

<svelte:head>
	<title>Open books · what the cooperative paid, month by month</title>
</svelte:head>

<h1 id="main">Open books</h1>
<p>
	Every month, the cooperative publishes its own totals: money paid out, what the repair fund
	allocated, and how many requests were paid. Small numbers stay hidden — a month shows its counts
	only once at least eleven requests were paid — because transparency should not unmask individuals.
	Quarters below are the published months summed; a quarter with fewer than three published months
	says how many months it covers. The grant report at the bottom lists the money funders have reported in.
</p>

{#if problem}
	<p class="problem">{problem}</p>
{:else if books.length === 0}
	<p class="empty">No month has passed its settlement lag yet — the first month's books publish once it is seven days over.</p>
{:else}
	{#each books as book}
		<div class="book">
			<h2>{book.yearMonth} · {book.fundLabel}</h2>
			<dl>
				<dt>Requests paid</dt>
				<dd>{book.monthlyRequestsPaid}</dd>
				<dt>Money paid out</dt>
				<dd>{formatCents(book.paidOutCents)}</dd>
				<dt>Repair fund allocated</dt>
				<dd>{formatCents(book.allocatedCents)}</dd>
				<dt>Kept in reserve</dt>
				<dd>{formatCents(book.reserveCents)}</dd>
				<dt>Pool runs</dt>
				<dd>{book.monthlyPoolRuns} ({book.monthlyPoolRunsShort} short)</dd>
			</dl>
		</div>
	{/each}
{/if}

<h2 id="quarters">The quarterly report</h2>
{#if problem || quarters.length === 0}
	<p class="empty">No quarters reported yet.</p>
{:else}
	{#each quarters as q}
		<div class="quarter">
			<h3>{q.quarter} · {q.fundLabel}</h3>
			<dl>
				<dt>Requests paid</dt>
				<dd>{q.requestsPaid}</dd>
				<dt>Money paid out</dt>
				<dd>{formatCents(q.paidOutCents)}</dd>
				<dt>Repair fund allocated</dt>
				<dd>{formatCents(q.allocatedCents)}</dd>
				<dt>Kept in reserve</dt>
				<dd>{formatCents(q.reserveCents)}</dd>
				<dt>Pool runs</dt>
				<dd>{q.poolRuns} ({q.poolRunsShort} short)</dd>
				<dt>Months published</dt>
				<dd>{q.months} of 3</dd>
			</dl>
		</div>
	{/each}
{/if}

<h2 id="formula">How members are chosen</h2>
{#if formulaProblem}
	<p class="empty">{formulaProblem}</p>
{:else if formulas.length === 0}
	<p class="empty">No needs formula has been published yet.</p>
{:else}
	<ul class="formulas">
		{#each formulas as f}
			<li>
				Version {f.version}, used from {f.effectiveFrom}: need {shareWord(f.needBps)}, readiness
				{shareWord(f.readinessBps)}, reliability {shareWord(f.reliabilityBps)}.
			</li>
		{/each}
	</ul>
	<p class="note">
		The weights are public and the score behind any place in the queue can be re-derived from them; the inputs
		that feed them stay private to the member. Older versions stay listed so a member can ask which formula
		priced their place.
	</p>
{/if}

<h2 id="grants">The grant report</h2>
{#if grantProblem}
	<p class="empty">{grantProblem}</p>
{:else if grants.length === 0}
	<p class="empty">No grant money has been reported in yet.</p>
{:else}
	<ul>
		{#each grants as g}
			<li>
				{g.fundLabel} from {g.source}{g.federal ? ' (federally funded)' : ''}: {formatCents(g.amountCents)} across
				{g.grants} grant{g.grants === 1 ? '' : 's'}.
			</li>
		{/each}
	</ul>
	<p class="note">
		Grant money funds the cooperative, never a list of chosen families: it reaches a fund's dues and premiums
		pots and its own labelled grant pots, and it never joins the money the repair fund allocates from. Federally
		funded money is kept as its own pot (2 CFR 200) and never enters insured cover.
	</p>
{/if}
