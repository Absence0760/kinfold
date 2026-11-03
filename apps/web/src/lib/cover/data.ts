import { fromNew, rpcNew } from '#lib/supabase/client.ts';
import type { Db } from '#lib/supabase/client.ts';

/**
 * Reads and writes for the car-cover console. Everything runs as the signed-in
 * member: RLS answers with their own vehicles and plan row, and the two doors
 * below (`set_my_plan`, `set_vehicle_class`) re-check that a signed-in member
 * owns what they change. Filed rates are public; premiums read the member's
 * own class and plan.
 */

function fail(error: { message: string; code?: string } | null): void {
	if (error) throw error;
}

export interface CoverAssetRow {
	id: string;
	description: string;
	/** Null until the member states a rating-law class on it. */
	vehicle_class: string | null;
	/** Set when a vehicle was retired; the console hides those. */
	removed_on: string | null;
}

export interface FiledRateRow {
	vehicle_class: string;
	plan: string;
	/** bigint cents over the wire; a single member's premium never nears 2^53. */
	premium_cents: number;
	cap_cents: number;
}

export interface CoverDetail {
	assets: CoverAssetRow[];
	/** Filed rates for the classes this member's vehicles carry. */
	filed: FiledRateRow[];
	/** The member's own choice; null means the Basic rates apply by default. */
	plan: string | null;
	/** The cooperative's paid premiums for this member, in cents. */
	premiumCents: number;
}

export async function loadCover(db: Db, uid: string): Promise<CoverDetail> {
	const [assetsRes, filedRes, planRes, premiumRes] = await Promise.all([
		// `covered_assets` grew the rating-law class; read it through the seam.
		fromNew(db, 'covered_assets')
			.select('id, description, vehicle_class, removed_on')
			.eq('member_id', uid),
		// `cover_plans` and `cover_choices` are newer than the committed types.
		fromNew(db, 'cover_plans').select('vehicle_class, plan, premium_cents, cap_cents'),
		fromNew(db, 'cover_choices').select('plan').eq('member_id', uid).maybeSingle(),
		// `cover_premium_cents` is newer than the generated types; see rpcNew.
		rpcNew(db, 'cover_premium_cents', { p_member: uid })
	]);
	fail(assetsRes.error);
	fail(filedRes.error);
	fail(planRes.error);
	fail(premiumRes.error);
	const allAssets = (assetsRes.data ?? []) as {
		id: string;
		description: string;
		vehicle_class: string | null;
		removed_on: string | null;
	}[];
	const assets = allAssets.filter((a) => a.removed_on === null);
	const classes = new Set(assets.map((a) => a.vehicle_class).filter((c): boolean => c !== null));
	const filed = ((filedRes.data ?? []) as FiledRateRow[]).filter((r) => classes.has(r.vehicle_class));
	const chosen = (planRes.data ?? null) as { plan: string } | null;
	return {
		assets,
		filed,
		plan: chosen?.plan ?? null,
		premiumCents: (premiumRes.data ?? 0) as number
	};
}

/** Choose the member's cover plan; the filed rates themselves are the partner's. */
export async function setCoverPlan(db: Db, plan: string): Promise<void> {
	const { error } = await rpcNew(db, 'set_my_plan', { p_plan: plan });
	fail(error);
}

/** State the rating-law class on one of the member's own vehicles. */
export async function classCoverVehicle(db: Db, assetId: string, vehicleClass: string): Promise<void> {
	const { error } = await rpcNew(db, 'set_vehicle_class', { p_asset: assetId, p_class: vehicleClass });
	fail(error);
}
