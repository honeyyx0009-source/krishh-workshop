//+------------------------------------------------------------------+
//|                                                 OrderManager.mqh |
//|             001 PERCEPTION - Order execution wrapper              |
//|                                                                  |
//| A thin, defensive wrapper over the standard-library CTrade. It   |
//| centralises magic-number stamping, filling-mode selection and    |
//| price/volume normalisation so no engine ever talks to the trade  |
//| server directly. Every engine gets its own magic number, which   |
//| keeps statistics and recovery logic cleanly separated.           |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_EXECUTION_ORDERMANAGER_MQH
#define PERCEPTION_EXECUTION_ORDERMANAGER_MQH

#include <Trade/Trade.mqh>
#include <Perception/Core/SymbolMeta.mqh>
#include <Perception/Core/Logger.mqh>

class COrderManager
  {
private:
   CTrade        m_trade;
   CSymbolMeta  *m_sym;
   CLogger      *m_log;
   long          m_magicLo, m_magicHi;

public:
                     COrderManager(): m_sym(NULL), m_log(NULL), m_magicLo(0), m_magicHi(0) {}

   void Init(CSymbolMeta *sym,CLogger *log,const long magicLo,const long magicHi)
     {
      m_sym=sym; m_log=log; m_magicLo=magicLo; m_magicHi=magicHi;
      m_trade.SetTypeFilling(sym.Filling());
      m_trade.SetDeviationInPoints(20);
      m_trade.SetAsyncMode(false);
     }

   //--- open a market position for a given engine --------------------
   bool OpenMarket(const SSignal &sig,const long magic,const string comment)
     {
      if(m_sym==NULL) return false;
      m_trade.SetExpertMagicNumber(magic);
      double lots=m_sym.NormalizeLots(sig.lots);
      bool ok=false;
      if(sig.dir==SIG_BUY)
         ok=m_trade.Buy(lots,m_sym.Symbol(),0.0,sig.sl,sig.tp,comment);
      else if(sig.dir==SIG_SELL)
         ok=m_trade.Sell(lots,m_sym.Symbol(),0.0,sig.sl,sig.tp,comment);
      if(!ok && m_log!=NULL)
         m_log.Warn(StringFormat("Open failed %s ret=%d %s",comment,
                    m_trade.ResultRetcode(),m_trade.ResultRetcodeDescription()));
      return ok;
     }

   //--- open a pending order (limit / stop) --------------------------
   bool OpenPending(const SSignal &sig,const long magic,const string comment)
     {
      if(m_sym==NULL) return false;
      m_trade.SetExpertMagicNumber(magic);
      double lots=m_sym.NormalizeLots(sig.lots);
      double price=m_sym.NormalizePrice(sig.price);
      bool ok=false;
      if(sig.entry==ENTRY_LIMIT)
        {
         if(sig.dir==SIG_BUY) ok=m_trade.BuyLimit(lots,price,m_sym.Symbol(),sig.sl,sig.tp,ORDER_TIME_GTC,0,comment);
         else                 ok=m_trade.SellLimit(lots,price,m_sym.Symbol(),sig.sl,sig.tp,ORDER_TIME_GTC,0,comment);
        }
      else // ENTRY_STOP
        {
         if(sig.dir==SIG_BUY) ok=m_trade.BuyStop(lots,price,m_sym.Symbol(),sig.sl,sig.tp,ORDER_TIME_GTC,0,comment);
         else                 ok=m_trade.SellStop(lots,price,m_sym.Symbol(),sig.sl,sig.tp,ORDER_TIME_GTC,0,comment);
        }
      return ok;
     }

   bool ModifyPosition(const ulong ticket,const double sl,const double tp)
     {
      return m_trade.PositionModify(ticket,sl,tp);
     }

   bool ClosePartial(const ulong ticket,const double lots)
     {
      return m_trade.PositionClosePartial(ticket,lots);
     }

   bool ClosePosition(const ulong ticket)
     {
      return m_trade.PositionClose(ticket);
     }

   //--- emergency: flatten everything belonging to this EA ----------
   int CloseAll()
     {
      int closed=0;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong tk=PositionGetTicket(i);
         if(tk==0) continue;
         long mg=(long)PositionGetInteger(POSITION_MAGIC);
         if(mg<m_magicLo || mg>m_magicHi) continue;
         if(m_trade.PositionClose(tk)) closed++;
        }
      return closed;
     }
  };

#endif // PERCEPTION_EXECUTION_ORDERMANAGER_MQH
//+------------------------------------------------------------------+
