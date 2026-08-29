//+------------------------------------------------------------------+
//|                                                   SwingEngine.mqh |
//|             001 PERCEPTION - Swing trading engine                 |
//|                                                                  |
//| Trades with the structural bias, entering as price returns to a  |
//| higher-low (uptrend) or lower-high (downtrend). Targets are       |
//| anchored to the nearest structural level so the reward-to-risk    |
//| reflects real swing geometry.                                    |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_ENGINES_SWING_MQH
#define PERCEPTION_ENGINES_SWING_MQH

#include <Perception/Engines/IEngine.mqh>

class CSwingEngine : public CEngine
  {
public:
   CSwingEngine() { m_id=ENG_SWING; m_name="Swing"; }

   double Suitability(const SMarketState &st) override
     {
      switch(st.regime)
        {
         case REGIME_WEAK_TREND_UP:
         case REGIME_WEAK_TREND_DOWN:   return 0.80;
         case REGIME_STRONG_TREND_UP:
         case REGIME_STRONG_TREND_DOWN: return 0.65;
         case REGIME_RANGE:             return 0.45;
         default:                       return 0.20;
        }
     }

   void Evaluate(const SMarketState &st,CSymbolMeta *sym,const SConfig &cfg,SSignal &out) override
     {
      out.Reset(); out.engine=m_id;
      double conf=PU::Clamp(0.30+0.40*st.trendStrength+0.30*st.mtfAlignment,0.0,1.0);
      double atr=st.atr;

      if(st.structureBias==TREND_UP && st.madeHL && st.rsi>45.0 && st.stochMain<70.0)
        {
         if(!MTFConfirms(st,SIG_BUY,cfg)) return;
         out.dir=SIG_BUY; out.confidence=conf; out.quality=0.6;
         out.sl=sym.NormalizePrice(st.swingLow-0.5*atr);
         out.tp=sym.NormalizePrice(st.nearestResistance);
         out.reason="Swing long from higher-low";
        }
      else if(st.structureBias==TREND_DOWN && st.madeLH && st.rsi<55.0 && st.stochMain>30.0)
        {
         if(!MTFConfirms(st,SIG_SELL,cfg)) return;
         out.dir=SIG_SELL; out.confidence=conf; out.quality=0.6;
         out.sl=sym.NormalizePrice(st.swingHigh+0.5*atr);
         out.tp=sym.NormalizePrice(st.nearestSupport);
         out.reason="Swing short from lower-high";
        }
     }
  };

#endif // PERCEPTION_ENGINES_SWING_MQH
//+------------------------------------------------------------------+
