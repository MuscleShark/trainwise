# Coaching principles

These are the rules the IronSage coach and the built-in templates follow. They come from the research listed at the end. The [architecture](architecture.md#ai-coach) describes how they run: the deterministic rules compute a plan, then Claude adjusts it for readiness and explains it.

Each rule says how strong its evidence is, so explanations to users stay honest.

## Principles

| Topic | What the research shows | Rule in IronSage | Evidence |
|---|---|---|---|
| **Weekly volume** (hard sets per muscle) | More sets give more hypertrophy and strength, with diminishing returns; returns flatten sooner for strength. Indirect sets (for example triceps in a bench press) should count as fractional sets | Track weekly sets per muscle, counting indirect sets as 0.5. Start moderate; add sets when progress stalls | Strong (meta-regression) |
| **Frequency** | More frequent training helps strength, with diminishing returns. With equal volume, frequency matters little for hypertrophy | Train each muscle at least twice a week | Strong for strength, weak for hypertrophy |
| **Proximity to failure** | Stopping closer to failure helps hypertrophy; it matters little for strength | Heavy compound sets: 1–3 reps in reserve (RIR). Isolation sets: 0–2 RIR | Moderate (meta-regression) |
| **Load** | A wide rep range builds muscle; maximal strength needs heavy loads | Main lifts 3–6 reps per set; accessories 6–15 | Strong |
| **Rest between sets** | Longer rest gives a small hypertrophy benefit; the difference is small | Default timer: 2–3 min for compounds, 1–2 min for isolation; user can change it | Moderate, small effect |
| **Periodization** | Small to moderate strength benefit, no clear hypertrophy difference. Undulating periodization helps trained lifters; beginners see almost no difference | Beginners: linear progression. Intermediates: undulating (heavy and moderate days) | Moderate |
| **Autoregulation** | Adjusting load by RPE/RIR or APRE did better than fixed percentages for maximal strength in a network meta-analysis; other reviews are mixed | Ask for RIR on working sets and use it to set the next load | Moderate, mixed |
| **Deloads** | Expert consensus: individual, based on fatigue, not a fixed schedule | Suggest a lighter week (fewer sets) when performance stalls for several sessions or readiness stays low | Expert consensus |
| **Sleep** | Acute sleep loss lowers exercise performance, strength included (about 7.6% on average) | After a short night: no load increase, or one set fewer | Strong (meta-analysis) |
| **HRV and resting heart rate** | Little direct evidence for HRV-guided strength training; most HRV-guided studies are endurance studies | Use as a supporting signal only, compared with the user's own baseline. Never change a plan on HRV alone. Say the evidence is limited when citing it | Weak |

## Progression rules

- **Estimated one-rep max (e1RM)** from recent working sets, used for trends and records.
- **Beginners: linear progression.** When every working set reaches the target reps, add 2.5 kg to upper-body lifts and 5 kg to lower-body lifts next session (or the closest available increment).
- **Intermediates: double progression with an RIR target.** Each exercise has a rep range (for example 6–10). When every working set reaches the top of the range at or above the target RIR, add load and return to the bottom of the range.
- **Stall:** no e1RM progress across three sessions of an exercise. Suggest changing the rep range or swapping the exercise; repeated stalls across exercises trigger a deload suggestion.
- **Safety limits:** never suggest more than about a 10% load jump in one step, and never raise load after a session marked as painful.

### How the app applies them

The iPhone app computes these suggestions itself (`ios/IronSageKit/Sources/IronSageCore/NextSession.swift`), so they work offline and cost nothing. New sets start from the suggestion, the workout screen says why under each exercise, and Today shows the next day of the template followed most recently.

- **Which rule:** a template with fixed reps (for example 3 × 5) uses linear progression; a rep range uses double progression. Each template set keeps its own target, so a template saved from a workout of 8, 7 and 6 reps progresses each set from its own reps. Without a template, compound lifts use 3–6 reps when the goal is strength and 6–10 otherwise, isolation work 10–15. Someone who trains outside that range keeps their own reps, as a range of two from the fewest reps done.
- **Steps:** one plate step (2.5 kg or 5 lb; 1.25 kg or 2.5 lb for one dumbbell). Linear progression on lower-body lifts takes two steps. The 10% limit applies, but one step is always allowed. Assisted exercises progress with less assistance.
- **Missed the range:** fixed reps missed → the same weight next time. Every set below the bottom of a range → one step lighter.
- **RIR:** a logged RIR below the target means the top of the range doesn't count yet. Sets without RIR are judged on reps alone.
- **Body weight:** at the top of the range without added weight, the app suggests adding weight or a harder variation.
- **Short night:** under 6 hours of sleep, or at least an hour below the user's 28-day average. No weight goes up that day.
- **Stall:** the best e1RM of the last three sessions is no better than the best before them. The app shows a note; changing the plan is left to the user and, later, the AI coach.
- **Not yet:** "painful" sessions can't be marked yet, and lighter-week (deload) suggestions come with the weekly summary.

## Built-in templates

IronSage writes its own templates from these principles. Programs such as 5/3/1, Starting Strength and StrongLifts are trademarks or copyrighted works, so their names and exact programs are not used.

| Experience and days | Template | Progression |
|---|---|---|
| Beginner, 3 days | Full body, alternating days A and B | Linear |
| Intermediate, 4 days | Upper / lower, each twice a week (one heavy day, one moderate day) | Double progression with RIR |
| Intermediate to advanced, 5–6 days | Push / pull / legs | Double progression; deloads when needed |
| Strength focus | Upper / lower with undulating heavy and moderate days | RIR-based load selection, e1RM tracking |

## Sources

- Pelland et al. 2025, weekly volume and frequency dose response, *Sports Medicine*: https://link.springer.com/article/10.1007/s40279-025-02344-w
- Robinson et al. 2024, proximity to failure, *Sports Medicine*: https://link.springer.com/article/10.1007/s40279-024-02069-2
- Schoenfeld et al. 2017, low vs high load, *JSCR*: https://journals.lww.com/nsca-jscr/fulltext/2017/12000/strength_and_hypertrophy_adaptations_between_low_.31.aspx
- Singer et al. 2024, rest intervals, *Frontiers in Sports and Active Living*: https://www.frontiersin.org/journals/sports-and-active-living/articles/10.3389/fspor.2024.1429789/full
- Moesgaard et al. 2022, periodization, *Sports Medicine*: https://pubmed.ncbi.nlm.nih.gov/35044672/
- Autoregulated training for maximal strength, network meta-analysis 2025: https://pubmed.ncbi.nlm.nih.gov/40791980/
- Load and volume autoregulation meta-analysis: https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8762534/
- Bell et al. 2023, deloading Delphi consensus, *Sports Medicine – Open*: https://link.springer.com/article/10.1186/s40798-023-00633-0
- Acute sleep loss and physical performance meta-analysis: https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9584849/
- HRV in strength and conditioning, narrative review: https://www.ncbi.nlm.nih.gov/pmc/articles/PMC11204851/

Review this page when new meta-analyses appear; the coach's evals should be updated with it.
