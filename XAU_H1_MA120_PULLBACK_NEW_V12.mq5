//+------------------------------------------------------------------+
//| XAU_H1_MA120_PULLBACK_NEW_V12.mq5                                |
//| V5: order comment tags which band (BB20/BB4) and timeframe        |
//| triggered entry, e.g. "MA120_M2_BB20".                             |
//| V6: tried forcing BB20-only entry (AllowBB4Entry=false) based on   |
//| V5's retrospective band split -- made results WORSE (-\$742 vs     |
//| -\$516 at SL=3R), since skipping BB4 delays entry to a wider/worse |
//| R rather than reproducing the same trades. Reverted to true.      |
//| V7: added TP_OppositeBB4 -- ride the full range instead of TP at   |
//| MA_Short(20): BUY entered at lower BB20/BB4 -> TP at the OPPOSITE  |
//| upper BB4; SELL mirrors. At SL=3R this turned the strategy GROSS   |
//| profitable for the first time (+\$108, PF 1.05 before commission)  |
//| -- net still -\$203 purely from \$309.60 of commission on 2064      |
//| trades, not from bad signals.                                      |
//| V8: added UseM1/UseM2/UseM3 toggles to disable a timeframe's       |
//| setups entirely. M2-only + SL=4R turned out best so far (net       |
//| -\$19.96, gross +\$84.41, PF 1.12 before commission); M3-only was    |
//| much weaker (barely gross-positive). Lot size (tried 0.05) just     |
//| scales P&L and commission together -- doesn't fix the ratio.       |
//| V9: added a 4th timeframe, M5 (UseM5 toggle, same as M1/M2/M3), to  |
//| see if a slower timeframe than M2/M3 does even better. Also added  |
//| MinR_Points to skip entries whose R (pullback-to-band distance) is |
//| too small. Results: M5 was WORSE than M2 (PF 0.85 vs 1.12). The R  |
//| filter changed trade character a lot (win rate 22%->58%, but avg   |
//| loss grew 5x) while leaving the overall PF essentially unchanged   |
//| (0.974 -> 0.973) -- doesn't actually improve the edge.             |
//| V10: added TP_OppositeBB20 -- like TP_OppositeBB4 but targets the   |
//| opposite BB20 instead. CORRECTION: BB20 is NOT reliably narrower/   |
//| closer than BB4 -- BB4 only looks back 4 bars with a 4.0 multiplier,|
//| so its width floats independently of BB20's and is often the       |
//| CLOSER band in practice (V5's entry-side data showed BB4 touched    |
//| first 59% of the time). Which one is farther varies bar to bar.    |
//| V11: added TP_OppositeFarther -- instead of hard-coding which       |
//| opposite band to target, dynamically pick whichever of BB20/BB4 is  |
//| currently FARTHER away, re-evaluated every bar. Takes priority over |
//| TP_OppositeBB20 and TP_OppositeBB4 if true. Also: StopLoss_R=3.5 +   |
//| MaxSetupHours=1 + MinR_Points=350 produced the first NET PROFITABLE |
//| result in this whole design line (M2: +\$234.79, PF 1.69). Follow-up |
//| tests with per-timeframe windows (M2=2h/M3=6h/M5=4h, run as three   |
//| separate single-timeframe instances) were even better and net      |
//| profitable individually (+\$307/+\$284/+\$155), with LOW cross-       |
//| correlation (0.07-0.27) -- combined Sharpe (1.55) beats any single  |
//| timeframe alone.                                                    |
//| V12: added per-timeframe MaxSetupHours_M1/M2/M3/M5 (replacing the    |
//| single shared MaxSetupHours) so ONE instance can run M1/M2/M3/M5    |
//| together, each with its own tuned window, instead of needing        |
//| separate instances per timeframe.                                   |
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
input bool   AllowBB4Entry        = true;  // V6 test: forcing BB20-only (false) made results WORSE, not
                                            // better, than mixed entry (-\$742 vs -\$516 at SL=3R) -- the
                                            // earlier BB20-vs-BB4 split was retrospective/observational,
                                            // not causal (skipping BB4 delays entry to a wider, worse R
                                            // rather than reproducing the same "good" BB20 trades).
                                            // Default back to true (mixed entry, whichever touches first).
input bool   TP_OppositeBB4       = false; // false = TP at MA_Short (20) as before. true = TP at the
                                            // OPPOSITE band's BB4 (BUY entered at lower BB20/BB4 -> TP at
                                            // upper BB4; SELL mirrors) -- ride the full range instead of
                                            // just back to the middle. Lowest priority of the three
                                            // opposite-band TP modes below.
input bool   TP_OppositeBB20      = false; // true = TP at the OPPOSITE band's BB20 instead of BB4.
                                            // NOTE: BB20 is NOT reliably narrower/closer than BB4 -- BB4
                                            // only looks back 4 bars with a 4.0 multiplier, so its width
                                            // floats independently and is often the CLOSER band in
                                            // practice. Takes priority over TP_OppositeBB4 if both true.
input bool   TP_OppositeFarther   = false; // true = TP at whichever of the opposite BB20/BB4 is FARTHER
                                            // away right now, recomputed every bar (since which one is
                                            // farther can flip over time). Takes priority over both of
                                            // the above if true.
input int    MaxSetupHours_M1     = 72;   // how long an M1 setup stays valid waiting for a touch
input int    MaxSetupHours_M2     = 72;   // (each timeframe gets its OWN window -- e.g. tests found
input int    MaxSetupHours_M3     = 72;   // M2=2h/M3=6h/M5=4h all net-profitable and low-correlated,
input int    MaxSetupHours_M5     = 72;   // so one EA instance can now run all three together)
input int    MaxPositionHours     = 72;   // safety timeout force-close (not explicitly requested)
input bool   UseM1                = true;  // set false to disable M1 setups entirely (still lets others run)
input bool   UseM2                = true;
input bool   UseM3                = true;
input bool   UseM5                = true;
input double MinR_Points          = 0;    // skip entry if R (=|MA_Long-entry price| at touch, in points)
                                           // is below this -- filters out setups where the pullback barely
                                           // reached MA_Long, which give a tiny R and are more likely just
                                           // noise. 0 = no filter (matches earlier behavior).
input double Lots                 = 0.01; // PER TIMEFRAME -- up to 4x this can be open at once (M1+M2+M3+M5)
input bool   EnableLiveOrders     = false; // SAFETY: set true only after checks
input ulong  MagicNumber          = 95014101; // base magic; M1/M2/M3/M5 use MagicNumber+0/+1/+2/+3
input int    MaxDeviationPts      = 50;

#define N_TF 4
ENUM_TIMEFRAMES ENTRY_TFS[N_TF]={PERIOD_M1,PERIOD_M2,PERIOD_M3,PERIOD_M5};
bool TFEnabled[N_TF]; // set from UseM1/UseM2/UseM3/UseM5 in OnInit
int  MaxSetupHoursArr[N_TF]; // set from MaxSetupHours_M1/M2/M3/M5 in OnInit

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

// Per-timeframe open-position state -- up to N_TF (4: M1/M2/M3/M5) positions can be open concurrently.
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

   for(int k=0;k<N_TF;k++)
   {
      if(!TFEnabled[k]) continue;
      datetime expire=t+MaxSetupHoursArr[k]*3600;
      int n=ArraySize(setups); ArrayResize(setups,n+1);
      setups[n].signal_time=sig;
      setups[n].expire_time=expire;
      setups[n].dir=dir;
      setups[n].tf=k;
      setups[n].phase=PHASE_WAIT_MA120;
   }
   Log("SETUP_ARMED",(dir==1?"BUY":"SELL")+string(" from H1 ")+(dir==1?"BULL":"BEAR")+
       " | watching enabled timeframes for MA"+IntegerToString(MA_Long)+" touch");
}

bool OpenAtBB(int dir,int tf,double maLongAtTouch,string bandLabel,datetime setup_expire,MqlTick &tick)
{
   ulong old; if(OwnPosition(tf,old)) return false; // MAX1 per timeframe

   double entry=(dir==+1?tick.ask:tick.bid);
   double R=MathAbs(maLongAtTouch-entry);
   double minR=MathMax(_Point,MinR_Points*_Point);
   if(R<=minR)
   {
      Log("ENTRY_SKIPPED","R too small ("+DoubleToString(R,_Digits)+" <= min "+DoubleToString(minR,_Digits)+
          ") tf="+EnumToString(ENTRY_TFS[tf]));
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

      // PHASE_WAIT_BB. BB4 (4-bar, dev4.0) is NOT always the wider/farther band -- with only
      // 4 bars of history its width floats independently of BB20's (20-bar, dev2.0), so either
      // one can be nearer at a given moment. V5's band-tagged results showed BB4 entries
      // consistently underperform BB20 entries, so BB20 always has priority; BB4 is only used
      // as a fallback (and only if AllowBB4Entry=true) when it triggers WITHOUT BB20 also being
      // touched at that moment.
      bool touchedBB20=(dir==+1 ? tick.bid<=cur_e_l20[tf] : tick.ask>=cur_e_u20[tf]);
      bool touchedBB4=(dir==+1 ? tick.bid<=cur_e_l4[tf] : tick.ask>=cur_e_u4[tf]);
      bool enter=touchedBB20 || (AllowBB4Entry && touchedBB4);
      if(enter)
      {
         string bandLabel=touchedBB20?"BB20":"BB4";
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
      if(TP_OppositeFarther)
      {
         // Whichever of the opposite BB20/BB4 is currently farther away -- recomputed every
         // bar since which one is farther can flip over time (BB4's width floats independently).
         double target=(managed_dir[tf]==+1 ? MathMax(cur_e_u20[tf],cur_e_u4[tf])
                                             : MathMin(cur_e_l20[tf],cur_e_l4[tf]));
         bool tp_hit=(managed_dir[tf]==+1 ? px>=target : px<=target);
         if(tp_hit){ ClosePosition(tf,"TP_OPPOSITE_FARTHER"); continue; }
      }
      else if(TP_OppositeBB20)
      {
         // BUY entered at lower BB20/BB4 -> TP at upper BB20 (opposite band). SELL mirrors.
         double target=(managed_dir[tf]==+1?cur_e_u20[tf]:cur_e_l20[tf]);
         bool tp_hit=(managed_dir[tf]==+1 ? px>=target : px<=target);
         if(tp_hit){ ClosePosition(tf,"TP_OPPOSITE_BB20"); continue; }
      }
      else if(TP_OppositeBB4)
      {
         // BUY entered at lower BB20/BB4 -> TP at upper BB4 (opposite extreme). SELL mirrors.
         double target=(managed_dir[tf]==+1?cur_e_u4[tf]:cur_e_l4[tf]);
         bool tp_hit=(managed_dir[tf]==+1 ? px>=target : px<=target);
         if(tp_hit){ ClosePosition(tf,"TP_OPPOSITE_BB4"); continue; }
      }
      else
      {
         bool tp_hit=(managed_dir[tf]==+1 ? px>=cur_ma_short[tf] : px<=cur_ma_short[tf]);
         if(tp_hit){ ClosePosition(tf,"TP_MA_SHORT"); continue; }
      }
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
      Print("MA120PULLBACK INIT FAILED: HEDGING account required (up to 4 concurrent M1/M2/M3/M5 positions).");
      return INIT_FAILED;
   }

   TFEnabled[0]=UseM1; TFEnabled[1]=UseM2; TFEnabled[2]=UseM3; TFEnabled[3]=UseM5;
   MaxSetupHoursArr[0]=MaxSetupHours_M1; MaxSetupHoursArr[1]=MaxSetupHours_M2;
   MaxSetupHoursArr[2]=MaxSetupHours_M3; MaxSetupHoursArr[3]=MaxSetupHours_M5;

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

   Log("START","BUILD=v12_per_tf_setup_hours | EntryTFs(enabled)="+(UseM1?"M1 ":"")+(UseM2?"M2 ":"")+(UseM3?"M3 ":"")+(UseM5?"M5":"")+
       " | MaxSetupHours(M1/M2/M3/M5)="+IntegerToString(MaxSetupHours_M1)+"/"+IntegerToString(MaxSetupHours_M2)+
       "/"+IntegerToString(MaxSetupHours_M3)+"/"+IntegerToString(MaxSetupHours_M5)+
       " | MA_Long="+IntegerToString(MA_Long)+
       " | MA_Short="+IntegerToString(MA_Short)+" | StopLoss_R="+DoubleToString(StopLoss_R,2)+
       " | MinR_Points="+DoubleToString(MinR_Points,1)+
       " | Lots="+DoubleToString(Lots,2)+
       " | AllowBB4Entry="+(AllowBB4Entry?"true":"false")+" | TP_OppositeBB4="+(TP_OppositeBB4?"true":"false")+
       " | TP_OppositeBB20="+(TP_OppositeBB20?"true":"false")+" | TP_OppositeFarther="+(TP_OppositeFarther?"true":"false")+
       " | BaseMagic="+IntegerToString((int)MagicNumber)+" (M1/M2/M3/M5 = base+0/+1/+2/+3)"+
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
