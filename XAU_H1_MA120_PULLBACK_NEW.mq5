//+------------------------------------------------------------------+
//| XAU_H1_MA120_PULLBACK_NEW.mq5                                    |
//| NEW strategy (user-designed), trend-following (NOT countertrend):|
//|                                                                    |
//| 1) H1 signal filter: same dual-BB breakout used elsewhere in this |
//|    project (BB20 dev2.0 on Close + BB4 dev4.0 on Open, PERIOD_H1).|
//|    A BULL H1 bar (up breakout) arms a BUY setup. A BEAR H1 bar    |
//|    (down breakout) arms a SELL setup. Unlike the countertrend EAs,|
//|    the trade direction here MATCHES the H1 signal direction.      |
//|                                                                    |
//| 2) Entry timing on a lower "entry timeframe" (EntryTF input --    |
//|    run this EA separately on M1 / M2 / M3 to compare):            |
//|      - BUY setup: wait for price to pull back down and TOUCH the  |
//|        MA_Long (120) moving average on EntryTF -> enter BUY.      |
//|      - SELL setup: mirror -- wait for a bounce up to touch MA_Long|
//|        -> enter SELL.                                             |
//|    If AllowReentryAtBB=true (variant 2), a SECOND chance is given:|
//|    if the MA_Long entry gets stopped out, arm a re-entry at the   |
//|    EntryTF's own outer Bollinger band (lower BB20/BB4 for BUY,    |
//|    upper BB20/BB4 for SELL) -- catches the "falls further before  |
//|    turning" case the user described. Only one re-entry per H1     |
//|    setup. If AllowReentryAtBB=false (variant 1), it's a single    |
//|    shot: whichever level (MA_Long or the BB) is touched FIRST is  |
//|    the only entry, no re-entry after a stop-out.                  |
//|    If price skips straight past MA_Long to the BB without ever    |
//|    registering a touch there, that BB touch itself is used as the |
//|    (only) entry -- there is no deeper level left to re-enter at.  |
//|                                                                    |
//| 3) Exit: take-profit when price reaches MA_Short (20) on EntryTF.  |
//|    Stop-loss (still experimental per user): on an EntryTF BAR      |
//|    CLOSE beyond the OUTER band (BB4) against the position ("이탈"),|
//|    close at market. A MaxPositionHours safety timeout is also      |
//|    included (not explicitly requested, but matches this project's  |
//|    convention of never leaving a position unmanaged indefinitely). |
//|                                                                    |
//| UNVALIDATED: brand new design, not yet backtested in any form      |
//| (Python or MT5). Test both AllowReentryAtBB=true/false, and each   |
//| of EntryTF=M1/M2/M3, to see which combination performs best.       |
//| Own-Magic MAX1 (one position at a time), same discipline as the    |
//| other EAs in this project.                                         |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input ENUM_TIMEFRAMES EntryTF     = PERIOD_M2;  // run separately for M1 / M2 / M3 to compare
input int    MA_Long              = 120;
input int    MA_Short             = 20;
input double BB20_Dev             = 2.0;
input double BB4_Dev              = 4.0;
input int    MaxSetupHours        = 72;   // how long an H1 setup stays valid waiting for a touch
input int    MaxPositionHours     = 72;   // safety timeout force-close (not explicitly requested)
input bool   AllowReentryAtBB     = true; // false = variant 1 (single first-touch entry, no re-entry)
                                           // true  = variant 2 (MA_Long first; if stopped out, one
                                           //         re-entry chance at the outer Bollinger band)
input double Lots                 = 0.01;
input bool   EnableLiveOrders     = false; // SAFETY: set true only after checks
input ulong  MagicNumber          = 95014101;
input int    MaxDeviationPts      = 50;
input double EmergencySL_BandMult = 3.0;  // broker-side backstop SL, set at (outer band half-width * this
                                           // multiple) from entry -- should rarely be hit; the REAL exit
                                           // is the EA-managed bar-close BB4 rule above. Pure protection
                                           // against the platform/EA being offline.

int hH1_20=INVALID_HANDLE,hH1_4=INVALID_HANDLE;
int hE_20=INVALID_HANDLE,hE_4=INVALID_HANDLE,hE_MAL=INVALID_HANDLE,hE_MAS=INVALID_HANDLE;
datetime last_h1_bar=0,last_e_bar=0;

// Cached EntryTF-derived levels, refreshed once per EntryTF bar close (not every tick).
double cur_ma_long=0,cur_ma_short=0,cur_e_u20=0,cur_e_l20=0,cur_e_u4=0,cur_e_l4=0;
bool   cur_levels_ready=false;

#define PHASE_WAIT_FIRST   0   // watching for MA_Long touch (and, in variant1, racing BB too)
#define PHASE_WAIT_REENTRY 1   // variant2 only: MA_Long leg was stopped out, watching for BB touch
struct Setup {
   datetime signal_time,expire_time;
   int dir;      // +1 BUY setup (from H1 bull), -1 SELL setup (from H1 bear)
   int phase;
};
Setup setups[];

bool   managed=false;
ulong  managed_ticket=0;
int    managed_dir=0;
double managed_entry=0;
datetime managed_entry_time=0;
bool   managed_from_bb=false;      // true if the OPEN position's entry came from the BB leg (reentry or direct-skip)
datetime managed_setup_expire=0;   // the owning setup's expiry, needed to decide whether to arm reentry on SL

string TS(datetime t){ return TimeToString(t,TIME_DATE|TIME_MINUTES|TIME_SECONDS); }
void Log(string event,string detail=""){ Print("MA120PULLBACK | ",event," | ",detail); }

void RemoveSetup(int idx)
{
   int n=ArraySize(setups);
   for(int j=idx;j<n-1;j++) setups[j]=setups[j+1];
   ArrayResize(setups,n-1);
}

bool OwnPosition(ulong &ticket)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t>0 && PositionSelectByTicket(t) &&
         PositionGetString(POSITION_SYMBOL)==_Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC)==MagicNumber){ ticket=t; return true; }
   }
   return false;
}

//--- Refresh MA_Long/MA_Short and EntryTF band levels; called once per EntryTF bar close.
bool RefreshEntryLevels()
{
   double mal[1],mas[1],u20[1],l20[1],u4[1],l4[1];
   if(CopyBuffer(hE_MAL,0,1,1,mal)!=1) return false;
   if(CopyBuffer(hE_MAS,0,1,1,mas)!=1) return false;
   if(CopyBuffer(hE_20,1,1,1,u20)!=1 || CopyBuffer(hE_20,2,1,1,l20)!=1) return false;
   if(CopyBuffer(hE_4,1,1,1,u4)!=1  || CopyBuffer(hE_4,2,1,1,l4)!=1) return false;
   cur_ma_long=mal[0]; cur_ma_short=mas[0];
   cur_e_u20=u20[0]; cur_e_l20=l20[0]; cur_e_u4=u4[0]; cur_e_l4=l4[0];
   cur_levels_ready=true;
   return true;
}

//--- H1 signal detection: unchanged dual-BB breakout definition used throughout this project.
void CheckH1Signal()
{
   datetime t=iTime(_Symbol,PERIOD_H1,0);
   if(t==0 || t==last_h1_bar) return;
   last_h1_bar=t;

   double o=iOpen(_Symbol,PERIOD_H1,1),h=iHigh(_Symbol,PERIOD_H1,1);
   double l=iLow(_Symbol,PERIOD_H1,1),c=iClose(_Symbol,PERIOD_H1,1);
   datetime sig=iTime(_Symbol,PERIOD_H1,1);
   if(sig==0) return;

   double u20[1],l20[1],u4[1],l4[1];
   if(CopyBuffer(hH1_20,1,1,1,u20)!=1 || CopyBuffer(hH1_20,2,1,1,l20)!=1 ||
      CopyBuffer(hH1_4,1,1,1,u4)!=1   || CopyBuffer(hH1_4,2,1,1,l4)!=1) return;

   int dir=0;
   if(c>o && h>=u20[0] && h>=u4[0]) dir=+1;      // H1 bull breakout -> BUY setup
   else if(c<o && l<=l20[0] && l<=l4[0]) dir=-1; // H1 bear breakout -> SELL setup
   if(dir==0) return;

   int n=ArraySize(setups); ArrayResize(setups,n+1);
   setups[n].signal_time=sig;
   setups[n].expire_time=t+MaxSetupHours*3600;
   setups[n].dir=dir;
   setups[n].phase=PHASE_WAIT_FIRST;
   Log("SETUP_ARMED",(dir==1?"BUY":"SELL")+string(" from H1 ")+(dir==1?"BULL":"BEAR")+
       " | waiting for MA"+IntegerToString(MA_Long)+" touch on "+EnumToString(EntryTF));
}

bool HasFreeSlot()
{
   ulong t; return !OwnPosition(t);
}

bool OpenFromSetup(int dir,bool fromBB,datetime setup_expire,MqlTick &tick)
{
   ulong old; if(OwnPosition(old)) return false; // MAX1

   double entry=(dir==+1?tick.ask:tick.bid);
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(MaxDeviationPts);
   trade.SetTypeFillingBySymbol(_Symbol);

   if(!EnableLiveOrders)
   {
      Log("DRY_ENTRY",(dir==1?"BUY":"SELL")+string(" @~")+DoubleToString(entry,_Digits)+
          " | leg="+(fromBB?"BB":"MA120"));
      managed=true; managed_ticket=0; managed_dir=dir; managed_entry=entry;
      managed_entry_time=(datetime)(tick.time_msc/1000);
      managed_from_bb=fromBB; managed_setup_expire=setup_expire;
      return true;
   }

   double half_width=MathMax(cur_e_u4-cur_e_l4,0.0)/2.0;
   double backstop=half_width*EmergencySL_BandMult;
   double sl=(backstop>0 ? entry-dir*backstop : 0.0);
   if(sl>0) sl=NormalizeDouble(sl,_Digits);

   bool ok=(dir==+1 ? trade.Buy(Lots,_Symbol,0.0,sl,0.0,"MA120PULLBACK")
                    : trade.Sell(Lots,_Symbol,0.0,sl,0.0,"MA120PULLBACK"));
   if(!ok)
   {
      Log("ORDER_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
      return false;
   }
   ulong t;
   if(OwnPosition(t) && PositionSelectByTicket(t))
   {
      managed=true; managed_ticket=t; managed_dir=dir;
      managed_entry=PositionGetDouble(POSITION_PRICE_OPEN);
      managed_entry_time=(datetime)PositionGetInteger(POSITION_TIME);
   }
   else
   {
      managed=true; managed_ticket=0; managed_dir=dir; managed_entry=entry;
      managed_entry_time=(datetime)(tick.time_msc/1000);
   }
   managed_from_bb=fromBB; managed_setup_expire=setup_expire;
   Log("ENTRY_OK",(dir==1?"BUY":"SELL")+string(" entry=")+DoubleToString(managed_entry,_Digits)+
       " | leg="+(fromBB?"BB":"MA120"));
   return true;
}

void ClosePosition(string reason)
{
   if(EnableLiveOrders && managed_ticket>0)
   {
      trade.SetExpertMagicNumber(MagicNumber);
      if(!trade.PositionClose(managed_ticket))
         Log("CLOSE_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
   }
   Log("EXIT_"+reason,(managed_dir==1?"BUY":"SELL")+" entry="+DoubleToString(managed_entry,_Digits));

   // Variant 2: a SL_BAND exit from the MA_Long leg arms exactly one re-entry chance at the BB.
   if(reason=="SL_BAND" && AllowReentryAtBB && !managed_from_bb && TimeCurrent()<managed_setup_expire)
   {
      int n=ArraySize(setups); ArrayResize(setups,n+1);
      setups[n].signal_time=TimeCurrent();
      setups[n].expire_time=managed_setup_expire;
      setups[n].dir=managed_dir;
      setups[n].phase=PHASE_WAIT_REENTRY;
      Log("REENTRY_ARMED",(managed_dir==1?"BUY":"SELL")+" | waiting for BB touch on "+EnumToString(EntryTF));
   }

   managed=false; managed_ticket=0; managed_dir=0; managed_entry=0; managed_from_bb=false;
}

//--- Process pending setups against the current tick: touch checks and entry dispatch.
void CheckSetups(MqlTick &tick)
{
   if(!cur_levels_ready) return;
   datetime now=(datetime)(tick.time_msc/1000);

   for(int i=ArraySize(setups)-1;i>=0;i--)
   {
      if(now>setups[i].expire_time)
      { Log("SETUP_EXPIRE",TS(setups[i].signal_time)); RemoveSetup(i); continue; }

      if(!HasFreeSlot()) continue; // MAX1: wait for the current position to close first

      int dir=setups[i].dir;
      bool touchedMA  =(dir==+1 ? tick.bid<=cur_ma_long : tick.ask>=cur_ma_long);
      bool touchedBB  =(dir==+1 ? (tick.bid<=cur_e_l20 || tick.bid<=cur_e_l4)
                                 : (tick.ask>=cur_e_u20 || tick.ask>=cur_e_u4));

      if(setups[i].phase==PHASE_WAIT_REENTRY)
      {
         if(touchedBB)
         {
            Log("REENTRY_TOUCH",TS(setups[i].signal_time));
            OpenFromSetup(dir,true,setups[i].expire_time,tick);
            RemoveSetup(i);
         }
         continue;
      }

      // PHASE_WAIT_FIRST
      if(!AllowReentryAtBB)
      {
         // Variant 1: whichever level is touched first is the only entry.
         if(touchedMA || touchedBB)
         {
            Log("FIRST_TOUCH",TS(setups[i].signal_time)+" via "+(touchedMA?"MA120":"BB"));
            OpenFromSetup(dir,!touchedMA,setups[i].expire_time,tick);
            RemoveSetup(i);
         }
      }
      else
      {
         // Variant 2: MA_Long has priority; if price skips straight to BB, use that
         // directly (no deeper level left, so no reentry armed afterwards).
         if(touchedMA)
         {
            Log("MA120_TOUCH",TS(setups[i].signal_time));
            OpenFromSetup(dir,false,setups[i].expire_time,tick);
            RemoveSetup(i);
         }
         else if(touchedBB)
         {
            Log("SKIP_TO_BB",TS(setups[i].signal_time));
            OpenFromSetup(dir,true,setups[i].expire_time,tick);
            RemoveSetup(i);
         }
      }
   }
}

//--- Manage the open position: TP at MA_Short, SL on an EntryTF bar-close beyond the outer band,
//    plus a safety timeout.
void ManageOpenPosition(MqlTick &tick)
{
   if(!managed) return;
   if(EnableLiveOrders)
   {
      ulong t; if(!OwnPosition(t)){ managed=false; managed_ticket=0; managed_dir=0; return; } // closed by broker (rare)
   }

   datetime now=(datetime)(tick.time_msc/1000);
   if(now>managed_entry_time+MaxPositionHours*3600) { ClosePosition("TIMEOUT"); return; }

   double px=(managed_dir==+1?tick.bid:tick.ask);
   bool tp_hit=(managed_dir==+1 ? px>=cur_ma_short : px<=cur_ma_short);
   if(tp_hit){ ClosePosition("TP_MA_SHORT"); return; }
   // SL is evaluated on EntryTF bar close (see OnNewEntryBar) to avoid single-wick noise.
}

void OnNewEntryBar(MqlTick &tick)
{
   datetime t=iTime(_Symbol,EntryTF,0);
   if(t==0 || t==last_e_bar) return;
   last_e_bar=t;
   if(!RefreshEntryLevels()) return;

   if(managed)
   {
      double last_close=iClose(_Symbol,EntryTF,1);
      bool sl_hit=(managed_dir==+1 ? last_close<cur_e_l4 : last_close>cur_e_u4);
      if(sl_hit) ClosePosition("SL_BAND");
   }
}

int OnInit()
{
   hH1_20=iBands(_Symbol,PERIOD_H1,20,0,BB20_Dev,PRICE_CLOSE);
   hH1_4 =iBands(_Symbol,PERIOD_H1,4,0,BB4_Dev,PRICE_OPEN);
   hE_20 =iBands(_Symbol,EntryTF,20,0,BB20_Dev,PRICE_CLOSE);
   hE_4  =iBands(_Symbol,EntryTF,4,0,BB4_Dev,PRICE_OPEN);
   hE_MAL=iMA(_Symbol,EntryTF,MA_Long,0,MODE_SMA,PRICE_CLOSE);
   hE_MAS=iMA(_Symbol,EntryTF,MA_Short,0,MODE_SMA,PRICE_CLOSE);
   if(hH1_20==INVALID_HANDLE||hH1_4==INVALID_HANDLE||hE_20==INVALID_HANDLE||
      hE_4==INVALID_HANDLE||hE_MAL==INVALID_HANDLE||hE_MAS==INVALID_HANDLE) return INIT_FAILED;

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(MaxDeviationPts);
   trade.SetTypeFillingBySymbol(_Symbol);

   Log("START","EntryTF="+EnumToString(EntryTF)+" | MA_Long="+IntegerToString(MA_Long)+
       " | MA_Short="+IntegerToString(MA_Short)+" | AllowReentryAtBB="+(AllowReentryAtBB?"true":"false")+
       " | Magic="+IntegerToString((int)MagicNumber)+" | orders="+(EnableLiveOrders?"ENABLED":"DRY"));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(hH1_20!=INVALID_HANDLE) IndicatorRelease(hH1_20);
   if(hH1_4!=INVALID_HANDLE)  IndicatorRelease(hH1_4);
   if(hE_20!=INVALID_HANDLE)  IndicatorRelease(hE_20);
   if(hE_4!=INVALID_HANDLE)   IndicatorRelease(hE_4);
   if(hE_MAL!=INVALID_HANDLE) IndicatorRelease(hE_MAL);
   if(hE_MAS!=INVALID_HANDLE) IndicatorRelease(hE_MAS);
}

void OnTick()
{
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;
   CheckH1Signal();
   OnNewEntryBar(tick);
   CheckSetups(tick);
   ManageOpenPosition(tick);
}
//+------------------------------------------------------------------+
