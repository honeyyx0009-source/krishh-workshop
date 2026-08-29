//+------------------------------------------------------------------+
//|                                                      Presets.mqh |
//|             001 PERCEPTION - Account preset profiles              |
//|                                                                  |
//| A micro account and an institutional account should never be     |
//| traded with the same exposure. Presets encode battle-tested risk |
//| envelopes so a user can pick a tier and have sizing, exposure,    |
//| grid depth, recovery and aggressiveness set coherently in one    |
//| move. The chosen preset overrides the individual risk inputs.    |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_RISK_PRESETS_MQH
#define PERCEPTION_RISK_PRESETS_MQH

#include <Perception/Core/Config.mqh>

class CPresets
  {
public:
   //--- overwrite the risk envelope of cfg from the selected tier ---
   static void Apply(SConfig &cfg)
     {
      switch(cfg.preset)
        {
         case PRESET_MICRO:
            cfg.riskPercent=0.50; cfg.maxOpenTrades=2;  cfg.maxTradesPerSymbol=1;
            cfg.dailyLossLimitPct=3.0; cfg.maxDrawdownPct=10.0; cfg.equityStopPct=15.0;
            cfg.gridMaxLevels=3;  cfg.gridLotFactor=1.0; cfg.aggressiveness=0.30;
            cfg.useRecovery=false; break;

         case PRESET_SMALL:
            cfg.riskPercent=0.75; cfg.maxOpenTrades=3;  cfg.maxTradesPerSymbol=2;
            cfg.dailyLossLimitPct=4.0; cfg.maxDrawdownPct=12.0; cfg.equityStopPct=18.0;
            cfg.gridMaxLevels=4;  cfg.gridLotFactor=1.1; cfg.aggressiveness=0.40;
            cfg.useRecovery=true; break;

         case PRESET_MEDIUM:
            cfg.riskPercent=1.00; cfg.maxOpenTrades=5;  cfg.maxTradesPerSymbol=2;
            cfg.dailyLossLimitPct=5.0; cfg.maxDrawdownPct=15.0; cfg.equityStopPct=20.0;
            cfg.gridMaxLevels=5;  cfg.gridLotFactor=1.2; cfg.aggressiveness=0.50;
            cfg.useRecovery=true; break;

         case PRESET_LARGE:
            cfg.riskPercent=1.00; cfg.maxOpenTrades=8;  cfg.maxTradesPerSymbol=3;
            cfg.dailyLossLimitPct=5.0; cfg.maxDrawdownPct=15.0; cfg.equityStopPct=20.0;
            cfg.gridMaxLevels=6;  cfg.gridLotFactor=1.2; cfg.aggressiveness=0.55;
            cfg.useRecovery=true; break;

         case PRESET_PROFESSIONAL:
            cfg.riskPercent=0.75; cfg.maxOpenTrades=10; cfg.maxTradesPerSymbol=3;
            cfg.dailyLossLimitPct=4.0; cfg.maxDrawdownPct=12.0; cfg.equityStopPct=18.0;
            cfg.gridMaxLevels=6;  cfg.gridLotFactor=1.15; cfg.aggressiveness=0.60;
            cfg.useRecovery=true; break;

         case PRESET_COMMERCIAL:
            cfg.riskPercent=0.60; cfg.maxOpenTrades=14; cfg.maxTradesPerSymbol=4;
            cfg.dailyLossLimitPct=3.5; cfg.maxDrawdownPct=10.0; cfg.equityStopPct=15.0;
            cfg.gridMaxLevels=7;  cfg.gridLotFactor=1.1; cfg.aggressiveness=0.65;
            cfg.useRecovery=true; break;

         case PRESET_INSTITUTION:
            cfg.riskPercent=0.40; cfg.maxOpenTrades=20; cfg.maxTradesPerSymbol=5;
            cfg.dailyLossLimitPct=2.5; cfg.maxDrawdownPct=8.0;  cfg.equityStopPct=12.0;
            cfg.gridMaxLevels=8;  cfg.gridLotFactor=1.05; cfg.aggressiveness=0.70;
            cfg.useRecovery=true; break;
        }
     }
  };

#endif // PERCEPTION_RISK_PRESETS_MQH
//+------------------------------------------------------------------+
