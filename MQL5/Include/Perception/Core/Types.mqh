//+------------------------------------------------------------------+
//|                                                        Types.mqh |
//|                 001 PERCEPTION - Shared data structures           |
//|                                                                  |
//| These plain structs are the "vocabulary" exchanged between the   |
//| analysis layer, the engines, the intelligence layer, the risk    |
//| manager and the dashboard. They deliberately contain data only   |
//| (no behaviour) so they can be copied cheaply and passed around   |
//| without ownership concerns.                                      |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_CORE_TYPES_MQH
#define PERCEPTION_CORE_TYPES_MQH

#include <Perception/Core/Enums.mqh>

//+------------------------------------------------------------------+
//| A trade intention produced by an engine.                        |
//| Prices left at 0 mean "let the execution layer decide".         |
//+------------------------------------------------------------------+
struct SSignal
  {
   ENUM_SIGNAL_DIR   dir;         // BUY / SELL / NONE
   ENUM_ENTRY_TYPE   entry;       // market / limit / stop
   double            price;       // desired entry (0 => current market)
   double            sl;          // stop loss (0 => risk manager fills)
   double            tp;          // take profit (0 => risk manager fills)
   double            lots;        // volume (0 => risk manager sizes)
   double            confidence;  // engine's own belief in the setup [0..1]
   double            quality;     // structural quality of the setup [0..1]
   double            rr;          // desired reward-to-risk (0 => default)
   ENUM_ENGINE_ID    engine;      // author of the signal
   string            reason;      // human readable justification

   void Reset()
     {
      dir=SIG_NONE; entry=ENTRY_MARKET; price=0; sl=0; tp=0; lots=0;
      confidence=0; quality=0; rr=0; engine=ENG_NONE; reason="";
     }
   bool IsValid() const { return(dir!=SIG_NONE); }
  };

//+------------------------------------------------------------------+
//| A full snapshot of the market as understood by the analysis      |
//| layer on a given bar. Engines read this instead of recomputing   |
//| indicators themselves, which keeps CPU usage low.                |
//+------------------------------------------------------------------+
struct SMarketState
  {
   datetime          time;            // bar time of the snapshot
   //--- prices
   double            bid;
   double            ask;
   double            mid;
   double            spreadPts;        // spread in points
   //--- volatility / strength
   double            atr;              // ATR (price units)
   double            atrPct;           // ATR / price
   double            atrAvg;           // longer ATR baseline
   double            volRatio;         // atr / atrAvg
   ENUM_VOL_STATE    vol;
   double            adx;
   double            plusDI;
   double            minusDI;
   //--- oscillators
   double            rsi;
   double            cci;
   double            stochMain;
   double            stochSignal;
   double            macdMain;
   double            macdSignal;
   double            macdHist;
   //--- moving structure
   double            emaFast;
   double            emaSlow;
   double            emaTrend;         // long baseline (e.g. 200)
   double            sma;
   double            vwap;
   //--- channels
   double            bbUpper;
   double            bbMid;
   double            bbLower;
   double            bbWidth;          // (upper-lower)/mid
   double            keltUpper;
   double            keltLower;
   double            donchUpper;
   double            donchLower;
   //--- derived trend
   ENUM_TREND_DIR    trend;
   double            trendStrength;    // [0..1]
   //--- market structure
   double            swingHigh;
   double            swingLow;
   ENUM_TREND_DIR    structureBias;
   bool              madeHH;
   bool              madeHL;
   bool              madeLH;
   bool              madeLL;
   double            nearestSupport;
   double            nearestResistance;
   //--- multi timeframe alignment
   ENUM_TREND_DIR    trendLow;         // trading TF
   ENUM_TREND_DIR    trendMid;         // one step up
   ENUM_TREND_DIR    trendHigh;        // two steps up
   double            mtfAlignment;     // [0..1] agreement across TFs
   //--- classified regime
   ENUM_MARKET_REGIME regime;
   double            regimeConfidence; // [0..1]
   //--- session
   bool              sessionAsia;
   bool              sessionLondon;
   bool              sessionNY;

   void Reset()
     {
      time=0; bid=0; ask=0; mid=0; spreadPts=0;
      atr=0; atrPct=0; atrAvg=0; volRatio=0; vol=VOL_CALM;
      adx=0; plusDI=0; minusDI=0; rsi=0; cci=0;
      stochMain=0; stochSignal=0; macdMain=0; macdSignal=0; macdHist=0;
      emaFast=0; emaSlow=0; emaTrend=0; sma=0; vwap=0;
      bbUpper=0; bbMid=0; bbLower=0; bbWidth=0;
      keltUpper=0; keltLower=0; donchUpper=0; donchLower=0;
      trend=TREND_FLAT; trendStrength=0;
      swingHigh=0; swingLow=0; structureBias=TREND_FLAT;
      madeHH=false; madeHL=false; madeLH=false; madeLL=false;
      nearestSupport=0; nearestResistance=0;
      trendLow=TREND_FLAT; trendMid=TREND_FLAT; trendHigh=TREND_FLAT; mtfAlignment=0;
      regime=REGIME_UNKNOWN; regimeConfidence=0;
      sessionAsia=false; sessionLondon=false; sessionNY=false;
     }
  };

//+------------------------------------------------------------------+
//| Running performance record for a single engine. The intelligence |
//| layer uses these numbers to "learn" which engines to trust.      |
//+------------------------------------------------------------------+
struct SEngineStats
  {
   int      trades;
   int      wins;
   int      losses;
   double   grossProfit;
   double   grossLoss;      // stored as a positive magnitude
   double   netProfit;
   double   lastResult;
   double   expectancy;     // running expectancy per trade
   double   confMultiplier; // adaptive trust multiplier [0.5..1.5]
   int      lossStreak;     // consecutive losing trades

   void Reset()
     {
      trades=0; wins=0; losses=0; grossProfit=0; grossLoss=0;
      netProfit=0; lastResult=0; expectancy=0; confMultiplier=1.0; lossStreak=0;
     }
   double WinRate()      const { return(trades>0 ? (double)wins/trades : 0.0); }
   double ProfitFactor() const { return(grossLoss>1e-9 ? grossProfit/grossLoss : (grossProfit>0?3.0:0.0)); }
  };

//+------------------------------------------------------------------+
//| The intelligence layer's evaluation of one engine on this bar.   |
//+------------------------------------------------------------------+
struct SEngineScore
  {
   ENUM_ENGINE_ID id;
   string         name;
   SSignal        signal;
   double         suitability;   // fit to current regime [0..1]
   double         aiConfidence;  // AI adjusted confidence [0..1]
   double         finalScore;    // ranking key
   bool           accepted;
   string         note;          // reason for accept / reject

   void Reset()
     {
      id=ENG_NONE; name=""; signal.Reset(); suitability=0;
      aiConfidence=0; finalScore=0; accepted=false; note="";
     }
  };

//+------------------------------------------------------------------+
//| A single line in the live decision log shown on the dashboard.   |
//+------------------------------------------------------------------+
struct SDecision
  {
   datetime       time;
   ENUM_ENGINE_ID engine;
   bool           accepted;
   string         text;
  };

//+------------------------------------------------------------------+
//| Aggregate account / portfolio statistics for the stats module.   |
//+------------------------------------------------------------------+
struct SPortfolioStats
  {
   double  winRate;
   double  lossRate;
   double  profitFactor;
   double  recoveryFactor;
   double  sharpe;
   double  expectancy;
   double  avgRR;
   double  largestWin;
   double  largestLoss;
   int     tradesToday;
   int     tradesWeek;
   int     tradesMonth;
   double  currentDD;      // fraction [0..1]
   double  maxDD;          // fraction [0..1]

   void Reset()
     {
      winRate=0; lossRate=0; profitFactor=0; recoveryFactor=0; sharpe=0;
      expectancy=0; avgRR=0; largestWin=0; largestLoss=0;
      tradesToday=0; tradesWeek=0; tradesMonth=0; currentDD=0; maxDD=0;
     }
  };

#endif // PERCEPTION_CORE_TYPES_MQH
//+------------------------------------------------------------------+
