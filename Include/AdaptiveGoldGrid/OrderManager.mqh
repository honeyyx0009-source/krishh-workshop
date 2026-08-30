//+------------------------------------------------------------------+
//|                                                 OrderManager.mqh |
//|      Adaptive Gold Grid EA - Defensive order & basket manager     |
//+------------------------------------------------------------------+
//| PURPOSE                                                          |
//|   Thin, defensive wrapper around CTrade. Owns:                    |
//|     (a) broker-correct lot normalisation,                         |
//|     (b) defensive market / pending order helpers with magic-      |
//|         number stamping, retcode inspection, and retry on         |
//|         transient errors,                                         |
//|     (c) basket queries filtered by (magic + symbol) so the        |
//|         recovery logic can treat all EA positions as one group,   |
//|     (d) profit-taking close helpers.                              |
//|                                                                  |
//|   v2 IMPORTANT - CLOSE SEMANTICS CHANGED:                         |
//|   The close helpers here are pure MECHANISM: they close whatever   |
//|   they are told to close, at whatever the current PnL happens to   |
//|   be. They enforce no policy of their own.                        |
//|   ALL close POLICY lives in RecoveryEngine.mqh, which calls them   |
//|   from exactly four gated places: group take-profit (in profit),   |
//|   basket trailing (in profit), the opt-in basket stop (bounded     |
//|   loss), and harvesting a single profitable leg.                   |
//|   The SafetyValve still never closes anything at all.             |
//+------------------------------------------------------------------+
#ifndef ADAPTIVEGRID_ORDERMANAGER_MQH
#define ADAPTIVEGRID_ORDERMANAGER_MQH

#include <Trade/Trade.mqh>
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Trade direction helper enum.                                     |
//+------------------------------------------------------------------+
enum ENUM_GRID_DIRECTION
  {
   GRID_BUY,
   GRID_SELL
  };

//+------------------------------------------------------------------+
//| COrderManager                                                    |
//+------------------------------------------------------------------+
class COrderManager
  {
private:
   CTrade            m_trade;         // Underlying MT5 trade wrapper
   CLogger          *m_log;           // Optional logger (may be NULL)
   string            m_symbol;        // Symbol this manager operates on
   long              m_magic;         // Magic number isolating this EA's positions
   int               m_max_retries;   // Retry attempts on transient send errors
   int               m_retry_sleep_ms;// Sleep between retries (ms)

   //--- Is the given retcode a transient error worth retrying?
   bool              IsTransient(const uint retcode) const
     {
      switch(retcode)
        {
         case TRADE_RETCODE_REQUOTE:
         case TRADE_RETCODE_PRICE_OFF:
         case TRADE_RETCODE_PRICE_CHANGED:
         case TRADE_RETCODE_REJECT:
         case TRADE_RETCODE_TIMEOUT:
         case TRADE_RETCODE_CONNECTION:
         case TRADE_RETCODE_TOO_MANY_REQUESTS:
            return(true);
         default:
            return(false);
        }
     }

   void              LogErr(const string m)  { if(m_log!=NULL) m_log.Error(m); }
   void              LogWarn(const string m) { if(m_log!=NULL) m_log.Warn(m);  }
   void              LogInfo(const string m) { if(m_log!=NULL) m_log.Info(m);  }
   void              LogDbg(const string m)  { if(m_log!=NULL) m_log.Debug(m); }

public:
                     COrderManager(void)
     {
      m_log            = NULL;
      m_symbol         = _Symbol;
      m_magic          = 0;
      m_max_retries    = 3;
      m_retry_sleep_ms = 300;
     }
                    ~COrderManager(void) {}

   //--- Initialise. Call once from OnInit.
   void              Init(const string symbol,const long magic,CLogger *logger=NULL,
                          const int max_retries=3,const int retry_sleep_ms=300)
     {
      m_symbol         = symbol;
      m_magic          = magic;
      m_log            = logger;
      m_max_retries    = MathMax(1,max_retries);
      m_retry_sleep_ms = MathMax(0,retry_sleep_ms);
      m_trade.SetExpertMagicNumber(magic);
      m_trade.SetTypeFillingBySymbol(symbol);
      m_trade.SetMarginMode();
     }

   long              Magic(void) const  { return(m_magic); }
   string            Symbol(void) const { return(m_symbol); }

   //================================================================//
   //  (a) LOT NORMALISATION                                         //
   //================================================================//
   //--- Clamp to broker min/max and round DOWN to the volume step so
   //    we never submit an illegal volume.
   double            NormalizeLot(const double volume) const
     {
      double vmin  = SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MIN);
      double vmax  = SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MAX);
      double vstep = SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_STEP);
      if(vstep<=0.0) vstep = 0.01;   // defensive default

      double v = volume;
      if(v<vmin) v = vmin;
      if(v>vmax) v = vmax;

      //--- snap to step
      double steps = MathFloor((v - vmin)/vstep + 0.0000001);
      v = vmin + steps*vstep;

      //--- guard against rounding drift past the limits
      if(v<vmin) v = vmin;
      if(v>vmax) v = vmax;

      //--- normalise decimals to the step precision
      int digits = 0;
      double s = vstep;
      while(s<1.0 && digits<8) { s*=10.0; digits++; }
      return(NormalizeDouble(v,digits));
     }

   //================================================================//
   //  FREE-MARGIN CHECK (used before every send)                    //
   //================================================================//
   //--- Return true if the account has enough free margin to open
   //    `volume` in `dir`. Uses OrderCalcMargin.
   bool              HasMarginFor(const ENUM_GRID_DIRECTION dir,const double volume) const
     {
      ENUM_ORDER_TYPE otype = (dir==GRID_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
      double price = (dir==GRID_BUY ? SymbolInfoDouble(m_symbol,SYMBOL_ASK)
                                    : SymbolInfoDouble(m_symbol,SYMBOL_BID));
      double need  = 0.0;
      if(!OrderCalcMargin(otype,m_symbol,volume,price,need))
         return(false);            // could not compute -> treat as unsafe
      double freem = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      return(freem >= need);
     }

   //================================================================//
   //  (b) DEFENSIVE ORDER HELPERS                                   //
   //================================================================//
   //--- Open a market order with retries on transient errors.
   bool              OpenMarket(const ENUM_GRID_DIRECTION dir,const double lot,
                                const string comment="")
     {
      double vol = NormalizeLot(lot);
      if(vol<=0.0)
        {
         LogErr("OpenMarket: normalised volume <= 0, aborting.");
         return(false);
        }
      if(!HasMarginFor(dir,vol))
        {
         LogWarn("OpenMarket: insufficient free margin for "+DoubleToString(vol,2)+" lots, aborting.");
         return(false);
        }

      for(int attempt=1; attempt<=m_max_retries; attempt++)
        {
         if(!IsTradeContextFree())
           {
            Sleep(m_retry_sleep_ms);
            continue;
           }
         bool ok = (dir==GRID_BUY)
                   ? m_trade.Buy(vol,m_symbol,0.0,0.0,0.0,comment)
                   : m_trade.Sell(vol,m_symbol,0.0,0.0,0.0,comment);
         uint rc = m_trade.ResultRetcode();
         if(ok && (rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_PLACED))
           {
            LogInfo(StringFormat("OpenMarket %s %.2f lots ok (ticket=%I64u)",
                                 (dir==GRID_BUY?"BUY":"SELL"),vol,m_trade.ResultOrder()));
            return(true);
           }
         if(!IsTransient(rc))
           {
            LogErr(StringFormat("OpenMarket failed permanently rc=%u (%s)",rc,m_trade.ResultRetcodeDescription()));
            return(false);
           }
         LogWarn(StringFormat("OpenMarket transient rc=%u attempt %d/%d, retrying...",rc,attempt,m_max_retries));
         Sleep(m_retry_sleep_ms);
        }
      LogErr("OpenMarket: exhausted retries.");
      return(false);
     }

   //--- Place a pending order (limit or stop). type_price is the
   //    trigger price; validity is left to broker/EA policy.
   bool              OpenPending(const ENUM_ORDER_TYPE order_type,const double lot,
                                 const double price,const string comment="")
     {
      double vol = NormalizeLot(lot);
      if(vol<=0.0)
        {
         LogErr("OpenPending: normalised volume <= 0, aborting.");
         return(false);
        }
      for(int attempt=1; attempt<=m_max_retries; attempt++)
        {
         if(!IsTradeContextFree())
           {
            Sleep(m_retry_sleep_ms);
            continue;
           }
         bool ok=false;
         switch(order_type)
           {
            case ORDER_TYPE_BUY_LIMIT:  ok=m_trade.BuyLimit(vol,price,m_symbol,0,0,ORDER_TIME_GTC,0,comment);  break;
            case ORDER_TYPE_SELL_LIMIT: ok=m_trade.SellLimit(vol,price,m_symbol,0,0,ORDER_TIME_GTC,0,comment); break;
            case ORDER_TYPE_BUY_STOP:   ok=m_trade.BuyStop(vol,price,m_symbol,0,0,ORDER_TIME_GTC,0,comment);   break;
            case ORDER_TYPE_SELL_STOP:  ok=m_trade.SellStop(vol,price,m_symbol,0,0,ORDER_TIME_GTC,0,comment);  break;
            default:
               LogErr("OpenPending: unsupported order type.");
               return(false);
           }
         uint rc = m_trade.ResultRetcode();
         if(ok && (rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_PLACED))
           {
            LogInfo(StringFormat("OpenPending type=%d %.2f @ %.5f ok",(int)order_type,vol,price));
            return(true);
           }
         if(!IsTransient(rc))
           {
            LogErr(StringFormat("OpenPending failed permanently rc=%u (%s)",rc,m_trade.ResultRetcodeDescription()));
            return(false);
           }
         LogWarn(StringFormat("OpenPending transient rc=%u attempt %d/%d, retrying...",rc,attempt,m_max_retries));
         Sleep(m_retry_sleep_ms);
        }
      LogErr("OpenPending: exhausted retries.");
      return(false);
     }

   //--- Convenience wrappers for the pending helpers.
   bool              OpenLimit(const ENUM_GRID_DIRECTION dir,const double lot,const double price,const string comment="")
     {
      return(OpenPending(dir==GRID_BUY?ORDER_TYPE_BUY_LIMIT:ORDER_TYPE_SELL_LIMIT,lot,price,comment));
     }
   bool              OpenStop(const ENUM_GRID_DIRECTION dir,const double lot,const double price,const string comment="")
     {
      return(OpenPending(dir==GRID_BUY?ORDER_TYPE_BUY_STOP:ORDER_TYPE_SELL_STOP,lot,price,comment));
     }

   //--- True when it is safe to attempt a trade send this instant.
   //    We check both the EA-stop flag and the terminal's trade-context
   //    availability (TERMINAL_TRADE_ALLOWED). CTrade already serialises
   //    the actual send, so this is a best-effort pre-check to avoid
   //    spinning when trading is globally disabled or the EA is being
   //    torn down. It is read-only and never closes/forces anything.
   bool              IsTradeContextFree(void) const
     {
      if(IsStopped())
         return(false);
      if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
         return(false);
      return(true);
     }

   //================================================================//
   //  (c) BASKET QUERIES (filtered by magic + symbol)               //
   //================================================================//
   //--- Does a given position belong to this EA's basket?
   bool              IsOurPosition(const ulong ticket) const
     {
      if(!PositionSelectByTicket(ticket))
         return(false);
      return(PositionGetInteger(POSITION_MAGIC)==m_magic &&
             PositionGetString(POSITION_SYMBOL)==m_symbol);
     }

   //--- Count of open positions in this basket.
   int               CountBasketPositions(void) const
     {
      int cnt=0;
      int total=PositionsTotal();
      for(int i=0;i<total;i++)
        {
         ulong tk=PositionGetTicket(i);
         if(tk==0) continue;
         if(PositionGetInteger(POSITION_MAGIC)==m_magic &&
            PositionGetString(POSITION_SYMBOL)==m_symbol)
            cnt++;
        }
      return(cnt);
     }

   //--- Count of open positions on ONE side of the basket only.
   //    Used by the RecoveryEngine as the martingale/grid LEVEL INDEX so
   //    an opposite-side hedge leg does not inflate the progression
   //    exponent or consume grid depth on the recovery side.
   int               CountSidePositions(const ENUM_GRID_DIRECTION dir) const
     {
      ENUM_POSITION_TYPE want = (dir==GRID_BUY ? POSITION_TYPE_BUY : POSITION_TYPE_SELL);
      int cnt=0;
      int total=PositionsTotal();
      for(int i=0;i<total;i++)
        {
         ulong tk=PositionGetTicket(i);
         if(tk==0) continue;
         if(PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol) continue;
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=want) continue;
         cnt++;
        }
      return(cnt);
     }

   //--- Summed volume of one side of the basket.
   double            SideVolume(const ENUM_GRID_DIRECTION dir) const
     {
      ENUM_POSITION_TYPE want = (dir==GRID_BUY ? POSITION_TYPE_BUY : POSITION_TYPE_SELL);
      double v=0.0;
      int total=PositionsTotal();
      for(int i=0;i<total;i++)
        {
         ulong tk=PositionGetTicket(i);
         if(tk==0) continue;
         if(PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol) continue;
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=want) continue;
         v+=PositionGetDouble(POSITION_VOLUME);
        }
      return(v);
     }

   //--- Summed volume of the whole basket.
   double            BasketVolume(void) const
     {
      double v=0.0;
      int total=PositionsTotal();
      for(int i=0;i<total;i++)
        {
         ulong tk=PositionGetTicket(i);
         if(tk==0) continue;
         if(PositionGetInteger(POSITION_MAGIC)==m_magic &&
            PositionGetString(POSITION_SYMBOL)==m_symbol)
            v+=PositionGetDouble(POSITION_VOLUME);
        }
      return(v);
     }

   //--- Combined floating PnL (profit + swap + commission proxy).
   double            BasketFloatingPnL(void) const
     {
      double pnl=0.0;
      int total=PositionsTotal();
      for(int i=0;i<total;i++)
        {
         ulong tk=PositionGetTicket(i);
         if(tk==0) continue;
         if(PositionGetInteger(POSITION_MAGIC)==m_magic &&
            PositionGetString(POSITION_SYMBOL)==m_symbol)
           {
            pnl+=PositionGetDouble(POSITION_PROFIT);
            pnl+=PositionGetDouble(POSITION_SWAP);
           }
        }
      return(pnl);
     }

   //--- Collect the tickets of the basket into `tickets[]`. Returns count.
   int               BasketTickets(ulong &tickets[]) const
     {
      ArrayResize(tickets,0);
      int total=PositionsTotal();
      for(int i=0;i<total;i++)
        {
         ulong tk=PositionGetTicket(i);
         if(tk==0) continue;
         if(PositionGetInteger(POSITION_MAGIC)==m_magic &&
            PositionGetString(POSITION_SYMBOL)==m_symbol)
           {
            int n=ArraySize(tickets);
            ArrayResize(tickets,n+1);
            tickets[n]=tk;
           }
        }
      return(ArraySize(tickets));
     }

   //--- Volume-weighted average entry price for one side.
   //    dir=GRID_BUY -> buys only; GRID_SELL -> sells only.
   //    Returns 0.0 if no positions on that side.
   double            WeightedAvgEntry(const ENUM_GRID_DIRECTION dir) const
     {
      ENUM_POSITION_TYPE want = (dir==GRID_BUY ? POSITION_TYPE_BUY : POSITION_TYPE_SELL);
      double num=0.0, den=0.0;
      int total=PositionsTotal();
      for(int i=0;i<total;i++)
        {
         ulong tk=PositionGetTicket(i);
         if(tk==0) continue;
         if(PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol) continue;
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=want) continue;
         double vol=PositionGetDouble(POSITION_VOLUME);
         double pe =PositionGetDouble(POSITION_PRICE_OPEN);
         num+=pe*vol;
         den+=vol;
        }
      return(den>0.0 ? num/den : 0.0);
     }

   //--- NET-BASKET break-even price across BOTH legs.
   //    A single side's weighted-average entry is only the break-even
   //    when the basket is one-sided. Once a hedge is open the true net
   //    break-even must net the opposite leg. We compute the price at
   //    which the combined buy/sell P&L is zero:
   //        net_lots = buy_vol - sell_vol   (signed net exposure)
   //        For BUY-net:  P&L(price) = (price - buy_avg)*buy_vol
   //                                 - (price - sell_avg)*sell_vol = 0
   //        => price = (buy_avg*buy_vol - sell_avg*sell_vol) / net_lots
   //    `ok` is false and 0.0 returned when the basket is flat/netted
   //    (net_lots ~ 0), because then no single price flips the sign and
   //    a points-based target is meaningless (currency-mode TP handles
   //    that case correctly). This is PURELY a target calculation; it
   //    never triggers a close by itself.
   double            NetBasketBreakEven(const ENUM_GRID_DIRECTION net_dir,bool &ok) const
     {
      ok=false;
      double buy_vol  = SideVolume(GRID_BUY);
      double sell_vol = SideVolume(GRID_SELL);
      double buy_avg  = WeightedAvgEntry(GRID_BUY);
      double sell_avg = WeightedAvgEntry(GRID_SELL);

      double net_lots = buy_vol - sell_vol;   // >0 net long, <0 net short
      //--- require a meaningful net exposure to define a break-even price
      double vstep = SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_STEP);
      if(vstep<=0.0) vstep = 0.01;
      if(MathAbs(net_lots) < vstep*0.5)
         return(0.0);                          // netted flat -> no BE price

      //--- direction sanity: net side must match the requested net_dir
      if(net_dir==GRID_BUY  && net_lots<=0.0) return(0.0);
      if(net_dir==GRID_SELL && net_lots>=0.0) return(0.0);

      double be = (buy_avg*buy_vol - sell_avg*sell_vol) / net_lots;
      if(be<=0.0) return(0.0);
      ok=true;
      return(be);
     }

   //--- Open time of the OLDEST position in the basket (0 if none).
   //    Used by the RecoveryEngine to age a basket for the time-decay
   //    take-profit, so a stale basket can escape at a smaller target
   //    instead of being stuck for weeks.
   datetime          BasketOldestOpenTime(void) const
     {
      datetime oldest = 0;
      int total=PositionsTotal();
      for(int i=0;i<total;i++)
        {
         ulong tk=PositionGetTicket(i);
         if(tk==0) continue;
         if(PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol) continue;
         datetime t=(datetime)PositionGetInteger(POSITION_TIME);
         if(oldest==0 || t<oldest) oldest=t;
        }
      return(oldest);
     }

   //--- Basket age in hours (0 when there is no basket).
   double            BasketAgeHours(void) const
     {
      datetime oldest = BasketOldestOpenTime();
      if(oldest==0) return(0.0);
      long secs = (long)(TimeCurrent() - oldest);
      if(secs<0) secs=0;
      return((double)secs/3600.0);
     }

   //--- Find the MOST PROFITABLE leg in the basket.
   //    Returns true and fills ticket/profit/volume when a leg with
   //    profit strictly above `min_profit` exists. Used by the partial
   //    harvest logic to bank a winning leg and cut exposure.
   bool              MostProfitableLeg(const double min_profit,ulong &ticket,
                                       double &profit,double &volume) const
     {
      ticket = 0;
      profit = 0.0;
      volume = 0.0;
      bool found=false;
      int total=PositionsTotal();
      for(int i=0;i<total;i++)
        {
         ulong tk=PositionGetTicket(i);
         if(tk==0) continue;
         if(PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol) continue;
         double pr = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         if(pr <= min_profit) continue;
         if(!found || pr > profit)
           {
            found  = true;
            ticket = tk;
            profit = pr;
            volume = PositionGetDouble(POSITION_VOLUME);
           }
        }
      return(found);
     }

   //--- Close ONE position entirely by ticket (used by partial harvest
   //    to bank a single profitable leg). Retries transient errors.
   bool              ClosePosition(const ulong ticket)
     {
      for(int attempt=1;attempt<=m_max_retries;attempt++)
        {
         bool ok=m_trade.PositionClose(ticket);
         uint rc=m_trade.ResultRetcode();
         if(ok && (rc==TRADE_RETCODE_DONE||rc==TRADE_RETCODE_PLACED))
            return(true);
         if(!IsTransient(rc))
            return(false);
         Sleep(m_retry_sleep_ms);
        }
      return(false);
     }

   //================================================================//
   //  (d) BASKET CLOSE HELPERS                                      //
   //                                                                //
   //  v2 NOTE ON SEMANTICS - this changed from v1 and it matters:    //
   //    In v1 CloseBasket() was documented as profit-only, and the   //
   //    RecoveryEngine only ever called it when basket PnL > 0. That  //
   //    guaranteed no loss was ever realised - and that is exactly    //
   //    why a basket on the wrong side of a trend held until the      //
   //    account died.                                                //
   //                                                                //
   //    In v2 this helper is MECHANISM ONLY: it closes the basket     //
   //    whatever the PnL. The POLICY of when closing is allowed lives  //
   //    entirely in the RecoveryEngine, which calls it from exactly   //
   //    two places: the group take-profit path (in profit) and the    //
   //    basket stop path (bounded loss, and only when the basket stop  //
   //    is enabled). The SafetyValve still never closes anything.     //
   //================================================================//
   //--- Close every position in the basket.
   bool              CloseBasket(void)
     {
      bool all_ok=true;
      //--- iterate a fresh snapshot of tickets to avoid index shift
      ulong tickets[];
      int n=BasketTickets(tickets);
      for(int i=0;i<n;i++)
        {
         bool ok=false;
         for(int attempt=1;attempt<=m_max_retries;attempt++)
           {
            ok=m_trade.PositionClose(tickets[i]);
            uint rc=m_trade.ResultRetcode();
            if(ok && (rc==TRADE_RETCODE_DONE||rc==TRADE_RETCODE_PLACED))
               break;
            if(!IsTransient(rc))
               break;
            Sleep(m_retry_sleep_ms);
           }
         if(!ok)
           {
            all_ok=false;
            LogWarn(StringFormat("CloseBasket: failed to close ticket %I64u",tickets[i]));
           }
        }
      if(n>0)
         LogInfo(StringFormat("CloseBasket: closed %d position(s), all_ok=%s",n,(all_ok?"true":"false")));
      return(all_ok);
     }

   //--- Partially close a single position (profit scaling).
   bool              ClosePartial(const ulong ticket,const double volume)
     {
      double vol=NormalizeLot(volume);
      if(vol<=0.0) return(false);
      for(int attempt=1;attempt<=m_max_retries;attempt++)
        {
         bool ok=m_trade.PositionClosePartial(ticket,vol);
         uint rc=m_trade.ResultRetcode();
         if(ok && (rc==TRADE_RETCODE_DONE||rc==TRADE_RETCODE_PLACED))
            return(true);
         if(!IsTransient(rc))
            return(false);
         Sleep(m_retry_sleep_ms);
        }
      return(false);
     }
  };

#endif // ADAPTIVEGRID_ORDERMANAGER_MQH
//+------------------------------------------------------------------+
