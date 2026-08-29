//+------------------------------------------------------------------+
//|                                                        Utils.mqh |
//|                     001 PERCEPTION - Stateless helper functions   |
//|                                                                  |
//| Small, pure helpers that have no dependency on framework state.  |
//| Everything here is free of side effects so it can be reused by   |
//| any module without creating coupling.                            |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_CORE_UTILS_MQH
#define PERCEPTION_CORE_UTILS_MQH

#include <Perception/Core/Enums.mqh>

//+------------------------------------------------------------------+
//| Numeric helpers                                                  |
//+------------------------------------------------------------------+
namespace PU
  {
//--- Clamp a value into [lo, hi] ------------------------------------
double Clamp(const double v,const double lo,const double hi)
  {
   if(v<lo) return lo;
   if(v>hi) return hi;
   return v;
  }

int ClampI(const int v,const int lo,const int hi)
  {
   if(v<lo) return lo;
   if(v>hi) return hi;
   return v;
  }

//--- Linear interpolation -------------------------------------------
double Lerp(const double a,const double b,const double t)
  {
   return a+(b-a)*Clamp(t,0.0,1.0);
  }

//--- Safe division (returns def when denominator is ~0) -------------
double SafeDiv(const double num,const double den,const double def=0.0)
  {
   if(MathAbs(den)<1e-12) return def;
   return num/den;
  }

//--- Rescale x from [inLo,inHi] to [0,1], clamped -------------------
double Normalize01(const double x,const double inLo,const double inHi)
  {
   if(MathAbs(inHi-inLo)<1e-12) return 0.0;
   return Clamp((x-inLo)/(inHi-inLo),0.0,1.0);
  }

//--- Exponential moving update of a running value -------------------
double EmaUpdate(const double prev,const double sample,const double alpha)
  {
   return prev+alpha*(sample-prev);
  }

//+------------------------------------------------------------------+
//| Formatting helpers                                               |
//+------------------------------------------------------------------+
string Money(const double v)
  {
   return DoubleToString(v,2);
  }

string Pct(const double v01,const int digits=1)
  {
   return DoubleToString(v01*100.0,digits)+"%";
  }

//--- Round a volume to the broker lot step --------------------------
double RoundToStep(const double value,const double step)
  {
   if(step<=0.0) return value;
   return MathRound(value/step)*step;
  }

//--- Round a price to the symbol digits -----------------------------
double NormalizePrice(const double price,const int digits)
  {
   return NormalizeDouble(price,digits);
  }
  } // namespace PU

//+------------------------------------------------------------------+
//| Human readable label helpers (global scope so they can be used   |
//| unqualified across the framework and dashboard).                 |
//+------------------------------------------------------------------+
string RegimeName(const ENUM_MARKET_REGIME r)
  {
   switch(r)
     {
      case REGIME_STRONG_TREND_UP:   return "Strong Uptrend";
      case REGIME_STRONG_TREND_DOWN: return "Strong Downtrend";
      case REGIME_WEAK_TREND_UP:     return "Weak Uptrend";
      case REGIME_WEAK_TREND_DOWN:   return "Weak Downtrend";
      case REGIME_RANGE:             return "Range";
      case REGIME_SIDEWAYS:          return "Sideways";
      case REGIME_VOLATILE:          return "Volatile";
      case REGIME_CALM:              return "Calm";
      case REGIME_EXPANSION:         return "Expansion";
      case REGIME_COMPRESSION:       return "Compression";
      case REGIME_NEWS:              return "News";
      case REGIME_GAP:               return "Gap";
      case REGIME_FLASH:             return "Flash Move";
      default:                       return "Unknown";
     }
  }

string SignalName(const ENUM_SIGNAL_DIR d)
  {
   switch(d)
     {
      case SIG_BUY:  return "BUY";
      case SIG_SELL: return "SELL";
      default:       return "-";
     }
  }

string PresetName(const ENUM_PRESET p)
  {
   switch(p)
     {
      case PRESET_MICRO:        return "Micro";
      case PRESET_SMALL:        return "Small";
      case PRESET_MEDIUM:       return "Medium";
      case PRESET_LARGE:        return "Large";
      case PRESET_PROFESSIONAL: return "Professional";
      case PRESET_COMMERCIAL:   return "Commercial";
      case PRESET_INSTITUTION:  return "Institution";
      default:                  return "Custom";
     }
  }

#endif // PERCEPTION_CORE_UTILS_MQH
//+------------------------------------------------------------------+
