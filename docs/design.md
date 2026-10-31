# Kinfold: product and business design

Kinfold is a member-owned cooperative where people pay for each other's bad days instead of paying insurers' and banks' margins. It runs on one mechanic: **post a request, upload evidence, get an AI legitimacy score, and get paid by your family and friends or by the community.** A car crash and a down payment go through the same flow.

It runs as **one platform with one membership**, and each kind of money behind it sits in a separate entity.

The test for every decision: **does this leave members better off than a bank would?**

## The problem

A typical home buyer pays more in interest than the house is worth. A $400,000 mortgage at 6.5% over 30 years costs about $2,528 a month, and roughly $510,000 of the total is interest.

| Problem | Who it hurts | Why current options fail |
| --- | --- | --- |
| Interest burden | Every borrower | Banks profit from interest, so they have no reason to reduce it |
| Credit exclusion | Gig workers, immigrants, young people, people recovering from medical debt | A credit score can't see what a family or community knows about someone's reliability |
| Informal family loans go wrong | Both lender and borrower | No written terms, no tracking, and surprise tax problems lead to resentment and estrangement |
| One bad event costs the home | Households with no savings cushion | Insurance rarely covers job loss; payment-protection products are expensive and full of exclusions |
| Crowdfunding rewards popularity | People with small networks or less moving stories | Donation sites send money to whoever goes viral, not whoever needs it most |

Communities have solved parts of this for generations: rotating savings groups (tandas, susus, hui), interest-free lending in Islamic finance, mutual aid societies and early building societies. Kinfold gives those practices modern tools and fair rules.

## Principles

Every feature must pass all eight. A feature that would make money by breaking one doesn't ship.

1. **No interest, ever.** Members repay what they borrowed and nothing more. Where tax law requires a minimum rate on family loans, Kinfold shows it and arranges for it to be forgiven as a gift.
2. **Protect the lender as much as the borrower.** Nobody lends money they can't afford to lose. Lenders get clear warnings and a cap tied to their savings.
3. **Hardship is never a profit source.** No late fees or penalty rates. A missed payment starts a conversation and a plan, not a charge.
4. **Evidence, not popularity.** The community pool pays by legitimacy score (and, for the Home Fund, need), never by story quality or follower count. People without wealthy networks get the same ranking as everyone else.
5. **Keeping the home comes first.** Foreclosure is the very last resort, after payment pauses, restructuring, protection payouts and a voluntary sale where the family keeps its equity.
6. **Open books, private people.** Verified members see every pool request, its score band and its outcome on the board; anyone can see fees, reserve balances and monthly pool totals. Names, towns, exact dates and any figure small enough to point at one person never show. Every term fits on one screen.
7. **Members own it.** One member, one vote. Surplus goes back to members or into the fund, never to outside shareholders.
8. **AI advises, people decide.** Every score comes with its reasons. A low score asks for more evidence; only a person can turn a request down, and every refusal can be appealed.

## How it works: requests

Everything on Kinfold starts as a **request**. Insurance claims and home loans differ only in where the money comes from and whether it's paid back.

```
 Post request ──► Upload evidence ──► Legitimacy score ──► Funded
 (what, how much)  (PII removed)       (AI, explained)      │
                                                            ├─► Your people: gift or 0% loan
                                                            └─► Community pool: by score band
```

### 1. Post a request

The member picks a type (car damage, home repair, down payment, mortgage gap, loan payoff) and states the amount. Damage requests name the repair shop; home requests name the lender or seller. That payee matters: **money goes to the payee, not the member**.

### 2. Upload evidence

| Request | Typical evidence |
| --- | --- |
| Car damage | Photos (with original metadata), police or incident report, shop estimate, the other driver's insurer details if any |
| Home repair | Photos, contractor quote, proof of ownership |
| Down payment / mortgage gap | Purchase contract or mortgage statement, proof of income |
| Loan payoff | Loan statement showing balance and rate |

Evidence goes on the board once posted, so PII removal can't rely on the member alone (the original vision makes the member responsible, but people will miss a plate in a reflection). Kinfold runs automatic redaction (faces, plates, names, addresses, account numbers), the member reviews and confirms it, and the unredacted original is kept privately for the scorer and reviewers only.

### 3. Legitimacy score

An AI model scores 0 to 100 how well the evidence supports the request, and **shows its reasons** ("photo damage matches the estimate", "police report date matches", "no photos of the vehicle yet").

- The score measures **evidence**, not deservingness. Need is a separate input, used only for the Home Fund.
- A score below 70 never means "denied". It means "needs more evidence" and goes to a trained member reviewer.
- **Only a person can refuse a request**, in writing, with appeal to a member panel.
- The model, its version and its inputs are logged for every score, and it's audited yearly for bias (by neighbourhood, age, language and vehicle value).

### 4. Funded

- **Your people.** The member shares the request with family and friends by link. Each can give, or lend at zero interest using the Family & Friends tooling (agreement, tracking, gift letters).
- **The community pool.** Members pay a monthly subscription based on verified earnings. Most of it (the core share) funds the protection pool by rule; members choose where the rest goes (see "The subscription"). The pool holds back a reserve, then pays by legitimacy band: everything scoring 90 or above is filled first, **all at the same time**; if the pool can't cover the whole band, each request gets the same share of what it still needs; then the 80s, then the 70s. This is the "10 claims above 90%, filled concurrently" rule from the original vision, made precise. (Reference implementation: `apps/web/src/lib/requests/allocation.ts`.)
- Money from both sources stacks: **the pool pays what it covers first**, and family and friends fund the member's own share, anything above the cover cap, and anything the pool doesn't cover. The other way round, gifts would only save the pool money, and in a declared disaster FEMA expects insurance-type cover to pay before it does (44 CFR 206.191).
- **Pledges are all-or-nothing.** Nothing is charged until a request is fully funded, so a repair shop never gets a half-paid job. If a request is withdrawn, refused or expires, every pledge is released.

### The subscription

- A share of verified monthly earnings (proved through a read-only bank link, with tax returns or self-attestation plus random audit for people paid in cash), **$0 below a floor** and capped at the top. Design target (formula v1): nothing below $1,500 a month of take-home pay, 1% above it, capped at $60 a month, pending actuarial work.
- **80% is the core share** and always goes to the protection pool; the member directs the other 20% to car requests, home help or "highest score first". A pool that members could empty by redirecting it wouldn't be insurance, and a licensed partner couldn't accept it.
- A $0 subscriber is covered, but with a lower per-request cap until they've been a member for a year, so cover can't be farmed by joining for free.
- Verified earnings leave out disaster aid, gifts, pool payouts and loan proceeds, so help received never raises what a member pays.
- Money a member directs to home help goes to the fund as a whole, never to a named request.
- Year-end surplus is refunded or kept as reserves, by member vote.
### Fraud-proofing

| Attack | Defence |
| --- | --- |
| Quote from an expensive shop, repair at a cheap one | Payment goes to the named shop against its final invoice, not to the member |
| Staged crash | Cross-checks: police report, photo metadata and damage physics, the other party's identity, and patterns across requests, people, vehicles and shops |
| The same damage claimed twice, or also paid by an insurer, FEMA, SBA, a state programme or a charity | Photo fingerprinting across all requests; members declare other cover **and any other money for the same damage**, and agree to report recoveries that arrive later; insurer databases where a partner gives access. The same repair is never paid twice |
| Joining the day after a crash | Pool cover, and each vehicle, has a 60-day waiting period before the incident date |
| AI-generated or edited photos | Photos taken in the Kinfold app carry content credentials and device attestation and count for more; gallery uploads count for less; large requests get an in-person shop inspection |
| Fake repair shop | Payees are verified (business registration, bank account) before they can be paid |
| Fake accounts | Verified identity for every member; no anonymous requests |
| Friends inflating a score | Scores depend only on evidence, never on likes, shares or donations |
| A reviewer colluding with a member | Random second review of approvals; reviewers rotate and never see their own region's requests |

### Legal reality

These shape the roadmap; none is a reason not to build it, and all need counsel before launch.

- **A promise to pay is insurance.** If members pay in expecting their requests to be paid, regulators treat it as insurance, which needs a license and reserves. China's Xiang Hu Bao, Ant Group's mutual aid platform, served more than 100 million members and closed on 28 January 2022 amid China's fintech crackdown. So the community pool launches only through a licensed partner (or a licensed reciprocal exchange Kinfold sets up later), never as an unlicensed "no guarantee" sharing scheme.
- **Liability insurance stays mandatory.** Every US state except New Hampshire requires drivers to carry liability cover (Virginia's opt-out fee ended in July 2024), and New Hampshire still requires proof of financial responsibility after a crash. The pool starts by covering **your own damage** (collision costs and deductibles), which is the expensive part people can't afford, and can later pay members' liability premiums for them.
- **Disaster aid counts what we pay.** In a federally declared disaster, FEMA, SBA disaster loans and HUD rebuilding grants subtract insurance, gifts and other money for the same repair, and a member who already got the aid may have to repay it (42 USC 5155; 13 CFR 123.101 names gifts). Paying the payee makes every gift a gift for a specific repair, so it counts. We keep paying the payee (it stops fraud and laundering) and instead tell members, ask what aid they've had or applied for, and time gifts after insurance and public aid where that leaves the member better off.
- **Strangers lending at interest-free is still lending.** Gifts from anyone are fine, and so are loans between family and friends. Loans funded by the wider community are securities or lending, which is why community home help goes through the Home Fund and a credit union rather than strangers lending directly (in November 2008 the SEC ruled that Prosper's peer-to-peer loan notes were securities, and Prosper stopped selling them until its registration took effect in July 2009). A licensed payment partner moves all money; note that agent-of-payee exemptions from money-transmitter licensing vary by state, so Kinfold relies on the partner's licences, not an exemption.

## Paying it back, and when you can't

Gifts and pool payouts are never repaid. Loans are: zero-interest loans from family and friends, and Home Fund loans. Everything about repayment, including what happens if it stops, is agreed and signed **before** any money moves, so nobody improvises in a crisis.

### How repayment works

- **Monthly, on payday.** The borrower picks a payment day (1st to 28th) and the payment partner collects it automatically from their bank and sends it to the lender (or the Home Fund). Equal installments; the last one takes the rounding, so the total is exactly what was borrowed.
- **No interest and no late fees, ever.** There is no interest column anywhere in the database.
- **Prepay any time**, with no penalty.
- **Home Fund loans** can instead use income-based payments (a set share of verified take-home pay, so payments fall automatically if income falls), because the Fund lends to people with less cushion.

### If the borrower can't pay

Each step is tried before the next. None of them costs the borrower money.

| Step | What happens | Who decides |
| --- | --- | --- |
| 1. A missed payment | Reminder, then a 10-day grace period. No fee. The missed installment shows in the app for both sides | Automatic |
| 2. Pause | Up to 3 months in any 12 (the default; set at signing). Every unpaid installment moves back; the total owed doesn't change | Borrower alone, within the allowance |
| 3. Restructure | Smaller payments over a longer term, or a new start date. A new schedule both sides sign | Borrower and lender together |
| 4. Hardship request | The borrower posts a request so friends, or the pool once home cover exists, pay the installments | Same request flow as everything else |
| 5. Partial forgiveness | The lender forgives some of the balance as a gift; Kinfold produces the gift paperwork | Lender |
| 6. Mediation | A neutral, trained mediator helps agree a plan | Both, with the mediator |
| 7. The agreed default plan | Applied only when repayment has truly stopped (see below) | Set at signing; applied after mediation |

**The default plan** is chosen by both sides when the loan is signed, one of:

- **Forgive the rest.** The balance becomes a gift. Good for small loans between close family.
- **Repay on sale or cash-out refinance** (secured loans only). The lien on the home stays and is paid when the home is eventually sold, or refinanced in a way that takes cash out; a plain rate-and-term refinance gets the lien resubordinated instead. Nobody forces a sale. The lender's money waits in the home's equity, but a lien behind other liens may have little equity behind it at first, and the lender is told so at signing.
- **Mediate.** A mediator's agreement decides.

**Protecting the lender:** lending is capped by the lender's savings, with a plain warning if a loan is more than they could afford to lose. Borrowers can add an optional guarantor from their own circle, social backing in place of fees: Hebrew Free Loan societies lend at 0% with guarantors and report defaults under 1%, while Kiva's peer-vouched US loans repay far worse than its partner-checked ones. Because Kinfold documents every loan properly (written agreement, schedule, payment records), an unpaid family loan can qualify as a bad-debt tax deduction for the lender, which an informal handshake loan usually can't.

**What a missed payment does to the borrower's record:** the reliability record counts plans honoured, not perfection. A pause or a restructure that's then kept counts as reliable; only payments missed with no plan count against it. Kinfold never reports to credit bureaus negatively.

### Mortgages

Kinfold doesn't hold anyone's first mortgage, so the bank's rules apply to it. Kinfold's job is to keep the member in the home:

1. **Shrink it up front:** family money for the down payment, as a gift by default (lenders accept a gift letter stating the amount, that no repayment is expected, and the donor's relationship).
2. **Bridge a gap:** a zero-interest Home Fund loan covers missed mortgage payments while the member gets back on their feet, repaid monthly or income-based afterwards.
3. **Get the bank's own relief:** Kinfold connects the member to a HUD-approved housing counselor to ask for forbearance or a loan modification early. US rules generally stop a servicer starting foreclosure until a borrower is more than 120 days behind, so there is time if the member acts early.
4. **Last resort, sell on your terms:** if keeping the home isn't possible, a sale before foreclosure keeps the family's equity instead of losing it at auction.

Home Fund down-payment loans run through a programme mortgage lenders already accept, which decides who can be the lender of record:

- **Fannie Mae Community Seconds** accepts governments, housing agencies, 501(c)(3) charities, Home Loan Banks, employers and tribes, not a cooperative or a credit union. The Home Fund charity (see "Structure") qualifies.
- **Freddie Mac Affordable Seconds** accepts a credit union (if it isn't also making the first mortgage, outside Home Possible), a nonprofit, or an already-certified CDFI.

Default terms: 0%, no payments until the home is sold or stops being the main residence, and a maturity no earlier than the first mortgage's (Fannie bars a required payoff before the earlier of 15 years or the first mortgage's maturity). Deferred payments keep the loan out of the member's debt-to-income ratio, and total housing cost stays at or below about 30% of income (Habitat for Humanity's rule), re-measured yearly. The no-payment shape also qualifies for lighter federal disclosure rules (12 CFR 1026.3(h)). CDFI certification counts a deferred loan only if a payment falls due within 12 months, so confirm with the CDFI Fund before relying on longer deferrals for certification.

Home Fund loans are secured by a lien behind the bank's and behind any public-assistance liens, with all liens together at or below 105% of the home's value. They follow the same ladder: pause, restructure, income-based payments, and on true default, repayment when the home is sold or refinanced with cash out. **The Fund never forecloses.**

Bridge and debt buy-out loans (steps 2 and 3 of "What it funds") are not Community or Affordable Seconds. They need their own lending-licence review, and federal ability-to-repay rules apply unless the lender is a certified CDFI or a 501(c)(3) lending only to households at or below 80% of area median income (12 CFR 1026.43(a)(3)).

### Tracking what people give and receive

**Yes, track it, but show it only to the member, and never use it to decide who gets help.**

Each member has a private **giving record**: subscriptions paid, gifts given, money lent, and money received from the pool and from people. It makes the cooperative feel fair, shows members what their money did, and gives them a reason to keep helping.

What it must not do:

- **Rank or refuse requests.** Insurance works because unlucky people receive more than they paid; that's the point. Prioritising "givers" would turn the pool back into a popularity contest, punish people who can't afford to give, and is the kind of unfair discrimination insurance regulators prohibit.
- **Be public.** Showing who has taken more than they've given invites shame and pressure.

What it can feed, openly and by published rule: **how often** a member's pool requests are paid (in the last three years) raises their own share of the next request, the same way a deductible works. Frequent claimants pay more of their own repair; they never wait longer or get refused.

## Dashboards

Four dashboards, one per audience. Each shows only what its audience is allowed to see; none is a back door to another's data.

| Dashboard | Who sees it | What it shows |
| --- | --- | --- |
| **Member home** | The member | Open requests with status, score and its reasons; loans given and taken with the next installment; pauses and missed installments; subscription and pool cover; the reliability record and the private giving record |
| **Public transparency** | Anyone, on the website | Per fund: money in, requests paid, money paid out, reserve held against the 20% target, pool runs and how often a run fell short. The expense share against the ~15% target and every fee. The measures in "How we know it's helping", headed by **the share of help reaching households without wealthy networks** |
| **Members-only board** | Verified members | Every pool request from the last 12 months (and any still open) with its member-confirmed redacted summary, outcome, amount band and 10-point score band, by month and by state, or by Census division where the state has fewer than 1,000 active members. The exact amount shows only while a request is still being funded, because givers need it. Never names, towns or exact dates |
| **Operations console** | Reviewers, panel, staff | The review queue, scores near the review line, fraud signals, appeals, daily reconciliation breaks, reserve alerts, and score gaps by model version for the bias audit |

Rules for all four:

- **Small numbers identify people.** "One roof request in Vermont this week" points at a person, and so does the difference between two live totals. So:
  - Public figures are **monthly snapshots of ended months, never live**, so one new request can't be read off as a change.
  - A count of 1 to 10 shows as "10 or fewer" (CMS hides 1 to 10; CDC under 10).
  - A dollar total shows only when it covers at least 11 requests and no one request is half of it, rounded to $1,000.
  - A percentage needs a base of at least 30 (NCHS's rule for a share).
  - When one cell of a breakdown is hidden, a second is hidden too, or small cells roll up (state to Census division to national; month to quarter to year), so nothing can be worked out by subtraction. Snapshots never overlap and have no all-funds or all-time totals until that's built.
  - Free text is the riskiest field: the board's summary is redacted automatically, then confirmed by the member before it shows, and confirmed again after any change.
- **The giving record never leaves the member's own dashboard.** It isn't on the operations console either; reviewers decide requests without it.
- **Every console read of PII is audit-logged**, the same as signed-URL evidence views.
- **The transparency dashboard is the grant report.** Funders and agencies (see "Public and grant funding") get the same aggregates the public sees, plus the extra aggregates a grant requires. Any loan-level report an agency requires (the CDFI Fund asks for census tract and some demographics) goes only to that agency under a written data agreement, never onto a dashboard.
- **A missed installment shows as the next step**, worded the same for borrower and lender ("Behind by $120 · pause available"), never as a running count of misses.

## Business model review: gotchas and fixes

A critical read of the model above, and what changed because of it. Each fix is already reflected in the sections above and in the database (`apps/backend/supabase/migrations`).

### The big ones

| Gotcha | Why it breaks the model | Fix |
| --- | --- | --- |
| **Pricing by earnings alone invites adverse selection** | A careless driver pays the same as a careful one. Careful drivers leave, the pool gets riskier, payments rise: the classic insurance death spiral | Keep earnings-based pricing (it's the point), but put the risk in **cover terms**: per-request caps tied to vehicle value, a member share that rises with how often you claim, and waiting periods. Price stays fair; abuse gets expensive |
| **Fully member-directed money isn't a pool** | If everyone points their money at home help, car requests go unpaid, and "insurance" that may not pay is just crowdfunding | 80% core share to the protection pool by rule; members direct the 20% |
| **Joining after the crash** | Nothing stops someone signing up, paying $0 and posting a request the same week | 60-day waiting period on cover and on each newly added vehicle, enforced in `submit_request` |
| **A monthly pool can run dry** | One hailstorm could use a month's money and leave everyone else waiting | 20% of every run held as reserve, reinsurance for disasters, and lower bands wait for the next run rather than being refused |
| **Partial funding helps nobody** | A shop won't fix half a car | Pledges are all-or-nothing; pool grants and friends' pledges stay pledged until the request is fully covered |
| **Generative AI makes photo evidence cheap to fake** | In 2026 a convincing damaged-bumper photo takes seconds | In-app capture with content credentials counts more; photo fingerprints are compared across all requests; large requests get a physical inspection |
| **"Legitimacy score" sounds like an accusation** | Telling an honest member they scored 55% legit implies fraud, and regulators look hard at AI that affects claims (the NAIC's December 2023 model bulletin on insurers' use of AI, adopted by 27 states plus DC and Puerto Rico by October 2026, expects a written AI programme with governance and testing for unfair discrimination; California, Colorado, New York and Texas have their own rules) | Recommend calling it an **evidence score** in the app: it measures how well the evidence supports the request. Low scores ask for more evidence and never refuse |
| **Public board leaks identity even without names** | "$2,840, rear-ended, Tuesday, Springfield" identifies a neighbour | Board is visible to verified members only, shows state and week (never town or exact date), and only the redacted summary; the open-to-everyone site shows aggregate numbers |
| **Family loans can block the mortgage** | A repayable family loan counts toward debt-to-income, and Fannie Mae only accepts a second lien that charges a market rate, so a 0% family lien doesn't fit a Fannie mortgage at all (FHA does allow secured family loans) | Down payments default to **gifts** with a gift letter. The app asks the mortgage type before offering a lien: secured 0% family loans only with FHA or with the first lender's written approval; otherwise an unsecured note that counts toward debt-to-income, and the app explains the trade-off |
| **Money moving between people is money transmission** | Holding or routing funds between members needs state money-transmitter licenses | A licensed payment partner moves all money; Kinfold records it but never holds it |
| **A fake request can launder money** | Pay "gifts" into a staged request, get clean money out | Money only ever goes to verified payees (shops, lenders, sellers), never to the member; payers are identity-checked above partner thresholds |
| **When another driver is at fault, their insurer should pay** | Otherwise the pool subsidises other insurers | The pool pays the member's deductible and gap straight away, and the member assigns the recovery right (subrogation) to the partner insurer, which claims from the at-fault insurer and refunds the pool |

### Unit economics

Kinfold's costs per request are real even though it charges no interest: identity checks (about $0.50 to $3 a member at list prices), bank links (vendors don't publish prices; budget about $1 to $2 a connection a year until quoted), AI scoring (cents), human review (the big one, minutes per borderline request), payment fees (0.25% to 3%), the partner insurer's fronting fee (often 5% to 10% of premium) and reinsurance. At ~$15 average monthly subscription, an expense share around 15% leaves room for these and still beats the roughly 25% to 28% US property and casualty insurers spend on underwriting expenses (25.3% in AM Best's January 2026 figures). Rules that keep it there:

- AI does the first pass on every request; people handle only the low-score, flagged and appealed ones. Score agreement is tracked so automation only grows where it's proven accurate.
- Givers see payment fees and can choose to cover them.
- A partner repair-shop network with agreed labour rates lowers what requests cost in the first place.

### The insurance structure over time

1. **Launch: managing agent with a fronting carrier.** Kinfold designs the product, runs the app and scoring; a licensed insurer issues the cover and holds the reserves; reinsurers take catastrophe risk.
2. **Later: a reciprocal exchange.** Members insure each other directly, with Kinfold as the manager (attorney-in-fact). Surplus legally belongs to members, which is the cooperative's whole idea (Erie Insurance Exchange and USAA are reciprocals). Attorney-in-fact fees are a known conflict of interest (Erie's manager may keep up to 25% of premium), so Kinfold's fee would be capped in the bylaws. Needs capital and a license, so it waits for proven loss data.

### What's still unsolved

- **Fair cover limits for $0 subscribers** need real loss data before they're set.
- **The scoring model** needs a labelled evaluation set before launch, and a decision on vendor model vs. self-hosted.
- **Cross-state rules**: insurance and lending law is per state; the first state is chosen partly for how friendly its regulator is to new models (Kentucky, Vermont, West Virginia, North Carolina and South Dakota run insurance sandboxes; Utah runs a general one).

## Structure: one platform, partners behind it

**Recommendation: one app, one membership, separate legal entities and money pools.** The member sees one front door. Behind it, each piece is run by whoever is licensed to hold that kind of money.

| Piece | Who runs it | What the member sees |
| --- | --- | --- |
| Family & Friends requests | Kinfold runs the software; money moves between people through a payment partner | Share a request; friends give or lend at 0% |
| Community protection | A licensed partner insurer (later, Kinfold's own licensed reciprocal) holds the pool | Pay an earnings-based subscription; post damage requests to the public board |
| Community Home Fund | **Kinfold Home Fund**, a separate 501(c)(3) public charity whose board the cooperative elects. It owns the loans, receives gifts, grants, program-related investments and federal awards, and keeps its money in its own accounts at a partner credit union. Kinfold runs the app and the selection rules for it, at fair market value | Apply for zero-interest help, or give |
| Mortgage matching | Partner lenders, ideally credit unions and community lenders | A fair first mortgage, with family loans and fund help already counted |

### Why one platform

- **The pieces make each other safer.** Protection is what makes relatives willing to lend. Repayment history is what lets people without good credit get fund help. Separate apps break those links.
- **Life isn't split by product.** After a job loss, a member needs payment cover, a pause on the family loan and help talking to the mortgage lender, all at once.
- **Trust builds in one place.** Payments, contributions and repayments become one reliability record that replaces a credit score.

### Why not one company holding everything

- **One bad event could sink it all.** A recession brings claims and defaults together. With pooled money, insurance reserves get used to cover loans and members lose both.
- **Conflicts of interest.** A company that both lends and insures can be tempted to deny a claim to protect its loan book.
- **Licensing.** Insurance, deposits and mortgage lending each need different licenses and capital. Partners who hold them let the people-first parts launch years sooner.

### Mortgages: partner, don't originate

Kinfold does not write first mortgages. That needs huge capital and is where the pressure to charge interest lives. Kinfold's value is everything around the mortgage: making the bank mortgage smaller (family loans, zero-interest fund help), protecting the payments, and steering members to fair lenders. Over time, the fund's shared-equity homes become Kinfold's own interest-free alternative to a mortgage.

## Product 1: Family & Friends requests

A member shares any request (a car repair, a down payment, a loan payoff) with the people they choose. Each can give, or lend at zero interest. Gifts need nothing more; loans get the tooling below, which turns an informal family loan into a clear, documented, low-stress arrangement. Money moves between people through a payment partner; Kinfold never holds it.

**How it works**

1. **Plan together.** Borrower and lenders set the amount, schedule and purpose. A guided conversation covers the hard questions up front: what if payments stop, what if the lender needs the money back, what happens if someone dies.
2. **Check affordability on both sides.** The borrower sees whether payments fit their budget. The lender sees the loan against their savings, with a clear warning if it's more than they can afford to lose.
3. **Sign plain-language documents.** A promissory note, plus a recorded lien on the home for larger loans where the first mortgage allows it (see "Family loans can block the mortgage"). Where a minimum interest rate is required, Kinfold calculates it and sets it up to be forgiven as a gift.
4. **Repay and track.** Automatic payments, a shared balance, gentle reminders.
5. **Gift instead of lend.** Lenders can forgive part of the balance each year within the annual gift-tax exclusion ($19,000 per recipient in 2026). Kinfold tracks it and produces the paperwork, including mortgage lenders' gift letters.

**Protections built in**

| For the borrower | For the lender |
| --- | --- |
| Hardship pause: up to three months without penalty, agreed in advance | Lending cap tied to the lender's savings |
| Can post a hardship request to friends or the pool | Repayments can resume from a funded hardship request |
| No late fees, ever | Legal security: lien recorded on the home, where the first mortgage allows |
| Prepay at any time | Clear plan if the lender needs money back early |
| A neutral mediator if things get difficult | Estate planning: what happens to the loan if the lender dies |

**Tax note:** US rules (26 USC 7872) treat a below-market family loan above $10,000 as if it charged the Applicable Federal Rate. For loans totalling $100,000 or less, the imputed interest the lender must report is capped at the borrower's net investment income, and is zero if that is $1,000 or less (unless tax avoidance is a main purpose). The forgone interest is still a gift. If a documented loan goes unpaid, the lender may deduct it as a nonbusiness bad debt (a short-term capital loss) only if it was a bona fide loan and they made reasonable collection efforts, which Kinfold's records show. Document templates need review by a tax attorney before launch.

**For the member receiving help:** gifts from family and friends aren't income (26 USC 102); a giver who gives one person more than $19,000 in 2026 files a gift-tax return (Form 709), though tax is rarely due. Gifts from an employer are wages, not gifts. Requests paid straight to a shop don't put a Form 1099-K in the member's name, and the payment partner's own threshold is $20,000 and 200 transactions a year (26 USC 6050W(e), as amended in 2025).

## Product 2: Community protection

Damage requests paid from the community pool. **Cars first**, then homes, then other cover as reserves and data grow.

**What it covers at launch** (amounts are design targets pending actuarial review)

| Event | Cover | Why start here |
| --- | --- | --- |
| Damage to your car in a crash, at fault or not | Repair cost, paid to the shop | Collision cover is where premiums hurt most |
| Your deductible when another insurer pays | The deductible | A $1,000 deductible is a crisis for most households |
| Hail, flood, deer and other non-crash damage | Repair cost | Simple, photo-heavy evidence; good for proving the scorer |

**Not at launch:** liability for injuring someone else (stays with a licensed insurer, as the law requires), health, and life.

**How the money works**

1. **Subscriptions** (earnings-based, member-directed; see "How it works") go into a ring-fenced pool held by the licensed partner.
2. **Requests** are scored and paid by band, highest first, filled concurrently.
3. **Reinsurance** covers rare disasters such as a hailstorm hitting a whole city.
4. **Surplus** at year end is refunded or kept as reserves, by member vote.
5. **In declared disasters** the pool decides within 30 days, outside the weekly run, and gives the member a payment statement or a decline letter: FEMA won't consider an insured loss without one. The pool never waits to pay "after FEMA".

Payouts reimburse a loss, so they aren't income, but they reduce any casualty-loss tax deduction (IRS Publication 547). The app tells members both things when a request is paid.

**Pointing members to public help:** the pool sits beside public programmes rather than taking their money. Kinfold points members to state low-cost auto insurance where it exists (California's covers liability only, which pairs with the pool's own-damage cover), the state FAIR plan when no insurer will cover a home, roof-strengthening grants such as Strengthen Alabama Homes (up to $10,000, paid to the contractor), and FEMA, SBA and USDA repair help after disasters. None of that money enters the pool.

**Fairness rules:** the subscription depends on earnings, never on neighbourhood, race, credit score or proxies for them; scores depend only on evidence; refusals are made by people, in plain language, with appeal to a member panel.

## Product 3: Community Home Fund

For people with no wealthy family to borrow from. Lends without interest, allocated by need and readiness.

**Where the money comes from**

- **Gifts** to the Home Fund charity, tax-deductible for people who itemize, and from 2026 up to $1,000 ($2,000 joint) for people who don't (26 USC 170(p)), which needs the Fund to stay a public charity. Gifts go to the Fund as a whole; a gift pointed at a named family's request isn't deductible (IRS Publication 3833), so those go through Family & Friends instead.
- **Community investment notes, later:** zero-interest notes members can withdraw on notice, only after state securities counsel signs off. They're investments, not insured savings, and not deductible; only banks and credit unions may call anything a "deposit".
- **Matching and program-related investments:** foundations, employers and local governments match small gifts, weighted toward census tracts that meet the CDFI Fund's income and poverty tests (never chosen by racial makeup); foundations can also lend to the Fund at 0% to 1%, or back its loss reserve.
- **Repayments:** every repaid dollar goes back out to the next family.
- **Surplus** from the cooperative's fees.

**What it funds** (in priority order)

1. **Keeping a home:** bridging a gap so a family isn't foreclosed on or evicted.
2. **Down payments:** zero-interest second loans that shrink the bank mortgage.
3. **Buying out expensive debt:** replacing a high-rate loan on a home with a zero-interest one.
4. **Over time, whole homes:** shared equity. The fund co-owns a home and the family buys the fund's share back with no interest; the repaid share funds the next family.

**Who it helps:** households at or below 80% of area median income, households facing foreclosure or eviction, and households in a designated distressed area: the charitable class the Fund exists for. An account is free and a subscription is never a condition of help, because a charity can't keep its help for paying members.

**How applicants are chosen:** the same request, evidence and legitimacy score as every other request, plus a published needs formula covering need, readiness and reliability (rent paid on time, family loan repayments). The formula uses no prohibited basis under fair-lending law, and public-assistance income counts like any other income. A member panel reviews edge cases. Directors don't borrow from the Fund while they serve. Hardship details stay private; the board shows only the request type, amount band, score band and outcome.

**Public money stays in the funder's name:** FHLB, HOME, CDBG and state housing-agency help goes to the household under that programme's own note and lien, never into the Fund, because programme rules follow the money forever (HOME repayments stay HOME money, 24 CFR 92.503) and a city's HOME agreement would usually oblige the lien holder to enforce it. The Fund's own loan is sized last, to fill the gap that's left.

**Contributor safety:** a gift is a gift: it isn't returned. Until notes are approved, the Fund takes only gifts, grants and program-related investments. The Fund's money, repayments and surplus are used only for charitable lending and never return to the cooperative or its members as members; on dissolution they go to another charity.

## How the pieces connect

```
 Requests + evidence ──► Scores people can trust ──► Friends and pool pay
         ▲                                                  │
         │              One membership,                     ▼
   Money recycles ◄──── one reliability record ◄──── Repayments, subscriptions
```

Every request scored, subscription paid and loan repaid adds to one reliability record. The record replaces a credit score and opens the Home Fund to people banks overlook, and repaid money funds the next family. Loan money and the protection pool never mix.

**A member's journey: Maria**

1. Maria rents and has a thin credit file. She joins Kinfold and pays about 1% of her earnings into the pool.
2. She posts a home request and shares it with family. Her aunt lends $30,000 at zero interest, with a written agreement recorded on the home.
3. Maria buys with a smaller bank mortgage and pays thousands less in interest.
4. In year two someone rear-ends her car. She posts a damage request with photos and the police report; it scores 96% and the pool pays the shop in three days.
5. Her on-time repayments build a reliability record that opens the Home Fund for a roof repair.
6. Maria now points her subscription at home requests, helping the next family.

## Sustainability

Flat, published fees for real work, never interest or penalties. Grants fund the early years and fund matching.

| Revenue source | What members pay for | Guardrail |
| --- | --- | --- |
| Family loan setup fee | Documents, lien recording, tax setup | Flat, not a percentage; waived for low-income members |
| Loan servicing | Payment processing, tracking, yearly tax paperwork | Small flat monthly fee, shown before signing |
| Pool admin share | Scoring, review and paying requests | Capped, published share of subscriptions; the rest stays in the pool |
| Mortgage matching (no fee) | Matching members to fair lenders | Kinfold takes **no referral fees** from mortgage lenders: RESPA section 8 bans them, and disclosure doesn't cure it |
| Employer benefit | Employers offer membership as a housing benefit | Employer pays; members' terms are identical |
| Grants and impact funding | Home Fund lending and matching (through the Home Fund charity); co-op start-up only for specific charitable projects | Funders get no say over individual decisions |

**Kinfold never:** charges interest, charges late fees, sells member data, earns hidden returns on members' money, or takes outside investors who expect profits from members.

### Public and grant funding

Insurers' government billions mostly come from programmes where the government subsidises or backstops the cover itself. In federal crop insurance the government pays about 60% of farmers' premiums and pays insurers 12% to 22% of premium for running the policies. In flood insurance (NFIP) the government is the insurer, and private companies sell and service the policies for a fee. In ACA and Medicare Advantage, subsidies follow the customer to the insurer. Terrorism cover has a federal backstop (TRIA). **None of these subsidies covers car damage, deductibles or home repairs**, and Kinfold's pool isn't the insurer anyway (the partner is). Disaster aid and some state programmes do pay for repairs, but they sit beside the pool (see Product 2), not inside it. The public money that fits Kinfold is on the **lending and housing** side, and nearly all of it goes to the **Home Fund charity**, not the cooperative:

| Source | What it funds | Fit and catch | When |
| --- | --- | --- | --- |
| **Foundations and impact funders** | Home Fund lending, matching, its start-up costs | Grants go to the Home Fund charity, or through a fiscal sponsor until the IRS recognises it. A foundation can fund the cooperative itself only for a specific charitable project, with expenditure responsibility and the money kept separate (Treas. Reg. 53.4945-6). The cooperative's own start-up costs come from member capital, cooperative or CDFI loans, and development-centre help | Stage 0 onward |
| **Program-related investments** | Loans to the Fund at 0% to 1%, or deposits and guarantees at the partner credit union that back the loss reserve | Debt only, never equity. The foundation needs no extra oversight when the borrower is a public charity (Treas. Reg. 53.4944-3) | Stage 3 |
| **CDFI Fund (US Treasury)** | Technical Assistance grants ($10,000 to $150,000 in the FY2025 round, no match required) for "emerging" lenders not yet certified; Financial Assistance and capital for certified CDFIs. Certification also brings bank investment, because banks get CRA credit for funding CDFIs | The best fit, for the Home Fund. Only an entity holding loans on its own books can certify (loans the credit union keeps count for the credit union), so it must be the Home Fund charity, and it must exist before applying. Certification needs: a primary community-development mission, financing as a main activity, at least 60% of loans (by number and dollars) to a target market, development services, accountability to that market (today a third of the board; a September 2026 proposal would measure it by lending), and not being a government body. Race-based target markets are being removed, so use low-income households or qualifying census tracts. An emerging CDFI must certify by its award agreement's date, within about three years. Funded at $324M for FY2026 after the administration proposed cutting it; payouts have run late and no FY2026 notice was out on 2026-10-30, so don't plan around a set date | TA once the Home Fund charity exists and has a lending plan (end of Stage 2); certify after a full fiscal year of lending in Stage 3 |
| **FHLB Affordable Housing Program** | Down-payment grants to first-time buyers at or below 80% of area median income, with counseling and a 5-year retention lien. Per-household cap $32,837 for 2026 (FHFA); each Home Loan Bank may set less | Only through a member bank or credit union, so the partner credit union must be an FHLB member willing to run the set-aside. The grant is the household's, in the credit union's name, stacked under the Fund's loan | Stage 3 |
| **State housing finance agencies; HOME and CDBG funds through cities** | Down-payment help and foreclosure prevention, the Home Fund's first two priorities | Local, competitive, income limits per programme. Each programme's lien stays in the funder's own name; Kinfold never administers HOME or CDBG paper. A city may be able to count the Fund's 0% loans as HOME match (24 CFR 92.220) | Stage 3, in the pilot city |
| **HUD housing counseling grants** | Counseling | Go to HUD-approved nonprofit agencies. Kinfold **partners with one** agency, certified under 24 CFR part 214, for every applicant and for the "get the bank's own relief" step, rather than becoming one | Stage 3 |
| **USDA Rural Cooperative Development Grants** | Free help setting up a co-op, from regional development centres | Paid to the centres, not to co-ops (FY2026: $200,000 to $1M per centre, rural focus). Kinfold uses a centre's help with forming the cooperative; it doesn't apply itself | Stage 0, co-op formation |
| **Local-government matching** | Home Fund matching (Product 3) | Relationship by relationship | Stage 3 |

**What grants must not buy:**

- **No say over individual decisions** (the Sustainability guardrail). Grant agreements fund the Fund, not a list of chosen families.
- **Only the records an award requires.** The CDFI Fund's yearly loan-level report asks for each loan's census tract and borrower demographics where collected, and accepts "Do Not Know". Federal auditors and inspectors general can see any loan file a federal award pays for (2 CFR 200.337), and the Fund's loan terms tell members so. Data terms are agreed in writing before signing.
- **Demographics only where the law allows asking.** Fair-lending law bars asking race, ethnicity or sex, with exceptions (12 CFR 1002.5). For home-purchase and refinance loans secured by the home, the lender must ask on the government monitoring form (1002.13), and Kinfold asks on the credit union's behalf. For every other Fund loan, Kinfold asks only as a voluntary fair-lending self-test with its four required disclosures (1002.5(b)(1)), or doesn't ask. The answers never reach the scorer, reviewers or panel; self-test results go to the board and the auditor, not the public; and CDFI reports show "Do Not Know" for self-test data.
- **No public money in the protection pool.** Grants may pay members' subscriptions from a separate labelled pot, fund mitigation, or fund operations; they never change cover terms or who the pool pays. Federal money inside the pool would turn payouts into federal aid and push them behind insurance in the payment order.
- **No eligibility rule that breaks a principle.** If a grant's income limits or target market would make the Home Fund refuse someone the formula would help, that money funds a separate, labelled pot; it doesn't change the formula.
- **No dependence.** Grant money pays for start-up and matching, never for running costs the fees must cover, so a cut programme pauses matching but not the cooperative.

**Federal money in a revolving loan fund comes with conditions** (2 CFR 200), so federally funded loans are tracked as their own pot:

- A single audit once federal spending reaches $1M a year, where the count includes new loans plus the opening balance of earlier federally funded loans (200.501, 200.502(b)).
- Repayments are programme income, bound to the programme's rules; ask for the "addition" method (200.307).
- The government gets a licence to work and data the award pays for (200.315), so federal money never funds the platform or the scorer.
- Awards can be ended when agency priorities change (200.340(a)(4)).

## Risks and safeguards

The biggest risk is mostly helping families who are already comfortable. The Community Home Fund and needs-weighted matching exist to counter it, and the share of help reaching households without wealthy networks is a headline measure.

| Risk | Who it hurts | Safeguard |
| --- | --- | --- |
| Helps people with rich relatives most | Families without wealth | Fund prioritised by need; matching weighted toward under-served areas |
| A family loan breaks a relationship | Both sides | Agreed plan up front, neutral tracking, hardship pause, mediator |
| A lender loses money they needed | Older and retired lenders | Lending cap tied to savings, warnings, hardship requests |
| A hailstorm or recession triggers many requests | Every pool member | Reinsurance, conservative reserves, separate entities |
| Fraud or scams | Contributors and lenders | Identity checks, payee-direct payment, cross-request pattern checks (see Fraud-proofing) |
| The AI scorer is wrong or biased | Honest members with thin evidence | Explained scores, people decide refusals, appeals, yearly bias audit |
| Public evidence exposes someone | Members and third parties in photos | Automatic redaction, member confirmation, originals kept private |
| Treated as unlicensed insurance | Everyone | Pool launches only with a licensed partner; legal review per state |
| Elder financial abuse | Older relatives | Independent lender confirmation, cooling-off period, unusual-pattern flags |
| Biased approvals | Applicants from marginalised groups | Published formula, bias audits, appeal panel |
| Conflict between lending and protection | Members with claims | Separate entities and pools; claims decided without reference to loan exposure |
| Mission drift | All members | Cooperative ownership; principles in the bylaws; no outside equity |
| Regulatory failure | Everyone | Licensed partners hold money; legal review before each launch |

## Governance

- **One member, one vote**, however much money a member has put in.
- **Reserved board seats** for borrowers, lenders, fund recipients and pool members.
- **Principles in the bylaws.** Changing "no interest" or "no late fees" needs a supermajority of all members.
- **Open books** every quarter: reserves, claims, fund allocations (anonymised), fees and costs.
- **Paid, rotating member panels** for fund edge cases and claim appeals.
- **Annual independent audit** of finances and of the fund formula's fairness.
- **The Home Fund charity is the cooperative's affiliate, not its property.** The cooperative elects its board. Services between them are at fair market value, approved by independent directors (26 USC 4958), and the Fund's assets never return to the cooperative or its members as members.

## Roadmap

Start with cars and requests paid by people you know: it exercises the whole request, evidence and scoring flow without holding anyone's money. Add the community pool only once scoring has proved fair. Durations are planning estimates. **The stage-by-stage build plan (what to build, in what order, and how each stage is tested) is [roadmap.md](roadmap.md); the data model and backend are [backend.md](backend.md).**

| Phase | When | Scope | Gate to move on |
| --- | --- | --- | --- |
| 1. Requests between people | Months 0 to 9 | Requests, evidence, redaction and scoring for car damage and home help; family and friends pay (gifts and 0% loans). No pooled money | Legal review passed; 500 requests scored; people agree with the score at least 9 times in 10 |
| 2. Community car pool | Months 9 to 18 | Earnings-based subscriptions, the members-only board, own-damage car requests, one state, licensed partner insurer | Requests paid within 7 days; fraud below target; books reconcile daily; credit union partner signed (a Home Loan Bank member); Home Fund charity formed |
| 3. Home Fund pilot | Months 18 to 30 | One city, the Home Fund charity lending through a credit union partner, matching funds, CDFI application | 25 fund loans repaying on time |
| 4. Grow | Year 3 onward | More cover types and states; members' own reciprocal insurer; shared-equity homes | — |

### How we know it's helping

| Measure | What it shows | Proposed goal |
| --- | --- | --- |
| Interest saved by members | Money kept by families instead of lenders | Reported quarterly, growing year on year |
| Homes kept | Foreclosures and evictions avoided | Zero foreclosures on Kinfold loans |
| Help reaching families without wealth | Share of fund money to households with no family lender | At least half of fund money |
| Lender losses | Whether lending relatives stay safe | None beyond what hardship requests cover |
| Loans back on track | Share of missed-payment loans that recover through pause or restructure | Most; few reach the default plan |
| Relationships intact | Yearly survey: did the loan help or hurt the family? | Most families say it helped |
| Request speed | Whether help arrives when needed | Paid within 7 days |
| Score agreement | Whether people reviewing agree with the AI score | At least 9 in 10 |
| Score fairness | Score gaps by neighbourhood, age and language, published only for groups of at least 30 members | No significant gap in the yearly audit |

## Open questions

- Which state to launch in first (lien recording, licensing and partner availability vary by state).
- Which credit union or community development lender to approach for the Home Fund pilot.
- Which licensed insurer to partner with for the car pool, and whether to set up Kinfold's own reciprocal exchange later.
- The subscription formula (floor, share of earnings, cap), which needs actuarial work.
- Which AI model scores requests, how it's evaluated before launch, and where evidence is stored.
- Legal form of the cooperative and its subsidiaries; needs a lawyer experienced in cooperatives and consumer finance. Choose a cooperative statute with no investor members (for example, not Minnesota 308B).
- The Home Fund charity: its Form 1023 timeline and public-support test, the services agreement with the cooperative, and how it is licensed as a lender in the launch state.
- Which target market to define for CDFI certification (low-income households, or the pilot city's qualifying census tracts) so that 60% of Home Fund lending meets it.
- Whether a 0% forgivable family loan counts as a "subsidized loan" when HUD calculates disaster-rebuilding grants (HUD excludes only private loans on typical commercial terms, 84 FR 28836).
- How the community pool's yearly bias audit gets demographics: the pool is insurance, not credit, so it is a state insurance-law question; estimating race from surname and geography (the CFPB's BISG method) avoids asking.
