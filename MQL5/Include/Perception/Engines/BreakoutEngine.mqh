//+------------------------------------------------------------------+
//|                                                BreakoutEngine.mqh |
//|             001 PERCEPTION - Breakout engine                      |
//|                                                                  |
//| Trades genuine Donchian breakouts confirmed by a volatility      |
//| expansion. It is most valuable exactly when range engines are    |
//| worst: as compression resolves into a new directional leg.       |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_ENGINES_BREAKOUT_MQH
#define PERCEPTION_ENGINES_BREAKOUT_MQH

#include <Perception/Engines/IEngine.mqh>

class CBreakoutEngine : public CEngine
  {
public:
   CBreakoutEngine() { m_id=ENG_BREAKOUT; m_name="Breakout"; }

   double Suitability(const SMarketState &st) override
     {
      switch(st.regime)
        {
         case REGIME_COMPRESSION: return 0.88;
         case REGIME_EXPANSION:   return 0.82;
         case REGIME_CALM:        return 0.55;
         case REGIME_RANGE:       return 0.45;
         default:                 return 0.20;
        }
     }

   void Evaluate(const SMarketState &st,CSymbolMeta *sym,const SConfig &cfg,SSignal &out) override
     {
      out.Reset(); out.engine=m_id;
      double atr=st.atr; if(atr<=0.0) return;
      bool expanding=(st.volRatio>1.0);
      double conf=PU::Clamp(0.35+0.35*PU::Normalize01(st.volRatio,1.0,1.8)+0.15*st.mtfAlignment,0.0,1.0);

      if(st.bid>st.donchUpper && expanding)
        {
         out.dir=SIG_BUY; out.confidence=conf; out.quality=0.6; out.rr=2.2;
         out.sl=sym.NormalizePrice(st.donchUpper-1.0*atr);
         out.reason="Breakout above range high";
        }
      else if(st.ask<st.donchLower && expanding)
        {
         out.dir=SIG_SELL; out.confidence=conf; out.quality=0.6; out.rr=2.2;
         out.sl=sym.NormalizePrice(st.donchLower+1.0*atr);
         out.reason="Breakout below range low";
        }
     }
  };

#endif // PERCEPTION_ENGINES_BREAKOUT_MQH
//+------------------------------------------------------------------+
