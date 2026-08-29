//+------------------------------------------------------------------+
//|                                              OrderBlockEngine.mqh |
//|             001 PERCEPTION - Order block (SMC) engine             |
//|                                                                  |
//| An order block is the last opposing candle before an impulsive   |
//| move that breaks structure - the footprint of institutional      |
//| activity. This engine scans recent candles for the most recent   |
//| valid block and trades price's return into that zone.            |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_ENGINES_ORDERBLOCK_MQH
#define PERCEPTION_ENGINES_ORDERBLOCK_MQH

#include <Perception/Engines/IEngine.mqh>

class COrderBlockEngine : public CEngine
  {
private:
   int m_scan;
public:
   COrderBlockEngine() { m_id=ENG_ORDER_BLOCK; m_name="OrderBlock"; m_scan=30; }

   double Suitability(const SMarketState &st) override
     {
      switch(st.regime)
        {
         case REGIME_WEAK_TREND_UP:
         case REGIME_WEAK_TREND_DOWN:   return 0.75;
         case REGIME_STRONG_TREND_UP:
         case REGIME_STRONG_TREND_DOWN: return 0.70;
         case REGIME_RANGE:             return 0.45;
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

      //--- most recent bullish order block --------------------------
      for(int i=2;i<n-2;i++)
        {
         bool bearish=(r[i].close<r[i].open);
         bool impulse=(r[i-1].close>r[i-1].open) && (r[i-1].close-r[i].low>1.2*atr) &&
                      (r[i-1].close>r[i].high);
         if(bearish && impulse)
           {
            double lo=r[i].low, hi=r[i].high;
            if(price>=lo && price<=hi && st.trend!=TREND_DOWN)
              {
               out.dir=SIG_BUY; out.confidence=0.62; out.quality=0.6; out.rr=2.0;
               out.sl=sym.NormalizePrice(lo-0.5*atr);
               out.reason="Bullish order block retest";
              }
            break;
           }
        }
      if(out.IsValid()) return;

      //--- most recent bearish order block --------------------------
      for(int i=2;i<n-2;i++)
        {
         bool bullish=(r[i].close>r[i].open);
         bool impulse=(r[i-1].close<r[i-1].open) && (r[i].high-r[i-1].close>1.2*atr) &&
                      (r[i-1].close<r[i].low);
         if(bullish && impulse)
           {
            double lo=r[i].low, hi=r[i].high;
            if(price>=lo && price<=hi && st.trend!=TREND_UP)
              {
               out.dir=SIG_SELL; out.confidence=0.62; out.quality=0.6; out.rr=2.0;
               out.sl=sym.NormalizePrice(hi+0.5*atr);
               out.reason="Bearish order block retest";
              }
            break;
           }
        }
     }
  };

#endif // PERCEPTION_ENGINES_ORDERBLOCK_MQH
//+------------------------------------------------------------------+
