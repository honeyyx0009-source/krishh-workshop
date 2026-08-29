//+------------------------------------------------------------------+
//|                                              StrategySelector.mqh |
//|          001 PERCEPTION - Engine scoring & selection              |
//|                                                                  |
//| Every bar the selector polls each enabled engine for a signal    |
//| and a suitability, hands the pair to the AI layer for scoring,   |
//| records the verdict on the event bus (for the live decision log) |
//| and finally elects the single highest-scoring accepted engine.   |
//| This is the concrete realisation of the project's core           |
//| philosophy: never depend on one strategy; let confidence decide. |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_INTELLIGENCE_STRATEGYSELECTOR_MQH
#define PERCEPTION_INTELLIGENCE_STRATEGYSELECTOR_MQH

#include <Perception/Engines/EngineManager.mqh>
#include <Perception/Intelligence/AIEngine.mqh>
#include <Perception/Core/EventBus.mqh>

class CStrategySelector
  {
private:
   CEngineManager *m_engines;
   CAIEngine      *m_ai;
   CEventBus      *m_bus;
   SEngineScore    m_scores[];    // last evaluation, for the dashboard
   int             m_scoreCount;

public:
                     CStrategySelector(): m_engines(NULL), m_ai(NULL), m_bus(NULL), m_scoreCount(0) {}

   void Init(CEngineManager *engines,CAIEngine *ai,CEventBus *bus)
     { m_engines=engines; m_ai=ai; m_bus=bus; ArrayResize(m_scores,engines.Count()); }

   //--- returns true and fills `best` when a tradeable winner exists -
   bool Select(const SMarketState &st,CSymbolMeta *sym,const SConfig &cfg,SEngineScore &best)
     {
      m_scoreCount=0;
      best.Reset();
      double bestKey=-1.0;
      int n=m_engines.Count();
      for(int i=0;i<n;i++)
        {
         CEngine *e=m_engines.At(i);
         if(e==NULL || !e.Enabled()) continue;

         SEngineScore sc; sc.Reset();
         sc.id=e.Id(); sc.name=e.Name();
         sc.suitability=PU::Clamp(e.Suitability(st),0.0,1.0);

         //--- only bother asking for a signal if the fit is plausible
         if(sc.suitability>=0.20)
            e.Evaluate(st,sym,cfg,sc.signal);

         SEngineStats es=e.Stats();
         m_ai.Assess(sc,st,es);

         //--- record for dashboard + decision log ------------------
         if(m_scoreCount<ArraySize(m_scores)) m_scores[m_scoreCount++]=sc;
         if(m_bus!=NULL && sc.signal.IsValid())
            m_bus.Publish(sc.id,sc.accepted,
                          StringFormat("%s %s %s (%.2f) - %s",e.Name(),
                                       SignalName(sc.signal.dir),
                                       sc.accepted?"ACCEPT":"reject",
                                       sc.aiConfidence,sc.signal.reason));

         if(sc.accepted && sc.finalScore>bestKey)
           { bestKey=sc.finalScore; best=sc; }
        }
      return (bestKey>=0.0 && best.signal.IsValid());
     }

   //--- dashboard access to the ranked candidates -------------------
   int  ScoreCount() const { return m_scoreCount; }
   bool ScoreAt(const int i,SEngineScore &out) const
     {
      if(i<0 || i>=m_scoreCount) return false;
      out=m_scores[i];
      return true;
     }

   //--- ranking helper: fill idx[] with score indices high->low -----
   void RankIndices(int &idx[]) const
     {
      ArrayResize(idx,m_scoreCount);
      for(int i=0;i<m_scoreCount;i++) idx[i]=i;
      for(int a=0;a<m_scoreCount-1;a++)
         for(int b=a+1;b<m_scoreCount;b++)
            if(m_scores[idx[b]].finalScore>m_scores[idx[a]].finalScore)
              { int t=idx[a]; idx[a]=idx[b]; idx[b]=t; }
     }
  };

#endif // PERCEPTION_INTELLIGENCE_STRATEGYSELECTOR_MQH
//+------------------------------------------------------------------+
