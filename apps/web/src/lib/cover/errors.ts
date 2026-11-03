/** The parts of a Postgres error (or any thrown error) this needs. */
export interface DbError {
	code?: string;
	message?: string;
}

/**
 * A cover door's refusal in plain words. The doors raise readable messages for
 * each rule (who may act, which asset); anything unrecognised is passed
 * through, so a new rule shows up rather than hiding behind a shrug.
 */
export function explainCoverError(error: DbError | null | undefined): string {
	const message = error?.message ?? '';
	const code = error?.code ?? '';

	if (/plan is chosen by a signed-in member/i.test(message))
		return 'Sign in again to choose your cover plan: the plan belongs to the signed-in member.';
	if (/class is stated by the member who owns the vehicle/i.test(message))
		return 'The class on a vehicle is stated by the member who owns it.';
	if (/asset not found, not yours, already removed, or not a vehicle/i.test(message) || code === 'P0002')
		return 'That vehicle isn’t yours to class, it was retired, or it isn’t a vehicle.';

	return message;
}
