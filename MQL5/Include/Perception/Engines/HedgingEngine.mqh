//+------------------------------------------------------------------+
//|                                                 HedgingEngine.mqh |
//|             001 PERCEPTION - Protective hedge engine (opt-in)     |
//|                                                                  |
//| When this engine's own directional basket is deeply underwater   |
//| it opens a partial opposite position to cap further loss while   |
//| the market decides. This is a defensive brake, not a profit      |
//| centre, and is disabled by default. On netting accounts a hedge  |
//| simply reduces net exposure rather than opening an opposite      |
//| ticket - the effect (reduced risk) is the same.                  |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_ENGINES_HEDGING_MQH
#define PERCEPTION_ENGINES_HEDGING_MQH

#include <Perception/Engines/IEngine.mqh>

class CHedgingEngine : public CEngine
  {
public:
   CHedgingEngine() { m_id=ENG_HEDGING; m_name="Hedge"; m_enabled=false; }

   double Suitability(const SMarketState &st) override
     {
      return (OwnVolume()>0.0 ? 0.40 : 0.05);
     }

   void Evaluate(const SMarketState &st,CSymbolMeta *sym,const SConfig &cfg,SSignal &out) override
     {
      out.Reset(); out.engine=m_id;
      double atr=st.atr; if(atr<=0.0) return;
      double bBuy,wBuy,bSell,wSell; int buys,sells;
      if(!OwnExtreme(bBuy,wBuy,bSell,wSell,buys,sells)) return;

      //--- if long basket is >2 ATR underwater, add a partial short -
      if(buys>0 && sells==0 && (wBuy-st.mid)>2.0*atr)
        {
         out.dir=SIG_SELL; out.lots=sym.NormalizeLots(OwnVolume()*0.5);
         out.confidence=0.45; out.quality=0.4; out.rr=1.2;
         out.reason="Protective hedge (long basket underwater)";
        }
      else if(sells>0 && buys==0 && (st.mid-wSell)>2.0*atr)
        {
         out.dir=SIG_BUY; out.lots=sym.NormalizeLots(OwnVolume()*0.5);
         out.confidence=0.45; out.quality=0.4; out.rr=1.2;
         out.reason="Protective hedge (short basket underwater)";
        }
     }
  };

#endif // PERCEPTION_ENGINES_HEDGING_MQH
//+------------------------------------------------------------------+
