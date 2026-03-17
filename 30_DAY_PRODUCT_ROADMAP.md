# Constellation 30-Day Product Roadmap

## Positioning (North Star)
Constellation helps people turn fragmented media consumption (movies, TV, books, podcasts) into an explainable intelligence graph that produces better next picks than any single-platform app.

## Product Promise
1. Every recommendation is explainable.
2. Capture is frictionless (especially podcast timestamp notes).
3. The app gets visibly smarter from user actions.
4. Performance feels instant for core flows.

---

## Week 1: Home + Discover Value Clarity

### Goal
Make the app answer: "What should I do next, and why?" within 5 seconds.

### Build
1. Home v2 layout:
- Knowledge Pulse (this week’s themes, strongest bridge, active medium)
- Continue Loop (in-progress episodes/items, pending note/theme actions)
- Top 3 Explainable Picks (with one-line path rationale)
- Single CTA to immersive graph

2. Discover card clarity:
- Add confidence tiers: Strong / Medium / Exploratory
- Add "Why this is strong" microcopy
- Add user controls: More like this / Less like this / Not now

3. Empty-state strategy:
- No dead space states
- Guided first actions when library is sparse

### Success Metrics
- Time to first meaningful action on Home < 10s
- Discover card open rate +20%
- Suggestion dismissal rate down (indicates stronger relevance)

---

## Week 2: Capture Moat (Podcast + Notes)

### Goal
Make note capture and synthesis feel uniquely better than podcast apps.

### Build
1. Timestamp note capture refinement:
- 1-tap note at current timestamp
- Fast edit flow
- Better visual hierarchy for multiple notes

2. Notes intelligence pipeline:
- "Generate themes from my notes" primary CTA
- Summary generation source indicator (notes/transcript/mixed)
- Better handling when transcript unavailable

3. Notes-driven recommendation refresh:
- Recommendations update after note/theme generation
- Small toast to explain what changed

### Success Metrics
- Notes per podcast episode +30%
- Theme generation usage +25%
- % podcast episodes with at least 1 meaningful note increases week-over-week

---

## Week 3: Suggestion Engine Quality + Speed

### Goal
Increase recommendation trust while reducing waiting.

### Build
1. Engine quality upgrades:
- Path validity scoring as hard gate
- Bayesian + popularity weighting
- Stronger creator/adaptation identity constraints
- Diversity balancing (avoid near-duplicates)

2. Engine speed architecture:
- Stale-while-revalidate everywhere
- Persistent resolved match cache (movie/TV/book)
- Latency budgets + partial results strategy
- Top-up in background only

3. Explainability upgrade:
- Surface explicit path + confidence + reason tags on every suggestion

### Success Metrics
- Discover first paint <= 300ms (warm)
- First useful suggestions <= 1.5s target
- Suggestions with user feedback "good pick" increase materially

---

## Week 4: Graph Intelligence + Launch Readiness

### Goal
Turn the graph from "cool visual" into "decision tool," then package for launch.

### Build
1. Graph insight overlays:
- Most central themes
- Orphan nodes (items needing connection)
- Best next connection to add

2. Connection drill-down:
- Tap connection stat on detail -> open exact connected items + why
- Theme and genre pages provide expert-quality, skimmable context

3. Launch hardening:
- Performance profiling pass
- Dark mode parity pass
- Reliability pass (posters/loading/fallbacks)
- Analytics events for key loops

### Success Metrics
- Graph interaction rate +25%
- Connection drill-down CTR +30%
- Crash-free and major-flow failure rate at launch threshold

---

## Core Metrics Dashboard (Track Weekly)
1. Activation:
- Added first 3 media items
- Opened first recommendation detail

2. Engagement:
- Weekly active users
- Discover sessions per user
- Notes created per active podcast listener

3. Recommendation Quality:
- Quick add rate from Discover
- Dismiss / "not for me" rate
- Repeat add rate from same session

4. Retention Signals:
- D1 / D7 retention
- Return rate after generating themes

5. Performance:
- Home load time
- Discover first paint
- Suggestion generation time p50/p90

---

## Launch Narrative (External)

### One-liner
"Constellation maps what you watch, read, and listen to into explainable recommendations you can trust."

### Why now
People consume across multiple media apps, but discovery and memory are fragmented.

### Differentiator stack
1. Cross-media graph (movies + TV + books + podcasts)
2. Explainable paths (not black-box suggestions)
3. Timestamp note intelligence for podcasts
4. Feedback loops that make recommendations visibly improve

---

## Feature Prioritization Rules
Use these rules to avoid scope drift:
1. If it does not improve decision quality, speed, or trust, defer it.
2. If a feature cannot be explained in one sentence to users, simplify it.
3. Build for repeat weekly usage, not one-time novelty.
4. Favor interaction loops over decorative UI.

---

## Immediate Next 5 Tasks (Start Tomorrow)
1. Ship Home v2 wireframe implementation with Knowledge Pulse + Top 3 explainable picks.
2. Add confidence tier + reason clarity to Discover cards.
3. Add event instrumentation for Home/Discover/Quick Add/Note capture.
4. Improve podcast timestamp note creation flow friction (1-tap + auto-focus).
5. Add graph "best next connection" insight card and drill-down path.
