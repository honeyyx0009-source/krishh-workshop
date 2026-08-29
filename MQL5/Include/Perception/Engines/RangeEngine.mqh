//+------------------------------------------------------------------+
//|                                                   RangeEngine.mqh |
//|             001 PERCEPTION - Range trading engine                 |
//|                                                                  |
//| Fades the edges of a Bollinger channel while the market lacks    |
//| directional conviction, targeting the mean. It refuses to trade  |
//| when ADX indicates a genuine trend is underway.                  |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_ENGINES_RANGE_MQH
#define PERCEPTION_ENGINES_RANGE_MQH

#include <Perception/Engines/IEngine.mqh>

class CRangeEngine : public CEngine
  {
public:
   CRangeEngine() { m_id=ENG_RANGE; m_name="Range"; }

   double Suitability(const SMarketState &st) override
     {
      switch(st.regime)
        {
         case REGIME_RANGE:    return 0.90;
         case REGIME_SIDEWAYS: return 0.85;
         case REGIME_CALM:     return 0.70;
         case REGIME_COMPRESSION: return 0.55;
         default:              return 0.10;
        }
     }

   void Evaluate(const SMarketState &st,CSymbolMeta *sym,const SConfig &cfg,SSignal &out) override
     {
      out.Reset(); out.engine=m_id;
      if(st.adx>24.0) return;                          // real trend -> stand down
      double atr=st.atr;
      double conf=PU::Clamp(0.35+0.45*(1.0-PU::Normalize01(st.adx,10,24)),0.0,1.0);

      if(st.bid<=st.bbLower && st.rsi<35.0)
        {
         out.dir=SIG_BUY; out.confidence=conf; out.quality=0.5;
         out.sl=sym.NormalizePrice(st.bbLower-1.0*atr);
         out.tp=sym.NormalizePrice(st.bbMid);
         out.reason="Range buy at lower band";
        }
      else if(st.ask>=st.bbUpper && st.rsi>65.0)
        {
         out.dir=SIG_SELL; out.confidence=conf; out.quality=0.5;
         out.sl=sym.NormalizePrice(st.bbUpper+1.0*atr);
         out.tp=sym.NormalizePrice(st.bbMid);
         out.reason="Range sell at upper band";
        }
     }
  };

#endif // PERCEPTION_ENGINES_RANGE_MQH
//+------------------------------------------------------------------+
