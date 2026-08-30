# Adaptive Gold Grid EA (XAUUSD)

A preset-driven, institutional-style **adaptive grid + basket-recovery (bounded martingale)** Expert Advisor for MetaTrader 5, tuned for **XAUUSD (gold)** and designed for continuous 24/7 operation.

The EA reads classical multi-indicator + price-action context, seeds a grid basket with structure bias, adapts its spacing to volatility, and manages the whole basket as one group with a single goal: **bring the group back to a net profit and close it in profit**. Risk control is deliberately **entry-side only**: the Safety Valve blocks *new* exposure when the account is stressed but never force-closes a losing trade and never halts the EA.

---

## 1. Overview & Honest Disclaimer

- **Backtest first, always.** Nothing in this repository has been run, compiled, or backtested inside the build environment (there is no MetaTrader 5, MetaEditor, or wine here). Compilation and Strategy Tester backtesting are **your responsibility**. See section 10.
- **This is not financial advice.** Grid and martingale-style systems can be profitable in ranging conditions and dangerous in strong trends. You are responsible for your own capital, broker choice, and risk decisions.
- **"Always closes in profit" is a design goal, not a guarantee.** The recovery model is built to only ever *close* a basket when it is in net profit. That does not mean the account cannot be wiped out first. See the RISK WARNING in section 7.
- **No AI/ML claims by default.** The default build uses ordinary deterministic indicators. The optional ONNX hook (section 8) is disabled by default and does nothing until you supply and wire your own trained model.

---

## 2. Architecture

All engine modules live under `MQL5/Include/AdaptiveGoldGrid/` and are pulled into the main EA (`MQL5/Experts/AdaptiveGoldGrid/AdaptiveGoldGrid.mq5`) with angle-bracket includes such as `#include <AdaptiveGoldGrid/Config.mqh>`.

| Module | Responsibility |
|---|---|
| **Config.mqh** | The single source of truth for all tuned numbers. Defines `ENUM_ACCOUNT_PRESET`, the `PresetProfile` struct, and `CConfig` which returns a fully tuned profile per preset. |
| **Logger.mqh** | Dependency-free leveled logger (ERROR/WARN/INFO/DEBUG) with optional file output. Included by every other module without creating circular dependencies. |
| **OrderManager.mqh** | Defensive `CTrade` wrapper. Owns magic-number + symbol basket isolation, order sending with retcode handling, and basket queries (count, volume, floating PnL, weighted-average entry, basket close). Defines `ENUM_GRID_DIRECTION` (`GRID_BUY` / `GRID_SELL`). |
| **SafetyValve.mqh** | The entry-blocking gate. Answers only "is it safe to open a NEW order right now?" using drawdown, margin level, free margin, and projected margin. It never closes, modifies, or halts anything. |
| **MarketAnalysis.mqh** | Classical multi-indicator + price-action engine (RSI, MACD, ATR, fast/slow EMA, swing S/R). Produces a consolidated `MarketContext` struct. Explicitly **not** machine learning. |
| **GridEngine.mqh** | Pure decision module for grid geometry. Computes ATR-based adaptive spacing, chooses seed direction from structure/momentum, and returns a `GridIntent` (never sends orders). |
| **LotSizer.mqh** | Bounded adaptive/progressive lot sizing. Applies the martingale progression factor while enforcing the per-order cap, total-basket exposure cap, and broker volume normalization (min/max/step). |
| **RecoveryEngine.mqh** | Basket-first group recovery. Checks the group take-profit, proposes bounded averaging adds, and optionally proposes a one-time hedge. Its only close is the profit-only `CloseBasket()`. |
| **MLHook.mqh** | Optional Phase-2 ONNX **inference-only** hook. Disabled by default; returns a NEUTRAL "no opinion" result until you supply a trained `.onnx` model and complete the Phase-2 plumbing. Advisory only, can never bypass the Safety Valve. |

### How a tick flows through the system

1. **`OnTick`** refreshes the Safety Valve peak-equity baseline.
2. **MarketAnalysis** rebuilds the `MarketContext` (on a new bar, or whenever a basket is open, or when context is stale). If context is not ready, the EA does nothing this tick.
3. **If a basket exists → RecoveryEngine.Manage()** runs first (profit-first):
   - Group TP reached → `CloseBasket()` closes the whole group **in profit**.
   - Price moved one adaptive step adverse → propose an **averaging add** (bounded lot).
   - Hedge enabled and basket drawdown armed → propose a **one-time hedge**.
   - Otherwise → **hold** (a deliberate state, never a forced loss).
4. **If no basket exists → seed a fresh one**: GridEngine builds a seed `GridIntent` from trend/momentum bias, LotSizer computes the bounded seed lot.
5. **Optional ML confirmation filter** (only when the ONNX hook is active): the model may **veto** a classical seed whose direction it disagrees with. It can never create an entry.
6. **Every new-order intent** (seed, averaging, hedge) is routed through **`ExecuteIntentGated()`**, which asks the **SafetyValve** and then OrderManager for margin room before any `OrderSend`. If blocked, the EA logs and holds; nothing is closed.

The critical invariant: **no order is ever sent without passing the SafetyValve gate, and the SafetyValve never closes or halts.**

---

## 3. The Five Presets

Pick one preset in the `AccountPreset` input. Values below are the exact defaults implemented in `Config.mqh`. Every downstream module reads its limits from this profile; nothing is hardcoded elsewhere.

| Parameter | Micro | Medium | Large | BigLevel | Commercial |
|---|---|---|---|---|---|
| `base_lot` (first grid order) | 0.01 | 0.05 | 0.10 | 0.25 | 0.50 |
| `max_grid_levels` | 6 | 8 | 10 | 12 | 15 |
| `risk_percent_per_trade` (%) | 0.25 | 0.35 | 0.45 | 0.55 | 0.65 |
| `lot_progression_factor` (martingale x) | 1.30 | 1.40 | 1.45 | 1.50 | 1.55 |
| `max_lot_cap` (per-order hard cap) | 0.10 | 0.50 | 1.50 | 4.00 | 10.00 |
| `max_basket_exposure_lots` (total exposure cap) | 0.50 | 2.50 | 8.00 | 25.00 | 75.00 |
| `atr_spacing_multiplier` | 1.50 | 1.40 | 1.30 | 1.20 | 1.15 |
| `max_drawdown_percent` (DD circuit breaker %) | 25.0 | 30.0 | 35.0 | 40.0 | 45.0 |
| `margin_level_floor_percent` (margin floor %) | 400.0 | 350.0 | 300.0 | 250.0 | 200.0 |
| `min_free_margin_currency` (acct ccy) | 20.0 | 100.0 | 500.0 | 2000.0 | 10000.0 |

Notes:
- The martingale progression is **always bounded**: `lot_progression_factor` scales each deeper lot, but `max_lot_cap` caps any single order and `max_basket_exposure_lots` caps the summed basket volume. No preset allows unbounded doubling.
- Micro is the most conservative; Commercial is the largest but still bounded.
- Larger presets use a **tighter** ATR spacing multiplier (levels fill sooner) and a **higher** drawdown circuit-breaker ceiling, matching larger capital and exposure appetite.

---

## 4. Input Parameter Reference

These match the input block in `AdaptiveGoldGrid.mq5`.

### General
| Input | Type | Default | Meaning |
|---|---|---|---|
| `AccountPreset` | `ENUM_ACCOUNT_PRESET` | `PRESET_MICRO` | Selects one of the five presets (Micro/Medium/Large/BigLevel/Commercial). |
| `MagicNumber` | `long` | `20240517` | Isolates this EA's basket from other trades/EAs. |
| `AnalysisTF` | `ENUM_TIMEFRAMES` | `PERIOD_M15` | Timeframe used for indicator analysis and the new-bar detector. |

### Logging
| Input | Type | Default | Meaning |
|---|---|---|---|
| `LogLevel` | `ENUM_LOG_LEVEL` | `LOG_INFO` | Log verbosity (ERROR/WARN/INFO/DEBUG). |
| `EnableFileLog` | `bool` | `false` | Also append the log to a file under `MQL5/Files`. |
| `LogFileName` | `string` | `"AdaptiveGoldGrid.log"` | Log file name (under `MQL5/Files`). |

### Execution
| Input | Type | Default | Meaning |
|---|---|---|---|
| `SeedOnNewBarOnly` | `bool` | `true` | Seed a fresh basket only on a new bar (reduces churn). If false, may seed on any tick. |
| `WarnIfNotGold` | `bool` | `true` | Warn (do not block) if the chart symbol is not XAUUSD/gold. |

### Basket Take-Profit
| Input | Type | Default | Meaning |
|---|---|---|---|
| `BasketTPMode` | `ENUM_BASKET_TP_MODE` | `BASKET_TP_CURRENCY` | Group TP mode: currency profit or points beyond break-even. |
| `BasketTPCurrency` | `double` | `10.0` | (Currency mode) close basket when floating PnL is at or above this. |
| `BasketTPPerLot` | `double` | `0.0` | (Currency mode) extra target per basket lot (scales the target with size). |
| `BasketTPPoints` | `double` | `200.0` | (Points mode) close when price is this far beyond break-even. |

### Hedging (optional)
| Input | Type | Default | Meaning |
|---|---|---|---|
| `EnableHedge` | `bool` | `false` | Enable the optional opposite-side hedge action. |
| `HedgeTriggerDDPct` | `double` | `15.0` | Arm the hedge when basket floating drawdown reaches this % of equity. |

### Optional ONNX ML (Phase-2, default OFF)
| Input | Type | Default | Meaning |
|---|---|---|---|
| `EnableOnnxML` | `bool` | `false` | Enable optional ONNX inference (advisory only; never bypasses the SafetyValve). |
| `OnnxModelFile` | `string` | `""` | User-supplied `.onnx` model file under `MQL5/Files`. Empty means the hook stays NEUTRAL. |

### Advanced Overrides (leave off to use the preset)
| Input | Type | Default | Meaning |
|---|---|---|---|
| `UseManualOverride` | `bool` | `false` | Override selected preset values with the fields below. |
| `OverrideBaseLot` | `double` | `0.01` | Manual base lot (if override on). |
| `OverrideMaxGridLevels` | `int` | `6` | Manual max grid levels (if override on). |
| `OverrideLotProgression` | `double` | `1.30` | Manual lot progression factor (clamped to >= 1.0). |
| `OverrideMaxLotCap` | `double` | `0.10` | Manual per-order lot cap. |
| `OverrideMaxBasketLots` | `double` | `0.50` | Manual total-basket exposure cap. |
| `OverrideAtrSpacingMult` | `double` | `1.50` | Manual ATR spacing multiplier. |
| `OverrideMaxDrawdownPct` | `double` | `25.0` | Manual drawdown gate % (entry-blocking only). |

---

## 5. How the Adaptive Grid and Basket Recovery Work

### Adaptive grid spacing (ATR + volatility regimes)
The base grid step is derived from volatility, never hardcoded:

```
step_points = ATR_points * preset.atr_spacing_multiplier
```

MarketAnalysis classifies the current ATR into a **volatility regime** using its percentile over a recent lookback window:

- **VOL_HIGH** (ATR percentile >= 0.66) → **widen** the step so the grid does not stack levels into a fast move.
- **VOL_CALM** (ATR percentile <= 0.33) → **tighten** the step so levels fill in quiet ranges.
- **VOL_NORMAL** → leave the step as-is.

A minimum-step floor prevents spacing from collapsing to zero, and the engine can snap a level to a nearby swing support/resistance when price is within a fraction of a step.

### Seed direction
With no basket open, the seed direction comes from the consolidated `MarketContext` (fast/slow EMA relationship + slope for trend, plus a blended RSI/MACD momentum score). This is a structure-biased entry, not a coin flip. Once a basket exists, additional levels are added on the same recovery side.

### Basket recovery (group TP, averaging, optional hedge)
The EA thinks in **baskets**, not single trades. A basket is every position sharing the EA's magic number and symbol, managed as one group:

1. **Group take-profit first.** Each tick the RecoveryEngine checks whether the basket's floating PnL has reached the configured target (currency or points beyond weighted-average break-even). When it has, `CloseBasket()` closes the whole group **in profit**. This is the only close the engine ever issues.
2. **Averaging.** If price has moved one adaptive step adverse and there is grid depth (`max_grid_levels`) and exposure room left, the engine proposes a bounded averaging add on the recovery side to pull the weighted-average entry closer to price.
3. **Optional hedge.** If `EnableHedge` is on and basket floating drawdown reaches `HedgeTriggerDDPct`, the engine proposes a single opposite-side hedge to cap further adverse bleed while the primary side waits to recover.
4. **Hold.** If none of the above apply (for example, exposure caps are hit), the engine simply holds and waits for the market to return to the break-even target. Holding is a deliberate state, not a bug, and no loss is ever realized.

Every proposed add is only an **intent**; the main EA still gates it through the Safety Valve before any order is sent.

---

## 6. The Safety Valve

The Safety Valve is a **gate, not a kill-switch**. Each tick it answers exactly one question: *"Is it safe to open a NEW grid / recovery order right now?"*

It blocks **new entries** when any of these thresholds are crossed (values come from the active preset):
- **Drawdown circuit breaker**: equity drawdown from the tracked peak reaches `max_drawdown_percent`.
- **Margin level floor**: `ACCOUNT_MARGIN_LEVEL` falls below `margin_level_floor_percent` (only enforced when margin is actually in use).
- **Free-margin minimum**: `ACCOUNT_MARGIN_FREE` falls below `min_free_margin_currency`.
- **Projected margin**: the free margin that *would remain* after the intended next order would breach the minimum.

Non-negotiable semantics, stated plainly:
- It **NEVER force-closes** a position (no close-at-loss, ever).
- It **NEVER modifies** an existing trade.
- It **NEVER halts** the EA (no `ExpertRemove`, no account halt).
- It **NEVER realizes a loss**.

**Why it works this way:** this is a grid + basket-recovery system. The recovery basket needs room (free margin and surviving equity) to work its way back to profit. Force-closing at a loss or halting would lock in the drawdown and defeat the entire recovery model. So the only protective action is to **stop adding new exposure** until the account has breathing room again. Blocking new entries keeps the account alive so the existing basket can recover and close in profit. **This is a precondition for recovery, not a defeat.**

---

## 7. RISK WARNING (READ THIS)

**Grid + martingale strategies carry a real risk of large drawdown and total account loss.**

- Even though the Safety Valve stops opening new orders when the account is stressed, **it cannot close the existing basket at a profit if the market never comes back.** A strong, sustained trend against the basket can grow the floating loss until your **broker forces a stop-out** and liquidates positions at a loss, regardless of anything this EA does.
- **"The basket always closes in profit" is NOT guaranteed.** It is the intended closing behavior of the recovery engine, but the account can still be blown up by an adverse move before that ever happens. The design keeps the account alive as long as possible; it does not make losses impossible.
- Deeper grid levels use progressively larger lots (bounded, but still larger). Exposure and margin usage can climb quickly during a losing sequence.
- News spikes, gaps, weekend risk, widened spreads, slippage, swap costs, and broker-specific stop-out levels can all cause outcomes far worse than a clean backtest suggests.

**Mitigate this by:** using a conservative preset for your capital, backtesting thoroughly on real-tick data across multiple years and market regimes, forward-testing on a demo account, and never risking money you cannot afford to lose. **You must backtest thoroughly before considering live use.**

---

## 8. ONNX / ML Phase-2 Hook (Optional, Inference-Only)

`MLHook.mqh` provides an **optional, disabled-by-default** ONNX inference hook. Honest facts about it:

- **MQL5 cannot train** an LSTM/CNN/GRU or any neural network. There is no training runtime in the terminal. You must train **outside** MT5 (for example Python + PyTorch/TensorFlow) and export to the `.onnx` format yourself.
- MQL5 can only run **inference** via `OnnxCreate()` → `OnnxRun()` → `OnnxRelease()`. That is the only thing this hook does.
- The classical indicators in `MarketAnalysis.mqh` are ordinary deterministic math and are **never** relabeled or presented as "ML confidence". A genuine ML signal comes only from a real trained model run through `OnnxRun()`.
- When `EnableOnnxML=false` (default), or when `OnnxModelFile` is empty, or before the Phase-2 tensor plumbing is completed, `Predict()` returns a **NEUTRAL "no opinion"** result and the classical Phase-1 logic runs completely unchanged.
- Even when active, the hook is **advisory only**: it may only bias/confirm (veto a disagreeing seed). It can never open, modify, or close an order, and it can **never bypass the Safety Valve**.

To finish Phase-2 you would (see the `// TODO(Phase-2)` markers in `MLHook.mqh`): define the model input/output tensor shapes, apply the same normalization used at training time, call `OnnxRun`, and parse the output into a real confidence in `[0,1]`.

---

## 9. Install, Compile (F7), and Backtest (Strategy Tester)

### Install (place folders under the MT5 data folder)
1. In MetaTrader 5, open **File → Open Data Folder**. This opens `<MT5 data folder>`.
2. Copy the source tree so it mirrors the MT5 `MQL5` layout:
   - `Experts/AdaptiveGoldGrid/AdaptiveGoldGrid.mq5` → `<MT5>/MQL5/Experts/AdaptiveGoldGrid/AdaptiveGoldGrid.mq5`
   - `Include/AdaptiveGoldGrid/*.mqh` → `<MT5>/MQL5/Include/AdaptiveGoldGrid/*.mqh`
3. In MetaEditor, refresh the Navigator so it sees the new files.

### Compile (F7)
1. Open MetaEditor (from MT5: **Tools → MetaQuotes Language Editor**, or press F4).
2. Open `MQL5/Experts/AdaptiveGoldGrid/AdaptiveGoldGrid.mq5`.
3. Press **F7** (Compile). Fix any reported issues. A successful compile produces `AdaptiveGoldGrid.ex5` next to the `.mq5`.
   - Do **not** commit the generated `.ex5`; it is a local build artifact.

### Backtest (Strategy Tester) on XAUUSD
1. In MT5 open **View → Strategy Tester** (Ctrl+R).
2. Select the Expert **AdaptiveGoldGrid**.
3. Symbol: **XAUUSD** (or your broker's gold symbol, e.g. `GOLD`, `XAUUSD.m`).
4. Timeframe: **M5** or **M15** (match `AnalysisTF`).
5. Modeling: **Every tick based on real ticks** for the most realistic fills.
6. Choose a multi-year date range that includes trends, ranges, and news events.
7. Start with **`AccountPreset = PRESET_MICRO`** and default inputs.
8. Run, then review the equity curve, maximum drawdown, and margin-level behavior. Only after thorough backtesting and demo forward-testing should you consider a small live/demo trial.

---

## 10. Verified vs. Not Verified

**Verified in this environment (by inspection only):**
- Module structure, include guards, and cross-module include paths were reviewed by reading the source.
- The main EA declares `OnInit` / `OnTick` / `OnDeinit` and a complete input block.
- Logic flow was reviewed: SafetyValve is entry-blocking only, RecoveryEngine's only close is the profit-only `CloseBasket()`, and the ONNX hook is disabled by default and cannot bypass the SafetyValve.
- The preset table in this README was cross-checked field-by-field against the literal defaults in `Config.mqh`.

**NOT verified (your responsibility):**
- **Compilation was NOT performed.** There is no MQL5 compiler, MetaEditor, MetaTrader 5, or wine in the build environment, so the EA could not be compiled here. You must compile it yourself with MetaEditor (F7).
- **Backtesting was NOT performed.** No Strategy Tester exists here. You must backtest and forward-test the EA yourself on XAUUSD as described in section 9.
- Runtime behavior, broker-specific fills, margin math on your account, and profitability were **not** validated and cannot be inferred from static inspection.

Treat every result as unverified until you have compiled and backtested it yourself.
