//+------------------------------------------------------------------+
//|                                              MartingaleEngine.mqh |
//|             001 PERCEPTION - Controlled martingale (opt-in)       |
//|                                                                  |
//| A tightly capped martingale. After a losing trade it re-enters   |
//| in the direction of the prevailing trend with a modestly larger  |
//| size, but the multiplier is bounded and margin still governs the |
//| final volume. Disabled by default - this is a recovery tool, not |
//| a core strategy, and it must be used with eyes open.             |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_ENGINES_MARTINGALE_MQH
#define PERCEPTION_ENGINES_MARTINGALE_MQH

#include <Perception/Engines/IEngine.mqh>

class CMartingaleEngine : public CEngine
  {
public:
   CMartingaleEngine() { m_id=ENG_MARTINGALE; m_name="Martingale"; m_enabled=false; }

   double Suitability(const SMarketState &st) override
     {
      if(m_stats.lossStreak<=0) return 0.05;             // only relevant after a loss
      switch(st.regime)
        {
         case REGIME_STRONG_TREND_UP:
         case REGIME_STRONG_TREND_DOWN:
         case REGIME_WEAK_TREND_UP:
         case REGIME_WEAK_TREND_DOWN: return 0.55;
         default:                     return 0.20;
        }
     }

   void Evaluate(const SMarketState &st,CSymbolMeta *sym,const SConfig &cfg,SSignal &out) override
     {
      out.Reset(); out.engine=m_id;
      if(OwnCount()>0) return;                           // one recovery trade at a time
      if(m_stats.lossStreak<=0) return;
      ENUM_SIGNAL_DIR dir=(st.trend==TREND_UP?SIG_BUY:(st.trend==TREND_DOWN?SIG_SELL:SIG_NONE));
      if(dir==SIG_NONE) return;
      if(!MTFConfirms(st,dir,cfg)) return;

      int capped=(int)MathMin(m_stats.lossStreak,4);
      double mult=MathPow(1.6,capped);
      out.dir=dir;
      out.lots=sym.NormalizeLots(sym.VolMin()*mult);
      out.confidence=0.5; out.quality=0.4; out.rr=1.5;
      out.reason=StringFormat("Martingale recovery x%.2f (streak %d)",mult,m_stats.lossStreak);
     }
  };

#endif // PERCEPTION_ENGINES_MARTINGALE_MQH
//+------------------------------------------------------------------+
