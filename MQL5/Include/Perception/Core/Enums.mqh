//+------------------------------------------------------------------+
//|                                                        Enums.mqh |
//|                            001 PERCEPTION - Core enumerations     |
//|                                                                  |
//| Central definitions for every enumerated type used across the    |
//| framework. Keeping them in one place guarantees that engines,    |
//| the intelligence layer and the dashboard all speak the same      |
//| language.                                                        |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_CORE_ENUMS_MQH
#define PERCEPTION_CORE_ENUMS_MQH

//--- Direction of a trade signal ------------------------------------
enum ENUM_SIGNAL_DIR
  {
   SIG_NONE = 0,   // No signal
   SIG_BUY  = 1,   // Long bias
   SIG_SELL = 2    // Short bias
  };

//--- How a signal wants to enter the market -------------------------
enum ENUM_ENTRY_TYPE
  {
   ENTRY_MARKET = 0,   // Immediate market execution
   ENTRY_LIMIT  = 1,   // Passive limit order
   ENTRY_STOP   = 2    // Breakout stop order
  };

//--- Market regime produced by the RegimeClassifier -----------------
enum ENUM_MARKET_REGIME
  {
   REGIME_UNKNOWN = 0,
   REGIME_STRONG_TREND_UP,
   REGIME_STRONG_TREND_DOWN,
   REGIME_WEAK_TREND_UP,
   REGIME_WEAK_TREND_DOWN,
   REGIME_RANGE,
   REGIME_SIDEWAYS,
   REGIME_VOLATILE,
   REGIME_CALM,
   REGIME_EXPANSION,
   REGIME_COMPRESSION,
   REGIME_NEWS,
   REGIME_GAP,
   REGIME_FLASH
  };

//--- Coarse trend direction ----------------------------------------
enum ENUM_TREND_DIR
  {
   TREND_FLAT = 0,
   TREND_UP   = 1,
   TREND_DOWN = 2
  };

//--- Volatility state ----------------------------------------------
enum ENUM_VOL_STATE
  {
   VOL_CALM = 0,
   VOL_NORMAL,
   VOL_ELEVATED,
   VOL_EXTREME
  };

//--- Identity for every trading engine (also seeds the magic base) --
enum ENUM_ENGINE_ID
  {
   ENG_NONE            = 0,
   ENG_TREND           = 1,
   ENG_SWING           = 2,
   ENG_SCALPING        = 3,
   ENG_BREAKOUT        = 4,
   ENG_RANGE           = 5,
   ENG_GRID            = 6,
   ENG_ADAPTIVE_GRID   = 7,
   ENG_MARTINGALE      = 8,
   ENG_RECOVERY        = 9,
   ENG_HEDGING         = 10,
   ENG_MEAN_REVERSION  = 11,
   ENG_MOMENTUM        = 12,
   ENG_LIQUIDITY_GRAB  = 13,
   ENG_SMC             = 14,
   ENG_SUPPLY_DEMAND   = 15,
   ENG_SUPPORT_RES     = 16,
   ENG_ORDER_BLOCK     = 17,
   ENG_FVG             = 18,
   ENG_VOLUME_PROFILE  = 19,
   ENG_SESSION         = 20,
   ENG_VOLATILITY      = 21,
   ENG_CORRELATION     = 22,
   ENG_BASKET          = 23
  };

//--- Account presets ------------------------------------------------
enum ENUM_PRESET
  {
   PRESET_MICRO = 0,
   PRESET_SMALL,
   PRESET_MEDIUM,
   PRESET_LARGE,
   PRESET_PROFESSIONAL,
   PRESET_COMMERCIAL,
   PRESET_INSTITUTION
  };

//--- Dashboard render mode -----------------------------------------
enum ENUM_DASH_MODE
  {
   DASH_COMPACT = 1,   // Minimal, top-left
   DASH_PRO     = 2,   // Full professional layout
   DASH_RESEARCH= 3    // Institutional / quant research
  };

//--- Logging verbosity ---------------------------------------------
enum ENUM_LOG_LEVEL
  {
   LOG_SILENT = 0,
   LOG_ERROR  = 1,
   LOG_WARN   = 2,
   LOG_INFO   = 3,
   LOG_DEBUG  = 4
  };

//--- Health state of the whole system ------------------------------
enum ENUM_SYSTEM_STATE
  {
   STATE_INIT = 0,
   STATE_RUNNING,
   STATE_THROTTLED,     // Reduced activity (e.g. news / high spread)
   STATE_RECOVERY,      // Recovery mode active
   STATE_HALTED         // Kill switch tripped
  };

#endif // PERCEPTION_CORE_ENUMS_MQH
//+------------------------------------------------------------------+
