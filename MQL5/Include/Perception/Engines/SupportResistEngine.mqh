//+------------------------------------------------------------------+
//|                                          SupportResistEngine.mqh  |
//|             001 PERCEPTION - Support / Resistance engine          |
//|                                                                  |
//| Trades rejections at the nearest structural level detected by    |
//| the market-structure module. A long is taken when price probes   |
//| support and the oscillators show the sellers are exhausted.      |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_ENGINES_SUPPORTRESIST_MQH
#define PERCEPTION_ENGINES_SUPPORTRESIST_MQH

#include <Perception/Engines/IEngine.mqh>

class CSupportResistEngine : public CEngine
  {
public:
   CSupportResistEngine() { m_id=ENG_SUPPORT_RES; m_name="S/R"; }

   double Suitability(const SMarketState &st) override
     {
      switch(st.regime)
        {
         case REGIME_RANGE:    return 0.80;
         case REGIME_SIDEWAYS: return 0.72;
         case REGIME_WEAK_TREND_UP:
         case REGIME_WEAK_TREND_DOWN: return 0.55;
         default:              return 0.25;
        }
     }

   void Evaluate(const SMarketState &st,CSymbolMeta *sym,const SConfig &cfg,SSignal &out) override
     {
      out.Reset(); out.engine=m_id;
      double atr=st.atr; if(atr<=0.0) return;
      double nearSup=MathAbs(st.mid-st.nearestSupport);
      double nearRes=MathAbs(st.nearestResistance-st.mid);
      double conf=0.55;

      if(nearSup<=0.5*atr && st.rsi<45.0 && st.nearestSupport>0.0)
        {
         out.dir=SIG_BUY; out.confidence=conf; out.quality=0.55;
         out.sl=sym.NormalizePrice(st.nearestSupport-1.0*atr);
         out.tp=sym.NormalizePrice(st.nearestResistance);
         out.reason="Bounce from support";
        }
      else if(nearRes<=0.5*atr && st.rsi>55.0 && st.nearestResistance>0.0)
        {
         out.dir=SIG_SELL; out.confidence=conf; out.quality=0.55;
         out.sl=sym.NormalizePrice(st.nearestResistance+1.0*atr);
         out.tp=sym.NormalizePrice(st.nearestSupport);
         out.reason="Rejection at resistance";
        }
     }
  };

#endif // PERCEPTION_ENGINES_SUPPORTRESIST_MQH
//+------------------------------------------------------------------+
