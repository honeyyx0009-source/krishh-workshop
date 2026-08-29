//+------------------------------------------------------------------+
//|                                                       Config.mqh |
//|              001 PERCEPTION - Resolved runtime configuration      |
//|                                                                  |
//| SConfig is the immutable-ish snapshot of user inputs after they  |
//| have been merged with the selected account preset. Modules read  |
//| this struct instead of the raw `input` globals so they stay      |
//| testable and decoupled from the EA entry point.                  |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_CORE_CONFIG_MQH
#define PERCEPTION_CORE_CONFIG_MQH

#include <Perception/Core/Enums.mqh>

struct SConfig
  {
   //--- identity / general
   long              magicBase;
   ENUM_PRESET       preset;
   ENUM_DASH_MODE    dashMode;
   ENUM_LOG_LEVEL    logLevel;
   bool              autoTrade;

   //--- multi timeframe
   ENUM_TIMEFRAMES   tfMid;
   ENUM_TIMEFRAMES   tfHigh;
   bool              useMTFConfirm;

   //--- intelligence
   double            minConfidence;     // gate for taking a trade [0..1]
   bool              adaptiveThresholds;
   double            aggressiveness;    // [0..1] scales frequency & size

   //--- risk (post-preset)
   double            riskPercent;       // % equity risked per trade
   double            maxSpreadPts;      // 0 => auto
   int               maxOpenTrades;
   int               maxTradesPerSymbol;
   double            dailyLossLimitPct;
   double            maxDrawdownPct;
   double            equityStopPct;
   bool              useKillSwitch;

   //--- stop / target sizing
   double            atrSlMult;
   double            atrTpMult;
   double            minStopAtrMult;

   //--- trade management
   bool              useTrailing;
   double            trailAtrMult;
   double            trailStartRR;
   bool              useBreakeven;
   double            beTriggerRR;
   double            beLockPts;
   bool              usePartialClose;
   double            partialRR;
   double            partialPct;

   //--- grid / recovery
   bool              useRecovery;
   double            gridStepAtrMult;
   int               gridMaxLevels;
   double            gridLotFactor;

   //--- filters
   bool              useSessionFilter;
   bool              useNewsFilter;
   int               newsBufferMinutes;

   //--- dashboard / chart
   bool              showDashboard;
   bool              darkSkin;
   bool              drawZones;
  };

//--- per-engine enable flags, resolved from inputs ------------------
struct SEngineToggles
  {
   bool trend, swing, momentum, range, meanRev, scalp, breakout, volatility;
   bool session, supportRes, orderBlock, fvg, liqGrab, supplyDem, smc, volProfile;
   bool grid, adaptiveGrid, martingale, recovery, hedging;

   bool Enabled(const ENUM_ENGINE_ID id) const
     {
      switch(id)
        {
         case ENG_TREND:          return trend;
         case ENG_SWING:          return swing;
         case ENG_MOMENTUM:       return momentum;
         case ENG_RANGE:          return range;
         case ENG_MEAN_REVERSION: return meanRev;
         case ENG_SCALPING:       return scalp;
         case ENG_BREAKOUT:       return breakout;
         case ENG_VOLATILITY:     return volatility;
         case ENG_SESSION:        return session;
         case ENG_SUPPORT_RES:    return supportRes;
         case ENG_ORDER_BLOCK:    return orderBlock;
         case ENG_FVG:            return fvg;
         case ENG_LIQUIDITY_GRAB: return liqGrab;
         case ENG_SUPPLY_DEMAND:  return supplyDem;
         case ENG_SMC:            return smc;
         case ENG_VOLUME_PROFILE: return volProfile;
         case ENG_GRID:           return grid;
         case ENG_ADAPTIVE_GRID:  return adaptiveGrid;
         case ENG_MARTINGALE:     return martingale;
         case ENG_RECOVERY:       return recovery;
         case ENG_HEDGING:        return hedging;
         default:                 return false;
        }
     }
  };

#endif // PERCEPTION_CORE_CONFIG_MQH
//+------------------------------------------------------------------+
