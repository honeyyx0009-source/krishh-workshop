//+------------------------------------------------------------------+
//|                                             AdaptiveGoldGrid.mq5 |
//|            Adaptive Gold Grid EA - Main orchestrator (v2)          |
//|                                                                  |
//|   Institutional-style, preset-driven ADAPTIVE GRID + ACTIVE        |
//|   BASKET RECOVERY (bounded martingale) system for XAUUSD (gold).   |
//+------------------------------------------------------------------+
//| ARCHITECTURE (all modules under MQL5/Include/AdaptiveGoldGrid/):   |
//|   Config.mqh          - presets + tuned PresetProfile             |
//|   Logger.mqh          - leveled logging                           |
//|   OrderManager.mqh     - defensive CTrade wrapper + basket queries |
//|   SafetyValve.mqh      - ENTRY-blocking gate (never closes/halts)  |
//|   MarketAnalysis.mqh    - classical RSI/MACD/ATR/MA + S/R (NOT ML) |
//|   RegimeFilter.mqh      - HIGHER-TF regime gate (ADX/EMA/ATR)      |
//|   GridEngine.mqh        - ATR-adaptive grid geometry (intents only)|
//|   LotSizer.mqh          - bounded adaptive/progressive lot sizing  |
//|   RecoveryEngine.mqh     - ACTIVE basket recovery                  |
//|   MLHook.mqh             - optional ONNX inference (OFF by default)|
//|                                                                  |
//| ================  v2 CHANGES (WHY THEY EXIST)  ================== |
//|   A v1 test blew a $1000 demo account on gold in two days using    |
//|   PRESET_MICRO. Three defects caused it and all three are fixed:   |
//|                                                                  |
//|   1. COUNTER-TREND ENTRY + AVERAGING. v1 picked its side from a    |
//|      fast-timeframe EMA pair, so a brief flicker inside a larger    |
//|      trend was enough to seed against it - then it kept averaging   |
//|      into the trend. v2 adds RegimeFilter: a higher-timeframe       |
//|      ADX/EMA/ATR gate that refuses counter-trend seeds AND refuses  |
//|      to enlarge a basket that opposes a dominant trend.            |
//|                                                                  |
//|   2. OVER-SIZED EXPOSURE. v1 PRESET_MICRO permitted 0.50 basket    |
//|      lots. On gold (1 lot = 100 oz, so $1 move = $100) that let a  |
//|      $77 adverse move erase a $1000 account. v2 retunes every      |
//|      preset to ~0.02 lots per $1000 equity, adds PRESET_NANO for   |
//|      ~$1000 accounts, and adds optional capital-aware auto-sizing. |
//|                                                                  |
//|   3. PASSIVE "HOLD FOREVER" RECOVERY. v1 could only wait for the   |
//|      market to return, so baskets sat for weeks while the loss     |
//|      grew. v2 recovery is ACTIVE: time-decay take-profit, basket   |
//|      trailing, partial profit harvesting, and a bounded basket     |
//|      stop that closes a hopeless basket and starts fresh.          |
//|                                                                  |
//|   HONEST NOTE: item 3 deliberately REVERSES the v1 rule of "never  |
//|   close at a loss". Those two goals - never realise a loss, and    |
//|   never get stuck - cannot both be satisfied. If the market does   |
//|   not come back, the only choices are a bounded loss now or an     |
//|   unbounded loss later. The basket stop is an input and can be     |
//|   disabled, but doing so restores the v1 failure mode.            |
//+------------------------------------------------------------------+
#property copyright "Adaptive Gold Grid EA"
#property version   "2.00"
#property description "Preset-driven adaptive grid + ACTIVE basket recovery for XAUUSD (gold)."
#property description "Higher-timeframe regime filter refuses counter-trend seeding and averaging."
#property description "Active recovery: time-decay TP, basket trailing, partial harvest, bounded basket stop."
#property description "BACKTEST FIRST. High-risk grid/martingale design - use a demo before live."
#property strict

//--- Engine modules (resolve under MQL5/Include/AdaptiveGoldGrid/).
#include <AdaptiveGoldGrid/Config.mqh>
#include <AdaptiveGoldGrid/Logger.mqh>
#include <AdaptiveGoldGrid/OrderManager.mqh>
#include <AdaptiveGoldGrid/SafetyValve.mqh>
#include <AdaptiveGoldGrid/MarketAnalysis.mqh>
#include <AdaptiveGoldGrid/RegimeFilter.mqh>
#include <AdaptiveGoldGrid/GridEngine.mqh>
#include <AdaptiveGoldGrid/LotSizer.mqh>
#include <AdaptiveGoldGrid/RecoveryEngine.mqh>
#include <AdaptiveGoldGrid/MLHook.mqh>

//+------------------------------------------------------------------+
//|                        INPUT PARAMETERS                          |
//+------------------------------------------------------------------+

//--- General ---------------------------------------------------------
input group "=== General ==="
input ENUM_ACCOUNT_PRESET AccountPreset = PRESET_NANO;        // Account preset (NANO for ~$1000)
input long                MagicNumber   = 20240517;           // Magic number (isolates this EA's basket)
input ENUM_TIMEFRAMES     AnalysisTF    = PERIOD_M15;         // Fast analysis timeframe

//--- Regime filter (higher timeframe) -------------------------------
input group "=== Regime Filter (prevents counter-trend grids) ==="
input bool                EnableRegimeFilter = true;          // Master switch (STRONGLY recommended ON)
input ENUM_TIMEFRAMES     RegimeTF           = PERIOD_H1;     // Higher timeframe for regime detection
input ENUM_GRID_POLICY    GridPolicy         = POLICY_RANGING_ONLY; // Which regimes may seed a basket
input int                 RegimeAdxPeriod    = 14;            // ADX period
input double              RegimeAdxTrend     = 22.0;          // ADX above this => a trend exists
input double              RegimeAdxStrong    = 30.0;          // ADX above this => STRONG trend
input int                 RegimeEmaFast      = 50;            // Higher-TF fast EMA
input int                 RegimeEmaSlow      = 200;           // Higher-TF slow EMA
input double              RegimeViolentRatio = 1.80;          // fast/slow ATR above this => stand aside

//--- Logging ---------------------------------------------------------
input group "=== Logging ==="
input ENUM_LOG_LEVEL      LogLevel      = LOG_INFO;           // Log verbosity
input bool                EnableFileLog = false;              // Also write log to MQL5/Files
input string              LogFileName   = "AdaptiveGoldGrid.log"; // Log file name (under MQL5/Files)

//--- Execution cadence ----------------------------------------------
input group "=== Execution ==="
input bool                SeedOnNewBarOnly = true;            // Seed a fresh basket only on a new bar
input bool                WarnIfNotGold    = true;            // Warn if the chart symbol is not XAUUSD/gold

//--- Group take-profit (basket) -------------------------------------
input group "=== Basket Take-Profit ==="
input ENUM_BASKET_TP_MODE BasketTPMode     = BASKET_TP_CURRENCY; // Group TP mode
input double              BasketTPCurrency = 5.0;             // (Currency mode) close basket when PnL >= this
input double              BasketTPPerLot   = 0.0;             // (Currency mode) extra target per basket lot
input double              BasketTPPoints   = 200.0;           // (Points mode) points beyond break-even

//--- Active recovery: time-decay TP ---------------------------------
input group "=== Active Recovery: Time-Decay TP ==="
input bool                UseDecayOverride    = false;        // Override the preset's decay settings
input double              DecayStartHours     = 8.0;          // Target starts shrinking after this age
input double              DecayFullHours      = 48.0;         // Target reaches its floor at this age
input double              DecayFloorFraction  = 0.15;         // Floor as a fraction of the original target

//--- Active recovery: trailing + harvest ----------------------------
input group "=== Active Recovery: Trailing & Harvest ==="
input bool                UseTrailOverride    = false;        // Override the preset's trailing settings
input double              TrailActivateFrac   = 0.70;         // Arm trailing at this fraction of target
input double              TrailGivebackFrac   = 0.35;         // Close if this fraction of peak profit is lost
input bool                UseHarvestOverride  = false;        // Override the preset's harvest settings
input bool                EnablePartialHarvest= true;         // Bank profitable legs to cut exposure
input double              HarvestMinLegProfit = 0.30;         // A leg must be this profitable to harvest

//--- Basket stop (bounded loss backstop) ----------------------------
input group "=== Basket Stop (bounded loss - READ THE README) ==="
input bool                UseStopOverride     = false;        // Override the preset's basket-stop settings
input bool                EnableBasketStop    = true;         // Close a hopeless basket at a bounded loss
input double              BasketStopLossPct   = 8.0;          // Close basket when loss >= this % of balance

//--- Capital-aware auto-sizing --------------------------------------
input group "=== Capital-Aware Auto-Sizing ==="
input bool                EnableCapitalSizing = true;         // Derive exposure caps from live equity
input bool                BlockIfUnderfunded  = false;        // Refuse to init if equity is below the preset minimum

//--- Hedging (optional recovery strategy) ---------------------------
input group "=== Hedging (optional) ==="
input bool                EnableHedge      = false;           // Enable the optional opposite-side hedge
input double              HedgeTriggerDDPct= 15.0;            // Arm hedge when basket DD >= this % of balance

//--- Optional Phase-2 ONNX ML hook (OFF by default) -----------------
input group "=== Optional ONNX ML (Phase-2, default OFF) ==="
input bool                EnableOnnxML     = false;           // Enable optional ONNX inference (advisory only)
input string              OnnxModelFile    = "";              // .onnx model under MQL5/Files (empty => NEUTRAL)

//--- Advanced manual overrides --------------------------------------
input group "=== Advanced Sizing Overrides (leave off to use preset) ==="
input bool                UseManualOverride       = false;    // Override preset sizing with the fields below
input double              OverrideBaseLot         = 0.01;     // Manual base lot
input int                 OverrideMaxGridLevels   = 3;        // Manual max grid levels
input double              OverrideLotProgression  = 1.00;     // Manual lot progression factor (>=1.0)
input double              OverrideMaxLotCap       = 0.01;     // Manual per-order lot cap
input double              OverrideMaxBasketLots   = 0.03;     // Manual total-basket exposure cap
input double              OverrideAtrSpacingMult  = 2.00;     // Manual ATR spacing multiplier
input double              OverrideMaxDrawdownPct  = 15.0;     // Manual drawdown gate % (entry-blocking only)

//+------------------------------------------------------------------+
//|                        GLOBAL STATE                              |
//+------------------------------------------------------------------+
CConfig          g_config;
CLogger          g_logger;
COrderManager    g_om;
CSafetyValve     g_safety;
CMarketAnalysis  g_market;
CRegimeFilter    g_regime;
CGridEngine      g_grid;
CLotSizer        g_lots;
CRecoveryEngine  g_recovery;
CMLHook          g_ml;

PresetProfile    g_profile;
datetime         g_last_bar_time = 0;
bool             g_market_ready  = false;
bool             g_regime_ready  = false;

//+------------------------------------------------------------------+
//| Apply manual sizing overrides on top of the preset profile.      |
//+------------------------------------------------------------------+
void ApplyOverrides(PresetProfile &p)
  {
   if(UseManualOverride)
     {
      p.base_lot                 = OverrideBaseLot;
      p.max_grid_levels          = OverrideMaxGridLevels;
      p.lot_progression_factor   = MathMax(1.0,OverrideLotProgression);
      p.max_lot_cap              = OverrideMaxLotCap;
      p.max_basket_exposure_lots = OverrideMaxBasketLots;
      p.atr_spacing_multiplier   = OverrideAtrSpacingMult;
      p.max_drawdown_percent     = OverrideMaxDrawdownPct;
      g_logger.Warn("Manual sizing overrides ACTIVE - preset sizing replaced by input fields.");
     }

   if(UseDecayOverride)
     {
      p.tp_decay_start_hours    = MathMax(0.0,DecayStartHours);
      p.tp_decay_full_hours     = MathMax(0.0,DecayFullHours);
      p.tp_decay_floor_fraction = MathMax(0.0,MathMin(1.0,DecayFloorFraction));
      g_logger.Info("Time-decay TP overrides ACTIVE.");
     }

   if(UseTrailOverride)
     {
      p.trail_activate_fraction = MathMax(0.0,TrailActivateFrac);
      p.trail_giveback_fraction = MathMax(0.0,MathMin(1.0,TrailGivebackFrac));
      g_logger.Info("Basket trailing overrides ACTIVE.");
     }

   if(UseHarvestOverride)
     {
      p.enable_partial_harvest     = EnablePartialHarvest;
      p.harvest_min_leg_profit_ccy = MathMax(0.0,HarvestMinLegProfit);
      g_logger.Info("Partial-harvest overrides ACTIVE.");
     }

   if(UseStopOverride)
     {
      p.enable_basket_stop       = EnableBasketStop;
      p.basket_stop_loss_percent = MathMax(0.1,BasketStopLossPct);
      g_logger.Warn(StringFormat("Basket-stop overrides ACTIVE: enabled=%s at %.2f%% of balance.",
                                 (p.enable_basket_stop?"true":"false"),p.basket_stop_loss_percent));
     }

   if(!p.enable_basket_stop)
      g_logger.Warn("BASKET STOP IS DISABLED. A basket trapped against a trend will hold indefinitely "
                    "and the floating loss can grow until the broker stops the account out. "
                    "This is the v1 failure mode - re-enable unless you fully accept that risk.");
  }

//+------------------------------------------------------------------+
//| CAPITAL-AWARE AUTO-SIZING                                        |
//|                                                                  |
//| Derives the total basket exposure cap from live equity using the  |
//| preset's exposure density (lots per $1000). It only ever SHRINKS  |
//| the preset caps, never enlarges them, so selecting an over-sized  |
//| preset on a small account cannot silently increase risk.         |
//|                                                                  |
//| Why this matters on gold: 1.00 lot = 100 oz, so a $1 gold move is |
//| $100 per lot. Exposure of E lots loses about E * 100 * M dollars  |
//| on an adverse move of M dollars. Keeping E proportional to equity |
//| is what stops a routine $100 gold trend from being fatal.        |
//+------------------------------------------------------------------+
void ApplyCapitalAwareSizing(PresetProfile &p)
  {
   if(!EnableCapitalSizing)
      return;

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq<=0.0)
     {
      g_logger.Warn("Capital-aware sizing skipped: equity unavailable.");
      return;
     }

   double vmin = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   if(vmin<=0.0) vmin = 0.01;

   //--- Exposure the account can actually carry at the preset's density.
   double derived = p.exposure_lots_per_1k * (eq/1000.0);

   //--- The broker cannot trade less than one minimum lot, so that is the
   //    hard floor. If even one minimum lot exceeds the derived budget the
   //    account is under-funded for this instrument - warn loudly.
   if(derived < vmin)
     {
      g_logger.Warn(StringFormat("UNDER-FUNDED: equity %.2f supports only %.4f lots at this preset's density, "
                                 "but the broker minimum is %.2f lots. Running at the broker minimum means each "
                                 "position carries MORE risk than the preset intends. Consider a larger account "
                                 "or a symbol with a smaller contract size.",eq,derived,vmin));
      derived = vmin;
     }

   //--- Only ever tighten.
   if(derived < p.max_basket_exposure_lots)
     {
      g_logger.Info(StringFormat("Capital-aware sizing: basket exposure cap %.3f -> %.3f lots (equity %.2f, %.3f lots/$1k).",
                                 p.max_basket_exposure_lots,derived,eq,p.exposure_lots_per_1k));
      p.max_basket_exposure_lots = derived;
     }

   //--- Keep the per-order cap and base lot internally consistent.
   if(p.max_lot_cap > p.max_basket_exposure_lots)
      p.max_lot_cap = p.max_basket_exposure_lots;
   if(p.max_lot_cap < vmin)
      p.max_lot_cap = vmin;
   if(p.base_lot > p.max_lot_cap)
      p.base_lot = p.max_lot_cap;
   if(p.base_lot < vmin)
      p.base_lot = vmin;

   //--- Under-capitalisation advisory against the preset's own guidance.
   if(p.recommended_min_equity>0.0 && eq < p.recommended_min_equity)
      g_logger.Warn(StringFormat("Equity %.2f is below this preset's recommended minimum %.2f. "
                                 "Consider a smaller preset (PRESET_NANO is the smallest).",
                                 eq,p.recommended_min_equity));
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
//|                                                                  |
//| THE MANDATORY GATE: no OrderManager send happens unless the      |
//| SafetyValve says the account has room. If blocked we LOG and     |
//| SKIP. Nothing is ever closed to "make room".                     |
//+------------------------------------------------------------------+
bool ExecuteIntentGated(const GridIntent &gi,const double lot,const string comment)
  {
   if(!gi.valid || lot<=0.0)
      return(false);

   SafetyDecision d = g_safety.CanOpenNew(gi.direction,lot);
   if(!d.allowed)
     {
      g_logger.Warn("Entry BLOCKED by SafetyValve: "+d.detail+" ["+comment+"]");
      return(false);
     }

   if(!g_om.HasMarginFor(gi.direction,lot))
     {
      g_logger.Warn("Entry SKIPPED: OrderManager reports insufficient margin ["+comment+"].");
      return(false);
     }

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
   g_logger.SetMinLevel(LogLevel);
   g_logger.SetPrefix("AdaptiveGoldGrid");
   if(EnableFileLog)
      g_logger.EnableFile(LogFileName);
   g_logger.Info("OnInit: starting Adaptive Gold Grid EA v2.");

   //--- Resolve the active profile: preset -> overrides -> capital-aware.
   g_profile = g_config.GetProfile(AccountPreset);
   ApplyOverrides(g_profile);
   ApplyCapitalAwareSizing(g_profile);

   g_logger.Info(StringFormat("Preset=%s base=%.2f levels=%d progr=%.2f capLot=%.2f capBasket=%.3f atrMult=%.2f ddGate=%.1f%% stop=%s@%.1f%%",
                              g_config.PresetName(AccountPreset),g_profile.base_lot,g_profile.max_grid_levels,
                              g_profile.lot_progression_factor,g_profile.max_lot_cap,
                              g_profile.max_basket_exposure_lots,g_profile.atr_spacing_multiplier,
                              g_profile.max_drawdown_percent,
                              (g_profile.enable_basket_stop?"ON":"OFF"),g_profile.basket_stop_loss_percent));

   //--- Optional hard refusal when the account is below the preset minimum.
   double eq_now = AccountInfoDouble(ACCOUNT_EQUITY);
   if(BlockIfUnderfunded && g_profile.recommended_min_equity>0.0 &&
      eq_now < g_profile.recommended_min_equity)
     {
      g_logger.Error(StringFormat("Aborting init: equity %.2f is below the preset's recommended minimum %.2f "
                                  "and BlockIfUnderfunded is true.",eq_now,g_profile.recommended_min_equity));
      return(INIT_FAILED);
     }

   //--- Symbol sanity.
   if(WarnIfNotGold && !SymbolLooksLikeGold())
      g_logger.Warn("Chart symbol '"+_Symbol+"' does not look like XAUUSD/gold. This EA is tuned for gold.");

   if(!SymbolInfoInteger(_Symbol,SYMBOL_SELECT))
      SymbolSelect(_Symbol,true);
   ENUM_SYMBOL_TRADE_MODE tm = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE);
   if(tm==SYMBOL_TRADE_MODE_DISABLED)
     {
      g_logger.Error("Symbol trading is DISABLED for '"+_Symbol+"'. Aborting init.");
      return(INIT_FAILED);
     }

   //--- Core modules.
   g_om.Init(_Symbol,MagicNumber,GetPointer(g_logger));
   g_safety.Init(g_profile,_Symbol,GetPointer(g_om),GetPointer(g_logger));

   g_market_ready = g_market.Init(_Symbol,AnalysisTF,GetPointer(g_logger));
   if(!g_market_ready)
     {
      g_logger.Error("MarketAnalysis failed to create indicator handles. Aborting init.");
      return(INIT_FAILED);
     }

   //--- Higher-timeframe regime filter. When disabled we still leave the
   //    object un-initialised and pass NULL semantics via g_regime_ready.
   if(EnableRegimeFilter)
     {
      g_regime_ready = g_regime.Init(_Symbol,RegimeTF,GetPointer(g_logger),
                                     RegimeAdxPeriod,RegimeEmaFast,RegimeEmaSlow,
                                     14,50,RegimeAdxTrend,RegimeAdxStrong,RegimeViolentRatio);
      if(!g_regime_ready)
        {
         g_logger.Error("RegimeFilter failed to create indicator handles. Aborting init "
                        "(the regime filter is the main protection against counter-trend grids).");
         return(INIT_FAILED);
        }
     }
   else
     {
      g_regime_ready = false;
      g_logger.Warn("REGIME FILTER DISABLED. The EA may seed and average AGAINST a dominant trend, "
                    "which is the primary way grid accounts are destroyed. Strongly consider enabling it.");
     }

   g_grid.Init(g_profile,_Symbol,GetPointer(g_logger));
   g_lots.Init(g_profile,_Symbol,GetPointer(g_om),GetPointer(g_logger));

   //--- RecoveryEngine: pass the regime filter only when it is live.
   //    Use an explicit pointer variable rather than a ternary so the
   //    NULL case is unambiguous to the compiler.
   CRegimeFilter *regime_ptr = NULL;
   if(g_regime_ready)
      regime_ptr = GetPointer(g_regime);

   g_recovery.Init(g_profile,GetPointer(g_om),GetPointer(g_safety),
                   regime_ptr,
                   GetPointer(g_grid),GetPointer(g_lots),GetPointer(g_logger));
   g_recovery.ConfigureTP(BasketTPMode,BasketTPCurrency,BasketTPPoints,BasketTPPerLot);
   g_recovery.ConfigureHedge(EnableHedge,HedgeTriggerDDPct);

   g_ml.Init(EnableOnnxML,OnnxModelFile,GetPointer(g_logger));

   g_logger.Info("OnInit complete. EA armed.");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_market.Deinit();
   g_regime.Deinit();
   g_ml.Release();
   g_logger.Info(StringFormat("OnDeinit: reason=%d. Handles released. (Open positions are left untouched.)",reason));
  }

//+------------------------------------------------------------------+
//| Expert tick                                                      |
//+------------------------------------------------------------------+
void OnTick(void)
  {
   g_safety.UpdatePeakEquity();

   //--- (1) Refresh the fast market context.
   static MarketContext  mc;
   static RegimeContext  rc;
   bool new_bar     = IsNewBar();
   bool have_basket = (g_om.CountBasketPositions() > 0);

   if(new_bar || have_basket || !mc.ready)
      mc = g_market.Evaluate();

   if(!mc.ready)
      return;   // no reliable data -> never force a trade

   //--- (2) Refresh the higher-timeframe regime read-out.
   //    When the filter is disabled we synthesise a permissive context so
   //    the rest of the flow is identical; the RecoveryEngine receives a
   //    NULL filter pointer in that case and skips its regime gate.
   if(g_regime_ready)
     {
      if(new_bar || have_basket || !rc.ready)
         rc = g_regime.Evaluate();
      if(!rc.ready)
         return;   // regime data not ready -> do not open new exposure
     }
   else
     {
      rc.ready     = true;
      rc.regime    = REGIME_RANGING;   // permissive placeholder when disabled
      rc.adx       = 0.0;
      rc.plus_di   = 0.0;
      rc.minus_di  = 0.0;
      rc.htf_trend = TREND_NONE;
      rc.atr_ratio = 1.0;
      rc.detail    = "regime filter disabled";
     }

   //--- (3) BASKET MANAGEMENT FIRST (active recovery).
   if(have_basket)
     {
      RecoveryDecision rd = g_recovery.Manage(mc,rc);
      switch(rd.action)
        {
         case RECOVERY_CLOSED_IN_PROFIT:
         case RECOVERY_CLOSED_TRAILED:
         case RECOVERY_CLOSED_AT_STOP:
         case RECOVERY_HARVESTED_LEG:
            //--- The engine already acted on existing positions.
            return;

         case RECOVERY_ADD_AVERAGING:
            ExecuteIntentGated(rd.intent,rd.lot,"avg");
            return;

         case RECOVERY_ADD_HEDGE:
            if(ExecuteIntentGated(rd.intent,rd.lot,"hedge"))
               g_recovery.MarkHedgePlaced();
            return;

         case RECOVERY_NONE:
         default:
            //--- Do NOT seed a new basket while one is being recovered.
            return;
        }
     }

   //--- (4) NO BASKET: consider SEEDING a fresh one.
   if(SeedOnNewBarOnly && !new_bar)
      return;

   GridIntent seed = g_grid.BuildSeedIntent(mc);
   if(!seed.valid)
      return;   // no decisive bias yet -> wait

   //--- (4a) REGIME GATE ON THE SEED. This is where a counter-trend entry
   //    - the root cause of the v1 blow-up - is refused outright.
   if(g_regime_ready)
     {
      string why="";
      if(!g_regime.AllowSeed(seed.direction,rc,GridPolicy,why))
        {
         g_logger.Debug("Seed refused by RegimeFilter: "+why);
         return;
        }
      g_logger.Debug("RegimeFilter allows seed: "+why);
     }

   //--- (4b) OPTIONAL ML CONFIRMATION FILTER (advisory only, OFF by default).
   //    An inactive hook returns NEUTRAL and this block is a no-op. When
   //    active the model may only VETO a classical seed; it can never
   //    create an entry and never bypasses the SafetyValve.
   MLPrediction mlp = g_ml.Predict(mc);
   if(mlp.active && mlp.opinion!=ML_NEUTRAL)
     {
      bool ml_agrees = (seed.direction==GRID_BUY  && mlp.opinion==ML_BULLISH) ||
                       (seed.direction==GRID_SELL && mlp.opinion==ML_BEARISH);
      if(!ml_agrees)
        {
         g_logger.Info(StringFormat("Seed VETOED by ONNX ML (conf=%.2f) - direction disagreement.",mlp.confidence));
         return;
        }
     }

   double seed_lot = g_lots.SeedLot(mc);
   if(seed_lot<=0.0)
     {
      g_logger.Warn("Seed skipped: bounded seed lot is 0 (exposure caps).");
      return;
     }

   //--- (5) Gate EVERY new-order intent through the SafetyValve before send.
   g_recovery.ResetBasketState();
   ExecuteIntentGated(seed,seed_lot,"seed");
  }
//+------------------------------------------------------------------+
