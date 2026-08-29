# 001 PERCEPTION — Explainer

*How an adaptive, multi-strategy MetaTrader 5 framework is put together, and why each
piece exists.*

---

## Background

### For the newcomer (skip if you know MT5/MQL5)

MetaTrader 5 (MT5) is a retail trading platform. Automated strategies for it are called
**Expert Advisors (EAs)**, written in **MQL5** — a C++-like language. An EA is driven by
event callbacks the terminal invokes:

- `OnInit()` once when the EA loads,
- `OnTick()` on every incoming price quote,
- `OnTimer()` on a timer you request,
- `OnDeinit()` when it unloads.

Everything an EA does — reading indicators, deciding to buy or sell, sending orders,
drawing on the chart — hangs off those callbacks. A *symbol* (e.g. `EURUSD`, `XAUUSD`)
has broker-specific properties: how many digits its price has, the value of one tick,
the minimum/maximum/step of a trade *lot*, the minimum stop distance, and so on. A naive
EA hard-codes assumptions about one symbol; a robust one *asks the broker* at runtime.

> **Key term — "engine".** In this project an *engine* is one self-contained trading
> strategy (trend-following, range-fading, breakout, …). The whole design goal is to run
> many of them side by side and let the best one act.

### The narrow background: an empty repository

This framework was built into a repository that contained nothing but a README reading
"MT5 ROBOT". There was no prior code to integrate with — which is a luxury: the
architecture could be designed clean, top to bottom, rather than retrofitted.

The problem statement asked for something unusually large: *"the world's most advanced
commercial-grade MT5 EA"* — a modular, adaptive, autonomous framework with ~27 strategy
engines, an internal AI layer, institutional risk management, account presets, automatic
market-regime switching, and three distinct premium dashboards. The engineering
challenge is less about any single indicator and more about **structure**: how do you
let twenty very different strategies coexist without the code collapsing into a tangle?

---

## Intuition

The core intuition is a small analogy: **treat strategies like job candidates and the AI
layer like a hiring manager.**

Every bar, each engine submits an application:

1. *"How suitable am I for today's market?"* — a number in `[0,1]`.
2. *"Here is a concrete trade I'd take"* — or nothing, if it sees no setup.

The hiring manager (the AI layer) then:

- turns the application into a **calibrated probability** by blending suitability,
  the engine's own confidence, setup quality, multi-timeframe agreement and how sure we
  are about the regime;
- multiplies by **earned trust** — an engine that has actually made money is believed
  more than one that hasn't;
- compares against an **acceptance threshold** that *rises when the account is bleeding*
  and *relaxes when it's winning*;
- **hires exactly one** candidate — the highest final score — and rejects the rest.

A toy example. Suppose the market is a tight, directionless range:

| Engine     | Suitability | Own confidence | AI probability | Verdict           |
|------------|-------------|----------------|----------------|-------------------|
| Trend      | 0.15        | 0.70           | 0.31           | reject (poor fit) |
| Range      | 0.90        | 0.62           | 0.64           | **hire**          |
| Breakout   | 0.45        | 0.00 (no setup)| —              | reject (no setup) |

The trend engine is confident but irrelevant; the range engine wins because it *fits the
regime*. Flip the market into a strong trend and the table inverts — no code changes, the
same machinery simply elects a different engine. That is the whole product in miniature.

> **Why not just average all signals?** Averaging lets a confident-but-wrong strategy
> drag down a correct one, and it trades constantly. Electing a single best-fit engine
> keeps behaviour legible ("right now we are a *Range* bot") and lets each engine own its
> own trades, statistics and recovery logic.

---

## Code — a guided tour

The dependency flow is strictly one-directional, which is what keeps a system this size
maintainable:

```
Core → Analysis → {Intelligence, Engines, Risk, Execution} → Dashboard → Orchestrator
```

### 1. Core: vocabulary and auto-detection

`Core/Types.mqh` defines the plain data structs every layer speaks in — most importantly
`SSignal` (a trade intention) and `SMarketState` (a full snapshot of the bar).

`Core/SymbolMeta.mqh` is the "no manual configuration" promise. It interrogates the
broker once and derives clean helpers, e.g. converting a money risk into a normalised lot
size:

```cpp
double LotsForRisk(const double money,const double stopPoints) const
  {
   double perLot=stopPoints*m_valuePerPoint;      // value of the stop for 1.0 lot
   if(perLot<=0.0) return m_volMin;
   return NormalizeLots(money/perLot);            // clamp to min/max/step
  }
```

### 2. Analysis: turning ticks into understanding

`Analysis/IndicatorHub.mqh` creates every indicator handle **once** and refreshes cached
values **once per bar** — the single biggest CPU saving in a multi-strategy EA, because
engines read cached doubles instead of each calling `CopyBuffer`.

`Analysis/MarketContext.mqh` assembles the `SMarketState`, and
`Analysis/RegimeClassifier.mqh` labels it. The classifier is deliberately a readable
decision tree, not a black box:

```cpp
if(st.trend!=TREND_FLAT && adx>=25.0 && str>=0.55)
  {
   st.regime=(st.trend==TREND_UP?REGIME_STRONG_TREND_UP:REGIME_STRONG_TREND_DOWN);
   st.regimeConfidence=PU::Clamp(0.5+0.5*PU::Normalize01(adx,25,45),0.5,1.0);
   return;
  }
```

### 3. Engines: one interface, many strategies

`Engines/IEngine.mqh` is the contract. Every strategy implements just two methods:

```cpp
virtual double Suitability(const SMarketState &st)=0;   // regime fit [0..1]
virtual void   Evaluate(const SMarketState &st,CSymbolMeta *sym,
                        const SConfig &cfg,SSignal &out)=0;
```

That uniformity is the trick that makes twenty strategies interchangeable. A concrete
engine is then short and focused — here is the entire decision core of the range engine:

```cpp
if(st.adx>24.0) return;                    // a real trend is underway → stand down
if(st.bid<=st.bbLower && st.rsi<35.0) { out.dir=SIG_BUY;  /* fade to the mean */ }
else if(st.ask>=st.bbUpper && st.rsi>65.0) { out.dir=SIG_SELL; }
```

The riskier engines (grid, adaptive grid, martingale, recovery, hedging) implement the
same interface but ship **disabled by default** and tightly capped.

### 4. Intelligence: the hiring manager

`Intelligence/AIEngine.mqh` implements the scoring described in the Intuition section:

```cpp
double prob = 0.32*sc.suitability + 0.28*sc.signal.confidence
            + 0.15*sc.signal.quality + 0.13*st.mtfAlignment
            + 0.12*st.regimeConfidence;
sc.aiConfidence = PU::Clamp(prob*TrustFromStats(stats),0.0,1.0);
sc.accepted     = sc.signal.IsValid() && sc.aiConfidence>=m_threshold && sc.suitability>=0.30;
```

and adapts the bar with account health:

```cpp
t -= (aggressiveness-0.5)*0.20;   // braver users trade a touch more
t += currentDD*0.50;              // tighten as drawdown grows
t -= (winRate-0.5)*0.20;          // reward a good hit rate
```

`Intelligence/StrategySelector.mqh` runs the whole poll each bar, publishes every verdict
to the event bus (which feeds the dashboard's live log), and returns the single winner.

### 5. Risk & Execution: the pessimist and the hands

`Risk/RiskManager.mqh` is the last gate before capital moves. It sizes positions
fixed-fractionally, caps them by margin, and layers circuit breakers: spread, margin,
daily-loss, max-drawdown, an equity floor, and a kill switch that flattens everything.
Below the hard drawdown cap it de-risks rather than stopping (recovery/throttle states).

`Execution/OrderManager.mqh` wraps the standard `CTrade`, stamping each engine's own magic
number; `Execution/PositionManager.mqh` runs break-even, ATR trailing and a one-shot
partial close, all expressed in R-multiples so behaviour is identical across symbols.

### 6. Dashboard and Orchestrator

`Dashboard/Dashboard.mqh` renders three faces (Compact / Professional / Research) from a
read-only view model, using a create-or-update drawing toolkit so repainting never
flickers or leaks objects. `Perception.mqh` is the one place that owns every module and
wires the lifecycle:

```cpp
void OnNewBar()
  {
   ScanClosedDeals();                 // attribute results back to engines (learning)
   m_mkt.Update(); m_state=m_mkt.State(); m_regime.Classify(m_state);
   m_stats.Recompute(); m_ai.AdaptThreshold(ps);
   bool found=m_sel.Select(m_state,GetPointer(m_sym),m_cfg,best);
   if(m_risk.TradingAllowed(m_state,reason) && found && m_risk.SymbolSlotFree(_Symbol))
     { m_risk.ResolveStops(sig,m_state); sig.lots=m_risk.SizePosition(sig); /* open */ }
  }
```

---

## Verification

Because MetaEditor (the MQL5 compiler) is not available in the build environment, the
code was verified by **static analysis** rather than compilation:

- **Include graph** — every `#include <Perception/...>` was confirmed to resolve to a
  real file; every header carries a unique include guard.
- **Bracket/brace/paren balance** — checked per file (all 48 balanced).
- **MQL5 pitfalls** — scanned and fixed: no `->` misuse (MQL5 uses `.` on pointers);
  formatting helpers were moved to global scope so unqualified calls resolve; and every
  place that passed a *temporary struct* into a `const&` parameter was rebound to a local
  first (a known MQL5 fussiness).
- **Contract completeness** — every engine implements both pure-virtual methods; the base
  class has a virtual destructor so `delete` on a base pointer is safe.

### How to QA it yourself

1. Copy `MQL5/` into your terminal's data folder and **Compile** `001_PERCEPTION.mq5`
   (expect zero errors).
2. Open the **Strategy Tester**, pick a symbol and a few months of history, and run in
   *Every tick based on real ticks* mode. Watch the Experts/Journal tabs for the
   `001P|INFO` lines describing each opened trade and why.
3. On a live chart (demo!), press **1/2/3** to switch dashboards; confirm the panels
   populate, the AI confidence bar moves, and the decision log scrolls.
4. Force edge cases: set a tiny `InpMaxDrawdownPct` and confirm the kill switch trips and
   flattens positions; set `InpAutoTrade=false` and confirm no new trades open.

---

## Alternatives

Two orthogonal designs were considered.

**A. Blend all engine signals into one vote (ensemble) instead of electing one.**

| Pros | Cons |
|------|------|
| Smoother equity, less single-engine risk | One confident-but-wrong engine taxes the winners |
| No "winner-take-all" whipsaw between engines | Behaviour is opaque ("what *is* the bot doing?") |
| Naturally diversified | Hard to attribute P/L or run per-engine recovery |

**B. Externalise the "AI" to a Python/ML service over sockets.**

| Pros | Cons |
|------|------|
| Access to real ML models | Latency + a second process to deploy and babysit |
| Easier experimentation off-platform | Fragile for a *commercial* product; a network blip stalls trading |
| Richer features | Opaque; buyers can't audit the decision logic |

The chosen design — **elect one engine via a transparent in-process scorer** — was picked
for legibility, auditability and zero external dependencies, which matter most for a
product other people are expected to trust and run unattended.

---

## Suggested people to talk to

This is a **greenfield** codebase: before this work the repository held only a one-line
README, so there are no prior authors with historical context to consult. Everything here
was authored in a single pass by the AI agent. Practically, that means:

- **You (the repository owner)** are now the domain owner. The highest-leverage next step
  is a careful read of `Perception.mqh` (the orchestrator) and `Intelligence/AIEngine.mqh`
  (the scoring), since those two files define the system's behaviour.
- For MQL5-specific correctness questions (filling modes, netting vs hedging accounts,
  tester quirks), the MetaTrader 5 / MQL5 community forum is the most authoritative source.

As the project accrues real commit history, this section should be regenerated from
`git log` on the files being changed.

---

## Quiz

<details>
<summary><b>1. Why does the IndicatorHub refresh values only once per bar rather than per engine?</b></summary>

**Answer: to minimise CPU.** If each of 21 engines called `CopyBuffer` for every
indicator on every tick, cost would explode. Centralising the reads into one cached
snapshot per bar means the expensive work happens once and every engine reads cheap
doubles. (Answers about "accuracy" are wrong — the values are identical either way; the
difference is purely performance.)
</details>

<details>
<summary><b>2. An engine returns a valid BUY with confidence 0.9, but the AI rejects it. Give a plausible reason.</b></summary>

**Answer:** its **suitability was below 0.30** (poor regime fit), or the account is in
drawdown so the **adaptive threshold rose above its aiConfidence**. Remember
`aiConfidence = probability × trust`, and `probability` is dominated by suitability and
regime confidence — a high *self*-confidence alone does not clear the bar.
</details>

<details>
<summary><b>3. Where do the grid/martingale engines get their larger volumes from, given sizing is normally risk-based?</b></summary>

**Answer:** they set `SSignal.lots` explicitly. `RiskManager.SizePosition` was written to
**honour an explicit volume when present** (still capped by margin) and only fall back to
fixed-fractional sizing when `lots==0`. That's the hook that lets opt-in recovery engines
scale in without breaking the default risk model.
</details>

<details>
<summary><b>4. Why are stop/target thresholds in the PositionManager expressed in "R-multiples" instead of pips or points?</b></summary>

**Answer:** so behaviour is **symbol-independent**. 1R = the initial ATR-based risk. A
"trail after 1R" rule then behaves identically on a 5-digit FX pair and on gold, whose
point sizes differ by orders of magnitude. Hard-coded pip thresholds would be reckless on
one and inert on the other.
</details>

<details>
<summary><b>5. The kill switch trips on max drawdown. What two things happen, and what resets the *daily* halt?</b></summary>

**Answer:** the system state becomes `STATE_HALTED` **and** an emergency-close flag is
raised, which the orchestrator uses to flatten all of the EA's positions. That halt is
sticky for the session. The **daily-loss** halt is different: it is released automatically
at the next midnight rollover (tracked by the day stamp in `RiskManager.OnTick`).
</details>
