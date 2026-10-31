# Kinfold

Help paid by people, not profit. Post a request (a car crash, a down payment, a loan), upload evidence, get an AI legitimacy score, and get paid by your family and friends or the community.

Kinfold is a member-owned platform with one app and one membership. Behind it, each product runs as its own legal entity with its own money:

| Product | What it does | Who holds the money |
| --- | --- | --- |
| **Family & Friends requests** | Share a request with your people; they give, or lend at zero interest with documents, tracking and gift letters | Nobody: money moves between people through a payment partner |
| **Community protection** | Earnings-based subscriptions fund a public board of damage requests (cars first), paid by legitimacy score, highest first | A licensed partner insurer |
| **Community Home Fund** | Zero-interest home help for people with no wealthy family to ask, allocated by score and need rather than popularity | A partner credit union or community lender |
| **Mortgage matching** | Steers members to fair first mortgages, with family loans and fund help already counted | Partner lenders |

Kinfold never charges interest or late fees, and never writes first mortgages itself.

## The name

**Kin** is family, and the people you treat as family. A **fold** is a sheepfold, the walled pen that keeps a flock safe at night; "coming into the fold" means being taken in and looked after. Read together: your people, keeping each other safe. The suffix **-fold** (twofold, manyfold) adds the last idea: every repaid dollar goes on to help the next family, so help multiplies.

## Docs

- **[docs/design.md](docs/design.md)**: the product and business design: how requests work, repayment and hardship, the business-model review, structure, risks, governance
- **[docs/backend.md](docs/backend.md)**: the data model, where each rule is enforced, access model, edge functions
- **[docs/roadmap.md](docs/roadmap.md)**: what to build, stage by stage, with the gate for each
- **[docs/STACK.md](docs/STACK.md)**: tech stack and dev setup (`pnpm dev:run:web` → http://localhost:7790)
- [CONTRIBUTING.md](CONTRIBUTING.md) · [SECURITY.md](SECURITY.md) · [SUPPORT.md](SUPPORT.md)

## Status

Design stage. A preview website lives in `apps/web`; the database schema (Supabase, with pgTAP tests) lives in `apps/backend`. Next is Stage 1 of [docs/roadmap.md](docs/roadmap.md): requests paid by family and friends, with no pooled money.

## License

[MIT](LICENSE)
