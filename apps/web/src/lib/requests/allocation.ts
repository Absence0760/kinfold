// How the community repair fund (gifts and grants, not insured cover) is shared
// out across open requests.
//
// Requests are grouped into evidence bands (90-100, 80-89, ...). The highest
// band is filled first, and every request inside a band is filled at the same
// time: if the pool can't cover the whole band, each request gets the same
// share of what it still needs. Requests below `minScore` are never paid from
// the pool; they go to a person for review and a request for more evidence.
//
// A member's own share of the repair rises with how often their pool requests
// were paid in the last three years (`share` mirrors the published `share_rules`
// table): frequent claimants get a smaller grant and pay more themselves -
// never a refusal and never a wait.

export interface FundingRequest {
	id: string;
	amount: number;
	/** Already raised, e.g. from family and friends. */
	funded: number;
	/** Already paid by insured deductible cover, stacked before pledges. */
	covered?: number;
	/** Pool requests this member had paid in the last three years. */
	paid3y?: number;
	/** Evidence score, 0 to 100. */
	score: number;
}

export type AllocationStatus = 'funded' | 'partial' | 'waiting' | 'needs-review';

export interface Allocation {
	id: string;
	grant: number;
	status: AllocationStatus;
}

/** The published share rule (mirrors `share_rules`: step per paid request, cap). */
export interface ShareRule {
	/** Percentage points moved to the member's own share per paid request. */
	stepBps: number;
	/** Percentage points at most. */
	capBps: number;
}

export interface AllocationOptions {
	minScore?: number;
	bandSize?: number;
	share?: ShareRule;
}

const floorCents = (n: number) => Math.floor(n * 100) / 100;

export function allocatePool(
	requests: FundingRequest[],
	pool: number,
	{ minScore = 70, bandSize = 10, share }: AllocationOptions = {}
): { allocations: Allocation[]; remainingPool: number } {
	let left = Math.max(0, pool);
	const grants = new Map<string, number>();

	const bands = new Map<number, FundingRequest[]>();
	for (const r of requests) {
		if (r.score < minScore) continue;
		const band = Math.floor(r.score / bandSize) * bandSize;
		bands.set(band, [...(bands.get(band) ?? []), r]);
	}

	for (const band of [...bands.keys()].sort((a, b) => b - a)) {
		const members = bands.get(band)!;
		const carryBps = (r: FundingRequest) =>
			Math.min(share?.capBps ?? 0, (r.paid3y ?? 0) * (share?.stepBps ?? 0));
		const need = (r: FundingRequest) =>
			Math.max(0, r.amount - (r.covered ?? 0) - r.funded) -
				Math.floor(Math.max(0, r.amount - (r.covered ?? 0) - r.funded) * carryBps(r) / 10000);
		const totalNeed = members.reduce((sum, r) => sum + need(r), 0);
		if (totalNeed === 0) continue;
		const fill = Math.min(1, left / totalNeed);
		for (const r of members) {
			const grant = fill === 1 ? need(r) : floorCents(need(r) * fill);
			grants.set(r.id, grant);
			left -= grant;
		}
		if (fill < 1) left = 0;
	}

	const allocations = requests.map((r): Allocation => {
		const grant = grants.get(r.id) ?? 0;
		let status: AllocationStatus;
		if (r.score < minScore) status = 'needs-review';
		else if ((r.covered ?? 0) + r.funded + grant >= r.amount) status = 'funded';
		else if (grant > 0) status = 'partial';
		else status = 'waiting';
		return { id: r.id, grant, status };
	});

	return { allocations, remainingPool: floorCents(left) };
}
