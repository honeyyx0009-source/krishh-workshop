//+------------------------------------------------------------------+
//|                                                  RiskManager.mqh |
//|            001 PERCEPTION - Institutional risk control            |
//|                                                                  |
//| The risk manager is deliberately pessimistic. It is the last     |
//| gate before capital is committed and the first thing to speak up |
//| when the account is under stress. Position sizing is derived     |
//| from a fixed-fractional model, stops are volatility-scaled and   |
//| respect broker stop levels, and a layered set of circuit         |
//| breakers (spread, margin, daily loss, drawdown, equity floor)    |
//| can throttle or fully halt trading.                              |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_RISK_RISKMANAGER_MQH
#define PERCEPTION_RISK_RISKMANAGER_MQH

#include <Perception/Core/SymbolMeta.mqh>
#include <Perception/Core/Config.mqh>
#include <Perception/Core/Logger.mqh>
#include <Perception/Stats/Statistics.mqh>

class CRiskManager
  {
private:
   CSymbolMeta      *m_sym;
   CStatistics      *m_stats;
   CLogger          *m_log;
   SConfig           m_cfg;
   long              m_magicLo, m_magicHi;
   double            m_initialEquity;
   ENUM_SYSTEM_STATE m_state;
   bool              m_haltedForDay;
   datetime          m_haltDay;
   bool              m_emergencyClose;
   string            m_reason;

public:
                     CRiskManager(): m_sym(NULL), m_stats(NULL), m_log(NULL),
                                     m_initialEquity(0), m_state(STATE_INIT),
                                     m_haltedForDay(false), m_haltDay(0),
                                     m_emergencyClose(false), m_reason("") {}

   void Init(CSymbolMeta *sym,CStatistics *stats,CLogger *log,const SConfig &cfg,
             const long magicLo,const long magicHi)
     {
      m_sym=sym; m_stats=stats; m_log=log; m_cfg=cfg;
      m_magicLo=magicLo; m_magicHi=magicHi;
      m_initialEquity=AccountInfoDouble(ACCOUNT_EQUITY);
      m_state=STATE_RUNNING;
     }

   //================================================================
   //  Portfolio inspection helpers
   //================================================================
   int CountPortfolio()
     {
      int c=0;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong tk=PositionGetTicket(i);
         if(tk==0) continue;
         long mg=(long)PositionGetInteger(POSITION_MAGIC);
         if(mg>=m_magicLo && mg<=m_magicHi) c++;
        }
      return c;
     }

   int CountSymbol(const string sym)
     {
      int c=0;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong tk=PositionGetTicket(i);
         if(tk==0) continue;
         if(PositionGetString(POSITION_SYMBOL)!=sym) continue;
         long mg=(long)PositionGetInteger(POSITION_MAGIC);
         if(mg>=m_magicLo && mg<=m_magicHi) c++;
        }
      return c;
     }

   double FloatingPL()
     {
      double pl=0.0;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong tk=PositionGetTicket(i);
         if(tk==0) continue;
         long mg=(long)PositionGetInteger(POSITION_MAGIC);
         if(mg>=m_magicLo && mg<=m_magicHi)
            pl+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
        }
      return pl;
     }

   //================================================================
   //  Circuit breakers, evaluated once per tick
   //================================================================
   void OnTick()
     {
      if(m_stats!=NULL) m_stats.OnEquityTick();

      //--- reset the daily halt when a new day begins ---------------
      MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
      datetime day=StringToTime(StringFormat("%04d.%02d.%02d 00:00",dt.year,dt.mon,dt.day));
      if(m_haltDay!=day){ m_haltDay=day; m_haltedForDay=false; }

      double equity=AccountInfoDouble(ACCOUNT_EQUITY);
      double dd=(m_stats!=NULL?m_stats.Stats().currentDD:0.0);

      //--- hard equity floor relative to initial deposit ------------
      if(m_initialEquity>0.0 &&
         equity<=m_initialEquity*(1.0-m_cfg.equityStopPct/100.0))
        {
         Halt("Equity floor breached");
         return;
        }

      //--- maximum drawdown protection ------------------------------
      if(dd*100.0>=m_cfg.maxDrawdownPct)
        {
         if(m_cfg.useKillSwitch){ Halt("Max drawdown kill switch"); return; }
         m_state=STATE_THROTTLED; m_reason="Drawdown throttle"; return;
        }

      //--- daily loss limiter ---------------------------------------
      if(m_stats!=NULL)
        {
         double startBal=equity-m_stats.DailyProfit();
         if(startBal>0.0 && m_stats.DailyProfit()<=-startBal*m_cfg.dailyLossLimitPct/100.0)
           {
            m_haltedForDay=true; m_reason="Daily loss limit";
           }
        }

      if(m_state==STATE_HALTED) return;
      if(m_haltedForDay){ m_state=STATE_THROTTLED; return; }

      //--- recovery zone: drawdown building but below the hard cap --
      if(dd*100.0>=m_cfg.maxDrawdownPct*0.6 && m_cfg.useRecovery)
        { m_state=STATE_RECOVERY; m_reason="Recovery mode"; }
      else
        { m_state=STATE_RUNNING; m_reason="Nominal"; }
     }

   void Halt(const string why)
     {
      if(m_state!=STATE_HALTED && m_log!=NULL) m_log.Warn("KILL SWITCH: "+why);
      m_state=STATE_HALTED; m_reason=why; m_emergencyClose=true;
     }

   //--- master gate for opening NEW trades ---------------------------
   bool TradingAllowed(const SMarketState &st,string &reason)
     {
      if(!m_cfg.autoTrade)          { reason="Auto-trading off"; return false; }
      if(m_state==STATE_HALTED)     { reason=m_reason;           return false; }
      if(m_haltedForDay)            { reason="Daily loss limit"; return false; }
      if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) { reason="Terminal trade disabled"; return false; }
      if(!MQLInfoInteger(MQL_TRADE_ALLOWED))           { reason="EA trade disabled";       return false; }

      //--- spread gate (auto cap derived from ATR when not set) -----
      double cap=m_cfg.maxSpreadPts;
      if(cap<=0.0 && m_sym!=NULL && st.atr>0.0)
         cap=MathMax(20.0,0.15*(st.atr/m_sym.Point()));
      if(cap>0.0 && st.spreadPts>cap){ reason=StringFormat("Spread %.0f>%.0f",st.spreadPts,cap); return false; }

      //--- exposure caps --------------------------------------------
      if(CountPortfolio()>=m_cfg.maxOpenTrades){ reason="Max open trades"; return false; }

      //--- margin sanity --------------------------------------------
      if(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL)>0.0 &&
         AccountInfoDouble(ACCOUNT_MARGIN_LEVEL)<200.0 &&
         AccountInfoDouble(ACCOUNT_MARGIN)>0.0)
        { reason="Margin level low"; return false; }

      reason="OK";
      return true;
     }

   bool SymbolSlotFree(const string sym)
     { return(CountSymbol(sym)<m_cfg.maxTradesPerSymbol); }

   //================================================================
   //  Stop / target construction and position sizing
   //================================================================
   //--- fill missing SL/TP from ATR and clamp to broker stop level --
   void ResolveStops(SSignal &sig,const SMarketState &st)
     {
      if(m_sym==NULL) return;
      double atr=st.atr; if(atr<=0.0) atr=st.mid*0.001;
      double entry=(sig.price>0.0?sig.price:(sig.dir==SIG_BUY?st.ask:st.bid));
      double slDist=m_cfg.atrSlMult*atr;
      double minDist=MathMax(m_cfg.minStopAtrMult*atr,
                             (m_sym.StopLevel()+st.spreadPts)*m_sym.Point());
      if(slDist<minDist) slDist=minDist;

      double rr=(sig.rr>0.0?sig.rr:PU::SafeDiv(m_cfg.atrTpMult,m_cfg.atrSlMult,1.5));
      double tpDist=slDist*rr;

      if(sig.dir==SIG_BUY)
        {
         if(sig.sl<=0.0) sig.sl=m_sym.NormalizePrice(entry-slDist);
         if(sig.tp<=0.0) sig.tp=m_sym.NormalizePrice(entry+tpDist);
        }
      else if(sig.dir==SIG_SELL)
        {
         if(sig.sl<=0.0) sig.sl=m_sym.NormalizePrice(entry+slDist);
         if(sig.tp<=0.0) sig.tp=m_sym.NormalizePrice(entry-tpDist);
        }
      sig.price=m_sym.NormalizePrice(entry);
     }

   //--- fixed-fractional sizing with a hard margin cap --------------
   //--- if the signal carries an explicit volume (grid / recovery    |
   //--- engines) that volume is honoured, still capped by margin.    |
   double SizePosition(const SSignal &sig)
     {
      if(m_sym==NULL) return 0.0;
      double lots;
      if(sig.lots>0.0)
        {
         lots=m_sym.NormalizeLots(sig.lots);
        }
      else
        {
         double stopPoints=PU::SafeDiv(MathAbs(sig.price-sig.sl),m_sym.Point(),0.0);
         if(stopPoints<=0.0) return m_sym.VolMin();

         double equity=AccountInfoDouble(ACCOUNT_EQUITY);
         double riskPct=m_cfg.riskPercent;
         if(m_state==STATE_RECOVERY) riskPct*=0.5;        // de-risk in drawdown
         if(m_state==STATE_THROTTLED) riskPct*=0.35;
         double riskMoney=equity*riskPct/100.0;

         lots=m_sym.LotsForRisk(riskMoney,stopPoints);
        }

      //--- never let one order eat more than half of free margin ----
      double price=sig.price;
      ENUM_ORDER_TYPE ot=(sig.dir==SIG_BUY?ORDER_TYPE_BUY:ORDER_TYPE_SELL);
      double marginOne=0.0;
      if(OrderCalcMargin(ot,m_sym.Symbol(),1.0,price,marginOne) && marginOne>0.0)
        {
         double freeM=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
         double maxLotsByMargin=(freeM*0.5)/marginOne;
         if(lots>maxLotsByMargin) lots=m_sym.NormalizeLots(maxLotsByMargin);
        }
      if(lots<m_sym.VolMin()) lots=m_sym.VolMin();
      return lots;
     }

   //--- accessors ----------------------------------------------------
   ENUM_SYSTEM_STATE State()  const { return m_state; }
   string            Reason() const { return m_reason; }
   bool  EmergencyRequested() const { return m_emergencyClose; }
   void  ClearEmergency()           { m_emergencyClose=false; }
   double CurrentRiskPct() const
     {
      double r=m_cfg.riskPercent;
      if(m_state==STATE_RECOVERY) r*=0.5;
      if(m_state==STATE_THROTTLED) r*=0.35;
      return r;
     }
  };

#endif // PERCEPTION_RISK_RISKMANAGER_MQH
//+------------------------------------------------------------------+
