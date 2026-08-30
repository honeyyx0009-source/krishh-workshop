//+------------------------------------------------------------------+
//|                                               MarketAnalysis.mqh |
//|   Adaptive Gold Grid EA - Classical multi-indicator + price-      |
//|   action market analysis engine.                                  |
//+------------------------------------------------------------------+
//| PURPOSE                                                          |
//|   Consolidates several CLASSICAL technical signals into one       |
//|   easy-to-consume MarketContext struct that the grid and recovery |
//|   engines read each tick / bar:                                   |
//|     * Trend bias      : fast/slow MA relationship + slope.        |
//|     * Momentum         : MACD histogram + RSI regime.             |
//|     * Volatility        : ATR value + ATR percentile regime.      |
//|     * Structure         : swing-high / swing-low support &        |
//|                           resistance over a lookback window.      |
//|                                                                  |
//| HONEST LABELLING (READ THIS)                                     |
//|   These are ordinary, deterministic technical indicators and      |
//|   price-action rules. They are NOT machine learning. There is no  |
//|   LSTM / CNN / GRU / neural network here and nothing in this file  |
//|   should ever be described as "AI" or "ML". Optional ONNX          |
//|   inference is a SEPARATE, clearly-marked module delivered later.  |
//|                                                                  |
//| DEFENSIVE DESIGN                                                 |
//|   Every indicator handle is validated on creation. If any handle  |
//|   is invalid the engine reports "not ready" and downstream code   |
//|   must refrain from opening new orders. Handles are released in    |
//|   Deinit so the terminal never leaks indicator resources.         |
//+------------------------------------------------------------------+
#ifndef ADAPTIVEGRID_MARKETANALYSIS_MQH
#define ADAPTIVEGRID_MARKETANALYSIS_MQH

#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Trend direction bias.                                            |
//+------------------------------------------------------------------+
enum ENUM_TREND_DIR
  {
   TREND_NONE = 0,   // No clear bias / flat
   TREND_UP,         // Bullish bias (fast MA above slow, rising)
   TREND_DOWN        // Bearish bias (fast MA below slow, falling)
  };

//+------------------------------------------------------------------+
//| Volatility regime classification (derived from ATR percentile).  |
//+------------------------------------------------------------------+
enum ENUM_VOL_REGIME
  {
   VOL_CALM = 0,     // Below-average volatility -> tighten grid
   VOL_NORMAL,       // Around-average volatility
   VOL_HIGH          // Above-average volatility -> widen grid
  };

//+------------------------------------------------------------------+
//| MarketContext                                                    |
//|   The single consolidated read-out consumed by GridEngine,       |
//|   LotSizer and RecoveryEngine. Everything downstream needs about  |
//|   the market state lives here.                                    |
//+------------------------------------------------------------------+
struct MarketContext
  {
   bool             ready;            // false => analysis unavailable this tick (do NOT trade)
   ENUM_TREND_DIR   trend;            // Consolidated trend bias
   ENUM_VOL_REGIME  vol_regime;       // Volatility regime classification
   double           atr_value;        // Raw ATR value (price units, e.g. USD for gold)
   double           atr_points;       // ATR expressed in POINTS (atr_value / _Point)
   double           atr_percentile;   // 0..1 where current ATR sits vs its recent range
   double           momentum_score;   // -1..+1 blended MACD/RSI momentum (sign = direction)
   double           rsi_value;        // Latest RSI (0..100) for reference / logging
   double           macd_hist;        // Latest MACD histogram (main - signal)
   double           support;          // Nearest swing-low support below current price (0 if none)
   double           resistance;       // Nearest swing-high resistance above current price (0 if none)
   double           bid;              // Snapshot bid at evaluation
   double           ask;              // Snapshot ask at evaluation
  };

//+------------------------------------------------------------------+
//| CMarketAnalysis                                                  |
//+------------------------------------------------------------------+
class CMarketAnalysis
  {
private:
   CLogger          *m_log;           // Optional logger (may be NULL)
   string            m_symbol;        // Symbol under analysis
   ENUM_TIMEFRAMES   m_tf;            // Analysis timeframe

   //--- Indicator handles (INVALID_HANDLE until Init succeeds).
   int               m_h_rsi;         // RSI
   int               m_h_macd;        // MACD
   int               m_h_atr;         // ATR
   int               m_h_ma_fast;     // Fast moving average
   int               m_h_ma_slow;     // Slow moving average

   //--- Indicator parameters.
   int               m_rsi_period;
   int               m_macd_fast;
   int               m_macd_slow;
   int               m_macd_signal;
   int               m_atr_period;
   int               m_ma_fast_period;
   int               m_ma_slow_period;

   //--- Structural analysis parameters.
   int               m_sr_lookback;   // Bars scanned for swing S/R
   int               m_swing_strength;// Bars each side required to confirm a swing
   int               m_atr_percentile_lookback; // Bars used for the ATR percentile

   bool              m_ready;         // All handles valid?

   void              LogErr(const string m)  { if(m_log!=NULL) m_log.Error(m); }
   void              LogWarn(const string m) { if(m_log!=NULL) m_log.Warn(m);  }
   void              LogInfo(const string m) { if(m_log!=NULL) m_log.Info(m);  }
   void              LogDbg(const string m)  { if(m_log!=NULL) m_log.Debug(m); }

   //--- Copy a single value from an indicator buffer defensively.
   //    Returns false if the copy fails (data not yet ready).
   bool              CopyOne(const int handle,const int buffer,const int shift,double &out) const
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
                     CMarketAnalysis(void)
     {
      m_log                     = NULL;
      m_symbol                  = _Symbol;
      m_tf                      = PERIOD_M15;
      m_h_rsi                   = INVALID_HANDLE;
      m_h_macd                  = INVALID_HANDLE;
      m_h_atr                   = INVALID_HANDLE;
      m_h_ma_fast               = INVALID_HANDLE;
      m_h_ma_slow               = INVALID_HANDLE;
      m_rsi_period              = 14;
      m_macd_fast               = 12;
      m_macd_slow               = 26;
      m_macd_signal             = 9;
      m_atr_period              = 14;
      m_ma_fast_period          = 20;
      m_ma_slow_period          = 50;
      m_sr_lookback             = 120;
      m_swing_strength          = 3;
      m_atr_percentile_lookback = 100;
      m_ready                   = false;
     }
                    ~CMarketAnalysis(void) { Deinit(); }

   //================================================================//
   //  INIT : create every indicator handle, validate defensively.  //
   //================================================================//
   bool              Init(const string symbol,const ENUM_TIMEFRAMES tf,CLogger *logger=NULL,
                          const int rsi_period=14,
                          const int macd_fast=12,const int macd_slow=26,const int macd_signal=9,
                          const int atr_period=14,
                          const int ma_fast=20,const int ma_slow=50,
                          const int sr_lookback=120,const int swing_strength=3,
                          const int atr_percentile_lookback=100)
     {
      m_symbol                  = symbol;
      m_tf                      = tf;
      m_log                     = logger;
      m_rsi_period              = rsi_period;
      m_macd_fast               = macd_fast;
      m_macd_slow               = macd_slow;
      m_macd_signal             = macd_signal;
      m_atr_period              = atr_period;
      m_ma_fast_period          = ma_fast;
      m_ma_slow_period          = ma_slow;
      m_sr_lookback             = sr_lookback;
      m_swing_strength          = swing_strength;
      m_atr_percentile_lookback = atr_percentile_lookback;

      //--- create handles
      m_h_rsi     = iRSI(m_symbol,m_tf,m_rsi_period,PRICE_CLOSE);
      m_h_macd    = iMACD(m_symbol,m_tf,m_macd_fast,m_macd_slow,m_macd_signal,PRICE_CLOSE);
      m_h_atr     = iATR(m_symbol,m_tf,m_atr_period);
      m_h_ma_fast = iMA(m_symbol,m_tf,m_ma_fast_period,0,MODE_EMA,PRICE_CLOSE);
      m_h_ma_slow = iMA(m_symbol,m_tf,m_ma_slow_period,0,MODE_EMA,PRICE_CLOSE);

      m_ready = (m_h_rsi!=INVALID_HANDLE && m_h_macd!=INVALID_HANDLE &&
                 m_h_atr!=INVALID_HANDLE && m_h_ma_fast!=INVALID_HANDLE &&
                 m_h_ma_slow!=INVALID_HANDLE);

      if(!m_ready)
        {
         LogErr("MarketAnalysis.Init: one or more indicator handles failed to create.");
         Deinit();  // release whatever succeeded so we do not leak
         return(false);
        }

      LogInfo(StringFormat("MarketAnalysis ready on %s tf=%d (RSI/MACD/ATR/MA%d/MA%d).",
                           m_symbol,(int)m_tf,m_ma_fast_period,m_ma_slow_period));
      return(true);
     }

   //================================================================//
   //  DEINIT : release every valid handle. Safe to call repeatedly. //
   //================================================================//
   void              Deinit(void)
     {
      if(m_h_rsi    !=INVALID_HANDLE) { IndicatorRelease(m_h_rsi);     m_h_rsi=INVALID_HANDLE; }
      if(m_h_macd   !=INVALID_HANDLE) { IndicatorRelease(m_h_macd);    m_h_macd=INVALID_HANDLE; }
      if(m_h_atr    !=INVALID_HANDLE) { IndicatorRelease(m_h_atr);     m_h_atr=INVALID_HANDLE; }
      if(m_h_ma_fast!=INVALID_HANDLE) { IndicatorRelease(m_h_ma_fast); m_h_ma_fast=INVALID_HANDLE; }
      if(m_h_ma_slow!=INVALID_HANDLE) { IndicatorRelease(m_h_ma_slow); m_h_ma_slow=INVALID_HANDLE; }
      m_ready=false;
     }

   bool              IsReady(void) const { return(m_ready); }

   //================================================================//
   //  SWING SUPPORT / RESISTANCE                                    //
   //  Scan the lookback window for fractal-style swing highs/lows.  //
   //  A bar is a swing high if its high is the highest within        //
   //  m_swing_strength bars on each side; symmetric for swing low.   //
   //  We keep the NEAREST resistance above and support below price.  //
   //================================================================//
   void              DetectSupportResistance(double &support,double &resistance) const
     {
      support    = 0.0;
      resistance = 0.0;

      int need = m_sr_lookback + m_swing_strength*2 + 2;
      double highs[], lows[];
      ArraySetAsSeries(highs,true);
      ArraySetAsSeries(lows,true);
      if(CopyHigh(m_symbol,m_tf,0,need,highs) < need) return;
      if(CopyLow(m_symbol,m_tf,0,need,lows)  < need) return;

      double price = SymbolInfoDouble(m_symbol,SYMBOL_BID);
      double best_res_dist = DBL_MAX;
      double best_sup_dist = DBL_MAX;

      //--- start at m_swing_strength so both sides exist in the array
      for(int i=m_swing_strength; i<m_sr_lookback+m_swing_strength; i++)
        {
         bool is_high=true, is_low=true;
         for(int k=1;k<=m_swing_strength;k++)
           {
            if(highs[i] < highs[i-k] || highs[i] < highs[i+k]) is_high=false;
            if(lows[i]  > lows[i-k]  || lows[i]  > lows[i+k])  is_low=false;
            if(!is_high && !is_low) break;
           }
         if(is_high && highs[i] > price)
           {
            double d = highs[i] - price;
            if(d < best_res_dist) { best_res_dist=d; resistance=highs[i]; }
           }
         if(is_low && lows[i] < price)
           {
            double d = price - lows[i];
            if(d < best_sup_dist) { best_sup_dist=d; support=lows[i]; }
           }
        }
     }

   //================================================================//
   //  ATR PERCENTILE + REGIME                                       //
   //  Where does the latest ATR sit in its own recent range?        //
   //  0 => calmest in the window, 1 => most volatile.               //
   //================================================================//
   double            AtrPercentile(void) const
     {
      if(m_h_atr==INVALID_HANDLE) return(0.5);
      int n = m_atr_percentile_lookback;
      double buf[];
      ArraySetAsSeries(buf,true);
      if(CopyBuffer(m_h_atr,0,0,n,buf) < n) return(0.5);

      double cur = buf[0];
      double lo  = buf[0], hi = buf[0];
      for(int i=1;i<n;i++)
        {
         if(buf[i]<lo) lo=buf[i];
         if(buf[i]>hi) hi=buf[i];
        }
      double range = hi-lo;
      if(range<=0.0) return(0.5);
      double pct = (cur-lo)/range;
      if(pct<0.0) pct=0.0;
      if(pct>1.0) pct=1.0;
      return(pct);
     }

   //================================================================//
   //  EVALUATE : build the consolidated MarketContext.              //
   //  Call once per new bar (or per tick if desired). Returns a      //
   //  context with ready=false if any required data is unavailable.  //
   //================================================================//
   MarketContext     Evaluate(void)
     {
      MarketContext c;
      c.ready          = false;
      c.trend          = TREND_NONE;
      c.vol_regime     = VOL_NORMAL;
      c.atr_value      = 0.0;
      c.atr_points     = 0.0;
      c.atr_percentile = 0.5;
      c.momentum_score = 0.0;
      c.rsi_value      = 50.0;
      c.macd_hist      = 0.0;
      c.support        = 0.0;
      c.resistance     = 0.0;
      c.bid            = SymbolInfoDouble(m_symbol,SYMBOL_BID);
      c.ask            = SymbolInfoDouble(m_symbol,SYMBOL_ASK);

      if(!m_ready)
        {
         LogWarn("MarketAnalysis.Evaluate: engine not ready (invalid handles).");
         return(c);
        }

      //--- ATR (buffer 0). Latest closed value at shift 1 for stability.
      double atr=0.0;
      if(!CopyOne(m_h_atr,0,1,atr))
        {
         LogDbg("MarketAnalysis.Evaluate: ATR buffer not ready.");
         return(c);
        }
      double point = SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      if(point<=0.0) point=_Point;
      c.atr_value  = atr;
      c.atr_points = (point>0.0 ? atr/point : 0.0);

      //--- ATR percentile + regime classification.
      c.atr_percentile = AtrPercentile();
      if(c.atr_percentile <= 0.33)      c.vol_regime = VOL_CALM;
      else if(c.atr_percentile >= 0.66) c.vol_regime = VOL_HIGH;
      else                              c.vol_regime = VOL_NORMAL;

      //--- Moving averages (fast vs slow) + fast-MA slope for trend.
      double ma_fast_0=0.0, ma_fast_2=0.0, ma_slow_0=0.0;
      if(!CopyOne(m_h_ma_fast,0,1,ma_fast_0) ||
         !CopyOne(m_h_ma_fast,0,3,ma_fast_2) ||
         !CopyOne(m_h_ma_slow,0,1,ma_slow_0))
        {
         LogDbg("MarketAnalysis.Evaluate: MA buffers not ready.");
         return(c);
        }
      double slope = ma_fast_0 - ma_fast_2;   // rising if > 0
      if(ma_fast_0 > ma_slow_0 && slope > 0.0)      c.trend = TREND_UP;
      else if(ma_fast_0 < ma_slow_0 && slope < 0.0) c.trend = TREND_DOWN;
      else                                          c.trend = TREND_NONE;

      //--- RSI regime (buffer 0).
      double rsi=50.0;
      if(!CopyOne(m_h_rsi,0,1,rsi))
        {
         LogDbg("MarketAnalysis.Evaluate: RSI buffer not ready.");
         return(c);
        }
      c.rsi_value = rsi;

      //--- MACD histogram = main(0) - signal(1).
      double macd_main=0.0, macd_sig=0.0;
      if(!CopyOne(m_h_macd,0,1,macd_main) || !CopyOne(m_h_macd,1,1,macd_sig))
        {
         LogDbg("MarketAnalysis.Evaluate: MACD buffers not ready.");
         return(c);
        }
      c.macd_hist = macd_main - macd_sig;

      //--- Blended momentum score in [-1,+1].
      //    RSI centred at 50 and scaled; MACD histogram sign-normalised.
      double rsi_component  = (rsi - 50.0) / 50.0;                       // -1..+1
      double macd_component = (c.macd_hist > 0.0 ? 1.0 : (c.macd_hist < 0.0 ? -1.0 : 0.0));
      c.momentum_score = 0.5*rsi_component + 0.5*macd_component;
      if(c.momentum_score >  1.0) c.momentum_score =  1.0;
      if(c.momentum_score < -1.0) c.momentum_score = -1.0;

      //--- Price-action structure.
      DetectSupportResistance(c.support,c.resistance);

      c.ready = true;
      LogDbg(StringFormat("MC ready: trend=%d vol=%d atr_pts=%.1f mom=%.2f rsi=%.1f S=%.2f R=%.2f",
                          (int)c.trend,(int)c.vol_regime,c.atr_points,c.momentum_score,
                          c.rsi_value,c.support,c.resistance));
      return(c);
     }
  };

#endif // ADAPTIVEGRID_MARKETANALYSIS_MQH
//+------------------------------------------------------------------+
