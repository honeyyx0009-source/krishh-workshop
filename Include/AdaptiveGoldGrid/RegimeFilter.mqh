//+------------------------------------------------------------------+
//|                                                 RegimeFilter.mqh |
//|   Adaptive Gold Grid EA - Higher-timeframe regime / trend filter. |
//+------------------------------------------------------------------+
//| WHY THIS MODULE EXISTS (READ THIS)                               |
//|                                                                  |
//|   The single biggest killer of a grid/martingale system is        |
//|   AVERAGING INTO A TREND. The failure mode looks exactly like     |
//|   this:                                                          |
//|                                                                  |
//|     1. A short/noisy timeframe shows a momentary down-flicker     |
//|        inside a larger UPTREND.                                   |
//|     2. The EA seeds a SELL.                                       |
//|     3. Price resumes the uptrend.                                 |
//|     4. The recovery engine keeps adding SELLs "to average up".     |
//|     5. 6-7 levels later exposure is large, the market never       |
//|        comes back, and the account bleeds to death.               |
//|                                                                  |
//|   No amount of clever lot maths fixes that. The ONLY real fix is  |
//|   to refuse to fight a dominant trend in the first place, and to  |
//|   STOP ENLARGING a basket that is on the wrong side of one.       |
//|                                                                  |
//| WHAT IT DOES                                                     |
//|   Builds a HIGHER-TIMEFRAME regime read-out (independent of the   |
//|   fast analysis timeframe) from three classical inputs:           |
//|     * ADX (+DI / -DI)  -> is there a trend, and how strong?       |
//|     * EMA fast/slow    -> which way is the higher TF structured?  |
//|     * ATR fast/slow    -> is volatility expanding violently?      |
//|                                                                  |
//|   It then answers two gating questions:                           |
//|     AllowSeed()      - may we START a basket in this direction?   |
//|     AllowAveraging() - may we ENLARGE a basket in this direction? |
//|                                                                  |
//| HONEST LABELLING                                                 |
//|   Ordinary deterministic indicators. NOT machine learning, not    |
//|   "AI". No neural network is involved anywhere in this file.      |
//|                                                                  |
//| IMPORTANT: this module is ADVISORY + ENTRY-SIDE ONLY. It never    |
//|   sends, modifies or closes an order. It only says "yes" or "no"  |
//|   to NEW exposure.                                                |
//+------------------------------------------------------------------+
#ifndef ADAPTIVEGRID_REGIMEFILTER_MQH
#define ADAPTIVEGRID_REGIMEFILTER_MQH

#include "Logger.mqh"
#include "OrderManager.mqh"    // ENUM_GRID_DIRECTION
#include "MarketAnalysis.mqh"  // ENUM_TREND_DIR

//+------------------------------------------------------------------+
//| Higher-timeframe market regime classification.                   |
//+------------------------------------------------------------------+
enum ENUM_MARKET_REGIME
  {
   REGIME_UNKNOWN = 0,   // Data not ready -> caller must not open new exposure
   REGIME_RANGING,        // No dominant trend: the ONLY healthy grid regime
   REGIME_TREND_UP,       // Dominant uptrend: never grid short into this
   REGIME_TREND_DOWN,     // Dominant downtrend: never grid long into this
   REGIME_VIOLENT         // Volatility explosion: stand aside entirely
  };

//+------------------------------------------------------------------+
//| Which regimes is the EA allowed to seed a basket in?             |
//+------------------------------------------------------------------+
enum ENUM_GRID_POLICY
  {
   POLICY_RANGING_ONLY = 0,  // Safest: only seed when the HTF is ranging
   POLICY_WITH_TREND_ONLY,   // Only seed in the direction of the HTF trend
   POLICY_RANGING_AND_TREND  // Ranging, or with-trend when trending
  };

//+------------------------------------------------------------------+
//| RegimeContext - the consolidated higher-timeframe read-out.      |
//+------------------------------------------------------------------+
struct RegimeContext
  {
   bool               ready;      // false => do NOT open new exposure
   ENUM_MARKET_REGIME regime;     // Classified regime
   double             adx;        // ADX main line (trend strength)
   double             plus_di;    // +DI
   double             minus_di;   // -DI
   ENUM_TREND_DIR     htf_trend;  // EMA-structure trend on the higher TF
   double             atr_ratio;  // fast ATR / slow ATR (>1 = expanding)
   string             detail;     // Human-readable summary for logging
  };

//+------------------------------------------------------------------+
//| CRegimeFilter                                                    |
//+------------------------------------------------------------------+
class CRegimeFilter
  {
private:
   CLogger        *m_log;
   string          m_symbol;
   ENUM_TIMEFRAMES m_tf;              // Higher timeframe (e.g. H1 / H4)

   //--- Indicator handles.
   int             m_h_adx;
   int             m_h_ema_fast;
   int             m_h_ema_slow;
   int             m_h_atr_fast;
   int             m_h_atr_slow;

   //--- Parameters.
   int             m_adx_period;
   int             m_ema_fast_period;
   int             m_ema_slow_period;
   int             m_atr_fast_period;
   int             m_atr_slow_period;

   //--- Thresholds.
   double          m_adx_trend_level;    // ADX above this => a trend exists
   double          m_adx_strong_level;   // ADX above this => STRONG trend
   double          m_atr_violent_ratio;  // fast/slow ATR above this => violent

   bool            m_ready;

   void            LogErr(const string m)  { if(m_log!=NULL) m_log.Error(m); }
   void            LogWarn(const string m) { if(m_log!=NULL) m_log.Warn(m);  }
   void            LogInfo(const string m) { if(m_log!=NULL) m_log.Info(m);  }
   void            LogDbg(const string m)  { if(m_log!=NULL) m_log.Debug(m); }

   //--- Defensive single-value buffer copy.
   bool            CopyOne(const int handle,const int buffer,const int shift,double &out) const
     {
      if(handle==INVALID_HANDLE)
         return(false);
      double tmp[];
      if(CopyBuffer(handle,buffer,shift,1,tmp)<1)
         return(false);
      out=tmp[0];
      return(true);
     }

public:
                   CRegimeFilter(void)
     {
      m_log               = NULL;
      m_symbol            = _Symbol;
      m_tf                = PERIOD_H1;
      m_h_adx             = INVALID_HANDLE;
      m_h_ema_fast        = INVALID_HANDLE;
      m_h_ema_slow        = INVALID_HANDLE;
      m_h_atr_fast        = INVALID_HANDLE;
      m_h_atr_slow        = INVALID_HANDLE;
      m_adx_period        = 14;
      m_ema_fast_period   = 50;
      m_ema_slow_period   = 200;
      m_atr_fast_period   = 14;
      m_atr_slow_period   = 50;
      m_adx_trend_level   = 22.0;
      m_adx_strong_level  = 30.0;
      m_atr_violent_ratio = 1.80;
      m_ready             = false;
     }
                  ~CRegimeFilter(void) { Deinit(); }

   //================================================================//
   //  INIT                                                          //
   //================================================================//
   bool            Init(const string symbol,const ENUM_TIMEFRAMES higher_tf,
                        CLogger *logger=NULL,
                        const int adx_period=14,
                        const int ema_fast=50,const int ema_slow=200,
                        const int atr_fast=14,const int atr_slow=50,
                        const double adx_trend_level=22.0,
                        const double adx_strong_level=30.0,
                        const double atr_violent_ratio=1.80)
     {
      m_symbol            = symbol;
      m_tf                = higher_tf;
      m_log               = logger;
      m_adx_period        = adx_period;
      m_ema_fast_period   = ema_fast;
      m_ema_slow_period   = ema_slow;
      m_atr_fast_period   = atr_fast;
      m_atr_slow_period   = atr_slow;
      m_adx_trend_level   = adx_trend_level;
      m_adx_strong_level  = MathMax(adx_trend_level,adx_strong_level);
      m_atr_violent_ratio = MathMax(1.0,atr_violent_ratio);

      m_h_adx      = iADX(m_symbol,m_tf,m_adx_period);
      m_h_ema_fast = iMA(m_symbol,m_tf,m_ema_fast_period,0,MODE_EMA,PRICE_CLOSE);
      m_h_ema_slow = iMA(m_symbol,m_tf,m_ema_slow_period,0,MODE_EMA,PRICE_CLOSE);
      m_h_atr_fast = iATR(m_symbol,m_tf,m_atr_fast_period);
      m_h_atr_slow = iATR(m_symbol,m_tf,m_atr_slow_period);

      m_ready = (m_h_adx!=INVALID_HANDLE && m_h_ema_fast!=INVALID_HANDLE &&
                 m_h_ema_slow!=INVALID_HANDLE && m_h_atr_fast!=INVALID_HANDLE &&
                 m_h_atr_slow!=INVALID_HANDLE);

      if(!m_ready)
        {
         LogErr("RegimeFilter.Init: one or more indicator handles failed to create.");
         Deinit();
         return(false);
        }

      LogInfo(StringFormat("RegimeFilter ready on %s HTF=%d (ADX%d, EMA%d/%d, ATR%d/%d).",
                           m_symbol,(int)m_tf,m_adx_period,
                           m_ema_fast_period,m_ema_slow_period,
                           m_atr_fast_period,m_atr_slow_period));
      return(true);
     }

   //================================================================//
   //  DEINIT : release handles. Safe to call repeatedly.            //
   //================================================================//
   void            Deinit(void)
     {
      if(m_h_adx     !=INVALID_HANDLE) { IndicatorRelease(m_h_adx);      m_h_adx=INVALID_HANDLE;      }
      if(m_h_ema_fast!=INVALID_HANDLE) { IndicatorRelease(m_h_ema_fast); m_h_ema_fast=INVALID_HANDLE; }
      if(m_h_ema_slow!=INVALID_HANDLE) { IndicatorRelease(m_h_ema_slow); m_h_ema_slow=INVALID_HANDLE; }
      if(m_h_atr_fast!=INVALID_HANDLE) { IndicatorRelease(m_h_atr_fast); m_h_atr_fast=INVALID_HANDLE; }
      if(m_h_atr_slow!=INVALID_HANDLE) { IndicatorRelease(m_h_atr_slow); m_h_atr_slow=INVALID_HANDLE; }
      m_ready=false;
     }

   bool            IsReady(void) const { return(m_ready); }

   //--- Text helper for logs.
   string          RegimeName(const ENUM_MARKET_REGIME r) const
     {
      switch(r)
        {
         case REGIME_RANGING:    return("RANGING");
         case REGIME_TREND_UP:   return("TREND_UP");
         case REGIME_TREND_DOWN: return("TREND_DOWN");
         case REGIME_VIOLENT:    return("VIOLENT");
         default:                return("UNKNOWN");
        }
     }

   //================================================================//
   //  EVALUATE : classify the higher-timeframe regime.              //
   //                                                                //
   //  Classification order matters:                                  //
   //    1. VIOLENT  - volatility expansion dominates everything.      //
   //                  Grids get destroyed in volatility explosions,   //
   //                  so this wins over any trend/range reading.      //
   //    2. TREND    - ADX above the trend level AND the EMA structure //
   //                  agrees with the DI dominance. Requiring BOTH    //
   //                  avoids calling a trend on a single noisy input. //
   //    3. RANGING  - everything else (the healthy grid regime).      //
   //================================================================//
   RegimeContext   Evaluate(void)
     {
      RegimeContext rc;
      rc.ready     = false;
      rc.regime    = REGIME_UNKNOWN;
      rc.adx       = 0.0;
      rc.plus_di   = 0.0;
      rc.minus_di  = 0.0;
      rc.htf_trend = TREND_NONE;
      rc.atr_ratio = 1.0;
      rc.detail    = "not ready";

      if(!m_ready)
        {
         LogWarn("RegimeFilter.Evaluate: engine not ready (invalid handles).");
         return(rc);
        }

      //--- ADX main + directional indicators (shift 1 = last closed bar).
      double adx=0.0, pdi=0.0, mdi=0.0;
      if(!CopyOne(m_h_adx,0,1,adx) ||
         !CopyOne(m_h_adx,1,1,pdi) ||
         !CopyOne(m_h_adx,2,1,mdi))
        {
         LogDbg("RegimeFilter.Evaluate: ADX buffers not ready.");
         return(rc);
        }
      rc.adx      = adx;
      rc.plus_di  = pdi;
      rc.minus_di = mdi;

      //--- Higher-TF EMA structure.
      double ema_f=0.0, ema_s=0.0;
      if(!CopyOne(m_h_ema_fast,0,1,ema_f) || !CopyOne(m_h_ema_slow,0,1,ema_s))
        {
         LogDbg("RegimeFilter.Evaluate: EMA buffers not ready.");
         return(rc);
        }
      if(ema_f > ema_s)      rc.htf_trend = TREND_UP;
      else if(ema_f < ema_s) rc.htf_trend = TREND_DOWN;
      else                   rc.htf_trend = TREND_NONE;

      //--- Volatility expansion ratio.
      double atr_f=0.0, atr_s=0.0;
      if(!CopyOne(m_h_atr_fast,0,1,atr_f) || !CopyOne(m_h_atr_slow,0,1,atr_s))
        {
         LogDbg("RegimeFilter.Evaluate: ATR buffers not ready.");
         return(rc);
        }
      rc.atr_ratio = (atr_s>0.0 ? atr_f/atr_s : 1.0);

      //--- (1) VIOLENT wins over everything else.
      if(rc.atr_ratio >= m_atr_violent_ratio)
        {
         rc.regime = REGIME_VIOLENT;
         rc.detail = StringFormat("VIOLENT: ATR ratio %.2f >= %.2f (volatility explosion)",
                                  rc.atr_ratio,m_atr_violent_ratio);
        }
      //--- (2) TREND requires ADX strength AND EMA/DI agreement.
      else if(adx >= m_adx_trend_level && pdi > mdi && rc.htf_trend==TREND_UP)
        {
         rc.regime = REGIME_TREND_UP;
         rc.detail = StringFormat("TREND_UP: ADX %.1f (+DI %.1f > -DI %.1f), EMA%d>EMA%d",
                                  adx,pdi,mdi,m_ema_fast_period,m_ema_slow_period);
        }
      else if(adx >= m_adx_trend_level && mdi > pdi && rc.htf_trend==TREND_DOWN)
        {
         rc.regime = REGIME_TREND_DOWN;
         rc.detail = StringFormat("TREND_DOWN: ADX %.1f (-DI %.1f > +DI %.1f), EMA%d<EMA%d",
                                  adx,mdi,pdi,m_ema_fast_period,m_ema_slow_period);
        }
      //--- (3) Otherwise: ranging (the regime a grid actually wants).
      else
        {
         rc.regime = REGIME_RANGING;
         rc.detail = StringFormat("RANGING: ADX %.1f < %.1f or no EMA/DI agreement (ATR ratio %.2f)",
                                  adx,m_adx_trend_level,rc.atr_ratio);
        }

      rc.ready = true;
      LogDbg("RegimeFilter: "+rc.detail);
      return(rc);
     }

   //--- Is the trend strong enough that we must never oppose it?
   bool            IsStrongTrend(const RegimeContext &rc) const
     {
      if(!rc.ready) return(false);
      if(rc.regime!=REGIME_TREND_UP && rc.regime!=REGIME_TREND_DOWN) return(false);
      return(rc.adx >= m_adx_strong_level);
     }

   //================================================================//
   //  ALLOW SEED : may we START a fresh basket in `dir`?            //
   //                                                                //
   //  This is where the counter-trend seed - the root cause of the   //
   //  "sold into an uptrend then averaged 7 levels" blow-up - is     //
   //  refused. Under every policy, seeding AGAINST a detected trend  //
   //  is denied. VIOLENT always stands aside.                        //
   //================================================================//
   bool            AllowSeed(const ENUM_GRID_DIRECTION dir,const RegimeContext &rc,
                             const ENUM_GRID_POLICY policy,string &why) const
     {
      if(!rc.ready)
        {
         why = "regime not ready -> no seed";
         return(false);
        }

      //--- Volatility explosion: never start a grid into one.
      if(rc.regime==REGIME_VIOLENT)
        {
         why = "regime VIOLENT -> stand aside (no new basket)";
         return(false);
        }

      //--- HARD RULE (all policies): never seed against a detected trend.
      if(rc.regime==REGIME_TREND_UP && dir==GRID_SELL)
        {
         why = "counter-trend seed refused: HTF TREND_UP, requested SELL";
         return(false);
        }
      if(rc.regime==REGIME_TREND_DOWN && dir==GRID_BUY)
        {
         why = "counter-trend seed refused: HTF TREND_DOWN, requested BUY";
         return(false);
        }

      //--- Policy-specific gating.
      switch(policy)
        {
         case POLICY_RANGING_ONLY:
            if(rc.regime!=REGIME_RANGING)
              {
               why = "policy RANGING_ONLY and regime is "+RegimeName(rc.regime);
               return(false);
              }
            break;

         case POLICY_WITH_TREND_ONLY:
            if(rc.regime!=REGIME_TREND_UP && rc.regime!=REGIME_TREND_DOWN)
              {
               why = "policy WITH_TREND_ONLY and regime is "+RegimeName(rc.regime);
               return(false);
              }
            break;

         case POLICY_RANGING_AND_TREND:
         default:
            //--- ranging or with-trend both fine (counter-trend already denied)
            break;
        }

      why = "seed permitted in regime "+RegimeName(rc.regime);
      return(true);
     }

   //================================================================//
   //  ALLOW AVERAGING : may we ENLARGE an existing basket in `dir`? //
   //                                                                //
   //  THIS IS THE MOST IMPORTANT GATE IN THE WHOLE EA.              //
   //                                                                //
   //  Adding more volume to a basket that is on the wrong side of a  //
   //  dominant trend is precisely how grid accounts die. Once the    //
   //  higher timeframe is trending against the basket we STOP        //
   //  ENLARGING it. The basket is not closed here and no loss is     //
   //  realised by this function - it simply stops growing, which     //
   //  caps the exposure that the recovery / stop logic then has to   //
   //  resolve.                                                       //
   //================================================================//
   bool            AllowAveraging(const ENUM_GRID_DIRECTION basket_dir,
                                  const RegimeContext &rc,string &why) const
     {
      if(!rc.ready)
        {
         why = "regime not ready -> no averaging";
         return(false);
        }

      //--- Volatility explosion: do not feed a basket into it.
      if(rc.regime==REGIME_VIOLENT)
        {
         why = "regime VIOLENT -> averaging suspended";
         return(false);
        }

      //--- The core rule: never enlarge a basket that opposes the trend.
      if(rc.regime==REGIME_TREND_UP && basket_dir==GRID_SELL)
        {
         why = "averaging REFUSED: SELL basket against HTF TREND_UP (ADX "+
               DoubleToString(rc.adx,1)+")";
         return(false);
        }
      if(rc.regime==REGIME_TREND_DOWN && basket_dir==GRID_BUY)
        {
         why = "averaging REFUSED: BUY basket against HTF TREND_DOWN (ADX "+
               DoubleToString(rc.adx,1)+")";
         return(false);
        }

      why = "averaging permitted in regime "+RegimeName(rc.regime);
      return(true);
     }
  };

#endif // ADAPTIVEGRID_REGIMEFILTER_MQH
//+------------------------------------------------------------------+
