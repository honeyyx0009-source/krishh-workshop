//+------------------------------------------------------------------+
//|                                                     SMCEngine.mqh |
//|             001 PERCEPTION - Smart Money Concept engine           |
//|                                                                  |
//| A composite price-action engine. It waits for a break of         |
//| structure (BOS) - the last swing being decisively taken out -    |
//| and then joins the move on the first pullback, aligning with the |
//| structural bias reported by the analysis layer.                  |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_ENGINES_SMC_MQH
#define PERCEPTION_ENGINES_SMC_MQH

#include <Perception/Engines/IEngine.mqh>

class CSMCEngine : public CEngine
  {
public:
   CSMCEngine() { m_id=ENG_SMC; m_name="SMC"; }

   double Suitability(const SMarketState &st) override
     {
      switch(st.regime)
        {
         case REGIME_STRONG_TREND_UP:
         case REGIME_STRONG_TREND_DOWN: return 0.80;
         case REGIME_WEAK_TREND_UP:
         case REGIME_WEAK_TREND_DOWN:   return 0.78;
         case REGIME_EXPANSION:         return 0.55;
         default:                       return 0.25;
        }
     }

   void Evaluate(const SMarketState &st,CSymbolMeta *sym,const SConfig &cfg,SSignal &out) override
     {
      out.Reset(); out.engine=m_id;
      double atr=st.atr; if(atr<=0.0) return;
      double hi[],lo[]; ArraySetAsSeries(hi,true); ArraySetAsSeries(lo,true);
      if(CopyHigh(m_symbol,m_tf,0,14,hi)<14) return;
      if(CopyLow(m_symbol,m_tf,0,14,lo)<14)  return;
      double cl1=iClose(m_symbol,m_tf,1);

      //--- reference swing from bars 2..12 --------------------------
      double refHigh=hi[2]; double refLow=lo[2];
      for(int i=3;i<=12;i++){ if(hi[i]>refHigh) refHigh=hi[i]; if(lo[i]<refLow) refLow=lo[i]; }

      bool bosUp=(cl1>refHigh);
      bool bosDown=(cl1<refLow);

      if(bosUp && st.structureBias!=TREND_DOWN && st.mid<=cl1 && st.mid>=refHigh)
        {
         if(!MTFConfirms(st,SIG_BUY,cfg)) return;
         out.dir=SIG_BUY; out.confidence=0.68; out.quality=0.65; out.rr=2.2;
         out.sl=sym.NormalizePrice(refHigh-1.0*atr);
         out.reason="Bullish BOS retest";
        }
      else if(bosDown && st.structureBias!=TREND_UP && st.mid>=cl1 && st.mid<=refLow)
        {
         if(!MTFConfirms(st,SIG_SELL,cfg)) return;
         out.dir=SIG_SELL; out.confidence=0.68; out.quality=0.65; out.rr=2.2;
         out.sl=sym.NormalizePrice(refLow+1.0*atr);
         out.reason="Bearish BOS retest";
        }
     }
  };

#endif // PERCEPTION_ENGINES_SMC_MQH
//+------------------------------------------------------------------+
