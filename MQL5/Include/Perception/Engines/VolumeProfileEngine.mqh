//+------------------------------------------------------------------+
//|                                            VolumeProfileEngine.mqh|
//|             001 PERCEPTION - Volume profile engine                |
//|                                                                  |
//| Builds a lightweight volume-by-price histogram over a recent     |
//| window to locate the Point of Control (POC) - the price that     |
//| traded the most. It fades stretch away from the POC back toward  |
//| this high-activity fair value.                                   |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_ENGINES_VOLUMEPROFILE_MQH
#define PERCEPTION_ENGINES_VOLUMEPROFILE_MQH

#include <Perception/Engines/IEngine.mqh>

class CVolumeProfileEngine : public CEngine
  {
private:
   int m_bars;
   int m_bins;
public:
   CVolumeProfileEngine() { m_id=ENG_VOLUME_PROFILE; m_name="VolProfile"; m_bars=120; m_bins=24; }

   double Suitability(const SMarketState &st) override
     {
      switch(st.regime)
        {
         case REGIME_RANGE:    return 0.72;
         case REGIME_SIDEWAYS: return 0.68;
         case REGIME_CALM:     return 0.62;
         default:              return 0.22;
        }
     }

   void Evaluate(const SMarketState &st,CSymbolMeta *sym,const SConfig &cfg,SSignal &out) override
     {
      out.Reset(); out.engine=m_id;
      double atr=st.atr; if(atr<=0.0) return;
      double cl[]; long vol[];
      ArraySetAsSeries(cl,true); ArraySetAsSeries(vol,true);
      if(CopyClose(m_symbol,m_tf,1,m_bars,cl)<m_bars) return;
      if(CopyTickVolume(m_symbol,m_tf,1,m_bars,vol)<m_bars) return;

      double lo=cl[ArrayMinimum(cl,0,m_bars)];
      double hi=cl[ArrayMaximum(cl,0,m_bars)];
      if(hi-lo<=0.0) return;
      double binSize=(hi-lo)/m_bins;

      double hist[]; ArrayResize(hist,m_bins); ArrayInitialize(hist,0.0);
      for(int i=0;i<m_bars;i++)
        {
         int b=(int)PU::ClampI((int)((cl[i]-lo)/binSize),0,m_bins-1);
         hist[b]+=(double)vol[i];
        }
      int pocBin=ArrayMaximum(hist);
      double poc=lo+(pocBin+0.5)*binSize;

      double stretch=(st.mid-poc)/atr;
      if(stretch<=-1.5 && st.rsi<40.0)
        {
         out.dir=SIG_BUY; out.confidence=0.55; out.quality=0.5;
         out.tp=sym.NormalizePrice(poc); out.rr=1.5;
         out.reason="Below POC, revert up";
        }
      else if(stretch>=1.5 && st.rsi>60.0)
        {
         out.dir=SIG_SELL; out.confidence=0.55; out.quality=0.5;
         out.tp=sym.NormalizePrice(poc); out.rr=1.5;
         out.reason="Above POC, revert down";
        }
     }
  };

#endif // PERCEPTION_ENGINES_VOLUMEPROFILE_MQH
//+------------------------------------------------------------------+
