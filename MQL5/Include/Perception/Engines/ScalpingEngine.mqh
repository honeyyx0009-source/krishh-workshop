//+------------------------------------------------------------------+
//|                                                ScalpingEngine.mqh |
//|             001 PERCEPTION - Scalping engine                      |
//|                                                                  |
//| Short-horizon trades that only make sense when the spread is     |
//| tight and volatility is orderly. Uses a stochastic turn in the   |
//| direction of the fast EMA for a quick, low reward-to-risk grab.  |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_ENGINES_SCALPING_MQH
#define PERCEPTION_ENGINES_SCALPING_MQH

#include <Perception/Engines/IEngine.mqh>

class CScalpingEngine : public CEngine
  {
public:
   CScalpingEngine() { m_id=ENG_SCALPING; m_name="Scalp"; }

   double Suitability(const SMarketState &st) override
     {
      //--- scalping hates wide spreads and chaos --------------------
      double base;
      switch(st.regime)
        {
         case REGIME_CALM:     base=0.80; break;
         case REGIME_SIDEWAYS: base=0.70; break;
         case REGIME_WEAK_TREND_UP:
         case REGIME_WEAK_TREND_DOWN: base=0.60; break;
         case REGIME_VOLATILE:
         case REGIME_FLASH:    base=0.05; break;
         default:              base=0.35; break;
        }
      return base;
     }

   void Evaluate(const SMarketState &st,CSymbolMeta *sym,const SConfig &cfg,SSignal &out) override
     {
      out.Reset(); out.engine=m_id;
      double spreadAtrPts=PU::SafeDiv(st.spreadPts,(st.atr/sym.Point()),1.0);
      if(spreadAtrPts>0.12) return;                    // spread too rich for scalps
      double conf=PU::Clamp(0.35+0.30*(1.0-spreadAtrPts*5.0),0.0,0.9);

      bool bull=(st.emaFast>st.emaSlow && st.stochMain>st.stochSignal && st.stochMain<40.0);
      bool bear=(st.emaFast<st.emaSlow && st.stochMain<st.stochSignal && st.stochMain>60.0);

      if(bull)
        {
         out.dir=SIG_BUY; out.confidence=conf; out.quality=0.4; out.rr=1.1;
         out.reason="Scalp long (stoch turn up)";
        }
      else if(bear)
        {
         out.dir=SIG_SELL; out.confidence=conf; out.quality=0.4; out.rr=1.1;
         out.reason="Scalp short (stoch turn down)";
        }
     }
  };

#endif // PERCEPTION_ENGINES_SCALPING_MQH
//+------------------------------------------------------------------+
