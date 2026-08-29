//+------------------------------------------------------------------+
//|                                                     FVGEngine.mqh |
//|             001 PERCEPTION - Fair Value Gap engine                |
//|                                                                  |
//| A fair value gap is a three-candle imbalance where the wicks do  |
//| not overlap, leaving an unfilled price void. Markets frequently  |
//| revisit these voids; this engine trades the fill in the          |
//| direction of the prevailing trend.                               |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_ENGINES_FVG_MQH
#define PERCEPTION_ENGINES_FVG_MQH

#include <Perception/Engines/IEngine.mqh>

class CFVGEngine : public CEngine
  {
private:
   int m_scan;
public:
   CFVGEngine() { m_id=ENG_FVG; m_name="FVG"; m_scan=30; }

   double Suitability(const SMarketState &st) override
     {
      switch(st.regime)
        {
         case REGIME_WEAK_TREND_UP:
         case REGIME_WEAK_TREND_DOWN:   return 0.70;
         case REGIME_STRONG_TREND_UP:
         case REGIME_STRONG_TREND_DOWN: return 0.72;
         case REGIME_EXPANSION:         return 0.55;
         default:                       return 0.25;
        }
     }

   void Evaluate(const SMarketState &st,CSymbolMeta *sym,const SConfig &cfg,SSignal &out) override
     {
      out.Reset(); out.engine=m_id;
      double atr=st.atr; if(atr<=0.0) return;
      MqlRates r[]; ArraySetAsSeries(r,true);
      int n=CopyRates(m_symbol,m_tf,0,m_scan,r);
      if(n<6) return;
      double price=st.mid;

      //--- three-candle window: r[i] newest of triple, r[i+2] oldest -
      for(int i=1;i<n-3;i++)
        {
         //--- bullish FVG: gap between candle3.high and candle1.low --
         double gLo=r[i+2].high, gHi=r[i].low;
         if(gHi>gLo && (gHi-gLo)>0.4*atr && st.trend==TREND_UP)
           {
            if(price>=gLo && price<=gHi)
              {
               out.dir=SIG_BUY; out.confidence=0.6; out.quality=0.55; out.rr=1.8;
               out.sl=sym.NormalizePrice(gLo-0.5*atr);
               out.reason="Bullish FVG fill";
               return;
              }
           }
         //--- bearish FVG: gap between candle1.high and candle3.low --
         double bHi=r[i+2].low, bLo=r[i].high;
         if(bHi>bLo && (bHi-bLo)>0.4*atr && st.trend==TREND_DOWN)
           {
            if(price>=bLo && price<=bHi)
              {
               out.dir=SIG_SELL; out.confidence=0.6; out.quality=0.55; out.rr=1.8;
               out.sl=sym.NormalizePrice(bHi+0.5*atr);
               out.reason="Bearish FVG fill";
               return;
              }
           }
        }
     }
  };

#endif // PERCEPTION_ENGINES_FVG_MQH
//+------------------------------------------------------------------+
