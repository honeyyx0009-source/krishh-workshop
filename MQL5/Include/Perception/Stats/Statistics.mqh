//+------------------------------------------------------------------+
//|                                                   Statistics.mqh |
//|             001 PERCEPTION - Performance analytics                |
//|                                                                  |
//| Institutional dashboards live or die by their metrics. This      |
//| module reconstructs a balance curve from the deal history that   |
//| belongs to 001 PERCEPTION (filtered by magic number range) and   |
//| derives the standard performance ratios, while tracking the      |
//| live equity high-water mark for real-time drawdown.              |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_STATS_STATISTICS_MQH
#define PERCEPTION_STATS_STATISTICS_MQH

#include <Perception/Core/Types.mqh>
#include <Perception/Core/Utils.mqh>

class CStatistics
  {
private:
   long     m_magicLo, m_magicHi;
   SPortfolioStats m_s;
   double   m_equityPeak;
   double   m_maxDDmoney;
   double   m_startBalanceDay;
   datetime m_dayStamp;

   bool InRange(const long magic) const { return(magic>=m_magicLo && magic<=m_magicHi); }

public:
                     CStatistics(): m_magicLo(0), m_magicHi(0), m_equityPeak(0),
                                    m_maxDDmoney(0), m_startBalanceDay(0), m_dayStamp(0)
     { m_s.Reset(); }

   void SetMagicRange(const long base,const long span) { m_magicLo=base; m_magicHi=base+span; }

   //--- called every tick to maintain live drawdown -----------------
   void OnEquityTick()
     {
      double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_equityPeak<=0.0) m_equityPeak=eq;
      if(eq>m_equityPeak)   m_equityPeak=eq;
      double dd=PU::SafeDiv(m_equityPeak-eq,m_equityPeak,0.0);
      m_s.currentDD=dd;
      if(dd>m_s.maxDD) m_s.maxDD=dd;

      //--- roll the daily anchor at midnight ------------------------
      MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
      datetime dayStart=StringToTime(StringFormat("%04d.%02d.%02d 00:00",dt.year,dt.mon,dt.day));
      if(m_dayStamp!=dayStart)
        {
         m_dayStamp=dayStart;
         m_startBalanceDay=AccountInfoDouble(ACCOUNT_BALANCE);
        }
     }

   double DailyProfit() const
     {
      return AccountInfoDouble(ACCOUNT_EQUITY)-m_startBalanceDay;
     }

   //--- rebuild aggregate stats from closed deal history ------------
   void Recompute()
     {
      SPortfolioStats s; s.Reset();
      if(!HistorySelect(0,TimeCurrent())) return;

      datetime now=TimeCurrent();
      datetime dToday=now-86400, dWeek=now-7*86400, dMonth=now-30*86400;

      double gp=0.0, gl=0.0, net=0.0;
      double peak=0.0, curve=0.0, maxdd=0.0;
      double sumR=0.0, sumR2=0.0; int rn=0;
      double rrSum=0.0; int rrN=0;

      int total=HistoryDealsTotal();
      for(int i=0;i<total;i++)
        {
         ulong ticket=HistoryDealGetTicket(i);
         if(ticket==0) continue;
         long magic=(long)HistoryDealGetInteger(ticket,DEAL_MAGIC);
         if(!InRange(magic)) continue;
         long entry=(long)HistoryDealGetInteger(ticket,DEAL_ENTRY);
         if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_INOUT) continue;

         double profit=HistoryDealGetDouble(ticket,DEAL_PROFIT);
         double swap=HistoryDealGetDouble(ticket,DEAL_SWAP);
         double comm=HistoryDealGetDouble(ticket,DEAL_COMMISSION);
         double r=profit+swap+comm;
         datetime t=(datetime)HistoryDealGetInteger(ticket,DEAL_TIME);

         net+=r;
         if(r>=0.0){ s.wins++; gp+=r; if(r>s.largestWin) s.largestWin=r; }
         else      { s.losses++; gl+=-r; if(r<s.largestLoss) s.largestLoss=r; }

         //--- balance curve for money drawdown ---------------------
         curve+=r;
         if(curve>peak) peak=curve;
         double dd=peak-curve;
         if(dd>maxdd) maxdd=dd;

         //--- per-trade return series for Sharpe -------------------
         sumR+=r; sumR2+=r*r; rn++;

         if(t>=dToday) s.tradesToday++;
         if(t>=dWeek)  s.tradesWeek++;
         if(t>=dMonth) s.tradesMonth++;
        }

      int trades=s.wins+s.losses;
      s.winRate=(trades>0?(double)s.wins/trades:0.0);
      s.lossRate=(trades>0?(double)s.losses/trades:0.0);
      s.profitFactor=(gl>1e-9?gp/gl:(gp>0?3.0:0.0));
      s.expectancy=(trades>0?net/trades:0.0);
      s.recoveryFactor=(maxdd>1e-9?net/maxdd:(net>0?3.0:0.0));

      double avgWin=(s.wins>0?gp/s.wins:0.0);
      double avgLoss=(s.losses>0?gl/s.losses:0.0);
      s.avgRR=(avgLoss>1e-9?avgWin/avgLoss:0.0);

      if(rn>1)
        {
         double mean=sumR/rn;
         double var=(sumR2/rn)-(mean*mean);
         double sd=(var>0.0?MathSqrt(var):0.0);
         s.sharpe=(sd>1e-9?mean/sd*MathSqrt((double)rn):0.0);
        }

      //--- preserve live equity-based DD tracked on ticks -----------
      s.currentDD=m_s.currentDD;
      s.maxDD=MathMax(m_s.maxDD,PU::SafeDiv(maxdd,m_equityPeak,0.0));
      m_maxDDmoney=maxdd;
      m_s=s;
     }

   const SPortfolioStats Stats() const { return m_s; }
   double EquityPeak() const { return m_equityPeak; }
   double MaxDDMoney() const { return m_maxDDmoney; }
  };

#endif // PERCEPTION_STATS_STATISTICS_MQH
//+------------------------------------------------------------------+
