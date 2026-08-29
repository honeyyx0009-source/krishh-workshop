//+------------------------------------------------------------------+
//|                                                MomentumEngine.mqh |
//|             001 PERCEPTION - Momentum engine                      |
//|                                                                  |
//| Rides strong directional bursts: it wants MACD and RSI pushing   |
//| the same way while the market is expanding, and it deliberately  |
//| stands down in quiet, mean-reverting conditions.                 |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_ENGINES_MOMENTUM_MQH
#define PERCEPTION_ENGINES_MOMENTUM_MQH

#include <Perception/Engines/IEngine.mqh>

class CMomentumEngine : public CEngine
  {
public:
   CMomentumEngine() { m_id=ENG_MOMENTUM; m_name="Momentum"; }

   double Suitability(const SMarketState &st) override
     {
      switch(st.regime)
        {
         case REGIME_STRONG_TREND_UP:
         case REGIME_STRONG_TREND_DOWN: return 0.85;
         case REGIME_EXPANSION:         return 0.80;
         case REGIME_VOLATILE:          return 0.50;
         default:                       return 0.15;
        }
     }

   void Evaluate(const SMarketState &st,CSymbolMeta *sym,const SConfig &cfg,SSignal &out) override
     {
      out.Reset(); out.engine=m_id;
      double conf=PU::Clamp(0.30+0.50*PU::Normalize01(st.adx,18,40)+0.20*st.mtfAlignment,0.0,1.0);

      bool bullMom=(st.macdHist>0.0 && st.rsi>55.0 && st.plusDI>st.minusDI);
      bool bearMom=(st.macdHist<0.0 && st.rsi<45.0 && st.minusDI>st.plusDI);

      if(bullMom && st.trend!=TREND_DOWN)
        {
         if(!MTFConfirms(st,SIG_BUY,cfg)) return;
         out.dir=SIG_BUY; out.confidence=conf; out.quality=0.55; out.rr=1.8;
         out.reason=StringFormat("Bull momentum (RSI %.0f, +DI %.0f)",st.rsi,st.plusDI);
        }
      else if(bearMom && st.trend!=TREND_UP)
        {
         if(!MTFConfirms(st,SIG_SELL,cfg)) return;
         out.dir=SIG_SELL; out.confidence=conf; out.quality=0.55; out.rr=1.8;
         out.reason=StringFormat("Bear momentum (RSI %.0f, -DI %.0f)",st.rsi,st.minusDI);
        }
     }
  };

#endif // PERCEPTION_ENGINES_MOMENTUM_MQH
//+------------------------------------------------------------------+
