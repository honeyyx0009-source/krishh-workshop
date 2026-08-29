//+------------------------------------------------------------------+
//|                                                       Params.mqh |
//|          001 PERCEPTION - User inputs & config resolver           |
//|                                                                  |
//| All `input` parameters live here so the main EA file stays a     |
//| clean orchestrator. BuildConfig() folds the raw inputs into an   |
//| SConfig; the selected preset then overrides the risk envelope.   |
//| Engine on/off toggles are exposed as inputs and read by the      |
//| orchestrator when it populates the engine roster.                |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_PARAMS_MQH
#define PERCEPTION_PARAMS_MQH

#include <Perception/Core/Config.mqh>

//====================================================================
input group "== 001 PERCEPTION :: General =="
input long          InpMagicBase        = 20250001;      // Magic base (engines add their id)
input ENUM_PRESET   InpPreset           = PRESET_MEDIUM; // Account preset (governs risk)
input ENUM_DASH_MODE InpDashMode        = DASH_PRO;      // Dashboard mode (hotkeys 1/2/3)
input ENUM_LOG_LEVEL InpLogLevel        = LOG_INFO;      // Log verbosity
input bool          InpAutoTrade        = true;          // Enable autonomous trading

input group "== Intelligence / AI =="
input double        InpMinConfidence    = 0.55;          // Base AI confidence threshold
input bool          InpAdaptiveThresholds = true;        // Adapt threshold to account health
input bool          InpUseMTFConfirm    = true;          // Require multi-timeframe agreement
input ENUM_TIMEFRAMES InpTFMid          = PERIOD_H1;     // Mid confirmation timeframe
input ENUM_TIMEFRAMES InpTFHigh         = PERIOD_H4;     // High confirmation timeframe

input group "== Risk & Stops =="
input double        InpAtrSlMult        = 1.5;           // Stop loss = ATR x
input double        InpAtrTpMult        = 2.5;           // Take profit = ATR x
input double        InpMinStopAtrMult   = 0.6;           // Minimum stop distance = ATR x
input double        InpMaxSpreadPts     = 0;             // Max spread points (0 = auto)
input bool          InpUseKillSwitch    = true;          // Hard halt on max drawdown

input group "== Trade Management =="
input bool          InpUseTrailing      = true;          // ATR trailing stop
input double        InpTrailAtrMult     = 2.0;           // Trailing distance = ATR x
input double        InpTrailStartRR     = 1.0;           // Start trailing at R multiple
input bool          InpUseBreakeven     = true;          // Move to break-even
input double        InpBeTriggerRR      = 1.0;           // Break-even trigger (R)
input double        InpBeLockPts        = 20;            // Break-even lock (points)
input bool          InpUsePartialClose  = true;          // One-shot partial close
input double        InpPartialRR        = 1.5;           // Partial close trigger (R)
input double        InpPartialPct       = 0.5;           // Fraction to close

input group "== Grid / Recovery (opt-in) =="
input double        InpGridStepAtrMult  = 1.0;           // Grid step = ATR x

input group "== Engine Roster =="
input bool          InpEnTrend          = true;
input bool          InpEnSwing          = true;
input bool          InpEnMomentum       = true;
input bool          InpEnRange          = true;
input bool          InpEnMeanReversion  = true;
input bool          InpEnScalping        = true;
input bool          InpEnBreakout       = true;
input bool          InpEnVolatility     = true;
input bool          InpEnSession        = false;
input bool          InpEnSupportRes     = true;
input bool          InpEnOrderBlock     = true;
input bool          InpEnFVG            = true;
input bool          InpEnLiquidityGrab  = true;
input bool          InpEnSupplyDemand   = true;
input bool          InpEnSMC            = true;
input bool          InpEnVolumeProfile  = false;
input bool          InpEnGrid           = false;         // opt-in (risky)
input bool          InpEnAdaptiveGrid   = false;         // opt-in (risky)
input bool          InpEnMartingale     = false;         // opt-in (risky)
input bool          InpEnRecovery       = false;         // opt-in
input bool          InpEnHedging        = false;         // opt-in

input group "== Filters =="
input bool          InpUseSessionFilter = false;         // Only trade active sessions
input bool          InpUseNewsFilter    = false;         // Avoid high-volatility news bars
input int           InpNewsBufferMin    = 30;            // News buffer (minutes)

input group "== Scanner =="
input string        InpScannerSymbols   = "";            // CSV watchlist ("" = chart symbol)
input ENUM_TIMEFRAMES InpScannerTF      = PERIOD_H1;     // Scanner timeframe

input group "== Dashboard / Chart =="
input bool          InpShowDashboard    = true;          // Draw the dashboard
input bool          InpDarkSkin         = true;          // Apply dark cyber chart skin
input bool          InpDrawZones        = true;          // Draw zones / markers on chart

//--- fold inputs into an SConfig (preset applied by the caller) -----
SConfig BuildConfig()
  {
   SConfig c;
   c.magicBase          = InpMagicBase;
   c.preset             = InpPreset;
   c.dashMode           = InpDashMode;
   c.logLevel           = InpLogLevel;
   c.autoTrade          = InpAutoTrade;

   c.tfMid              = InpTFMid;
   c.tfHigh             = InpTFHigh;
   c.useMTFConfirm      = InpUseMTFConfirm;

   c.minConfidence      = InpMinConfidence;
   c.adaptiveThresholds = InpAdaptiveThresholds;
   c.aggressiveness     = 0.5;   // preset overrides

   //--- risk envelope defaults (preset overrides most of these) ----
   c.riskPercent        = 1.0;
   c.maxSpreadPts       = InpMaxSpreadPts;
   c.maxOpenTrades      = 5;
   c.maxTradesPerSymbol = 2;
   c.dailyLossLimitPct  = 5.0;
   c.maxDrawdownPct     = 15.0;
   c.equityStopPct      = 20.0;
   c.useKillSwitch      = InpUseKillSwitch;

   c.atrSlMult          = InpAtrSlMult;
   c.atrTpMult          = InpAtrTpMult;
   c.minStopAtrMult     = InpMinStopAtrMult;

   c.useTrailing        = InpUseTrailing;
   c.trailAtrMult       = InpTrailAtrMult;
   c.trailStartRR       = InpTrailStartRR;
   c.useBreakeven       = InpUseBreakeven;
   c.beTriggerRR        = InpBeTriggerRR;
   c.beLockPts          = InpBeLockPts;
   c.usePartialClose    = InpUsePartialClose;
   c.partialRR          = InpPartialRR;
   c.partialPct         = InpPartialPct;

   c.useRecovery        = true;
   c.gridStepAtrMult    = InpGridStepAtrMult;
   c.gridMaxLevels      = 5;
   c.gridLotFactor      = 1.2;

   c.useSessionFilter   = InpUseSessionFilter;
   c.useNewsFilter      = InpUseNewsFilter;
   c.newsBufferMinutes  = InpNewsBufferMin;

   c.showDashboard      = InpShowDashboard;
   c.darkSkin           = InpDarkSkin;
   c.drawZones          = InpDrawZones;
   return c;
  }

//--- resolve the engine on/off toggles from inputs ------------------
SEngineToggles BuildToggles()
  {
   SEngineToggles t;
   t.trend=InpEnTrend;             t.swing=InpEnSwing;
   t.momentum=InpEnMomentum;       t.range=InpEnRange;
   t.meanRev=InpEnMeanReversion;   t.scalp=InpEnScalping;
   t.breakout=InpEnBreakout;       t.volatility=InpEnVolatility;
   t.session=InpEnSession;         t.supportRes=InpEnSupportRes;
   t.orderBlock=InpEnOrderBlock;   t.fvg=InpEnFVG;
   t.liqGrab=InpEnLiquidityGrab;   t.supplyDem=InpEnSupplyDemand;
   t.smc=InpEnSMC;                 t.volProfile=InpEnVolumeProfile;
   t.grid=InpEnGrid;               t.adaptiveGrid=InpEnAdaptiveGrid;
   t.martingale=InpEnMartingale;   t.recovery=InpEnRecovery;
   t.hedging=InpEnHedging;
   return t;
  }

#endif // PERCEPTION_PARAMS_MQH
//+------------------------------------------------------------------+
