//+------------------------------------------------------------------+
//|                                                   Perception.mqh |
//|          001 PERCEPTION - Central orchestrator (the brain)        |
//|                                                                  |
//| CPerception is the one object that owns every module and wires   |
//| them together. It embodies the project philosophy: on each new   |
//| bar it rebuilds the market picture, classifies the regime, asks  |
//| the AI layer to score every engine, lets the risk manager veto   |
//| or size the winner, executes it, and finally manages open        |
//| trades and paints the dashboard. Nothing else in the framework   |
//| needs to know about this glue - modules stay independent.        |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_PERCEPTION_MQH
#define PERCEPTION_PERCEPTION_MQH

#include <Perception/Core/Logger.mqh>
#include <Perception/Core/SymbolMeta.mqh>
#include <Perception/Core/EventBus.mqh>
#include <Perception/Analysis/MarketContext.mqh>
#include <Perception/Analysis/RegimeClassifier.mqh>
#include <Perception/Analysis/Scanner.mqh>
#include <Perception/Stats/Statistics.mqh>
#include <Perception/Risk/Presets.mqh>
#include <Perception/Risk/RiskManager.mqh>
#include <Perception/Execution/OrderManager.mqh>
#include <Perception/Execution/PositionManager.mqh>
#include <Perception/Intelligence/AIEngine.mqh>
#include <Perception/Intelligence/StrategySelector.mqh>
#include <Perception/Dashboard/ChartSkin.mqh>
#include <Perception/Dashboard/Dashboard.mqh>

class CPerception
  {
private:
   //--- modules --------------------------------------------------
   CLogger            m_log;
   CSymbolMeta        m_sym;
   CEventBus          m_bus;
   CMarketContext     m_mkt;
   CRegimeClassifier  m_regime;
   CScanner           m_scan;
   CStatistics        m_stats;
   CRiskManager       m_risk;
   COrderManager      m_om;
   CPositionManager   m_pm;
   CAIEngine          m_ai;
   CEngineManager     m_engines;
   CStrategySelector  m_sel;
   CChartSkin         m_skin;
   CDashboard         m_dash;

   //--- state ----------------------------------------------------
   SConfig            m_cfg;
   SMarketState       m_state;
   bool               m_hasState;
   long               m_magicLo, m_magicHi;
   datetime           m_lastBar;
   datetime           m_lastDealTime;

   //--- display / telemetry --------------------------------------
   string             m_bestEngine, m_bestReason, m_skipReason;
   double             m_bestConf;
   double             m_cpuMsEMA, m_latencyEMA, m_fps;
   uint               m_lastTickMs, m_lastFpsTick, m_renders;

   //--- attribute newly closed deals to their originating engine --
   void ScanClosedDeals()
     {
      if(!HistorySelect(m_lastDealTime,TimeCurrent())) return;
      datetime newest=m_lastDealTime;
      int total=HistoryDealsTotal();
      for(int i=0;i<total;i++)
        {
         ulong tk=HistoryDealGetTicket(i);
         if(tk==0) continue;
         datetime t=(datetime)HistoryDealGetInteger(tk,DEAL_TIME);
         if(t<=m_lastDealTime) continue;
         long magic=(long)HistoryDealGetInteger(tk,DEAL_MAGIC);
         if(magic<m_magicLo || magic>m_magicHi) continue;

         double comm=HistoryDealGetDouble(tk,DEAL_COMMISSION);
         double lots=HistoryDealGetDouble(tk,DEAL_VOLUME);
         m_sym.ObserveCommission(comm,lots);

         long entry=(long)HistoryDealGetInteger(tk,DEAL_ENTRY);
         if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_INOUT)
           {
            double r=HistoryDealGetDouble(tk,DEAL_PROFIT)+HistoryDealGetDouble(tk,DEAL_SWAP)+comm;
            CEngine *e=m_engines.FindById((ENUM_ENGINE_ID)(magic-m_cfg.magicBase));
            if(e!=NULL) e.OnTradeClosed(r);
           }
         if(t>newest) newest=t;
        }
      m_lastDealTime=newest;
     }

   //--- choose what the dashboard should headline ----------------
   void DisplayFromScores(const bool found,const SEngineScore &best)
     {
      if(found)
        { m_bestEngine=best.name; m_bestConf=best.aiConfidence; m_bestReason=best.signal.reason; return; }
      int idx[]; m_sel.RankIndices(idx);
      if(ArraySize(idx)>0)
        {
         SEngineScore sc;
         if(m_sel.ScoreAt(idx[0],sc))
           {
            m_bestEngine=sc.name+" (watch)";
            m_bestConf=sc.aiConfidence;
            m_bestReason=(sc.signal.IsValid()?sc.signal.reason:"waiting for setup");
           }
        }
     }

   //--- the heartbeat: everything that happens once per bar ------
   void OnNewBar()
     {
      ScanClosedDeals();
      if(!m_mkt.Update()) return;
      m_state=m_mkt.State();
      m_regime.Classify(m_state);
      m_hasState=true;

      m_stats.Recompute();
      SPortfolioStats ps=m_stats.Stats();
      m_ai.AdaptThreshold(ps);

      SEngineScore best;
      bool found=m_sel.Select(m_state,GetPointer(m_sym),m_cfg,best);
      DisplayFromScores(found,best);

      string reason="";
      if(!m_risk.TradingAllowed(m_state,reason))         m_skipReason=reason;
      else if(!found)                                    m_skipReason="no accepted setup";
      else if(!m_risk.SymbolSlotFree(_Symbol))           m_skipReason="symbol slot full";
      else
        {
         SSignal sig=best.signal;
         m_risk.ResolveStops(sig,m_state);
         sig.lots=m_risk.SizePosition(sig);
         CEngine *e=m_engines.FindById(best.id);
         long magic=(e!=NULL?e.Magic():m_cfg.magicBase);
         string cm=(e!=NULL?e.Comment():"001P");
         bool ok=(sig.entry==ENTRY_MARKET? m_om.OpenMarket(sig,magic,cm)
                                         : m_om.OpenPending(sig,magic,cm));
         m_skipReason="";
         if(ok) m_log.Info(StringFormat("OPEN %s %s conf %.2f - %s",
                            best.name,SignalName(sig.dir),best.aiConfidence,sig.reason));
        }
     }

   //--- assemble the read-only view model & paint ----------------
   void RenderDash()
     {
      SDashContext ctx;
      ctx.sym=GetPointer(m_sym);   ctx.risk=GetPointer(m_risk);
      ctx.stats=GetPointer(m_stats); ctx.sel=GetPointer(m_sel);
      ctx.scan=GetPointer(m_scan); ctx.bus=GetPointer(m_bus);
      ctx.st=m_state;              ctx.cfg=m_cfg;
      ctx.m.cpuMs=m_cpuMsEMA;      ctx.m.frameRate=m_fps;
      ctx.m.memUsedMB=(double)TerminalInfoInteger(TERMINAL_MEMORY_USED);
      ctx.m.latencyMs=m_latencyEMA;
      ctx.m.aiThreshold=m_ai.Threshold();
      ctx.m.aiConfidence=m_bestConf;
      ctx.m.bestEngine=m_bestEngine;
      ctx.m.bestReason=m_bestReason;
      ctx.m.skipReason=m_skipReason;
      ctx.m.state=m_risk.State();
      ctx.m.stateReason=m_risk.Reason();
      ctx.m.dailyProfit=m_stats.DailyProfit();
      ctx.m.preset=m_cfg.preset;
      ctx.m.autoTrade=m_cfg.autoTrade;
      ctx.m.openTrades=m_risk.CountPortfolio();
      ctx.m.floating=m_risk.FloatingPL();
      m_dash.Render(ctx);
     }

public:
                     CPerception(): m_hasState(false), m_magicLo(0), m_magicHi(0),
                                    m_lastBar(0), m_lastDealTime(0),
                                    m_bestEngine("Init"), m_bestReason(""), m_skipReason(""),
                                    m_bestConf(0), m_cpuMsEMA(0), m_latencyEMA(0), m_fps(0),
                                    m_lastTickMs(0), m_lastFpsTick(0), m_renders(0) {}

   //================================================================
   int OnInitApp(const SConfig &cfg,const SEngineToggles &tog,
                 const string scannerSymbols,const ENUM_TIMEFRAMES scannerTF)
     {
      m_cfg=cfg;
      CPresets::Apply(m_cfg);                    // preset governs the risk envelope
      m_log.SetLevel(m_cfg.logLevel);
      m_log.SetTag("001P");

      if(!m_sym.Load(_Symbol))
        { m_log.Error("Symbol metadata load failed"); return INIT_FAILED; }

      m_magicLo=m_cfg.magicBase+1;
      m_magicHi=m_cfg.magicBase+100;
      m_stats.SetMagicRange(m_cfg.magicBase,100);

      SIndicatorCfg icfg; icfg.Defaults();
      if(!m_mkt.Init(_Symbol,(ENUM_TIMEFRAMES)_Period,m_cfg.tfMid,m_cfg.tfHigh,m_sym.GmtOffset(),icfg))
        { m_log.Error("Indicator initialisation failed"); return INIT_FAILED; }
      m_regime.Init(_Symbol,(ENUM_TIMEFRAMES)_Period);

      m_risk.Init(GetPointer(m_sym),GetPointer(m_stats),GetPointer(m_log),m_cfg,m_magicLo,m_magicHi);
      m_om.Init(GetPointer(m_sym),GetPointer(m_log),m_magicLo,m_magicHi);
      m_pm.Init(GetPointer(m_sym),GetPointer(m_om),m_magicLo,m_magicHi);

      m_ai.Configure(m_cfg.minConfidence,m_cfg.aggressiveness,m_cfg.adaptiveThresholds);
      m_engines.Populate();
      for(int i=0;i<m_engines.Count();i++)
        {
         CEngine *e=m_engines.At(i);
         if(e!=NULL) e.SetEnabled(tog.Enabled(e.Id()));
        }
      m_engines.InitAll(_Symbol,(ENUM_TIMEFRAMES)_Period,m_cfg.magicBase);
      m_sel.Init(GetPointer(m_engines),GetPointer(m_ai),GetPointer(m_bus));

      m_scan.Init(scannerSymbols,scannerTF,m_magicLo,m_magicHi);

      if(m_cfg.darkSkin) m_skin.Apply(0);
      m_dash.Init(0,m_cfg.dashMode);

      m_lastDealTime=TimeCurrent();
      m_lastBar=0; m_hasState=false;
      m_lastTickMs=GetTickCount(); m_lastFpsTick=m_lastTickMs; m_renders=0;
      m_bestEngine="Scanning"; m_bestReason=""; m_skipReason="";

      //--- prime one snapshot so the dashboard has data immediately -
      if(m_mkt.Update()){ m_state=m_mkt.State(); m_regime.Classify(m_state); m_hasState=true; }
      m_stats.OnEquityTick();
      m_stats.Recompute();
      m_scan.Refresh();

      EventSetMillisecondTimer(500);
      m_log.Info("001 PERCEPTION online on "+_Symbol+"  preset="+PresetName(m_cfg.preset));
      return INIT_SUCCEEDED;
     }

   void OnDeinitApp(const int reason)
     {
      EventKillTimer();
      m_dash.Clear();
      m_skin.Remove();
     }

   void OnTickApp()
     {
      ulong t0=GetMicrosecondCount();

      //--- feed responsiveness (tick gap) as a latency proxy --------
      uint now=GetTickCount();
      double gap=(double)(now-m_lastTickMs); m_lastTickMs=now;
      m_latencyEMA=(m_latencyEMA<=0.0?gap:PU::EmaUpdate(m_latencyEMA,gap,0.2));

      m_risk.OnTick();
      if(m_risk.EmergencyRequested())
        {
         int n=m_om.CloseAll();
         if(n>0) m_log.Warn(StringFormat("Emergency close: %d positions flattened",n));
         m_risk.ClearEmergency();
        }

      if(m_hasState) m_pm.Update(m_state,m_cfg);   // manage open trades every tick

      datetime bt=iTime(_Symbol,(ENUM_TIMEFRAMES)_Period,0);
      if(bt!=m_lastBar){ m_lastBar=bt; OnNewBar(); }

      double ms=(double)(GetMicrosecondCount()-t0)/1000.0;
      m_cpuMsEMA=(m_cpuMsEMA<=0.0?ms:PU::EmaUpdate(m_cpuMsEMA,ms,0.2));
     }

   void OnTimerApp()
     {
      m_scan.Refresh();
      m_renders++;
      uint now=GetTickCount();
      if(now-m_lastFpsTick>=1000)
        {
         m_fps=(double)m_renders*1000.0/(double)(now-m_lastFpsTick);
         m_renders=0; m_lastFpsTick=now;
        }
      if(m_cfg.showDashboard) RenderDash();
     }

   void OnChartEventApp(const int id,const long &lparam,const double &dparam,const string &sparam)
     {
      if(id==CHARTEVENT_CHART_CHANGE) m_dash.OnResize();
      else if(id==CHARTEVENT_KEYDOWN)
        {
         int key=(int)lparam;
         if(key==49)      m_dash.SetMode(DASH_COMPACT);   // '1'
         else if(key==50) m_dash.SetMode(DASH_PRO);       // '2'
         else if(key==51) m_dash.SetMode(DASH_RESEARCH);  // '3'
        }
     }
  };

#endif // PERCEPTION_PERCEPTION_MQH
//+------------------------------------------------------------------+
