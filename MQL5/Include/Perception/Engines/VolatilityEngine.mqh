//+------------------------------------------------------------------+
//|                                              VolatilityEngine.mqh |
//|             001 PERCEPTION - Volatility expansion engine          |
//|                                                                  |
//| A cousin of the breakout engine that keys off the Keltner        |
//| channel. When a candle closes outside the Keltner band while     |
//| ATR is rising, it joins the impulse.                             |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_ENGINES_VOLATILITY_MQH
#define PERCEPTION_ENGINES_VOLATILITY_MQH

#include <Perception/Engines/IEngine.mqh>

class CVolatilityEngine : public CEngine
  {
public:
   CVolatilityEngine() { m_id=ENG_VOLATILITY; m_name="Volatility"; }

   double Suitability(const SMarketState &st) override
     {
      switch(st.regime)
        {
         case REGIME_EXPANSION: return 0.85;
         case REGIME_VOLATILE:  return 0.70;
         case REGIME_COMPRESSION: return 0.60;
         default:               return 0.20;
        }
     }

   void Evaluate(const SMarketState &st,CSymbolMeta *sym,const SConfig &cfg,SSignal &out) override
     {
      out.Reset(); out.engine=m_id;
      if(st.volRatio<1.05) return;                     // need expanding ATR
      double conf=PU::Clamp(0.30+0.45*PU::Normalize01(st.volRatio,1.05,2.0),0.0,0.95);

      if(st.bid>st.keltUpper && st.macdHist>0.0)
        {
         out.dir=SIG_BUY; out.confidence=conf; out.quality=0.55; out.rr=2.0;
         out.reason="Volatility breakout (Keltner up)";
        }
      else if(st.ask<st.keltLower && st.macdHist<0.0)
        {
         out.dir=SIG_SELL; out.confidence=conf; out.quality=0.55; out.rr=2.0;
         out.reason="Volatility breakout (Keltner down)";
        }
     }
  };

#endif // PERCEPTION_ENGINES_VOLATILITY_MQH
//+------------------------------------------------------------------+
