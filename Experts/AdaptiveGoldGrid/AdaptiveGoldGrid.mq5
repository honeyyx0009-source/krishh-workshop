//+------------------------------------------------------------------+
//|                                             AdaptiveGoldGrid.mq5 |
//|            Adaptive Gold Grid EA - Main orchestrator (FEAT-002)   |
//|                                                                  |
//|   Institutional-style, preset-driven ADAPTIVE GRID + BASKET       |
//|   RECOVERY (bounded martingale) system for XAUUSD (gold).         |
//+------------------------------------------------------------------+
//| ARCHITECTURE (all modules under MQL5/Include/AdaptiveGoldGrid/):   |
//|   Config.mqh          - presets + tuned PresetProfile             |
//|   Logger.mqh          - leveled logging                           |
//|   OrderManager.mqh     - defensive CTrade wrapper + basket queries |
//|   SafetyValve.mqh      - ENTRY-blocking gate (never closes/halts)  |
//|   MarketAnalysis.mqh    - classical RSI/MACD/ATR/MA + S/R (NOT ML) |
//|   GridEngine.mqh        - ATR-adaptive grid geometry (intents only)|
//|   LotSizer.mqh          - bounded adaptive/progressive lot sizing  |
//|   RecoveryEngine.mqh     - basket-first group recovery (profit-only |
//|                            close)                                  |
//|                                                                  |
//| INCLUDE STYLE: this file lives in                                 |
//|   <MT5>/MQL5/Experts/AdaptiveGoldGrid/AdaptiveGoldGrid.mq5         |
//| and the modules live in                                           |
//|   <MT5>/MQL5/Include/AdaptiveGoldGrid/*.mqh                        |
//| We use the ANGLE-BRACKET include style (<AdaptiveGoldGrid/X.mqh>)  |
//| which resolves against the MQL5/Include root. This is the         |
//| cleanest option when the tree is dropped into MQL5/ because the    |
//| modules also include each other by the SAME relative names        |
//| (e.g. #include "Config.mqh") which resolve within Include/         |
//| AdaptiveGoldGrid/ regardless of who pulls them in first.           |
//+------------------------------------------------------------------+
#property copyright "Adaptive Gold Grid EA"
#property version   "1.00"
#property description "Preset-driven adaptive grid + basket-recovery EA for XAUUSD (gold)."
#property description "Classical multi-indicator analysis (RSI/MACD/ATR/MA + price-action S/R)."
#property description "Bounded martingale recovery: the basket only ever closes IN PROFIT."
#property description "BACKTEST FIRST. High-risk grid/martingale design - use a demo before live."
#property strict

//--- Engine modules (resolve under MQL5/Include/AdaptiveGoldGrid/).
#include <AdaptiveGoldGrid/Config.mqh>
#include <AdaptiveGoldGrid/Logger.mqh>
#include <AdaptiveGoldGrid/OrderManager.mqh>
#include <AdaptiveGoldGrid/SafetyValve.mqh>
#include <AdaptiveGoldGrid/MarketAnalysis.mqh>
#include <AdaptiveGoldGrid/GridEngine.mqh>
#include <AdaptiveGoldGrid/LotSizer.mqh>
#include <AdaptiveGoldGrid/RecoveryEngine.mqh>

//+------------------------------------------------------------------+
//|                        INPUT PARAMETERS                          |
//|  Comments are human-readable so they render in the EA dialog.    |
//+------------------------------------------------------------------+

//--- General ---------------------------------------------------------
input group "=== General ==="
input ENUM_ACCOUNT_PRESET AccountPreset = PRESET_MICRO;      // Account preset (Micro/Medium/Large/BigLevel/Commercial)
input long                MagicNumber   = 20240517;          // Magic number (isolates this EA's basket)
input ENUM_TIMEFRAMES     AnalysisTF    = PERIOD_M15;        // Analysis timeframe

//--- Logging ---------------------------------------------------------
input group "=== Logging ==="
input ENUM_LOG_LEVEL      LogLevel      = LOG_INFO;          // Log verbosity
input bool                EnableFileLog = false;             // Also write log to MQL5/Files
input string              LogFileName   = "AdaptiveGoldGrid.log"; // Log file name (under MQL5/Files)

//--- Execution cadence ----------------------------------------------
input group "=== Execution ==="
input bool                SeedOnNewBarOnly = true;           // Seed a fresh basket only on a new bar (else every tick)
input bool                WarnIfNotGold    = true;           // Warn if the chart symbol is not XAUUSD/gold

//--- Group take-profit (basket) -------------------------------------
input group "=== Basket Take-Profit ==="
input ENUM_BASKET_TP_MODE BasketTPMode     = BASKET_TP_CURRENCY; // Group TP mode: currency profit or points beyond break-even
input double              BasketTPCurrency = 10.0;           // (Currency mode) close basket when floating PnL >= this
input double              BasketTPPerLot   = 0.0;            // (Currency mode) extra target per basket lot (scales with size)
input double              BasketTPPoints   = 200.0;          // (Points mode) close when price is this far beyond break-even

//--- Hedging (optional recovery strategy) ---------------------------
input group "=== Hedging (optional) ==="
input bool                EnableHedge      = false;          // Enable the optional opposite-side hedge action
input double              HedgeTriggerDDPct= 15.0;           // Arm hedge when basket floating DD >= this % of equity

//--- Reserved: ONNX ML (implemented in a later feature) -------------
input group "=== Reserved: ONNX ML (placeholder) ==="
input bool                EnableOnnxML     = false;          // RESERVED placeholder - ML module ships separately; gates nothing yet

//--- Advanced manual overrides --------------------------------------
input group "=== Advanced Overrides (leave off to use preset) ==="
input bool                UseManualOverride       = false;   // Override selected preset values with the fields below
input double              OverrideBaseLot         = 0.01;    // Manual base lot (if override on)
input int                 OverrideMaxGridLevels   = 6;       // Manual max grid levels (if override on)
input double              OverrideLotProgression  = 1.30;    // Manual lot progression factor (>=1.0)
input double              OverrideMaxLotCap       = 0.10;    // Manual per-order lot cap
input double              OverrideMaxBasketLots   = 0.50;    // Manual total-basket exposure cap
input double              OverrideAtrSpacingMult  = 1.50;    // Manual ATR spacing multiplier
input double              OverrideMaxDrawdownPct  = 25.0;    // Manual drawdown gate % (entry-blocking only)

//+------------------------------------------------------------------+
//|                        GLOBAL STATE                              |
//+------------------------------------------------------------------+
CConfig          g_config;
CLogger          g_logger;
COrderManager    g_om;
CSafetyValve     g_safety;
CMarketAnalysis  g_market;
CGridEngine      g_grid;
CLotSizer        g_lots;
CRecoveryEngine  g_recovery;

PresetProfile    g_profile;          // Resolved active profile
datetime         g_last_bar_time = 0;// New-bar detector
bool             g_market_ready  = false; // Did indicator handles create OK?

//+------------------------------------------------------------------+
//| Apply manual overrides on top of the preset profile (if enabled). |
//+------------------------------------------------------------------+
void ApplyOverrides(PresetProfile &p)
  {
   if(!UseManualOverride)
      return;
   p.base_lot                 = OverrideBaseLot;
   p.max_grid_levels          = OverrideMaxGridLevels;
   p.lot_progression_factor   = MathMax(1.0,OverrideLotProgression);
   p.max_lot_cap              = OverrideMaxLotCap;
   p.max_basket_exposure_lots = OverrideMaxBasketLots;
   p.atr_spacing_multiplier   = OverrideAtrSpacingMult;
   p.max_drawdown_percent     = OverrideMaxDrawdownPct;
   g_logger.Warn("Manual overrides ACTIVE - preset sizing values replaced by input fields.");
  }

//+------------------------------------------------------------------+
//| New-bar detector on the analysis timeframe.                      |
//+------------------------------------------------------------------+
bool IsNewBar(void)
  {
   datetime t = (datetime)SeriesInfoInteger(_Symbol,AnalysisTF,SERIES_LASTBAR_DATE);
   if(t==0)
      return(false);
   if(t!=g_last_bar_time)
     {
      g_last_bar_time = t;
      return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Is the current chart symbol a gold instrument?                   |
//+------------------------------------------------------------------+
bool SymbolLooksLikeGold(void)
  {
   string s = _Symbol;
   StringToUpper(s);
   return(StringFind(s,"XAU")>=0 || StringFind(s,"GOLD")>=0);
  }

//+------------------------------------------------------------------+
//| Route a NEW-order intent through the SafetyValve, then send.     |
//| Returns true if an order was actually placed.                    |
//|                                                                  |
//| THE MANDATORY GATE: no OrderManager send happens unless the      |
//| SafetyValve says the account has room. If blocked we LOG and     |
//| SKIP. We NEVER close anything to "make room" - holding is fine.  |
//+------------------------------------------------------------------+
bool ExecuteIntentGated(const GridIntent &gi,const double lot,const string comment)
  {
   if(!gi.valid || lot<=0.0)
      return(false);

   //--- (a) SafetyValve gate (drawdown / margin level / free & projected margin).
   SafetyDecision d = g_safety.CanOpenNew(gi.direction,lot);
   if(!d.allowed)
     {
      g_logger.Warn("Entry BLOCKED by SafetyValve: "+d.detail+" ["+comment+"] - holding, nothing closed.");
      return(false);
     }

   //--- (b) Belt-and-braces free-margin check at the OrderManager level.
   if(!g_om.HasMarginFor(gi.direction,lot))
     {
      g_logger.Warn("Entry SKIPPED: OrderManager reports insufficient margin ["+comment+"].");
      return(false);
     }

   //--- (c) Only now do we send. Seed uses market; averaging also market
   //    (basket recovery reacts to live price, not resting pendings).
   bool ok = g_om.OpenMarket(gi.direction,lot,comment);
   if(!ok)
      g_logger.Warn("OrderManager.OpenMarket returned false ["+comment+"].");
   return(ok);
  }

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit(void)
  {
   //--- Logger first so every other Init can report through it.
   g_logger.SetMinLevel(LogLevel);
   g_logger.SetPrefix("AdaptiveGoldGrid");
   if(EnableFileLog)
      g_logger.EnableFile(LogFileName);
   g_logger.Info("OnInit: starting Adaptive Gold Grid EA.");

   //--- Resolve the active profile from the preset, then apply overrides.
   g_profile = g_config.GetProfile(AccountPreset);
   ApplyOverrides(g_profile);
   g_logger.Info(StringFormat("Preset=%s base_lot=%.2f maxLevels=%d progr=%.2f capLot=%.2f capBasket=%.2f atrMult=%.2f ddCap=%.1f%%",
                              g_config.PresetName(AccountPreset),g_profile.base_lot,g_profile.max_grid_levels,
                              g_profile.lot_progression_factor,g_profile.max_lot_cap,g_profile.max_basket_exposure_lots,
                              g_profile.atr_spacing_multiplier,g_profile.max_drawdown_percent));

   //--- Symbol sanity: warn (do not block) if not gold.
   if(WarnIfNotGold && !SymbolLooksLikeGold())
      g_logger.Warn("Chart symbol '"+_Symbol+"' does not look like XAUUSD/gold. This EA is tuned for gold.");

   //--- Is the symbol tradable at all?
   if(!SymbolInfoInteger(_Symbol,SYMBOL_SELECT))
      SymbolSelect(_Symbol,true);
   ENUM_SYMBOL_TRADE_MODE tm = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE);
   if(tm==SYMBOL_TRADE_MODE_DISABLED)
     {
      g_logger.Error("Symbol trading is DISABLED for '"+_Symbol+"'. Aborting init.");
      return(INIT_FAILED);
     }

   //--- OrderManager (magic + symbol basket isolation).
   g_om.Init(_Symbol,MagicNumber,GetPointer(g_logger));

   //--- SafetyValve captures the starting equity as the drawdown baseline.
   g_safety.Init(g_profile,_Symbol,GetPointer(g_om),GetPointer(g_logger));

   //--- MarketAnalysis creates all indicator handles.
   g_market_ready = g_market.Init(_Symbol,AnalysisTF,GetPointer(g_logger));
   if(!g_market_ready)
     {
      g_logger.Error("MarketAnalysis failed to create indicator handles. Aborting init.");
      return(INIT_FAILED);
     }

   //--- GridEngine geometry + LotSizer (needs OrderManager for bounds).
   g_grid.Init(g_profile,_Symbol,GetPointer(g_logger));
   g_lots.Init(g_profile,_Symbol,GetPointer(g_om),GetPointer(g_logger));

   //--- RecoveryEngine wiring + configuration.
   g_recovery.Init(g_profile,GetPointer(g_om),GetPointer(g_safety),
                   GetPointer(g_grid),GetPointer(g_lots),GetPointer(g_logger));
   g_recovery.ConfigureTP(BasketTPMode,BasketTPCurrency,BasketTPPoints,BasketTPPerLot);
   g_recovery.ConfigureHedge(EnableHedge,HedgeTriggerDDPct);

   if(EnableOnnxML)
      g_logger.Warn("EnableOnnxML=true but the ONNX ML module is not part of this build; toggle is a reserved placeholder and gates nothing.");

   g_logger.Info("OnInit complete. EA armed.");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   //--- Release indicator handles so the terminal does not leak them.
   g_market.Deinit();
   g_logger.Info(StringFormat("OnDeinit: reason=%d. Handles released. (Open positions are left untouched.)",reason));
  }

//+------------------------------------------------------------------+
//| Expert tick                                                      |
//+------------------------------------------------------------------+
void OnTick(void)
  {
   //--- Keep the drawdown baseline fresh every tick.
   g_safety.UpdatePeakEquity();

   //--- (1) Refresh consolidated market context.
   //    Analysis is bar-driven; refresh on a new bar and also whenever
   //    we have an open basket (so recovery reacts within the bar).
   static MarketContext mc;
   bool new_bar = IsNewBar();
   bool have_basket = (g_om.CountBasketPositions() > 0);
   if(new_bar || have_basket || !mc.ready)
      mc = g_market.Evaluate();

   if(!mc.ready)
      return;   // no reliable data this tick -> do nothing (never forces a trade)

   //--- (2) BASKET MANAGEMENT FIRST (profit-first, then recovery).
   if(have_basket)
     {
      RecoveryDecision rd = g_recovery.Manage(mc);
      switch(rd.action)
        {
         case RECOVERY_CLOSED_IN_PROFIT:
            //--- basket already closed in profit by the engine. Done.
            return;

         case RECOVERY_ADD_AVERAGING:
            //--- gate the averaging intent through the SafetyValve.
            ExecuteIntentGated(rd.intent,rd.lot,"avg");
            return;

         case RECOVERY_ADD_HEDGE:
            //--- gate the hedge intent; mark placed on success.
            if(ExecuteIntentGated(rd.intent,rd.lot,"hedge"))
               g_recovery.MarkHedgePlaced();
            return;

         case RECOVERY_NONE:
         default:
            //--- HOLD: do NOT seed a new basket while one is being recovered.
            return;
        }
     }

   //--- (3) NO BASKET: consider SEEDING a fresh one.
   //    Respect the new-bar-only seeding preference to avoid churn.
   if(SeedOnNewBarOnly && !new_bar)
      return;

   GridIntent seed = g_grid.BuildSeedIntent(mc);
   if(!seed.valid)
      return;   // no decisive bias yet -> wait

   double seed_lot = g_lots.SeedLot(mc);
   if(seed_lot<=0.0)
     {
      g_logger.Warn("Seed skipped: bounded seed lot is 0 (exposure caps).");
      return;
     }

   //--- (4) Gate EVERY new-order intent through the SafetyValve before send.
   g_recovery.ResetBasketState();          // fresh basket -> clear hedge flag
   ExecuteIntentGated(seed,seed_lot,"seed");
  }
//+------------------------------------------------------------------+
