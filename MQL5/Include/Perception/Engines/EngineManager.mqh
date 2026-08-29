//+------------------------------------------------------------------+
//|                                                EngineManager.mqh |
//|          001 PERCEPTION - Engine registry & lifecycle             |
//|                                                                  |
//| Owns the full roster of trading engines. It news them up once,   |
//| assigns each a unique magic number (magicBase + engine id) and   |
//| exposes simple iteration for the strategy selector. Ownership is |
//| centralised here so there is exactly one place that creates and  |
//| destroys engines - no leaks, no dangling pointers.               |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_ENGINES_ENGINEMANAGER_MQH
#define PERCEPTION_ENGINES_ENGINEMANAGER_MQH

#include <Perception/Engines/TrendEngine.mqh>
#include <Perception/Engines/SwingEngine.mqh>
#include <Perception/Engines/MomentumEngine.mqh>
#include <Perception/Engines/RangeEngine.mqh>
#include <Perception/Engines/MeanReversionEngine.mqh>
#include <Perception/Engines/ScalpingEngine.mqh>
#include <Perception/Engines/BreakoutEngine.mqh>
#include <Perception/Engines/VolatilityEngine.mqh>
#include <Perception/Engines/SessionEngine.mqh>
#include <Perception/Engines/SupportResistEngine.mqh>
#include <Perception/Engines/OrderBlockEngine.mqh>
#include <Perception/Engines/FVGEngine.mqh>
#include <Perception/Engines/LiquidityGrabEngine.mqh>
#include <Perception/Engines/SupplyDemandEngine.mqh>
#include <Perception/Engines/SMCEngine.mqh>
#include <Perception/Engines/VolumeProfileEngine.mqh>
#include <Perception/Engines/GridEngine.mqh>
#include <Perception/Engines/AdaptiveGridEngine.mqh>
#include <Perception/Engines/MartingaleEngine.mqh>
#include <Perception/Engines/RecoveryEngine.mqh>
#include <Perception/Engines/HedgingEngine.mqh>

class CEngineManager
  {
private:
   CEngine *m_e[];

   void Add(CEngine *e)
     {
      int n=ArraySize(m_e);
      ArrayResize(m_e,n+1);
      m_e[n]=e;
     }

public:
                     CEngineManager() {}
                    ~CEngineManager()
     {
      for(int i=0;i<ArraySize(m_e);i++)
         if(CheckPointer(m_e[i])==POINTER_DYNAMIC) delete m_e[i];
      ArrayFree(m_e);
     }

   //--- register the full roster ------------------------------------
   void Populate()
     {
      Add(new CTrendEngine());
      Add(new CSwingEngine());
      Add(new CMomentumEngine());
      Add(new CRangeEngine());
      Add(new CMeanReversionEngine());
      Add(new CScalpingEngine());
      Add(new CBreakoutEngine());
      Add(new CVolatilityEngine());
      Add(new CSessionEngine());
      Add(new CSupportResistEngine());
      Add(new COrderBlockEngine());
      Add(new CFVGEngine());
      Add(new CLiquidityGrabEngine());
      Add(new CSupplyDemandEngine());
      Add(new CSMCEngine());
      Add(new CVolumeProfileEngine());
      Add(new CGridEngine());
      Add(new CAdaptiveGridEngine());
      Add(new CMartingaleEngine());
      Add(new CRecoveryEngine());
      Add(new CHedgingEngine());
     }

   //--- initialise every engine with a unique magic number ----------
   void InitAll(const string symbol,const ENUM_TIMEFRAMES tf,const long magicBase)
     {
      for(int i=0;i<ArraySize(m_e);i++)
         m_e[i].Init(symbol,tf,magicBase+(long)m_e[i].Id());
     }

   int      Count()      const { return ArraySize(m_e); }
   CEngine *At(const int i)    { return (i>=0 && i<ArraySize(m_e) ? m_e[i] : NULL); }

   CEngine *FindById(const ENUM_ENGINE_ID id)
     {
      for(int i=0;i<ArraySize(m_e);i++)
         if(m_e[i].Id()==id) return m_e[i];
      return NULL;
     }

   void SetEnabledById(const ENUM_ENGINE_ID id,const bool on)
     {
      CEngine *e=FindById(id);
      if(e!=NULL) e.SetEnabled(on);
     }
  };

#endif // PERCEPTION_ENGINES_ENGINEMANAGER_MQH
//+------------------------------------------------------------------+
