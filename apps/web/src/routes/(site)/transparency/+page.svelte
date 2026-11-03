<script lang="ts">
	import { formatCents } from '#lib/dashboard/format.ts';
import { reachShareBps, shareWord } from '#lib/transparency/data.ts';
import { formatDay } from '#lib/dashboard/format.ts';
import { counselorAsks } from '#lib/requests/public-help.ts';

	// A page's `$props()` is the page context: the load result sits under `data` (see the other route pages).
	let { data } = $props();
</script>

<svelte:head>
	<title>Open books · what the cooperative paid, month by month</title>
</svelte:head>

<h1>Open books</h1>
<p>
	Every month, the cooperative publishes its own totals: money paid out, what the repair fund
	allocated, and how many requests were paid. Small numbers stay hidden — a month shows its counts
	only once at least eleven requests were paid — because transparency should not unmask individuals.
	The fairness measure below names the share of a fund's granted money that reached households with no family lender
	of their own.
	Quarters below are the published months summed; a quarter with fewer than three published months
	says how many months it covers. The share rule says what part of a repair a member carries themselves; the grant report lists the money funders have reported in, and the counselor names the one agency
	the Fund partners with to keep a stalled mortgage at the bank.
</p>

{#if data.problem}
	<p class="problem">{data.problem}</p>
{:else if data.books.length === 0}
	<p class="empty">No month has passed its settlement lag yet — the first month's books publish once it is seven days over.</p>
{:else}
	{#each data.books as book}
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
{#if data.problem || data.quarters.length === 0}
	<p class="empty">No quarters reported yet.</p>
{:else}
	{#each data.quarters as q}
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
{#if data.formulaProblem}
	<p class="empty">{data.formulaProblem}</p>
{:else if data.formulas.length === 0}
	<p class="empty">No needs formula has been published yet.</p>
{:else}
	<ul class="formulas">
		{#each data.formulas as f}
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

<h2 id="share">The share rule: what a member carries themselves</h2>
{#if data.shareProblem}
	<p class="empty">{data.shareProblem}</p>
{:else if data.shareRules.length === 0}
	<p class="empty">No share rule has been published yet.</p>
{:else}
	<ul>
		{#each data.shareRules as r}
			<li>
				Version {r.version}, used from {r.effectiveFrom}: {shareWord(r.shareStepBps)} of what a request still
				needs moves to the member's own share per pool request they had paid in three years, up to
				{shareWord(r.shareCapBps)}.
			</li>
		{/each}
	</ul>
	<p class="note">
		How often a member's pool requests were paid sets how much of the next repair they carry themselves: the
		fund's grant to them shrinks by that share and they pay the rest. A smaller grant is never a refusal and
		never a wait. Older versions stay listed so a member can ask which rule priced their share.
	</p>
{/if}

<h2 id="counsel">The certified housing counselor</h2>
{#if data.counselProblem}
	<p class="empty">{data.counselProblem}</p>
{:else if data.counsel === null}
	<p class="empty">No certified agency is in effect yet — the Fund names one only with its certification on paper.</p>
{:else}
	<ul class="counsel">
		<li>
			<strong>{data.counsel.agencyName}</strong>, certified under {data.counsel.certifiedUnder} and
			HUD-approved on {formatDay(data.counsel.hudApprovedOn)}, the agency the Fund partners with since
			{formatDay(data.counsel.effectiveFrom)}; its own contact page:
			<a href={data.counsel.contactUrl}>{data.counsel.agencyName}</a>.
		</li>
	</ul>
	<p class="note">
		Keeping a mortgage the bank already holds is the bank's to decide, so Kinfold never becomes a counselor and
		never asks one on a member's behalf: it names the one agency it partners with, and the member goes to theirs
		asking for {counselorAsks}. Older versions stay
		listed in the table so a fairness auditor can ask which agency was named beside a request.
	</p>
{/if}

<h2 id="reach">Help reaching families without a family lender</h2>
{#if data.problem || data.books.length === 0}
	<p class="empty">No month has published its fairness share yet.</p>
{:else}
	<ul class="reach">
		{#each data.books as book}
			{@const share = reachShareBps(book.monthlyPoolRequests, book.allocatedCents, book.noLenderCents)}
			<li>
				{book.yearMonth} · {book.fundLabel}:
				{#if share === null}
					not enough granted requests to publish a share yet.
				{:else}
					{shareWord(share)} of the money the fund granted went to members with no family loan of their own.
				{/if}
			</li>
		{/each}
	</ul>
	<p class="note">
		The biggest risk for a fund is mostly helping families who could already lean on relatives. This measure answers
		how much of the granted money reached households that had no family lender: a family loan that never carried money
		— proposed, or cancelled — never counts as a lender, and the month behind a published share carries at least
		thirty granted requests.
	</p>
{/if}

<h2 id="grants">The grant report</h2>
{#if data.grantProblem}
	<p class="empty">{data.grantProblem}</p>
{:else if data.grants.length === 0}
	<p class="empty">No grant money has been reported in yet.</p>
{:else}
	<ul>
		{#each data.grants as g}
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
