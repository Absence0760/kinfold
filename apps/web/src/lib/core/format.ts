const usd = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 });

/** Whole-dollar US currency, e.g. `$2,528`. */
export const formatUsd = (value: number): string => usd.format(Math.round(value));

/** Compact dollars for headlines, e.g. `$510k`. */
export function formatUsdShort(value: number): string {
	const v = Math.round(value);
	if (Math.abs(v) >= 1_000_000) return `$${(v / 1_000_000).toFixed(1).replace(/\.0$/, '')}M`;
	if (Math.abs(v) >= 1_000) return `$${Math.round(v / 1_000)}k`;
	return formatUsd(v);
}
