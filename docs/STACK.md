# Stack

**Not chosen yet.** Kinfold is at the design stage. The product design lives in [design.md](design.md); read it before writing any code.

When the stack is picked, start from the matching `templates` branch (likely `mobile-fullstack` or `web-postgres`, since the product needs relational data and auth) and replace this file with that branch's `docs/STACK.md`.

## Domain rules that hold whatever the stack

These come from `design.md` and apply to every line of code:

- **No interest and no late fees in any code path.** A repayment schedule only ever sums to the principal. Where tax law needs a minimum rate on a family loan, it is calculated, shown, and set up to be forgiven as a gift.
- **The app never holds member money in Phase 1.** Family loans move directly between relatives; Kinfold stores records, documents and schedules. Pooled money (Community Home Fund, Protection Circles) only ever sits with a licensed partner, reached through their API.
- **The money pools stay separate.** Lending data and protection-reserve data live in separate schemas or services with no code path that moves funds between them.
- **Financial and identity data is sensitive.** Treat loan amounts, income, hardship details and identity documents as PII: encrypted at rest, least-privilege access, audit-logged reads.
- **Fund decisions are explainable.** The Community Home Fund scoring formula is versioned in code and its inputs logged, so any decision can be explained to the applicant and audited for bias.

## Setup

Nothing to set up yet beyond `pre-commit install` (gitleaks).
