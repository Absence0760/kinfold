/**
 * Fixed-rate loan maths for the savings calculator. Pure functions, no rounding:
 * callers format for display.
 */

/** Monthly payment on a fully amortising loan. A 0% rate repays principal evenly. */
export function monthlyPayment(principal: number, annualRatePct: number, years: number): number {
	const n = years * 12;
	if (principal <= 0 || n <= 0) return 0;
	const r = annualRatePct / 100 / 12;
	if (r === 0) return principal / n;
	return (principal * r) / (1 - (1 + r) ** -n);
}

/** Total interest paid over the life of the loan. */
export function totalInterest(principal: number, annualRatePct: number, years: number): number {
	if (principal <= 0) return 0;
	return monthlyPayment(principal, annualRatePct, years) * years * 12 - principal;
}

export interface SavingsInput {
	/** Amount that would otherwise be borrowed from a bank. */
	loanAmount: number;
	annualRatePct: number;
	years: number;
	/** Part of the loan covered by zero-interest family or community money. */
	zeroInterestAmount: number;
}

export interface SavingsResult {
	bankOnly: { monthly: number; interest: number };
	withKinfold: { monthly: number; interest: number; bankPrincipal: number };
	interestSaved: number;
}

/**
 * Compare a bank-only loan with one where part of the principal comes from a
 * zero-interest loan repaid over the same term. The zero-interest share is
 * clamped to the loan amount, so the bank portion is never negative.
 */
export function compareSavings(input: SavingsInput): SavingsResult {
	const { loanAmount, annualRatePct, years } = input;
	const zero = Math.min(Math.max(input.zeroInterestAmount, 0), Math.max(loanAmount, 0));
	const bankPrincipal = Math.max(loanAmount, 0) - zero;

	const bankOnlyInterest = totalInterest(loanAmount, annualRatePct, years);
	const mixedInterest = totalInterest(bankPrincipal, annualRatePct, years);

	return {
		bankOnly: {
			monthly: monthlyPayment(loanAmount, annualRatePct, years),
			interest: bankOnlyInterest
		},
		withKinfold: {
			monthly: monthlyPayment(bankPrincipal, annualRatePct, years) + monthlyPayment(zero, 0, years),
			interest: mixedInterest,
			bankPrincipal
		},
		interestSaved: bankOnlyInterest - mixedInterest
	};
}
