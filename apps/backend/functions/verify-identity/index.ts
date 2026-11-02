// `verify-identity`: triggered at signup. It starts an identity check; the
// vendor's webhook calls `record_identity_check`, which stores the vendor's
// reference and moves a `pending_verification` member to `active`. The local
// stand-in for the vendor is the rule below: a `*@test.com` email stands in
// for a passing check, and completes straight away by calling that same
// guarded function — so the function's word still passes the function's own
// guard (`private.is_service()`), never a looser one.
//
// The member's documents never come here: the reference and the outcome are
// all that gets stored (in `private.member_identity`).

import { Db } from "../shared/rest.ts";

const PROVIDER = "fake-vendor";

export interface IdentityStart {
  /** True when the check completed and the member was moved to `active`. */
  completed: boolean;
  /** Where the member continues the real vendor's flow; null when it completed. */
  vendorUrl: string | null;
}

/** The local fake vendor: only a `*@test.com` email stands in for a passing check. */
export function fakeVendorApproves(email: string): boolean {
  return email.toLowerCase().endsWith("@test.com");
}

export async function startIdentityCheck(
  memberId: string,
  email: string,
  db: Db,
): Promise<IdentityStart> {
  if (email === "") {
    throw new Error("the vendor needs an email to match the applicant");
  }
  if (!fakeVendorApproves(email)) {
    // The real vendor runs its own flow; its webhook finishes the check.
    return {
      completed: false,
      vendorUrl: `https://vendor.example/verify/${memberId}`,
    };
  }
  await db.rpc("record_identity_check", {
    p_member: memberId,
    p_provider: PROVIDER,
    p_provider_ref: `ref-${memberId}`,
  });
  return { completed: true, vendorUrl: null };
}
