# Adaptive Gold Grid EA (XAUUSD) — v2

A preset-driven **adaptive grid + ACTIVE basket recovery (bounded martingale)** Expert Advisor for MetaTrader 5, tuned for **XAUUSD (gold)** and designed for continuous 24/7 operation.

The EA reads a higher-timeframe **regime filter** to decide whether a grid is appropriate at all, seeds a basket with structure bias, adapts its spacing to volatility, and then manages the whole basket **actively** — time-decayed profit targets, trailing, partial harvesting, and a bounded stop — instead of holding and hoping.

---

## 1. Why v2 exists (read this first)

**v1 blew up a $1000 demo account on gold in two days using `PRESET_MICRO`.** That was a real defect, not bad luck. Three causes, all fixed:

| # | v1 defect | v2 fix |
|---|---|---|
| 1 | **Counter-trend entry + averaging.** v1 picked its side from a fast M15 EMA pair, so a brief flicker inside a larger trend was enough to seed against it — then it kept averaging into that trend. | New **`RegimeFilter.mqh`**: a higher-timeframe ADX/EMA/ATR gate that refuses counter-trend seeds **and refuses to enlarge a basket that opposes a dominant trend.** |
| 2 | **Over-sized exposure.** `PRESET_MICRO` allowed `0.50` basket lots. On gold that let a **$77** adverse move erase a $1000 account. | Every preset retuned to **~0.02 lots per $1000 equity**, new **`PRESET_NANO`** for ~$1000 accounts, plus optional **capital-aware auto-sizing**. |
| 3 | **Passive "hold forever" recovery.** v1 could only wait for the market to return, so baskets sat stuck for weeks while the loss grew. | Recovery is now **ACTIVE**: time-decay TP, basket trailing, partial harvesting, and a bounded **basket stop**. |

### The gold contract math that caused the blow-up

```
1.00 lot XAUUSD = 100 oz   =>   a $1 gold move = $100 P&L
0.01 lot XAUUSD            =>   a $1 gold move = $1   P&L

basket loss  ~=  exposure_lots x 100 x adverse_move_in_dollars
```

v1 `PRESET_MICRO` (0.50 lot basket cap, 6 levels) permitted roughly **0.13 lots** of real exposure on a $1000 account. Gold routinely travels **$100–150 in a couple of days**. `0.13 x 100 x 77 = $1001`. The account was arithmetically dead before the market did anything unusual.

### The honest trade-off you must accept

v2 **deliberately reverses** the v1 rule of *"never close at a loss."*

> **"Never realise a loss" and "never get stuck" cannot both be true.** If the market does not come back, your only two options are a **bounded loss now** or an **unbounded loss later**. v1 chose the second and the account died. v2 chooses the first, by default.

The basket stop is an input and you *can* disable it — but doing so restores the exact v1 failure mode, and the EA will log a warning at startup if you do.

### What this EA does NOT do

**There is no system that profits regardless of which way the market moves.** Hedging both directions on one instrument nets your exposure to zero while you still pay spread, commission and swap — a guaranteed small loss. If such a system existed, markets would not. This EA does not pretend otherwise, and it does not hide floating losses to make an equity curve look green.

---

## 2. Architecture

Modules live under `MQL5/Include/AdaptiveGoldGrid/`; the EA is `MQL5/Experts/AdaptiveGoldGrid/AdaptiveGoldGrid.mq5` and pulls them in with angle-bracket includes (`#include <AdaptiveGoldGrid/Config.mqh>`).

| Module | Responsibility |
|---|---|
| **Config.mqh** | Single source of truth for all tuned numbers. `ENUM_ACCOUNT_PRESET`, the `PresetProfile` struct (21 fields), and `CConfig`. |
| **Logger.mqh** | Dependency-free leveled logger (ERROR/WARN/INFO/DEBUG) with optional file output. |
| **OrderManager.mqh** | Defensive `CTrade` wrapper. Lot normalisation, margin checks, magic+symbol basket queries, basket age, most-profitable-leg lookup, and close **mechanism** (no policy). |
| **SafetyValve.mqh** | Entry-blocking gate. Answers only *"is it safe to open a NEW order?"* using drawdown, margin level, free margin, projected margin. **Never closes, modifies or halts anything.** |
| **MarketAnalysis.mqh** | Fast-timeframe classical engine (RSI, MACD, ATR, fast/slow EMA, swing S/R) → `MarketContext`. Explicitly **not** machine learning. |
| **RegimeFilter.mqh** | **NEW in v2.** Higher-timeframe regime gate (ADX/±DI, EMA structure, ATR expansion) → `RegimeContext`. Answers `AllowSeed()` and `AllowAveraging()`. |
| **GridEngine.mqh** | Pure geometry: ATR-based adaptive spacing, seed direction, S/R snapping. Returns intents, never sends. |
| **LotSizer.mqh** | Bounded progressive sizing. Enforces per-order cap → basket exposure cap → broker min/max/step. |
| **RecoveryEngine.mqh** | **Reworked in v2.** Active basket management: group TP (time-decayed), trailing, basket stop, partial harvest, regime-gated averaging, optional hedge. |
| **MLHook.mqh** | Optional Phase-2 ONNX **inference-only** hook. Disabled by default, advisory, can never bypass the SafetyValve. |

### How a tick flows

1. `OnTick` refreshes the SafetyValve peak-equity baseline.
2. **MarketAnalysis** rebuilds `MarketContext`. Not ready → do nothing.
3. **RegimeFilter** rebuilds `RegimeContext` (higher TF). Not ready → do not open new exposure.
4. **If a basket exists → `RecoveryEngine.Manage()`**, in strict priority order:
   1. **Group TP** (age-decayed) → close the basket **in profit**.
   2. **Trailing** → a fading win is banked **in profit**.
   3. **Basket stop** → bounded loss, close and start fresh *(only if enabled)*.
   4. **Partial harvest** → bank a profitable leg to cut exposure.
   5. **Averaging** → **only if the regime still permits it**.
   6. **Hedge** → optional, off by default.
   7. **Hold**.
5. **If no basket → seed one**: GridEngine proposes a direction, then **RegimeFilter.AllowSeed()** can refuse it, then the optional ML hook may veto it.
6. **Every new-order intent** routes through `ExecuteIntentGated()` → **SafetyValve** → margin check → send.

**Invariant:** no order is ever sent without passing the SafetyValve, and the SafetyValve never closes or halts.

---

## 3. The Six Presets

Values below are the **exact defaults in `Config.mqh`**. Pick one in the `AccountPreset` input.

| Parameter | NANO | MICRO | MEDIUM | LARGE | BIGLEVEL | COMMERCIAL |
|---|---|---|---|---|---|---|
| Target account size | ~$500–1.5k | ~$1.5k–5k | ~$5k–15k | ~$15k–50k | ~$50k–150k | ~$150k+ |
| `base_lot` | 0.01 | 0.01 | 0.02 | 0.05 | 0.10 | 0.25 |
| `max_grid_levels` | 3 | 4 | 5 | 6 | 7 | 8 |
| `risk_percent_per_trade` (%) | 0.15 | 0.20 | 0.25 | 0.30 | 0.35 | 0.40 |
| `lot_progression_factor` | **1.00** | 1.15 | 1.20 | 1.25 | 1.30 | 1.30 |
| `max_lot_cap` | 0.01 | 0.02 | 0.05 | 0.15 | 0.40 | 1.00 |
| `max_basket_exposure_lots` | **0.03** | 0.06 | 0.20 | 0.60 | 1.80 | 5.00 |
| `atr_spacing_multiplier` | 2.00 | 1.80 | 1.60 | 1.50 | 1.40 | 1.35 |
| `max_drawdown_percent` (%) | 15.0 | 18.0 | 20.0 | 22.0 | 25.0 | 28.0 |
| `margin_level_floor_percent` (%) | 600 | 500 | 450 | 400 | 350 | 300 |
| `min_free_margin_currency` | 10 | 20 | 100 | 300 | 1000 | 3000 |
| `enable_basket_stop` | true | true | true | true | true | true |
| `basket_stop_loss_percent` (%) | 8.0 | 10.0 | 10.0 | 12.0 | 12.0 | 15.0 |
| `tp_decay_start_hours` | 8 | 12 | 12 | 12 | 12 | 12 |
| `tp_decay_full_hours` | 48 | 96 | 96 | 96 | 96 | 96 |
| `tp_decay_floor_fraction` | 0.15 | 0.15 | 0.15 | 0.15 | 0.15 | 0.15 |
| `enable_partial_harvest` | true | true | true | true | true | true |
| `harvest_min_leg_profit_ccy` | 0.30 | 0.50 | 0.50 | 0.50 | 0.50 | 0.50 |
| `trail_activate_fraction` | 0.70 | 0.70 | 0.70 | 0.70 | 0.70 | 0.70 |
| `trail_giveback_fraction` | 0.35 | 0.35 | 0.35 | 0.35 | 0.35 | 0.35 |
| `exposure_lots_per_1k` | 0.03 | 0.02 | 0.02 | 0.02 | 0.02 | 0.02 |
| `recommended_min_equity` | 500 | 1500 | 5000 | 15000 | 50000 | 150000 |

**`PRESET_NANO` is the preset for a ~$1000 account.** It uses a **flat `1.00` progression — no martingale multiplication at all** — only 3 levels, a 0.03-lot total exposure ceiling, and the tightest basket stop (8%).

### Honest expectation for a $1000 account

At 0.03 lots total exposure, a completed basket on gold is worth **single-digit dollars**. That is arithmetic, not a defect: small capital cannot produce large absolute returns without the risk of ruin that destroyed the v1 test. If the profit per basket looks too small to be interesting, the honest answer is that the account is too small for this instrument — not that the risk should be increased.

---

## 4. Input Reference

### General
| Input | Default | Meaning |
|---|---|---|
| `AccountPreset` | `PRESET_NANO` | Selects one of the six presets. |
| `MagicNumber` | `20240517` | Isolates this EA's basket. |
| `AnalysisTF` | `PERIOD_M15` | Fast analysis timeframe. |

### Regime Filter — prevents counter-trend grids
| Input | Default | Meaning |
|---|---|---|
| `EnableRegimeFilter` | `true` | Master switch. **Strongly recommended ON** — this is the main protection against the v1 blow-up. |
| `RegimeTF` | `PERIOD_H1` | Higher timeframe for regime detection. |
| `GridPolicy` | `POLICY_RANGING_ONLY` | Which regimes may seed: `RANGING_ONLY` (safest), `WITH_TREND_ONLY`, `RANGING_AND_TREND`. |
| `RegimeAdxPeriod` | `14` | ADX period. |
| `RegimeAdxTrend` | `22.0` | ADX above this ⇒ a trend exists. |
| `RegimeAdxStrong` | `30.0` | ADX above this ⇒ strong trend. |
| `RegimeEmaFast` / `RegimeEmaSlow` | `50` / `200` | Higher-TF EMA structure. |
| `RegimeViolentRatio` | `1.80` | fast/slow ATR above this ⇒ stand aside entirely. |

### Basket Take-Profit
| Input | Default | Meaning |
|---|---|---|
| `BasketTPMode` | `BASKET_TP_CURRENCY` | Currency profit, or points beyond break-even. |
| `BasketTPCurrency` | `5.0` | (Currency mode) close basket when floating PnL ≥ this. |
| `BasketTPPerLot` | `0.0` | (Currency mode) extra target per basket lot. |
| `BasketTPPoints` | `200.0` | (Points mode) points beyond break-even. |

### Active Recovery — Time-Decay TP
| Input | Default | Meaning |
|---|---|---|
| `UseDecayOverride` | `false` | Override the preset's decay settings. |
| `DecayStartHours` | `8.0` | Target starts shrinking after this basket age. |
| `DecayFullHours` | `48.0` | Target reaches its floor at this age. |
| `DecayFloorFraction` | `0.15` | Floor as a fraction of the original target. |

### Active Recovery — Trailing & Harvest
| Input | Default | Meaning |
|---|---|---|
| `UseTrailOverride` | `false` | Override the preset's trailing settings. |
| `TrailActivateFrac` | `0.70` | Arm trailing at this fraction of the target. |
| `TrailGivebackFrac` | `0.35` | Close if this fraction of peak profit is given back. |
| `UseHarvestOverride` | `false` | Override the preset's harvest settings. |
| `EnablePartialHarvest` | `true` | Bank profitable legs to cut exposure. |
| `HarvestMinLegProfit` | `0.30` | A leg must be at least this profitable to harvest. |

### Basket Stop — bounded loss
| Input | Default | Meaning |
|---|---|---|
| `UseStopOverride` | `false` | Override the preset's basket-stop settings. |
| `EnableBasketStop` | `true` | Close a hopeless basket at a bounded loss and start fresh. |
| `BasketStopLossPct` | `8.0` | Close basket when loss ≥ this % of **balance**. |

### Capital-Aware Auto-Sizing
| Input | Default | Meaning |
|---|---|---|
| `EnableCapitalSizing` | `true` | Derive the basket exposure cap from live equity. **Only ever shrinks** the preset caps, never enlarges them. |
| `BlockIfUnderfunded` | `false` | Refuse to initialise if equity is below the preset's recommended minimum. |

### Hedging, ML, and Sizing Overrides
| Input | Default | Meaning |
|---|---|---|
| `EnableHedge` | `false` | Optional opposite-side hedge action. |
| `HedgeTriggerDDPct` | `15.0` | Arm hedge when basket DD ≥ this % of balance. |
| `EnableOnnxML` | `false` | Optional ONNX inference (advisory only). |
| `OnnxModelFile` | `""` | `.onnx` model under `MQL5/Files`. |
| `UseManualOverride` | `false` | Replace preset sizing with the `Override*` fields below it. |

Logging: `LogLevel` (`LOG_INFO`), `EnableFileLog` (`false`), `LogFileName` (`AdaptiveGoldGrid.log`).
Execution: `SeedOnNewBarOnly` (`true`), `WarnIfNotGold` (`true`).

---

## 5. How the active recovery works

### Adaptive grid spacing
```
step_points = ATR_points x preset.atr_spacing_multiplier
```
Then adjusted by volatility regime: **VOL_HIGH** widens the step (don't stack into a fast move), **VOL_CALM** tightens it, **VOL_NORMAL** leaves it. A minimum-step floor prevents collapse to zero, and levels can snap to nearby swing S/R.

### Regime-gated averaging — the most important change
Once the higher timeframe is **trending against the basket**, the engine **stops enlarging it**. A SELL basket in `REGIME_TREND_UP` gets no more levels; a BUY basket in `REGIME_TREND_DOWN` gets no more levels; `REGIME_VIOLENT` suspends averaging entirely. Nothing is closed by this gate — the basket simply stops growing, which caps the exposure the stop/recovery logic then has to resolve. This is what breaks the "average into a trend until dead" spiral.

### Time-decay take-profit — the fix for "stuck for 30 days"
The group target **shrinks with basket age**:

```
age <= decay_start        ->  full target
decay_start < age < full  ->  linear ramp down
age >= decay_full         ->  floor_fraction x target
```

With `PRESET_NANO` a basket older than 48 hours is trying to escape at **15% of its original target**, so a stale basket exits at a small profit instead of waiting weeks for a full-size target the market may never hand back.

### Partial harvest — with an honest caveat
When a basket is **aging** or **trend-trapped** (averaging refused), the engine banks the most profitable leg to realise cash and cut exposure.

> **Caveat:** harvesting the best-priced legs slightly **worsens the weighted average** of what remains. It is a **survival-over-recovery** trade — the right trade for a small account, but a real trade-off. It is configurable and can be turned off.

### Basket trailing
Once the basket reaches `trail_activate_fraction` of its (decayed) target, giving back `trail_giveback_fraction` of the peak closes it **in profit**. Trailing is currency-based; in points mode it stays off unless you also set `BasketTPCurrency`.

### Basket stop
The only path in the EA that realises a loss. Fires when the basket's floating loss reaches `basket_stop_loss_percent` of **balance** (balance, not equity — equity already contains the loss being measured, which would make the ratio accelerate and trip inconsistently). Closes the whole basket and starts fresh.

---

## 6. Where a loss can be realised (audit trail)

Close **mechanism** lives in `OrderManager`; close **policy** lives only in `RecoveryEngine`. There are exactly four gated close sites and no `ExpertRemove` anywhere:

| Site | Gate | Outcome |
|---|---|---|
| Group take-profit | `GroupTargetReached()` requires `pnl > 0` | **Profit** |
| Basket trailing | `pnl > 0 && pnl <= giveback_level` | **Profit** |
| **Basket stop** | `enable_basket_stop && pnl < 0 && dd% >= threshold` | **Bounded loss** (opt-in) |
| Partial harvest | `MostProfitableLeg(min_profit)` — leg must be profitable | **Profit** |

`SafetyValve.mqh` contains **no close or halt call of any kind** and only ever blocks new entries.

---

## 7. RISK WARNING

**Grid + martingale strategies carry a real risk of large drawdown and total account loss.**

- The basket stop bounds the loss **per basket**, not per account. A long series of stopped baskets still draws the account down.
- If you **disable** the basket stop, you restore the v1 failure mode: a basket trapped against a trend holds indefinitely and the floating loss can grow until the **broker stops the account out**, regardless of anything this EA does.
- Deeper grid levels use progressively larger lots on every preset except `PRESET_NANO` (which is flat).
- News spikes, gaps, weekend risk, widened spreads, slippage, swap costs, and broker-specific stop-out levels can all produce outcomes far worse than a clean backtest suggests.
- **Nothing here guarantees profit.** "Profit regardless of market direction" is not achievable and is not attempted.

**Mitigate by:** using a preset appropriate to your capital (`PRESET_NANO` for ~$1000), keeping the regime filter and basket stop enabled, backtesting on real-tick data across multiple years and regimes, forward-testing on demo, and never risking money you cannot afford to lose.

---

## 8. ONNX / ML Phase-2 hook (optional, inference-only)

- **MQL5 cannot train** an LSTM/CNN/GRU or any neural network. Train outside MT5 (e.g. Python + PyTorch/TensorFlow) and export to `.onnx` yourself.
- MQL5 can only run **inference** via `OnnxCreate()` → `OnnxRun()` → `OnnxRelease()`. That is all this hook does.
- The classical indicators in `MarketAnalysis.mqh` and `RegimeFilter.mqh` are ordinary deterministic math and are **never** relabelled as "ML confidence".
- With `EnableOnnxML=false` (default) or an empty `OnnxModelFile`, `Predict()` returns **NEUTRAL** and the classical logic runs unchanged.
- Even when active it is **advisory only**: it may veto a disagreeing seed. It can never open, modify or close an order, and never bypasses the SafetyValve.

See the `// TODO(Phase-2)` markers in `MLHook.mqh` for the remaining tensor-shaping, normalisation, run and parse steps.

---

## 9. Install, Compile (F7), and Backtest

### Install
1. In MT5: **File → Open Data Folder**.
2. Copy the tree to mirror the MT5 layout:
   - `Experts/AdaptiveGoldGrid/AdaptiveGoldGrid.mq5` → `<MT5>/MQL5/Experts/AdaptiveGoldGrid/`
   - `Include/AdaptiveGoldGrid/*.mqh` → `<MT5>/MQL5/Include/AdaptiveGoldGrid/`
3. Refresh the MetaEditor Navigator.

### Compile
1. Open MetaEditor (F4 from MT5).
2. Open `AdaptiveGoldGrid.mq5`.
3. Press **F7**. A successful compile produces `AdaptiveGoldGrid.ex5`. Do not commit the `.ex5`.

### Backtest
1. **View → Strategy Tester** (Ctrl+R).
2. Expert: **AdaptiveGoldGrid**. Symbol: **XAUUSD** (or your broker's gold symbol).
3. Timeframe **M15** (match `AnalysisTF`); modelling **Every tick based on real ticks**.
4. Choose a multi-year range containing trends, ranges and news events.
5. Start with `AccountPreset = PRESET_NANO`, `EnableRegimeFilter = true`, `EnableBasketStop = true`, and a $1000 starting deposit.
6. Review the equity curve, **maximum drawdown**, margin-level behaviour, and how often the basket stop fires. Only after thorough backtesting and demo forward-testing should you consider live use.

---

## 10. Verified vs. NOT verified

**Verified in the build environment (static inspection only):**
- Braces and parentheses balance in all 11 source files (comments/strings excluded).
- All 10 `.mqh` files have matching `#ifndef`/`#define`/`#endif` guards; the `.mq5` correctly has none.
- All **21** `PresetProfile` fields are assigned in **all six** preset paths (no uninitialised fields).
- Cross-module call arity matches definitions (`RegimeFilter.Init` 11/11, `RecoveryEngine.Init` 7/7, `RecoveryEngine.Manage` 2/2).
- Every `RECOVERY_*` action used by the EA exists in the enum.
- Close-path audit: four gated close sites as tabulated in section 6; `SafetyValve` contains no close/halt; no `ExpertRemove` anywhere.
- No illegal C idioms (`(void)expr;`), no `std::`, no exceptions.
- README preset table cross-checked against `Config.mqh` literals.

**NOT verified — your responsibility:**
- **Compilation was NOT performed.** There is no MQL5 compiler, MetaEditor, MT5 or wine in the build environment. Compile it yourself (F7).
- **Backtesting was NOT performed.** No Strategy Tester exists here. Backtest and forward-test yourself on XAUUSD.
- Runtime behaviour, broker-specific fills and contract specs, margin maths on your account, and profitability were **not** validated and cannot be inferred from static inspection.
- Gold tick value/contract size vary by broker (per-ounce vs per-100-oz, plus account-currency conversion). Verify the seed lot against your broker's specs in the Strategy Tester.

Treat every result as unverified until you have compiled and backtested it yourself.
