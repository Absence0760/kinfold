<script lang="ts">
	import { formatCents } from '#lib/dashboard/format.ts';

	let { books, quarters, problem } = $props();
</script>

<svelte:head>
	<title>Open books · what the cooperative paid, month by month</title>
</svelte:head>

<h1 id="main">Open books</h1>
<p>
	Every month, the cooperative publishes its own totals: money paid out, what the repair fund
	allocated, and how many requests were paid. Small numbers stay hidden — a month shows its counts
	only once at least eleven requests were paid — because transparency should not unmask individuals.
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
