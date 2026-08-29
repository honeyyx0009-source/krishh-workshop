//+------------------------------------------------------------------+
//|                                              MarketStructure.mqh |
//|             001 PERCEPTION - Price structure analysis             |
//|                                                                  |
//| Indicators describe momentum; structure describes intent. This   |
//| module walks recent swing points to decide whether price is      |
//| carving higher-highs / higher-lows (bullish structure) or the    |
//| mirror image, and it exposes the nearest structural support and  |
//| resistance so engines can anchor stops and targets to real       |
//| levels rather than arbitrary distances.                          |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_ANALYSIS_MARKETSTRUCTURE_MQH
#define PERCEPTION_ANALYSIS_MARKETSTRUCTURE_MQH

#include <Perception/Core/Types.mqh>

class CMarketStructure
  {
private:
   int    m_half;      // fractal half-window
   int    m_lookback;  // bars to scan

public:
                     CMarketStructure(): m_half(2), m_lookback(150) {}
   void SetParams(const int half,const int lookback) { m_half=half; m_lookback=lookback; }

   //--- fill the structural portion of a market state ----------------
   bool Analyze(const string symbol,const ENUM_TIMEFRAMES tf,SMarketState &st)
     {
      int n=m_lookback;
      double hi[],lo[];
      ArraySetAsSeries(hi,true); ArraySetAsSeries(lo,true);
      if(CopyHigh(symbol,tf,0,n,hi)<n) return false;
      if(CopyLow(symbol,tf,0,n,lo)<n)  return false;

      double price=0.5*(hi[0]+lo[0]);

      //--- collect swing highs / lows, most recent first ------------
      double swH[]; double swL[];
      ArrayResize(swH,0); ArrayResize(swL,0);
      for(int i=m_half;i<n-m_half;i++)
        {
         bool isHigh=true, isLow=true;
         for(int k=1;k<=m_half;k++)
           {
            if(hi[i]<hi[i-k] || hi[i]<hi[i+k]) isHigh=false;
            if(lo[i]>lo[i-k] || lo[i]>lo[i+k]) isLow=false;
           }
         if(isHigh){ int s=ArraySize(swH); ArrayResize(swH,s+1); swH[s]=hi[i]; }
         if(isLow) { int s=ArraySize(swL); ArrayResize(swL,s+1); swL[s]=lo[i]; }
        }

      st.madeHH=st.madeHL=st.madeLH=st.madeLL=false;
      st.swingHigh=(ArraySize(swH)>0?swH[0]:hi[0]);
      st.swingLow =(ArraySize(swL)>0?swL[0]:lo[0]);

      if(ArraySize(swH)>=2)
        {
         if(swH[0]>swH[1]) st.madeHH=true; else st.madeLH=true;
        }
      if(ArraySize(swL)>=2)
        {
         if(swL[0]>swL[1]) st.madeHL=true; else st.madeLL=true;
        }

      //--- structural bias ------------------------------------------
      if(st.madeHH && st.madeHL)      st.structureBias=TREND_UP;
      else if(st.madeLH && st.madeLL) st.structureBias=TREND_DOWN;
      else                            st.structureBias=TREND_FLAT;

      //--- nearest resistance above / support below current price ---
      double res=0.0, sup=0.0;
      for(int i=0;i<ArraySize(swH);i++)
         if(swH[i]>price){ res=swH[i]; break; }
      for(int i=0;i<ArraySize(swL);i++)
         if(swL[i]<price){ sup=swL[i]; break; }
      st.nearestResistance=(res>0.0?res:st.swingHigh);
      st.nearestSupport   =(sup>0.0?sup:st.swingLow);
      return true;
     }
  };

#endif // PERCEPTION_ANALYSIS_MARKETSTRUCTURE_MQH
//+------------------------------------------------------------------+
