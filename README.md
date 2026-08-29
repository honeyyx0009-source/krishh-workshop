# 001 PERCEPTION

**An adaptive, autonomous, multi-strategy trading framework for MetaTrader 5 (MQL5).**

001 PERCEPTION is not a single-strategy Expert Advisor. It is a modular framework in
which many independent trading *engines* compete, an internal *AI intelligence layer*
continuously scores them against the live market regime, and the highest-confidence
engine earns the right to trade — all under a strict, institutional-style risk manager
and a premium multi-mode dashboard.

> ⚠️ **Disclaimer.** This software automates trading and risk decisions. It does **not**
> guarantee profit and can lose money. Always validate in the MetaTrader 5 Strategy
> Tester and on a demo account before considering any live deployment. Trade at your own risk.

---

## Key ideas

- **Never depend on one strategy.** 21 engines (trend, swing, momentum, range, mean
  reversion, scalping, breakout, volatility, session, S/R, order block, FVG, liquidity
  grab, supply/demand, SMC, volume profile, grid, adaptive grid, martingale, recovery,
  hedging) each implement a tiny uniform interface.
- **A transparent AI brain.** No external APIs and no black box. The AI layer converts
  each engine's raw signal into a calibrated probability, weights it by the engine's
  *earned* track record, adapts its acceptance threshold to account health, and rejects
  weak setups.
- **Automatic market classification.** A regime classifier labels the market every bar
  (strong/weak trend, range, sideways, volatile, calm, expansion, compression, gap,
  flash) and each engine reports how suitable it is for that regime.
- **No manual configuration.** Symbol digits, tick value, contract size, lot
  constraints, stop/freeze levels, filling mode, swaps and broker GMT are auto-detected.
- **Institutional risk.** Fixed-fractional sizing, ATR stops, break-even, ATR trailing,
  partial close, daily-loss limiter, max-drawdown protection, equity floor, margin
  guard, a kill switch, and recovery/throttle states.
- **Three dashboards, one hotkey away.** Compact (1), Professional (2), Research (3) —
  dark cyber theme, resolution-scaled.

---

## Repository layout

```
MQL5/
├─ Experts/001_PERCEPTION/001_PERCEPTION.mq5     ← the EA entry point (tiny)
└─ Include/Perception/
   ├─ Perception.mqh            ← central orchestrator (the "brain")
   ├─ Params.mqh                ← all user inputs + config resolver
   ├─ Core/                     ← enums, types, config, logger, event bus,
   │                              utils, symbol auto-detection
   ├─ Analysis/                 ← indicator hub, market structure, market
   │                              context, regime classifier, scanner
   ├─ Intelligence/             ← AI decision engine + strategy selector
   ├─ Engines/                  ← IEngine base + manager + 21 engines
   ├─ Risk/                     ← presets + risk manager
   ├─ Execution/                ← order manager + position manager
   ├─ Stats/                    ← performance analytics
   └─ Dashboard/                ← draw toolkit, chart skin, 3-mode dashboard
```

The dependency flow is strictly one-directional:
`Core → Analysis → Intelligence/Engines/Risk/Execution → Dashboard → Orchestrator`.

---

## Installation

1. Copy the contents of this repo's `MQL5/` folder into your terminal's data folder
   `MQL5/` directory (File → Open Data Folder in MetaTrader 5). The result should be:
   - `MQL5/Experts/001_PERCEPTION/001_PERCEPTION.mq5`
   - `MQL5/Include/Perception/...`
2. Open `001_PERCEPTION.mq5` in MetaEditor and press **Compile** (F7). It should compile
   with no errors.
3. Attach the EA to any chart. Enable **Algo Trading**.

## Usage

- Pick an **account preset** (`InpPreset`) — it governs the whole risk envelope.
- Leave the default engine roster, or toggle engines on/off in the inputs. The grid /
  martingale / recovery / hedging engines are **off by default** because they are risky.
- Switch dashboards live with keys **1 / 2 / 3** (click the chart first).

See the detailed walkthrough in [`docs/EXPLAINER.md`](docs/EXPLAINER.md).

---

## Status

This is a complete, compiling **foundation**: a full modular architecture with real
(not placeholder) analysis, AI scoring, risk management and execution, plus a working
core set of engines and the full dashboard. It is designed to be extended — every engine
is independent, so adding or refining strategies never touches the rest of the system.

It has **not** been through months of live-forward testing. Treat it as a serious,
well-structured starting point that you must validate before trusting with capital.
