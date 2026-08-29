//+------------------------------------------------------------------+
//|                                                 SessionEngine.mqh |
//|             001 PERCEPTION - Session breakout engine              |
//|                                                                  |
//| Many instruments make their decisive move as London or New York  |
//| comes online. This engine only arms during those sessions and    |
//| joins a fresh Donchian break, deferring to the calmer engines    |
//| during the Asian lull.                                           |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_ENGINES_SESSION_MQH
#define PERCEPTION_ENGINES_SESSION_MQH

#include <Perception/Engines/IEngine.mqh>

class CSessionEngine : public CEngine
  {
public:
   CSessionEngine() { m_id=ENG_SESSION; m_name="Session"; }

   double Suitability(const SMarketState &st) override
     {
      if(st.sessionLondon || st.sessionNY) return 0.65;
      if(st.sessionAsia)                    return 0.30;
      return 0.20;
     }

   void Evaluate(const SMarketState &st,CSymbolMeta *sym,const SConfig &cfg,SSignal &out) override
     {
      out.Reset(); out.engine=m_id;
      if(!(st.sessionLondon || st.sessionNY)) return;
      double atr=st.atr; if(atr<=0.0) return;
      double conf=PU::Clamp(0.40+0.25*st.mtfAlignment+0.15*PU::Normalize01(st.volRatio,0.9,1.6),0.0,0.9);

      if(st.bid>st.donchUpper)
        {
         out.dir=SIG_BUY; out.confidence=conf; out.quality=0.5; out.rr=1.8;
         out.reason="Session breakout long";
        }
      else if(st.ask<st.donchLower)
        {
         out.dir=SIG_SELL; out.confidence=conf; out.quality=0.5; out.rr=1.8;
         out.reason="Session breakout short";
        }
     }
  };

#endif // PERCEPTION_ENGINES_SESSION_MQH
//+------------------------------------------------------------------+
