// The in-page sections the nav links to. Each `id` must match a section on the
// landing page; sections.test.ts fails if a link points at an id that is gone.
export interface NavSection {
	id: string;
	label: string;
}

export const navSections: NavSection[] = [
	{ id: 'requests', label: 'How it works' },
	{ id: 'board', label: 'Requests' },
	{ id: 'products', label: 'Products' },
	{ id: 'calculator', label: 'Savings' },
	{ id: 'principles', label: 'Principles' },
	{ id: 'roadmap', label: 'Roadmap' }
];
