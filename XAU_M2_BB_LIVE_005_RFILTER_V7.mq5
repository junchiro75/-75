//+------------------------------------------------------------------+
//| XAU_M2_BB_LIVE_005_RFILTER_V7.mq5                                |
//| V7: added TimeCutoffMin -- if TP1_R has NOT been reached within   |
//| this many minutes of entry, force-close the position at market    |
//| instead of waiting for the original SL/TP2. Data-motivated: an    |
//| analysis of live-config trades showed that trades which eventually|
//| hit the original SL take noticeably longer to resolve than trades |
//| that reach the protect-lock or full TP (median 6.3min vs 1.75min/ |
//| 1.1min; at the 30-min mark, 17.5% of eventual-SL trades are still |
//| open vs only 4.5%/3.9% of LOCK/TP trades) -- i.e. "if it hasn't    |
//| moved favorably soon, it's more likely a loser." This tests        |
//| whether force-closing those slow, still-unprofitable trades early |
//| (before the loss grows to the full -InitialSL_R*R) beats letting  |
//| them ride to the original SL, net of the cost of also cutting     |
//| short some slower-developing winners. 0 = disabled, reproduces    |
//| V6 exactly.                                                        |
//| ---- inherited from 005_RFILTER_V6.mq5 ----                       |
//| V6: added MaxSL_Points -- caps the INITIAL SL distance in         |
//| absolute points, but ONLY for the rare large-R signals where      |
//| InitialSL_R*R would otherwise exceed it. Normal-R trades (the     |
//| vast majority) are completely unaffected -- this does NOT shrink  |
//| SL uniformly (already shown to hurt: SL=1.0-3.5 all worse than    |
//| SL=4.0 in the earlier sweep). It only clips the tail: on an       |
//| unusually large signal candle (R far above typical), the SL       |
//| distance is capped at MaxSL_Points instead of scaling all the way |
//| up with R. TP1_R/Lock_R/TP2_R stay computed from the FULL         |
//| (uncapped) R, unaffected. 0 = no cap (reproduces V5 exactly).     |
//| ---- inherited from 005_RFILTER_V5.mq5 ----                       |
//| V5: added TightenSLOnTP1/TightenedSL_R -- an alternative to the   |
//| existing Lock_R protect mechanism. When TightenSLOnTP1=true and   |
//| price reaches TP1_R, instead of moving SL to the near-breakeven   |
//| Lock_R level, the SL is TIGHTENED from InitialSL_R*R down to      |
//| TightenedSL_R*R (e.g. 4.0R -> 2.0R) -- still a real, meaningfully |
//| wide stop, not a near-breakeven lock. TP2_R stays the exit target |
//| either way (unaffected). Mutually exclusive with the old Lock_R   |
//| behavior in practice (set TightenSLOnTP1=true to use this one     |
//| instead). Default false reproduces V4 exactly.                    |
//| ---- inherited from 005_RFILTER_V4.mq5 ----                       |
//| V4: added SimpleTP_NoProtect -- when true, the protect-lock       |
//| mechanism (TP1_R trigger -> move SL to Lock_R) is REMOVED          |
//| entirely, and the position's single TP is placed at TP1_R (0.5R   |
//| by default) instead of TP2_R -- i.e. take FULL profit the moment  |
//| price reaches TP1_R, no partial/lock/ride-further logic at all.   |
//| SL is unaffected by this flag (still InitialSL_R*R, or the V3     |
//| fixed-point option if UseFixedSL=true) -- built to answer whether  |
//| the current protect-lock mechanism (which caps most winners at    |
//| just +0.25R once triggered) actually costs more than it's worth,  |
//| compared to just taking the full +0.5R and moving on. Default     |
//| false reproduces V3 exactly.                                       |
//| ---- inherited from 005_RFILTER_V3.mq5 ----                       |
//| V3: added UseFixedSL/FixedSL_Points -- when UseFixedSL=true, the  |
//| initial SL is a FIXED point distance (entry -+ FixedSL_Points*   |
//| _Point) instead of the usual R-multiple (entry -+ InitialSL_R*R). |
//| TP1_R/Lock_R/TP2_R protect-lock logic is UNCHANGED and still R-   |
//| based (R reconstruction in FindOurPosition prefers TP2, which is  |
//| still R-based either way, so the protect mechanism keeps working  |
//| correctly regardless of how the initial SL was set). Built to     |
//| compare "wide R-multiple stop" (current live: InitialSL_R=4.0)    |
//| against "fixed point stop" (e.g. 15/20/25 points on gold) head-   |
//| to-head on the SAME signal set. Default false reproduces V2       |
//| exactly.                                                           |
//| ---- inherited from 005_RFILTER_V2.mq5 ----                       |
//| V2: added LatestSignalOnly -- when true, a new BB-breakout signal |
//| candle discards ANY still-pending earlier setup(s) instead of     |
//| letting them keep waiting alongside it. Default false reproduces  |
//| V1 exactly (multiple concurrent pending setups allowed).          |
//| ---- inherited from 005_RFILTER_V1.mq5 ----                       |
//| R-filter variant of 005_BUYONLY, built for symbols (e.g. NAS100+) |
//| where the unfiltered signal has a losing edge (gross PF<1) but a  |
//| large right-skewed R distribution -- same idea that turned MA120  |
//| V12 from PF 0.88 to PF 1.18 on NAS100 by keeping only the biggest  |
//| R (=M2 signal candle body) setups. Adds MinR_Points: skip signals  |
//| whose R is below this threshold. MinR_Points=0 reproduces          |
//| 005_BUYONLY exactly.                                                |
//| ---- inherited from 005_FINAL_BUYONLY.mq5 ----                     |
//| BUY-ONLY variant of 005 (AllowShort=false by default).          |
//| Real MT5 tick backtest (2025.01-2026.09): SELL trades alone were |
//| net -$540.86 vs BUY alone net +$1,697.03. Disabling SELL turns   |
//| the EA's 21-month result from +$1,156.17 to +$1,697.03. Re-enable|
//| SELL via the AllowShort input if you want the original behavior. |
//| M2 Dual-BB -> +0.95R extension -> 0.10R pullback -> countertrend |
//| LIVE FORWARD TEST EA | own-Magic MAX1                             |
//| NOTE: at 0.01 lot, 30% partial close is impossible on 0.01 step.  |
//| At TP1 this EA moves the whole position SL to +0.25R.             |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input double Lots                 = 0.01;
input double ExtensionR           = 0.95;
input double PullbackR            = 0.10;
input double InitialSL_R          = 2.00;
input double TP1_R                = 0.50;
input double Lock_R               = 0.25;
input double TP2_R                = 0.90;
input double MinR_Points          = 0;    // skip signal if R (=|close-open| of the M2 signal candle, in
                                           // points) is below this. 0 = no filter (identical to BUYONLY).
input bool   LatestSignalOnly     = false; // true = a new BB-breakout signal candle discards any earlier
                                            // still-pending setup(s); only the most recent signal is ever
                                            // watched. false = old behavior (multiple pending setups allowed).
input bool   UseFixedSL           = false; // true = initial SL is a FIXED point distance (FixedSL_Points)
                                            // instead of InitialSL_R*R. TP1/Lock/TP2 stay R-based either way.
input double FixedSL_Points       = 20;    // only used if UseFixedSL=true, e.g. 15/20/25 points on gold.
input bool   SimpleTP_NoProtect   = false; // true = remove the protect-lock mechanism entirely; single TP
                                            // placed at TP1_R (full exit there, no partial/ride-further).
input bool   TightenSLOnTP1       = false; // true = once TP1_R is reached, TIGHTEN the SL from InitialSL_R*R
                                            // down to TightenedSL_R*R instead of moving it to Lock_R. TP2_R
                                            // stays the exit target either way. Ignored if SimpleTP_NoProtect
                                            // is also true (no position management happens in that mode).
input double TightenedSL_R        = 2.0;   // only used if TightenSLOnTP1=true, e.g. 4.0R -> 2.0R on TP1 touch.
input double MaxSL_Points         = 0;     // caps InitialSL_R*R's distance at this many points on unusually
                                            // large-R signals only. 0 = no cap. E.g. 3000 = $30 max initial
                                            // risk on gold, regardless of how large R is.
input double TimeCutoffMin        = 0;     // if TP1_R not reached within this many minutes of entry, force-
                                            // close at market. 0 = disabled (no time cutoff).
input int    MaxExtensionHours    = 72;
input int    MaxPullbackHours     = 72;
input int    MaxVirtualExitHours  = 168;
input ulong  MagicNumber          = 95012101; // distinct from original 005 (95012001) so both can run side by side
input int    MaxDeviationPts      = 50;
input bool   EnableLiveOrders     = false; // SAFETY: set true only after checks
input bool   AllowShort           = false; // Ground-truth MT5 tick backtest (2025.01-2026.09) showed
                                            // SELL entries net -$540.86 vs BUY entries net +$1,697.03 --
                                            // in a secular gold uptrend, fading rallies (SELL) loses to
                                            // fading dips (BUY). Default false: BUY-only.

int hBB20=INVALID_HANDLE,hBB4=INVALID_HANDLE;
datetime last_m2_bar=0;
int f_log=INVALID_HANDLE;

struct Setup {
   datetime signal_time,close_time,extension_time;
   int sigdir;              // +1 bull signal, -1 bear signal
   double R,close_price,target,extreme;
   bool extension_hit;
};
Setup setups[];

bool managed=false;
ulong managed_ticket=0;
int managed_dir=0;          // +1 BUY, -1 SELL
double managed_R=0,managed_entry=0,managed_sl=0,managed_tp1=0,managed_lock=0,managed_tp2=0;
datetime managed_entry_time=0;
bool tp1_reached=false;

// DRY/tester virtual position: reproduces research MAX1 without sending orders.
bool v_open=false,v_tp1=false;
int v_dir=0;
double v_R=0,v_entry=0,v_sl=0,v_tp1px=0,v_lock=0,v_tp2=0;
datetime v_entry_time=0;
int v_entries=0,v_sl_n=0,v_lock_n=0,v_tp_n=0,v_timeout_n=0;
double v_totalR=0;

string TS(datetime t){ return TimeToString(t,TIME_DATE|TIME_MINUTES|TIME_SECONDS); }

void Log(string event,string detail="")
{
   Print("LIVE005 RFILTER2 M2 | ",event," | ",detail);
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

bool HasOurPosition()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);
      if(tk==0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      return true;
   }
   return false;
}

bool FindOurPosition()
{
   managed=false; managed_ticket=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);
      if(tk==0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;

      managed=true; managed_ticket=tk;
      managed_entry=PositionGetDouble(POSITION_PRICE_OPEN);
      managed_entry_time=(datetime)PositionGetInteger(POSITION_TIME);
      managed_sl=PositionGetDouble(POSITION_SL);
      managed_tp2=PositionGetDouble(POSITION_TP);
      long type=PositionGetInteger(POSITION_TYPE);
      managed_dir=(type==POSITION_TYPE_BUY ? +1 : -1);

      if(managed_tp2>0) managed_R=MathAbs(managed_tp2-managed_entry)/TP2_R;
      else if(managed_sl>0) managed_R=MathAbs(managed_sl-managed_entry)/InitialSL_R;
      else managed_R=0;

      if(managed_R>0)
      {
         managed_tp1=managed_entry+managed_dir*TP1_R*managed_R;
         managed_lock=managed_entry+managed_dir*Lock_R*managed_R;
         // If the current SL is already at/through the intended lock, preserve state after restart.
         double eps=2*_Point;
         tp1_reached=(managed_dir==+1 ? managed_sl>=managed_lock-eps
                                     : managed_sl<=managed_lock+eps && managed_sl>0);
      }
      return true;
   }
   tp1_reached=false;
   return false;
}

bool SafeModifyPosition(ulong ticket,int dir,double desired_sl,double desired_tp,string context)
{
   MqlTick q; if(!SymbolInfoTick(_Symbol,q)){ Log(context+"_FAIL","no tick"); return false; }
   double cushion=MinStopDistance()+_Point;
   double sl=desired_sl,tp=desired_tp;

   if(dir==+1) // BUY: SL below Bid, TP above Bid
   {
      if(sl>0 && sl>q.bid-cushion) sl=q.bid-cushion;
      if(tp>0 && tp<q.bid+cushion) tp=q.bid+cushion;
   }
   else // SELL: SL above Ask, TP below Ask
   {
      if(sl>0 && sl<q.ask+cushion) sl=q.ask+cushion;
      if(tp>0 && tp>q.ask-cushion) tp=q.ask-cushion;
   }

   sl=(sl>0?NormalizeDouble(sl,_Digits):0.0);
   tp=(tp>0?NormalizeDouble(tp,_Digits):0.0);
   if(trade.PositionModify(ticket,sl,tp)) return true;

   Log(context+"_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+
       trade.ResultRetcodeDescription()+" | bid="+DoubleToString(q.bid,_Digits)+
       " ask="+DoubleToString(q.ask,_Digits)+" sl="+DoubleToString(sl,_Digits)+
       " tp="+DoubleToString(tp,_Digits));
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

bool OpenCountertrend(Setup &s,MqlTick &tick)
{
   // Research-style MAX1 is ONLY for LIVE_005's own strategy.
   if(EnableLiveOrders)
   {
      if(HasOurPosition()){ Log("ENTRY_SKIPPED","LIVE005 own-Magic position already exists"); return false; }
   }
   else
   {
      if(v_open){ Log("VIRTUAL_SKIPPED","virtual MAX1 occupied"); return false; }
   }

   int dir=-s.sigdir; // bull signal -> SELL, bear signal -> BUY
   if(dir==-1 && !AllowShort)
   {
      Log("ENTRY_SKIPPED","SELL disabled by AllowShort=false (data-driven direction filter)");
      return false;
   }
   if(!EnableLiveOrders)
   {
      v_open=true; v_tp1=false; v_dir=dir; v_R=s.R;
      v_entry=(dir==+1 ? tick.ask : tick.bid);
      {
         double slDist=InitialSL_R*v_R;
         if(MaxSL_Points>0) slDist=MathMin(slDist,MaxSL_Points*_Point);
         v_sl=UseFixedSL ? (v_entry-dir*FixedSL_Points*_Point) : (v_entry-dir*slDist);
      }
      v_tp1px=v_entry+dir*TP1_R*v_R;
      v_lock=v_entry+dir*Lock_R*v_R;
      v_tp2=v_entry+dir*(SimpleTP_NoProtect?TP1_R:TP2_R)*v_R;
      v_entry_time=(datetime)(tick.time_msc/1000);
      v_entries++;
      Log("VIRTUAL_ACCEPT","#"+IntegerToString(v_entries)+" "+(dir==1?"BUY":"SELL")+
          " entry="+DoubleToString(v_entry,_Digits)+" R="+DoubleToString(v_R,_Digits));
      return true;
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(MaxDeviationPts);
   trade.SetTypeFillingBySymbol(_Symbol);

   MqlTick q; if(!SymbolInfoTick(_Symbol,q)){ Log("ORDER_FAIL","no current tick"); return false; }
   double ref=(dir==+1 ? q.ask : q.bid);
   double slDist=InitialSL_R*s.R;
   if(MaxSL_Points>0) slDist=MathMin(slDist,MaxSL_Points*_Point);
   double sl=UseFixedSL ? (ref-dir*FixedSL_Points*_Point) : (ref-dir*slDist);
   double tp=ref+dir*(SimpleTP_NoProtect?TP1_R:TP2_R)*s.R;

   // Make the initial protection broker-valid before the market order.
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

   bool ok=(dir==+1 ? trade.Buy(Lots,_Symbol,0.0,sl,tp,"LIVE005_M2")
                    : trade.Sell(Lots,_Symbol,0.0,sl,tp,"LIVE005_M2"));
   if(!ok)
   {
      Log("ORDER_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
      return false;
   }

   // Give the terminal a chance to expose the new position; later ticks will recover it if needed.
   if(FindOurPosition())
   {
      Log("ENTRY","ticket="+IntegerToString((int)managed_ticket)+" | "+(dir==1?"BUY":"SELL")+
          " | fill="+DoubleToString(managed_entry,_Digits)+" | R="+DoubleToString(managed_R,_Digits)+
          " | SL="+DoubleToString(managed_sl,_Digits)+" | TP2="+DoubleToString(managed_tp2,_Digits));
   }
   else
      Log("ORDER_SENT_NO_POSITION","retcode="+IntegerToString((int)trade.ResultRetcode()));
   return true;
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
         // Deliberately do NOT continue: trusted validator can evaluate pullback
         // in the same tick after extension state is established.
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
      OpenCountertrend(setups[i],tick);
      // Consume the setup whether live, dry, or MAX1-blocked: one opportunity, matching forward-test discipline.
      RemoveSetup(i);
   }
}

void CloseVirtual(string outcome,double outR,datetime now)
{
   v_totalR+=outR;
   if(outcome=="SL") v_sl_n++;
   else if(outcome=="LOCK") v_lock_n++;
   else if(outcome=="TP") v_tp_n++;
   else if(outcome=="TIMEOUT") v_timeout_n++;
   Log("VIRTUAL_EXIT_"+outcome,"R="+DoubleToString(outR,3)+" | totalR="+DoubleToString(v_totalR,3));
   v_open=false; v_tp1=false; v_dir=0; v_R=0; v_entry=0; v_entry_time=0;
}

void ManageVirtual(MqlTick &tick)
{
   if(EnableLiveOrders || !v_open) return;
   datetime now=(datetime)(tick.time_msc/1000);
   if(now<=v_entry_time) return;

   if(now>v_entry_time+MaxVirtualExitHours*3600)
   {
      // Validation FIX convention: free MAX1 slot, record TIMEOUT, fabricate no P/L.
      CloseVirtual("TIMEOUT",0.0,now);
      return;
   }

   // Executable close side: BUY closes at Bid, SELL closes at Ask.
   double px=(v_dir==+1 ? tick.bid : tick.ask);

   if(!v_tp1)
   {
      bool slhit=(v_dir==+1 ? px<=v_sl : px>=v_sl);
      if(slhit){ CloseVirtual("SL",-InitialSL_R,now); return; }

      bool tp1hit=(v_dir==+1 ? px>=v_tp1px : px<=v_tp1px);
      if(tp1hit)
      {
         v_tp1=true;
         Log("VIRTUAL_TP1","lock now active at "+DoubleToString(v_lock,_Digits));
      }
      return;
   }

   bool finalhit=(v_dir==+1 ? px>=v_tp2 : px<=v_tp2);
   if(finalhit){ CloseVirtual("TP",0.78,now); return; }

   bool lockhit=(v_dir==+1 ? px<=v_lock : px>=v_lock);
   if(lockhit){ CloseVirtual("LOCK",0.325,now); return; }
}

void ManagePosition(MqlTick &tick)
{
   if(SimpleTP_NoProtect) return; // no protect-lock mechanism: single TP at TP1_R handles the whole exit
   if(!FindOurPosition()) return;
   if(tp1_reached || managed_R<=0) return;

   double px=(managed_dir==+1 ? tick.bid : tick.ask); // executable close side
   bool hit=(managed_dir==+1 ? px>=managed_tp1 : px<=managed_tp1);
   if(!hit) return;

   double newSL=TightenSLOnTP1 ? (managed_entry-managed_dir*TightenedSL_R*managed_R) : managed_lock;

   if(!EnableLiveOrders)
   {
      tp1_reached=true;
      Log("DRY_TP1","would "+(TightenSLOnTP1?"tighten SL to "+DoubleToString(TightenedSL_R,2)+"R":"move whole-position SL to +0.25R"));
      return;
   }

   trade.SetExpertMagicNumber(MagicNumber);
   if(SafeModifyPosition(managed_ticket,managed_dir,newSL,managed_tp2,TightenSLOnTP1?"TIGHTEN_MODIFY":"LOCK_MODIFY"))
   {
      tp1_reached=true;
      Log(TightenSLOnTP1?"TP1_TIGHTEN":"TP1_LOCK","TP1 reached; whole SL moved to "+DoubleToString(newSL,_Digits));
   }
   // If temporarily invalid because price is too close, retry on later ticks.
}

// Force-close if TP1_R hasn't been reached within TimeCutoffMin of entry. Self-contained (re-fetches
// position state) so it works regardless of SimpleTP_NoProtect (which skips ManagePosition entirely).
void CheckTimeCutoff(MqlTick &tick)
{
   if(TimeCutoffMin<=0) return;
   if(!FindOurPosition()) return;
   if(tp1_reached || managed_R<=0 || managed_entry_time<=0) return;

   datetime now=(datetime)(tick.time_msc/1000);
   if(now<managed_entry_time+(datetime)(TimeCutoffMin*60)) return;

   if(!EnableLiveOrders)
   {
      Log("DRY_TIME_CUTOFF","would force-close, TP1 not reached within "+DoubleToString(TimeCutoffMin,1)+"min");
      return;
   }

   trade.SetExpertMagicNumber(MagicNumber);
   if(trade.PositionClose(managed_ticket))
      Log("TIME_CUTOFF_CLOSE","forced close after "+DoubleToString(TimeCutoffMin,1)+"min without reaching TP1");
   else
      Log("TIME_CUTOFF_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
}

int OnInit()
{
   hBB20=iBands(_Symbol,PERIOD_M2,20,0,2.0,PRICE_CLOSE);
   hBB4 =iBands(_Symbol,PERIOD_M2,4,0,4.0,PRICE_OPEN);
   if(hBB20==INVALID_HANDLE || hBB4==INVALID_HANDLE) return INIT_FAILED;

   f_log=FileOpen("XAU_M2_LIVE_005_RFILTER2_LOG.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
   if(f_log!=INVALID_HANDLE)
   {
      FileSeek(f_log,0,SEEK_END);
      if(FileTell(f_log)==0) FileWrite(f_log,"TIME","EVENT","DETAIL");
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(MaxDeviationPts);
   trade.SetTypeFillingBySymbol(_Symbol);
   FindOurPosition();

   Log("START",string("TF=M2 | PB=0.10R | SL=2R | own-Magic MAX1 | Magic=")+
       IntegerToString((int)MagicNumber)+" | Lots="+DoubleToString(Lots,2)+
       " | LatestSignalOnly="+(LatestSignalOnly?"true":"false")+
       " | AllowShort="+(AllowShort?"true":"false")+" | MinR_Points="+DoubleToString(MinR_Points,1)+
       " | UseFixedSL="+(UseFixedSL?"true":"false")+" | FixedSL_Points="+DoubleToString(FixedSL_Points,1)+
       " | SimpleTP_NoProtect="+(SimpleTP_NoProtect?"true":"false")+
       " | TightenSLOnTP1="+(TightenSLOnTP1?"true":"false")+" | TightenedSL_R="+DoubleToString(TightenedSL_R,2)+
       " | MaxSL_Points="+DoubleToString(MaxSL_Points,1)+" | TimeCutoffMin="+DoubleToString(TimeCutoffMin,1)+
       " | orders="+(EnableLiveOrders?"ENABLED":"DRY"));
   Log("NOTE","RFILTER7 build: RFILTER6 + TimeCutoffMin (force-close if TP1_R not reached within N minutes)");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(!EnableLiveOrders)
      Log("VIRTUAL_SUMMARY","entries="+IntegerToString(v_entries)+" SL="+IntegerToString(v_sl_n)+
          " LOCK="+IntegerToString(v_lock_n)+" TP="+IntegerToString(v_tp_n)+
          " TIMEOUT="+IntegerToString(v_timeout_n)+" totalR="+DoubleToString(v_totalR,3)+
          " open="+(v_open?"1":"0"));
   if(f_log!=INVALID_HANDLE){ FileFlush(f_log); FileClose(f_log); }
   if(hBB20!=INVALID_HANDLE) IndicatorRelease(hBB20);
   if(hBB4!=INVALID_HANDLE) IndicatorRelease(hBB4);
}

void OnTick()
{
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;
   CheckNewM2Bar();
   CheckSetups(tick);
   ManageVirtual(tick);
   ManagePosition(tick);
   CheckTimeCutoff(tick);
}
//+------------------------------------------------------------------+
