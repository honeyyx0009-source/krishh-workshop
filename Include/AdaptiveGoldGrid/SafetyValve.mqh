//+------------------------------------------------------------------+
//|                                                  SafetyValve.mqh |
//|      Adaptive Gold Grid EA - Entry-blocking safety gate           |
//+------------------------------------------------------------------+
//| ===============  READ THIS BEFORE TOUCHING ANYTHING  =========== |
//|                                                                  |
//|   The SafetyValve is a GATE, not a KILL-SWITCH.                   |
//|                                                                  |
//|   It answers exactly ONE question each tick:                     |
//|       "Is it safe to open a NEW grid / recovery order right now?" |
//|                                                                  |
//|   NON-NEGOTIABLE SEMANTICS:                                       |
//|     * It NEVER closes a position.                                 |
//|     * It NEVER modifies an existing trade (no SL/TP moves here).  |
//|     * It NEVER halts the EA (no ExpertRemove, no account halt).   |
//|     * It NEVER realises a loss.                                   |
//|                                                                  |
//|   WHY: this is a grid + basket-recovery system. The recovery      |
//|   basket needs ROOM (free margin + surviving equity) to work its  |
//|   way back to profit. Force-closing at a loss or halting would    |
//|   defeat the entire recovery model and lock in the drawdown.      |
//|   So the ONLY protective action available here is to STOP ADDING  |
//|   new exposure until the account has breathing room again. That   |
//|   keeps the account alive so the existing basket can recover and  |
//|   close in profit.                                                |
//|                                                                  |
//|   There are deliberately NO OrderClose / PositionClose /          |
//|   ExpertRemove / TradeClose calls anywhere in this file.          |
//+------------------------------------------------------------------+
#ifndef ADAPTIVEGRID_SAFETYVALVE_MQH
#define ADAPTIVEGRID_SAFETYVALVE_MQH

#include "Config.mqh"
#include "Logger.mqh"
#include "OrderManager.mqh"

//+------------------------------------------------------------------+
//| Reason a new entry was blocked (for logging / diagnostics).      |
//+------------------------------------------------------------------+
enum ENUM_BLOCK_REASON
  {
   BLOCK_NONE = 0,           // Entry permitted
   BLOCK_MARGIN_LEVEL,       // ACCOUNT_MARGIN_LEVEL below floor
   BLOCK_FREE_MARGIN,        // ACCOUNT_MARGIN_FREE below minimum
   BLOCK_PROJECTED_MARGIN,   // Free margin AFTER next order would breach floor
   BLOCK_DRAWDOWN            // Equity drawdown circuit breaker tripped
  };

//+------------------------------------------------------------------+
//| Decision returned by CanOpenNew().                               |
//+------------------------------------------------------------------+
struct SafetyDecision
  {
   bool              allowed;      // true => a new order may be opened
   ENUM_BLOCK_REASON reason;       // why it was blocked (BLOCK_NONE if allowed)
   string            detail;       // human-readable explanation for the log
  };

//+------------------------------------------------------------------+
//| CSafetyValve                                                     |
//+------------------------------------------------------------------+
class CSafetyValve
  {
private:
   PresetProfile     m_profile;      // Active preset limits
   COrderManager    *m_om;           // For margin projection (may be NULL)
   CLogger          *m_log;          // Optional logger
   string            m_symbol;       // Symbol under management
   double            m_peak_equity;  // Highest equity seen (for drawdown %)

   void              LogWarn(const string m) { if(m_log!=NULL) m_log.Warn(m);  }
   void              LogDbg(const string m)  { if(m_log!=NULL) m_log.Debug(m); }

   //--- Reason -> text (diagnostics only).
   string            ReasonText(const ENUM_BLOCK_REASON r) const
     {
      switch(r)
        {
         case BLOCK_NONE:             return("OK");
         case BLOCK_MARGIN_LEVEL:     return("MARGIN_LEVEL_BELOW_FLOOR");
         case BLOCK_FREE_MARGIN:      return("FREE_MARGIN_BELOW_MIN");
         case BLOCK_PROJECTED_MARGIN: return("PROJECTED_MARGIN_BREACH");
         case BLOCK_DRAWDOWN:         return("DRAWDOWN_CIRCUIT_BREAKER");
         default:                     return("UNKNOWN");
        }
     }

public:
                     CSafetyValve(void)
     {
      m_om          = NULL;
      m_log         = NULL;
      m_symbol      = _Symbol;
      m_peak_equity = 0.0;
     }
                    ~CSafetyValve(void) {}

   //--- Initialise. Call once from OnInit.
   void              Init(const PresetProfile &profile,const string symbol,
                          COrderManager *om=NULL,CLogger *logger=NULL)
     {
      m_profile     = profile;
      m_symbol      = symbol;
      m_om          = om;
      m_log         = logger;
      m_peak_equity = AccountInfoDouble(ACCOUNT_EQUITY);
     }

   //--- Refresh limits if the preset is changed at runtime.
   void              SetProfile(const PresetProfile &profile) { m_profile = profile; }

   //================================================================//
   //  PEAK-EQUITY TRACKING (drawdown baseline)                      //
   //  Call every tick. Peak only ever ratchets UP.                  //
   //================================================================//
   void              UpdatePeakEquity(void)
     {
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      if(eq>m_peak_equity)
         m_peak_equity = eq;
     }

   //--- Current drawdown from the tracked peak, as a percentage.
   double            CurrentDrawdownPercent(void) const
     {
      if(m_peak_equity<=0.0)
         return(0.0);
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      double dd = (m_peak_equity - eq) / m_peak_equity * 100.0;
      return(dd>0.0 ? dd : 0.0);
     }

   double            PeakEquity(void) const { return(m_peak_equity); }

   //================================================================//
   //  CORE DECISION                                                 //
   //  Returns whether a NEW order may be opened. It NEVER acts on    //
   //  existing positions - it only permits or blocks new exposure.   //
   //                                                                //
   //  prospective_dir / prospective_lot describe the order the EA is //
   //  about to place, so we can project margin usage. Pass lot<=0 to //
   //  skip the projected-margin check (generic "can I trade?" query).//
   //================================================================//
   SafetyDecision    CanOpenNew(const ENUM_GRID_DIRECTION prospective_dir,
                                const double prospective_lot)
     {
      SafetyDecision d;
      d.allowed = true;
      d.reason  = BLOCK_NONE;
      d.detail  = "OK";

      //--- Always refresh the drawdown baseline first.
      UpdatePeakEquity();

      //--- (d) Drawdown circuit breaker: block NEW entries only.
      //    Existing basket is left untouched to recover.
      double dd = CurrentDrawdownPercent();
      if(dd >= m_profile.max_drawdown_percent)
        {
         d.allowed = false;
         d.reason  = BLOCK_DRAWDOWN;
         d.detail  = StringFormat("Drawdown %.2f%% >= cap %.2f%% : holding, NOT closing. No new entries.",
                                  dd,m_profile.max_drawdown_percent);
         LogWarn("SafetyValve blocks new entry: "+d.detail);
         return(d);
        }

      //--- (a) Margin level floor.
      double margin_level = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
      //    ACCOUNT_MARGIN_LEVEL is 0 when there are no open positions;
      //    with no positions there is no margin risk, so only enforce
      //    the floor when margin is actually in use.
      double used_margin = AccountInfoDouble(ACCOUNT_MARGIN);
      if(used_margin>0.0 && margin_level < m_profile.margin_level_floor_percent)
        {
         d.allowed = false;
         d.reason  = BLOCK_MARGIN_LEVEL;
         d.detail  = StringFormat("Margin level %.1f%% < floor %.1f%% : no new entries.",
                                  margin_level,m_profile.margin_level_floor_percent);
         LogWarn("SafetyValve blocks new entry: "+d.detail);
         return(d);
        }

      //--- (b) Absolute free-margin minimum.
      double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(free_margin < m_profile.min_free_margin_currency)
        {
         d.allowed = false;
         d.reason  = BLOCK_FREE_MARGIN;
         d.detail  = StringFormat("Free margin %.2f < min %.2f : no new entries.",
                                  free_margin,m_profile.min_free_margin_currency);
         LogWarn("SafetyValve blocks new entry: "+d.detail);
         return(d);
        }

      //--- (c) Projected margin after the intended next order.
      if(prospective_lot>0.0)
        {
         double need = 0.0;
         ENUM_ORDER_TYPE otype = (prospective_dir==GRID_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
         double price = (prospective_dir==GRID_BUY ? SymbolInfoDouble(m_symbol,SYMBOL_ASK)
                                                   : SymbolInfoDouble(m_symbol,SYMBOL_BID));
         if(OrderCalcMargin(otype,m_symbol,prospective_lot,price,need))
           {
            double free_after = free_margin - need;
            //--- must stay above the minimum free-margin buffer.
            if(free_after < m_profile.min_free_margin_currency)
              {
               d.allowed = false;
               d.reason  = BLOCK_PROJECTED_MARGIN;
               d.detail  = StringFormat("Projected free margin %.2f (need %.2f) < min %.2f : no new entries.",
                                        free_after,need,m_profile.min_free_margin_currency);
               LogWarn("SafetyValve blocks new entry: "+d.detail);
               return(d);
              }
           }
         else
           {
            //--- If we cannot compute margin, err on the side of caution
            //    and BLOCK the new entry (still never touches open trades).
            d.allowed = false;
            d.reason  = BLOCK_PROJECTED_MARGIN;
            d.detail  = "OrderCalcMargin failed : blocking new entry as a precaution.";
            LogWarn("SafetyValve blocks new entry: "+d.detail);
            return(d);
           }
        }

      LogDbg("SafetyValve: new entry permitted.");
      return(d);
     }

   //--- Lightweight helper: is there margin room for a specific lot?
   //    Thin wrapper over the projected-margin logic; returns bool.
   //    Like CanOpenNew, this ONLY reports - it takes no action.
   bool              HasMarginRoomFor(const ENUM_GRID_DIRECTION dir,const double lot)
     {
      SafetyDecision d = CanOpenNew(dir,lot);
      return(d.allowed);
     }
  };

#endif // ADAPTIVEGRID_SAFETYVALVE_MQH
//+------------------------------------------------------------------+
