// Docs hygiene: every tracked `.md` file follows the repo's markdown rules, and
// every relative link and `#section` anchor it carries resolves to a real file
// and a real heading. Rules that were checked by hand on every docs change are
// now a gate, so a drift cannot ride a push into the preview build.
import { existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

const files = execFileSync('git', ['ls-files', '--', '*.md'], { encoding: 'utf8' })
		.split('\n')
		.filter((f) => f !== '');

const normalize = (path) => {
	 const parts = [];
	 for (const part of path.split('/')) {
	  if (part === '..') parts.pop();
	  else if (part !== '.' && part !== '') parts.push(part);
	 }
	 return parts.join('/');
};

const headingSlug = (line) => line.toLowerCase().replace(/[^\w\s-]/g, '').replace(/\s+/g, '-').replace(/-+/g, '-').replace(/^-|-$/g, '');
const anchors = {};
const bodies = {};

for (const file of files) {
	 const text = readFileSync(file, 'utf8');
	 bodies[file] = text;
	 const heads = new Set();
	 for (const line of text.split('\n')) {
	  const m = /^ {0,3}(#{1,6})\s+(.*)$/.exec(line);
	  if (m) heads.add(headingSlug(m[2]));
	 }
	 anchors[file] = heads;
}

const problems = [];
const join = (dir, rel) => dir === '' ? rel : `${dir}/${rel}`;

for (const file of files) {
	 const text = bodies[file];
	 const dir = file.includes('/') ? file.slice(0, file.lastIndexOf('/')) : '';
	 const lines = text.split('\n');

	 for (let i = 0; i < lines.length; i++) {
	  const line = lines[i];
	  if (line !== line.replace(/\s+$/, '')) problems.push(`${file}:${i + 1}: trailing whitespace`);
	  if (line.includes('\t')) problems.push(`${file}:${i + 1}: tab instead of spaces`);
	 }
	 if (/\n\n\n/.test(text)) problems.push(`${file}: three blank lines in a row`);
	 if (text.length === 0 || text.endsWith('\n\n') || !text.endsWith('\n')) problems.push(`${file}: not ended by exactly one newline`);

	 let block = [];
	 const flush = (at) => {
	  if (block.length < 2) return;
	  const counts = new Set(block.map((n) => bodies[file].split('\n')[n].split('|').length - 1));
	  if (counts.size > 1) problems.push(`${file}: table around line ${at} has cells of different widths`);
	 };
	 for (let i = 0; i < lines.length; i++) {
	  if (lines[i].startsWith('|')) {
	   block.push(i);
	  } else {
	   flush(i);
	   block = [];
	  }
	 }
	 flush(lines.length);

	 const codeFree = text.replace(/^ {0,3}(```|~~~)[\s\S]*?^\1[ \t]*$/gm, '');
	 for (const m of codeFree.matchAll(/(?<!!)\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g)) {
	  const target = m[1];
	  if (/^(https?:|mailto:|#)/.test(target)) continue;
	  const hash = target.indexOf('#');
	  const rel = hash === -1 ? target : target.slice(0, hash);
	  const anchor = hash === -1 ? '' : target.slice(hash + 1);
	  const path = normalize(rel === '' ? file : join(dir, rel));
	  if (!bodies[path] && !existsSync(path)) {
	   problems.push(`${file}: link to ${target} has no file behind it`);
	   continue;
	  }
	  if (anchor && !anchors[path].has(anchor)) {
	   problems.push(`${file}: link to ${target} points at a heading that is not there`);
	  }
	 }
}

if (problems.length) {
	 console.error('Docs hygiene failed:\n  ' + problems.join('\n  '));
	 process.exit(1);
}
console.log(`Docs hygiene: ${files.length} tracked markdown files OK`);