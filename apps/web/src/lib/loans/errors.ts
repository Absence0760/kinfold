/** The parts of a PostgrestError (or any thrown error) this needs. */
export interface DbError {
	code?: string;
	message?: string;
}

/**
 * A loan function's refusal in plain words: what happened and what to do
 * next. The loan functions raise readable messages for each rule (who may
 * act, which status, the pause allowance, no interest); anything unrecognised
 * is passed through, so a new rule shows up rather than hiding behind
 * "something went wrong".
 */
export function explainLoanError(error: DbError | null | undefined): string {
	const message = error?.message ?? '';
	const code = error?.code ?? '';

	if (/^loan not found$/i.test(message))
		return 'This loan isn’t yours to change, or it no longer exists. Only the borrower and the lender can act on it.';

	// set_loan_terms / set_loan_schedule after signing.
	if (/can only change by agreement \(restructure\)/i.test(message))
		return 'Both of you have signed, so the terms and schedule are fixed. Changing them needs a new agreement between you.';
	if (/payment day must be 1 to 28/i.test(message)) return 'Choose a payment day from the 1st to the 28th.';
	if (/pause allowance must be 0 to 12/i.test(message))
		return 'The pause allowance must be 0 to 12 months a year.';
	if (/repay on sale needs a loan secured by a lien/i.test(message) || /repay_on_sale_needs_lien/i.test(message))
		return '“Repay when the home is sold” is only for loans secured by a lien on the home. Choose another plan.';
	if (/schedule must be 1 to 480 months/i.test(message)) return 'Choose 1 to 480 monthly installments.';
	if (/too many installments for this amount/i.test(message))
		return 'That’s more installments than there are cents to repay. Choose fewer.';
		if (/the first installment cannot be due in the past/i.test(message))
				return 'A loan can’t be proposed with payments already overdue. Pick a first payment day from today on.';

	// sign_loan.
	const already = /^loan is already (\w+)/i.exec(message)?.[1];
	if (already)
		return already === 'signed'
			? 'This loan is already signed by both of you.'
			: 'This loan is past signing. Refresh to see where it stands.';
	if (/set a repayment schedule that adds up to the amount lent/i.test(message))
		return 'Set a repayment schedule first. It has to add up to exactly the amount lent before either of you can sign.';
	if (/installments \(.*\) exceed the principal/i.test(message))
		return 'The schedule can’t add up to more than the amount lent: Kinfold loans carry no interest.';

	// forgive_loan.
	if (/only the lender can forgive an active loan/i.test(message))
		return 'Only the lender can forgive, and only once the loan is being repaid (after the money reached the payee).';
	if (/payments and forgiveness exceed the principal/i.test(message))
		return 'That’s more than is left to repay. Refresh, then forgive the rest instead.';
	if (/loan_forgiveness_amount_cents_check/i.test(message)) return 'Enter an amount above zero.';
	if (/loan_forgiveness_tax_year_check/i.test(message)) return 'The tax year must be between 2000 and 2200.';

	// restructure_loan / sign_loan_restructure.
	if (/only a collecting loan can be restructured/i.test(message))
		return 'This loan is closed or still being set up, so there is no schedule to change.';
	if (/other side has not signed yet is already pending/i.test(message))
		return 'You have a new schedule waiting for your side to sign. Check the loan before staging another.';
	if (/owes nothing has nothing to restructure/i.test(message))
		return 'This loan owes nothing, so there is nothing to restructure.';
	if (/owes nothing, so there is nothing to restructure/i.test(message))
		return 'This loan owes nothing, so there is nothing to restructure.';
	if (/restructured schedule can't start in the past/i.test(message))
		return 'A new schedule cannot start in the past. Pick a start date from today on.';
	if (/too many installments for what is left to pay/i.test(message))
		return 'That’s more installments than there are cents left to repay. Choose fewer.';
	if (/no restructure is waiting for this side to sign/i.test(message))
		return 'There is no new schedule waiting for you to sign. Refresh to see where the loan stands.';

	// Fund loan doors (roadmap 3a): same ladder, Fund wording. Fund-only
	// messages first so the family allowance regex below doesn't swallow them.
	if (/^fund loan not found$/i.test(message))
		return 'This Fund loan isn’t yours to change, or it no longer exists. Only the borrower of a Fund loan can act on it.';
	if (/^fund loan is already \w+/i.test(message))
		return 'This Fund loan is past signing. Refresh to see where it stands.';
	if (/only a collecting loan can be paused/i.test(message))
		return 'This Fund loan isn’t collecting, so there’s nothing to pause.';
	const fundAllowance = /allows (\d+) pause months a year \((\d+) used\); ask the lending Fund to restructure/i.exec(message);
	if (fundAllowance)
		return `This Fund loan allows ${fundAllowance[1]} pause month${fundAllowance[1] === '1' ? '' : 's'} a year and ${fundAllowance[2]} ${fundAllowance[2] === '1' ? 'is' : 'are'} used. For more time, ask the lending Fund for a new schedule.`;
	if (/income schedules are computed from income; nothing to reschedule/i.test(message))
		return 'Income payments are sized from income every month; there is no fixed schedule to change.';
	if (/self-test data is already recorded/i.test(message))
		return 'The self-test is offered once per loan. The auditor keeps the record from that offer; refresh and the page keeps showing it.';
	if (/answers on the government monitoring form, not a self-test/i.test(message))
		return 'A Fund loan secured by the home answers on the credit union\u2019s government monitoring form \u2014 there is nothing to offer here.';
	if (/the self-test needs all four disclosures acknowledged/i.test(message))
		return 'The self-test is only an offer once all four disclosures are read \u2014 purpose, how they are collected, their limits, and how long they are kept.';
	if (/income due for this month is not owed/i.test(message))
		return 'Nothing is owed this month, so there is nothing to record.';
	if (/a restructure the partner has not answered yet/i.test(message))
		return 'The lending Fund hasn’t applied your last restructure ask yet. One ask waits at a time.';

	// pause_loan / resume_loan.
	if (/only an active loan can be paused/i.test(message))
		return 'Repayments haven’t started, or the loan is closed, so there’s nothing to pause.';
	const allowance = /allows (\d+) pause months a year \((\d+) used\)/i.exec(message);
	if (allowance)
		return `This loan allows ${allowance[1]} pause month${allowance[1] === '1' ? '' : 's'} a year and ${allowance[2]} ${
			allowance[2] === '1' ? 'is' : 'are'
		} used. For more time, agree a new schedule with your lender.`;
	if (/loan allows .* pause months a year/i.test(message))
		return 'That’s more pause months than this loan allows this year. For more time, agree a new schedule with your lender.';
	if (/loan_pauses_months_check/i.test(message)) return 'A pause is 1 to 12 months.';
	if (/loan_pauses_reason_check/i.test(message)) return 'Keep the note to 500 characters or fewer.';
	if (/only a paused loan can be resumed/i.test(message)) return 'This loan isn’t paused, so there’s nothing to resume.';
	if (/pause runs until/i.test(message)) return 'The borrower’s pause hasn’t ended yet.';

	if (code === '42501' && /permission denied/i.test(message))
		return 'Your account isn’t allowed to do this, so nothing was changed.';
	if (code === 'PGRST301' || /jwt expired/i.test(message)) return 'Your session has ended. Sign in again, then retry.';
	if (/failed to fetch|networkerror|fetch failed|load failed/i.test(message))
		return 'Can’t reach the server. Check your connection and try again. Nothing was changed.';

	return message ? `The server refused this: “${message}”` : 'Something went wrong and nothing was changed. Try again.';
}
