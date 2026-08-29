//+------------------------------------------------------------------+
//|                                           LiquidityGrabEngine.mqh |
//|             001 PERCEPTION - Liquidity grab / stop-run engine     |
//|                                                                  |
//| Price often spikes just beyond an obvious swing to trigger a     |
//| cluster of stop orders, then reverses. This engine detects that  |
//| failed break (a wick beyond the swing that closes back inside)   |
//| and fades it.                                                    |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_ENGINES_LIQUIDITYGRAB_MQH
#define PERCEPTION_ENGINES_LIQUIDITYGRAB_MQH

#include <Perception/Engines/IEngine.mqh>

class CLiquidityGrabEngine : public CEngine
  {
public:
   CLiquidityGrabEngine() { m_id=ENG_LIQUIDITY_GRAB; m_name="LiqGrab"; }

   double Suitability(const SMarketState &st) override
     {
      switch(st.regime)
        {
         case REGIME_RANGE:    return 0.72;
         case REGIME_SIDEWAYS: return 0.65;
         case REGIME_VOLATILE: return 0.55;
         case REGIME_WEAK_TREND_UP:
         case REGIME_WEAK_TREND_DOWN: return 0.50;
         default:              return 0.25;
        }
     }

   void Evaluate(const SMarketState &st,CSymbolMeta *sym,const SConfig &cfg,SSignal &out) override
     {
      out.Reset(); out.engine=m_id;
      double atr=st.atr; if(atr<=0.0) return;
      double hi1=iHigh(m_symbol,m_tf,1);
      double lo1=iLow(m_symbol,m_tf,1);
      double cl1=iClose(m_symbol,m_tf,1);

      //--- buy-side liquidity grab above swing high -> fade short ----
      if(st.swingHigh>0.0 && hi1>st.swingHigh && cl1<st.swingHigh)
        {
         out.dir=SIG_SELL; out.confidence=0.6; out.quality=0.55; out.rr=1.6;
         out.sl=sym.NormalizePrice(hi1+0.3*atr);
         out.reason="Liquidity grab above highs";
        }
      //--- sell-side liquidity grab below swing low -> fade long -----
      else if(st.swingLow>0.0 && lo1<st.swingLow && cl1>st.swingLow)
        {
         out.dir=SIG_BUY; out.confidence=0.6; out.quality=0.55; out.rr=1.6;
         out.sl=sym.NormalizePrice(lo1-0.3*atr);
         out.reason="Liquidity grab below lows";
        }
     }
  };

#endif // PERCEPTION_ENGINES_LIQUIDITYGRAB_MQH
//+------------------------------------------------------------------+
