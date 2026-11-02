<script lang="ts">
	import { formatCents } from '#lib/dashboard/format.ts';

	let { books, problem } = $props();
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
