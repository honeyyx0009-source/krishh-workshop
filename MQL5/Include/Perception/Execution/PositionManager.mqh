//+------------------------------------------------------------------+
//|                                              PositionManager.mqh |
//|             001 PERCEPTION - Live trade management                |
//|                                                                  |
//| Opening a trade is easy; managing it well is where edge is       |
//| preserved. This module walks the EA's open positions each bar    |
//| and applies break-even, an ATR trailing stop and a one-shot      |
//| partial close. Every threshold is expressed in R-multiples (the  |
//| initial ATR risk) so the behaviour is identical across symbols   |
//| regardless of their point size.                                  |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_EXECUTION_POSITIONMANAGER_MQH
#define PERCEPTION_EXECUTION_POSITIONMANAGER_MQH

#include <Perception/Execution/OrderManager.mqh>
#include <Perception/Core/Config.mqh>
#include <Perception/Core/Types.mqh>

class CPositionManager
  {
private:
   CSymbolMeta  *m_sym;
   COrderManager *m_om;
   long          m_magicLo, m_magicHi;
   ulong         m_partialDone[];   // tickets already partially closed

   bool WasPartialed(const ulong tk)
     {
      for(int i=0;i<ArraySize(m_partialDone);i++)
         if(m_partialDone[i]==tk) return true;
      return false;
     }
   void MarkPartialed(const ulong tk)
     {
      int s=ArraySize(m_partialDone);
      ArrayResize(m_partialDone,s+1);
      m_partialDone[s]=tk;
     }
   void PrunePartialed()
     {
      ulong keep[]; ArrayResize(keep,0);
      for(int i=0;i<ArraySize(m_partialDone);i++)
         if(PositionSelectByTicket(m_partialDone[i]))
           { int s=ArraySize(keep); ArrayResize(keep,s+1); keep[s]=m_partialDone[i]; }
      ArrayFree(m_partialDone);
      ArrayCopy(m_partialDone,keep);
     }

public:
                     CPositionManager(): m_sym(NULL), m_om(NULL), m_magicLo(0), m_magicHi(0) {}

   void Init(CSymbolMeta *sym,COrderManager *om,const long magicLo,const long magicHi)
     { m_sym=sym; m_om=om; m_magicLo=magicLo; m_magicHi=magicHi; }

   //--- manage all owned positions on the chart symbol --------------
   void Update(const SMarketState &st,const SConfig &cfg)
     {
      if(m_sym==NULL || m_om==NULL) return;
      double atr=st.atr; if(atr<=0.0) return;
      double point=m_sym.Point();
      double rUnit=cfg.atrSlMult*atr;                 // 1R in price
      if(rUnit<=0.0) return;

      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong tk=PositionGetTicket(i);
         if(tk==0) continue;
         long mg=(long)PositionGetInteger(POSITION_MAGIC);
         if(mg<m_magicLo || mg>m_magicHi) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_sym.Symbol()) continue;

         long type=(long)PositionGetInteger(POSITION_TYPE);
         double entry=PositionGetDouble(POSITION_PRICE_OPEN);
         double sl=PositionGetDouble(POSITION_SL);
         double tp=PositionGetDouble(POSITION_TP);
         double vol=PositionGetDouble(POSITION_VOLUME);
         double price=(type==POSITION_TYPE_BUY?m_sym.Bid():m_sym.Ask());
         double profitDist=(type==POSITION_TYPE_BUY?price-entry:entry-price);
         double rr=profitDist/rUnit;

         double newSL=sl;

         //--- break-even ------------------------------------------
         if(cfg.useBreakeven && rr>=cfg.beTriggerRR)
           {
            double be=(type==POSITION_TYPE_BUY? entry+cfg.beLockPts*point
                                              : entry-cfg.beLockPts*point);
            if(type==POSITION_TYPE_BUY  && (sl<be)) newSL=be;
            if(type==POSITION_TYPE_SELL && (sl>be || sl==0.0)) newSL=be;
           }

         //--- ATR trailing ----------------------------------------
         if(cfg.useTrailing && rr>=cfg.trailStartRR)
           {
            double trail=(type==POSITION_TYPE_BUY? price-cfg.trailAtrMult*atr
                                                 : price+cfg.trailAtrMult*atr);
            trail=m_sym.NormalizePrice(trail);
            if(type==POSITION_TYPE_BUY  && trail>newSL) newSL=trail;
            if(type==POSITION_TYPE_SELL && (trail<newSL || newSL==0.0)) newSL=trail;
           }

         if(MathAbs(newSL-sl)>point*0.5)
            m_om.ModifyPosition(tk,m_sym.NormalizePrice(newSL),tp);

         //--- one-shot partial close ------------------------------
         if(cfg.usePartialClose && rr>=cfg.partialRR && !WasPartialed(tk))
           {
            double closeVol=m_sym.NormalizeLots(vol*cfg.partialPct);
            if(closeVol>=m_sym.VolMin() && (vol-closeVol)>=m_sym.VolMin())
              {
               if(m_om.ClosePartial(tk,closeVol)) MarkPartialed(tk);
              }
           }
        }
      PrunePartialed();
     }
  };

#endif // PERCEPTION_EXECUTION_POSITIONMANAGER_MQH
//+------------------------------------------------------------------+
