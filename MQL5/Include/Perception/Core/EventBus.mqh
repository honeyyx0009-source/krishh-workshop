//+------------------------------------------------------------------+
//|                                                     EventBus.mqh |
//|             001 PERCEPTION - Central intelligence message bus     |
//|                                                                  |
//| The event bus is the "nervous system" of 001 PERCEPTION. Modules |
//| never call each other directly to report what they are thinking; |
//| instead they publish decisions here. The dashboard subscribes to |
//| the same buffer to render the live decision log, and the AI      |
//| layer can replay it. Keeping this one-directional avoids the     |
//| tangled cross-references that make large EAs unmaintainable.     |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_CORE_EVENTBUS_MQH
#define PERCEPTION_CORE_EVENTBUS_MQH

#include <Perception/Core/Types.mqh>

class CEventBus
  {
private:
   SDecision         m_log[];        // ring buffer of recent decisions
   int               m_capacity;
   int               m_head;         // next write index
   int               m_count;        // number of valid entries

public:
                     CEventBus(): m_capacity(64), m_head(0), m_count(0)
     {
      ArrayResize(m_log,m_capacity);
     }

   void SetCapacity(const int cap)
     {
      m_capacity=(cap<8?8:cap);
      ArrayResize(m_log,m_capacity);
      m_head=0; m_count=0;
     }

   //--- publish a decision to the bus --------------------------------
   void Publish(const ENUM_ENGINE_ID engine,const bool accepted,const string text)
     {
      SDecision d;
      d.time=TimeCurrent();
      d.engine=engine;
      d.accepted=accepted;
      d.text=text;
      m_log[m_head]=d;
      m_head=(m_head+1)%m_capacity;
      if(m_count<m_capacity) m_count++;
     }

   int Count() const { return m_count; }

   //--- read the i-th most recent decision (0 = newest) --------------
   bool Recent(const int i,SDecision &out) const
     {
      if(i<0 || i>=m_count) return false;
      int idx=(m_head-1-i+m_capacity*2)%m_capacity;
      out=m_log[idx];
      return true;
     }

   void Clear() { m_head=0; m_count=0; }
  };

#endif // PERCEPTION_CORE_EVENTBUS_MQH
//+------------------------------------------------------------------+
