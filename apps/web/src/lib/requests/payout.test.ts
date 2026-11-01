import { describe, expect, it } from 'vitest';
import { Constants } from '../../../../backend/supabase/database.types.ts';
import { payoutText } from './payout';

describe('payoutText', () => {
	it('words every payout status, naming the payee and never the member', () => {
		for (const status of Constants.public.Enums.payout_status) {
			const t = payoutText({ status, amount_cents: 125050, sent_at: null }, 'Ace Auto');
			expect(t.label, status).not.toBe('');
			expect(t.line, status).toMatch(/Ace Auto/);
			expect(t.line, status).toMatch(/\$1,250\.50/);
			expect(t.line, status).not.toMatch(/to you\b/);
		}
	});

	it('gives the sent date when the partner confirmed it', () => {
		const t = payoutText({ status: 'sent', amount_cents: 40000, sent_at: '2026-11-14T15:00:00Z' }, 'Ace Auto');
		expect(t.label).toBe('Sent');
		expect(t.tone).toBe('done');
		expect(t.line).toBe('$400 was sent to Ace Auto on Nov 14, 2026.');
		expect(payoutText({ status: 'sent', amount_cents: 40000, sent_at: null }, 'Ace Auto').line).toBe('$400 was sent to Ace Auto.');
	});

	it('says a failed or returned payout is Kinfold’s to follow up', () => {
		for (const status of ['failed', 'returned'] as const) {
			expect(payoutText({ status, amount_cents: 100, sent_at: null }, 'Ace Auto').line).toMatch(/you don’t need to do anything/);
		}
	});
});
