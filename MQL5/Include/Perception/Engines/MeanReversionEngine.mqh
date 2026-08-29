//+------------------------------------------------------------------+
//|                                            MeanReversionEngine.mqh|
//|             001 PERCEPTION - Mean reversion engine                |
//|                                                                  |
//| Trades statistical stretch away from VWAP / the moving average.  |
//| When price is far from fair value and the oscillators are        |
//| exhausted, it bets on a snap back toward the mean.               |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_ENGINES_MEANREVERSION_MQH
#define PERCEPTION_ENGINES_MEANREVERSION_MQH

#include <Perception/Engines/IEngine.mqh>

class CMeanReversionEngine : public CEngine
  {
public:
   CMeanReversionEngine() { m_id=ENG_MEAN_REVERSION; m_name="MeanRev"; }

   double Suitability(const SMarketState &st) override
     {
      switch(st.regime)
        {
         case REGIME_CALM:     return 0.85;
         case REGIME_RANGE:    return 0.80;
         case REGIME_SIDEWAYS: return 0.75;
         case REGIME_VOLATILE: return 0.30;
         default:              return 0.15;
        }
     }

   void Evaluate(const SMarketState &st,CSymbolMeta *sym,const SConfig &cfg,SSignal &out) override
     {
      out.Reset(); out.engine=m_id;
      double atr=st.atr; if(atr<=0.0) return;
      double ref=(st.vwap>0.0?st.vwap:st.sma);
      double stretch=(ref>0.0?(st.mid-ref)/atr:0.0);   // in ATR units
      double conf=PU::Clamp(0.30+0.15*MathAbs(stretch),0.0,0.95);

      if(stretch<=-1.8 && st.rsi<32.0 && st.cci<-120.0)
        {
         out.dir=SIG_BUY; out.confidence=conf; out.quality=PU::Clamp(MathAbs(stretch)/3.0,0,1);
         out.tp=sym.NormalizePrice(ref); out.rr=1.5;
         out.reason=StringFormat("Reversion buy (%.1f ATR below fair value)",MathAbs(stretch));
        }
      else if(stretch>=1.8 && st.rsi>68.0 && st.cci>120.0)
        {
         out.dir=SIG_SELL; out.confidence=conf; out.quality=PU::Clamp(MathAbs(stretch)/3.0,0,1);
         out.tp=sym.NormalizePrice(ref); out.rr=1.5;
         out.reason=StringFormat("Reversion sell (%.1f ATR above fair value)",stretch);
        }
     }
  };

#endif // PERCEPTION_ENGINES_MEANREVERSION_MQH
//+------------------------------------------------------------------+
