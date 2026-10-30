// Guard: every root script that delegates to a workspace (`pnpm -C <dir> <script>`)
// or to a local file (`node <file>`, `bash <file>`) must point at something that exists.
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const root = new URL('..', import.meta.url).pathname;
const { scripts } = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'));
const problems = [];

for (const [name, cmd] of Object.entries(scripts)) {
	if (name.startsWith('//')) continue;
	for (const [, dir, target] of cmd.matchAll(/pnpm -C (\S+) (\S+)/g)) {
		const pkgPath = join(root, dir, 'package.json');
		if (!existsSync(pkgPath)) {
			problems.push(`${name}: ${dir}/package.json does not exist`);
			continue;
		}
		const ws = JSON.parse(readFileSync(pkgPath, 'utf8'));
		if (!ws.scripts?.[target]) problems.push(`${name}: ${dir} has no "${target}" script`);
	}
	for (const [, file] of cmd.matchAll(/(?:node|bash) (\S+\.(?:mjs|js|sh))/g)) {
		if (!existsSync(join(root, file))) problems.push(`${name}: ${file} does not exist`);
	}
	for (const [, target] of cmd.matchAll(/pnpm run (\S+)/g)) {
		if (!scripts[target]) problems.push(`${name}: no root script "${target}"`);
	}
}

if (problems.length) {
	console.error('Root script guard failed:\n  ' + problems.join('\n  '));
	process.exit(1);
}
console.log(`Root script guard: ${Object.keys(scripts).filter((s) => !s.startsWith('//')).length} scripts OK`);
