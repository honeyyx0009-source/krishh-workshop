//+------------------------------------------------------------------+
//|                                                MarketContext.mqh |
//|          001 PERCEPTION - Unified market snapshot builder         |
//|                                                                  |
//| MarketContext is the analysis layer's public face. Once per bar  |
//| it refreshes the indicator hub, runs structure analysis, probes  |
//| the two higher timeframes for trend agreement and stamps the     |
//| active trading session. The result is one SMarketState that the  |
//| whole framework treats as ground truth for the current bar.      |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_ANALYSIS_MARKETCONTEXT_MQH
#define PERCEPTION_ANALYSIS_MARKETCONTEXT_MQH

#include <Perception/Analysis/IndicatorHub.mqh>
#include <Perception/Analysis/MarketStructure.mqh>
#include <Perception/Core/SymbolMeta.mqh>

class CMarketContext
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf, m_tfMid, m_tfHigh;
   int               m_gmtOffset;

   CIndicatorHub     m_hub;
   CMarketStructure  m_struct;
   SMarketState      m_state;

   //--- MTF trend probes --------------------------------------------
   int               h_emaFmid, h_emaSmid, h_emaFhigh, h_emaShigh;

   double ReadHandle(const int handle,const int shift=1)
     {
      if(handle==INVALID_HANDLE) return 0.0;
      double tmp[]; ArraySetAsSeries(tmp,true);
      if(CopyBuffer(handle,0,0,shift+2,tmp)<shift+1) return 0.0;
      return tmp[shift];
     }

   ENUM_TREND_DIR TrendFromEma(const int fast,const int slow,const string sym,const ENUM_TIMEFRAMES tf)
     {
      double f=ReadHandle(fast), s=ReadHandle(slow);
      if(f<=0.0 || s<=0.0) return TREND_FLAT;
      double px=iClose(sym,tf,1);
      if(f>s && px>=s) return TREND_UP;
      if(f<s && px<=s) return TREND_DOWN;
      return TREND_FLAT;
     }

   void ClassifyTrend()
     {
      double f=m_hub.EmaFast(), s=m_hub.EmaSlow(), t=m_hub.EmaTrend();
      double mid=m_state.mid;
      ENUM_TREND_DIR dir=TREND_FLAT;
      if(f>s && mid>t)      dir=TREND_UP;
      else if(f<s && mid<t) dir=TREND_DOWN;
      else if(f>s)          dir=TREND_UP;
      else if(f<s)          dir=TREND_DOWN;
      m_state.trend=dir;

      double adxComp=PU::Normalize01(m_hub.ADX(),15.0,45.0);
      double diSum=m_hub.PlusDI()+m_hub.MinusDI();
      double diComp=PU::SafeDiv(MathAbs(m_hub.PlusDI()-m_hub.MinusDI()),diSum,0.0);
      double sep=PU::SafeDiv(MathAbs(f-s),(m_state.atr>0?m_state.atr:1.0),0.0);
      double emaComp=PU::Normalize01(sep,0.0,2.0);
      m_state.trendStrength=PU::Clamp(0.5*adxComp+0.25*diComp+0.25*emaComp,0.0,1.0);
     }

   void ClassifyVolatility()
     {
      m_state.atrAvg=m_hub.ATRBase();
      m_state.volRatio=PU::SafeDiv(m_hub.ATR(),m_state.atrAvg,1.0);
      double r=m_state.volRatio;
      if(r<0.75)      m_state.vol=VOL_CALM;
      else if(r<1.25) m_state.vol=VOL_NORMAL;
      else if(r<1.8)  m_state.vol=VOL_ELEVATED;
      else            m_state.vol=VOL_EXTREME;
     }

   void ComputeMTF()
     {
      m_state.trendLow=m_state.trend;
      m_state.trendMid=TrendFromEma(h_emaFmid,h_emaSmid,m_symbol,m_tfMid);
      m_state.trendHigh=TrendFromEma(h_emaFhigh,h_emaShigh,m_symbol,m_tfHigh);
      //--- agreement fraction toward the low-TF direction ------------
      if(m_state.trendLow==TREND_FLAT){ m_state.mtfAlignment=0.34; return; }
      int agree=1;
      if(m_state.trendMid==m_state.trendLow) agree++;
      if(m_state.trendHigh==m_state.trendLow) agree++;
      m_state.mtfAlignment=agree/3.0;
     }

   void StampSession()
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(),dt);
      int gmtHour=((dt.hour-m_gmtOffset)%24+24)%24;
      m_state.sessionAsia  =(gmtHour>=0  && gmtHour<9);
      m_state.sessionLondon=(gmtHour>=7  && gmtHour<16);
      m_state.sessionNY    =(gmtHour>=12 && gmtHour<21);
     }

public:
                     CMarketContext()
     {
      h_emaFmid=h_emaSmid=h_emaFhigh=h_emaShigh=INVALID_HANDLE;
     }
                    ~CMarketContext()
     {
      if(h_emaFmid!=INVALID_HANDLE)  IndicatorRelease(h_emaFmid);
      if(h_emaSmid!=INVALID_HANDLE)  IndicatorRelease(h_emaSmid);
      if(h_emaFhigh!=INVALID_HANDLE) IndicatorRelease(h_emaFhigh);
      if(h_emaShigh!=INVALID_HANDLE) IndicatorRelease(h_emaShigh);
     }

   bool Init(const string symbol,const ENUM_TIMEFRAMES tf,
             const ENUM_TIMEFRAMES tfMid,const ENUM_TIMEFRAMES tfHigh,
             const int gmtOffset,const SIndicatorCfg &cfg)
     {
      m_symbol=symbol; m_tf=tf; m_tfMid=tfMid; m_tfHigh=tfHigh; m_gmtOffset=gmtOffset;
      m_state.Reset();
      if(!m_hub.Init(symbol,tf,cfg)) return false;
      h_emaFmid =iMA(symbol,tfMid,cfg.emaFast,0,MODE_EMA,PRICE_CLOSE);
      h_emaSmid =iMA(symbol,tfMid,cfg.emaSlow,0,MODE_EMA,PRICE_CLOSE);
      h_emaFhigh=iMA(symbol,tfHigh,cfg.emaFast,0,MODE_EMA,PRICE_CLOSE);
      h_emaShigh=iMA(symbol,tfHigh,cfg.emaSlow,0,MODE_EMA,PRICE_CLOSE);
      return true;
     }

   //--- rebuild the snapshot for the current bar ---------------------
   bool Update()
     {
      if(!m_hub.Refresh()) return false;

      double bid=SymbolInfoDouble(m_symbol,SYMBOL_BID);
      double ask=SymbolInfoDouble(m_symbol,SYMBOL_ASK);
      double pt =SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      m_state.time=iTime(m_symbol,m_tf,0);
      m_state.bid=bid; m_state.ask=ask; m_state.mid=0.5*(bid+ask);
      m_state.spreadPts=PU::SafeDiv(ask-bid,pt,0.0);

      m_state.atr=m_hub.ATR();
      m_state.atrPct=PU::SafeDiv(m_state.atr,m_state.mid,0.0);
      m_state.adx=m_hub.ADX();
      m_state.plusDI=m_hub.PlusDI();
      m_state.minusDI=m_hub.MinusDI();
      m_state.rsi=m_hub.RSI();
      m_state.cci=m_hub.CCI();
      m_state.stochMain=m_hub.StochMain();
      m_state.stochSignal=m_hub.StochSig();
      m_state.macdMain=m_hub.MacdMain();
      m_state.macdSignal=m_hub.MacdSig();
      m_state.macdHist=m_hub.MacdHist();
      m_state.emaFast=m_hub.EmaFast();
      m_state.emaSlow=m_hub.EmaSlow();
      m_state.emaTrend=m_hub.EmaTrend();
      m_state.sma=m_hub.SMA();
      m_state.vwap=m_hub.VWAP();
      m_state.bbUpper=m_hub.BBUpper();
      m_state.bbMid=m_hub.BBMid();
      m_state.bbLower=m_hub.BBLower();
      m_state.bbWidth=PU::SafeDiv(m_hub.BBUpper()-m_hub.BBLower(),m_hub.BBMid(),0.0);
      m_state.keltUpper=m_hub.KeltUpper();
      m_state.keltLower=m_hub.KeltLower();
      m_state.donchUpper=m_hub.DonUpper();
      m_state.donchLower=m_hub.DonLower();

      ClassifyVolatility();
      ClassifyTrend();
      m_struct.Analyze(m_symbol,m_tf,m_state);
      ComputeMTF();
      StampSession();
      return true;
     }

   const SMarketState State() const { return m_state; }
   CIndicatorHub *Hub() { return GetPointer(m_hub); }
  };

#endif // PERCEPTION_ANALYSIS_MARKETCONTEXT_MQH
//+------------------------------------------------------------------+
