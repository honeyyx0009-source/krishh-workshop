//+------------------------------------------------------------------+
//|                                                     AIEngine.mqh |
//|          001 PERCEPTION - Internal AI decision engine             |
//|                                                                  |
//| This is the "brain". It is deliberately a transparent, self-      |
//| contained model - no external API, no opaque neural net - so a   |
//| commercial user can audit every decision. Its job is fourfold:   |
//|   1. turn a raw engine signal into a calibrated probability;     |
//|   2. weight that probability by how much the engine has EARNED   |
//|      trust from its own realised statistics;                     |
//|   3. adapt the acceptance threshold to account health;           |
//|   4. reject anything that clears none of the above.              |
//| Together these make the framework behave like a risk-aware       |
//| portfolio manager rather than a naive signal follower.           |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_INTELLIGENCE_AIENGINE_MQH
#define PERCEPTION_INTELLIGENCE_AIENGINE_MQH

#include <Perception/Core/Types.mqh>
#include <Perception/Core/Utils.mqh>

class CAIEngine
  {
private:
   double m_baseThreshold;    // user's minimum confidence
   double m_threshold;        // adaptive, current
   double m_aggressiveness;   // [0..1]
   bool   m_adaptive;

public:
                     CAIEngine(): m_baseThreshold(0.55), m_threshold(0.55),
                                  m_aggressiveness(0.5), m_adaptive(true) {}

   void Configure(const double baseThreshold,const double aggressiveness,const bool adaptive)
     {
      m_baseThreshold=PU::Clamp(baseThreshold,0.30,0.90);
      m_threshold=m_baseThreshold;
      m_aggressiveness=PU::Clamp(aggressiveness,0.0,1.0);
      m_adaptive=adaptive;
     }

   double Threshold() const { return m_threshold; }

   //--- convert an engine's realised record into a trust multiplier -
   //--- (engines with no track record are trusted neutrally) --------
   double TrustFromStats(const SEngineStats &s) const
     {
      if(s.trades<5) return 1.0;
      double wr=s.WinRate();
      double pf=s.ProfitFactor();
      double mult=0.6+0.6*wr+0.1*PU::Clamp(pf-1.0,-0.5,1.0);
      return PU::Clamp(mult,0.5,1.5);
     }

   //--- estimated probability the setup works out [0..1] ------------
   double EstimateProbability(const SEngineScore &sc,const SMarketState &st) const
     {
      double p = 0.32*sc.suitability
               + 0.28*sc.signal.confidence
               + 0.15*sc.signal.quality
               + 0.13*st.mtfAlignment
               + 0.12*st.regimeConfidence;
      return PU::Clamp(p,0.0,1.0);
     }

   //--- fill in the AI verdict for one engine's candidate -----------
   void Assess(SEngineScore &sc,const SMarketState &st,const SEngineStats &stats)
     {
      double prob=EstimateProbability(sc,st);
      double trust=TrustFromStats(stats);
      sc.aiConfidence=PU::Clamp(prob*trust,0.0,1.0);
      //--- ranking key rewards both confidence and regime fit -------
      sc.finalScore=sc.aiConfidence*(0.5+0.5*sc.suitability);

      bool hasSignal=sc.signal.IsValid();
      bool clearsBar=(sc.aiConfidence>=m_threshold);
      bool goodFit=(sc.suitability>=0.30);

      sc.accepted=(hasSignal && clearsBar && goodFit);
      if(!hasSignal)      sc.note="no setup";
      else if(!goodFit)   sc.note="poor regime fit";
      else if(!clearsBar) sc.note=StringFormat("conf %.2f<thr %.2f",sc.aiConfidence,m_threshold);
      else                sc.note=StringFormat("accepted @ %.2f",sc.aiConfidence);
     }

   //--- move the acceptance bar with account health -----------------
   void AdaptThreshold(const SPortfolioStats &ps)
     {
      if(!m_adaptive){ m_threshold=m_baseThreshold; return; }
      double t=m_baseThreshold;
      t-=(m_aggressiveness-0.5)*0.20;      // braver users trade a touch more
      t+=ps.currentDD*0.50;                // tighten as drawdown grows
      if(ps.winRate>0.0) t-=(ps.winRate-0.5)*0.20; // reward a good hit rate
      m_threshold=PU::Clamp(t,0.35,0.85);
     }
  };

#endif // PERCEPTION_INTELLIGENCE_AIENGINE_MQH
//+------------------------------------------------------------------+
