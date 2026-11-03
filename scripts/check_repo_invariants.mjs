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

if (problems.length) {
	console.error(`Repo invariants: ${problems.length} problem(s)\n  ${problems.join('\n  ')}`);
	process.exit(1);
}
console.log(`Repo invariants: ${migrations.length} migrations in order, ${tests.length} pgTAP plans agree, lib modules paired, test chain complete`);