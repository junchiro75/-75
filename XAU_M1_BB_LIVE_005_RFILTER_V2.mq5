//+------------------------------------------------------------------+
//| XAU_M1_BB_LIVE_005_RFILTER_V2.mq5                                |
//| M1 sibling of XAU_M2_BB_LIVE_005_RFILTER_V2.mq5 -- identical      |
//| engine, just Timeframe default=PERIOD_M1 and a distinct Magic     |
//| Number so it can run alongside the M2 version. Most ground-truth  |
//| numbers in the inherited header below are M2-specific and do not  |
//| automatically transfer.                                            |
//| 2026.10.15: ported M2's Protect-stop/TrailingStop/TrailingTP       |
//| feature set (this sibling had been stale since 2025.09.29 and      |
//| lacked it entirely -- only did a one-time TP1_R->Lock_R SL move     |
//| with no continuous trailing). Ported WITH both bug fixes M2 found   |
//| live (ticket #1227805316) already built in: per-ticket cached R     |
//| in FindOurPosition() (not recomputed every tick from current        |
//| SL/TP) and a stale-POSITION_SL-read guard in the trailing block.    |
//| New inputs default to M2's CONFIRMED values but are UNTESTED on     |
//| this timeframe -- see each input's own comment.                    |
//| MinR_Points (CONFIRMED on M1 =350, was inherited stale M2 value    |
//| 200): an MT5 Optimizer sweep (2025.01-2026.09, 150-600 step 25,    |
//| Recovery Factor objective) found a genuine plateau at 325-400 --   |
//| RF 7.37-7.58 there vs 5.12 at the inherited MinR_Points=200 -- with |
//| 350 the single best (RF 7.578, PF 1.510, NET $19,240.36, 1768      |
//| trades, DD 2.12%, vs 200's RF 5.117, PF 1.351, NET $20,468.58,     |
//| 3652 trades, DD 3.23%). Fewer trades and slightly lower NET, but    |
//| a clean quality improvement on RF/PF/DD, same pattern as the        |
//| 001_STOCH family's own per-timeframe MinR tuning.                   |
//| ---- inherited from XAU_M2_BB_LIVE_005_RFILTER_V2.mq5 ----        |
//| V2: added LatestSignalOnly -- when true, a new BB-breakout signal |
//| candle discards ANY still-pending earlier setup(s) instead of     |
//| letting them keep waiting alongside it. Default false reproduces  |
//| V1 exactly (multiple concurrent pending setups allowed).          |
//| CONFIRMED defaults on M2 (ground-truth MT5 tick backtest,         |
//| 2025.01-2026.09, M2, Lots=0.1): InitialSL_R=3.5 (was stale 2.0),  |
//| MinR_Points=200 (was stale 0), LatestSignalOnly=true -- NET       |
//| $28,172.55, PF 1.61, Recovery Factor 9.80, WR 90.46% (2664W/      |
//| 281L, 2945 trades, BUY-only), MaxDD 1.07%/2.72%. Avg win +$27.92  |
//| vs avg loss -$148.70 (wide-SL/narrow-lock asymmetry, offset by    |
//| the high win rate).                                                |
//| SkipEntryHourKST (CONFIRMED on M2, default=true here too pending  |
//| its own M1 backtest): a KST hour-of-day breakdown of the M2       |
//| confirmed-default backtest found 20-22 KST is the weakest of      |
//| twelve 2-hour buckets -- WR 86.3% (vs 90.46% overall) and lowest  |
//| $/trade (n=291, NET only $620.20). Blocks new entries while the   |
//| KST hour is in [SkipHourStartKST,SkipHourEndKST). Confirmed on M2 |
//| (2945->2657 trades, NET $28,172.55->$28,329.75, PF 1.610->1.709,  |
//| WR 90.46%->90.97%) but UNTESTED on M1 -- needs its own backtest.  |
//| ---- inherited from 005_RFILTER_V1.mq5 ----                       |
//| R-filter variant of 005_BUYONLY, built for symbols (e.g. NAS100+) |
//| where the unfiltered signal has a losing edge (gross PF<1) but a  |
//| large right-skewed R distribution -- same idea that turned MA120  |
//| V12 from PF 0.88 to PF 1.18 on NAS100 by keeping only the biggest  |
//| R (=signal candle body) setups. Adds MinR_Points: skip signals     |
//| whose R is below this threshold. MinR_Points=0 reproduces          |
//| 005_BUYONLY exactly.                                                |
//| ---- inherited from 005_FINAL_BUYONLY.mq5 ----                     |
//| BUY-ONLY variant of 005 (AllowShort=false by default). On M2, a   |
//| real MT5 tick backtest (2025.01-2026.09) found SELL trades alone  |
//| net -$540.86 vs BUY alone net +$1,697.03 -- UNTESTED whether the   |
//| same BUY-only bias holds on M1.                                    |
//| Dual-BB -> +0.95R extension -> 0.10R pullback -> countertrend      |
//| LIVE FORWARD TEST EA | own-Magic MAX1                              |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input ENUM_TIMEFRAMES Timeframe   = PERIOD_M1; // signal-candle timeframe
input double Lots                 = 0.1; // Lot size
input double ExtensionR           = 0.95; // Extension (R) before pullback watch starts
input double PullbackR            = 0.10; // Pullback (R) from extension extreme to trigger entry
input double InitialSL_R          = 3.5; // Initial stop loss (R) (CONFIRMED on M2, see header)
input double TP1_R                = 0.50; // Partial/lock trigger (R)
input double Lock_R               = 0.30; // Lock SL level (R) (CONFIRMED on M2, see header)
input double TP2_R                = 0.90; // Final target (R)
input double MinR_Points          = 350; // Min signal-candle body (points) to trade, 0=no filter (CONFIRMED on M1, see header)
input bool   LatestSignalOnly     = true; // New signal cancels older pending setups (CONFIRMED on M2, see header)
input int    MaxExtensionHours    = 72; // Max hours waiting for extension
input int    MaxPullbackHours     = 72; // Max hours waiting for pullback
input int    MaxVirtualExitHours  = 168; // Max hours holding a position
input ulong  MagicNumber          = 95012102; // Magic number
input int    MaxDeviationPts      = 50; // Max price deviation (points)
input bool   EnableLiveOrders     = false; // Enable live orders
input bool   AllowShort           = false; // Allow SELL entries (default BUY-only, see header)
input int    SkipHourStartKST     = 20; // KST hour skip window start (see header, SkipEntryHourKST)
input int    SkipHourEndKST       = 22; // KST hour skip window end, exclusive (see header, SkipEntryHourKST)
input bool   SkipEntryHourKST     = true; // Block entries in [SkipHourStartKST,SkipHourEndKST) KST (CONFIRMED on M2, see header)

input double ProtectTriggerR      = 0.25; // Favorable R to arm an early protect-lock stop, before TP1 (REJECTED on M2, UNTESTED here, see header)
input double ProtectR             = 0.05; // SL level once armed, in R (REJECTED on M2, UNTESTED here, see header)
input bool   UseProtectStop       = false; // Move SL to ProtectR once armed, before TP1/Lock fires (REJECTED on M2, UNTESTED here, see header)

input bool   UseTrailingStop      = false; // After TP1 reached, continuously trail SL instead of the one-time move to Lock_R (OFF on M2 in favor of UseTrailingTP, UNTESTED here, see header)
input double TrailStopDistanceR   = 0.04; // Distance maintained between price and the trailing SL after TP1, in R (CONFIRMED-but-unused on M2, UNTESTED here; only used when UseTrailingStop=true AND UseTrailingTP hasn't armed)
input bool   UseTrailingTP        = true; // After TP1 reached, remove the TP2 cap and trail SL instead of closing at TP2 (CONFIRMED on M2, UNTESTED here, see header)
input double TrailTPDistanceR     = 0.09; // Distance maintained between price and the trailing SL once TP2 cap removed, in R (CONFIRMED on M2, UNTESTED here; only used when UseTrailingTP=true)

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
bool tp1_reached=false;
bool protect_reached=false; // UseProtectStop: SL already moved to the early protect-lock level
double trail_stop_level=0;    // UseTrailingStop: current trailing SL level post-TP1 (0 = not yet moved)
bool   trail_tp_armed=false;  // UseTrailingTP: TP2 cap removed, now trailing via SL
double trail_tp_stop_level=0; // UseTrailingTP: current trailing SL level once armed (0 = not yet moved)

// DRY/tester virtual position: reproduces research MAX1 without sending orders.
bool v_open=false,v_tp1=false;
int v_dir=0;
double v_R=0,v_entry=0,v_sl=0,v_tp1px=0,v_lock=0,v_tp2=0;
datetime v_entry_time=0;
int v_entries=0,v_sl_n=0,v_lock_n=0,v_tp_n=0,v_timeout_n=0;
double v_totalR=0;

string TS(datetime t){ return TimeToString(t,TIME_DATE|TIME_MINUTES|TIME_SECONDS); }

string TFPrefix()
{
   switch(Timeframe)
   {
      case PERIOD_M1: return "M1_";
      case PERIOD_M2: return "M2_";
      case PERIOD_M3: return "M3_";
      case PERIOD_M4: return "M4_";
      case PERIOD_M5: return "M5_";
      default: return EnumToString(Timeframe)+"_";
   }
}

datetime LastSundayOfMonth(int year,int month,int daysInMonth)
{
   MqlDateTime dt; dt.year=year; dt.mon=month; dt.day=daysInMonth;
   dt.hour=0; dt.min=0; dt.sec=0;
   datetime d=StructToTime(dt);
   MqlDateTime cur; TimeToStruct(d,cur);
   d-=cur.day_of_week*86400; // day_of_week: 0=Sunday
   return d;
}

bool IsEUDST(datetime server_now)
{
   MqlDateTime t; TimeToStruct(server_now,t);
   datetime dstStart=LastSundayOfMonth(t.year,3,31);
   datetime dstEnd  =LastSundayOfMonth(t.year,10,31);
   return (server_now>=dstStart && server_now<dstEnd);
}

int KST_Hour(datetime server_now)
{
   int offsetHours=IsEUDST(server_now)?6:7;
   MqlDateTime t; TimeToStruct(server_now+offsetHours*3600,t);
   return t.hour;
}

bool InSkipHourKST(datetime server_now)
{
   int h=KST_Hour(server_now);
   return (h>=SkipHourStartKST && h<SkipHourEndKST);
}

void Log(string event,string detail="")
{
   Print("LIVE005 RFILTER2 ",TFPrefix(),"| ",event," | ",detail);
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
   ulong prevTicket=managed_ticket; double prevR=managed_R;
   managed=false; managed_ticket=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);
      if(tk==0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;

      managed=true; managed_ticket=tk;
      managed_entry=PositionGetDouble(POSITION_PRICE_OPEN);
      managed_sl=PositionGetDouble(POSITION_SL);
      managed_tp2=PositionGetDouble(POSITION_TP);
      long type=PositionGetInteger(POSITION_TYPE);
      managed_dir=(type==POSITION_TYPE_BUY ? +1 : -1);

      bool sameTicketAsBefore=(tk==prevTicket && prevR>0);
      if(sameTicketAsBefore)
      {
         // Already-tracked position: keep the original R -- recomputing it
         // every tick from the CURRENT SL/TP breaks once UseTrailingTP zeroes
         // the TP (falls through to the SL-based formula using the already-
         // moved SL, silently shrinking R tick by tick). Ported from
         // XAU_M2_BB_LIVE_005_RFILTER_V2.mq5's own header -- see that file
         // for the live bug (ticket #1227805316, 2026.10.15) this guards
         // against; not yet observed live on this timeframe.
         managed_R=prevR;
      }
      else if(managed_tp2>0) managed_R=MathAbs(managed_tp2-managed_entry)/TP2_R;
      else if(managed_sl>0) managed_R=MathAbs(managed_sl-managed_entry)/InitialSL_R;
      else managed_R=0;

      if(managed_R>0)
      {
         managed_tp1=managed_entry+managed_dir*TP1_R*managed_R;
         managed_lock=managed_entry+managed_dir*Lock_R*managed_R;
         if(!sameTicketAsBefore)
         {
            // Newly-found position (fresh entry or EA restart): recover
            // tp1_reached/protect_reached from the current SL. Only done once
            // per ticket.
            double eps=2*_Point;
            tp1_reached=(managed_dir==+1 ? managed_sl>=managed_lock-eps
                                        : managed_sl<=managed_lock+eps && managed_sl>0);
            double managed_protect=managed_entry+managed_dir*ProtectR*managed_R;
            protect_reached=tp1_reached ||
               (managed_dir==+1 ? managed_sl>=managed_protect-eps
                                : managed_sl<=managed_protect+eps && managed_sl>0);
         }
      }
      return true;
   }
   tp1_reached=false;
   protect_reached=false;
   trail_stop_level=0; trail_tp_armed=false; trail_tp_stop_level=0;
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
   datetime t=iTime(_Symbol,Timeframe,0);
   if(t==0 || t==last_m2_bar) return;
   last_m2_bar=t;

   double o=iOpen(_Symbol,Timeframe,1),h=iHigh(_Symbol,Timeframe,1);
   double l=iLow(_Symbol,Timeframe,1),c=iClose(_Symbol,Timeframe,1);
   datetime sig=iTime(_Symbol,Timeframe,1);
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
   datetime entryNow=(datetime)(tick.time_msc/1000);
   bool skipHour=InSkipHourKST(entryNow);
   Log("SKIP_HOUR_CHECK","skipHour="+(skipHour?"true":"false")+" kstHour="+IntegerToString(KST_Hour(entryNow)));
   if(skipHour && SkipEntryHourKST)
   {
      Log("ENTRY_SKIPPED","blocked by SkipEntryHourKST=true (KST hour in ["+IntegerToString(SkipHourStartKST)+","+IntegerToString(SkipHourEndKST)+"))");
      return false;
   }
   if(!EnableLiveOrders)
   {
      v_open=true; v_tp1=false; v_dir=dir; v_R=s.R;
      v_entry=(dir==+1 ? tick.ask : tick.bid);
      v_sl=v_entry-dir*InitialSL_R*v_R;
      v_tp1px=v_entry+dir*TP1_R*v_R;
      v_lock=v_entry+dir*Lock_R*v_R;
      v_tp2=v_entry+dir*TP2_R*v_R;
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
   double sl=ref-dir*InitialSL_R*s.R;
   double tp=ref+dir*TP2_R*s.R;

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

   string tag="LIVE005_"+TFPrefix();
   bool ok=(dir==+1 ? trade.Buy(Lots,_Symbol,0.0,sl,tp,tag)
                    : trade.Sell(Lots,_Symbol,0.0,sl,tp,tag));
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
   if(!FindOurPosition()) return;
   if(managed_R<=0) return;

   if(UseProtectStop && !protect_reached && !tp1_reached)
   {
      double protectTriggerPx=managed_entry+managed_dir*ProtectTriggerR*managed_R;
      double px0=(managed_dir==+1 ? tick.bid : tick.ask);
      bool protectHit=(managed_dir==+1 ? px0>=protectTriggerPx : px0<=protectTriggerPx);
      if(protectHit)
      {
         double protectLevel=managed_entry+managed_dir*ProtectR*managed_R;
         Log("PROTECT_TRIGGER","favR="+DoubleToString(ProtectTriggerR,3));
         if(!EnableLiveOrders)
         {
            protect_reached=true;
            Log("DRY_PROTECT","would move SL to "+DoubleToString(protectLevel,_Digits));
         }
         else if(SafeModifyPosition(managed_ticket,managed_dir,protectLevel,managed_tp2,"PROTECT_MODIFY"))
         {
            protect_reached=true;
            Log("PROTECT_MOVED","SL->"+DoubleToString(protectLevel,_Digits));
         }
      }
   }

   if(!tp1_reached)
   {
      double px=(managed_dir==+1 ? tick.bid : tick.ask); // executable close side
      bool hit=(managed_dir==+1 ? px>=managed_tp1 : px<=managed_tp1);
      if(!hit) return;

      if(!EnableLiveOrders)
      {
         tp1_reached=true;
         Log("DRY_TP1","would move whole-position SL to +0.25R");
         return;
      }

      if(!UseTrailingStop && !UseTrailingTP)
      {
         trade.SetExpertMagicNumber(MagicNumber);
         if(SafeModifyPosition(managed_ticket,managed_dir,managed_lock,managed_tp2,"LOCK_MODIFY"))
         {
            tp1_reached=true;
            Log("TP1_LOCK","TP1 reached; 0.01 lot cannot partial-close 30%, whole SL moved to "+
                DoubleToString(managed_lock,_Digits));
         }
         // If temporarily invalid because price is too close, retry on later ticks.
         return;
      }

      // TP1 reached with trailing enabled: arm continuous trailing instead
      // of the static one-time Lock_R move. Falls through to the trailing
      // logic below on this same tick.
      tp1_reached=true;
      trade.SetExpertMagicNumber(MagicNumber);
      Log("TP1_TRAIL_ARM","TP1 reached, switching to continuous trailing instead of static Lock_R");
   }

   // -- post-TP1 continuous trailing (only reached once tp1_reached=true
   //    AND at least one trailing mode is enabled -- otherwise the static
   //    Lock_R branch above already handled this position) --
   if(!UseTrailingStop && !UseTrailingTP) return;

   if(UseTrailingTP && !trail_tp_armed)
   {
      if(!EnableLiveOrders)
      {
         trail_tp_armed=true;
         Log("TRAIL_TP_ARM_DRY","would remove TP2 cap and start trailing (EnableLiveOrders=false)");
      }
      else if(SafeModifyPosition(managed_ticket,managed_dir,managed_sl,0.0,"TRAIL_TP_ARM"))
      {
         trail_tp_armed=true;
         Log("TRAIL_TP_ARMED","TP2 cap removed, now trailing");
      }
   }

   bool tpRemoved=trail_tp_armed;
   if(!UseTrailingStop && !tpRemoved) return; // TrailingTP not armed yet, TrailingStop off: nothing to do this tick

   double curPrice=(managed_dir==+1 ? tick.bid : tick.ask);
   double distanceR=(tpRemoved ? TrailTPDistanceR : TrailStopDistanceR);
   double candidateSL=NormalizeDouble(curPrice-managed_dir*distanceR*managed_R,_Digits);
   double curSL=PositionGetDouble(POSITION_SL);
   // POSITION_SL can lag one tick behind a just-accepted modify (local
   // position cache not yet refreshed), so also floor/ceiling curSL against
   // this EA's own record of the last level it successfully set. Ported from
   // XAU_M2_BB_LIVE_005_RFILTER_V2.mq5's own header -- see that file for the
   // live bug (ticket #1227805316, 2026.10.15) this guards against; not yet
   // observed live on this timeframe.
   double knownSL=(tpRemoved ? trail_tp_stop_level : trail_stop_level);
   if(knownSL>0) curSL=(managed_dir==+1 ? MathMax(curSL,knownSL) : MathMin(curSL,knownSL));
   bool improves=(curSL==0) || (managed_dir==+1 ? candidateSL>curSL : candidateSL<curSL);
   if(!improves) return;

   double desiredTP=(tpRemoved ? 0.0 : managed_tp2);
   if(!EnableLiveOrders)
   {
      Log(tpRemoved?"TRAIL_TP_STOP_DRY":"TRAIL_STOP_DRY","would move SL->"+DoubleToString(candidateSL,_Digits)+
          " (EnableLiveOrders=false)");
      return;
   }
   if(SafeModifyPosition(managed_ticket,managed_dir,candidateSL,desiredTP,tpRemoved?"TRAIL_TP_STOP_MODIFY":"TRAIL_STOP_MODIFY"))
   {
      if(tpRemoved) trail_tp_stop_level=candidateSL; else trail_stop_level=candidateSL;
      Log(tpRemoved?"TRAIL_TP_STOP_MOVED":"TRAIL_STOP_MOVED","SL->"+DoubleToString(candidateSL,_Digits));
   }
}

int OnInit()
{
   hBB20=iBands(_Symbol,Timeframe,20,0,2.0,PRICE_CLOSE);
   hBB4 =iBands(_Symbol,Timeframe,4,0,4.0,PRICE_OPEN);
   if(hBB20==INVALID_HANDLE || hBB4==INVALID_HANDLE) return INIT_FAILED;

   f_log=FileOpen("XAU_"+TFPrefix()+"LIVE_005_RFILTER2_LOG.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
   if(f_log!=INVALID_HANDLE)
   {
      FileSeek(f_log,0,SEEK_END);
      if(FileTell(f_log)==0) FileWrite(f_log,"TIME","EVENT","DETAIL");
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(MaxDeviationPts);
   trade.SetTypeFillingBySymbol(_Symbol);
   FindOurPosition();

   Log("START","TF="+TFPrefix()+" | PB=0.10R | SL=2R | own-Magic MAX1 | Magic="+
       IntegerToString((int)MagicNumber)+" | Lots="+DoubleToString(Lots,2)+
       " | LatestSignalOnly="+(LatestSignalOnly?"true":"false")+
       " | AllowShort="+(AllowShort?"true":"false")+" | MinR_Points="+DoubleToString(MinR_Points,1)+
       " | ProtectTriggerR="+DoubleToString(ProtectTriggerR,2)+" ProtectR="+DoubleToString(ProtectR,2)+
       " UseProtectStop="+(UseProtectStop?"true":"false")+
       " | UseTrailingStop="+(UseTrailingStop?"true":"false")+" TrailStopDistanceR="+DoubleToString(TrailStopDistanceR,2)+
       " | UseTrailingTP="+(UseTrailingTP?"true":"false")+" TrailTPDistanceR="+DoubleToString(TrailTPDistanceR,2)+
       " | orders="+(EnableLiveOrders?"ENABLED":"DRY"));
   Log("NOTE","RFILTER2 build: 005_BUYONLY + MinR_Points filter + LatestSignalOnly (newest BB-breakout candle supersedes any pending earlier setup)");
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
}
//+------------------------------------------------------------------+
