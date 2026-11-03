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

	 // The roadmap's own conventions: step ids are unique and never go back,
	 // so a mislabelled or duplicated step row - which would hide a whole leg
	 // from the reader who walks the stage table - fails the gate.
	 if (file === 'docs/roadmap.md') {
	  const stepRows = [];
	  for (let i = 0; i < lines.length; i += 1) {
	   const cells = lines[i].split('|');
	   const step = cells.length > 1 ? cells[1].trim() : '';
	   if (/^\d[a-z]$/.test(step)) stepRows.push({ at: i, id: step });
	  }
	  const seen = new Map();
	  let previous = '';
	  const rank = (id) => Number(id[0]) * 100 + id.charCodeAt(1);
	  for (const row of stepRows) {
	   if (seen.has(row.id)) {
	    problems.push(`${file}:${row.at + 1}: step ${row.id} repeats the row at line ${seen.get(row.id)}`);
	   }
	   seen.set(row.id, row.at + 1);
	   if (previous !== '' && rank(row.id) < rank(previous)) {
	    problems.push(`${file}:${row.at + 1}: step ${row.id} is filed before ${previous}`);
	   }
	   previous = row.id;
	  }
	  if (stepRows.length === 0) problems.push(`${file}: the roadmap has no step rows`);
	 }

	 // The decision ledger's own conventions, since a ledger entry without a
	 // Reversal bullet is a decision no one can undo, and an entry filed out of
	 // date order hides a decision from the reader who scans the top.
	 if (file === 'docs/ledger.md') {
	  const entries = [];
	  for (let i = 0; i < lines.length; i += 1) {
	   if (lines[i].startsWith('## ')) entries.push({ at: i, title: lines[i] });
	  }
	  let previous = '';
	  for (let e = 0; e < entries.length; e += 1) {
	   const start = entries[e].at;
	   const end = e + 1 < entries.length ? entries[e + 1].at : lines.length;
	   const body = lines.slice(start, end).join('\n');
	   const date = /^## (\d{4}-\d{2}-\d{2}) /.exec(lines[start]);
	   if (!date) {
	    problems.push(`${file}:${start + 1}: a ledger entry has no decision date`);
	    continue;
	   }
	   if (previous !== '' && date[1] > previous) {
	    problems.push(`${file}:${start + 1}: dated ${date[1]} sits under ${previous}, so it is filed out of order`);
	   }
	   previous = date[1];
	   if (!body.includes('**Reversal')) {
	    problems.push(`${file}:${start + 1}: ${date[1]} has no Reversal bullet`);
	   }
	  }
	 }

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