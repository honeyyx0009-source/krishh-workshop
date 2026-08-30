//+------------------------------------------------------------------+
//|                                                     LotSizer.mqh |
//|   Adaptive Gold Grid EA - Adaptive + progressive (bounded         |
//|   martingale) lot sizing.                                         |
//+------------------------------------------------------------------+
//| PURPOSE                                                          |
//|   Turns "how much risk / how deep in the grid am I?" into a       |
//|   broker-legal lot size. Two jobs:                                |
//|                                                                  |
//|   1) SEED LOT (first order): start from preset.base_lot but scale |
//|      it by preset.risk_percent_per_trade against current equity   |
//|      and the ATR-based stop distance, so the risk-per-seed is     |
//|      proportional to account size and current volatility.         |
//|                                                                  |
//|   2) RECOVERY LOT (deeper levels): apply preset.lot_progression_  |
//|      factor per level (a martingale-style ramp), gently nudged by |
//|      market-condition confidence from MarketContext.              |
//|                                                                  |
//| BOUNDED MARTINGALE BY DESIGN (READ THIS)                         |
//|   Progressive sizing is dangerous if unbounded. EVERY lot this    |
//|   class returns passes through THREE hard limits before it is     |
//|   handed back:                                                    |
//|     (a) clamp to preset.max_lot_cap        (per-order ceiling)    |
//|     (b) clamp so BasketVolume + lot <= preset.max_basket_exposure |
//|         _lots                               (total-exposure ceiling)|
//|     (c) COrderManager.NormalizeLot(...)     (broker min/max/step)  |
//|   There is no code path that returns an un-clamped, un-normalised |
//|   volume. This is a deliberately CAPPED progression, never a      |
//|   blind double-until-broke martingale.                            |
//+------------------------------------------------------------------+
#ifndef ADAPTIVEGRID_LOTSIZER_MQH
#define ADAPTIVEGRID_LOTSIZER_MQH

#include "Config.mqh"
#include "Logger.mqh"
#include "OrderManager.mqh"
#include "MarketAnalysis.mqh"

//+------------------------------------------------------------------+
//| CLotSizer                                                        |
//+------------------------------------------------------------------+
class CLotSizer
  {
private:
   PresetProfile   m_profile;        // Active preset (all sizing limits)
   COrderManager  *m_om;             // For NormalizeLot + BasketVolume (required)
   CLogger        *m_log;            // Optional logger
   string          m_symbol;         // Symbol
   double          m_atr_stop_mult;  // ATR multiple used as the notional stop distance

   void            LogWarn(const string m) { if(m_log!=NULL) m_log.Warn(m); }
   void            LogDbg(const string m)  { if(m_log!=NULL) m_log.Debug(m); }

   //================================================================//
   //  THE THREE HARD LIMITS - applied to every returned lot.        //
   //================================================================//
   double          ApplyBounds(const double desired) const
     {
      double lot = desired;

      //--- (a) per-order hard cap
      if(lot > m_profile.max_lot_cap)
         lot = m_profile.max_lot_cap;

      //--- (b) total-basket exposure cap: never let basket exceed limit
      double room = m_profile.max_basket_exposure_lots;
      if(m_om!=NULL)
         room -= m_om.BasketVolume();
      if(room <= 0.0)
        {
         //--- no exposure room left: signal "cannot add" via 0.0
         return(0.0);
        }
      if(lot > room)
         lot = room;

      //--- (c) broker normalisation (min/max/step). Always last.
      //    NormalizeLot rounds UP to the broker volume minimum. If the
      //    remaining exposure room is a fraction below vmin, normalising
      //    would return a lot slightly ABOVE max_basket_exposure_lots and
      //    breach the cap. To keep the total-exposure ceiling strict, we
      //    treat "room < broker vmin" as "cannot add" (return 0) instead
      //    of normalising above the cap. Holding here is the designed
      //    out-of-room state; it never realises a loss.
      if(m_om!=NULL)
        {
         double vmin = SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MIN);
         if(vmin>0.0 && room < vmin)
            return(0.0);
         lot = m_om.NormalizeLot(lot);
        }

      return(lot);
     }

public:
                   CLotSizer(void)
     {
      m_om            = NULL;
      m_log           = NULL;
      m_symbol        = _Symbol;
      m_atr_stop_mult = 1.5;   // notional stop = 1.5 * ATR by default
     }
                  ~CLotSizer(void) {}

   //--- Initialise. Call once from OnInit. OrderManager is required
   //    for normalisation + basket-exposure bounding.
   void            Init(const PresetProfile &profile,const string symbol,
                        COrderManager *om,CLogger *logger=NULL,
                        const double atr_stop_mult=1.5)
     {
      m_profile       = profile;
      m_symbol        = symbol;
      m_om            = om;
      m_log           = logger;
      m_atr_stop_mult = MathMax(0.1,atr_stop_mult);
     }

   void            SetProfile(const PresetProfile &profile) { m_profile = profile; }

   //================================================================//
   //  SEED LOT                                                      //
   //  risk_currency = equity * risk_percent_per_trade / 100         //
   //  stop_distance = ATR * m_atr_stop_mult (price units)           //
   //  loss for 1 lot over stop_distance = stop_pts * tick_value     //
   //  lot_by_risk  = risk_currency / (loss for 1 lot)               //
   //  We start from base_lot and take the RISK-scaled value, then    //
   //  bound it. Falls back to base_lot when tick data is missing.    //
   //================================================================//
   double          SeedLot(const MarketContext &mc)
     {
      double lot = m_profile.base_lot;

      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double risk_ccy = equity * m_profile.risk_percent_per_trade / 100.0;

      double point      = SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      //--- BROKER-CONTRACT ASSUMPTION (verify during backtest):
      //    The risk-per-lot below is derived from SYMBOL_TRADE_TICK_VALUE
      //    and SYMBOL_TRADE_TICK_SIZE. For gold (XAUUSD) these vary by
      //    broker/feed: some quote tick value per-ounce, others per
      //    100-oz contract, and account-currency conversion may apply.
      //    If your broker's contract size differs from what the terminal
      //    reports here, the ATR-stop notional may not match the intended
      //    risk_percent_per_trade. ALWAYS verify the seed lot against your
      //    broker's contract specs in the Strategy Tester before going
      //    live. The guard below (tick_value>0 && tick_size>0) defensively
      //    falls back to base_lot when the terminal returns zero/invalid
      //    tick data, so we never divide by zero or size on garbage.
      double tick_value = SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_VALUE);
      double tick_size  = SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_SIZE);
      if(point<=0.0) point=_Point;

      if(mc.ready && mc.atr_value>0.0 && tick_value>0.0 && tick_size>0.0 && risk_ccy>0.0)
        {
         double stop_distance = mc.atr_value * m_atr_stop_mult;         // price units
         //--- money lost per 1.0 lot if price travels the stop distance
         double loss_per_lot = (stop_distance / tick_size) * tick_value;
         if(loss_per_lot > 0.0)
           {
            double lot_by_risk = risk_ccy / loss_per_lot;
            //--- use the risk-derived lot as the seed target
            lot = lot_by_risk;
           }
        }
      else
        {
         LogDbg("LotSizer.SeedLot: falling back to base_lot (missing ATR/tick data).");
        }

      //--- never seed below the preset base lot
      if(lot < m_profile.base_lot)
         lot = m_profile.base_lot;

      double bounded = ApplyBounds(lot);
      LogDbg(StringFormat("LotSizer.SeedLot: raw=%.3f -> bounded=%.3f (base=%.3f risk%%=%.2f)",
                          lot,bounded,m_profile.base_lot,m_profile.risk_percent_per_trade));
      return(bounded);
     }

   //================================================================//
   //  RECOVERY LOT (progressive)                                    //
   //  base_for_level = base_lot * progression_factor ^ level        //
   //  A small confidence nudge (from MarketContext momentum aligned  //
   //  with the basket side) scales the aggression WITHIN bounds:     //
   //  more confidence -> up to +25%, less -> down to -25%. Always     //
   //  clamped afterwards, so the nudge can never breach the caps.    //
   //================================================================//
   double          RecoveryLot(const MarketContext &mc,
                               const ENUM_GRID_DIRECTION basket_dir,
                               const int level_index)
     {
      int lvl = (level_index<0 ? 0 : level_index);

      //--- progression ramp: base * factor^level
      double factor = m_profile.lot_progression_factor;
      if(factor < 1.0) factor = 1.0;   // never shrink below flat
      double raw = m_profile.base_lot * MathPow(factor,(double)lvl);

      //--- confidence nudge (bounded to +/-25%)
      double conf = 0.0;
      if(mc.ready)
        {
         //--- momentum aligned WITH the recovery side raises confidence.
         double aligned = (basket_dir==GRID_BUY ? mc.momentum_score : -mc.momentum_score);
         conf = aligned;                       // -1..+1
         if(conf >  1.0) conf =  1.0;
         if(conf < -1.0) conf = -1.0;
        }
      double nudge = 1.0 + 0.25*conf;          // 0.75 .. 1.25
      raw *= nudge;

      double bounded = ApplyBounds(raw);
      LogDbg(StringFormat("LotSizer.RecoveryLot: lvl=%d raw=%.3f nudge=%.2f -> bounded=%.3f (cap=%.2f)",
                          lvl,raw,nudge,bounded,m_profile.max_lot_cap));
      return(bounded);
     }

   //--- How much basket-exposure room is left (lots). >0 means we can
   //    still add. Handy for callers to short-circuit before sizing.
   double          RemainingExposureLots(void) const
     {
      double room = m_profile.max_basket_exposure_lots;
      if(m_om!=NULL)
         room -= m_om.BasketVolume();
      return(room > 0.0 ? room : 0.0);
     }
  };

#endif // ADAPTIVEGRID_LOTSIZER_MQH
//+------------------------------------------------------------------+
