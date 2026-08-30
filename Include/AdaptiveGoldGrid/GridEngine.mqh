//+------------------------------------------------------------------+
//|                                                   GridEngine.mqh |
//|   Adaptive Gold Grid EA - ATR-driven adaptive grid level engine.  |
//+------------------------------------------------------------------+
//| PURPOSE                                                          |
//|   Decides WHERE and IN WHICH DIRECTION the next grid order should |
//|   sit. It is a PURE DECISION module:                              |
//|     * It NEVER sends, modifies or closes an order.                |
//|     * It returns a GridIntent (price + direction + validity)      |
//|       which the main EA routes through SafetyValve + OrderManager.|
//|                                                                  |
//| ADAPTIVE SPACING (core idea)                                     |
//|   The base grid step is:                                          |
//|       step_points = ATR_points * preset.atr_spacing_multiplier    |
//|   then it ADAPTS to the volatility regime from MarketContext:     |
//|     * VOL_HIGH  -> WIDEN the step (avoid stacking in a fast move)  |
//|     * VOL_CALM  -> TIGHTEN the step (levels fill in quiet ranges)  |
//|     * VOL_NORMAL-> leave as-is                                     |
//|   Spacing is therefore never hardcoded; it breathes with the      |
//|   market. All spacing ultimately derives from the preset.         |
//|                                                                  |
//| SEED DIRECTION                                                   |
//|   With no basket open, the seed direction is chosen from the      |
//|   consolidated MarketContext (trend + momentum). This is the      |
//|   institutional-style "trade with structure" bias, not a coin     |
//|   flip. Once a basket exists, the grid keeps adding on the        |
//|   SAME side (the recovery/averaging side) - the RecoveryEngine    |
//|   owns that decision; GridEngine just provides the geometry.      |
//+------------------------------------------------------------------+
#ifndef ADAPTIVEGRID_GRIDENGINE_MQH
#define ADAPTIVEGRID_GRIDENGINE_MQH

#include "Config.mqh"
#include "Logger.mqh"
#include "OrderManager.mqh"
#include "MarketAnalysis.mqh"

//+------------------------------------------------------------------+
//| GridIntent                                                       |
//|   A proposed next order. NOT an executed order - the main EA      |
//|   must still gate it through the SafetyValve before sending.      |
//+------------------------------------------------------------------+
struct GridIntent
  {
   bool                valid;        // false => no actionable intent this tick
   ENUM_GRID_DIRECTION direction;    // BUY or SELL
   double              price;        // Suggested entry price (market ref or aligned level)
   bool                is_seed;      // true => first order of a fresh basket
   int                 level_index;  // 0-based grid level this intent represents
   double              step_points;  // Adaptive spacing used (points) for logging
   string              reason;       // Human-readable rationale for the log
  };

//+------------------------------------------------------------------+
//| CGridEngine                                                      |
//+------------------------------------------------------------------+
class CGridEngine
  {
private:
   PresetProfile   m_profile;        // Active preset (source of all limits)
   CLogger        *m_log;            // Optional logger
   string          m_symbol;         // Symbol
   double          m_min_step_points;// Absolute floor so spacing never collapses to 0
   double          m_sr_align_tol;   // Fraction of step within which we snap to S/R

   void            LogInfo(const string m) { if(m_log!=NULL) m_log.Info(m); }
   void            LogDbg(const string m)  { if(m_log!=NULL) m_log.Debug(m); }

public:
                   CGridEngine(void)
     {
      m_log             = NULL;
      m_symbol          = _Symbol;
      m_min_step_points = 50.0;   // conservative floor; refined in Init
      m_sr_align_tol    = 0.35;   // snap to S/R if within 35% of a step
     }
                  ~CGridEngine(void) {}

   //--- Initialise. Call once from OnInit.
   void            Init(const PresetProfile &profile,const string symbol,CLogger *logger=NULL,
                        const double min_step_points=50.0,const double sr_align_tol=0.35)
     {
      m_profile         = profile;
      m_symbol          = symbol;
      m_log             = logger;
      m_min_step_points = MathMax(1.0,min_step_points);
      m_sr_align_tol    = MathMax(0.0,sr_align_tol);
     }

   void            SetProfile(const PresetProfile &profile) { m_profile = profile; }

   //================================================================//
   //  ADAPTIVE STEP                                                 //
   //  step = ATR_points * atr_spacing_multiplier, then widened /     //
   //  tightened by the volatility regime, floored at m_min_step.     //
   //================================================================//
   double          AdaptiveStepPoints(const MarketContext &mc) const
     {
      double step = mc.atr_points * m_profile.atr_spacing_multiplier;

      switch(mc.vol_regime)
        {
         case VOL_HIGH:   step *= 1.35; break;   // widen in fast markets
         case VOL_CALM:   step *= 0.75; break;   // tighten in quiet markets
         case VOL_NORMAL:
         default:         /* unchanged */        break;
        }

      if(step < m_min_step_points)
         step = m_min_step_points;
      return(step);
     }

   //================================================================//
   //  SEED DIRECTION from MarketContext.                            //
   //  Trend leads; momentum breaks ties. Returns false via `ok` when //
   //  there is no clean bias (caller should wait rather than force). //
   //================================================================//
   ENUM_GRID_DIRECTION SeedDirection(const MarketContext &mc,bool &ok) const
     {
      ok = true;
      if(mc.trend==TREND_UP)   return(GRID_BUY);
      if(mc.trend==TREND_DOWN) return(GRID_SELL);

      //--- flat trend: fall back to momentum sign if it is decisive
      if(mc.momentum_score >=  0.30) return(GRID_BUY);
      if(mc.momentum_score <= -0.30) return(GRID_SELL);

      ok = false;              // no decisive bias -> do not seed
      return(GRID_BUY);
     }

   //================================================================//
   //  Optional S/R alignment.                                       //
   //  If the raw target sits within tolerance of a swing level,      //
   //  snap to that level so the grid respects real structure.        //
   //================================================================//
   double          AlignToStructure(const double raw_price,const ENUM_GRID_DIRECTION dir,
                                    const MarketContext &mc,const double step_points) const
     {
      double point = SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      if(point<=0.0) point=_Point;
      double tol = step_points * m_sr_align_tol * point;
      if(tol<=0.0) return(raw_price);

      //--- BUY levels sit below price -> prefer aligning to support.
      if(dir==GRID_BUY && mc.support>0.0)
        {
         if(MathAbs(raw_price - mc.support) <= tol)
            return(mc.support);
        }
      //--- SELL levels sit above price -> prefer aligning to resistance.
      if(dir==GRID_SELL && mc.resistance>0.0)
        {
         if(MathAbs(raw_price - mc.resistance) <= tol)
            return(mc.resistance);
        }
      return(raw_price);
     }

   //================================================================//
   //  SEED INTENT : first order of a fresh basket.                  //
   //  Direction from MarketContext; price is the current market      //
   //  reference (market order). level_index = 0.                     //
   //================================================================//
   GridIntent      BuildSeedIntent(const MarketContext &mc)
     {
      GridIntent gi;
      gi.valid       = false;
      gi.direction   = GRID_BUY;
      gi.price       = 0.0;
      gi.is_seed     = true;
      gi.level_index = 0;
      gi.step_points = 0.0;
      gi.reason      = "";

      if(!mc.ready)
        {
         gi.reason = "market context not ready";
         return(gi);
        }

      bool ok=false;
      ENUM_GRID_DIRECTION dir = SeedDirection(mc,ok);
      if(!ok)
        {
         gi.reason = "no decisive trend/momentum bias -> wait";
         LogDbg("GridEngine: seed skipped, "+gi.reason);
         return(gi);
        }

      gi.direction   = dir;
      gi.price       = (dir==GRID_BUY ? mc.ask : mc.bid);
      gi.step_points = AdaptiveStepPoints(mc);
      gi.valid       = true;
      gi.reason      = StringFormat("seed %s from trend=%d mom=%.2f step=%.0fpts",
                                    (dir==GRID_BUY?"BUY":"SELL"),(int)mc.trend,
                                    mc.momentum_score,gi.step_points);
      LogInfo("GridEngine: "+gi.reason);
      return(gi);
     }

   //================================================================//
   //  NEXT GRID INTENT : an averaging level added to an open basket. //
   //  `basket_dir`      = the side the basket is recovering on.      //
   //  `avg_entry`       = weighted-average entry of that side.       //
   //  `current_levels`  = how many positions already in the basket.  //
   //                                                                //
   //  The averaging level is placed ONE adaptive step ADVERSE to the //
   //  weighted-average entry (buys average down, sells average up).  //
   //  Enforces preset.max_grid_levels: beyond that, returns invalid. //
   //================================================================//
   GridIntent      BuildNextLevelIntent(const MarketContext &mc,
                                        const ENUM_GRID_DIRECTION basket_dir,
                                        const double avg_entry,
                                        const int current_levels)
     {
      GridIntent gi;
      gi.valid       = false;
      gi.direction   = basket_dir;
      gi.price       = 0.0;
      gi.is_seed     = false;
      gi.level_index = current_levels;
      gi.step_points = 0.0;
      gi.reason      = "";

      if(!mc.ready)
        {
         gi.reason = "market context not ready";
         return(gi);
        }

      //--- Enforce the hard preset ceiling on grid depth.
      if(current_levels >= m_profile.max_grid_levels)
        {
         gi.reason = StringFormat("max_grid_levels reached (%d) -> no new level",
                                  m_profile.max_grid_levels);
         LogDbg("GridEngine: "+gi.reason);
         return(gi);
        }

      double step_points = AdaptiveStepPoints(mc);
      double point = SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      if(point<=0.0) point=_Point;
      double step_price = step_points * point;

      //--- Place the next level one full step ADVERSE to the avg entry.
      double base = (avg_entry>0.0 ? avg_entry
                                   : (basket_dir==GRID_BUY ? mc.ask : mc.bid));
      double raw_price = (basket_dir==GRID_BUY ? base - step_price
                                               : base + step_price);

      //--- Snap to structure where it makes sense.
      double aligned = AlignToStructure(raw_price,basket_dir,mc,step_points);

      gi.direction   = basket_dir;
      gi.price       = aligned;
      gi.step_points = step_points;
      gi.valid       = true;
      gi.reason      = StringFormat("level %d %s @ %.2f (avg %.2f, step %.0fpts, vol=%d)",
                                    current_levels,(basket_dir==GRID_BUY?"BUY":"SELL"),
                                    aligned,avg_entry,step_points,(int)mc.vol_regime);
      LogDbg("GridEngine: "+gi.reason);
      return(gi);
     }

   //--- Convenience: has the market moved adverse by at least one
   //    adaptive step from the weighted-average entry? Used by the
   //    RecoveryEngine to decide when to trigger the next level.
   bool            PriceMovedOneStepAdverse(const MarketContext &mc,
                                            const ENUM_GRID_DIRECTION basket_dir,
                                            const double avg_entry) const
     {
      if(!mc.ready || avg_entry<=0.0) return(false);
      double step_points = AdaptiveStepPoints(mc);
      double point = SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      if(point<=0.0) point=_Point;
      double step_price = step_points * point;

      if(basket_dir==GRID_BUY)
         return(mc.bid <= avg_entry - step_price);   // price fell one step
      else
         return(mc.ask >= avg_entry + step_price);   // price rose one step
     }
  };

#endif // ADAPTIVEGRID_GRIDENGINE_MQH
//+------------------------------------------------------------------+
