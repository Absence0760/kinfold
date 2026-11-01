import { formatCents, formatDay, parseDay } from '#lib/dashboard/format.ts';
import { poolName, poolRule, requestKindLabel, type FundingMode, type RequestKind } from '#lib/dashboard/labels.ts';
import type { Database } from '../../../../backend/supabase/database.types.ts';
import { fundForKind } from './form.ts';

type Tables = Database['public']['Tables'];
export type FundSettings = Pick<
	Tables['fund_settings']['Row'],
	'fund' | 'kinds' | 'max_request_cents' | 'waiting_days' | 'min_score'
>;
export type AssetRow = Pick<
	Tables['covered_assets']['Row'],
	'id' | 'kind' | 'description' | 'registered_on' | 'removed_on'
>;

/** `YYYY-MM-DD` plus whole days (Postgres `date + integer`). */
export function addDays(isoDate: string, days: number): string {
	const d = parseDay(isoDate);
	d.setUTCDate(d.getUTCDate() + days);
	return d.toISOString().slice(0, 10);
}

export const usesPool = (funding: FundingMode): boolean => funding === 'pool' || funding === 'both';

export interface PoolCheck {
	kind: RequestKind;
	funding: FundingMode;
	amountCents: number | null;
	incidentOn: string | null;
	assetId: string | null;
}

export interface PoolContext {
	/** Settings for the fund this kind draws on, or null if not loaded. */
	settings: FundSettings | null;
	/** `coverage_started_on`: the member's first captured dues payment. */
	coverageStartedOn: string | null;
	/** The member's own covered assets. */
	assets: readonly AssetRow[];
}

/**
 * Why the community pool couldn't pay this request, in plain words: the same
 * checks `submit_request` makes for pool and both requests, in the same
 * order, so the member hears about them while choosing rather than on submit.
 * Empty when the pool can consider it (or the request doesn't use the pool).
 * The database stays the authority; this only warns early.
 */
export function poolProblems(req: PoolCheck, ctx: PoolContext): string[] {
	if (!usesPool(req.funding) || !ctx.settings) return [];
	const s = ctx.settings;
	const pool = poolName(req.kind);
	const out: string[] = [];

	if (!s.kinds.includes(req.kind)) {
		out.push(`${cap(pool)} doesn’t cover ${requestKindLabel(req.kind).toLowerCase()} requests yet. Ask family and friends instead.`);
		return out;
	}
	if (req.amountCents != null && req.amountCents > s.max_request_cents) {
		out.push(`${cap(pool)} pays at most ${formatCents(s.max_request_cents)} per request. Lower the amount, or ask family and friends.`);
	}

	if (!ctx.coverageStartedOn) {
		out.push(
			`Your pool cover hasn’t started. It starts with your first dues payment, and covers what happens ${s.waiting_days} days after that.`
		);
	} else if (req.incidentOn) {
		const from = addDays(ctx.coverageStartedOn, s.waiting_days);
		if (req.incidentOn < from) {
			out.push(
				`Your pool cover covers what happens from ${formatDay(from)} (${s.waiting_days} days after your first dues payment), so it can’t help with this. Family and friends can.`
			);
		}
	}

	if (fundForKind(req.kind) === 'protection') {
		const asset = ctx.assets.find((a) => a.id === req.assetId && a.removed_on == null);
		if (!asset) {
			out.push('Choose the car this happened to. The repair fund only helps with cars registered with Kinfold.');
		} else if (req.incidentOn) {
			const from = addDays(asset.registered_on, s.waiting_days);
			if (req.incidentOn < from) {
				out.push(
					`${asset.description} was registered with Kinfold on ${formatDay(asset.registered_on)}, so the repair fund covers it from ${formatDay(from)}.`
				);
			}
		}
	}
	return out;
}

/** One line on the pool's rules, for the funding choice. */
export function poolRulesText(kind: RequestKind, settings: FundSettings | null): string {
	const pool = poolName(kind);
	if (!settings) return `${cap(pool)} ${poolRule(kind)} at each run.`;
	const car = fundForKind(kind) === 'protection';
	return [
		`${cap(pool)} ${poolRule(kind)} at each run, up to ${formatCents(settings.max_request_cents)} per request.`,
		`It covers what happens at least ${settings.waiting_days} days after your first dues payment${car ? ', to a car registered with Kinfold at least that long' : ''}.`,
		'Your request goes on the members-only board, without your name or town.'
	].join(' ');
}

const cap = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);
