import { fileProblem } from './evidence.ts';

/**
 * Several evidence files chosen at once, uploaded one after another so a weak
 * connection carries one file at a time, each with its own status.
 */
export type QueueStatus = 'waiting' | 'uploading' | 'done' | 'failed' | 'skipped';

export interface QueueItem {
	/** Stable within one queue, for keyed lists and ids. */
	key: string;
	/** The file's name as chosen, shown only on this device and never stored. */
	name: string;
	status: QueueStatus;
	/** Why it was skipped or failed. */
	message: string | null;
}

/** A queue for the chosen files: ones the upload can't take are skipped with the reason. */
export function makeQueue(files: readonly { name: string; size: number; type: string }[]): QueueItem[] {
	return files.map((f, i) => {
		const problem = fileProblem(f);
		return { key: `f${i}`, name: f.name, status: problem ? 'skipped' : 'waiting', message: problem };
	});
}

/** The next file to send, or -1 when none is waiting. */
export const nextWaiting = (items: readonly QueueItem[]): number => items.findIndex((i) => i.status === 'waiting');

/** Failed files go back to waiting, so one tap retries only those. */
export const retryFailed = (items: readonly QueueItem[]): QueueItem[] =>
	items.map((i) => (i.status === 'failed' ? { ...i, status: 'waiting', message: null } : i));

/** One file's status in words. */
export function queueItemText(item: QueueItem): string {
	switch (item.status) {
		case 'waiting':
			return 'Waiting to upload';
		case 'uploading':
			return 'Uploading…';
		case 'done':
			return 'Uploaded';
		case 'failed':
			return `Didn’t upload. ${item.message ?? 'Try it again.'}`;
		case 'skipped':
			return `Not uploaded. ${item.message ?? ''}`.trim();
	}
}

const files = (n: number) => (n === 1 ? '1 file' : `${n} files`);

/** The whole queue in one line, for the live region. */
export function queueSummary(items: readonly QueueItem[]): string {
	const count = (s: QueueStatus) => items.filter((i) => i.status === s).length;
	const done = count('done');
	const failed = count('failed');
	const skipped = count('skipped');
	const left = count('waiting') + count('uploading');
	const sendable = items.length - skipped;
	if (sendable === 0) return skipped === 1 ? 'That file couldn’t be used; see why below.' : `None of the ${skipped} files could be used; see why below.`;
	if (left > 0) return `Uploading ${done + 1} of ${sendable}. Keep this page open until it finishes.`;
	const parts = [`Uploaded ${done} of ${files(sendable)}.`];
	if (failed) parts.push(`${files(failed)} didn’t upload; you can try ${failed === 1 ? 'it' : 'them'} again.`);
	if (skipped) parts.push(`${files(skipped)} couldn’t be used; see why below.`);
	return parts.join(' ');
}
