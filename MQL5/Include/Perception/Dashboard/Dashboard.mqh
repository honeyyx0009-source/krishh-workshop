//+------------------------------------------------------------------+
//|                                                    Dashboard.mqh |
//|          001 PERCEPTION - Multi-mode dashboard renderer           |
//|                                                                  |
//| Three switchable faces over the same live data:                  |
//|   Mode 1 Compact  - a small top-left HUD for maximum chart room; |
//|   Mode 2 Pro      - the daily-driver, four-panel command centre; |
//|   Mode 3 Research - a dense, full-screen quant console.          |
//| The renderer is stateless with respect to the framework: it is   |
//| handed a read-only SDashContext each refresh and paints from it, |
//| which keeps the UI cleanly separated from trading logic.         |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_DASHBOARD_DASHBOARD_MQH
#define PERCEPTION_DASHBOARD_DASHBOARD_MQH

#include <Perception/Dashboard/Draw.mqh>
#include <Perception/Core/SymbolMeta.mqh>
#include <Perception/Risk/RiskManager.mqh>
#include <Perception/Stats/Statistics.mqh>
#include <Perception/Intelligence/StrategySelector.mqh>
#include <Perception/Analysis/Scanner.mqh>
#include <Perception/Core/EventBus.mqh>

//--- live scalar metrics gathered by the EA each refresh ------------
struct SDashMetrics
  {
   double  cpuMs;
   double  frameRate;
   double  memUsedMB;
   double  latencyMs;
   double  aiThreshold;
   double  aiConfidence;
   string  bestEngine;
   string  bestReason;
   string  skipReason;
   ENUM_SYSTEM_STATE state;
   string  stateReason;
   double  dailyProfit;
   ENUM_PRESET preset;
   bool    autoTrade;
   int     openTrades;
   double  floating;
  };

//--- everything the dashboard is allowed to read --------------------
struct SDashContext
  {
   CSymbolMeta       *sym;
   CRiskManager      *risk;
   CStatistics       *stats;
   CStrategySelector *sel;
   CScanner          *scan;
   CEventBus         *bus;
   SMarketState       st;
   SConfig            cfg;
   SDashMetrics       m;
  };

class CDashboard
  {
private:
   CDraw            m_d;
   long             m_chart;
   ENUM_DASH_MODE   m_mode;
   int              m_frame;

   //--- compute a proportional scale from the chart height ----------
   void Rescale()
     {
      long h=ChartGetInteger(m_chart,CHART_HEIGHT_IN_PIXELS);
      if(h<=0) h=900;
      double s=(double)h/1000.0;
      m_d.SetScale(PU::Clamp(s,0.78,1.6));
     }

   //--- key/value row inside a panel --------------------------------
   void KV(const string id,const int x,const int y,const string k,const string v,
           const color vc,const int labelW=110,const int fs=8)
     {
      m_d.Text(id+"k",x,y,k,CLR_TXT_DIM,fs);
      m_d.Text(id+"v",x+m_d.S(labelW),y,v,vc,fs);
     }

   string StateText(const ENUM_SYSTEM_STATE s)
     {
      switch(s)
        {
         case STATE_RUNNING:   return "RUNNING";
         case STATE_THROTTLED: return "THROTTLED";
         case STATE_RECOVERY:  return "RECOVERY";
         case STATE_HALTED:    return "HALTED";
         default:              return "INIT";
        }
     }
   color StateColor(const ENUM_SYSTEM_STATE s)
     {
      switch(s)
        {
         case STATE_RUNNING:   return CLR_GREEN;
         case STATE_THROTTLED: return CLR_AMBER;
         case STATE_RECOVERY:  return CLR_AMBER;
         case STATE_HALTED:    return CLR_RED;
         default:              return CLR_TXT_DIM;
        }
     }

   //--- header used by every mode -----------------------------------
   void Header(const string id,const int x,const int y,const int w,const int h,const SDashContext &c)
     {
      color accent=((m_frame/2)%2==0?CLR_NEON_BLUE:CLR_NEON_PURPLE); // pulsing border
      m_d.Panel(id,x,y,w,h,CLR_PANEL_2,accent);
      m_d.Text(id+"logo",x+m_d.S(10),y+m_d.S(6),"001 PERCEPTION",CLR_NEON_CYAN,13,"Segoe UI Semibold");
      m_d.Text(id+"sub",x+m_d.S(12),y+m_d.S(26),"ADAPTIVE AUTONOMOUS FRAMEWORK",CLR_TXT_DIM,7);
      //--- live status dot ------------------------------------------
      color dot=((m_frame%2==0)?StateColor(c.m.state):CLR_PANEL_2);
      m_d.Cell(id+"dot",x+w-m_d.S(120),y+m_d.S(12),m_d.S(10),m_d.S(10),dot);
      m_d.Text(id+"stat",x+w-m_d.S(104),y+m_d.S(8),StateText(c.m.state),StateColor(c.m.state),9,"Segoe UI Semibold");
      m_d.Text(id+"clock",x+w-m_d.S(104),y+m_d.S(26),TimeToString(TimeCurrent(),TIME_MINUTES),CLR_TXT_DIM,7);
     }

   void RenderCompact(const SDashContext &c);
   void RenderPro(const SDashContext &c);
   void RenderResearch(const SDashContext &c);

public:
                     CDashboard(): m_chart(0), m_mode(DASH_PRO), m_frame(0) {}

   void Init(const long chart,const ENUM_DASH_MODE mode)
     {
      m_chart=chart; m_mode=mode;
      m_d.Init(chart,"001P_");
      Rescale();
     }

   void SetMode(const ENUM_DASH_MODE mode)
     {
      if(mode!=m_mode){ m_mode=mode; m_d.Clear(); }   // wipe stale objects on switch
     }

   void OnResize() { Rescale(); }
   void Clear()    { m_d.Clear(); }

   void Render(const SDashContext &c)
     {
      m_frame++;
      switch(m_mode)
        {
         case DASH_COMPACT:  RenderCompact(c);  break;
         case DASH_RESEARCH: RenderResearch(c); break;
         default:            RenderPro(c);      break;
        }
      ChartRedraw(m_chart);
     }
  };

//+------------------------------------------------------------------+
//| MODE 1 - COMPACT                                                 |
//+------------------------------------------------------------------+
void CDashboard::RenderCompact(const SDashContext &c)
  {
   int x=m_d.S(8), y=m_d.S(22), w=m_d.S(232);
   int rowH=m_d.S(17), pad=m_d.S(10);
   int hHdr=m_d.S(46);
   Header("hdr",x,y,w,hHdr,c);

   int py=y+hHdr+m_d.S(6);
   int ph=rowH*15+m_d.S(52);
   m_d.Panel("cpanel",x,py,w,ph,CLR_PANEL,CLR_NEON_BLUE);
   int cx=x+pad, cy=py+m_d.S(8);

   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   SPortfolioStats ps=c.stats.Stats();

   KV("c01",cx,cy,"Symbol / TF",c.sym.Symbol()+"  "+StringSubstr(EnumToString((ENUM_TIMEFRAMES)Period()),7),CLR_TXT); cy+=rowH;
   KV("c02",cx,cy,"Strategy",c.m.bestEngine,CLR_NEON_CYAN); cy+=rowH;
   KV("c03",cx,cy,"Regime",RegimeName(c.st.regime),CLR_TXT); cy+=rowH;
   //--- AI confidence bar ----------------------------------------
   m_d.Text("c04k",cx,cy,"AI Confidence",CLR_TXT_DIM,8);
   m_d.Text("c04v",cx+m_d.S(110),cy,PU::Pct(c.m.aiConfidence),CDraw::Heat(c.m.aiConfidence),8);
   cy+=m_d.S(14);
   m_d.Bar("c04b",cx,cy,w-2*pad,m_d.S(6),c.m.aiConfidence,CDraw::Heat(c.m.aiConfidence)); cy+=m_d.S(12);

   KV("c05",cx,cy,"Spread / Lat",DoubleToString(c.st.spreadPts,0)+" / "+DoubleToString(c.m.latencyMs,0)+"ms",CLR_TXT); cy+=rowH;
   KV("c06",cx,cy,"Balance",PU::Money(bal),CLR_TXT); cy+=rowH;
   KV("c07",cx,cy,"Equity",PU::Money(eq),CLR_TXT); cy+=rowH;
   KV("c08",cx,cy,"Floating",PU::Money(c.m.floating),c.m.floating>=0?CLR_GREEN:CLR_RED); cy+=rowH;
   KV("c09",cx,cy,"Daily P/L",PU::Money(c.m.dailyProfit),c.m.dailyProfit>=0?CLR_GREEN:CLR_RED); cy+=rowH;
   KV("c10",cx,cy,"Open / Risk",IntegerToString(c.m.openTrades)+"  /  "+DoubleToString(c.risk.CurrentRiskPct(),2)+"%",CLR_TXT); cy+=rowH;
   KV("c11",cx,cy,"Auto Trade",c.m.autoTrade?"ON":"OFF",c.m.autoTrade?CLR_GREEN:CLR_RED); cy+=rowH;
   KV("c12",cx,cy,"Preset",PresetName(c.m.preset),CLR_TXT); cy+=rowH;
   KV("c13",cx,cy,"Status",StateText(c.m.state),StateColor(c.m.state)); cy+=rowH;
   //--- small performance (win rate) bar -------------------------
   m_d.Text("c14k",cx,cy,"Win Rate",CLR_TXT_DIM,8);
   m_d.Text("c14v",cx+m_d.S(110),cy,PU::Pct(ps.winRate),CLR_TXT,8); cy+=m_d.S(14);
   m_d.Bar("c14b",cx,cy,w-2*pad,m_d.S(6),ps.winRate,CLR_NEON_PURPLE); cy+=m_d.S(12);
   KV("c15",cx,cy,"CPU / Mem",DoubleToString(c.m.cpuMs,2)+"ms / "+DoubleToString(c.m.memUsedMB,0)+"MB",CLR_TXT_DIM); cy+=rowH;
  }

//+------------------------------------------------------------------+
//| MODE 2 - PROFESSIONAL                                            |
//+------------------------------------------------------------------+
void CDashboard::RenderPro(const SDashContext &c)
  {
   long wpx=ChartGetInteger(m_chart,CHART_WIDTH_IN_PIXELS); if(wpx<=0) wpx=1400;
   int margin=m_d.S(8);
   int top=m_d.S(20);
   int full=(int)wpx-2*margin;
   int hHdr=m_d.S(46);
   Header("hdr",margin,top,full,hHdr,c);

   int bodyY=top+hHdr+m_d.S(6);
   int colGap=m_d.S(6);
   int leftW=m_d.S(250);
   int rightW=m_d.S(250);
   int centerW=full-leftW-rightW-2*colGap;
   int bottomH=m_d.S(150);
   long hpx=ChartGetInteger(m_chart,CHART_HEIGHT_IN_PIXELS); if(hpx<=0) hpx=900;
   int bodyH=(int)hpx-bodyY-bottomH-m_d.S(14);
   if(bodyH<m_d.S(240)) bodyH=m_d.S(240);

   SPortfolioStats ps=c.stats.Stats();
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);

   //================= LEFT : AI + market ==========================
   int lx=margin, ly=bodyY;
   m_d.Panel("lp",lx,ly,leftW,bodyH,CLR_PANEL,CLR_NEON_BLUE);
   m_d.Text("lp_t",lx+m_d.S(10),ly+m_d.S(6),"AI CORE / MARKET",CLR_NEON_CYAN,9,"Segoe UI Semibold");
   int ix=lx+m_d.S(10), iy=ly+m_d.S(26); int rh=m_d.S(16);
   KV("l01",ix,iy,"Engine",c.m.bestEngine,CLR_NEON_CYAN); iy+=rh;
   KV("l02",ix,iy,"Regime",RegimeName(c.st.regime),CLR_TXT); iy+=rh;
   m_d.Text("l03k",ix,iy,"Trend Strength",CLR_TXT_DIM,8);
   m_d.Bar("l03b",ix+m_d.S(120),iy+m_d.S(2),m_d.S(96),m_d.S(7),c.st.trendStrength,CLR_NEON_BLUE); iy+=rh;
   m_d.Text("l04k",ix,iy,"Confidence",CLR_TXT_DIM,8);
   m_d.Bar("l04b",ix+m_d.S(120),iy+m_d.S(2),m_d.S(96),m_d.S(7),c.m.aiConfidence,CDraw::Heat(c.m.aiConfidence)); iy+=rh;
   KV("l05",ix,iy,"Volatility",DoubleToString(c.st.volRatio,2)+"x",CLR_TXT); iy+=rh;
   KV("l06",ix,iy,"MTF Align",PU::Pct(c.st.mtfAlignment),CLR_TXT); iy+=rh;
   KV("l07",ix,iy,"Spread",DoubleToString(c.st.spreadPts,0)+" pts",CLR_TXT); iy+=rh;
   KV("l08",ix,iy,"Latency",DoubleToString(c.m.latencyMs,0)+" ms",CLR_TXT); iy+=rh;
   KV("l09",ix,iy,"Broker",AccountInfoString(ACCOUNT_COMPANY),CLR_TXT_DIM,70); iy+=rh;
   KV("l10",ix,iy,"Leverage","1:"+IntegerToString(AccountInfoInteger(ACCOUNT_LEVERAGE)),CLR_TXT); iy+=rh;
   KV("l11",ix,iy,"Margin",PU::Money(AccountInfoDouble(ACCOUNT_MARGIN)),CLR_TXT); iy+=rh;
   KV("l12",ix,iy,"Risk / trade",DoubleToString(c.risk.CurrentRiskPct(),2)+"%",CLR_TXT); iy+=rh;
   KV("l13",ix,iy,"Balance",PU::Money(bal),CLR_TXT); iy+=rh;
   KV("l14",ix,iy,"Equity",PU::Money(eq),CLR_TXT); iy+=rh;
   KV("l15",ix,iy,"Floating",PU::Money(c.m.floating),c.m.floating>=0?CLR_GREEN:CLR_RED); iy+=rh;
   KV("l16",ix,iy,"Drawdown",PU::Pct(ps.currentDD),ps.currentDD>0.05?CLR_AMBER:CLR_TXT); iy+=rh;
   KV("l17",ix,iy,"Symbol",c.sym.Symbol(),CLR_TXT); iy+=rh;
   KV("l18",ix,iy,"Session",(c.st.sessionLondon?"London ":"")+(c.st.sessionNY?"NY ":"")+(c.st.sessionAsia?"Asia":""),CLR_TXT); iy+=rh;

   //================= CENTER : decision console ===================
   int mx=lx+leftW+colGap, my=bodyY;
   m_d.Panel("mp",mx,my,centerW,bodyH,CLR_PANEL,CLR_NEON_PURPLE);
   m_d.Text("mp_t",mx+m_d.S(10),my+m_d.S(6),"AI DECISION CONSOLE",CLR_NEON_CYAN,9,"Segoe UI Semibold");
   int ax=mx+m_d.S(10), ay=my+m_d.S(28);
   m_d.Text("m_fore",ax,ay,"Forecast: "+RegimeName(c.st.regime)+"  ("+PU::Pct(c.st.regimeConfidence)+" conf)",CLR_TXT,9); ay+=m_d.S(18);
   m_d.Text("m_next",ax,ay,"Next: "+(StringLen(c.m.bestReason)>0?c.m.bestReason:"scanning..."),CLR_GREEN,8); ay+=m_d.S(15);
   m_d.Text("m_skip",ax,ay,"Skip: "+(StringLen(c.m.skipReason)>0?c.m.skipReason:"-"),CLR_TXT_DIM,8); ay+=m_d.S(15);
   //--- probability meter ----------------------------------------
   m_d.Text("m_pk",ax,ay,"Probability",CLR_TXT_DIM,8);
   m_d.Bar("m_pb",ax+m_d.S(90),ay+m_d.S(2),centerW-m_d.S(120),m_d.S(8),c.m.aiConfidence,CDraw::Heat(c.m.aiConfidence)); ay+=m_d.S(20);
   //--- structural read-out --------------------------------------
   KV("m01",ax,ay,"Support",DoubleToString(c.st.nearestSupport,c.sym.Digits()),CLR_TXT,90); ay+=m_d.S(15);
   KV("m02",ax,ay,"Resistance",DoubleToString(c.st.nearestResistance,c.sym.Digits()),CLR_TXT,90); ay+=m_d.S(15);
   KV("m03",ax,ay,"Structure",(c.st.structureBias==TREND_UP?"Bullish (HH/HL)":c.st.structureBias==TREND_DOWN?"Bearish (LH/LL)":"Neutral"),CLR_TXT,90); ay+=m_d.S(18);
   //--- live decision log ----------------------------------------
   m_d.Text("m_lg",ax,ay,"LIVE DECISION LOG",CLR_NEON_BLUE,8,"Segoe UI Semibold"); ay+=m_d.S(16);
   int shown=8;
   for(int i=0;i<shown;i++)
     {
      SDecision d;
      string line=""; color lc=CLR_TXT_DIM;
      if(c.bus.Recent(i,d))
        { line=TimeToString(d.time,TIME_MINUTES)+"  "+d.text; lc=(d.accepted?CLR_GREEN:CLR_TXT_DIM); }
      m_d.Text("m_l"+IntegerToString(i),ax,ay,line,lc,7,"Consolas"); ay+=m_d.S(13);
     }

   //================= RIGHT : performance =========================
   int rx=mx+centerW+colGap, ry=bodyY;
   m_d.Panel("rp",rx,ry,rightW,bodyH,CLR_PANEL,CLR_NEON_BLUE);
   m_d.Text("rp_t",rx+m_d.S(10),ry+m_d.S(6),"PERFORMANCE",CLR_NEON_CYAN,9,"Segoe UI Semibold");
   int px=rx+m_d.S(10), py=ry+m_d.S(26);
   KV("r01",px,py,"Win Rate",PU::Pct(ps.winRate),CLR_GREEN); py+=rh;
   KV("r02",px,py,"Loss Rate",PU::Pct(ps.lossRate),CLR_RED); py+=rh;
   KV("r03",px,py,"Profit Factor",DoubleToString(ps.profitFactor,2),CLR_TXT); py+=rh;
   KV("r04",px,py,"Recovery",DoubleToString(ps.recoveryFactor,2),CLR_TXT); py+=rh;
   KV("r05",px,py,"Sharpe",DoubleToString(ps.sharpe,2),CLR_TXT); py+=rh;
   KV("r06",px,py,"Expectancy",PU::Money(ps.expectancy),ps.expectancy>=0?CLR_GREEN:CLR_RED); py+=rh;
   KV("r07",px,py,"Avg RR",DoubleToString(ps.avgRR,2),CLR_TXT); py+=rh;
   KV("r08",px,py,"Largest Win",PU::Money(ps.largestWin),CLR_GREEN); py+=rh;
   KV("r09",px,py,"Largest Loss",PU::Money(ps.largestLoss),CLR_RED); py+=rh;
   KV("r10",px,py,"Trades Today",IntegerToString(ps.tradesToday),CLR_TXT); py+=rh;
   KV("r11",px,py,"Trades Week",IntegerToString(ps.tradesWeek),CLR_TXT); py+=rh;
   KV("r12",px,py,"Trades Month",IntegerToString(ps.tradesMonth),CLR_TXT); py+=rh;
   m_d.Text("r13k",px,py,"Current DD",CLR_TXT_DIM,8);
   m_d.Bar("r13b",px+m_d.S(120),py+m_d.S(2),m_d.S(96),m_d.S(7),ps.currentDD,CDraw::Heat(1.0-ps.currentDD*5.0)); py+=rh;

   //================= BOTTOM : scanner ============================
   int sx=margin, sy=bodyY+bodyH+m_d.S(6);
   m_d.Panel("sp",sx,sy,full,bottomH,CLR_PANEL,CLR_NEON_PURPLE);
   m_d.Text("sp_t",sx+m_d.S(10),sy+m_d.S(6),"MULTI-SYMBOL SCANNER",CLR_NEON_CYAN,9,"Segoe UI Semibold");
   //--- header row -----------------------------------------------
   int hx=sx+m_d.S(12), hy=sy+m_d.S(26);
   string cols[]={"SYMBOL","BUY%","SELL%","TREND","MOM","VOL%","SPRD","LOT","FLOAT","BIAS","SIGNAL"};
   int cw[]={90,52,52,60,52,52,48,48,64,52,70};
   int cxp=hx;
   for(int i=0;i<ArraySize(cols);i++){ m_d.Text("sh"+IntegerToString(i),cxp,hy,cols[i],CLR_TXT_DIM,7,"Segoe UI Semibold"); cxp+=m_d.S(cw[i]); }
   //--- rows -----------------------------------------------------
   int rowsMax=6, ryy=hy+m_d.S(16);
   int rcount=(c.scan!=NULL?c.scan.Count():0);
   for(int r=0;r<rowsMax;r++)
     {
      SScanRow row;
      string id="sr"+IntegerToString(r)+"_";
      if(r<rcount && c.scan.Row(r,row) && row.valid)
        {
         int vx=hx;
         m_d.Text(id+"0",vx,ryy,row.symbol,CLR_TXT,7); vx+=m_d.S(cw[0]);
         m_d.Text(id+"1",vx,ryy,DoubleToString(row.buyPct,0),CLR_GREEN,7); vx+=m_d.S(cw[1]);
         m_d.Text(id+"2",vx,ryy,DoubleToString(row.sellPct,0),CLR_RED,7); vx+=m_d.S(cw[2]);
         m_d.Text(id+"3",vx,ryy,PU::Pct(row.trendStrength,0),CLR_TXT,7); vx+=m_d.S(cw[3]);
         m_d.Text(id+"4",vx,ryy,DoubleToString(row.momentum,2),row.momentum>=0?CLR_GREEN:CLR_RED,7); vx+=m_d.S(cw[4]);
         m_d.Text(id+"5",vx,ryy,DoubleToString(row.volatilityPct,2),CLR_TXT,7); vx+=m_d.S(cw[5]);
         m_d.Text(id+"6",vx,ryy,DoubleToString(row.spreadPts,0),CLR_TXT,7); vx+=m_d.S(cw[6]);
         m_d.Text(id+"7",vx,ryy,DoubleToString(row.lot,2),CLR_TXT,7); vx+=m_d.S(cw[7]);
         m_d.Text(id+"8",vx,ryy,PU::Money(row.floating),row.floating>=0?CLR_GREEN:CLR_RED,7); vx+=m_d.S(cw[8]);
         m_d.Text(id+"9",vx,ryy,SignalName(row.bias),CDraw::DirColor((int)row.bias),7); vx+=m_d.S(cw[9]);
         m_d.Bar(id+"10",vx,ryy+m_d.S(2),m_d.S(60),m_d.S(6),row.signalStrength,CLR_NEON_BLUE);
        }
      else
        { for(int k=0;k<11;k++) m_d.Text(id+IntegerToString(k),hx,ryy,"",CLR_TXT_DIM,7); m_d.Delete(id+"10_t"); m_d.Delete(id+"10_f"); }
      ryy+=m_d.S(17);
     }
  }

//+------------------------------------------------------------------+
//| MODE 3 - RESEARCH (institutional full screen)                    |
//+------------------------------------------------------------------+
void CDashboard::RenderResearch(const SDashContext &c)
  {
   long wpx=ChartGetInteger(m_chart,CHART_WIDTH_IN_PIXELS); if(wpx<=0) wpx=1600;
   long hpx=ChartGetInteger(m_chart,CHART_HEIGHT_IN_PIXELS); if(hpx<=0) hpx=1000;
   int margin=m_d.S(8);
   int full=(int)wpx-2*margin;
   int top=m_d.S(20);
   int hHdr=m_d.S(46);
   Header("hdr",margin,top,full,hHdr,c);

   int bodyY=top+hHdr+m_d.S(6);
   int gap=m_d.S(6);
   int colW=(full-3*gap)/4;             // four columns
   int bodyH=(int)hpx-bodyY-m_d.S(14);
   int halfH=(bodyH-gap)/2;

   SPortfolioStats ps=c.stats.Stats();

   //--- COL 1 : AI strategy ranking -------------------------------
   int x1=margin;
   m_d.Panel("g1",x1,bodyY,colW,bodyH,CLR_PANEL,CLR_NEON_BLUE);
   m_d.Text("g1t",x1+m_d.S(10),bodyY+m_d.S(6),"AI STRATEGY RANKING",CLR_NEON_CYAN,9,"Segoe UI Semibold");
   int yy=bodyY+m_d.S(28), rh=m_d.S(15), ex=x1+m_d.S(10);
   int idx[]; if(c.sel!=NULL) c.sel.RankIndices(idx);
   int nrank=(c.sel!=NULL?c.sel.ScoreCount():0);
   for(int i=0;i<nrank && i<18;i++)
     {
      SEngineScore sc;
      if(!c.sel.ScoreAt(idx[i],sc)) continue;
      m_d.Text("g1n"+IntegerToString(i),ex,yy,sc.name,sc.accepted?CLR_GREEN:CLR_TXT,7);
      m_d.Bar("g1b"+IntegerToString(i),ex+m_d.S(96),yy+m_d.S(2),m_d.S(70),m_d.S(6),sc.finalScore,CDraw::Heat(sc.finalScore));
      m_d.Text("g1v"+IntegerToString(i),ex+m_d.S(172),yy,DoubleToString(sc.finalScore,2),CLR_TXT_DIM,7,"Consolas");
      yy+=rh;
     }

   //--- COL 2 : scanner heatmap -----------------------------------
   int x2=x1+colW+gap;
   m_d.Panel("g2",x2,bodyY,colW,bodyH,CLR_PANEL,CLR_NEON_PURPLE);
   m_d.Text("g2t",x2+m_d.S(10),bodyY+m_d.S(6),"MARKET HEATMAP",CLR_NEON_CYAN,9,"Segoe UI Semibold");
   int hy=bodyY+m_d.S(28), hx=x2+m_d.S(10);
   int rcount=(c.scan!=NULL?c.scan.Count():0);
   for(int i=0;i<rcount && i<20;i++)
     {
      SScanRow row;
      if(!c.scan.Row(i,row) || !row.valid) continue;
      m_d.Text("g2s"+IntegerToString(i),hx,hy,row.symbol,CLR_TXT,7);
      //--- buy/sell strength cells -------------------------------
      m_d.Cell("g2cb"+IntegerToString(i),hx+m_d.S(90),hy+m_d.S(1),m_d.S(46),m_d.S(11),CDraw::Heat(row.buyPct/100.0));
      m_d.Text("g2bp"+IntegerToString(i),hx+m_d.S(94),hy,DoubleToString(row.buyPct,0),CLR_BG_DEEP,7);
      m_d.Cell("g2cv"+IntegerToString(i),hx+m_d.S(140),hy+m_d.S(1),m_d.S(46),m_d.S(11),CDraw::Heat(row.sellPct/100.0));
      m_d.Text("g2vp"+IntegerToString(i),hx+m_d.S(144),hy,DoubleToString(row.sellPct,0),CLR_BG_DEEP,7);
      m_d.Text("g2f"+IntegerToString(i),hx+m_d.S(190),hy,PU::Money(row.floating),row.floating>=0?CLR_GREEN:CLR_RED,7);
      hy+=m_d.S(15);
     }

   //--- COL 3 : decision log (top) + stats (bottom) ---------------
   int x3=x2+colW+gap;
   m_d.Panel("g3",x3,bodyY,colW,halfH,CLR_PANEL,CLR_NEON_BLUE);
   m_d.Text("g3t",x3+m_d.S(10),bodyY+m_d.S(6),"LIVE DECISION LOG",CLR_NEON_CYAN,9,"Segoe UI Semibold");
   int ly=bodyY+m_d.S(26), lx=x3+m_d.S(10);
   int logN=(int)((halfH-m_d.S(30))/m_d.S(12));
   for(int i=0;i<logN;i++)
     {
      SDecision d; string line=""; color lc=CLR_TXT_DIM;
      if(c.bus.Recent(i,d)){ line=TimeToString(d.time,TIME_MINUTES)+" "+d.text; lc=(d.accepted?CLR_GREEN:CLR_TXT_DIM); }
      m_d.Text("g3l"+IntegerToString(i),lx,ly,line,lc,7,"Consolas"); ly+=m_d.S(12);
     }

   int y3b=bodyY+halfH+gap;
   m_d.Panel("g3b",x3,y3b,colW,halfH,CLR_PANEL,CLR_NEON_PURPLE);
   m_d.Text("g3bt",x3+m_d.S(10),y3b+m_d.S(6),"STATISTICS",CLR_NEON_CYAN,9,"Segoe UI Semibold");
   int sy=y3b+m_d.S(26), sxx=x3+m_d.S(10);
   KV("s01",sxx,sy,"Win / Loss",PU::Pct(ps.winRate)+" / "+PU::Pct(ps.lossRate),CLR_TXT); sy+=rh;
   KV("s02",sxx,sy,"Profit Factor",DoubleToString(ps.profitFactor,2),CLR_TXT); sy+=rh;
   KV("s03",sxx,sy,"Recovery",DoubleToString(ps.recoveryFactor,2),CLR_TXT); sy+=rh;
   KV("s04",sxx,sy,"Sharpe",DoubleToString(ps.sharpe,2),CLR_TXT); sy+=rh;
   KV("s05",sxx,sy,"Expectancy",PU::Money(ps.expectancy),ps.expectancy>=0?CLR_GREEN:CLR_RED); sy+=rh;
   KV("s06",sxx,sy,"Avg RR",DoubleToString(ps.avgRR,2),CLR_TXT); sy+=rh;
   KV("s07",sxx,sy,"Max DD",PU::Pct(ps.maxDD),CLR_AMBER); sy+=rh;
   KV("s08",sxx,sy,"Trades T/W/M",IntegerToString(ps.tradesToday)+"/"+IntegerToString(ps.tradesWeek)+"/"+IntegerToString(ps.tradesMonth),CLR_TXT); sy+=rh;

   //--- COL 4 : exposure (top) + system health (bottom) -----------
   int x4=x3+colW+gap;
   m_d.Panel("g4",x4,bodyY,colW,halfH,CLR_PANEL,CLR_NEON_BLUE);
   m_d.Text("g4t",x4+m_d.S(10),bodyY+m_d.S(6),"RISK / EXPOSURE",CLR_NEON_CYAN,9,"Segoe UI Semibold");
   int ey=bodyY+m_d.S(26), exx=x4+m_d.S(10);
   KV("e01",exx,ey,"State",StateText(c.m.state),StateColor(c.m.state)); ey+=rh;
   KV("e02",exx,ey,"Open Trades",IntegerToString(c.m.openTrades),CLR_TXT); ey+=rh;
   KV("e03",exx,ey,"Floating",PU::Money(c.m.floating),c.m.floating>=0?CLR_GREEN:CLR_RED); ey+=rh;
   KV("e04",exx,ey,"Daily P/L",PU::Money(c.m.dailyProfit),c.m.dailyProfit>=0?CLR_GREEN:CLR_RED); ey+=rh;
   KV("e05",exx,ey,"Risk/trade",DoubleToString(c.risk.CurrentRiskPct(),2)+"%",CLR_TXT); ey+=rh;
   KV("e06",exx,ey,"Margin",PU::Money(AccountInfoDouble(ACCOUNT_MARGIN)),CLR_TXT); ey+=rh;
   KV("e07",exx,ey,"Free Margin",PU::Money(AccountInfoDouble(ACCOUNT_MARGIN_FREE)),CLR_TXT); ey+=rh;
   m_d.Text("e08k",exx,ey,"Drawdown",CLR_TXT_DIM,8);
   m_d.Bar("e08b",exx+m_d.S(120),ey+m_d.S(2),m_d.S(80),m_d.S(7),ps.currentDD,CDraw::Heat(1.0-ps.currentDD*5.0)); ey+=rh;

   int y4b=bodyY+halfH+gap;
   m_d.Panel("g4b",x4,y4b,colW,halfH,CLR_PANEL,CLR_NEON_PURPLE);
   m_d.Text("g4bt",x4+m_d.S(10),y4b+m_d.S(6),"SYSTEM HEALTH",CLR_NEON_CYAN,9,"Segoe UI Semibold");
   int fy=y4b+m_d.S(26), fxx=x4+m_d.S(10);
   KV("f01",fxx,fy,"CPU / tick",DoubleToString(c.m.cpuMs,3)+" ms",CLR_TXT); fy+=rh;
   KV("f02",fxx,fy,"Frame Rate",DoubleToString(c.m.frameRate,1)+" /s",CLR_TXT); fy+=rh;
   KV("f03",fxx,fy,"Memory",DoubleToString(c.m.memUsedMB,0)+" MB",CLR_TXT); fy+=rh;
   KV("f04",fxx,fy,"Latency",DoubleToString(c.m.latencyMs,0)+" ms",CLR_TXT); fy+=rh;
   KV("f05",fxx,fy,"AI Threshold",DoubleToString(c.m.aiThreshold,2),CLR_TXT); fy+=rh;
   KV("f06",fxx,fy,"Preset",PresetName(c.m.preset),CLR_TXT); fy+=rh;
   KV("f07",fxx,fy,"Engines",IntegerToString(c.sel!=NULL?c.sel.ScoreCount():0)+" scored",CLR_TXT); fy+=rh;
  }

#endif // PERCEPTION_DASHBOARD_DASHBOARD_MQH
//+------------------------------------------------------------------+
