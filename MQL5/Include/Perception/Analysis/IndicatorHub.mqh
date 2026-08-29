//+------------------------------------------------------------------+
//|                                                 IndicatorHub.mqh |
//|             001 PERCEPTION - Indicator handle manager             |
//|                                                                  |
//| Every professional indicator the framework relies on is created  |
//| exactly once here and refreshed a single time per bar. Engines   |
//| then read cached doubles instead of each calling CopyBuffer,     |
//| which is the single biggest CPU saving in a multi-strategy EA.   |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_ANALYSIS_INDICATORHUB_MQH
#define PERCEPTION_ANALYSIS_INDICATORHUB_MQH

#include <Perception/Core/Utils.mqh>

//--- indicator periods (sane professional defaults) -----------------
struct SIndicatorCfg
  {
   int atr, atrBase, adx, rsi, cci;
   int macdFast, macdSlow, macdSignal;
   int stochK, stochD, stochSlow;
   int emaFast, emaSlow, emaTrend, sma;
   int bbPeriod; double bbDev;
   int donchian; int vwapBars;

   void Defaults()
     {
      atr=14; atrBase=50; adx=14; rsi=14; cci=14;
      macdFast=12; macdSlow=26; macdSignal=9;
      stochK=5; stochD=3; stochSlow=3;
      emaFast=21; emaSlow=50; emaTrend=200; sma=100;
      bbPeriod=20; bbDev=2.0;
      donchian=20; vwapBars=100;
     }
  };

class CIndicatorHub
  {
private:
   string   m_symbol;
   ENUM_TIMEFRAMES m_tf;
   SIndicatorCfg m_cfg;
   //--- handles
   int h_atr, h_atrBase, h_adx, h_rsi, h_cci, h_macd, h_stoch;
   int h_emaF, h_emaS, h_emaT, h_sma, h_bb;
   bool m_ready;

   //--- cached (index 1 = last closed bar) ---------------------------
   double c_atr, c_atrBase, c_adx, c_pdi, c_mdi, c_rsi, c_cci;
   double c_stochM, c_stochS, c_macdM, c_macdS;
   double c_emaF, c_emaS, c_emaT, c_sma;
   double c_bbU, c_bbM, c_bbL;
   double c_donU, c_donL, c_vwap;

   bool CopyOne(const int handle,const int buffer,double &out,const int shift=1)
     {
      if(handle==INVALID_HANDLE) return false;
      double tmp[];
      ArraySetAsSeries(tmp,true);
      if(CopyBuffer(handle,buffer,0,shift+2,tmp)<shift+1) return false;
      out=tmp[shift];
      return true;
     }

   void ComputeDonchian()
     {
      double hi[],lo[];
      ArraySetAsSeries(hi,true); ArraySetAsSeries(lo,true);
      int n=m_cfg.donchian;
      if(CopyHigh(m_symbol,m_tf,1,n,hi)==n && CopyLow(m_symbol,m_tf,1,n,lo)==n)
        {
         c_donU=hi[ArrayMaximum(hi)];
         c_donL=lo[ArrayMinimum(lo)];
        }
     }

   void ComputeVWAP()
     {
      int n=m_cfg.vwapBars;
      double hi[],lo[],cl[]; long vol[];
      ArraySetAsSeries(hi,true); ArraySetAsSeries(lo,true);
      ArraySetAsSeries(cl,true); ArraySetAsSeries(vol,true);
      if(CopyHigh(m_symbol,m_tf,1,n,hi)!=n) return;
      if(CopyLow(m_symbol,m_tf,1,n,lo)!=n) return;
      if(CopyClose(m_symbol,m_tf,1,n,cl)!=n) return;
      if(CopyTickVolume(m_symbol,m_tf,1,n,vol)!=n) return;
      double num=0.0,den=0.0;
      for(int i=0;i<n;i++)
        {
         double tp=(hi[i]+lo[i]+cl[i])/3.0;
         double v=(double)vol[i];
         num+=tp*v; den+=v;
        }
      c_vwap=PU::SafeDiv(num,den,cl[0]);
     }

public:
                     CIndicatorHub(): m_ready(false)
     {
      h_atr=h_atrBase=h_adx=h_rsi=h_cci=h_macd=h_stoch=INVALID_HANDLE;
      h_emaF=h_emaS=h_emaT=h_sma=h_bb=INVALID_HANDLE;
     }
                    ~CIndicatorHub() { Release(); }

   bool Init(const string symbol,const ENUM_TIMEFRAMES tf,const SIndicatorCfg &cfg)
     {
      m_symbol=symbol; m_tf=tf; m_cfg=cfg;
      h_atr    =iATR(symbol,tf,cfg.atr);
      h_atrBase=iATR(symbol,tf,cfg.atrBase);
      h_adx    =iADX(symbol,tf,cfg.adx);
      h_rsi    =iRSI(symbol,tf,cfg.rsi,PRICE_CLOSE);
      h_cci    =iCCI(symbol,tf,cfg.cci,PRICE_TYPICAL);
      h_macd   =iMACD(symbol,tf,cfg.macdFast,cfg.macdSlow,cfg.macdSignal,PRICE_CLOSE);
      h_stoch  =iStochastic(symbol,tf,cfg.stochK,cfg.stochD,cfg.stochSlow,MODE_SMA,STO_LOWHIGH);
      h_emaF   =iMA(symbol,tf,cfg.emaFast,0,MODE_EMA,PRICE_CLOSE);
      h_emaS   =iMA(symbol,tf,cfg.emaSlow,0,MODE_EMA,PRICE_CLOSE);
      h_emaT   =iMA(symbol,tf,cfg.emaTrend,0,MODE_EMA,PRICE_CLOSE);
      h_sma    =iMA(symbol,tf,cfg.sma,0,MODE_SMA,PRICE_CLOSE);
      h_bb     =iBands(symbol,tf,cfg.bbPeriod,0,cfg.bbDev,PRICE_CLOSE);

      m_ready = (h_atr!=INVALID_HANDLE && h_adx!=INVALID_HANDLE &&
                 h_rsi!=INVALID_HANDLE && h_macd!=INVALID_HANDLE &&
                 h_emaF!=INVALID_HANDLE && h_emaS!=INVALID_HANDLE &&
                 h_bb!=INVALID_HANDLE);
      return m_ready;
     }

   void Release()
     {
      int handles[]={h_atr,h_atrBase,h_adx,h_rsi,h_cci,h_macd,h_stoch,
                     h_emaF,h_emaS,h_emaT,h_sma,h_bb};
      for(int i=0;i<ArraySize(handles);i++)
         if(handles[i]!=INVALID_HANDLE) IndicatorRelease(handles[i]);
      m_ready=false;
     }

   //--- refresh all cached values (call once per new bar) ------------
   bool Refresh()
     {
      if(!m_ready) return false;
      CopyOne(h_atr,0,c_atr);
      CopyOne(h_atrBase,0,c_atrBase);
      CopyOne(h_adx,0,c_adx);
      CopyOne(h_adx,1,c_pdi);   // +DI
      CopyOne(h_adx,2,c_mdi);   // -DI
      CopyOne(h_rsi,0,c_rsi);
      CopyOne(h_cci,0,c_cci);
      CopyOne(h_stoch,0,c_stochM);
      CopyOne(h_stoch,1,c_stochS);
      CopyOne(h_macd,0,c_macdM);
      CopyOne(h_macd,1,c_macdS);
      CopyOne(h_emaF,0,c_emaF);
      CopyOne(h_emaS,0,c_emaS);
      CopyOne(h_emaT,0,c_emaT);
      CopyOne(h_sma,0,c_sma);
      CopyOne(h_bb,0,c_bbM);    // base line
      CopyOne(h_bb,1,c_bbU);    // upper
      CopyOne(h_bb,2,c_bbL);    // lower
      ComputeDonchian();
      ComputeVWAP();
      return true;
     }

   bool Ready() const { return m_ready; }

   //--- accessors ----------------------------------------------------
   double ATR()      const { return c_atr; }
   double ATRBase()  const { return c_atrBase; }
   double ADX()      const { return c_adx; }
   double PlusDI()   const { return c_pdi; }
   double MinusDI()  const { return c_mdi; }
   double RSI()      const { return c_rsi; }
   double CCI()      const { return c_cci; }
   double StochMain()const { return c_stochM; }
   double StochSig() const { return c_stochS; }
   double MacdMain() const { return c_macdM; }
   double MacdSig()  const { return c_macdS; }
   double MacdHist() const { return c_macdM-c_macdS; }
   double EmaFast()  const { return c_emaF; }
   double EmaSlow()  const { return c_emaS; }
   double EmaTrend() const { return c_emaT; }
   double SMA()      const { return c_sma; }
   double BBUpper()  const { return c_bbU; }
   double BBMid()    const { return c_bbM; }
   double BBLower()  const { return c_bbL; }
   double DonUpper() const { return c_donU; }
   double DonLower() const { return c_donL; }
   double VWAP()     const { return c_vwap; }
   //--- keltner derived on the fly ----------------------------------
   double KeltUpper(const double mult=1.5) const { return c_emaF+mult*c_atr; }
   double KeltLower(const double mult=1.5) const { return c_emaF-mult*c_atr; }
  };

#endif // PERCEPTION_ANALYSIS_INDICATORHUB_MQH
//+------------------------------------------------------------------+
