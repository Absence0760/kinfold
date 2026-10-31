// How the community pool is shared out across open requests.
//
// Requests are grouped into legitimacy bands (90-100, 80-89, ...). The highest
// band is filled first, and every request inside a band is filled at the same
// time: if the pool can't cover the whole band, each request gets the same
// share of what it still needs. Requests below `minScore` are never paid from
// the pool; they go to a person for review and a request for more evidence.

export interface FundingRequest {
	id: string;
	amount: number;
	/** Already raised, e.g. from family and friends. */
	funded: number;
	/** Legitimacy score, 0 to 100. */
	score: number;
}

export type AllocationStatus = 'funded' | 'partial' | 'waiting' | 'needs-review';

export interface Allocation {
	id: string;
	grant: number;
	status: AllocationStatus;
}

export interface AllocationOptions {
	minScore?: number;
	bandSize?: number;
}

const floorCents = (n: number) => Math.floor(n * 100) / 100;

export function allocatePool(
	requests: FundingRequest[],
	pool: number,
	{ minScore = 70, bandSize = 10 }: AllocationOptions = {}
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
		const need = (r: FundingRequest) => Math.max(0, r.amount - r.funded);
		const totalNeed = members.reduce((sum, r) => sum + need(r), 0);
		if (totalNeed === 0) continue;
		const share = Math.min(1, left / totalNeed);
		for (const r of members) {
			const grant = share === 1 ? need(r) : floorCents(need(r) * share);
			grants.set(r.id, grant);
			left -= grant;
		}
		if (share < 1) left = 0;
	}

	const allocations = requests.map((r): Allocation => {
		const grant = grants.get(r.id) ?? 0;
		let status: AllocationStatus;
		if (r.score < minScore) status = 'needs-review';
		else if (r.funded + grant >= r.amount) status = 'funded';
		else if (grant > 0) status = 'partial';
		else status = 'waiting';
		return { id: r.id, grant, status };
	});

	return { allocations, remainingPool: floorCents(left) };
}
