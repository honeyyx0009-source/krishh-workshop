//+------------------------------------------------------------------+
//|                                                        Draw.mqh  |
//|          001 PERCEPTION - Dashboard drawing primitives            |
//|                                                                  |
//| A thin abstraction over MetaTrader's graphical objects. Every    |
//| element is addressed by a stable name and created-or-updated in  |
//| place, so repainting the dashboard every second never causes     |
//| flicker and never leaks objects. A global scale factor keeps the |
//| layout proportional across monitor resolutions.                  |
//|                                                                  |
//| NOTE: MetaTrader draws flat, opaque rectangles - it cannot do    |
//| true rounded corners, blur or alpha glass. We approximate a      |
//| premium "glass + neon" look with layered dark panels and bright  |
//| accent borders; this is an honest limit of the platform.        |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_DASHBOARD_DRAW_MQH
#define PERCEPTION_DASHBOARD_DRAW_MQH

//--- cyber dark theme palette ---------------------------------------
#define CLR_BG_DEEP    (color)C'8,10,20'
#define CLR_PANEL      (color)C'16,19,36'
#define CLR_PANEL_2    (color)C'22,26,48'
#define CLR_NEON_BLUE  (color)C'0,170,255'
#define CLR_NEON_PURPLE (color)C'150,90,255'
#define CLR_NEON_CYAN  (color)C'60,230,235'
#define CLR_TXT        (color)C'220,230,255'
#define CLR_TXT_DIM    (color)C'120,132,168'
#define CLR_GREEN      (color)C'0,220,140'
#define CLR_RED        (color)C'255,72,92'
#define CLR_AMBER      (color)C'255,190,60'
#define CLR_TRACK      (color)C'32,38,66'

class CDraw
  {
private:
   string   m_prefix;
   long     m_chart;
   double   m_scale;

   void Ensure(const string name,const ENUM_OBJECT type)
     {
      if(ObjectFind(m_chart,name)<0)
        {
         ObjectCreate(m_chart,name,type,0,0,0);
         ObjectSetInteger(m_chart,name,OBJPROP_SELECTABLE,false);
         ObjectSetInteger(m_chart,name,OBJPROP_HIDDEN,true);
         ObjectSetInteger(m_chart,name,OBJPROP_BACK,false);
        }
     }

public:
                     CDraw(): m_prefix("001P_"), m_chart(0), m_scale(1.0) {}

   void Init(const long chart,const string prefix) { m_chart=chart; m_prefix=prefix; }
   void SetScale(const double s) { m_scale=s; }
   double Scale() const { return m_scale; }
   int  S(const int v) const { return (int)MathRound(v*m_scale); }

   //--- a filled "glass" panel with a neon border --------------------
   void Panel(const string id,const int x,const int y,const int w,const int h,
              const color bg,const color border,const int corner=CORNER_LEFT_UPPER)
     {
      string n=m_prefix+id;
      Ensure(n,OBJ_RECTANGLE_LABEL);
      ObjectSetInteger(m_chart,n,OBJPROP_CORNER,corner);
      ObjectSetInteger(m_chart,n,OBJPROP_XDISTANCE,x);
      ObjectSetInteger(m_chart,n,OBJPROP_YDISTANCE,y);
      ObjectSetInteger(m_chart,n,OBJPROP_XSIZE,w);
      ObjectSetInteger(m_chart,n,OBJPROP_YSIZE,h);
      ObjectSetInteger(m_chart,n,OBJPROP_BGCOLOR,bg);
      ObjectSetInteger(m_chart,n,OBJPROP_BORDER_TYPE,BORDER_FLAT);
      ObjectSetInteger(m_chart,n,OBJPROP_COLOR,border);
      ObjectSetInteger(m_chart,n,OBJPROP_WIDTH,1);
     }

   //--- a text label -------------------------------------------------
   void Text(const string id,const int x,const int y,const string txt,const color clr,
             const int fontSize=9,const string font="Segoe UI",
             const int corner=CORNER_LEFT_UPPER,const int anchor=ANCHOR_LEFT_UPPER)
     {
      string n=m_prefix+id;
      Ensure(n,OBJ_LABEL);
      ObjectSetInteger(m_chart,n,OBJPROP_CORNER,corner);
      ObjectSetInteger(m_chart,n,OBJPROP_ANCHOR,anchor);
      ObjectSetInteger(m_chart,n,OBJPROP_XDISTANCE,x);
      ObjectSetInteger(m_chart,n,OBJPROP_YDISTANCE,y);
      ObjectSetInteger(m_chart,n,OBJPROP_COLOR,clr);
      ObjectSetInteger(m_chart,n,OBJPROP_FONTSIZE,(int)MathRound(fontSize*m_scale));
      ObjectSetString(m_chart,n,OBJPROP_FONT,font);
      ObjectSetString(m_chart,n,OBJPROP_TEXT,txt);
     }

   //--- a horizontal progress bar (track + fill) ---------------------
   void Bar(const string id,const int x,const int y,const int w,const int h,
            const double pct01,const color fg,const color track=CLR_TRACK,
            const int corner=CORNER_LEFT_UPPER)
     {
      double p=(pct01<0?0:(pct01>1?1:pct01));
      Panel(id+"_t",x,y,w,h,track,track,corner);
      int fw=(int)MathRound(w*p); if(fw<1) fw=1;
      Panel(id+"_f",x,y,fw,h,fg,fg,corner);
     }

   //--- a small solid dot / cell ------------------------------------
   void Cell(const string id,const int x,const int y,const int w,const int h,
             const color c,const int corner=CORNER_LEFT_UPPER)
     { Panel(id,x,y,w,h,c,c,corner); }

   void Delete(const string id) { ObjectDelete(m_chart,m_prefix+id); }
   void Clear() { ObjectsDeleteAll(m_chart,m_prefix); }

   //--- pick a colour along red -> amber -> green by value [0..1] ----
   static color Heat(const double v01)
     {
      double v=(v01<0?0:(v01>1?1:v01));
      if(v<0.5) return (color)C'255,72,92';
      if(v<0.7) return (color)C'255,190,60';
      return (color)C'0,220,140';
     }
   static color DirColor(const int dir)
     {
      if(dir==1) return CLR_GREEN;   // SIG_BUY
      if(dir==2) return CLR_RED;     // SIG_SELL
      return CLR_TXT_DIM;
     }
  };

#endif // PERCEPTION_DASHBOARD_DRAW_MQH
//+------------------------------------------------------------------+
