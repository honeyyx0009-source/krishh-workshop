//+------------------------------------------------------------------+
//|                                                      IEngine.mqh |
//|             001 PERCEPTION - Trading engine base class            |
//|                                                                  |
//| Every strategy in 001 PERCEPTION is a subclass of CEngine. The   |
//| contract is tiny and uniform: given the current market snapshot  |
//| an engine (a) reports how *suitable* it is for the prevailing    |
//| regime and (b) optionally emits a single SSignal. This uniformity |
//| is what lets the intelligence layer treat twenty very different  |
//| strategies as interchangeable, scoreable candidates.             |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_ENGINES_IENGINE_MQH
#define PERCEPTION_ENGINES_IENGINE_MQH

#include <Perception/Core/Types.mqh>
#include <Perception/Core/Config.mqh>
#include <Perception/Core/SymbolMeta.mqh>

class CEngine
  {
protected:
   ENUM_ENGINE_ID m_id;
   string         m_name;
   long           m_magic;
   bool           m_enabled;
   string         m_symbol;
   ENUM_TIMEFRAMES m_tf;
   SEngineStats   m_stats;

   //--- introspection of THIS engine's own open positions -----------
   int OwnCount() const
     {
      int c=0;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong tk=PositionGetTicket(i);
         if(tk==0) continue;
         if((long)PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol) continue;
         c++;
        }
      return c;
     }
   double OwnVolume() const
     {
      double v=0.0;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong tk=PositionGetTicket(i);
         if(tk==0) continue;
         if((long)PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol) continue;
         v+=PositionGetDouble(POSITION_VOLUME);
        }
      return v;
     }
   //--- worst-priced (last added) entry for this engine's basket -----
   bool OwnExtreme(double &bestBuy,double &worstBuy,double &bestSell,double &worstSell,
                   int &buys,int &sells) const
     {
      bestBuy=0; worstBuy=0; bestSell=0; worstSell=0; buys=0; sells=0;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong tk=PositionGetTicket(i);
         if(tk==0) continue;
         if((long)PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol) continue;
         double op=PositionGetDouble(POSITION_PRICE_OPEN);
         if((long)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
           { if(buys==0||op>bestBuy) bestBuy=op; if(buys==0||op<worstBuy) worstBuy=op; buys++; }
         else
           { if(sells==0||op<bestSell) bestSell=op; if(sells==0||op>worstSell) worstSell=op; sells++; }
        }
      return (buys+sells)>0;
     }

   //--- convenience: does the higher-TF context agree with dir? -----
   bool MTFConfirms(const SMarketState &st,const ENUM_SIGNAL_DIR dir,const SConfig &cfg) const
     {
      if(!cfg.useMTFConfirm) return true;
      ENUM_TREND_DIR want=(dir==SIG_BUY?TREND_UP:TREND_DOWN);
      //--- require at least the mid TF (or alignment) to agree ------
      if(st.trendMid==want || st.trendHigh==want) return true;
      return (st.mtfAlignment>=0.66);
     }

public:
                     CEngine(): m_id(ENG_NONE), m_name("Engine"), m_magic(0),
                                m_enabled(true), m_tf(PERIOD_CURRENT)
     { m_stats.Reset(); }
   virtual          ~CEngine() {}

   virtual bool Init(const string symbol,const ENUM_TIMEFRAMES tf,const long magic)
     {
      m_symbol=symbol; m_tf=tf; m_magic=magic;
      return true;
     }

   //--- the two things every engine MUST implement -------------------
   virtual double Suitability(const SMarketState &st)=0;              // [0..1] regime fit
   virtual void   Evaluate(const SMarketState &st,CSymbolMeta *sym,
                           const SConfig &cfg,SSignal &out)=0;

   //--- statistics / adaptive trust ---------------------------------
   void OnTradeClosed(const double result)
     {
      m_stats.trades++;
      m_stats.lastResult=result;
      m_stats.netProfit+=result;
      if(result>=0.0){ m_stats.wins++;   m_stats.grossProfit+=result; m_stats.lossStreak=0; }
      else           { m_stats.losses++; m_stats.grossLoss+=-result;  m_stats.lossStreak++; }
      m_stats.expectancy=(m_stats.trades>0?m_stats.netProfit/m_stats.trades:0.0);
     }

   //--- accessors ----------------------------------------------------
   ENUM_ENGINE_ID Id()      const { return m_id; }
   string         Name()    const { return m_name; }
   long           Magic()   const { return m_magic; }
   bool           Enabled() const { return m_enabled; }
   void           SetEnabled(const bool e) { m_enabled=e; }
   SEngineStats   Stats()   const { return m_stats; }
   void           SetConfMultiplier(const double m) { m_stats.confMultiplier=m; }
   double         ConfMultiplier() const { return m_stats.confMultiplier; }
   string         Comment() const { return StringFormat("001P#%s",m_name); }
  };

#endif // PERCEPTION_ENGINES_IENGINE_MQH
//+------------------------------------------------------------------+
