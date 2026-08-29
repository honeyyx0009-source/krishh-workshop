//+------------------------------------------------------------------+
//|                                                   TrendEngine.mqh |
//|             001 PERCEPTION - Trend following engine               |
//|                                                                  |
//| Buys pullbacks inside an established uptrend (and mirrors for     |
//| downtrends). It leans on EMA stack + MACD momentum + RSI not      |
//| being exhausted, and requires higher-timeframe agreement when     |
//| MTF confirmation is enabled.                                     |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_ENGINES_TREND_MQH
#define PERCEPTION_ENGINES_TREND_MQH

#include <Perception/Engines/IEngine.mqh>

class CTrendEngine : public CEngine
  {
public:
   CTrendEngine() { m_id=ENG_TREND; m_name="Trend"; }

   double Suitability(const SMarketState &st) override
     {
      switch(st.regime)
        {
         case REGIME_STRONG_TREND_UP:
         case REGIME_STRONG_TREND_DOWN: return 0.92;
         case REGIME_WEAK_TREND_UP:
         case REGIME_WEAK_TREND_DOWN:   return 0.70;
         case REGIME_EXPANSION:         return 0.55;
         default:                       return 0.15;
        }
     }

   void Evaluate(const SMarketState &st,CSymbolMeta *sym,const SConfig &cfg,SSignal &out) override
     {
      out.Reset(); out.engine=m_id;
      double conf=PU::Clamp(0.35+0.45*st.trendStrength+0.20*st.mtfAlignment,0.0,1.0);

      if(st.trend==TREND_UP && st.macdMain>st.macdSignal && st.rsi>48.0 && st.rsi<72.0 &&
         st.mid>st.emaSlow)
        {
         if(!MTFConfirms(st,SIG_BUY,cfg)) return;
         out.dir=SIG_BUY; out.confidence=conf; out.quality=st.mtfAlignment; out.rr=2.0;
         out.reason=StringFormat("Uptrend pullback (ADX %.0f, MTF %.0f%%)",st.adx,st.mtfAlignment*100);
        }
      else if(st.trend==TREND_DOWN && st.macdMain<st.macdSignal && st.rsi<52.0 && st.rsi>28.0 &&
              st.mid<st.emaSlow)
        {
         if(!MTFConfirms(st,SIG_SELL,cfg)) return;
         out.dir=SIG_SELL; out.confidence=conf; out.quality=st.mtfAlignment; out.rr=2.0;
         out.reason=StringFormat("Downtrend pullback (ADX %.0f, MTF %.0f%%)",st.adx,st.mtfAlignment*100);
        }
     }
  };

#endif // PERCEPTION_ENGINES_TREND_MQH
//+------------------------------------------------------------------+
