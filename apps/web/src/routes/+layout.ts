// Marketing pages are static content: render them to HTML at build time.
// The member area (`/signin`, `/app/*`) opts out in its own load files and runs
// in the browser only, served by the adapter's SPA fallback.
export const prerender = true;
