// Repo invariants the human gates keep checking by hand; run as `test:invariants`
// (in the root `test` chain and the CI web job).
//
// 1. Loader convention: every module under apps/web/src/lib ships a sibling
//    test. The one carve-out is the Supabase scaffold (src/lib/supabase/):
//    `client.ts` is the CLI-dropped file the adapter's own tooling owns, and
//    rewriting it against a test would be undone by the next `supabase link`
//    - a ledger note explains why the carve-out is directory-wide, not file-
//    named, so scaffold siblings would be caught too.
//
// 2. Migrations are a queue: names sort exactly as Supabase applies them, so
//    they must be unique and strictly increasing (a collision or a step
//    backwards ships the queue in the wrong order, which has shipped
//    migrations depending on tables that do not exist yet).
//
// 3. Every roadmap step row carries its state: a step is either built
//    ("landed"/"built" with a date) or deliberately not built ("Gate" — the
//    row says why it waits, e.g. partner or loss-data gates). A row with
//    neither is a step whose state nobody can read.
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const root = new URL('..', import.meta.url).pathname;
const files = execFileSync('git', ['ls-files'], { cwd: root, encoding: 'utf8' }).split('\n').filter(Boolean);
const problems = [];

// --- loader <-> sibling test ---
for (const f of files) {
	if (!f.startsWith('apps/web/src/lib/') || !f.endsWith('.ts') || f.endsWith('.test.ts')) continue;
	if (f.startsWith('apps/web/src/lib/supabase/')) continue; // scaffold carve-out
	const sibling = f.replace(/\.ts$/, '.test.ts');
	if (!files.includes(sibling)) {
		problems.push(`lib module ${f} has no sibling ${sibling}`);
	}
}

// --- the phone app's lib modules ship sibling tests (same pairing rule,
// Dart's own file names: lib/<path>/m.dart <-> test/<path>/m_test.dart) ---
for (const f of files) {
	if (!f.startsWith('apps/mobile/lib/') || !f.endsWith('.dart')) continue;
	const sibling = f.replace('apps/mobile/lib/', 'apps/mobile/test/').replace(/\.dart$/, '_test.dart');
	if (!files.includes(sibling)) {
		problems.push(`mobile module ${f} has no sibling ${sibling}`);
	}
}

// --- migration queue order ---
const migrations = files.filter((f) => f.endsWith('.sql') && f.includes('supabase/migrations/'));
for (let i = 1; i < migrations.length; i += 1) {
	const prev = migrations[i - 1].split('/').pop();
	const cur = migrations[i].split('/').pop();
	// Names are <14-digit stamp>_<slug>; fixed width makes comparing the
	// stamp lexicographic = numeric. A non-increasing pair applies a
	// migration before the tables it depends on exist.
	const prevStamp = prev.slice(0, 14);
	const curStamp = cur.slice(0, 14);
	if (!/^\d{14}_/.test(cur)) problems.push(`migration ${cur} does not start with a 14-digit stamp`);
	if (curStamp <= prevStamp) {
		problems.push(`migration queue out of order: ${prev} then ${cur} (stamp ${curStamp} must sort after ${prevStamp})`);
	}
}

// --- pgTAP plans count their assertions ---
const tests = files.filter((f) => f.endsWith('.sql') && f.includes('supabase/tests/'));
for (const f of tests) {
	const body = readFileSync(join(root, f), 'utf8');
	const plan = body.match(/^select plan\((\d+)\);/m);
	if (!plan) {
		problems.push(`${f}: no plan(N) line`);
		continue;
	}
	// Every top-level select-call is one assertion except the plan line
	// itself and pgTAP's own setup helpers (set_config feeds a run
	// constant, it asserts nothing) - counting calls keeps this generic
	// across assertion helper names without hardcoding a list.
	const asserts = [...body.matchAll(/^select ([a-z_]+)\(/gm)].filter((m) => m[1] !== 'plan' && m[1] !== 'set_config').length;
	if (Number(plan[1]) !== asserts) {
		problems.push(`${f}: plan(${plan[1]}) declares ${plan[1]} assertions, file has ${asserts}`);
	}
}

// --- the root test chain runs every gate ---
// A gate that is not chained is a gate CI and pnpm test never run, which is
// exactly how a whole-repo check comes to exist but never to fire. The chain
// names gates by "run <name>", so the name is checked whole, and every name
// the chain runs has to be a defined script (a typo would fail at run time,
// but only for whoever happens to type it). e2e is deliberately outside the
// chain: it needs the built site and Chromium, so it gets its own command and
// its own CI job - docs/STACK.md and the ledger keep that decision.
const chain = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8')).scripts;
const recipe = chain['test'];
const outsideChain = new Set(['test:web:e2e']);
for (const key of Object.keys(chain)) {
	if (!key.startsWith('test:') || outsideChain.has(key)) continue;
	if (!recipe.includes('run ' + key)) {
		problems.push('root package.json defines ' + key + ' but its test recipe never runs it');
	}
}
for (const m of recipe.matchAll(/run (test:[a-z0-9:]+)/g)) {
	if (!(m[1] in chain)) {
		problems.push('the test recipe runs ' + m[1] + ', which no script defines');
	}
}

// --- built artifacts stay out of the tracked tree ---
// The e2e audit reads the production build; a committed build directory is a
// snapshot that ages silently - the next audit pass would accuse stale HTML,
// and a push would ship it. Generated trees (the SvelteKit output, Playwright
// traces and caches) are never decisions, so nothing in them may be tracked.
const generatedDirs = ['apps/web/build/', 'apps/web/.svelte-kit/', 'apps/web/test-results/', 'apps/web/.e2e-chromium-cache/', 'apps/backend/node_modules/', 'node_modules/', 'dist/', 'apps/mobile/build/', 'apps/mobile/.dart_tool/'];
for (const f of files) {
	for (const dir of generatedDirs) {
		if (f.startsWith(dir)) {
			problems.push('tracked file ' + f + ' sits in the generated directory ' + dir + ' - the audit reads the live build, not a snapshot');
			break;
		}
	}
}

// --- internal links point at pages the site serves ---
// A typoed path link reads as a page that exists: it answers the error page,
// which looks like an accident to a reader and nothing fails. A site-absolute
// href is either a route (+page.svelte serves it, with [param] segments matched
// generically, the way SvelteKit itself serves them) or an asset under
// apps/web/static. Values carrying expressions (href="/#{id}") are left to the
// build, whose prerender step already fails on missing ids - this half is the
// paths, which the build lets through.
const routePaths = [];
for (const f of files) {
	if (!f.startsWith('apps/web/src/routes/') || !f.endsWith('/+page.svelte')) continue;
	const segs = f.replace('apps/web/src/routes/', '').replace(/\/\+page\.svelte$/, '').split('/').filter((s) => !/^\(.*\)$/.test(s));
	routePaths.push('/' + segs.join('/'));
}
const servesPath = (path) => {
	if (path === '/') return routePaths.includes('/');
	const want = path.slice(1).split('/');
	for (const rp of routePaths) {
		const have = rp === '/' ? [] : rp.slice(1).split('/');
		if (have.length !== want.length) continue;
		let ok = true;
		for (let i = 0; i < have.length; i += 1) {
			if (have[i].startsWith('[')) continue; // param segment
			if (have[i] !== want[i]) { ok = false; break; }
		}
		if (ok) return true;
	}
	return files.includes('apps/web/static' + path);
};
for (const f of files) {
	if (!f.startsWith('apps/web/src/') || !f.endsWith('.svelte')) continue;
	const body = readFileSync(join(root, f), 'utf8');
	for (const m of body.matchAll(/(?:href|src)="(\/[^"{ ]+)"/g)) {
		const path = m[1].split(/[?#]/)[0];
		if (path === '' || !path.startsWith('/') || path.startsWith('//')) continue;
		if (!servesPath(path)) {
			problems.push(`${f}: ${m[0].split("=")[0]}="${path}" names no page (no +page.svelte serves it) and no static file: the link answers the error page, or the image never loads`);
		}
	}
}

// 3. Roadmap step rows carry their state: built ("landed"/"built" dated) or a
//    Gate that names what waits. A row with neither leaves the roadmap's
//    remaining work unreadable.
{
	const roadmap = readFileSync(join(root, 'docs/roadmap.md'), 'utf8');
	for (const line of roadmap.split('\n')) {
		const m = line.match(/^\| (\d[a-z]?) \|/);
		if (!m) continue;
		if (!/landed|built|Gate/i.test(line)) {
			problems.push(`docs/roadmap.md ${m[1]}: step row with no landed annotation and no Gate note - its state cannot be read`);
		}
	}
}

if (problems.length) {
	console.error(`Repo invariants: ${problems.length} problem(s)\n  ${problems.join('\n  ')}`);
	process.exit(1);
}
console.log(`Repo invariants: ${migrations.length} migrations in order, ${tests.length} pgTAP plans agree, lib modules paired, test chain complete, generated dirs untracked, internal links resolve`);