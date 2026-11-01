import { formatCents, formatDay } from '#lib/dashboard/format.ts';
import type { DefaultPlan } from '#lib/dashboard/labels.ts';
import type { LoanDetailRow } from './loan.ts';

// Plain-word lines of the loan agreement shared by the loan page, the terms
// form and the sign panel, so all three say the same thing.

/** Why "repay on sale" can't be picked for an unsecured loan, in one line. */
export const REPAY_ON_SALE_UNAVAILABLE =
	'Not available for an unsecured loan: without a lien on the home, nothing ties repayment to its sale.';

/**
 * What each default plan means, said once. `forgive` spells out that the
 * lender gives up the whole remaining balance and that it counts as a gift
 * (`apply_default_plan` books it all against one tax year).
 * PENDING COUNSEL: the gift and Form 709 wording in `forgive`.
 */
export function planDetail(plan: DefaultPlan, secured: boolean): string {
	switch (plan) {
		case 'forgive':
			return 'The lender gives up the whole balance still owed at that point. It counts as the lender’s gift to the borrower for that tax year; above the yearly gift limit, the lender files a gift-tax return (IRS Form 709). Nothing more is owed.';
		case 'repay_on_sale':
			return secured
				? 'The lien stays on the home and what’s left is repaid when it’s sold or refinanced. Nobody forces a sale.'
				: REPAY_ON_SALE_UNAVAILABLE;
		case 'mediate':
			return 'A neutral mediator helps you both agree what happens next. Nothing is decided for you.';
	}
}

/**
 * The Security line, always shown. Nothing in the app can secure a loan yet,
 * so an unsecured loan says so plainly instead of hinting at a lien option.
 */
export function securityText(loan: Pick<LoanDetailRow, 'secured' | 'lien_recorded_at'>): string {
	if (!loan.secured)
		return 'Unsecured: there’s no lien on any property. Repayment rests on this signed agreement, and if repayments stop for good, the plan above applies.';
	return loan.lien_recorded_at
		? `Secured by a lien on the home, recorded with the county on ${formatDay(loan.lien_recorded_at)}.`
		: 'Secured by a lien on the home, not recorded with the county yet.';
}

/**
 * What the lender is agreeing to about their own money, shown before they
 * sign. Mirrors the backend: `capture_contributions` takes pledged money only
 * once the request is fully pledged and every loan on it is signed by both
 * sides; a request that closes unpaid cancels proposed and signed loans
 * (`release_on_close`). There is no way to withdraw or restructure a signed
 * loan in the app (backend.md, "Not built yet").
 */
export function lenderSignPoints(loan: Pick<LoanDetailRow, 'principal_cents' | 'request_id'>): string[] {
	const amount = formatCents(loan.principal_cents);
	return [
		loan.request_id
			? `Signing lets the payment partner collect ${amount} from you once the whole request is pledged and every loan on it is signed. It goes straight to the payee, not to the borrower.`
			: `Signing lets the payment partner collect ${amount} from you.`,
		loan.request_id
			? 'Once you have both signed, you can’t cancel it. It only falls through if the request closes before the money is collected, and then nothing is taken from you.'
			: 'Once you have both signed, you can’t cancel it.',
		'You could lose some or all of this money. Kinfold doesn’t guarantee or insure repayment. Only lend what you could manage without.'
	];
}

/**
 * What can still change after both sign. No restructure flow exists, so this
 * names only what does: pauses, forgiveness, and the agreed default plan.
 */
export function afterSigningText(pauseMonthsPerYear: number): string {
	const pauses = pauseMonthsPerYear > 0 ? 'the borrower can use the pauses above, ' : '';
	return `After you both sign, the terms and schedule are fixed. The app has no way to change them later: ${pauses}the lender can forgive some or all of what’s left, and the plan for when repayments stop applies if they stop for good.`;
}

/** Who the lender lent to, from the lender's own supporter row (the borrower's label for them). */
export function lentToText(relationship: string | null): string {
	return relationship ? ` to the member who invited you as their ${relationship}` : '';
}
