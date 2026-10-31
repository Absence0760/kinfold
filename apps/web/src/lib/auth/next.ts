/**
 * Where to go after signing in.
 *
 * Only a path inside the member area is accepted, so a crafted
 * `/signin?next=https://evil.example` (or `//evil.example`) can't turn the sign-in
 * page into an open redirect.
 */
export function safeNext(next: string | null | undefined): string {
	if (!next) return '/app';
	if (!/^\/app(?:[/?#]|$)/.test(next)) return '/app';
	if (next.includes('\\')) return '/app';
	return next;
}

/** The sign-in URL that returns to `url` afterwards. */
export function signinUrl(url: URL): string {
	const next = url.pathname + url.search;
	return next === '/app' ? '/signin' : `/signin?next=${encodeURIComponent(next)}`;
}
