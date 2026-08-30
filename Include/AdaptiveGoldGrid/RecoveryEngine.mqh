//+------------------------------------------------------------------+
//|                                                RecoveryEngine.mqh |
//|   Adaptive Gold Grid EA - Basket-first group recovery engine.     |
//+------------------------------------------------------------------+
//| =====================  BASKET-FIRST PHILOSOPHY  ================= |
//|                                                                  |
//|   This EA does NOT think in single trades. It thinks in BASKETS.  |
//|   A "basket" is every position sharing our magic + symbol. The     |
//|   whole basket is managed as ONE group with ONE goal:              |
//|                                                                  |
//|        Bring the ENTIRE group back to a NET PROFIT and only        |
//|        THEN close it - all at once, in profit.                     |
//|                                                                  |
//|   The trader who commissioned this system was explicit:            |
//|     * Do NOT cap the account with a "close everything at a loss"   |
//|       rule.                                                        |
//|     * When drawdown grows, MANAGE the basket (average / hedge)     |
//|       so it can recover, rather than realising the loss.           |
//|     * However deep the drawdown, the basket should close in        |
//|       PROFIT, never at a loss.                                     |
//|                                                                  |
//|   Therefore this engine contains ABSOLUTELY NO loss-realising      |
//|   close. There is no PositionClose-at-loss, no stop-out logic,     |
//|   no ExpertRemove. The ONLY close it ever issues is                |
//|   OrderManager.CloseBasket() and that fires EXCLUSIVELY when the    |
//|   basket's floating PnL has reached the group take-profit target   |
//|   (i.e. the group is already in profit).                           |
//|                                                                  |
//|   RISK CONTROL lives elsewhere and is ENTRY-SIDE ONLY:             |
//|     * SafetyValve gates whether a NEW averaging order may open.    |
//|     * LotSizer bounds every lot (per-order + total-basket caps).   |
//|     * GridEngine bounds grid depth (preset.max_grid_levels).       |
//|   When those gates say "no more room", the engine simply HOLDS      |
//|   and waits for the market to come back to the break-even target.  |
//|   Holding is a valid, deliberate state - not a bug.                |
//+------------------------------------------------------------------+
#ifndef ADAPTIVEGRID_RECOVERYENGINE_MQH
#define ADAPTIVEGRID_RECOVERYENGINE_MQH

#include "Config.mqh"
#include "Logger.mqh"
#include "OrderManager.mqh"
#include "SafetyValve.mqh"
#include "MarketAnalysis.mqh"
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
//| The engine NEVER acts itself except for the in-profit basket      |
//| close; all NEW-order actions are returned as intents for the      |
//| main EA to gate through the SafetyValve first.                    |
//+------------------------------------------------------------------+
enum ENUM_RECOVERY_ACTION
  {
   RECOVERY_NONE = 0,        // Nothing to do - hold and wait
   RECOVERY_CLOSED_IN_PROFIT,// Basket TP hit -> engine already closed it in profit
   RECOVERY_ADD_AVERAGING,   // Suggest adding an averaging position (see intent)
   RECOVERY_ADD_HEDGE        // Suggest opening an opposite-side hedge (see intent)
  };

//+------------------------------------------------------------------+
//| RecoveryDecision                                                 |
//+------------------------------------------------------------------+
struct RecoveryDecision
  {
   ENUM_RECOVERY_ACTION action;      // What the engine recommends
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
   COrderManager  *m_om;             // Basket queries + the profit-only close
   CSafetyValve   *m_sv;             // Entry gate (never closes anything)
   CGridEngine    *m_grid;           // Grid geometry / step logic
   CLotSizer      *m_lot;            // Bounded lot sizing
   CLogger        *m_log;            // Optional logger

   //--- Group take-profit configuration.
   ENUM_BASKET_TP_MODE m_tp_mode;    // currency or points-above-break-even
   double          m_tp_currency;    // target profit in account currency
   double          m_tp_points;      // target points beyond break-even
   double          m_tp_per_lot_ccy; // (currency mode) optional per-lot scaling add-on

   //--- Optional hedge strategy.
   bool            m_hedge_enabled;  // Master toggle for the hedge action
   double          m_hedge_trigger_dd_pct; // Basket DD% (vs equity) that arms a hedge
   bool            m_hedged_flag;    // Have we already placed the hedge for this basket?

   //--- ANTI-RESTACK THROTTLE (issue #3). Even though every add is
   //    bounded by the exposure + grid-depth caps, a fast/gapping adverse
   //    move could otherwise stack several averaging levels within a
   //    single bar before the weighted-average catches up. We space adds
   //    deterministically: the next averaging add must be at least one
   //    adaptive step beyond the LAST add's price AND on a new bar. This
   //    only throttles ENTRIES; it never forces a close and never blocks
   //    the profit-taking path.
   double          m_last_add_price; // price of the most recent averaging add (0 = none)
   datetime        m_last_add_bar;   // bar-open time of the most recent averaging add

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

      //--- Both sides present (hedged). Recovery side = the larger side.
      //    We compare volumes to pick the dominant exposure.
      double buy_vol=0.0, sell_vol=0.0;
      ulong tk[];
      int n=m_om.BasketTickets(tk);
      for(int i=0;i<n;i++)
        {
         if(!PositionSelectByTicket(tk[i])) continue;
         double v=PositionGetDouble(POSITION_VOLUME);
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY) buy_vol+=v;
         else sell_vol+=v;
        }
      ok=true;
      return(buy_vol>=sell_vol ? GRID_BUY : GRID_SELL);
     }

   //--- Bar-open time of the current bar (for the new-bar throttle).
   datetime        CurrentBarTime(void) const
     {
      if(m_om==NULL) return(0);
      datetime t[];
      if(CopyTime(m_om.Symbol(),PERIOD_CURRENT,0,1,t)==1)
         return(t[0]);
      return(0);
     }

   //--- ANTI-RESTACK guard: return true only when a new averaging add is
   //    allowed. The first add on a fresh basket is always allowed (no
   //    prior stamp). Subsequent adds require BOTH (a) a new bar since the
   //    last add and (b) price at least one adaptive step beyond the last
   //    add price, so adds are spaced by at least one step deterministically
   //    even in a fast move. This is purely an entry throttle.
   bool            AveragingSpacingOK(const MarketContext &mc,
                                      const ENUM_GRID_DIRECTION dir) const
     {
      if(m_last_add_price<=0.0) return(true);        // no prior add -> allow

      //--- (a) one add per bar at most
      datetime bar = CurrentBarTime();
      if(bar!=0 && bar==m_last_add_bar)
         return(false);

      //--- (b) at least one adaptive step beyond the last add price
      if(m_grid!=NULL)
        {
         double step_points = m_grid.AdaptiveStepPoints(mc);
         double point = SymbolInfoDouble(m_om.Symbol(),SYMBOL_POINT);
         if(point<=0.0) point=_Point;
         double step_price = step_points*point;
         double px = (dir==GRID_BUY ? mc.bid : mc.ask);
         if(dir==GRID_BUY)
           {
            if(px > m_last_add_price - step_price) return(false); // not a full step lower yet
           }
         else
           {
            if(px < m_last_add_price + step_price) return(false); // not a full step higher yet
           }
        }
      return(true);
     }

   //--- Record an averaging add so the throttle can space the next one.
   void            StampAveragingAdd(const double price)
     {
      m_last_add_price = price;
      m_last_add_bar   = CurrentBarTime();
     }

public:
                   CRecoveryEngine(void)
     {
      m_om                    = NULL;
      m_sv                    = NULL;
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
     }
                  ~CRecoveryEngine(void) {}

   //--- Initialise. Call once from OnInit. All engine pointers are
   //    required except the logger.
   void            Init(const PresetProfile &profile,
                        COrderManager *om,CSafetyValve *sv,
                        CGridEngine *grid,CLotSizer *lot,CLogger *logger=NULL)
     {
      m_profile = profile;
      m_om      = om;
      m_sv      = sv;
      m_grid    = grid;
      m_lot     = lot;
      m_log     = logger;
     }

   void            SetProfile(const PresetProfile &profile) { m_profile = profile; }

   //--- Group-TP configuration (called from OnInit with EA inputs).
   void            ConfigureTP(const ENUM_BASKET_TP_MODE mode,const double tp_currency,
                               const double tp_points,const double tp_per_lot_ccy=0.0)
     {
      m_tp_mode        = mode;
      m_tp_currency    = MathMax(0.0,tp_currency);
      m_tp_points      = MathMax(0.0,tp_points);
      m_tp_per_lot_ccy = MathMax(0.0,tp_per_lot_ccy);
     }

   //--- Hedge configuration.
   void            ConfigureHedge(const bool enabled,const double trigger_dd_pct)
     {
      m_hedge_enabled        = enabled;
      m_hedge_trigger_dd_pct = MathMax(0.0,trigger_dd_pct);
     }

   //--- Reset per-basket state (call when a basket has just closed).
   void            ResetBasketState(void)
     {
      m_hedged_flag    = false;
      m_last_add_price = 0.0;   // clear the anti-restack stamp for the next basket
      m_last_add_bar   = 0;
     }

   //================================================================//
   //  GROUP TAKE-PROFIT TARGET CHECK                                //
   //  Returns true when the basket's floating PnL is at/above the    //
   //  configured target. This is the ONLY condition under which the  //
   //  engine will ever issue a close - and by definition the basket  //
   //  is IN PROFIT when it fires.                                    //
   //================================================================//
   bool            GroupTargetReached(const MarketContext &mc) const
     {
      if(m_om==NULL) return(false);
      double pnl = m_om.BasketFloatingPnL();

      if(m_tp_mode==BASKET_TP_CURRENCY)
        {
         double target = m_tp_currency;
         if(m_tp_per_lot_ccy>0.0)
            target += m_tp_per_lot_ccy * m_om.BasketVolume();
         //--- profit-only by construction: target is a POSITIVE PnL.
         return(pnl >= target && pnl > 0.0);
        }
      else // BASKET_TP_POINTS
        {
         //--- price must be m_tp_points beyond break-even in our favour
         bool ok=false;
         ENUM_GRID_DIRECTION dir = BasketDirection(ok);
         if(!ok) return(false);

         //--- Break-even basis:
         //    * one-sided basket -> the side's weighted-average entry is
         //      the true break-even.
         //    * hedged basket (both legs open) -> a single side's average
         //      is NOT the break-even. Net both legs so the points target
         //      is measured from the real net-basket break-even. If the
         //      basket is netted flat (no meaningful net exposure), a
         //      points target is undefined, so we defer to the pnl>0 guard
         //      and simply do not fire in points mode (currency mode would
         //      handle a netted basket correctly). We never force a loss.
         double be = 0.0;
         bool have_sell = (m_om.WeightedAvgEntry(GRID_SELL) > 0.0);
         bool have_buy  = (m_om.WeightedAvgEntry(GRID_BUY)  > 0.0);
         if(have_buy && have_sell)
           {
            bool be_ok=false;
            be = m_om.NetBasketBreakEven(dir,be_ok);
            if(!be_ok) return(false);           // netted/flat -> no points target
           }
         else
           {
            be = m_om.WeightedAvgEntry(dir);    // one-sided: single-side avg is correct
           }
         if(be<=0.0) return(false);
         double point = SymbolInfoDouble(m_om.Symbol(),SYMBOL_POINT);
         if(point<=0.0) point=_Point;
         double target_price = (dir==GRID_BUY ? be + m_tp_points*point
                                              : be - m_tp_points*point);
         double px = (dir==GRID_BUY ? mc.bid : mc.ask);
         bool reached = (dir==GRID_BUY ? px >= target_price : px <= target_price);
         //--- extra guard: only ever close while genuinely in profit.
         return(reached && pnl > 0.0);
        }
     }

   //--- Basket drawdown as a % of equity (magnitude of adverse float).
   double          BasketDrawdownPercentOfEquity(void) const
     {
      if(m_om==NULL) return(0.0);
      double pnl = m_om.BasketFloatingPnL();
      if(pnl>=0.0) return(0.0);                      // in profit -> no DD
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      if(eq<=0.0) return(0.0);
      return(-pnl / eq * 100.0);
     }

   //================================================================//
   //  MANAGE : the per-tick basket decision.                        //
   //                                                                //
   //  Order of operations (profit first, then recovery):            //
   //    1) If the basket exists and the group TP is reached, close   //
   //       it IN PROFIT immediately (the only close we ever make).   //
   //    2) Otherwise, if price has moved one adaptive step adverse,  //
   //       propose an averaging add (bounded lot). The main EA must  //
   //       still gate it through the SafetyValve before sending.     //
   //    3) Optionally, if the hedge strategy is enabled and armed by  //
   //       basket drawdown, propose a one-time opposite-side hedge.   //
   //    4) If nothing applies, HOLD (RECOVERY_NONE). Holding lets a   //
   //       drawn-down basket wait for its recovery instead of ever    //
   //       realising a loss.                                          //
   //================================================================//
   RecoveryDecision Manage(const MarketContext &mc)
     {
      RecoveryDecision rd;
      rd.action = RECOVERY_NONE;
      rd.lot    = 0.0;
      rd.detail = "hold";
      //--- initialise the embedded intent to an inert state
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
         //--- no basket: nothing to recover. Reset any per-basket flags.
         ResetBasketState();
         rd.detail = "no basket";
         return(rd);
        }

      //--- (1) PROFIT FIRST: take the group profit if the target is hit.
      if(GroupTargetReached(mc))
        {
         double pnl = m_om.BasketFloatingPnL();
         bool ok = m_om.CloseBasket();          // closes the whole group IN PROFIT
         if(ok)
           {
            ResetBasketState();
            rd.action = RECOVERY_CLOSED_IN_PROFIT;
            rd.detail = StringFormat("group TP reached (PnL=%.2f) -> basket closed in profit",pnl);
            LogInfo("RecoveryEngine: "+rd.detail);
           }
         else
           {
            //--- close failed (transient). Do NOT force anything; retry next tick.
            rd.action = RECOVERY_NONE;
            rd.detail = "group TP reached but CloseBasket failed; will retry (holding, no loss taken)";
            LogWarn("RecoveryEngine: "+rd.detail);
           }
         return(rd);
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

      //--- LEVEL INDEX = positions on the RECOVERY SIDE only, NOT the
      //    total basket count. Using the total count would let an
      //    opposite-side hedge leg inflate the martingale exponent
      //    (base_lot * factor^level) and prematurely consume
      //    max_grid_levels. The grid depth and progression must reflect
      //    only how deep we are on the side we are actually averaging.
      int side_level = m_om.CountSidePositions(dir);

      //--- (2) AVERAGING: only when price is adverse by one adaptive step
      //    AND there is grid depth + exposure room. We DO NOT send here;
      //    we return an intent for the main EA to gate + execute.
      if(m_grid!=NULL && m_lot!=NULL &&
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
               //--- stamp this proposal so the anti-restack throttle spaces
               //    the next add by at least one adaptive step / bar. We
               //    stamp on PROPOSAL (the main EA gates+sends immediately
               //    after); worst case a blocked send simply delays the
               //    next add, which is safe (never forces a loss).
               StampAveragingAdd(gi.price);
               LogDbg("RecoveryEngine: "+rd.detail);
               return(rd);
              }
            else
              {
               //--- exposure/grid caps hit: HOLD, never force. This is the
               //    designed "out of room -> wait for recovery" state.
               rd.detail = "averaging wanted but lot bounded to 0 (exposure cap) -> hold";
               LogDbg("RecoveryEngine: "+rd.detail);
              }
           }
         else
           {
            rd.detail = "averaging wanted but grid says no (max levels/ctx) -> hold";
            LogDbg("RecoveryEngine: "+rd.detail);
           }
        }

      //--- (3) OPTIONAL HEDGE: a configurable, one-time opposite-side add
      //    that caps further adverse bleed while the primary side waits to
      //    recover. Still just an INTENT - the main EA gates + sends it.
      if(m_hedge_enabled && !m_hedged_flag && m_lot!=NULL)
        {
         double basket_dd = BasketDrawdownPercentOfEquity();
         if(basket_dd >= m_hedge_trigger_dd_pct)
           {
            ENUM_GRID_DIRECTION hedge_dir = (dir==GRID_BUY ? GRID_SELL : GRID_BUY);
            //--- The hedge leg is sized at the hedge SIDE's own level, not
            //    the total basket count, so an existing recovery side does
            //    not inflate the hedge's martingale exponent.
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

      //--- (4) Default: HOLD. No loss is ever realised here.
      return(rd);
     }

   //--- Call after the main EA successfully executes a hedge intent so
   //    we do not spam repeated hedges on the same basket.
   void            MarkHedgePlaced(void) { m_hedged_flag=true; }
  };

#endif // ADAPTIVEGRID_RECOVERYENGINE_MQH
//+------------------------------------------------------------------+
