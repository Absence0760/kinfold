import { describe, expect, it } from 'vitest';
import { makeQueue, nextWaiting, queueItemText, queueSummary, retryFailed, type QueueItem } from './upload-queue';

const photo = (name: string, type = 'image/jpeg', size = 1000) => ({ name, type, size });

describe('makeQueue', () => {
	it('queues usable files and skips the rest with the reason', () => {
		const q = makeQueue([photo('a.jpg'), photo('notes.txt', 'text/plain'), photo('b.heic', ''), photo('c.png', 'image/png', 0)]);
		expect(q.map((i) => i.status)).toEqual(['waiting', 'skipped', 'waiting', 'skipped']);
		expect(q[1].message).toMatch(/photo/);
		expect(q[3].message).toMatch(/empty/);
		expect(new Set(q.map((i) => i.key)).size).toBe(4);
	});
});

describe('stepping through the queue', () => {
	it('finds the next waiting file and retries only failed ones', () => {
		const q: QueueItem[] = [
			{ key: 'a', name: 'a', status: 'done', message: null },
			{ key: 'b', name: 'b', status: 'failed', message: 'Network' },
			{ key: 'c', name: 'c', status: 'skipped', message: 'Empty' }
		];
		expect(nextWaiting(q)).toBe(-1);
		const again = retryFailed(q);
		expect(again.map((i) => i.status)).toEqual(['done', 'waiting', 'skipped']);
		expect(again[1].message).toBe(null);
		expect(nextWaiting(again)).toBe(1);
	});
});

describe('queue wording', () => {
	it('words each status', () => {
		const item = (status: QueueItem['status'], message: string | null = null): QueueItem => ({ key: 'k', name: 'n', status, message });
		expect(queueItemText(item('waiting'))).toBe('Waiting to upload');
		expect(queueItemText(item('uploading'))).toBe('Uploading…');
		expect(queueItemText(item('done'))).toBe('Uploaded');
		expect(queueItemText(item('failed', 'The connection dropped.'))).toBe('Didn’t upload. The connection dropped.');
		expect(queueItemText(item('skipped', 'That file is empty.'))).toBe('Not uploaded. That file is empty.');
	});

	it('summarises progress, then the outcome', () => {
		const q = makeQueue([photo('a.jpg'), photo('b.jpg'), photo('x.txt', 'text/plain')]);
		expect(queueSummary(q)).toBe('Uploading 1 of 2. Keep this page open until it finishes.');
		q[0].status = 'done';
		q[1].status = 'uploading';
		expect(queueSummary(q)).toMatch(/^Uploading 2 of 2/);
		q[1].status = 'failed';
		expect(queueSummary(q)).toBe('Uploaded 1 of 2 files. 1 file didn’t upload; you can try it again. 1 file couldn’t be used; see why below.');
		q[1].status = 'done';
		expect(queueSummary(q)).toBe('Uploaded 2 of 2 files. 1 file couldn’t be used; see why below.');
	});

	it('says so when no file could be used', () => {
		expect(queueSummary(makeQueue([photo('x.txt', 'text/plain')]))).toBe('That file couldn’t be used; see why below.');
		expect(queueSummary(makeQueue([photo('x.txt', 'text/plain'), photo('y.gif', 'image/gif')]))).toBe(
			'None of the 2 files could be used; see why below.'
		);
	});
});
