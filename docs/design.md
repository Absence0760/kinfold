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
6. **Public, except you.** Every request, score, payout, fee and reserve balance is public. Personal details never are. Every term fits on one screen.
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

Evidence is public once posted, so PII removal can't rely on the member alone (the original vision makes the member responsible, but people will miss a plate in a reflection). Kinfold runs automatic redaction (faces, plates, names, addresses, account numbers), the member reviews and confirms it, and the unredacted original is kept privately for the scorer and reviewers only.

### 3. Legitimacy score

An AI model scores 0 to 100 how well the evidence supports the request, and **shows its reasons** ("photo damage matches the estimate", "police report date matches", "no photos of the vehicle yet").

- The score measures **evidence**, not deservingness. Need is a separate input, used only for the Home Fund.
- A score below 70 never means "denied". It means "needs more evidence" and goes to a trained member reviewer.
- **Only a person can refuse a request**, in writing, with appeal to a member panel.
- The model, its version and its inputs are logged for every score, and it's audited yearly for bias (by neighbourhood, age, language and vehicle value).

### 4. Funded

- **Your people.** The member shares the request with family and friends by link. Each can give, or lend at zero interest using the Family & Friends tooling (agreement, tracking, gift letters).
- **The community pool.** Members pay a monthly subscription based on verified earnings, and choose where theirs goes: car damage, home help, or "wherever the score is highest". The pool pays by legitimacy band: everything scoring 90 or above is filled first, **all at the same time**; if the pool can't cover the whole band, each request gets the same share of what it still needs; then the 80s, then the 70s. This is the "10 claims above 90%, filled concurrently" rule from the original vision, made precise. (Reference implementation: `apps/web/src/lib/requests/allocation.ts`.)
- Money from both sources stacks: friends' money is counted first, so the pool only covers the gap.

### The subscription

- A share of verified monthly earnings (proved by bank statement through a read-only bank link, never by uploading a password), **$0 below a floor** and capped at the top. Design target: about 1% of take-home pay, pending actuarial work.
- Members direct their own payment. Unallocated money follows the score.
- Year-end surplus is refunded or kept as reserves, by member vote.

### Fraud-proofing

| Attack | Defence |
| --- | --- |
| Quote from an expensive shop, repair at a cheap one | Payment goes to the named shop against its final invoice, not to the member |
| Staged crash | Cross-checks: police report, photo metadata and damage physics, the other party's identity, and patterns across requests, people, vehicles and shops |
| The same damage claimed twice, or also claimed from an insurer | Photo fingerprinting across all requests; members declare other cover; insurer databases where a partner gives access |
| Fake accounts | Verified identity for every member; no anonymous requests |
| Friends inflating a score | Scores depend only on evidence, never on likes, shares or donations |
| A reviewer colluding with a member | Random second review of approvals; reviewers rotate and never see their own region's requests |

### Legal reality

These shape the roadmap; none is a reason not to build it, and all need counsel before launch.

- **A promise to pay is insurance.** If members pay in expecting their requests to be paid, regulators treat it as insurance, which needs a license and reserves. China's Xiang Hu Bao ran a similar public-claims mutual aid model with about 100 million members and was shut down under regulatory pressure in 2022. So the community pool launches only through a licensed partner (or a licensed reciprocal exchange Kinfold sets up later), never as an unlicensed "no guarantee" sharing scheme.
- **Liability insurance stays mandatory.** Almost every US state requires drivers to carry liability cover from a licensed insurer. The pool starts by covering **your own damage** (collision costs and deductibles), which is the expensive part people can't afford, and can later pay members' liability premiums for them.
- **Strangers lending at interest-free is still lending.** Gifts from anyone are fine, and so are loans between family and friends. Loans funded by the wider community are securities or lending, which is why community home help goes through the Home Fund and a credit union rather than strangers lending directly (US peer-to-peer lenders had to register with the SEC from 2008).

## Structure: one platform, partners behind it

**Recommendation: one app, one membership, separate legal entities and money pools.** The member sees one front door. Behind it, each piece is run by whoever is licensed to hold that kind of money.

| Piece | Who runs it | What the member sees |
| --- | --- | --- |
| Family & Friends requests | Kinfold runs the software; money moves between people through a payment partner | Share a request; friends give or lend at 0% |
| Community protection | A licensed partner insurer (later, Kinfold's own licensed reciprocal) holds the pool | Pay an earnings-based subscription; post damage requests to the public board |
| Community Home Fund | A partner credit union or community development lender holds the money; Kinfold runs the app and the selection rules | Apply for zero-interest help, or contribute |
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
3. **Sign plain-language documents.** A promissory note, plus a recorded lien on the home for larger loans. Where a minimum interest rate is required, Kinfold calculates it and sets it up to be forgiven as a gift.
4. **Repay and track.** Automatic payments, a shared balance, gentle reminders.
5. **Gift instead of lend.** Lenders can forgive part of the balance each year within the annual gift-tax exclusion. Kinfold tracks it and produces the paperwork, including mortgage lenders' gift letters.

**Protections built in**

| For the borrower | For the lender |
| --- | --- |
| Hardship pause: up to three months without penalty, agreed in advance | Lending cap tied to the lender's savings |
| Can post a hardship request to friends or the pool | Repayments can resume from a funded hardship request |
| No late fees, ever | Legal security: lien recorded on the home |
| Prepay at any time | Clear plan if the lender needs money back early |
| A neutral mediator if things get difficult | Estate planning: what happens to the loan if the lender dies |

**Tax note:** US rules treat a below-market family loan above $10,000 as if it charged a minimum rate (the Applicable Federal Rate, published monthly by the IRS). Document templates need review by a tax attorney before launch.

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

**Fairness rules:** the subscription depends on earnings, never on neighbourhood, race, credit score or proxies for them; scores depend only on evidence; refusals are made by people, in plain language, with appeal to a member panel.

## Product 3: Community Home Fund

For people with no wealthy family to borrow from. Lends without interest, allocated by need and readiness.

**Where the money comes from**

- **Members' contributions:** gifts, or zero-interest deposits withdrawable on notice.
- **Matching:** foundations, employers and local governments match small contributions, weighted toward under-served areas.
- **Repayments:** every repaid dollar goes back out to the next family.
- **Surplus** from the cooperative's fees.

**What it funds** (in priority order)

1. **Keeping a home:** bridging a gap so a family isn't foreclosed on or evicted.
2. **Down payments:** zero-interest second loans that shrink the bank mortgage.
3. **Buying out expensive debt:** replacing a high-rate loan on a home with a zero-interest one.
4. **Over time, whole homes:** shared equity. The fund co-owns a home and the family buys the fund's share back with no interest; the repaid share funds the next family.

**How applicants are chosen:** the same request, evidence and legitimacy score as every other request, plus a published needs formula covering need, readiness and reliability (rent paid on time, subscription payments, family loan repayments). A member panel reviews edge cases. Hardship details stay private; the public board shows only the request type, amount, score and outcome.

**Contributor safety:** contributors choose gift or deposit up front. Deposits are held by the regulated partner and backed by a loss reserve. The app says plainly that deposits carry risk and are not insured savings.

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
| Mortgage partner referrals | Matching members to fair lenders | Disclosed; never steers to a worse offer |
| Employer benefit | Employers offer membership as a housing benefit | Employer pays; members' terms are identical |
| Grants and impact funding | Start-up costs and fund matching | Funders get no say over individual decisions |

**Kinfold never:** charges interest, charges late fees, sells member data, earns hidden returns on members' money, or takes outside investors who expect profits from members.

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

## Roadmap

Start with cars and requests paid by people you know: it exercises the whole request, evidence and scoring flow without holding anyone's money. Add the community pool only once scoring has proved fair. Durations are planning estimates.

| Phase | When | Scope | Gate to move on |
| --- | --- | --- | --- |
| 1. Requests between people | Months 0 to 9 | Requests, evidence, redaction and scoring for car damage and home help; family and friends pay (gifts and 0% loans). No pooled money | Legal review passed; 500 requests scored; people agree with the score at least 9 times in 10 |
| 2. Community car pool | Months 9 to 18 | Earnings-based subscriptions, the public board, own-damage car requests, one state, licensed partner | Requests paid within 7 days; fraud below target; credit union partner signed |
| 3. Home Fund pilot | Months 18 to 30 | One city, credit union partner, matching funds | 25 fund loans repaying on time |
| 4. Grow | Year 3 onward | More cover types and regions; shared-equity homes | — |

### How we know it's helping

| Measure | What it shows | Proposed goal |
| --- | --- | --- |
| Interest saved by members | Money kept by families instead of lenders | Reported quarterly, growing year on year |
| Homes kept | Foreclosures and evictions avoided | Zero foreclosures on Kinfold loans |
| Help reaching families without wealth | Share of fund money to households with no family lender | At least half of fund money |
| Lender losses | Whether lending relatives stay safe | None beyond what hardship requests cover |
| Relationships intact | Yearly survey: did the loan help or hurt the family? | Most families say it helped |
| Request speed | Whether help arrives when needed | Paid within 7 days |
| Score agreement | Whether people reviewing agree with the AI score | At least 9 in 10 |
| Score fairness | Score gaps by neighbourhood, age and language | No significant gap in the yearly audit |

## Open questions

- Which state to launch in first (lien recording, licensing and partner availability vary by state).
- Which credit union or community development lender to approach for the Home Fund pilot.
- Which licensed insurer to partner with for the car pool, and whether to set up Kinfold's own reciprocal exchange later.
- The subscription formula (floor, share of earnings, cap), which needs actuarial work.
- Which AI model scores requests, how it's evaluated before launch, and where evidence is stored.
- Legal form of the cooperative and its subsidiaries; needs a lawyer experienced in cooperatives and consumer finance.
