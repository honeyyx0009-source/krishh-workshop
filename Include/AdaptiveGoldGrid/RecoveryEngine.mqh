//+------------------------------------------------------------------+
//|                                                RecoveryEngine.mqh |
//|   Adaptive Gold Grid EA - ACTIVE basket recovery engine (v2).      |
//+------------------------------------------------------------------+
//| =============  WHAT CHANGED IN v2 AND WHY  ===================== |
//|                                                                  |
//|   v1 was PASSIVE. It had exactly three behaviours: take the group  |
//|   take-profit, add an averaging level, or HOLD. Holding was        |
//|   documented as a virtue and the basket was never allowed to close  |
//|   at a loss.                                                      |
//|                                                                  |
//|   In a real $1000 gold test that produced precisely the failure    |
//|   the trader described: the EA sold into a rising market, stacked   |
//|   6-7 levels, ran out of averaging room, and then sat there for     |
//|   weeks while the floating loss ground the account down. "Never     |
//|   close at a loss" and "never get stuck" are mutually exclusive:    |
//|   if the market does not come back, the only two possible outcomes  |
//|   are a bounded loss now or an unbounded loss later.               |
//|                                                                  |
//|   v2 therefore replaces hold-and-pray with FIVE ACTIVE behaviours: |
//|                                                                  |
//|   1) TIME-DECAY GROUP TP - the profit target SHRINKS as the basket |
//|      ages, so a stale basket escapes at a small profit instead of   |
//|      waiting weeks for a full-size target. This is the direct fix   |
//|      for "stuck for 20-30 days".                                   |
//|                                                                  |
//|   2) BASKET TRAILING - once the basket has earned most of its       |
//|      target, lock the gain instead of giving it back.              |
//|                                                                  |
//|   3) PARTIAL HARVEST - bank a genuinely profitable leg to realise   |
//|      cash and CUT EXPOSURE on an aging or trend-trapped basket.     |
//|      HONEST TRADE-OFF: harvesting the best-priced legs slightly     |
//|      WORSENS the weighted average of what remains. It is a          |
//|      survival-over-recovery trade, which is the right trade for a   |
//|      small account. It is configurable and can be turned off.       |
//|                                                                  |
//|   4) REGIME-GATED AVERAGING - the engine now REFUSES to enlarge a   |
//|      basket that sits against a dominant higher-timeframe trend.    |
//|      This is the single most important change: it stops the         |
//|      "average into a trend until dead" spiral at its source.       |
//|                                                                  |
//|   5) BASKET STOP - a bounded-loss backstop that closes the whole    |
//|      basket at a configured % of balance and starts fresh.          |
//|      This is a DELIBERATE REVERSAL of the v1 profit-only rule.      |
//|      It is what makes a small account survivable. It is exposed as  |
//|      an input and can be disabled - but disabling it restores the   |
//|      v1 failure mode, and the README says so plainly.              |
//|                                                                  |
//|   RISK CONTROL STILL LIVES ELSEWHERE TOO (unchanged from v1):      |
//|     * SafetyValve gates whether a NEW order may open.              |
//|     * LotSizer bounds every lot (per-order + total-basket caps).    |
//|     * GridEngine bounds grid depth (preset.max_grid_levels).        |
//|                                                                  |
//|   CLOSE POLICY (the important invariant to audit):                  |
//|     COrderManager.CloseBasket() is pure mechanism and will close    |
//|     at any PnL. The POLICY of when that is allowed lives ONLY in     |
//|     this file, in exactly three places:                             |
//|       (a) group take-profit          -> basket is in profit         |
//|       (b) basket trailing            -> basket is in profit         |
//|       (c) basket stop                -> bounded loss, and ONLY when  |
//|                                          enable_basket_stop is true  |
//|     Plus ClosePosition() for a single profitable harvested leg.      |
//|     There is no other close path and no ExpertRemove anywhere.      |
//+------------------------------------------------------------------+
#ifndef ADAPTIVEGRID_RECOVERYENGINE_MQH
#define ADAPTIVEGRID_RECOVERYENGINE_MQH

#include "Config.mqh"
#include "Logger.mqh"
#include "OrderManager.mqh"
#include "SafetyValve.mqh"
#include "MarketAnalysis.mqh"
#include "RegimeFilter.mqh"
#include "GridEngine.mqh"
#include "LotSizer.mqh"

//+------------------------------------------------------------------+
//| Basket-TP target mode.                                           |
//+------------------------------------------------------------------+
enum ENUM_BASKET_TP_MODE
  {
   BASKET_TP_CURRENCY = 0,   // Close when floating PnL >= a currency amount
   BASKET_TP_POINTS          // Close when price is >= N points beyond break-even
  };

//+------------------------------------------------------------------+
//| The action the RecoveryEngine wants the main EA to take.         |
//+------------------------------------------------------------------+
enum ENUM_RECOVERY_ACTION
  {
   RECOVERY_NONE = 0,          // Nothing to do - hold
   RECOVERY_CLOSED_IN_PROFIT,  // Group TP hit -> engine closed the basket in profit
   RECOVERY_CLOSED_TRAILED,    // Trailing stop on basket profit -> closed in profit
   RECOVERY_CLOSED_AT_STOP,    // Basket stop hit -> closed at a BOUNDED LOSS
   RECOVERY_HARVESTED_LEG,     // Banked one profitable leg to cut exposure
   RECOVERY_ADD_AVERAGING,     // Suggest adding an averaging position (see intent)
   RECOVERY_ADD_HEDGE          // Suggest opening an opposite-side hedge (see intent)
  };

//+------------------------------------------------------------------+
//| RecoveryDecision                                                 |
//+------------------------------------------------------------------+
struct RecoveryDecision
  {
   ENUM_RECOVERY_ACTION action;      // What the engine recommends / did
   GridIntent           intent;      // Order intent when action adds exposure
   double               lot;         // Suggested (already-bounded) lot for the intent
   string               detail;      // Human-readable rationale
  };

//+------------------------------------------------------------------+
//| CRecoveryEngine                                                  |
//+------------------------------------------------------------------+
class CRecoveryEngine
  {
private:
   PresetProfile   m_profile;        // Active preset
   COrderManager  *m_om;             // Basket queries + close mechanism
   CSafetyValve   *m_sv;             // Entry gate (never closes anything)
   CRegimeFilter  *m_regime;         // Higher-TF regime gate for averaging
   CGridEngine    *m_grid;           // Grid geometry / step logic
   CLotSizer      *m_lot;            // Bounded lot sizing
   CLogger        *m_log;            // Optional logger

   //--- Group take-profit configuration.
   ENUM_BASKET_TP_MODE m_tp_mode;
   double          m_tp_currency;
   double          m_tp_points;
   double          m_tp_per_lot_ccy;

   //--- Optional hedge strategy.
   bool            m_hedge_enabled;
   double          m_hedge_trigger_dd_pct;
   bool            m_hedged_flag;

   //--- Anti-restack throttle (v1, retained).
   double          m_last_add_price;
   datetime        m_last_add_bar;

   //--- v2 active-management state.
   double          m_peak_pnl;       // Best floating PnL seen on this basket (for trailing)
   datetime        m_last_harvest_bar; // Throttle harvests to one per bar

   void            LogInfo(const string m) { if(m_log!=NULL) m_log.Info(m); }
   void            LogWarn(const string m) { if(m_log!=NULL) m_log.Warn(m); }
   void            LogDbg(const string m)  { if(m_log!=NULL) m_log.Debug(m); }

   //--- Which side is the basket on? Uses the side that actually has
   //    volume. Returns true via `ok` when a dominant side exists.
   ENUM_GRID_DIRECTION BasketDirection(bool &ok) const
     {
      ok=false;
      if(m_om==NULL) return(GRID_BUY);
      double buy_avg  = m_om.WeightedAvgEntry(GRID_BUY);
      double sell_avg = m_om.WeightedAvgEntry(GRID_SELL);
      bool has_buy  = (buy_avg  > 0.0);
      bool has_sell = (sell_avg > 0.0);

      if(has_buy && !has_sell) { ok=true; return(GRID_BUY);  }
      if(has_sell && !has_buy) { ok=true; return(GRID_SELL); }
      if(!has_buy && !has_sell) return(GRID_BUY);   // no basket

      //--- Both sides present (hedged): recovery side = the larger side.
      double buy_vol  = m_om.SideVolume(GRID_BUY);
      double sell_vol = m_om.SideVolume(GRID_SELL);
      ok=true;
      return(buy_vol>=sell_vol ? GRID_BUY : GRID_SELL);
     }

   //--- Bar-open time of the current bar (for the throttles).
   datetime        CurrentBarTime(void) const
     {
      if(m_om==NULL) return(0);
      datetime t[];
      if(CopyTime(m_om.Symbol(),PERIOD_CURRENT,0,1,t)==1)
         return(t[0]);
      return(0);
     }

   //--- ANTI-RESTACK guard (v1, retained): at most one averaging add per
   //    bar, and only after price has moved a further adaptive step.
   bool            AveragingSpacingOK(const MarketContext &mc,
                                      const ENUM_GRID_DIRECTION dir) const
     {
      if(m_last_add_price<=0.0) return(true);        // no prior add -> allow

      datetime bar = CurrentBarTime();
      if(bar!=0 && bar==m_last_add_bar)
         return(false);

      if(m_grid!=NULL)
        {
         double step_points = m_grid.AdaptiveStepPoints(mc);
         double point = SymbolInfoDouble(m_om.Symbol(),SYMBOL_POINT);
         if(point<=0.0) point=_Point;
         double step_price = step_points*point;
         double px = (dir==GRID_BUY ? mc.bid : mc.ask);
         if(dir==GRID_BUY)
           {
            if(px > m_last_add_price - step_price) return(false);
           }
         else
           {
            if(px < m_last_add_price + step_price) return(false);
           }
        }
      return(true);
     }

   void            StampAveragingAdd(const double price)
     {
      m_last_add_price = price;
      m_last_add_bar   = CurrentBarTime();
     }

   //--- Stable denominator for percentage-of-account thresholds.
   //    ACCOUNT_BALANCE is used rather than equity because equity already
   //    contains the floating loss we are measuring; using equity would
   //    make the ratio accelerate as the loss grows and trip the stop at
   //    an inconsistent real loss. Falls back to equity if balance is 0.
   double          AccountReference(void) const
     {
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      if(bal>0.0) return(bal);
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      return(eq>0.0 ? eq : 0.0);
     }

public:
                   CRecoveryEngine(void)
     {
      m_om                    = NULL;
      m_sv                    = NULL;
      m_regime                = NULL;
      m_grid                  = NULL;
      m_lot                   = NULL;
      m_log                   = NULL;
      m_tp_mode               = BASKET_TP_CURRENCY;
      m_tp_currency           = 10.0;
      m_tp_points             = 200.0;
      m_tp_per_lot_ccy        = 0.0;
      m_hedge_enabled         = false;
      m_hedge_trigger_dd_pct  = 15.0;
      m_hedged_flag           = false;
      m_last_add_price        = 0.0;
      m_last_add_bar          = 0;
      m_peak_pnl              = 0.0;
      m_last_harvest_bar      = 0;
     }
                  ~CRecoveryEngine(void) {}

   //--- Initialise. Call once from OnInit.
   void            Init(const PresetProfile &profile,
                        COrderManager *om,CSafetyValve *sv,
                        CRegimeFilter *regime,
                        CGridEngine *grid,CLotSizer *lot,CLogger *logger=NULL)
     {
      m_profile = profile;
      m_om      = om;
      m_sv      = sv;
      m_regime  = regime;
      m_grid    = grid;
      m_lot     = lot;
      m_log     = logger;
     }

   void            SetProfile(const PresetProfile &profile) { m_profile = profile; }

   void            ConfigureTP(const ENUM_BASKET_TP_MODE mode,const double tp_currency,
                               const double tp_points,const double tp_per_lot_ccy=0.0)
     {
      m_tp_mode        = mode;
      m_tp_currency    = MathMax(0.0,tp_currency);
      m_tp_points      = MathMax(0.0,tp_points);
      m_tp_per_lot_ccy = MathMax(0.0,tp_per_lot_ccy);
     }

   void            ConfigureHedge(const bool enabled,const double trigger_dd_pct)
     {
      m_hedge_enabled        = enabled;
      m_hedge_trigger_dd_pct = MathMax(0.0,trigger_dd_pct);
     }

   //--- Reset per-basket state (call when a basket has just closed).
   void            ResetBasketState(void)
     {
      m_hedged_flag      = false;
      m_last_add_price   = 0.0;
      m_last_add_bar     = 0;
      m_peak_pnl         = 0.0;
      m_last_harvest_bar = 0;
     }

   //================================================================//
   //  TIME-DECAY FACTOR                                             //
   //                                                                //
   //  Returns the multiplier applied to the group take-profit target  //
   //  based on how long the basket has been open:                    //
   //                                                                //
   //    age <= decay_start          -> 1.0            (full target)  //
   //    decay_start < age < full    -> linear ramp down              //
   //    age >= decay_full           -> floor_fraction (small target) //
   //                                                                //
   //  This is what lets a stale basket escape. Without it a basket    //
   //  waits indefinitely for a full-size target that a trending       //
   //  market may never hand back.                                    //
   //================================================================//
   double          TimeDecayFactor(const double age_hours) const
     {
      double start = m_profile.tp_decay_start_hours;
      double full  = m_profile.tp_decay_full_hours;
      double floor_f = m_profile.tp_decay_floor_fraction;
      if(floor_f<0.0) floor_f=0.0;
      if(floor_f>1.0) floor_f=1.0;

      if(full <= start)  return(1.0);       // misconfigured -> no decay
      if(age_hours <= start) return(1.0);
      if(age_hours >= full)  return(floor_f);

      double t = (age_hours - start)/(full - start);   // 0..1
      return(1.0 - t*(1.0 - floor_f));
     }

   //--- The decayed currency target for the current basket.
   double          EffectiveCurrencyTarget(const double age_hours) const
     {
      double target = m_tp_currency;
      if(m_tp_per_lot_ccy>0.0 && m_om!=NULL)
         target += m_tp_per_lot_ccy * m_om.BasketVolume();
      return(target * TimeDecayFactor(age_hours));
     }

   //================================================================//
   //  GROUP TAKE-PROFIT TARGET CHECK                                //
   //  Now age-aware. Still only ever fires while genuinely in profit. //
   //================================================================//
   bool            GroupTargetReached(const MarketContext &mc,const double age_hours) const
     {
      if(m_om==NULL) return(false);
      double pnl = m_om.BasketFloatingPnL();

      if(m_tp_mode==BASKET_TP_CURRENCY)
        {
         double target = EffectiveCurrencyTarget(age_hours);
         return(pnl >= target && pnl > 0.0);
        }
      else // BASKET_TP_POINTS
        {
         bool ok=false;
         ENUM_GRID_DIRECTION dir = BasketDirection(ok);
         if(!ok) return(false);

         //--- Break-even basis: a single side's average is only correct
         //    for a one-sided basket; a hedged basket must net both legs.
         double be = 0.0;
         bool have_sell = (m_om.WeightedAvgEntry(GRID_SELL) > 0.0);
         bool have_buy  = (m_om.WeightedAvgEntry(GRID_BUY)  > 0.0);
         if(have_buy && have_sell)
           {
            bool be_ok=false;
            be = m_om.NetBasketBreakEven(dir,be_ok);
            if(!be_ok) return(false);           // netted flat -> no points target
           }
         else
           {
            be = m_om.WeightedAvgEntry(dir);
           }
         if(be<=0.0) return(false);
         double point = SymbolInfoDouble(m_om.Symbol(),SYMBOL_POINT);
         if(point<=0.0) point=_Point;
         //--- decay the points distance the same way as the currency target
         double pts = m_tp_points * TimeDecayFactor(age_hours);
         double target_price = (dir==GRID_BUY ? be + pts*point
                                              : be - pts*point);
         double px = (dir==GRID_BUY ? mc.bid : mc.ask);
         bool reached = (dir==GRID_BUY ? px >= target_price : px <= target_price);
         //--- extra guard: only ever close while genuinely in profit.
         return(reached && pnl > 0.0);
        }
     }

   //--- Basket drawdown as a % of the stable account reference.
   double          BasketDrawdownPercent(void) const
     {
      if(m_om==NULL) return(0.0);
      double pnl = m_om.BasketFloatingPnL();
      if(pnl>=0.0) return(0.0);
      double ref = AccountReference();
      if(ref<=0.0) return(0.0);
      return(-pnl / ref * 100.0);
     }

   //================================================================//
   //  MANAGE : the per-tick basket decision (v2, ACTIVE).           //
   //                                                                //
   //  Priority order, and the reason for each position:              //
   //    1) GROUP TP        - bank the win first, always.             //
   //    2) TRAILING        - protect a win that is fading.           //
   //    3) BASKET STOP     - bound the loss before it becomes fatal.  //
   //    4) PARTIAL HARVEST - de-risk an aging / trend-trapped basket. //
   //    5) AVERAGING       - only if the REGIME still permits it.     //
   //    6) HEDGE           - optional, unchanged from v1.             //
   //    7) HOLD            - genuinely nothing useful to do.          //
   //================================================================//
   RecoveryDecision Manage(const MarketContext &mc,const RegimeContext &rc)
     {
      RecoveryDecision rd;
      rd.action = RECOVERY_NONE;
      rd.lot    = 0.0;
      rd.detail = "hold";
      rd.intent.valid       = false;
      rd.intent.direction   = GRID_BUY;
      rd.intent.price       = 0.0;
      rd.intent.is_seed     = false;
      rd.intent.level_index = 0;
      rd.intent.step_points = 0.0;
      rd.intent.reason      = "";

      if(m_om==NULL) return(rd);

      int count = m_om.CountBasketPositions();
      if(count<=0)
        {
         ResetBasketState();
         rd.detail = "no basket";
         return(rd);
        }

      double pnl        = m_om.BasketFloatingPnL();
      double age_hours  = m_om.BasketAgeHours();
      double decay      = TimeDecayFactor(age_hours);

      //--- Track the best PnL this basket has achieved (for trailing).
      if(pnl > m_peak_pnl)
         m_peak_pnl = pnl;

      //--- (1) GROUP TAKE-PROFIT (age-aware). Bank the win.
      if(GroupTargetReached(mc,age_hours))
        {
         if(m_om.CloseBasket())
           {
            ResetBasketState();
            rd.action = RECOVERY_CLOSED_IN_PROFIT;
            rd.detail = StringFormat("group TP reached (PnL=%.2f, age=%.1fh, decay=%.2f) -> closed IN PROFIT",
                                     pnl,age_hours,decay);
            LogInfo("RecoveryEngine: "+rd.detail);
           }
         else
           {
            rd.detail = "group TP reached but CloseBasket failed; will retry next tick";
            LogWarn("RecoveryEngine: "+rd.detail);
           }
         return(rd);
        }

      //--- (2) BASKET TRAILING. Once the basket has earned most of its
      //    (decayed) target, do not hand the gain back to the market.
      //
      //    Trailing is deliberately a CURRENCY-based feature: it needs an
      //    absolute profit reference to decide when a gain is "most of the
      //    target". EffectiveCurrencyTarget() supplies that in currency
      //    mode. In POINTS mode there is no currency target unless the user
      //    also sets BasketTPCurrency, so trailing stays OFF rather than
      //    arming against the peak itself - comparing the peak to a
      //    fraction of the peak is trivially true and would close healthy
      //    baskets at a few cents of profit.
      double trail_ref = EffectiveCurrencyTarget(age_hours);
      if(m_profile.trail_activate_fraction > 0.0 && trail_ref > 0.0 &&
         m_peak_pnl >= trail_ref * m_profile.trail_activate_fraction &&
         m_peak_pnl > 0.0)
        {
         double giveback_level = m_peak_pnl * (1.0 - m_profile.trail_giveback_fraction);
         if(pnl > 0.0 && pnl <= giveback_level)
           {
            if(m_om.CloseBasket())
              {
               ResetBasketState();
               rd.action = RECOVERY_CLOSED_TRAILED;
               rd.detail = StringFormat("basket trail: PnL %.2f fell to %.0f%% of peak %.2f -> closed IN PROFIT",
                                        pnl,(1.0-m_profile.trail_giveback_fraction)*100.0,m_peak_pnl);
               LogInfo("RecoveryEngine: "+rd.detail);
               return(rd);
              }
            LogWarn("RecoveryEngine: trail close failed; will retry next tick.");
           }
        }

      //--- (3) BASKET STOP. The bounded-loss backstop.
      //    THIS IS THE ONLY PATH IN THE EA THAT REALISES A LOSS, it fires
      //    only when explicitly enabled, and it caps the damage so the
      //    account survives to trade again. Disabling it restores the v1
      //    behaviour where a trend-trapped basket bleeds indefinitely.
      if(m_profile.enable_basket_stop && pnl < 0.0)
        {
         double dd_pct = BasketDrawdownPercent();
         if(dd_pct >= m_profile.basket_stop_loss_percent)
           {
            if(m_om.CloseBasket())
              {
               ResetBasketState();
               rd.action = RECOVERY_CLOSED_AT_STOP;
               rd.detail = StringFormat("BASKET STOP: loss %.2f (%.2f%% of balance) >= %.2f%% -> closed at a BOUNDED LOSS, starting fresh",
                                        pnl,dd_pct,m_profile.basket_stop_loss_percent);
               LogWarn("RecoveryEngine: "+rd.detail);
               return(rd);
              }
            LogWarn("RecoveryEngine: basket stop triggered but CloseBasket failed; will retry next tick.");
            rd.detail = "basket stop pending (close failed)";
            return(rd);
           }
        }

      //--- Determine the basket's recovery side + weighted-average entry.
      bool have_dir=false;
      ENUM_GRID_DIRECTION dir = BasketDirection(have_dir);
      if(!have_dir)
        {
         rd.detail = "basket side indeterminate; hold";
         return(rd);
        }
      double avg = m_om.WeightedAvgEntry(dir);

      //--- Ask the regime gate whether this basket may still grow.
      bool averaging_allowed = true;
      string regime_why = "regime filter disabled";
      if(m_regime!=NULL)
         averaging_allowed = m_regime.AllowAveraging(dir,rc,regime_why);

      //--- (4) PARTIAL HARVEST. Bank a profitable leg to realise cash and
      //    cut exposure. Deliberately restricted to situations where it
      //    actually helps: the basket must have something to trim, and
      //    must either be AGING or unable to average because the trend is
      //    against it. Harvesting worsens the remaining weighted average,
      //    so it is a survival-over-recovery trade - configurable, and
      //    never applied to a fresh healthy basket.
      if(m_profile.enable_partial_harvest && count >= 2)
        {
         bool aging = (age_hours >= m_profile.tp_decay_start_hours);
         bool trapped = !averaging_allowed;
         datetime bar = CurrentBarTime();
         bool bar_ok = (bar==0 || bar!=m_last_harvest_bar);
         if((aging || trapped) && bar_ok)
           {
            ulong  h_ticket=0;
            double h_profit=0.0, h_volume=0.0;
            if(m_om.MostProfitableLeg(m_profile.harvest_min_leg_profit_ccy,
                                      h_ticket,h_profit,h_volume))
              {
               if(m_om.ClosePosition(h_ticket))
                 {
                  m_last_harvest_bar = bar;
                  rd.action = RECOVERY_HARVESTED_LEG;
                  rd.detail = StringFormat("harvested leg #%I64u (+%.2f, %.2f lots) to cut exposure [%s, age=%.1fh]",
                                           h_ticket,h_profit,h_volume,
                                           (trapped?"trend-trapped":"aging"),age_hours);
                  LogInfo("RecoveryEngine: "+rd.detail);
                  return(rd);
                 }
               LogWarn("RecoveryEngine: harvest close failed; continuing.");
              }
           }
        }

      //--- (5) AVERAGING - now REGIME-GATED. This is the change that
      //    prevents the "kept averaging into a trend" blow-up.
      int side_level = m_om.CountSidePositions(dir);
      if(!averaging_allowed)
        {
         rd.detail = "averaging blocked by regime: "+regime_why;
         LogDbg("RecoveryEngine: "+rd.detail);
        }
      else if(m_grid!=NULL && m_lot!=NULL &&
              m_grid.PriceMovedOneStepAdverse(mc,dir,avg) &&
              AveragingSpacingOK(mc,dir))
        {
         GridIntent gi = m_grid.BuildNextLevelIntent(mc,dir,avg,side_level);
         if(gi.valid)
           {
            double lot = m_lot.RecoveryLot(mc,dir,side_level);
            if(lot>0.0)
              {
               rd.action = RECOVERY_ADD_AVERAGING;
               rd.intent = gi;
               rd.lot    = lot;
               rd.detail = StringFormat("averaging add proposed: %s %.2f lots @ %.2f (side level %d)",
                                        (dir==GRID_BUY?"BUY":"SELL"),lot,gi.price,side_level);
               StampAveragingAdd(gi.price);
               LogDbg("RecoveryEngine: "+rd.detail);
               return(rd);
              }
            rd.detail = "averaging wanted but lot bounded to 0 (exposure cap) -> hold";
            LogDbg("RecoveryEngine: "+rd.detail);
           }
         else
           {
            rd.detail = "averaging wanted but grid says no (max levels/ctx) -> hold";
            LogDbg("RecoveryEngine: "+rd.detail);
           }
        }

      //--- (6) OPTIONAL HEDGE (unchanged from v1): a one-time opposite-side
      //    add that caps further adverse bleed. Still just an INTENT.
      if(m_hedge_enabled && !m_hedged_flag && m_lot!=NULL)
        {
         double basket_dd = BasketDrawdownPercent();
         if(basket_dd >= m_hedge_trigger_dd_pct)
           {
            ENUM_GRID_DIRECTION hedge_dir = (dir==GRID_BUY ? GRID_SELL : GRID_BUY);
            int hedge_level = m_om.CountSidePositions(hedge_dir);
            double hedge_lot = m_lot.RecoveryLot(mc,hedge_dir,hedge_level);
            if(hedge_lot>0.0)
              {
               GridIntent hi;
               hi.valid       = true;
               hi.direction   = hedge_dir;
               hi.price       = (hedge_dir==GRID_BUY ? mc.ask : mc.bid);
               hi.is_seed     = false;
               hi.level_index = hedge_level;
               hi.step_points = 0.0;
               hi.reason      = "hedge";
               rd.action = RECOVERY_ADD_HEDGE;
               rd.intent = hi;
               rd.lot    = hedge_lot;
               rd.detail = StringFormat("hedge proposed: %s %.2f lots (basket DD %.1f%% >= %.1f%%)",
                                        (hedge_dir==GRID_BUY?"BUY":"SELL"),hedge_lot,
                                        basket_dd,m_hedge_trigger_dd_pct);
               LogInfo("RecoveryEngine: "+rd.detail);
               return(rd);
              }
           }
        }

      //--- (7) HOLD.
      return(rd);
     }

   //--- Call after the main EA successfully executes a hedge intent.
   void            MarkHedgePlaced(void) { m_hedged_flag=true; }

   //--- Diagnostics for the main EA log.
   double          PeakPnL(void) const { return(m_peak_pnl); }
  };

#endif // ADAPTIVEGRID_RECOVERYENGINE_MQH
//+------------------------------------------------------------------+
