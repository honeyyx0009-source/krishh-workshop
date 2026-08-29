//+------------------------------------------------------------------+
//|                                             RegimeClassifier.mqh |
//|            001 PERCEPTION - Market regime classification          |
//|                                                                  |
//| The classifier turns the numeric SMarketState into a single      |
//| human-meaningful label plus a confidence. It is intentionally a  |
//| transparent decision tree rather than a black box: a commercial  |
//| user must be able to read the code and understand exactly why    |
//| the EA believes the market is, say, "compression" versus         |
//| "strong uptrend".                                                |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_ANALYSIS_REGIMECLASSIFIER_MQH
#define PERCEPTION_ANALYSIS_REGIMECLASSIFIER_MQH

#include <Perception/Core/Types.mqh>
#include <Perception/Core/Utils.mqh>

class CRegimeClassifier
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;

   //--- detect a fresh opening gap relative to ATR ------------------
   bool DetectGap(const double atr,double &conf)
     {
      double open0=iOpen(m_symbol,m_tf,0);
      double close1=iClose(m_symbol,m_tf,1);
      if(atr<=0.0) return false;
      double g=MathAbs(open0-close1)/atr;
      if(g>1.0){ conf=PU::Clamp(g/2.0,0.5,1.0); return true; }
      return false;
     }

   //--- detect a violent single-bar expansion (flash move) ----------
   bool DetectFlash(const double atr,double &conf)
     {
      double hi=iHigh(m_symbol,m_tf,1);
      double lo=iLow(m_symbol,m_tf,1);
      if(atr<=0.0) return false;
      double range=(hi-lo)/atr;
      if(range>2.5){ conf=PU::Clamp(range/4.0,0.6,1.0); return true; }
      return false;
     }

public:
                     CRegimeClassifier(): m_tf(PERIOD_CURRENT) {}
   void Init(const string symbol,const ENUM_TIMEFRAMES tf) { m_symbol=symbol; m_tf=tf; }

   //--- assign regime + confidence in-place --------------------------
   void Classify(SMarketState &st)
     {
      double conf=0.0;

      //--- exceptional states first (they override everything) ------
      if(DetectFlash(st.atr,conf)){ st.regime=REGIME_FLASH; st.regimeConfidence=conf; return; }
      if(DetectGap(st.atr,conf))  { st.regime=REGIME_GAP;   st.regimeConfidence=conf; return; }

      double adx=st.adx;
      double str=st.trendStrength;
      double r=st.volRatio;
      double bbw=st.bbWidth;

      //--- strong / weak trend --------------------------------------
      if(st.trend!=TREND_FLAT && adx>=25.0 && str>=0.55)
        {
         st.regime=(st.trend==TREND_UP?REGIME_STRONG_TREND_UP:REGIME_STRONG_TREND_DOWN);
         st.regimeConfidence=PU::Clamp(0.5+0.5*PU::Normalize01(adx,25,45),0.5,1.0);
         return;
        }
      if(st.trend!=TREND_FLAT && adx>=18.0)
        {
         st.regime=(st.trend==TREND_UP?REGIME_WEAK_TREND_UP:REGIME_WEAK_TREND_DOWN);
         st.regimeConfidence=PU::Clamp(0.4+0.4*PU::Normalize01(adx,18,28),0.4,0.85);
         return;
        }

      //--- volatility driven states ---------------------------------
      if(st.vol==VOL_EXTREME)
        {
         st.regime=REGIME_VOLATILE;
         st.regimeConfidence=PU::Clamp(PU::Normalize01(r,1.6,2.5),0.5,1.0);
         return;
        }
      if(r>1.25 && bbw>0.0)
        {
         st.regime=REGIME_EXPANSION;
         st.regimeConfidence=PU::Clamp(PU::Normalize01(r,1.25,1.8),0.4,0.9);
         return;
        }
      if(r<0.8 && adx<18.0)
        {
         //--- squeeze: low range + low directionality ---------------
         st.regime=(bbw<0.004?REGIME_COMPRESSION:REGIME_CALM);
         st.regimeConfidence=PU::Clamp(1.0-PU::Normalize01(r,0.5,0.9),0.4,0.9);
         return;
        }

      //--- default oscillation --------------------------------------
      if(adx<16.0)
        {
         st.regime=REGIME_SIDEWAYS;
         st.regimeConfidence=PU::Clamp(1.0-PU::Normalize01(adx,8,18),0.4,0.85);
        }
      else
        {
         st.regime=REGIME_RANGE;
         st.regimeConfidence=0.5;
        }
     }
  };

#endif // PERCEPTION_ANALYSIS_REGIMECLASSIFIER_MQH
//+------------------------------------------------------------------+
