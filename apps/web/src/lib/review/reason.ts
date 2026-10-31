/**
 * The written reason every review carries. The database checks the same bounds
 * (`reviews.reason`, 10 to 2,000 characters); checking here first means the
 * reviewer hears it before the round trip, in the same words.
 */
export const REASON_MIN = 10;
export const REASON_MAX = 2000;

/** The reason as it will be saved: surrounding whitespace dropped. */
export function cleanReason(text: string): string {
	return text.trim();
}

/** Null when the reason can be saved, else what to fix. */
export function reasonProblem(text: string): string | null {
	const n = cleanReason(text).length;
	if (n === 0) return 'Write the reason for your decision. The member reads it.';
	if (n < REASON_MIN) return `Write at least ${REASON_MIN} characters (${REASON_MIN - n} more).`;
	if (n > REASON_MAX) return `Keep it to ${REASON_MAX.toLocaleString('en-US')} characters (${(n - REASON_MAX).toLocaleString('en-US')} over).`;
	return null;
}

/** Short counter text for under the field. */
export function reasonCounter(text: string): string {
	const n = cleanReason(text).length;
	return `${n.toLocaleString('en-US')} / ${REASON_MAX.toLocaleString('en-US')}`;
}
