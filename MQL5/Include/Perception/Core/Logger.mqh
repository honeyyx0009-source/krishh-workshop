//+------------------------------------------------------------------+
//|                                                       Logger.mqh |
//|                     001 PERCEPTION - Lightweight logging          |
//|                                                                  |
//| A single logger instance is shared through the central context.  |
//| It respects a verbosity level so production runs stay quiet while |
//| debugging runs can be made verbose without touching call sites.  |
//+------------------------------------------------------------------+
#ifndef PERCEPTION_CORE_LOGGER_MQH
#define PERCEPTION_CORE_LOGGER_MQH

#include <Perception/Core/Enums.mqh>

class CLogger
  {
private:
   ENUM_LOG_LEVEL    m_level;
   string            m_tag;
public:
                     CLogger(): m_level(LOG_INFO), m_tag("001P") {}
   void              SetLevel(const ENUM_LOG_LEVEL lvl) { m_level=lvl; }
   void              SetTag(const string tag)           { m_tag=tag;   }

   void Error(const string msg) { if(m_level>=LOG_ERROR) Print(m_tag,"|ERR | ",msg); }
   void Warn (const string msg) { if(m_level>=LOG_WARN ) Print(m_tag,"|WARN| ",msg); }
   void Info (const string msg) { if(m_level>=LOG_INFO ) Print(m_tag,"|INFO| ",msg); }
   void Debug(const string msg) { if(m_level>=LOG_DEBUG) Print(m_tag,"|DBG | ",msg); }
  };

#endif // PERCEPTION_CORE_LOGGER_MQH
//+------------------------------------------------------------------+
