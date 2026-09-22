//+------------------------------------------------------------------+
//| XAU_M2_BB_LIVE_005_DUALPROTECT_TEST.mq5                          |
//| A/B protect-SL comparison test, built on top of RFILTER_V2's     |
//| live-config signal logic (LatestSignalOnly + MinR_Points).       |
//| Every confirmed pullback entry opens TWO simultaneous positions  |
//| under DIFFERENT magic numbers, same direction/SL/TP2 at open:    |
//|   Position A (MagicNumber_A) -- KEEPS existing behavior: once    |
//|     price reaches TP1_R, whole-position SL is moved to Lock_R.   |
//|   Position B (MagicNumber_B) -- protect-SL logic REMOVED: rides  |
//|     the original SL/TP2 bracket set at entry, untouched.         |
//| No new dual-entry signal is taken until BOTH A and B are flat,   |
//| so each pair shares the identical entry -- only the exit rule    |
//| differs. MT5's own report separates A vs B by magic number in    |
//| the deals/orders comment ("DUAL_A_PROTECT" / "DUAL_B_NOPROTECT") |
//| for post-hoc parsing.                                            |
//| Tester-only: EnableLiveOrders must be true (no DRY/virtual path).|
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input double LotsA                = 0.10;    // Position A: keeps protect-SL (TP1_R -> Lock_R)
input double LotsB                = 0.10;    // Position B: NO protect-SL, rides original SL/TP2 only
input double ExtensionR           = 0.95;
input double PullbackR            = 0.10;
input double InitialSL_R          = 4.00;    // matches current live 005 config
input double TP1_R                = 0.50;
input double Lock_R               = 0.25;
input double TP2_R                = 0.90;
input double MinR_Points          = 0;       // 0 = matches current live 005 config
input bool   LatestSignalOnly     = true;    // matches current live 005 config
input int    MaxExtensionHours    = 72;
input int    MaxPullbackHours     = 72;
input ulong  MagicNumber_A        = 95012101; // same magic as live 005 (protect side)
input ulong  MagicNumber_B        = 95012199; // distinct magic (no-protect side)
input int    MaxDeviationPts      = 50;
input bool   EnableLiveOrders     = true;     // this test variant only supports the real-order path
input bool   AllowShort           = false;

int hBB20=INVALID_HANDLE,hBB4=INVALID_HANDLE;
datetime last_m2_bar=0;
int f_log=INVALID_HANDLE;

struct Setup {
   datetime signal_time,close_time,extension_time;
   int sigdir;
   double R,close_price,target,extreme;
   bool extension_hit;
};
Setup setups[];

struct ManagedPos {
   bool   found;
   ulong  ticket;
   int    dir;
   double R,entry,sl,tp1,lock,tp2;
   bool   tp1_reached;
};

string TS(datetime t){ return TimeToString(t,TIME_DATE|TIME_MINUTES|TIME_SECONDS); }

void Log(string event,string detail="")
{
   Print("LIVE005 DUALTEST M2 | ",event," | ",detail);
   if(f_log!=INVALID_HANDLE){ FileWrite(f_log,TS(TimeCurrent()),event,detail); FileFlush(f_log); }
}

void RemoveSetup(int idx)
{
   int n=ArraySize(setups);
   for(int j=idx;j<n-1;j++) setups[j]=setups[j+1];
   ArrayResize(setups,n-1);
}

double MinStopDistance()
{
   long stops=0,freeze=0;
   SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL,stops);
   SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL,freeze);
   return (double)MathMax(stops,freeze)*_Point;
}

bool HasPosition(ulong magic)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);
      if(tk==0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=magic) continue;
      return true;
   }
   return false;
}

bool AnySlotOccupied(){ return HasPosition(MagicNumber_A) || HasPosition(MagicNumber_B); }

bool FindPosition(ulong magic,ManagedPos &mp)
{
   mp.found=false; mp.ticket=0; mp.tp1_reached=false;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);
      if(tk==0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=magic) continue;

      mp.found=true; mp.ticket=tk;
      mp.entry=PositionGetDouble(POSITION_PRICE_OPEN);
      mp.sl=PositionGetDouble(POSITION_SL);
      mp.tp2=PositionGetDouble(POSITION_TP);
      long type=PositionGetInteger(POSITION_TYPE);
      mp.dir=(type==POSITION_TYPE_BUY ? +1 : -1);

      if(mp.tp2>0) mp.R=MathAbs(mp.tp2-mp.entry)/TP2_R;
      else if(mp.sl>0) mp.R=MathAbs(mp.sl-mp.entry)/InitialSL_R;
      else mp.R=0;

      if(mp.R>0)
      {
         mp.tp1=mp.entry+mp.dir*TP1_R*mp.R;
         mp.lock=mp.entry+mp.dir*Lock_R*mp.R;
         double eps=2*_Point;
         mp.tp1_reached=(mp.dir==+1 ? mp.sl>=mp.lock-eps
                                    : mp.sl<=mp.lock+eps && mp.sl>0);
      }
      return true;
   }
   return false;
}

bool SafeModifyPosition(ulong ticket,int dir,double desired_sl,double desired_tp,string context)
{
   MqlTick q; if(!SymbolInfoTick(_Symbol,q)){ Log(context+"_FAIL","no tick"); return false; }
   double cushion=MinStopDistance()+_Point;
   double sl=desired_sl,tp=desired_tp;

   if(dir==+1)
   {
      if(sl>0 && sl>q.bid-cushion) sl=q.bid-cushion;
      if(tp>0 && tp<q.bid+cushion) tp=q.bid+cushion;
   }
   else
   {
      if(sl>0 && sl<q.ask+cushion) sl=q.ask+cushion;
      if(tp>0 && tp>q.ask-cushion) tp=q.ask-cushion;
   }

   sl=(sl>0?NormalizeDouble(sl,_Digits):0.0);
   tp=(tp>0?NormalizeDouble(tp,_Digits):0.0);
   if(trade.PositionModify(ticket,sl,tp)) return true;

   Log(context+"_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+
       trade.ResultRetcodeDescription());
   return false;
}

void AddSignal(datetime sig,datetime close_time,int dir,double R,double c)
{
   if(LatestSignalOnly && ArraySize(setups)>0)
   {
      Log("SIGNAL_SUPERSEDES","dropping "+IntegerToString(ArraySize(setups))+" pending setup(s) for newer signal");
      ArrayResize(setups,0);
   }
   int n=ArraySize(setups); ArrayResize(setups,n+1);
   setups[n].signal_time=sig;
   setups[n].close_time=close_time;
   setups[n].extension_time=0;
   setups[n].sigdir=dir;
   setups[n].R=R;
   setups[n].close_price=c;
   setups[n].target=c+dir*ExtensionR*R;
   setups[n].extreme=c;
   setups[n].extension_hit=false;
   Log("SIGNAL",(dir==1?"BULL":"BEAR")+" R="+DoubleToString(R,_Digits)+
       " ext="+DoubleToString(setups[n].target,_Digits));
}

void CheckNewM2Bar()
{
   datetime t=iTime(_Symbol,PERIOD_M2,0);
   if(t==0 || t==last_m2_bar) return;
   last_m2_bar=t;

   double o=iOpen(_Symbol,PERIOD_M2,1),h=iHigh(_Symbol,PERIOD_M2,1);
   double l=iLow(_Symbol,PERIOD_M2,1),c=iClose(_Symbol,PERIOD_M2,1);
   datetime sig=iTime(_Symbol,PERIOD_M2,1);
   if(sig==0) return;

   double up20[1],lo20[1],up4[1],lo4[1];
   if(CopyBuffer(hBB20,1,1,1,up20)!=1 || CopyBuffer(hBB20,2,1,1,lo20)!=1 ||
      CopyBuffer(hBB4,1,1,1,up4)!=1   || CopyBuffer(hBB4,2,1,1,lo4)!=1) return;

   int dir=0;
   if(c>o && h>=up20[0] && h>=up4[0]) dir=+1;
   else if(c<o && l<=lo20[0] && l<=lo4[0]) dir=-1;
   if(dir==0) return;

   double R=MathAbs(c-o);
   double minR=MathMax(_Point,MinR_Points*_Point);
   if(R<=minR) return;
   AddSignal(sig,t,dir,R,c);
}

void OpenDualEntry(Setup &s,MqlTick &tick)
{
   if(!EnableLiveOrders){ Log("ENTRY_SKIPPED","EnableLiveOrders=false -- this test variant requires real orders"); return; }
   if(AnySlotOccupied()){ Log("ENTRY_SKIPPED","dual-slot occupied (A and/or B still open)"); return; }

   int dir=-s.sigdir; // bull signal -> SELL, bear signal -> BUY
   if(dir==-1 && !AllowShort)
   {
      Log("ENTRY_SKIPPED","SELL disabled by AllowShort=false");
      return;
   }

   MqlTick q; if(!SymbolInfoTick(_Symbol,q)){ Log("ORDER_FAIL","no current tick"); return; }
   double ref=(dir==+1 ? q.ask : q.bid);
   double sl=ref-dir*InitialSL_R*s.R;
   double tp=ref+dir*TP2_R*s.R;

   double cushion=MinStopDistance()+_Point;
   if(dir==+1)
   {
      if(sl>q.bid-cushion) sl=q.bid-cushion;
      if(tp<q.ask+cushion) tp=q.ask+cushion;
   }
   else
   {
      if(sl<q.ask+cushion) sl=q.ask+cushion;
      if(tp>q.bid-cushion) tp=q.bid-cushion;
   }
   sl=NormalizeDouble(sl,_Digits); tp=NormalizeDouble(tp,_Digits);

   trade.SetExpertMagicNumber(MagicNumber_A);
   trade.SetDeviationInPoints(MaxDeviationPts);
   trade.SetTypeFillingBySymbol(_Symbol);
   bool okA=(dir==+1 ? trade.Buy(LotsA,_Symbol,0.0,sl,tp,"DUAL_A_PROTECT")
                     : trade.Sell(LotsA,_Symbol,0.0,sl,tp,"DUAL_A_PROTECT"));
   if(!okA) Log("ORDER_FAIL_A",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
   else     Log("ENTRY_A",(dir==1?"BUY":"SELL")+" | sl="+DoubleToString(sl,_Digits)+" | tp2="+DoubleToString(tp,_Digits));

   trade.SetExpertMagicNumber(MagicNumber_B);
   bool okB=(dir==+1 ? trade.Buy(LotsB,_Symbol,0.0,sl,tp,"DUAL_B_NOPROTECT")
                     : trade.Sell(LotsB,_Symbol,0.0,sl,tp,"DUAL_B_NOPROTECT"));
   if(!okB) Log("ORDER_FAIL_B",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
   else     Log("ENTRY_B",(dir==1?"BUY":"SELL")+" | sl="+DoubleToString(sl,_Digits)+" | tp2="+DoubleToString(tp,_Digits)+" | NO protect-SL will be applied");
}

void CheckSetups(MqlTick &tick)
{
   datetime now=(datetime)(tick.time_msc/1000);

   for(int i=ArraySize(setups)-1;i>=0;i--)
   {
      if(now<setups[i].close_time) continue;

      if(!setups[i].extension_hit)
      {
         if(now>setups[i].close_time+MaxExtensionHours*3600)
         { Log("EXT_EXPIRE",TS(setups[i].signal_time)); RemoveSetup(i); continue; }

         double px=(setups[i].sigdir==+1 ? tick.bid : tick.ask);
         bool hit=(setups[i].sigdir==+1 ? px>=setups[i].target : px<=setups[i].target);
         if(!hit) continue;

         setups[i].extension_hit=true;
         setups[i].extension_time=now;
         setups[i].extreme=px;
         Log("EXT_HIT",TS(setups[i].signal_time)+" extreme="+DoubleToString(px,_Digits));
      }

      if(now>setups[i].extension_time+MaxPullbackHours*3600)
      { Log("PB_EXPIRE",TS(setups[i].signal_time)); RemoveSetup(i); continue; }

      double px=(setups[i].sigdir==+1 ? tick.bid : tick.ask);
      if(setups[i].sigdir==+1)
      {
         if(px>setups[i].extreme) setups[i].extreme=px;
         double trigger=setups[i].extreme-PullbackR*setups[i].R;
         if(px>trigger) continue;
      }
      else
      {
         if(px<setups[i].extreme) setups[i].extreme=px;
         double trigger=setups[i].extreme+PullbackR*setups[i].R;
         if(px<trigger) continue;
      }

      Log("PB_CONFIRM",TS(setups[i].signal_time)+" R="+DoubleToString(setups[i].R,_Digits));
      OpenDualEntry(setups[i],tick);
      RemoveSetup(i);
   }
}

// Position A only: once TP1_R is reached, move whole-position SL to Lock_R (existing live behavior).
void ManageProtectA(MqlTick &tick)
{
   ManagedPos mp;
   if(!FindPosition(MagicNumber_A,mp)) return;
   if(mp.tp1_reached || mp.R<=0) return;

   double px=(mp.dir==+1 ? tick.bid : tick.ask);
   bool hit=(mp.dir==+1 ? px>=mp.tp1 : px<=mp.tp1);
   if(!hit) return;

   trade.SetExpertMagicNumber(MagicNumber_A);
   if(SafeModifyPosition(mp.ticket,mp.dir,mp.lock,mp.tp2,"LOCK_MODIFY_A"))
      Log("TP1_LOCK_A","whole SL moved to "+DoubleToString(mp.lock,_Digits));
}
// Position B: deliberately NO management function -- rides original SL/TP2 bracket set at OpenDualEntry.

int OnInit()
{
   hBB20=iBands(_Symbol,PERIOD_M2,20,0,2.0,PRICE_CLOSE);
   hBB4 =iBands(_Symbol,PERIOD_M2,4,0,4.0,PRICE_OPEN);
   if(hBB20==INVALID_HANDLE || hBB4==INVALID_HANDLE) return INIT_FAILED;

   f_log=FileOpen("XAU_M2_LIVE_005_DUALTEST_LOG.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
   if(f_log!=INVALID_HANDLE)
   {
      FileSeek(f_log,0,SEEK_END);
      if(FileTell(f_log)==0) FileWrite(f_log,"TIME","EVENT","DETAIL");
   }

   trade.SetDeviationInPoints(MaxDeviationPts);
   trade.SetTypeFillingBySymbol(_Symbol);

   Log("START",string("A/B DUAL PROTECT-SL TEST | TF=M2 | LotsA=")+DoubleToString(LotsA,2)+
       " (MagicA="+IntegerToString((int)MagicNumber_A)+", protect-SL ON) | LotsB="+DoubleToString(LotsB,2)+
       " (MagicB="+IntegerToString((int)MagicNumber_B)+", protect-SL OFF) | InitialSL_R="+DoubleToString(InitialSL_R,2)+
       " | LatestSignalOnly="+(LatestSignalOnly?"true":"false")+" | MinR_Points="+DoubleToString(MinR_Points,1));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(f_log!=INVALID_HANDLE){ FileFlush(f_log); FileClose(f_log); }
   if(hBB20!=INVALID_HANDLE) IndicatorRelease(hBB20);
   if(hBB4!=INVALID_HANDLE) IndicatorRelease(hBB4);
}

void OnTick()
{
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;
   CheckNewM2Bar();
   CheckSetups(tick);
   ManageProtectA(tick);
}
//+------------------------------------------------------------------+
