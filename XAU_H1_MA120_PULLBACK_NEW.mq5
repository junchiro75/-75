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
//| 2) Entry: M1, M2 and M3 each run their OWN independent copy of    |
//|    this logic in parallel -- NOT a race where only one wins. Every|
//|    H1 setup arms three separate watchers (one per timeframe), and |
//|    each one enters on its own schedule when ITS OWN candle first  |
//|    touches MA_Long (120): BUY setup -> price pulling back down to |
//|    MA_Long; SELL setup -> price bouncing up to it. In practice M1 |
//|    will typically touch first, then M2, then M3, but all three    |
//|    are independent trades with independent position sizes -- up   |
//|    to 3 concurrent positions can be open from a single H1 setup.  |
//|    Each timeframe's trade is managed (TP/SL) using ITS OWN MA20/  |
//|    BB4 levels for its whole life.                                  |
//|                                                                    |
//|    If AllowReentryAtBB=true (variant 2): on any one timeframe, if |
//|    its MA_Long entry gets stopped out, a re-entry is armed on that|
//|    SAME timeframe at the outer Bollinger band (lower BB20/BB4 for |
//|    BUY, upper for SELL). Only one re-entry per timeframe per H1   |
//|    setup. If AllowReentryAtBB=false (variant 1): each timeframe is|
//|    single-shot -- whichever of {MA_Long, BB} it touches FIRST is  |
//|    its only entry, no re-entry after a stop-out. If price skips   |
//|    straight past MA_Long to the BB without ever touching MA_Long, |
//|    that BB touch is used directly as the (only) entry.             |
//|                                                                    |
//| 3) Exit: take-profit when price reaches MA_Short (20) on the same |
//|    timeframe as the entry. Stop-loss (still experimental per      |
//|    user): on that timeframe's own BAR CLOSE beyond the OUTER band |
//|    (BB4) against the position ("이탈"), close at market. A         |
//|    MaxPositionHours safety timeout is also included (not          |
//|    explicitly requested, but matches this project's convention of |
//|    never leaving a position unmanaged indefinitely). A broker-side |
//|    emergency backstop SL is placed at entry too (pure disaster     |
//|    protection if the platform goes offline; the real exit is the   |
//|    EA-managed rules above).                                        |
//|                                                                    |
//| Because up to 3 positions can be open simultaneously (one per      |
//| timeframe), each uses its own magic number (MagicNumber + 0/1/2    |
//| for M1/M2/M3) and a HEDGING account is REQUIRED -- on a netting     |
//| account MT5 would merge same-direction fills into one net position |
//| and this EA's per-timeframe bookkeeping would no longer match      |
//| reality.                                                            |
//|                                                                    |
//| UNVALIDATED: brand new design, not yet backtested in any form      |
//| (Python or MT5). Test AllowReentryAtBB=true and false in MT5       |
//| Strategy Tester to see which performs better.                      |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input int    MA_Long              = 120;
input int    MA_Short             = 20;
input double BB20_Dev             = 2.0;
input double BB4_Dev              = 4.0;
input int    MaxSetupHours        = 72;   // how long a per-timeframe setup stays valid waiting for a touch
input int    MaxPositionHours     = 72;   // safety timeout force-close (not explicitly requested)
input bool   AllowReentryAtBB     = true; // false = variant 1 (single first-touch entry, no re-entry)
                                           // true  = variant 2 (MA_Long first; if stopped out, one
                                           //         re-entry chance at the outer Bollinger band)
input double Lots                 = 0.01; // PER TIMEFRAME -- up to 3x this can be open at once (M1+M2+M3)
input bool   EnableLiveOrders     = false; // SAFETY: set true only after checks
input ulong  MagicNumber          = 95014101; // base magic; M1/M2/M3 use MagicNumber+0/+1/+2
input int    MaxDeviationPts      = 50;
input int    EmergencySL_Points    = 5000; // broker-side backstop SL, this many points from entry.
                                           // Fixed and NOT band-relative on purpose: BB4's own width is
                                           // often just a few dollars (a handful of recent bars), so an
                                           // earlier band-relative backstop ended up TIGHTER than the
                                           // real intended SL_BAND rule and fired almost immediately on
                                           // most trades. This should rarely if ever be hit; the REAL
                                           // exit is the EA-managed bar-close BB4 rule above. Pure
                                           // protection against the platform/EA being offline.

#define N_TF 3
ENUM_TIMEFRAMES ENTRY_TFS[N_TF]={PERIOD_M1,PERIOD_M2,PERIOD_M3};

int hH1_20=INVALID_HANDLE,hH1_4=INVALID_HANDLE;
int hE_20[N_TF],hE_4[N_TF],hE_MAL[N_TF],hE_MAS[N_TF];
datetime last_h1_bar=0,last_e_bar[N_TF];

// Cached per-timeframe levels, each refreshed once per that timeframe's own bar close.
double cur_ma_long[N_TF],cur_ma_short[N_TF],cur_e_u20[N_TF],cur_e_l20[N_TF],cur_e_u4[N_TF],cur_e_l4[N_TF];
bool   cur_levels_ready[N_TF];

#define PHASE_WAIT_FIRST   0   // watching for MA_Long touch (and, in variant1, racing BB too)
#define PHASE_WAIT_REENTRY 1   // variant2 only: MA_Long leg was stopped out, watching for BB touch
struct Setup {
   datetime signal_time,expire_time;
   int dir;      // +1 BUY setup (from H1 bull), -1 SELL setup (from H1 bear)
   int tf;       // which timeframe index (0=M1,1=M2,2=M3) this setup belongs to
   int phase;
};
Setup setups[];

// Per-timeframe open-position state -- up to N_TF positions can be open concurrently.
bool     managed[N_TF];
ulong    managed_ticket[N_TF];
int      managed_dir[N_TF];
double   managed_entry[N_TF];
datetime managed_entry_time[N_TF];
bool     managed_from_bb[N_TF];      // true if that TF's OPEN position came from the BB leg
datetime managed_setup_expire[N_TF]; // that TF's owning setup's expiry (for the reentry decision)

string TS(datetime t){ return TimeToString(t,TIME_DATE|TIME_MINUTES|TIME_SECONDS); }
void Log(string event,string detail=""){ Print("MA120PULLBACK | ",event," | ",detail); }

ulong MagicFor(int tf){ return MagicNumber+(ulong)tf; }

void RemoveSetup(int idx)
{
   int n=ArraySize(setups);
   for(int j=idx;j<n-1;j++) setups[j]=setups[j+1];
   ArrayResize(setups,n-1);
}

bool OwnPosition(int tf,ulong &ticket)
{
   ulong magic=MagicFor(tf);
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t>0 && PositionSelectByTicket(t) &&
         PositionGetString(POSITION_SYMBOL)==_Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC)==magic){ ticket=t; return true; }
   }
   return false;
}

//--- Refresh MA_Long/MA_Short and band levels for timeframe index k; called once per that TF's bar close.
bool RefreshEntryLevels(int k)
{
   double mal[1],mas[1],u20[1],l20[1],u4[1],l4[1];
   if(CopyBuffer(hE_MAL[k],0,1,1,mal)!=1) return false;
   if(CopyBuffer(hE_MAS[k],0,1,1,mas)!=1) return false;
   if(CopyBuffer(hE_20[k],1,1,1,u20)!=1 || CopyBuffer(hE_20[k],2,1,1,l20)!=1) return false;
   if(CopyBuffer(hE_4[k],1,1,1,u4)!=1  || CopyBuffer(hE_4[k],2,1,1,l4)!=1) return false;
   cur_ma_long[k]=mal[0]; cur_ma_short[k]=mas[0];
   cur_e_u20[k]=u20[0]; cur_e_l20[k]=l20[0]; cur_e_u4[k]=u4[0]; cur_e_l4[k]=l4[0];
   cur_levels_ready[k]=true;
   return true;
}

//--- H1 signal detection: unchanged dual-BB breakout definition used throughout this project.
//    Arms THREE independent setups (one per timeframe) per signal.
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

   datetime expire=t+MaxSetupHours*3600;
   for(int k=0;k<N_TF;k++)
   {
      int n=ArraySize(setups); ArrayResize(setups,n+1);
      setups[n].signal_time=sig;
      setups[n].expire_time=expire;
      setups[n].dir=dir;
      setups[n].tf=k;
      setups[n].phase=PHASE_WAIT_FIRST;
   }
   Log("SETUP_ARMED",(dir==1?"BUY":"SELL")+string(" from H1 ")+(dir==1?"BULL":"BEAR")+
       " | M1+M2+M3 independently watching for MA"+IntegerToString(MA_Long)+" touch");
}

bool OpenFromSetup(int dir,int tf,bool fromBB,datetime setup_expire,MqlTick &tick)
{
   ulong old; if(OwnPosition(tf,old)) return false; // MAX1 per timeframe

   double entry=(dir==+1?tick.ask:tick.bid);
   ulong magic=MagicFor(tf);
   trade.SetExpertMagicNumber(magic);
   trade.SetDeviationInPoints(MaxDeviationPts);
   trade.SetTypeFillingBySymbol(_Symbol);

   if(!EnableLiveOrders)
   {
      Log("DRY_ENTRY",(dir==1?"BUY":"SELL")+string(" @~")+DoubleToString(entry,_Digits)+
          " | leg="+(fromBB?"BB":"MA120")+" | tf="+EnumToString(ENTRY_TFS[tf]));
      managed[tf]=true; managed_ticket[tf]=0; managed_dir[tf]=dir; managed_entry[tf]=entry;
      managed_entry_time[tf]=(datetime)(tick.time_msc/1000);
      managed_from_bb[tf]=fromBB; managed_setup_expire[tf]=setup_expire;
      return true;
   }

   double sl=entry-dir*EmergencySL_Points*_Point;
   if(sl>0) sl=NormalizeDouble(sl,_Digits);

   bool ok=(dir==+1 ? trade.Buy(Lots,_Symbol,0.0,sl,0.0,"MA120PULLBACK_"+EnumToString(ENTRY_TFS[tf]))
                    : trade.Sell(Lots,_Symbol,0.0,sl,0.0,"MA120PULLBACK_"+EnumToString(ENTRY_TFS[tf])));
   if(!ok)
   {
      Log("ORDER_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
      return false;
   }
   ulong t;
   if(OwnPosition(tf,t) && PositionSelectByTicket(t))
   {
      managed[tf]=true; managed_ticket[tf]=t; managed_dir[tf]=dir;
      managed_entry[tf]=PositionGetDouble(POSITION_PRICE_OPEN);
      managed_entry_time[tf]=(datetime)PositionGetInteger(POSITION_TIME);
   }
   else
   {
      managed[tf]=true; managed_ticket[tf]=0; managed_dir[tf]=dir; managed_entry[tf]=entry;
      managed_entry_time[tf]=(datetime)(tick.time_msc/1000);
   }
   managed_from_bb[tf]=fromBB; managed_setup_expire[tf]=setup_expire;
   Log("ENTRY_OK",(dir==1?"BUY":"SELL")+string(" entry=")+DoubleToString(managed_entry[tf],_Digits)+
       " | leg="+(fromBB?"BB":"MA120")+" | tf="+EnumToString(ENTRY_TFS[tf]));
   return true;
}

void ClosePosition(int tf,string reason)
{
   if(EnableLiveOrders && managed_ticket[tf]>0)
   {
      trade.SetExpertMagicNumber(MagicFor(tf));
      if(!trade.PositionClose(managed_ticket[tf]))
         Log("CLOSE_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
   }
   Log("EXIT_"+reason,(managed_dir[tf]==1?"BUY":"SELL")+" entry="+DoubleToString(managed_entry[tf],_Digits)+
       " | tf="+EnumToString(ENTRY_TFS[tf]));

   // Variant 2: a SL_BAND exit from the MA_Long leg arms exactly one re-entry chance at the BB,
   // on the SAME timeframe.
   if(reason=="SL_BAND" && AllowReentryAtBB && !managed_from_bb[tf] && TimeCurrent()<managed_setup_expire[tf])
   {
      int n=ArraySize(setups); ArrayResize(setups,n+1);
      setups[n].signal_time=TimeCurrent();
      setups[n].expire_time=managed_setup_expire[tf];
      setups[n].dir=managed_dir[tf];
      setups[n].tf=tf;
      setups[n].phase=PHASE_WAIT_REENTRY;
      Log("REENTRY_ARMED",(managed_dir[tf]==1?"BUY":"SELL")+" | tf="+EnumToString(ENTRY_TFS[tf])+
          " | waiting for BB touch");
   }

   managed[tf]=false; managed_ticket[tf]=0; managed_dir[tf]=0; managed_entry[tf]=0; managed_from_bb[tf]=false;
}

//--- Process pending setups against the current tick. Each setup only watches its OWN timeframe.
void CheckSetups(MqlTick &tick)
{
   datetime now=(datetime)(tick.time_msc/1000);

   for(int i=ArraySize(setups)-1;i>=0;i--)
   {
      int tf=setups[i].tf;
      if(now>setups[i].expire_time)
      { Log("SETUP_EXPIRE",TS(setups[i].signal_time)+" tf="+EnumToString(ENTRY_TFS[tf])); RemoveSetup(i); continue; }

      if(!cur_levels_ready[tf]) continue;
      if(managed[tf]) continue; // MAX1 per timeframe: wait for that TF's position to close first

      int dir=setups[i].dir;
      bool touchedMA=(dir==+1 ? tick.bid<=cur_ma_long[tf] : tick.ask>=cur_ma_long[tf]);
      bool touchedBB=(dir==+1 ? (tick.bid<=cur_e_l20[tf] || tick.bid<=cur_e_l4[tf])
                               : (tick.ask>=cur_e_u20[tf] || tick.ask>=cur_e_u4[tf]));

      if(setups[i].phase==PHASE_WAIT_REENTRY)
      {
         if(touchedBB)
         {
            Log("REENTRY_TOUCH",TS(setups[i].signal_time)+" tf="+EnumToString(ENTRY_TFS[tf]));
            if(OpenFromSetup(dir,tf,true,setups[i].expire_time,tick)) RemoveSetup(i);
         }
         continue;
      }

      // PHASE_WAIT_FIRST
      if(!AllowReentryAtBB)
      {
         // Variant 1: whichever level is touched first (on this TF) is the only entry.
         if(touchedMA || touchedBB)
         {
            Log("FIRST_TOUCH",TS(setups[i].signal_time)+" via "+(touchedMA?"MA120":"BB")+
                " tf="+EnumToString(ENTRY_TFS[tf]));
            if(OpenFromSetup(dir,tf,!touchedMA,setups[i].expire_time,tick)) RemoveSetup(i);
         }
      }
      else
      {
         // Variant 2: MA_Long has priority; if price skips straight to BB, use that
         // directly (no deeper level left, so no reentry armed afterwards).
         if(touchedMA)
         {
            Log("MA120_TOUCH",TS(setups[i].signal_time)+" tf="+EnumToString(ENTRY_TFS[tf]));
            if(OpenFromSetup(dir,tf,false,setups[i].expire_time,tick)) RemoveSetup(i);
         }
         else if(touchedBB)
         {
            Log("SKIP_TO_BB",TS(setups[i].signal_time)+" tf="+EnumToString(ENTRY_TFS[tf]));
            if(OpenFromSetup(dir,tf,true,setups[i].expire_time,tick)) RemoveSetup(i);
         }
      }
   }
}

//--- Manage every open position: TP at MA_Short, timeout, all evaluated per-timeframe.
void ManageOpenPositions(MqlTick &tick)
{
   datetime now=(datetime)(tick.time_msc/1000);
   for(int tf=0;tf<N_TF;tf++)
   {
      if(!managed[tf]) continue;
      if(EnableLiveOrders)
      {
         ulong t; if(!OwnPosition(tf,t)){ managed[tf]=false; managed_ticket[tf]=0; managed_dir[tf]=0; continue; } // closed by broker (rare)
      }

      if(now>managed_entry_time[tf]+MaxPositionHours*3600) { ClosePosition(tf,"TIMEOUT"); continue; }

      double px=(managed_dir[tf]==+1?tick.bid:tick.ask);
      bool tp_hit=(managed_dir[tf]==+1 ? px>=cur_ma_short[tf] : px<=cur_ma_short[tf]);
      if(tp_hit){ ClosePosition(tf,"TP_MA_SHORT"); continue; }
      // SL is evaluated on this TF's own bar close (see OnNewEntryBars) to avoid single-wick noise.
   }
}

void OnNewEntryBars()
{
   for(int k=0;k<N_TF;k++)
   {
      datetime t=iTime(_Symbol,ENTRY_TFS[k],0);
      if(t==0 || t==last_e_bar[k]) continue;
      last_e_bar[k]=t;
      if(!RefreshEntryLevels(k)) continue;

      if(managed[k])
      {
         double last_close=iClose(_Symbol,ENTRY_TFS[k],1);
         bool sl_hit=(managed_dir[k]==+1 ? last_close<cur_e_l4[k] : last_close>cur_e_u4[k]);
         if(sl_hit) ClosePosition(k,"SL_BAND");
      }
   }
}

int OnInit()
{
   // Up to 3 concurrent same-symbol positions (one per timeframe) require hedging.
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      Print("MA120PULLBACK INIT FAILED: HEDGING account required (up to 3 concurrent M1/M2/M3 positions).");
      return INIT_FAILED;
   }

   hH1_20=iBands(_Symbol,PERIOD_H1,20,0,BB20_Dev,PRICE_CLOSE);
   hH1_4 =iBands(_Symbol,PERIOD_H1,4,0,BB4_Dev,PRICE_OPEN);
   if(hH1_20==INVALID_HANDLE||hH1_4==INVALID_HANDLE) return INIT_FAILED;

   for(int k=0;k<N_TF;k++)
   {
      hE_20[k] =iBands(_Symbol,ENTRY_TFS[k],20,0,BB20_Dev,PRICE_CLOSE);
      hE_4[k]  =iBands(_Symbol,ENTRY_TFS[k],4,0,BB4_Dev,PRICE_OPEN);
      hE_MAL[k]=iMA(_Symbol,ENTRY_TFS[k],MA_Long,0,MODE_SMA,PRICE_CLOSE);
      hE_MAS[k]=iMA(_Symbol,ENTRY_TFS[k],MA_Short,0,MODE_SMA,PRICE_CLOSE);
      if(hE_20[k]==INVALID_HANDLE||hE_4[k]==INVALID_HANDLE||
         hE_MAL[k]==INVALID_HANDLE||hE_MAS[k]==INVALID_HANDLE) return INIT_FAILED;
      last_e_bar[k]=0; cur_levels_ready[k]=false;
      managed[k]=false; managed_ticket[k]=0; managed_dir[k]=0; managed_entry[k]=0;
      managed_from_bb[k]=false;
   }

   Log("START","EntryTFs=M1+M2+M3 (all independent) | MA_Long="+IntegerToString(MA_Long)+
       " | MA_Short="+IntegerToString(MA_Short)+" | AllowReentryAtBB="+(AllowReentryAtBB?"true":"false")+
       " | BaseMagic="+IntegerToString((int)MagicNumber)+" (M1/M2/M3 = base+0/+1/+2)"+
       " | orders="+(EnableLiveOrders?"ENABLED":"DRY"));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(hH1_20!=INVALID_HANDLE) IndicatorRelease(hH1_20);
   if(hH1_4!=INVALID_HANDLE)  IndicatorRelease(hH1_4);
   for(int k=0;k<N_TF;k++)
   {
      if(hE_20[k]!=INVALID_HANDLE)  IndicatorRelease(hE_20[k]);
      if(hE_4[k]!=INVALID_HANDLE)   IndicatorRelease(hE_4[k]);
      if(hE_MAL[k]!=INVALID_HANDLE) IndicatorRelease(hE_MAL[k]);
      if(hE_MAS[k]!=INVALID_HANDLE) IndicatorRelease(hE_MAS[k]);
   }
}

void OnTick()
{
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;
   CheckH1Signal();
   OnNewEntryBars();
   CheckSetups(tick);
   ManageOpenPositions(tick);
}
//+------------------------------------------------------------------+
