//+------------------------------------------------------------------+
//|                                                       Scanner.mqh |
//|          001 PERCEPTION - Multi-symbol market scanner             |
//|                                                                  |
//| A portfolio-level lens. For a configurable watchlist it computes |
//| a fast directional bias, momentum, volatility and spread using a |
//| tiny indicator footprint, and tallies the EA's floating P/L per  |
//| symbol. The scanner is refreshed on the timer, never on the      |
//| tick, so a large watchlist never threatens tick throughput.      |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_ANALYSIS_SCANNER_MQH
#define PERCEPTION_ANALYSIS_SCANNER_MQH

#include <Perception/Core/Utils.mqh>

struct SScanRow
  {
   string  symbol;
   double  buyPct;
   double  sellPct;
   double  trendStrength;   // [0..1]
   double  momentum;        // [-1..1]
   double  volatilityPct;   // atr/price %
   double  spreadPts;
   double  lot;             // suggested min lot
   double  floating;        // EA floating P/L on this symbol
   double  signalStrength;  // [0..1]
   ENUM_SIGNAL_DIR bias;
   bool    valid;
  };

class CScanner
  {
private:
   string   m_symbols[];
   int      h_emaF[], h_emaS[], h_rsi[], h_atr[];
   SScanRow m_rows[];
   ENUM_TIMEFRAMES m_tf;
   long     m_magicLo, m_magicHi;
   bool     m_ready;

   double Read(const int handle,const int buf=0,const int shift=1)
     {
      if(handle==INVALID_HANDLE) return 0.0;
      double t[]; ArraySetAsSeries(t,true);
      if(CopyBuffer(handle,buf,0,shift+2,t)<shift+1) return 0.0;
      return t[shift];
     }

   double SymbolFloating(const string sym)
     {
      double pl=0.0;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong tk=PositionGetTicket(i);
         if(tk==0) continue;
         if(PositionGetString(POSITION_SYMBOL)!=sym) continue;
         long mg=(long)PositionGetInteger(POSITION_MAGIC);
         if(mg>=m_magicLo && mg<=m_magicHi)
            pl+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
        }
      return pl;
     }

public:
                     CScanner(): m_tf(PERIOD_H1), m_magicLo(0), m_magicHi(0), m_ready(false) {}
                    ~CScanner() { Release(); }

   void Release()
     {
      for(int i=0;i<ArraySize(h_emaF);i++)
        {
         if(h_emaF[i]!=INVALID_HANDLE) IndicatorRelease(h_emaF[i]);
         if(h_emaS[i]!=INVALID_HANDLE) IndicatorRelease(h_emaS[i]);
         if(h_rsi[i]!=INVALID_HANDLE)  IndicatorRelease(h_rsi[i]);
         if(h_atr[i]!=INVALID_HANDLE)  IndicatorRelease(h_atr[i]);
        }
     }

   //--- symbolsCsv e.g. "EURUSD,GBPUSD,XAUUSD" ("" => chart symbol) --
   bool Init(const string symbolsCsv,const ENUM_TIMEFRAMES tf,const long magicLo,const long magicHi)
     {
      m_tf=tf; m_magicLo=magicLo; m_magicHi=magicHi;
      string list=symbolsCsv;
      if(StringLen(list)==0) list=_Symbol;
      string parts[];
      int cnt=StringSplit(list,',',parts);
      if(cnt<=0){ ArrayResize(parts,1); parts[0]=_Symbol; cnt=1; }

      ArrayResize(m_symbols,0);
      for(int i=0;i<cnt;i++)
        {
         string s=parts[i];
         StringTrimLeft(s); StringTrimRight(s);
         if(StringLen(s)==0) continue;
         if(!SymbolSelect(s,true)) continue;
         int n=ArraySize(m_symbols); ArrayResize(m_symbols,n+1); m_symbols[n]=s;
        }
      int m=ArraySize(m_symbols);
      ArrayResize(h_emaF,m); ArrayResize(h_emaS,m);
      ArrayResize(h_rsi,m);  ArrayResize(h_atr,m);
      ArrayResize(m_rows,m);
      for(int i=0;i<m;i++)
        {
         h_emaF[i]=iMA(m_symbols[i],m_tf,21,0,MODE_EMA,PRICE_CLOSE);
         h_emaS[i]=iMA(m_symbols[i],m_tf,50,0,MODE_EMA,PRICE_CLOSE);
         h_rsi[i] =iRSI(m_symbols[i],m_tf,14,PRICE_CLOSE);
         h_atr[i] =iATR(m_symbols[i],m_tf,14);
        }
      m_ready=(m>0);
      return m_ready;
     }

   void Refresh()
     {
      if(!m_ready) return;
      for(int i=0;i<ArraySize(m_symbols);i++)
        {
         SScanRow row; row.valid=false; row.symbol=m_symbols[i];
         double emaF=Read(h_emaF[i]);
         double emaS=Read(h_emaS[i]);
         double rsi =Read(h_rsi[i]);
         double atr =Read(h_atr[i]);
         double bid =SymbolInfoDouble(m_symbols[i],SYMBOL_BID);
         double ask =SymbolInfoDouble(m_symbols[i],SYMBOL_ASK);
         double pt  =SymbolInfoDouble(m_symbols[i],SYMBOL_POINT);
         if(emaF<=0.0 || emaS<=0.0 || bid<=0.0){ m_rows[i]=row; continue; }

         double score=0.0;                       // -100..100
         score+=(emaF>emaS? 40.0:-40.0);
         score+=(rsi>55.0? 20.0:(rsi<45.0?-20.0:0.0));
         score+=(bid>emaF? 20.0:-20.0);
         score+=PU::Clamp((rsi-50.0)*0.8,-20.0,20.0);

         row.buyPct=PU::Clamp(50.0+score/2.0,0.0,100.0);
         row.sellPct=100.0-row.buyPct;
         row.trendStrength=PU::Clamp(MathAbs(emaF-emaS)/(atr>0?atr:1.0),0.0,1.0);
         row.momentum=PU::Clamp((rsi-50.0)/50.0,-1.0,1.0);
         row.volatilityPct=PU::SafeDiv(atr,bid,0.0)*100.0;
         row.spreadPts=PU::SafeDiv(ask-bid,pt,0.0);
         row.lot=SymbolInfoDouble(m_symbols[i],SYMBOL_VOLUME_MIN);
         row.floating=SymbolFloating(m_symbols[i]);
         row.signalStrength=PU::Clamp(MathAbs(score)/100.0,0.0,1.0);
         row.bias=(score>15.0?SIG_BUY:(score<-15.0?SIG_SELL:SIG_NONE));
         row.valid=true;
         m_rows[i]=row;
        }
     }

   int  Count() const { return ArraySize(m_rows); }
   bool Row(const int i,SScanRow &out) const
     {
      if(i<0 || i>=ArraySize(m_rows)) return false;
      out=m_rows[i];
      return true;
     }
  };

#endif // PERCEPTION_ANALYSIS_SCANNER_MQH
//+------------------------------------------------------------------+
