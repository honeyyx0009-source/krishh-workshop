//+------------------------------------------------------------------+
//|                                            SupplyDemandEngine.mqh |
//|             001 PERCEPTION - Supply / demand zone engine          |
//|                                                                  |
//| Identifies a tight "base" of candles that precedes an impulsive  |
//| departure - the classic supply or demand zone - and trades       |
//| price's first return to that base.                               |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_ENGINES_SUPPLYDEMAND_MQH
#define PERCEPTION_ENGINES_SUPPLYDEMAND_MQH

#include <Perception/Engines/IEngine.mqh>

class CSupplyDemandEngine : public CEngine
  {
private:
   int m_scan;
public:
   CSupplyDemandEngine() { m_id=ENG_SUPPLY_DEMAND; m_name="SupplyDem"; m_scan=40; }

   double Suitability(const SMarketState &st) override
     {
      switch(st.regime)
        {
         case REGIME_WEAK_TREND_UP:
         case REGIME_WEAK_TREND_DOWN: return 0.70;
         case REGIME_RANGE:           return 0.62;
         case REGIME_COMPRESSION:     return 0.58;
         default:                     return 0.25;
        }
     }

   void Evaluate(const SMarketState &st,CSymbolMeta *sym,const SConfig &cfg,SSignal &out) override
     {
      out.Reset(); out.engine=m_id;
      double atr=st.atr; if(atr<=0.0) return;
      MqlRates r[]; ArraySetAsSeries(r,true);
      int n=CopyRates(m_symbol,m_tf,0,m_scan,r);
      if(n<8) return;
      double price=st.mid;

      //--- look for base (2 small bars) + impulse -------------------
      for(int i=2;i<n-3;i++)
        {
         double baseHi=MathMax(r[i].high,r[i+1].high);
         double baseLo=MathMin(r[i].low,r[i+1].low);
         double baseRange=baseHi-baseLo;
         if(baseRange<=0.0 || baseRange>0.9*atr) continue;     // not tight enough

         //--- demand: impulse up leaving the base -------------------
         if(r[i-1].close-baseHi>1.3*atr && st.trend!=TREND_DOWN)
           {
            if(price>=baseLo && price<=baseHi)
              {
               out.dir=SIG_BUY; out.confidence=0.6; out.quality=0.55; out.rr=2.0;
               out.sl=sym.NormalizePrice(baseLo-0.5*atr);
               out.reason="Demand zone retest";
               return;
              }
           }
         //--- supply: impulse down leaving the base -----------------
         if(baseLo-r[i-1].close>1.3*atr && st.trend!=TREND_UP)
           {
            if(price>=baseLo && price<=baseHi)
              {
               out.dir=SIG_SELL; out.confidence=0.6; out.quality=0.55; out.rr=2.0;
               out.sl=sym.NormalizePrice(baseHi+0.5*atr);
               out.reason="Supply zone retest";
               return;
              }
           }
        }
     }
  };

#endif // PERCEPTION_ENGINES_SUPPLYDEMAND_MQH
//+------------------------------------------------------------------+
