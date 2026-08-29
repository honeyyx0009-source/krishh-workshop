//+------------------------------------------------------------------+
//|                                                    ChartSkin.mqh |
//|          001 PERCEPTION - Chart appearance controller             |
//|                                                                  |
//| Applies the dark cyber theme to the underlying chart: grid off,  |
//| candles on and clearly coloured, neon bull/bear bodies and a     |
//| deep navy background so the dashboard panels sit on a coherent   |
//| canvas. Original settings are captured on Apply() and restored   |
//| on Remove() so the user's chart is left as it was found.         |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_DASHBOARD_CHARTSKIN_MQH
#define PERCEPTION_DASHBOARD_CHARTSKIN_MQH

#include <Perception/Dashboard/Draw.mqh>

class CChartSkin
  {
private:
   long  m_chart;
   bool  m_applied;
   //--- captured originals
   long  o_grid, o_mode, o_bg, o_fg, o_bull, o_bear, o_up, o_down, o_vol;

public:
                     CChartSkin(): m_chart(0), m_applied(false) {}

   void Apply(const long chart)
     {
      m_chart=chart;
      if(!m_applied)
        {
         o_grid=ChartGetInteger(m_chart,CHART_SHOW_GRID);
         o_mode=ChartGetInteger(m_chart,CHART_MODE);
         o_bg  =ChartGetInteger(m_chart,CHART_COLOR_BACKGROUND);
         o_fg  =ChartGetInteger(m_chart,CHART_COLOR_FOREGROUND);
         o_bull=ChartGetInteger(m_chart,CHART_COLOR_CANDLE_BULL);
         o_bear=ChartGetInteger(m_chart,CHART_COLOR_CANDLE_BEAR);
         o_up  =ChartGetInteger(m_chart,CHART_COLOR_CHART_UP);
         o_down=ChartGetInteger(m_chart,CHART_COLOR_CHART_DOWN);
         o_vol =ChartGetInteger(m_chart,CHART_SHOW_VOLUMES);
         m_applied=true;
        }
      ChartSetInteger(m_chart,CHART_SHOW_GRID,false);
      ChartSetInteger(m_chart,CHART_MODE,CHART_CANDLES);
      ChartSetInteger(m_chart,CHART_COLOR_BACKGROUND,CLR_BG_DEEP);
      ChartSetInteger(m_chart,CHART_COLOR_FOREGROUND,CLR_TXT_DIM);
      ChartSetInteger(m_chart,CHART_COLOR_CANDLE_BULL,CLR_NEON_CYAN);
      ChartSetInteger(m_chart,CHART_COLOR_CANDLE_BEAR,CLR_NEON_PURPLE);
      ChartSetInteger(m_chart,CHART_COLOR_CHART_UP,CLR_NEON_CYAN);
      ChartSetInteger(m_chart,CHART_COLOR_CHART_DOWN,CLR_NEON_PURPLE);
      ChartSetInteger(m_chart,CHART_COLOR_CHART_LINE,CLR_TXT_DIM);
      ChartSetInteger(m_chart,CHART_SHOW_VOLUMES,CHART_VOLUME_HIDE);
      ChartSetInteger(m_chart,CHART_SHOW_OHLC,true);
      ChartSetInteger(m_chart,CHART_FOREGROUND,false);
      ChartRedraw(m_chart);
     }

   void Remove()
     {
      if(!m_applied) return;
      ChartSetInteger(m_chart,CHART_SHOW_GRID,o_grid);
      ChartSetInteger(m_chart,CHART_MODE,o_mode);
      ChartSetInteger(m_chart,CHART_COLOR_BACKGROUND,o_bg);
      ChartSetInteger(m_chart,CHART_COLOR_FOREGROUND,o_fg);
      ChartSetInteger(m_chart,CHART_COLOR_CANDLE_BULL,o_bull);
      ChartSetInteger(m_chart,CHART_COLOR_CANDLE_BEAR,o_bear);
      ChartSetInteger(m_chart,CHART_COLOR_CHART_UP,o_up);
      ChartSetInteger(m_chart,CHART_COLOR_CHART_DOWN,o_down);
      ChartSetInteger(m_chart,CHART_SHOW_VOLUMES,o_vol);
      ChartRedraw(m_chart);
      m_applied=false;
     }
  };

#endif // PERCEPTION_DASHBOARD_CHARTSKIN_MQH
//+------------------------------------------------------------------+
