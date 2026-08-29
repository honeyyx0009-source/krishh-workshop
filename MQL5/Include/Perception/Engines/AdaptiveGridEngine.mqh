//+------------------------------------------------------------------+
//|                                            AdaptiveGridEngine.mqh |
//|             001 PERCEPTION - Adaptive grid engine (opt-in)        |
//|                                                                  |
//| Identical safety envelope to the standard grid, but the step     |
//| between levels breathes with volatility: wider when ATR is       |
//| elevated, tighter when the market is calm. Disabled by default.  |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_ENGINES_ADAPTIVEGRID_MQH
#define PERCEPTION_ENGINES_ADAPTIVEGRID_MQH

#include <Perception/Engines/GridEngine.mqh>

class CAdaptiveGridEngine : public CGridEngine
  {
protected:
   double StepMultiplier(const SMarketState &st,const SConfig &cfg) override
     {
      //--- scale the base step by the current volatility ratio ------
      double scale=PU::Clamp(st.volRatio,0.6,2.5);
      return cfg.gridStepAtrMult*scale;
     }
public:
   CAdaptiveGridEngine() { m_id=ENG_ADAPTIVE_GRID; m_name="AdaptiveGrid"; m_enabled=false; }

   double Suitability(const SMarketState &st) override
     {
      double base=CGridEngine::Suitability(st);
      //--- adaptive grid tolerates a bit more movement than a fixed one
      if(st.regime==REGIME_EXPANSION) base=MathMax(base,0.35);
      return base;
     }
  };

#endif // PERCEPTION_ENGINES_ADAPTIVEGRID_MQH
//+------------------------------------------------------------------+
