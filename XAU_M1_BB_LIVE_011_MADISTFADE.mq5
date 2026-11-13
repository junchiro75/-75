//+------------------------------------------------------------------+
//| XAU_M1_BB_LIVE_011_MADISTFADE.mq5                                  |
//+------------------------------------------------------------------+
//| New dedicated model (2026-11-13), split out of the exploratory    |
//| UseMADistanceDir/UseBearFarFadeOnly/UseMADistStochConfirm toggles  |
//| built inside XAU_M1_BB_LIVE_001_STOCH.mq5. Signal: the SAME        |
//| double-BB touch (BB20(20,2,PRICE_CLOSE) AND BB4(4,4,PRICE_OPEN)    |
//| both touched) 001 uses, but direction is decided by the signal      |
//| candle's distance (in R) from a moving average instead of          |
//| Stochastic: distR=|close-MA|/R. Restricted to ONLY the BEAR signal  |
//| + far-from-MA case (sigdir=-1, distR>=MADistanceThresholdR) --      |
//| traded as a BUY fade -- with a Stochastic-oversold confirmation on  |
//| top (same StochOversold level as 001's own FADE_BEAR_OS). Exit:     |
//| the same ProtectStop/TrailingStop/TrailingTP management ported      |
//| from 001/M2_v2.                                                     |
//|                                                                     |
//| CONFIRMED LIVE (2026-11-13): SL_R=1.0, TP_R=0.5 (structurally       |
//| inert once UseTrailingTP arms at TrailTPTriggerR=0.15R and removes  |
//| the fixed TP), MinR_Points=300, MADistanceThresholdR=0.5,           |
//| MADistancePeriod=20. Chosen from a 196-combo MT5 Optimizer sweep    |
//| (SL_R 0.5-2.0, MinR_Points 200-800, MADistanceThresholdR 0.25-1.0): |
//| NET $37,386.60, PF 2.725, RF 51.48, Equity DD 0.72% over            |
//| 2025.01-2026.10 (MT5-verified official report). MADistanceThresholdR|
//| itself barely moves the result (0.25/0.5/0.75 are near-identical);  |
//| MinR_Points=300 beats both 200 (lower NET, thinner PF) and 400+     |
//| (lower NET for barely less DD) in the sweep -- unlike model 010's   |
//| BB4 signal, this signal's risk stays low (DD<=~1.2%) across nearly  |
//| the whole sweep, so the pick here favours NET more than 010's did.  |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input ENUM_TIMEFRAMES Timeframe = PERIOD_M1; // signal-candle timeframe
input double Lots               = 0.1; // Lot size
input int    StochK_Period      = 17;    // Stoch %K period (only used for UseMADistStochConfirm)
input int    StochD_Period      = 3; // Stoch %D period
input int    StochSlowing       = 3; // Stoch slowing
input double StochOversold      = 25.0; // Stoch oversold level, confirms the BEAR_FAR_FADE case
input double SL_R               = 1.0;  // Stop loss (R) (CONFIRMED, see header)
input double TP_R               = 0.5; // Take profit (R) (structurally inert once UseTrailingTP arms, CONFIRMED, see header)
input double MinR_Points        = 300;  // Min signal-candle body (points) to trade (CONFIRMED, see header)
input int    MADistancePeriod   = 20;    // Moving average period (SMA on Close) (CONFIRMED, see header)
input double MADistanceThresholdR = 0.5; // Distance (R) threshold: below this, NEAR (not traded here); at/above, FAR (CONFIRMED, see header)
input ulong  MagicNumber        = 95016121; // Magic number
input int    MaxDeviationPts    = 50; // Max price deviation (points)
input bool   EnableLiveOrders   = false; // Enable live orders

input int    SkipHourStartKST   = 14; // KST hour skip window start (ported from 001, UNTESTED on this signal)
input int    SkipHourEndKST     = 16; // KST hour skip window end, exclusive
input bool   SkipHourEntryKST   = true; // Block entries in [SkipHourStartKST,SkipHourEndKST) KST

input double MildZoneR          = 2.0;  // Adverse-R boundary for dwell-time diagnostic (no trading effect)

input double ProtectTriggerR    = 0.25; // Favorable R to arm protect-lock stop (CONFIRMED, ported from 001)
input double ProtectR           = 0.05; // SL level once armed, in R (CONFIRMED, ported from 001)
input bool   UseProtectStop     = true; // Move SL to ProtectR once armed (CONFIRMED, ported from 001)

input bool   UseTrailingStop    = true; // Continuously trail SL behind price once armed (CONFIRMED, ported from 001)
input double TrailStopTriggerR  = 0.09; // Favorable R to arm the trailing stop (CONFIRMED, ported from 001)
input double TrailStopDistanceR = 0.05; // Distance maintained between price and the trailing SL, in R (CONFIRMED, ported from 001)
input bool   UseTrailingTP      = true; // Once price reaches TrailTPTriggerR, widen the broker TP and trail SL instead (CONFIRMED, ported from 001)
input double TrailTPTriggerR    = 0.15; // Favorable R to arm the trailing TP -- must be strictly less than TP_R or the broker's own TP fires first
input double TrailTPDistanceR   = 0.04; // Distance maintained between price and the trailing SL once UseTrailingTP arms, in R

int hBB20=INVALID_HANDLE,hBB4=INVALID_HANDLE,hStoch=INVALID_HANDLE,hMA=INVALID_HANDLE;
datetime last_m1_bar=0;
int f_log=INVALID_HANDLE;

#define TRACK_SLOTS 4
ulong    g_trackTicket[TRACK_SLOTS];
double   g_trackEntry[TRACK_SLOTS], g_trackR[TRACK_SLOTS];
int      g_trackDir[TRACK_SLOTS];
string   g_trackTag[TRACK_SLOTS];
datetime g_trackLastSample[TRACK_SLOTS];
double   g_timeMildMin[TRACK_SLOTS], g_timeDangerMin[TRACK_SLOTS];
bool     g_protectTriggered[TRACK_SLOTS];
bool     g_protectMoved[TRACK_SLOTS];
double   g_trailStopLevel[TRACK_SLOTS];
bool     g_trailTPArmed[TRACK_SLOTS];
double   g_trailTPStopLevel[TRACK_SLOTS];

int FindTrackSlot(ulong ticket)
{
   for(int i=0;i<TRACK_SLOTS;i++) if(g_trackTicket[i]==ticket) return i;
   return -1;
}

int FindFreeTrackSlot()
{
   for(int i=0;i<TRACK_SLOTS;i++) if(g_trackTicket[i]==0) return i;
   return -1;
}

void StartMAETracking(ulong ticket,double entry,double R,int dir,string tag)
{
   int i=FindFreeTrackSlot();
   if(i<0){ Log("TRACK_SLOTS_FULL","dropping tracking for ticket="+IntegerToString((int)ticket)); return; }
   g_trackTicket[i]=ticket; g_trackEntry[i]=entry; g_trackR[i]=R; g_trackDir[i]=dir; g_trackTag[i]=tag;
   g_trackLastSample[i]=TimeCurrent(); g_timeMildMin[i]=0; g_timeDangerMin[i]=0;
   g_protectTriggered[i]=false; g_protectMoved[i]=false;
   g_trailStopLevel[i]=0; g_trailTPArmed[i]=false; g_trailTPStopLevel[i]=0;
}

void AdoptOrphanPositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);
      if(tk==0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      if(FindTrackSlot(tk)>=0) continue;

      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=PositionGetDouble(POSITION_SL);
      int dir=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?1:-1;
      if(sl<=0 || SL_R<=0) continue;
      double R=MathAbs(entry-sl)/SL_R;
      if(R<=0) continue;

      StartMAETracking(tk,entry,R,dir,"ADOPTED_ORPHAN");
      Log("ORPHAN_ADOPTED","ticket="+IntegerToString((int)tk)+" entry="+DoubleToString(entry,_Digits)+
          " R="+DoubleToString(R,_Digits)+" dir="+(dir==1?"BUY":"SELL"));
   }
}

void CheckMAEProgress()
{
   AdoptOrphanPositions();
   bool anyActive=false;
   for(int i=0;i<TRACK_SLOTS;i++) if(g_trackTicket[i]!=0){ anyActive=true; break; }
   if(!anyActive) return;
   MqlTick q; if(!SymbolInfoTick(_Symbol,q)) return;

   for(int i=0;i<TRACK_SLOTS;i++)
   {
      if(g_trackTicket[i]==0) continue;
      if(!PositionSelectByTicket(g_trackTicket[i])) continue;
      double adverseR=(g_trackDir[i]==+1) ? (g_trackEntry[i]-q.bid)/g_trackR[i] : (q.ask-g_trackEntry[i])/g_trackR[i];

      datetime now=TimeCurrent();
      double elapsedMin=(double)(now-g_trackLastSample[i])/60.0;
      if(elapsedMin>0)
      {
         if(adverseR<MildZoneR) g_timeMildMin[i]+=elapsedMin;
         else                   g_timeDangerMin[i]+=elapsedMin;
         g_trackLastSample[i]=now;
      }

      double favR=(g_trackDir[i]==+1) ? (q.bid-g_trackEntry[i])/g_trackR[i] : (g_trackEntry[i]-q.ask)/g_trackR[i];
      if(!g_protectTriggered[i] && favR>=ProtectTriggerR)
      {
         g_protectTriggered[i]=true;
         Log("PROTECT_TRIGGER","favR="+DoubleToString(favR,3)+" | "+g_trackTag[i]);
         if(UseProtectStop)
         {
            double curTP=PositionGetDouble(POSITION_TP);
            double lock=NormalizeDouble(g_trackEntry[i]+g_trackDir[i]*ProtectR*g_trackR[i],_Digits);
            if(!EnableLiveOrders)
               Log("PROTECT_MOVE_DRY","would move SL->"+DoubleToString(lock,_Digits)+" (EnableLiveOrders=false) | "+g_trackTag[i]);
            else if(trade.PositionModify(g_trackTicket[i],lock,curTP))
            {
               g_protectMoved[i]=true;
               Log("PROTECT_MOVED","SL->"+DoubleToString(lock,_Digits)+" | "+g_trackTag[i]);
            }
            else
               Log("PROTECT_MOVE_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
         }
      }

      if(UseTrailingStop && favR>=TrailStopTriggerR)
      {
         double curPrice=(g_trackDir[i]==+1)?q.bid:q.ask;
         double candidateSL=NormalizeDouble(curPrice-g_trackDir[i]*TrailStopDistanceR*g_trackR[i],_Digits);
         double curSL=PositionGetDouble(POSITION_SL);
         if(g_trailStopLevel[i]>0) curSL=(g_trackDir[i]==+1 ? MathMax(curSL,g_trailStopLevel[i]) : MathMin(curSL,g_trailStopLevel[i]));
         bool improves=(curSL==0) || (g_trackDir[i]==+1 ? candidateSL>curSL : candidateSL<curSL);
         if(improves)
         {
            double cushion=MinStopDistance()+_Point;
            double sl=candidateSL;
            if(g_trackDir[i]==+1){ if(sl>q.bid-cushion) sl=q.bid-cushion; }
            else                 { if(sl<q.ask+cushion) sl=q.ask+cushion; }
            sl=NormalizeDouble(sl,_Digits);
            double curTPforTrail=PositionGetDouble(POSITION_TP);
            if(!EnableLiveOrders)
               Log("TRAIL_STOP_DRY","would move SL->"+DoubleToString(sl,_Digits)+" (EnableLiveOrders=false) | "+g_trackTag[i]);
            else if(trade.PositionModify(g_trackTicket[i],sl,curTPforTrail))
            {
               g_trailStopLevel[i]=sl;
               Log("TRAIL_STOP_MOVED","SL->"+DoubleToString(sl,_Digits)+" favR="+DoubleToString(favR,3)+" | "+g_trackTag[i]);
            }
            else
               Log("TRAIL_STOP_MOVE_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
         }
      }

      if(UseTrailingTP)
      {
         if(!g_trailTPArmed[i] && favR>=TrailTPTriggerR)
         {
            double curSLforArm=PositionGetDouble(POSITION_SL);
            if(!EnableLiveOrders)
            {
               g_trailTPArmed[i]=true;
               Log("TRAIL_TP_ARM_DRY","would widen TP and start trailing (EnableLiveOrders=false) | "+g_trackTag[i]);
            }
            else if(trade.PositionModify(g_trackTicket[i],curSLforArm,0.0))
            {
               g_trailTPArmed[i]=true;
               Log("TRAIL_TP_ARMED","TP removed, now trailing | favR="+DoubleToString(favR,3)+" | "+g_trackTag[i]);
            }
            else
               Log("TRAIL_TP_ARM_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
         }

         if(g_trailTPArmed[i])
         {
            double curPriceTP=(g_trackDir[i]==+1)?q.bid:q.ask;
            double candidateSL2=NormalizeDouble(curPriceTP-g_trackDir[i]*TrailTPDistanceR*g_trackR[i],_Digits);
            double curSL2=PositionGetDouble(POSITION_SL);
            if(g_trailTPStopLevel[i]>0) curSL2=(g_trackDir[i]==+1 ? MathMax(curSL2,g_trailTPStopLevel[i]) : MathMin(curSL2,g_trailTPStopLevel[i]));
            bool improves2=(curSL2==0) || (g_trackDir[i]==+1 ? candidateSL2>curSL2 : candidateSL2<curSL2);
            if(improves2)
            {
               double cushion2=MinStopDistance()+_Point;
               double sl2=candidateSL2;
               if(g_trackDir[i]==+1){ if(sl2>q.bid-cushion2) sl2=q.bid-cushion2; }
               else                 { if(sl2<q.ask+cushion2) sl2=q.ask+cushion2; }
               sl2=NormalizeDouble(sl2,_Digits);
               if(!EnableLiveOrders)
                  Log("TRAIL_TP_STOP_DRY","would move SL->"+DoubleToString(sl2,_Digits)+" (EnableLiveOrders=false) | "+g_trackTag[i]);
               else if(trade.PositionModify(g_trackTicket[i],sl2,0.0))
               {
                  g_trailTPStopLevel[i]=sl2;
                  Log("TRAIL_TP_STOP_MOVED","SL->"+DoubleToString(sl2,_Digits)+" favR="+DoubleToString(favR,3)+" | "+g_trackTag[i]);
               }
               else
                  Log("TRAIL_TP_STOP_MOVE_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
            }
         }
      }
   }
}

string TS(datetime t){ return TimeToString(t,TIME_DATE|TIME_MINUTES|TIME_SECONDS); }

void Log(string event,string detail="")
{
   Print("XAU_M1_BB_LIVE_011_MADISTFADE | ",event," | ",detail);
   if(f_log!=INVALID_HANDLE){ FileWrite(f_log,TS(TimeCurrent()),event,detail); FileFlush(f_log); }
}

double MinStopDistance()
{
   long stops=0,freeze=0;
   SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL,stops);
   SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL,freeze);
   return (double)MathMax(stops,freeze)*_Point;
}

// -- Korea-time session helper, ported unchanged from 001/005/006/007. ---
datetime LastSundayOfMonth(int year,int month,int daysInMonth)
{
   MqlDateTime dt; dt.year=year; dt.mon=month; dt.day=daysInMonth;
   dt.hour=0; dt.min=0; dt.sec=0;
   datetime d=StructToTime(dt);
   MqlDateTime cur; TimeToStruct(d,cur);
   d-=cur.day_of_week*86400;
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

int CountOurPositions()
{
   int n=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);
      if(tk==0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      n++;
   }
   return n;
}

void OpenTrade(int dir,double R,string tag)
{
   if(CountOurPositions()>0){ Log("ENTRY_SKIPPED","own-Magic position already exists"); return; }
   int kstHour=KST_Hour(TimeCurrent());
   bool inSkipHour=(kstHour>=SkipHourStartKST && kstHour<SkipHourEndKST);
   if(inSkipHour && SkipHourEntryKST)
   {
      Log("ENTRY_SKIPPED","KST hour in ["+IntegerToString(SkipHourStartKST)+","+IntegerToString(SkipHourEndKST)+") by SkipHourEntryKST=true");
      return;
   }
   tag="M1_"+tag;

   MqlTick q; if(!SymbolInfoTick(_Symbol,q)){ Log("ORDER_FAIL","no current tick"); return; }
   double ref=(dir==+1 ? q.ask : q.bid);
   double sl=ref-dir*SL_R*R;
   double tp=ref+dir*TP_R*R;

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

   if(!EnableLiveOrders)
   {
      Log("DRY_ENTRY",(dir==1?"BUY":"SELL")+string(" @~")+DoubleToString(ref,_Digits)+
          " R="+DoubleToString(R,_Digits)+" SL="+DoubleToString(sl,_Digits)+" TP="+DoubleToString(tp,_Digits)+" | "+tag);
      return;
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(MaxDeviationPts);
   trade.SetTypeFillingBySymbol(_Symbol);

   bool ok=(dir==+1 ? trade.Buy(Lots,_Symbol,0.0,sl,tp,tag)
                    : trade.Sell(Lots,_Symbol,0.0,sl,tp,tag));
   if(!ok)
      Log("ORDER_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
   else
   {
      Log("ENTRY_OK",(dir==1?"BUY":"SELL")+" R="+DoubleToString(R,_Digits)+
          " SL="+DoubleToString(sl,_Digits)+" TP="+DoubleToString(tp,_Digits)+" | "+tag);
      ulong posId=0;
      ulong orderTicket=trade.ResultOrder();
      if(orderTicket!=0 && PositionSelectByTicket(orderTicket)) posId=orderTicket;
      if(posId==0)
      {
         ulong dealTicket=trade.ResultDeal();
         if(dealTicket!=0 && HistoryDealSelect(dealTicket))
         {
            ulong pid=(ulong)HistoryDealGetInteger(dealTicket,DEAL_POSITION_ID);
            if(pid!=0 && PositionSelectByTicket(pid)) posId=pid;
         }
      }
      if(posId!=0)
         StartMAETracking(posId,ref,R,dir,tag);
      else
      {
         for(int i=PositionsTotal()-1;i>=0;i--)
         {
            ulong tk=PositionGetTicket(i);
            if(tk==0 || !PositionSelectByTicket(tk)) continue;
            if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
            if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
            StartMAETracking(tk,ref,R,dir,tag);
            break;
         }
      }
   }
}

void CheckNewM1Bar()
{
   datetime t=iTime(_Symbol,Timeframe,0);
   if(t==0 || t==last_m1_bar) return;
   last_m1_bar=t;

   double o=iOpen(_Symbol,Timeframe,1),h=iHigh(_Symbol,Timeframe,1);
   double l=iLow(_Symbol,Timeframe,1),c=iClose(_Symbol,Timeframe,1);
   datetime sig=iTime(_Symbol,Timeframe,1);
   if(sig==0){ Log("BAR_DATA_FAIL","iTime(1) returned 0"); return; }

   double up20[1],lo20[1],up4[1],lo4[1];
   int r1=CopyBuffer(hBB20,1,1,1,up20), r2=CopyBuffer(hBB20,2,1,1,lo20);
   int r3=CopyBuffer(hBB4,1,1,1,up4),   r4=CopyBuffer(hBB4,2,1,1,lo4);
   if(r1!=1 || r2!=1 || r3!=1 || r4!=1)
   {
      Log("COPYBUFFER_FAIL","BB20up="+IntegerToString(r1)+" BB20lo="+IntegerToString(r2)+
          " BB4up="+IntegerToString(r3)+" BB4lo="+IntegerToString(r4)+
          " err="+IntegerToString(GetLastError()));
      return;
   }

   // Same double-BB signal as 001: BB20 AND BB4 both touched this bar.
   int sigdir=0;
   if(c>o && h>=up20[0] && h>=up4[0]) sigdir=+1;
   else if(c<o && l<=lo20[0] && l<=lo4[0]) sigdir=-1;
   if(sigdir==0) return;

   double R=MathAbs(c-o);
   double minR=MathMax(_Point,MinR_Points*_Point);
   if(R<=minR){ Log("SIGNAL_SKIPPED","R too small"); return; }

   // Direction decided by distance from the signal candle's close to a
   // moving average instead of Stochastic -- restricted to ONLY the BEAR
   // signal + far-from-MA (fade/BUY) case (CONFIRMED, see header).
   double maBuf[1];
   if(CopyBuffer(hMA,0,1,1,maBuf)!=1){ Log("MA_FAIL","no MA value"); return; }
   double maVal=maBuf[0];
   double distR=MathAbs(c-maVal)/R;
   bool near=(distR<MADistanceThresholdR);
   if(!(sigdir==-1 && !near))
   { Log("SIGNAL_SKIPPED","not a BEAR_FAR_FADE case (sigdir="+IntegerToString(sigdir)+" near="+(near?"true":"false")+")"); return; }

   // Stochastic-oversold confirmation on top of the FAR_FADE case
   // (CONFIRMED, see header): same level 001's own FADE_BEAR_OS uses.
   double kbufM[1];
   if(CopyBuffer(hStoch,0,1,1,kbufM)!=1){ Log("STOCH_FAIL","no stochastic value"); return; }
   double stochKm=kbufM[0];
   if(!(stochKm<StochOversold))
   { Log("SIGNAL_SKIPPED","Stochastic not confirming (stochK="+DoubleToString(stochKm,2)+")"); return; }

   int dir=+1; // fade the BEAR signal candle -> BUY
   string tag="MADIST_BEAR_FAR_FADE";

   Log("SIGNAL","MA-distance | sigdir=BEAR R="+DoubleToString(R,_Digits)+
       " MA="+DoubleToString(maVal,_Digits)+" distR="+DoubleToString(distR,3)+
       " stochK="+DoubleToString(stochKm,2)+" | decided dir=BUY | "+tag);
   OpenTrade(dir,R,tag);
}

int OnInit()
{
   hBB20=iBands(_Symbol,Timeframe,20,0,2.0,PRICE_CLOSE);
   hBB4 =iBands(_Symbol,Timeframe,4,0,4.0,PRICE_OPEN);
   hStoch=iStochastic(_Symbol,Timeframe,StochK_Period,StochD_Period,StochSlowing,MODE_LWMA,STO_LOWHIGH);
   hMA  =iMA(_Symbol,Timeframe,MADistancePeriod,0,MODE_SMA,PRICE_CLOSE);
   if(hBB20==INVALID_HANDLE || hBB4==INVALID_HANDLE || hStoch==INVALID_HANDLE || hMA==INVALID_HANDLE) return INIT_FAILED;

   f_log=FileOpen("XAU_M1_BB_LIVE_011_MADISTFADE_LOG.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
   if(f_log!=INVALID_HANDLE)
   {
      FileSeek(f_log,0,SEEK_END);
      if(FileTell(f_log)==0) FileWrite(f_log,"TIME","EVENT","DETAIL");
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(MaxDeviationPts);
   trade.SetTypeFillingBySymbol(_Symbol);

   Log("START",string("TF=")+EnumToString(Timeframe)+" | SL_R="+DoubleToString(SL_R,2)+
       " | TP_R="+DoubleToString(TP_R,2)+" | MinR_Points="+DoubleToString(MinR_Points,1)+
       " | MADistancePeriod="+IntegerToString(MADistancePeriod)+" MADistanceThresholdR="+DoubleToString(MADistanceThresholdR,2)+
       " | StochOversold="+DoubleToString(StochOversold,1)+
       " | SkipHourStartKST="+IntegerToString(SkipHourStartKST)+" SkipHourEndKST="+IntegerToString(SkipHourEndKST)+
       " SkipHourEntryKST="+(SkipHourEntryKST?"true":"false")+
       " | ProtectTriggerR="+DoubleToString(ProtectTriggerR,2)+" ProtectR="+DoubleToString(ProtectR,2)+
       " UseProtectStop="+(UseProtectStop?"true":"false")+
       " | UseTrailingStop="+(UseTrailingStop?"true":"false")+" TrailStopTriggerR="+DoubleToString(TrailStopTriggerR,2)+
       " TrailStopDistanceR="+DoubleToString(TrailStopDistanceR,2)+
       " | UseTrailingTP="+(UseTrailingTP?"true":"false")+" TrailTPTriggerR="+DoubleToString(TrailTPTriggerR,2)+
       " TrailTPDistanceR="+DoubleToString(TrailTPDistanceR,2)+
       " | Lots="+DoubleToString(Lots,2)+" | Magic="+IntegerToString((int)MagicNumber)+
       " | orders="+(EnableLiveOrders?"ENABLED":"DRY"));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(f_log!=INVALID_HANDLE){ FileFlush(f_log); FileClose(f_log); }
   if(hBB20!=INVALID_HANDLE) IndicatorRelease(hBB20);
   if(hBB4!=INVALID_HANDLE)  IndicatorRelease(hBB4);
   if(hStoch!=INVALID_HANDLE) IndicatorRelease(hStoch);
   if(hMA!=INVALID_HANDLE)   IndicatorRelease(hMA);
}

// Sums profit+swap+commission across EVERY deal belonging to a closed
// position (entry AND exit) -- see 001's header for the ground-truth bug
// this works around (commission charged on the entry deal only).
double SumPositionProfit(ulong posId)
{
   double sum=0;
   if(HistorySelectByPosition(posId))
   {
      int total=HistoryDealsTotal();
      for(int d=0;d<total;d++)
      {
         ulong dealTicket=HistoryDealGetTicket(d);
         if(dealTicket==0) continue;
         sum+=HistoryDealGetDouble(dealTicket,DEAL_PROFIT)+HistoryDealGetDouble(dealTicket,DEAL_SWAP)+
              HistoryDealGetDouble(dealTicket,DEAL_COMMISSION);
      }
   }
   return sum;
}

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if((ulong)HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=MagicNumber) return;
   if(HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=_Symbol) return;
   if((long)HistoryDealGetInteger(trans.deal,DEAL_ENTRY)!=DEAL_ENTRY_OUT) return;

   ulong posId=(ulong)HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID);
   int i=FindTrackSlot(posId);
   if(i<0) return;

   double profit=SumPositionProfit(posId);
   string outcome=(profit>0?"WIN":"LOSS");
   Log("MAE_OUTCOME","outcome="+outcome+" profit="+DoubleToString(profit,2)+
       " timeMildMin="+DoubleToString(g_timeMildMin[i],1)+" timeDangerMin="+DoubleToString(g_timeDangerMin[i],1)+
       " protectTriggered="+(g_protectTriggered[i]?"true":"false")+
       " protectMoved="+(g_protectMoved[i]?"true":"false")+
       " trailStopLevel="+DoubleToString(g_trailStopLevel[i],_Digits)+
       " trailTPArmed="+(g_trailTPArmed[i]?"true":"false")+
       " trailTPStopLevel="+DoubleToString(g_trailTPStopLevel[i],_Digits)+
       " | "+g_trackTag[i]);
   g_trackTicket[i]=0;
}

void OnTick()
{
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;
   CheckMAEProgress();
   CheckNewM1Bar();
}
