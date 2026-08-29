//+------------------------------------------------------------------+
//|                                                RecoveryEngine.mqh |
//|             001 PERCEPTION - Recovery engine (opt-in)             |
//|                                                                  |
//| A safer sibling of the martingale. After a loss it looks for a   |
//| single, high-quality, trend-aligned re-entry at NORMAL size but  |
//| with a larger target, aiming to recoup the prior loss without    |
//| inflating exposure. Disabled by default.                         |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_ENGINES_RECOVERY_MQH
#define PERCEPTION_ENGINES_RECOVERY_MQH

#include <Perception/Engines/IEngine.mqh>

class CRecoveryEngine : public CEngine
  {
public:
   CRecoveryEngine() { m_id=ENG_RECOVERY; m_name="Recovery"; m_enabled=false; }

   double Suitability(const SMarketState &st) override
     {
      if(m_stats.lossStreak<=0) return 0.05;
      switch(st.regime)
        {
         case REGIME_STRONG_TREND_UP:
         case REGIME_STRONG_TREND_DOWN: return 0.60;
         case REGIME_WEAK_TREND_UP:
         case REGIME_WEAK_TREND_DOWN:   return 0.50;
         default:                       return 0.25;
        }
     }

   void Evaluate(const SMarketState &st,CSymbolMeta *sym,const SConfig &cfg,SSignal &out) override
     {
      out.Reset(); out.engine=m_id;
      if(OwnCount()>0) return;
      if(m_stats.lossStreak<=0) return;
      ENUM_SIGNAL_DIR dir=(st.trend==TREND_UP?SIG_BUY:(st.trend==TREND_DOWN?SIG_SELL:SIG_NONE));
      if(dir==SIG_NONE) return;
      if(st.trendStrength<0.5) return;                   // demand a clean trend
      if(!MTFConfirms(st,dir,cfg)) return;

      out.dir=dir; out.confidence=0.55; out.quality=0.5;
      out.rr=2.5;                                        // recoup with a wider target
      out.reason="Recovery re-entry (normal size)";
     }
  };

#endif // PERCEPTION_ENGINES_RECOVERY_MQH
//+------------------------------------------------------------------+
