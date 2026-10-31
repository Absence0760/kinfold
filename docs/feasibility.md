# Feasibility

Can Kinfold work? This is the honest answer, product by product, from the research behind [design.md](design.md) (the legal reports are in `reviews/legal-*.md`, git-ignored). It is research, not legal or actuarial advice; [followups.md](followups.md) lists the counsel each part still needs.

Last reviewed 2026-10-30.

## Verdict

**Buildable, but as a cooperative plus a charity, not a venture-backed company, and not all three products on equal footing.** Nothing found so far rules Kinfold out: every legal problem the research hit has a known, lawful structure behind it. The three products differ sharply in risk.

| Product | Verdict | Why |
| --- | --- | --- |
| Family & Friends requests and 0% loans | **Works** | Documents, schedules and a payment partner moving money between people who know each other. Light licensing; families already pay for family-loan paperwork. Revenue (flat fees) is small, so it doesn't pay for review staff and scoring on its own |
| Community Home Fund | **Works, as a charity, at the speed of its funding** | A century-old model: Hebrew Free Loan societies lend at 0% with defaults under 1%, and CDFI loan funds and housing charities do this today. It must be a 501(c)(3) the cooperative controls (see design.md, "Structure"). A 0% lender earns nothing on its money, so it grows only as fast as gifts, grants and program-related investments arrive |
| Community car cover | **Works only as changed** (see "Community car pool" below) | The original earnings-priced pool is unlawful and unaffordable; deductible cover bought by the cooperative, plus a gift-funded repair fund and 0% repair loans, works. The gating risk is finding a partner insurer |

## What it takes overall

- **No outside equity, by design**, so no venture capital. Money comes from member fees, grants (through the Home Fund charity), program-related investments, and cooperative or CDFI loans. Growth is slow.
- **Legal work before launch is real and costs money**: tax-exempt, securities, consumer-finance, insurance-regulatory, disaster-recovery and cooperative-law counsel (followups.md, "Funding and structure").
- **The roadmap's order protects the project.** Stage 1 holds no pooled money, so if the car pool doesn't work, Kinfold still has a useful Family & Friends product and a path to the Home Fund.

## Community car pool

**Verdict: the original design doesn't work; a changed one does.** Researched 2026-10-30 from state rating law, current loss data and the record of earlier attempts (`reviews/legal-car-pool-rating.md`, `reviews/car-pool-economics.md`, `reviews/car-pool-precedents.md`, git-ignored). design.md and roadmap.md now describe the changed design.

### Why the original fails

The original: an earnings-based subscription funds one pool that pays own-damage car repairs by evidence-score band from whatever is available.

| Problem | Finding | Confidence |
| --- | --- | --- |
| **Pricing is unlawful** | No state checked lets an insurer price car damage cover by earnings. Rating laws require price differences to follow expected losses (Vt. § 4685, Tex. Ins. Code § 2251.051(d), Fla. § 627.0651(6)); California's rating factors are a closed list (Ins. Code § 1861.02); Michigan allows earned income only for lost-wage cover. A reciprocal exchange is held to the same law. Where income-based car cover exists (Hawaii, California's Low Cost Auto), a legislature created it | High |
| **"Pay what's available" is unlawful for insurance** | An insured claim must be paid in full on the state's clock (California 40 days to decide and 30 to pay; Texas 15 business days and 5, with 18% a year if late). Banded, partial payment is an unfair claims practice. Removing the promise instead makes it a discretionary scheme regulators shut down (US health care sharing ministries; a Montana faith-based car scheme in 2019) | High |
| **The money doesn't add up** | Full own-damage claims cost about $380 to $700 per member-year; the formula raises $19 to $36 a month on average, about 69 cents of each dollar reaching claims. Loss ratio 128% to 430% in every scenario modelled. Break-even dues for full cover are $47 to $84 a month, above the $60 cap | Medium (several inputs are assumptions) |
| **Adverse selection** | Members at the $60 cap pay $576 a year for cover worth about $390 and mostly already have collision cover, so they leave first; $0 members and drivers without collision cover stay, and skew younger and riskier | Medium-high |
| **Precedent** | Peer-to-peer car cover stalled, pivoted or closed: Guevara closed in 2017 unable to capitalise an underwriter, Friendsurance became a seller to banks, Xiang Hu Bao closed in 2022 after its cost per period rose about 8×. What survived prices by risk (Root, USAA, Kin) or stays small and capped with no promise (Broodfonds). No audited evidence that a "community" layer lowers claims | Medium-high |

### The design that works

| Layer | What it is | Why it works |
| --- | --- | --- |
| **Dues and a group policy** | The cooperative buys a group policy from a licensed insurer at one filed, broadly averaged rate per vehicle class and plan, and pays every member's premium from earnings-based dues. Members below the floor get the Basic plan, paid in full | The rate is risk-based and filed; earnings only decide what the member pays the cooperative. Vermont, Rhode Island and Florida law allow group-averaged rates. Anti-rebating law binds insurers and agents, so the cooperative, not Kinfold's agency, pays the premium |
| **Deductible cover first** | Pays the member's deductible, up to $1,000, when their own cover or the other driver's insurer pays. Claims paid in full, on the statutory clock | Breaks even at about $6 to $13 a month; loss ratio 17% to 66% at today's formula; almost no hail exposure; stable from a few hundred members |
| **Gap cover later** | Own damage up to $1,000 a year for members without collision cover | Breaks even at about $13 to $19 a month; raised only with loss data |
| **Community repair fund** | Gifts and grants only, capped repair grants paid to the shop, by evidence band | Nobody buys a right to it, so it isn't insurance and may pay partly; capped grant funds last (Broodfonds, Britepaths) |
| **0% repair loans** | Through a partner credit union or CDFI, paid to the shop, with a gift-funded loss reserve | Not insurance; low- and zero-interest repair lending repays well (Mission Asset Fund reports about 0.7% losses, Ways to Work about 10% against about 35% at buy-here-pay-here lots; self-reported) |

### What could still sink it

- **No partner insurer agrees.** A fronting carrier must accept the group, the rate filing and an unproven book. This is the gating risk; Guevara died here.
- **The regulator reads the cooperative's premium payments as a rebate** or doesn't accept the cooperative as a qualifying group. Needs insurance-regulatory counsel and, ideally, the regulator's written view before launch.
- **Dues can't fund Basic for everyone below the floor** if the membership skews low-income: the cooperative then needs grants for dues (allowed, from a separate labelled pot) or a smaller Basic plan.
- **Premiums the cooperative pays may be taxable income to members**; unresolved, needs tax counsel.
- The economics model uses assumptions (withholding, member mix, deductible spread, reinsurance and claims-handling rates); re-run it with the partner's real figures before signing.

**Bottom line:** car help is possible as **deductible cover bought by the cooperative, plus a gift-funded repair fund and 0% repair loans**. A single earnings-priced pool paying full repairs is neither lawful nor affordable.
