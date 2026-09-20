//+------------------------------------------------------------------+
//| XAU_H1_MA120_PULLBACK_NEW_V5.mq5                                 |
//| V5: order comment now tags which band (BB20 or BB4) triggered    |
//| entry and which timeframe, e.g. "MA120_M2_BB20" -- so results can |
//| be split by entry band in the Deals report. No logic change from |
//| V4 otherwise (same MA120-arm + BB-entry + StopLoss_R design; test |
//| StopLoss_R=3.0 by just changing that input, no code change needed)|
//| NEW strategy (user-designed), trend-following (NOT countertrend):|
//|                                                                    |
//| 1) H1 signal filter: same dual-BB breakout used elsewhere in this |
//|    project (BB20 dev2.0 on Close + BB4 dev4.0 on Open, PERIOD_H1).|
//|    A BULL H1 bar (up breakout) arms a BUY setup. A BEAR H1 bar    |
//|    (down breakout) arms a SELL setup. Unlike the countertrend EAs,|
//|    the trade direction here MATCHES the H1 signal direction.      |
//|                                                                    |
//| 2) Entry: M1, M2 and M3 each run their OWN independent copy of    |
//|    this logic in parallel (not a race -- up to 3 concurrent       |
//|    positions per H1 setup, one per timeframe, each on its own     |
//|    magic number MagicNumber+0/+1/+2). Two-stage entry:            |
//|      Stage A -- ARM: wait for that timeframe's own candle to      |
//|      touch MA_Long (120). This is NOT an entry, just confirmation |
//|      that price has pulled back far enough to be interesting.     |
//|      Stage B -- ENTER: after MA_Long is touched, wait for price   |
//|      to reach the outer Bollinger band (BB20 or BB4, whichever    |
//|      touches first) and enter THERE. R = |MA_Long value at that   |
//|      moment - entry price| (how far price overshot MA_Long to     |
//|      reach the band). SL = entry -+ 2R (a real broker-side stop,  |
//|      same 2R convention as the other EAs in this project).        |
//|                                                                    |
//|    V4 CHANGE (was V1-V3's "enter AT MA_Long"): backtesting showed  |
//|    that on M1/M2/M3, MA_Long and MA_Short are often closer         |
//|    together than the bid-ask spread, so entering right at MA_Long |
//|    let TP trigger almost instantly for a spread-sized loss ~39%   |
//|    of the time. Requiring the extra move out to the Bollinger band|
//|    before entering, plus a real 2R stop instead of a fixed-points |
//|    backstop, gives the trade actual room. AllowReentryAtBB and    |
//|    the old bar-close-beyond-BB4 SL rule are both gone -- with     |
//|    entry now happening AT the band, "re-enter at the band" no     |
//|    longer means anything, and 2R is now the one real stop.        |
//|                                                                    |
//| 3) Exit: take-profit when price reaches MA_Short (20) on the same  |
//|    timeframe as the entry (EA-managed, since MA_Short moves every |
//|    bar). Stop-loss is the 2R broker-side order placed at entry.    |
//|    A MaxPositionHours safety timeout is also included (not         |
//|    explicitly requested, but matches this project's convention of |
//|    never leaving a position unmanaged indefinitely).               |
//|                                                                    |
//| Because up to 3 positions can be open simultaneously (one per      |
//| timeframe), each uses its own magic number (MagicNumber + 0/1/2    |
//| for M1/M2/M3) and a HEDGING account is REQUIRED -- on a netting     |
//| account MT5 would merge same-direction fills into one net position |
//| and this EA's per-timeframe bookkeeping would no longer match      |
//| reality.                                                            |
//|                                                                    |
//| UNVALIDATED: brand new entry/SL mechanism, not yet backtested in   |
//| any form. Test in MT5 Strategy Tester before drawing conclusions.  |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input int    MA_Long              = 120;
input int    MA_Short             = 20;
input double BB20_Dev             = 2.0;
input double BB4_Dev              = 4.0;
input double StopLoss_R           = 2.0;  // SL = entry -+ StopLoss_R * R, R = |MA_Long - entry price| at entry
input int    MaxSetupHours        = 72;   // how long a per-timeframe setup stays valid waiting for a touch
input int    MaxPositionHours     = 72;   // safety timeout force-close (not explicitly requested)
input double Lots                 = 0.01; // PER TIMEFRAME -- up to 3x this can be open at once (M1+M2+M3)
input bool   EnableLiveOrders     = false; // SAFETY: set true only after checks
input ulong  MagicNumber          = 95014101; // base magic; M1/M2/M3 use MagicNumber+0/+1/+2
input int    MaxDeviationPts      = 50;

#define N_TF 3
ENUM_TIMEFRAMES ENTRY_TFS[N_TF]={PERIOD_M1,PERIOD_M2,PERIOD_M3};

int hH1_20=INVALID_HANDLE,hH1_4=INVALID_HANDLE;
int hE_20[N_TF],hE_4[N_TF],hE_MAL[N_TF],hE_MAS[N_TF];
datetime last_h1_bar=0,last_e_bar[N_TF];

// Cached per-timeframe levels, each refreshed once per that timeframe's own bar close.
double cur_ma_long[N_TF],cur_ma_short[N_TF],cur_e_u20[N_TF],cur_e_l20[N_TF],cur_e_u4[N_TF],cur_e_l4[N_TF];
bool   cur_levels_ready[N_TF];

#define PHASE_WAIT_MA120  0   // waiting for this timeframe's candle to touch MA_Long (arm only, no entry)
#define PHASE_WAIT_BB     1   // MA_Long armed; waiting for BB20/BB4 touch to actually enter
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
      setups[n].phase=PHASE_WAIT_MA120;
   }
   Log("SETUP_ARMED",(dir==1?"BUY":"SELL")+string(" from H1 ")+(dir==1?"BULL":"BEAR")+
       " | M1+M2+M3 independently watching for MA"+IntegerToString(MA_Long)+" touch");
}

bool OpenAtBB(int dir,int tf,double maLongAtTouch,string bandLabel,datetime setup_expire,MqlTick &tick)
{
   ulong old; if(OwnPosition(tf,old)) return false; // MAX1 per timeframe

   double entry=(dir==+1?tick.ask:tick.bid);
   double R=MathAbs(maLongAtTouch-entry);
   if(R<=_Point)
   {
      Log("ENTRY_SKIPPED","R too small (MA_Long≈entry) tf="+EnumToString(ENTRY_TFS[tf]));
      return false;
   }
   double sl=entry-dir*StopLoss_R*R;
   string tag="M"+IntegerToString((int)PeriodSeconds(ENTRY_TFS[tf])/60)+"_"+bandLabel; // e.g. M1_BB20

   ulong magic=MagicFor(tf);
   trade.SetExpertMagicNumber(magic);
   trade.SetDeviationInPoints(MaxDeviationPts);
   trade.SetTypeFillingBySymbol(_Symbol);

   if(!EnableLiveOrders)
   {
      Log("DRY_ENTRY",(dir==1?"BUY":"SELL")+string(" @~")+DoubleToString(entry,_Digits)+
          " R="+DoubleToString(R,_Digits)+" SL="+DoubleToString(sl,_Digits)+" | "+tag);
      managed[tf]=true; managed_ticket[tf]=0; managed_dir[tf]=dir; managed_entry[tf]=entry;
      managed_entry_time[tf]=(datetime)(tick.time_msc/1000);
      return true;
   }

   sl=NormalizeDouble(sl,_Digits);
   bool ok=(dir==+1 ? trade.Buy(Lots,_Symbol,0.0,sl,0.0,"MA120_"+tag)
                    : trade.Sell(Lots,_Symbol,0.0,sl,0.0,"MA120_"+tag));
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
   Log("ENTRY_OK",(dir==1?"BUY":"SELL")+string(" entry=")+DoubleToString(managed_entry[tf],_Digits)+
       " R="+DoubleToString(R,_Digits)+" SL="+DoubleToString(sl,_Digits)+" | "+tag);
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
   managed[tf]=false; managed_ticket[tf]=0; managed_dir[tf]=0; managed_entry[tf]=0;
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

      if(setups[i].phase==PHASE_WAIT_MA120)
      {
         bool touchedMA=(dir==+1 ? tick.bid<=cur_ma_long[tf] : tick.ask>=cur_ma_long[tf]);
         if(!touchedMA) continue;
         setups[i].phase=PHASE_WAIT_BB;
         Log("MA120_ARMED",TS(setups[i].signal_time)+" tf="+EnumToString(ENTRY_TFS[tf])+
             " | now watching for BB touch");
         // fall through: price may have already reached the band on this very same tick
      }

      // PHASE_WAIT_BB. Check the wider BB4 first: if it's touched, BB20 (narrower) is
      // necessarily touched too, so checking BB4 first correctly labels the rarer
      // "price skipped straight past BB20" case instead of always reporting BB20.
      bool touchedBB4=(dir==+1 ? tick.bid<=cur_e_l4[tf] : tick.ask>=cur_e_u4[tf]);
      bool touchedBB20=(dir==+1 ? tick.bid<=cur_e_l20[tf] : tick.ask>=cur_e_u20[tf]);
      if(touchedBB4 || touchedBB20)
      {
         string bandLabel=touchedBB4?"BB4":"BB20";
         Log("BB_TOUCH",TS(setups[i].signal_time)+" tf="+EnumToString(ENTRY_TFS[tf])+" band="+bandLabel);
         if(OpenAtBB(dir,tf,cur_ma_long[tf],bandLabel,setups[i].expire_time,tick)) RemoveSetup(i);
      }
   }
}

//--- Manage every open position: TP at MA_Short, timeout, all evaluated per-timeframe.
//    SL is the broker-side 2R stop placed at entry -- no EA-side SL logic needed here.
void ManageOpenPositions(MqlTick &tick)
{
   datetime now=(datetime)(tick.time_msc/1000);
   for(int tf=0;tf<N_TF;tf++)
   {
      if(!managed[tf]) continue;
      if(EnableLiveOrders)
      {
         ulong t; if(!OwnPosition(tf,t)){ managed[tf]=false; managed_ticket[tf]=0; managed_dir[tf]=0; continue; } // closed by broker (SL hit, rare TIMEOUT, etc.)
      }

      if(now>managed_entry_time[tf]+MaxPositionHours*3600) { ClosePosition(tf,"TIMEOUT"); continue; }

      double px=(managed_dir[tf]==+1?tick.bid:tick.ask);
      bool tp_hit=(managed_dir[tf]==+1 ? px>=cur_ma_short[tf] : px<=cur_ma_short[tf]);
      if(tp_hit){ ClosePosition(tf,"TP_MA_SHORT"); continue; }
   }
}

void OnNewEntryBars()
{
   for(int k=0;k<N_TF;k++)
   {
      datetime t=iTime(_Symbol,ENTRY_TFS[k],0);
      if(t==0 || t==last_e_bar[k]) continue;
      last_e_bar[k]=t;
      RefreshEntryLevels(k);
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
   }

   Log("START","BUILD=v5_band_tagged | EntryTFs=M1+M2+M3 (all independent) | MA_Long="+IntegerToString(MA_Long)+
       " | MA_Short="+IntegerToString(MA_Short)+" | StopLoss_R="+DoubleToString(StopLoss_R,2)+
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
