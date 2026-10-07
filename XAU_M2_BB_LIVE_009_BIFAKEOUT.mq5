//+------------------------------------------------------------------+
//| XAU_M2_BB_LIVE_009_BIFAKEOUT.mq5                                  |
//| New mechanical idea (user's own, UNTESTED): after a "더블비"        |
//| (dual-band BB20+BB4 touch) signal candle, watch for a WEAK same-   |
//| direction continuation candle, then enter the OPPOSITE direction   |
//| if the very next candle reverses sharply -- a "failed             |
//| continuation / exhaustion" fade, not a pivot/neckline pattern like |
//| 008. Completely independent of 008's logic.                       |
//|                                                                    |
//| Mechanical definition:                                             |
//|  BAR 1 ("더블비"): a dual-band signal candle, same detection as     |
//|    001/005/007 (bull: close>open, high>=BB20-upper AND              |
//|    high>=BB4-upper; bear: mirrored on the lower bands). R = this    |
//|    candle's body, |close-open|. This is the pattern anchor; its     |
//|    own direction is called biDir (+1 bull-bi, -1 bear-bi).          |
//|  BAR 2 (continuation check): must be the SAME color as biDir, and   |
//|    its close must sit no more than Bar2FractionR*R beyond bar1's    |
//|    close in biDir's own favorable direction (a mild further push,   |
//|    not a strong one). Two timing variants (see UseDelayedBar2Scan   |
//|    below) control WHEN bar 2 is allowed to be checked.              |
//|  BAR 3 (entry trigger): the candle immediately after whichever bar   |
//|    satisfied bar 2. If its close has moved AT LEAST Bar3FractionR*R  |
//|    in the OPPOSITE direction from bar 2's close, enter a trade in    |
//|    that opposite direction at bar 3's close (market). Otherwise the  |
//|    whole setup is discarded -- single-shot, no retry on that bi.     |
//|                                                                      |
//| UseDelayedBar2Scan selects between the user's two requested          |
//| variants, both built on the same mechanics above:                    |
//|  1안 (false, default): bar 2 MUST be the very next candle after bar  |
//|    1. Any other outcome (wrong color, or exceeds Bar2FractionR*R)    |
//|    discards the setup immediately -- no further waiting.             |
//|  2안 (true): bar 2 is NOT checked until DelayedBar2StartOffset bars   |
//|    after bar 1 (default 5, i.e. scanning starts at the 6th candle    |
//|    counting bar 1 itself as the 1st). From there, every subsequent    |
//|    candle is checked against the same bar-2 condition (color + cap)  |
//|    until one matches or MaxBar2ScanBars is exceeded (give up, no     |
//|    entry). Once a match is found, bar 3 is checked exactly the same  |
//|    way as in 1안 (the very next candle after the matched bar 2).      |
//|                                                                       |
//| Both variants are UNTESTED.                                          |
//| SL: SLBar2RangeMult (default 1.0) times bar 2's FULL range (high-low, |
//|   body+wick -- a different R from bar1's body-only R used for the     |
//|   bar2/bar3 trigger checks above), measured as a price distance from  |
//|   the entry fill.                                                     |
//| TP: the current 20-SMA (BB20 basis line) value at entry time, read    |
//|   once and set as a static target -- "20이평 터치". If the 20-SMA     |
//|   isn't on the favorable side of entry (can happen since this is a    |
//|   mean-reversion entry right after a sharp move), falls back to the   |
//|   near BB4 (원비/44band) edge in the favorable direction instead      |
//|   ("원비 터치"), also a static one-time read. If even THAT isn't      |
//|   favorable (rare), the entry is skipped (TP_TARGET_INVALID).         |
//| MinR_Points: minimum bar1 (더블비) body size, in points, to even start |
//|   tracking a pattern -- same convention as 001/005/007/008.           |
//| No pivot/neckline/ATR machinery from 008 is used here at all.         |
//| Single in-flight position (own Magic, MAX1). A new 더블비 is only     |
//| detected while idle (stage 0) -- one found mid-pattern is ignored    |
//| until the current bi resolves or times out (kept simple; a bi that   |
//| resolves/fails on the exact same bar a new one would start is missed |
//| for that one bar, a rare edge case, not specially handled).          |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input ENUM_TIMEFRAMES Timeframe   = PERIOD_M2; // signal timeframe
input double Lots                 = 0.1; // Lot size
input double Bar2FractionR        = 0.5; // Max favorable continuation from bar1's close, as R multiple (bar2 condition, UNTESTED)
input double Bar3FractionR        = 0.5; // Min reversal move from bar2's close, as R multiple (bar3 entry trigger, UNTESTED)
input bool   UseDelayedBar2Scan   = false; // false=1안 (bar2 must be the very next candle), true=2안 (scan for bar2 starting DelayedBar2StartOffset bars after bar1)
input int    DelayedBar2StartOffset = 5; // 2안 only: bars after bar1 before bar2-matching starts (default 5 = scanning begins at the 6th candle counting bar1 as the 1st)
input int    MaxBar2ScanBars      = 15; // 2안 only: give up if no matching bar2 found within this many bars after bar1
input double SLBar2RangeMult      = 1.0; // SL distance as a multiple of bar2's FULL range (high-low, body+wick), from entry (UNTESTED)
input int    MinR_Points          = 300; // Min bar1 (더블비) body (points) to track a pattern, 0=no filter
input bool   AllowBuyEntry        = true; // Allow entries reversing a bear-더블비 (BUY)
input bool   AllowSellEntry       = true; // Allow entries reversing a bull-더블비 (SELL)
input ulong  MagicNumber          = 95016109; // Magic number
input int    MaxDeviationPts      = 50; // Max price deviation (points)
input bool   EnableLiveOrders     = false; // Enable live orders

int hBB20=INVALID_HANDLE,hBB4=INVALID_HANDLE;
datetime last_bar=0;
int f_log=INVALID_HANDLE;
int g_barCounter=0;

// -- single-slot "bi" (더블비) pattern state machine: 0=idle, 1=waiting for bar2, 2=bar2 found waiting for bar3
int    g_biStage=0;
int    g_biDir=0;          // original 더블비 direction, +1 bull-bi / -1 bear-bi (entry dir = -g_biDir)
double g_biClose1=0,g_biR=0;
int    g_biBar1Index=0;
double g_biClose2=0,g_biHigh2=0,g_biLow2=0;
int    g_biBar2Index=0;

// -- outcome tracking (one in-flight position at a time, own-Magic MAX1) --
ulong  g_trackTicket=0;
double g_trackEntry=0,g_trackR=0,g_trackSLRange=0;
int    g_trackDir=0;
string g_trackTag="";

string TS(datetime t){ return TimeToString(t,TIME_DATE|TIME_SECONDS); }

void Log(string event,string detail="")
{
   Print("XAU_M2_BB_LIVE_009_BIFAKEOUT | ",event," | ",detail);
   if(f_log!=INVALID_HANDLE){ FileWrite(f_log,TS(TimeCurrent()),event,detail); FileFlush(f_log); }
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

void ResetBi()
{
   g_biStage=0; g_biDir=0; g_biClose1=0; g_biR=0; g_biBar1Index=0;
   g_biClose2=0; g_biHigh2=0; g_biLow2=0; g_biBar2Index=0;
}

void OpenTrade(int dir,double biR,double slRange,string tag)
{
   if(HasOurPosition()){ Log("ENTRY_SKIPPED","own-Magic position already exists | "+tag); return; }

   MqlTick q; if(!SymbolInfoTick(_Symbol,q)){ Log("ORDER_FAIL","no current tick"); return; }
   double ref=(dir==+1 ? q.ask : q.bid);

   double sma20buf[1];
   if(CopyBuffer(hBB20,0,1,1,sma20buf)!=1){ Log("ORDER_FAIL","no 20-SMA value | "+tag); return; }
   double sma20=sma20buf[0];
   bool sma20Valid=(dir==+1) ? (sma20>ref) : (sma20<ref);

   double tp=0; string tpSource="";
   if(sma20Valid)
   {
      tp=sma20; tpSource="20SMA";
   }
   else
   {
      // 20-SMA isn't on the favorable side (can happen right after a sharp
      // reversal move) -- fall back to the near BB4 (원비/44band) edge in
      // the favorable direction instead.
      double bb4up[1],bb4lo[1];
      if(CopyBuffer(hBB4,1,1,1,bb4up)!=1 || CopyBuffer(hBB4,2,1,1,bb4lo)!=1)
      { Log("ORDER_FAIL","no BB4 value | "+tag); return; }
      double bb4edge=(dir==+1) ? bb4up[0] : bb4lo[0];
      bool bb4Valid=(dir==+1) ? (bb4edge>ref) : (bb4edge<ref);
      if(!bb4Valid)
      {
         Log("TP_TARGET_INVALID","sma20="+DoubleToString(sma20,_Digits)+" bb4edge="+DoubleToString(bb4edge,_Digits)+
             " ref="+DoubleToString(ref,_Digits)+" | "+tag);
         return;
      }
      tp=bb4edge; tpSource="BB4";
   }

   double sl=ref-dir*SLBar2RangeMult*slRange;

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
          " slRange="+DoubleToString(slRange,_Digits)+" SL="+DoubleToString(sl,_Digits)+
          " TP="+DoubleToString(tp,_Digits)+" tpSource="+tpSource+" | "+tag);
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
      Log("ENTRY_OK",(dir==1?"BUY":"SELL")+" slRange="+DoubleToString(slRange,_Digits)+
          " SL="+DoubleToString(sl,_Digits)+" TP="+DoubleToString(tp,_Digits)+" tpSource="+tpSource+" | "+tag);
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong tk=PositionGetTicket(i);
         if(tk==0 || !PositionSelectByTicket(tk)) continue;
         if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
         g_trackTicket=tk; g_trackEntry=ref; g_trackR=biR; g_trackSLRange=slRange; g_trackDir=dir; g_trackTag=tag;
         break;
      }
   }
}

void CheckNewBar()
{
   datetime t=iTime(_Symbol,Timeframe,0);
   if(t==0 || t==last_bar) return;
   last_bar=t;
   g_barCounter++;

   double o=iOpen(_Symbol,Timeframe,1),c=iClose(_Symbol,Timeframe,1),
          h=iHigh(_Symbol,Timeframe,1),l=iLow(_Symbol,Timeframe,1);

   // ---------------- Stage 0: waiting for a fresh 더블비 (bar1) ----------------
   if(g_biStage==0)
   {
      double up20[1],lo20[1],up4[1],lo4[1];
      if(CopyBuffer(hBB20,1,1,1,up20)!=1 || CopyBuffer(hBB20,2,1,1,lo20)!=1 ||
         CopyBuffer(hBB4,1,1,1,up4)!=1   || CopyBuffer(hBB4,2,1,1,lo4)!=1)
      { Log("COPYBUFFER_FAIL","BB bands"); return; }

      int sigdir=0;
      if(c>o && h>=up20[0] && h>=up4[0]) sigdir=+1;       // bull 더블비
      else if(c<o && l<=lo20[0] && l<=lo4[0]) sigdir=-1;  // bear 더블비
      if(sigdir==0) return;

      double r1=MathAbs(c-o);
      if(MinR_Points>0 && r1<MinR_Points*_Point)
      { Log("SIGNAL_SKIPPED","R too small | R="+DoubleToString(r1,_Digits)); return; }

      g_biStage=1; g_biDir=sigdir; g_biClose1=c; g_biR=r1; g_biBar1Index=g_barCounter;
      Log("BI_PIVOT1",(sigdir==1?"BULL":"BEAR")+" close1="+DoubleToString(c,_Digits)+" R="+DoubleToString(g_biR,_Digits));
      return;
   }

   // ---------------- Stage 1: waiting for bar2 ----------------
   if(g_biStage==1)
   {
      if(g_biR<=0){ ResetBi(); return; }
      int barsSinceBar1=g_barCounter-g_biBar1Index;
      bool checkThisBar=false;

      if(!UseDelayedBar2Scan) // 1안
      {
         if(barsSinceBar1==1) checkThisBar=true;
         else { ResetBi(); return; } // defensive; should not happen in normal operation
      }
      else // 2안
      {
         if(barsSinceBar1<DelayedBar2StartOffset) return; // still in the skip window
         if(barsSinceBar1>DelayedBar2StartOffset+MaxBar2ScanBars)
         { Log("BI_BAR2_TIMEOUT","no matching bar2 within scan window"); ResetBi(); return; }
         checkThisBar=true;
      }

      if(checkThisBar)
      {
         bool sameColor=(g_biDir==+1) ? (c>o) : (c<o);
         double distFav=(g_biDir==+1) ? (c-g_biClose1) : (g_biClose1-c);
         bool withinCap=(distFav>=0 && distFav<=Bar2FractionR*g_biR);

         if(sameColor && withinCap)
         {
            g_biStage=2; g_biClose2=c; g_biHigh2=h; g_biLow2=l; g_biBar2Index=g_barCounter;
            Log("BI_BAR2_OK","close2="+DoubleToString(c,_Digits)+" distFavR="+DoubleToString(distFav/g_biR,3)+
                " range2="+DoubleToString(h-l,_Digits)+" barsSinceBar1="+IntegerToString(barsSinceBar1));
         }
         else if(!UseDelayedBar2Scan)
         {
            Log("BI_BAR2_FAIL","sameColor="+(sameColor?"true":"false")+" distFavR="+DoubleToString(distFav/g_biR,3));
            ResetBi();
         }
         // 2안, no match this bar: keep scanning silently until a match or timeout
      }
      return;
   }

   // ---------------- Stage 2: bar3 = the very next candle after bar2 ----------------
   if(g_biStage==2)
   {
      int barsSinceBar2=g_barCounter-g_biBar2Index;
      if(barsSinceBar2!=1){ ResetBi(); return; } // defensive; should not happen in normal operation

      double distRev=(g_biDir==+1) ? (g_biClose2-c) : (c-g_biClose2);
      bool trigger=(distRev>=Bar3FractionR*g_biR);

      if(trigger)
      {
         int entryDir=-g_biDir;
         string tag=(g_biDir==1 ? "FAKEOUT_BULLBI_SELL" : "FAKEOUT_BEARBI_BUY");
         Log("BI_BAR3_TRIGGER","close3="+DoubleToString(c,_Digits)+" distRevR="+DoubleToString(distRev/g_biR,3)+" | "+tag);
         bool allowed=(entryDir==+1 ? AllowBuyEntry : AllowSellEntry);
         if(allowed) OpenTrade(entryDir,g_biR,g_biHigh2-g_biLow2,tag);
         else        Log("ENTRY_SKIPPED","direction disabled by Allow*Entry input | "+tag);
      }
      else
         Log("BI_BAR3_NOENTRY","close3="+DoubleToString(c,_Digits)+" distRevR="+DoubleToString(distRev/g_biR,3));

      ResetBi();
      return;
   }
}

int OnInit()
{
   hBB20=iBands(_Symbol,Timeframe,20,0,2.0,PRICE_CLOSE);
   hBB4 =iBands(_Symbol,Timeframe,4,0,4.0,PRICE_OPEN);
   if(hBB20==INVALID_HANDLE || hBB4==INVALID_HANDLE) return INIT_FAILED;

   f_log=FileOpen("XAU_M2_BB_LIVE_009_BIFAKEOUT_LOG.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
   if(f_log!=INVALID_HANDLE)
   {
      FileSeek(f_log,0,SEEK_END);
      if(FileTell(f_log)==0) FileWrite(f_log,"TIME","EVENT","DETAIL");
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(MaxDeviationPts);
   trade.SetTypeFillingBySymbol(_Symbol);

   Log("START","TF="+EnumToString(Timeframe)+
       " | Bar2FractionR="+DoubleToString(Bar2FractionR,2)+" Bar3FractionR="+DoubleToString(Bar3FractionR,2)+
       " | UseDelayedBar2Scan="+(UseDelayedBar2Scan?"true(2안)":"false(1안)")+
       " DelayedBar2StartOffset="+IntegerToString(DelayedBar2StartOffset)+" MaxBar2ScanBars="+IntegerToString(MaxBar2ScanBars)+
       " | SLBar2RangeMult="+DoubleToString(SLBar2RangeMult,2)+" TP=20SMA MinR_Points="+DoubleToString(MinR_Points,1)+
       " | AllowBuyEntry="+(AllowBuyEntry?"true":"false")+" AllowSellEntry="+(AllowSellEntry?"true":"false")+
       " | Lots="+DoubleToString(Lots,2)+" | Magic="+IntegerToString((int)MagicNumber)+
       " | orders="+(EnableLiveOrders?"ENABLED":"DRY"));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(f_log!=INVALID_HANDLE){ FileFlush(f_log); FileClose(f_log); }
   if(hBB20!=INVALID_HANDLE) IndicatorRelease(hBB20);
   if(hBB4!=INVALID_HANDLE)  IndicatorRelease(hBB4);
}

void OnTick()
{
   CheckNewBar();
}

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if((ulong)HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=MagicNumber) return;
   if(HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=_Symbol) return;
   if((long)HistoryDealGetInteger(trans.deal,DEAL_ENTRY)!=DEAL_ENTRY_OUT) return;

   ulong posId=(ulong)HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID);
   if(g_trackTicket==0 || posId!=g_trackTicket) return;

   double profit=HistoryDealGetDouble(trans.deal,DEAL_PROFIT)+HistoryDealGetDouble(trans.deal,DEAL_SWAP)+
                 HistoryDealGetDouble(trans.deal,DEAL_COMMISSION);
   string outcome=(profit>0?"WIN":"LOSS");
   Log("MAE_OUTCOME","outcome="+outcome+" profit="+DoubleToString(profit,2)+" biR="+DoubleToString(g_trackR,_Digits)+
       " slRange="+DoubleToString(g_trackSLRange,_Digits)+" | "+g_trackTag);
   g_trackTicket=0;
}
//+------------------------------------------------------------------+
