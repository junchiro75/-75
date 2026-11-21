//+------------------------------------------------------------------+
//| XAU_M3_MATOUCHGRID_test.mq5                                       |
//+------------------------------------------------------------------+
//| TEST FORK (2026-11-21) -- NOT the live file. FIRST-PASS GUESS,     |
//| COMPLETELY UNTESTED (no backtest run yet).                         |
//|                                                                     |
//| Full-auto port of the user-uploaded MATouchGridManual_EA.mq5 (a     |
//| semi-manual, button-driven tool): M3-chart 120-SMA touch entry +    |
//| a 5-leg DCA grid, shared single stop-loss across the whole basket.  |
//| That tool required a human to press [ON] (to arm direction), wait   |
//| for a touch to fire the first market entry, then TYPE a grid "step" |
//| into a text box before the grid/SL would be placed; it had NO take- |
//| profit at all (purely discretionary/manual exit).                   |
//|                                                                     |
//| This file automates all three human actions:                       |
//|  1) ARM: whenever flat, automatically evaluate current bid vs the   |
//|     M3 120-SMA (MAPeriod) -- bid>MA => arm BUY (wait for price to   |
//|     drop down and touch the MA); bid<MA => arm SELL (wait for price |
//|     to rise up and touch it). Same rule as the manual tool's [ON]   |
//|     button, just evaluated every tick instead of on a click.        |
//|  2) STEP: the manual tool's typed step-size box is replaced by      |
//|     UseATRStep (step=ATR(StepATRPeriod)*StepATRMult, price units)   |
//|     or, if false, a fixed GridStepPoints. The manual tool's author   |
//|     described eyeballing recent volatility and re-typing the step    |
//|     by hand (~50pt variance range / 5 steps = 10pt step in their own |
//|     example, matching GridStepPoints=10's default here) -- ATR is    |
//|     the natural automatic stand-in for that eyeballed volatility     |
//|     read, but the StepATRMult=0.2 default is an UNVALIDATED guess.   |
//|  3) EXIT: the manual tool had NO take-profit mechanism at all        |
//|     (purely discretionary). UseBasketTrailStop is a NEW addition,    |
//|     not in the original tool, needed to make this backtestable:      |
//|     once the basket's volume-weighted average entry price has moved  |
//|     TrailTriggerStep steps favorably, arm a trailing stop that keeps |
//|     TrailDistanceStep steps behind price, applied as the SAME shared |
//|     SL across every open leg (and every still-pending grid order),   |
//|     mirroring the one-shared-SL structure the manual tool already    |
//|     used for its hard stop. This exit design is an unvalidated first |
//|     guess -- the original author's own philosophy (per the attached  |
//|     "3분 장기이평 매매" cafe post, read the same session this file was |
//|     requested) is closer to "give it one solid swing target and take |
//|     it manually," which a fixed trailing distance only approximates. |
//|                                                                     |
//| PRESERVED EXACTLY from the manual tool: grid legs are placed in the  |
//| ADVERSE direction from the first fill (P0) -- i.e. a DCA/martingale  |
//| ladder, NOT scaling out with the trend -- at levels P0-dir*k*step    |
//| for k=1..GridCount, with ONE shared stop-loss for the entire basket   |
//| at P0-dir*SLMult*step (GridCount=5, SLMult=5.5 defaults ported        |
//| unchanged). A grid leg whose level has already been passed by price  |
//| at placement time fills at market instead of as a pending order,      |
//| exactly like the manual tool.                                        |
//|                                                                     |
//| NOT YET IMPLEMENTED (flagged, not built): the cafe article the user  |
//| shared alongside this request ("3분 장기이평 매매") spends most of its  |
//| length on WHICH long-MA touches to skip -- near a prior high/low,     |
//| near a W/M double top/bottom, right after a higher-timeframe outsize  |
//| candle -- calling the common thread "변곡의 초입" (the early stage of  |
//| a reversal). This file has NO such filter; it takes every touch.     |
//| Adding one is a natural next iteration once this first pass has a     |
//| baseline backtest to compare against.                                 |
//|                                                                     |
//| Also not built: a re-arm cooldown. The moment a basket fully closes   |
//| (flat), the very next tick re-arms immediately off current price vs   |
//| MA -- there is no minimum gap enforced between baskets. If a          |
//| backtest shows pathological immediate-re-entry churn right at the     |
//| shared-SL exit price, a CooldownBars input is the straightforward      |
//| fix, deferred until that's actually observed.                         |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input group "=== Signal: long-term MA touch (ported from MATouchGridManual_EA.mq5, now full-auto, TEST/untested) ==="
input ENUM_TIMEFRAMES Timeframe  = PERIOD_M3; // signal timeframe (manual tool was fixed M3) (TEST, untested)
input int    MAPeriod            = 120;  // long-term SMA period (TEST, untested, ported from manual tool default)
input int    MaxWaitBars         = 0;    // cancel WAIT and re-evaluate direction after N new signal-TF bars with no touch (0 = never cancel, matches manual tool's indefinite wait) (TEST, untested)

input group "=== Grid step sizing (manual tool had a user-typed box; this automates it, TEST/untested) ==="
input bool   UseATRStep          = true;  // true: step=ATR(StepATRPeriod)*StepATRMult (price units); false: fixed GridStepPoints (TEST, untested)
input int    StepATRPeriod       = 14;    // (TEST, untested)
input double StepATRMult         = 0.2;   // first-guess only, no backtest run yet (TEST, untested)
input double GridStepPoints      = 10;    // used only when UseATRStep=false, in points (matches manual tool author's own "10포인트 간격" example) (TEST, untested)

input group "=== Grid/basket structure (same semantics as MATouchGridManual_EA.mq5) ==="
input double Lots                = 0.1;   // lot size, SAME for every leg (first entry + all grid legs) -- max basket exposure = Lots*(1+GridCount) (TEST, untested)
input int    GridCount            = 5;    // additional DCA legs beyond the first entry, ported unchanged from manual tool default (TEST, untested)
input double SLMult               = 5.5;  // shared basket SL = P0 -/+ SLMult*step, ALL legs share this one SL, ported unchanged from manual tool default (TEST, untested)

input group "=== Exit automation (NEW -- manual tool had NO take-profit, purely discretionary/manual exit, TEST/untested) ==="
input bool   UseBasketTrailStop   = true;  // first-guess automatic substitute for the manual tool's discretionary exit (TEST, untested)
input double TrailTriggerStep     = 1.0;   // favorable move from basket's volume-weighted avg entry, in steps, to arm trailing (TEST, untested)
input double TrailDistanceStep    = 0.5;   // distance kept behind price once armed, in steps (TEST, untested)

input group "=== Misc ==="
input ulong  MagicNumber          = 95016300; // Magic number (unused by any other model in this repo)
input int    MaxDeviationPts      = 50;    // Max price deviation (points)
input bool   EnableLiveOrders     = false; // Enable live orders

//+------------------------------------------------------------------+
//| State                                                              |
//+------------------------------------------------------------------+
enum ENUM_GSTATE { GS_IDLE=0, GS_WAIT=1, GS_BASKET=2 };
ENUM_GSTATE g_state=GS_IDLE;
int      g_dir=0;          // +1 long basket, -1 short basket
double   g_p0=0;           // first-leg fill price
double   g_step=0;         // step used for this basket (fixed once placed)
double   g_sl=0;           // current shared SL for the whole basket
datetime g_basketOpenTime=0;
int      g_waitBarCount=0;
datetime g_lastSeenBar=0;
bool     g_trailArmed=false;

int hMA=INVALID_HANDLE, hATR=INVALID_HANDLE;
int f_log=INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Utility (ported from MATouchGridManual_EA.mq5)                     |
//+------------------------------------------------------------------+
int LotDigits()
{
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   int d=0;
   while(step<1.0-1e-9 && d<8){ step*=10.0; d++; }
   return d;
}

double NormLot(double lot)
{
   double mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double mx=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double st=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(st<=0) st=0.01;
   lot=MathFloor(lot/st+1e-9)*st;
   return NormalizeDouble(MathMax(mn,MathMin(mx,lot)),LotDigits());
}

double NP(double p){ return NormalizeDouble(p,_Digits); }

double MinStopDistance()
{
   long stops=0,freeze=0;
   SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL,stops);
   SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL,freeze);
   return (double)MathMax(stops,freeze)*_Point;
}

string TS(datetime t){ return TimeToString(t,TIME_DATE|TIME_MINUTES|TIME_SECONDS); }

void Log(string event,string detail="")
{
   Print("XAU_M3_MATOUCHGRID_test | ",event," | ",detail);
   if(f_log!=INVALID_HANDLE){ FileWrite(f_log,TS(TimeCurrent()),event,detail); FileFlush(f_log); }
}

bool GetMA(double &v)
{
   double b[1];
   if(CopyBuffer(hMA,0,0,1,b)<1) return false; // forming/current bar value -- intentional, matches manual tool's live-updating MA touch read
   v=b[0];
   return true;
}

double GetStep()
{
   if(!UseATRStep) return MathMax(_Point,GridStepPoints*_Point);
   double b[1];
   if(CopyBuffer(hATR,0,1,1,b)<1) return MathMax(_Point,GridStepPoints*_Point); // fallback to fixed if ATR unavailable
   double step=b[0]*StepATRMult; // ATR buffer is already in price units, same convention as XAU_M5_PULLBACKTREND_test.mq5's R=ATR
   return MathMax(_Point,step);
}

bool IsMine(ulong magic,string sym){ return magic==MagicNumber && sym==_Symbol; }

int CountPositions()
{
   int c=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0 || !PositionSelectByTicket(t)) continue;
      if(IsMine((ulong)PositionGetInteger(POSITION_MAGIC),PositionGetString(POSITION_SYMBOL))) c++;
   }
   return c;
}

void DeletePendings()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong t=OrderGetTicket(i);
      if(t==0 || !OrderSelect(t)) continue;
      if(!IsMine((ulong)OrderGetInteger(ORDER_MAGIC),OrderGetString(ORDER_SYMBOL))) continue;
      if(!trade.OrderDelete(t))
         Log("PENDING_DELETE_FAIL",IntegerToString((int)trade.ResultRetcode())+" #"+IntegerToString((long)t));
   }
}

void CloseAllPositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0 || !PositionSelectByTicket(t)) continue;
      if(!IsMine((ulong)PositionGetInteger(POSITION_MAGIC),PositionGetString(POSITION_SYMBOL))) continue;
      if(!trade.PositionClose(t))
         Log("CLOSE_FAIL",IntegerToString((int)trade.ResultRetcode())+" #"+IntegerToString((long)t));
   }
}

//+------------------------------------------------------------------+
//| First entry (auto equivalent of manual tool's DoFirstEntry)        |
//+------------------------------------------------------------------+
bool DoFirstEntry()
{
   if(!EnableLiveOrders)
   {
      MqlTick q; if(!SymbolInfoTick(_Symbol,q)) return false;
      g_p0=(g_dir>0?q.ask:q.bid);
      Log("DRY_FIRST_ENTRY",(g_dir>0?"BUY":"SELL")+string(" @~")+DoubleToString(g_p0,_Digits));
      return true;
   }

   double lot=NormLot(Lots);
   bool ok=(g_dir>0 ? trade.Buy(lot,_Symbol,0.0,0.0,0.0,"MTG_P0") : trade.Sell(lot,_Symbol,0.0,0.0,0.0,"MTG_P0"));
   if(!ok)
   {
      Log("FIRST_ENTRY_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
      return false;
   }

   g_p0=trade.ResultPrice();
   if(g_p0<=0)
   {
      ulong deal=trade.ResultDeal();
      if(deal>0 && HistoryDealSelect(deal)) g_p0=HistoryDealGetDouble(deal,DEAL_PRICE);
   }
   if(g_p0<=0) g_p0=(g_dir>0?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID));

   Log("FIRST_ENTRY_OK",(g_dir>0?"BUY":"SELL")+" @"+DoubleToString(g_p0,_Digits));
   return true;
}

//+------------------------------------------------------------------+
//| Grid placement (auto equivalent of manual tool's PlaceGrid)        |
//+------------------------------------------------------------------+
void PlaceGrid(double step)
{
   g_step=step;
   g_sl=NP(g_p0-g_dir*SLMult*step);
   g_basketOpenTime=TimeCurrent();

   if(!EnableLiveOrders)
   {
      Log("DRY_GRID","P0="+DoubleToString(g_p0,_Digits)+" step="+DoubleToString(step,_Digits)+" SL="+DoubleToString(g_sl,_Digits));
      g_state=GS_BASKET;
      return;
   }

   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID), ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   //--- already past the hard SL at the moment the grid would be placed -> close immediately (matches manual tool)
   if((g_dir>0 && bid<=g_sl) || (g_dir<0 && ask>=g_sl))
   {
      Log("GRID_ALREADY_PAST_SL","closing immediately, SL="+DoubleToString(g_sl,_Digits));
      CloseAllPositions();
      DeletePendings();
      g_state=GS_IDLE;
      return;
   }

   //--- 1) set SL on the first-entry position
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0 || !PositionSelectByTicket(t)) continue;
      if(!IsMine((ulong)PositionGetInteger(POSITION_MAGIC),PositionGetString(POSITION_SYMBOL))) continue;
      if(!trade.PositionModify(t,g_sl,PositionGetDouble(POSITION_TP)))
         Log("GRID_SL_SET_FAIL",IntegerToString((int)trade.ResultRetcode()));
   }

   //--- 2) grid legs 1..GridCount, in the ADVERSE direction from P0
   double lot=NormLot(Lots);
   double minDist=MinStopDistance();
   for(int k=1;k<=GridCount;k++)
   {
      double level=NP(g_p0-g_dir*k*step);
      string cmt=StringFormat("MTG_G%d",k);
      bool ok;
      bool passed=(g_dir>0)?(ask<=level+minDist):(bid>=level-minDist);
      if(passed)
      {
         ok=(g_dir>0 ? trade.Buy(lot,_Symbol,0.0,g_sl,0.0,cmt) : trade.Sell(lot,_Symbol,0.0,g_sl,0.0,cmt));
         Log("GRID_LEG_MARKET",IntegerToString(k)+" level="+DoubleToString(level,_Digits)+" "+(ok?"FILLED":"FAILED"));
      }
      else
      {
         ok=(g_dir>0 ? trade.BuyLimit (lot,level,_Symbol,g_sl,0.0,ORDER_TIME_GTC,0,cmt)
                     : trade.SellLimit(lot,level,_Symbol,g_sl,0.0,ORDER_TIME_GTC,0,cmt));
         Log("GRID_LEG_PENDING",IntegerToString(k)+" level="+DoubleToString(level,_Digits)+" "+(ok?"PLACED":"FAILED"));
      }
      if(!ok) Log("GRID_LEG_RETCODE",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
      bid=SymbolInfoDouble(_Symbol,SYMBOL_BID); ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   }

   g_state=GS_BASKET;
   Log("GRID_COMPLETE","P0="+DoubleToString(g_p0,_Digits)+" step="+DoubleToString(step,_Digits)+" SL="+DoubleToString(g_sl,_Digits));
}

//+------------------------------------------------------------------+
//| Basket-level trailing stop (NEW -- not in the manual tool)         |
//+------------------------------------------------------------------+
void UpdateBasketTrail()
{
   if(!UseBasketTrailStop) return;

   double sumVolPrice=0, sumVol=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0 || !PositionSelectByTicket(t)) continue;
      if(!IsMine((ulong)PositionGetInteger(POSITION_MAGIC),PositionGetString(POSITION_SYMBOL))) continue;
      double vol=PositionGetDouble(POSITION_VOLUME), op=PositionGetDouble(POSITION_PRICE_OPEN);
      sumVol+=vol; sumVolPrice+=vol*op;
   }
   if(sumVol<=0) return;
   double avgEntry=sumVolPrice/sumVol;

   MqlTick q; if(!SymbolInfoTick(_Symbol,q)) return;
   double curPrice=(g_dir>0)?q.bid:q.ask;
   double favSteps=(g_dir>0 ? (curPrice-avgEntry) : (avgEntry-curPrice))/g_step;

   if(!g_trailArmed && favSteps>=TrailTriggerStep)
   {
      g_trailArmed=true;
      Log("BASKET_TRAIL_ARM","favSteps="+DoubleToString(favSteps,3)+" avgEntry="+DoubleToString(avgEntry,_Digits));
   }
   if(!g_trailArmed) return;

   double candidate=NP(curPrice-g_dir*TrailDistanceStep*g_step);
   bool improves=(g_dir>0)?(candidate>g_sl):(candidate<g_sl);
   if(!improves) return;

   double cushion=MinStopDistance()+_Point;
   double sl=candidate;
   if(g_dir>0){ if(sl>q.bid-cushion) sl=q.bid-cushion; }
   else       { if(sl<q.ask+cushion) sl=q.ask+cushion; }
   sl=NP(sl);
   if(g_dir>0 ? sl<=g_sl : sl>=g_sl) return; // cushion clamp wiped out the improvement

   if(!EnableLiveOrders)
   {
      g_sl=sl;
      Log("BASKET_TRAIL_DRY","would move shared SL->"+DoubleToString(sl,_Digits)+" favSteps="+DoubleToString(favSteps,3));
      return;
   }

   bool anyFail=false;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0 || !PositionSelectByTicket(t)) continue;
      if(!IsMine((ulong)PositionGetInteger(POSITION_MAGIC),PositionGetString(POSITION_SYMBOL))) continue;
      if(!trade.PositionModify(t,sl,PositionGetDouble(POSITION_TP))) anyFail=true;
   }
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong t=OrderGetTicket(i);
      if(t==0 || !OrderSelect(t)) continue;
      if(!IsMine((ulong)OrderGetInteger(ORDER_MAGIC),OrderGetString(ORDER_SYMBOL))) continue;
      double op=OrderGetDouble(ORDER_PRICE_OPEN), tp=OrderGetDouble(ORDER_TP);
      if(!trade.OrderModify(t,op,sl,tp,ORDER_TIME_GTC,0)) anyFail=true;
   }
   if(anyFail) Log("BASKET_TRAIL_MOVE_PARTIAL_FAIL","target="+DoubleToString(sl,_Digits));
   g_sl=sl;
   Log("BASKET_TRAIL_MOVED","shared SL->"+DoubleToString(sl,_Digits)+" favSteps="+DoubleToString(favSteps,3));
}

//+------------------------------------------------------------------+
//| Basket close / finalize                                            |
//+------------------------------------------------------------------+
void FinalizeBasketIfFlat()
{
   if(CountPositions()>0) return;
   DeletePendings();

   double basketProfit=0;
   if(g_basketOpenTime>0 && HistorySelect(g_basketOpenTime-1,TimeCurrent()))
   {
      int total=HistoryDealsTotal();
      for(int d=0;d<total;d++)
      {
         ulong dt=HistoryDealGetTicket(d);
         if(dt==0) continue;
         if((ulong)HistoryDealGetInteger(dt,DEAL_MAGIC)!=MagicNumber) continue;
         if(HistoryDealGetString(dt,DEAL_SYMBOL)!=_Symbol) continue;
         basketProfit+=HistoryDealGetDouble(dt,DEAL_PROFIT)+HistoryDealGetDouble(dt,DEAL_SWAP)+HistoryDealGetDouble(dt,DEAL_COMMISSION);
      }
   }

   Log("BASKET_CLOSED","dir="+(g_dir>0?"BUY":"SELL")+" P0="+DoubleToString(g_p0,_Digits)+
       " step="+DoubleToString(g_step,_Digits)+" finalSL="+DoubleToString(g_sl,_Digits)+
       " trailArmed="+(g_trailArmed?"true":"false")+" basketProfit="+DoubleToString(basketProfit,2));

   g_state=GS_IDLE; g_dir=0; g_p0=0; g_step=0; g_sl=0; g_basketOpenTime=0;
   g_trailArmed=false; g_waitBarCount=0;
}

//+------------------------------------------------------------------+
//| Restart recovery (auto equivalent of manual tool's RecoverState)   |
//+------------------------------------------------------------------+
void RecoverState()
{
   ulong firstTicket=0; datetime earliest=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0 || !PositionSelectByTicket(t)) continue;
      if(!IsMine((ulong)PositionGetInteger(POSITION_MAGIC),PositionGetString(POSITION_SYMBOL))) continue;
      datetime ot=(datetime)PositionGetInteger(POSITION_TIME);
      if(earliest==0 || ot<earliest){ earliest=ot; firstTicket=t; }
   }
   if(firstTicket==0){ g_state=GS_IDLE; return; }

   PositionSelectByTicket(firstTicket);
   g_dir=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?1:-1;
   g_p0=PositionGetDouble(POSITION_PRICE_OPEN);
   g_sl=PositionGetDouble(POSITION_SL);
   g_basketOpenTime=earliest;
   g_step=(g_sl>0 && SLMult>0) ? MathAbs(g_p0-g_sl)/SLMult : GetStep();
   g_state=GS_BASKET;
   Log("RECOVERED","dir="+(g_dir>0?"BUY":"SELL")+" P0="+DoubleToString(g_p0,_Digits)+
       " step="+DoubleToString(g_step,_Digits)+" SL="+DoubleToString(g_sl,_Digits));
}

//+------------------------------------------------------------------+
//| Events                                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   hMA =iMA(_Symbol,Timeframe,MAPeriod,0,MODE_SMA,PRICE_CLOSE);
   hATR=iATR(_Symbol,Timeframe,StepATRPeriod);
   if(hMA==INVALID_HANDLE || hATR==INVALID_HANDLE) return INIT_FAILED;

   f_log=FileOpen("XAU_M3_MATOUCHGRID_test_LOG.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
   if(f_log!=INVALID_HANDLE)
   {
      FileSeek(f_log,0,SEEK_END);
      if(FileTell(f_log)==0) FileWrite(f_log,"TIME","EVENT","DETAIL");
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(MaxDeviationPts);
   trade.SetTypeFillingBySymbol(_Symbol);

   Log("START",string("TF=")+EnumToString(Timeframe)+" | MAPeriod="+IntegerToString(MAPeriod)+
       " MaxWaitBars="+IntegerToString(MaxWaitBars)+
       " | UseATRStep="+(UseATRStep?"true":"false")+" StepATRPeriod="+IntegerToString(StepATRPeriod)+
       " StepATRMult="+DoubleToString(StepATRMult,2)+" GridStepPoints="+DoubleToString(GridStepPoints,1)+
       " | Lots="+DoubleToString(Lots,2)+" GridCount="+IntegerToString(GridCount)+" SLMult="+DoubleToString(SLMult,2)+
       " | UseBasketTrailStop="+(UseBasketTrailStop?"true":"false")+" TrailTriggerStep="+DoubleToString(TrailTriggerStep,2)+
       " TrailDistanceStep="+DoubleToString(TrailDistanceStep,2)+
       " | Magic="+IntegerToString((int)MagicNumber)+" | orders="+(EnableLiveOrders?"ENABLED":"DRY"));

   g_state=GS_IDLE;
   RecoverState();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(f_log!=INVALID_HANDLE){ FileFlush(f_log); FileClose(f_log); }
   if(hMA!=INVALID_HANDLE)  IndicatorRelease(hMA);
   if(hATR!=INVALID_HANDLE) IndicatorRelease(hATR);
}

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if((ulong)HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=MagicNumber) return;
   if(HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=_Symbol) return;
   if((long)HistoryDealGetInteger(trans.deal,DEAL_ENTRY)!=DEAL_ENTRY_OUT) return;

   ulong posId=(ulong)HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID);
   double profit=HistoryDealGetDouble(trans.deal,DEAL_PROFIT)+HistoryDealGetDouble(trans.deal,DEAL_SWAP)+HistoryDealGetDouble(trans.deal,DEAL_COMMISSION);
   Log("GRID_LEG_CLOSED","posId="+IntegerToString((long)posId)+" profit="+DoubleToString(profit,2));
}

void OnTick()
{
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;

   switch(g_state)
   {
      case GS_IDLE:
      {
         double ma; if(!GetMA(ma)) return;
         double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
         if(bid>ma) g_dir=1; else if(bid<ma) g_dir=-1; else return;
         g_state=GS_WAIT;
         g_waitBarCount=0;
         g_lastSeenBar=iTime(_Symbol,Timeframe,0);
         Log("ARMED",(g_dir>0?"BUY":"SELL")+" wait for MA touch | bid="+DoubleToString(bid,_Digits)+" ma="+DoubleToString(ma,_Digits));
         return;
      }

      case GS_WAIT:
      {
         if(MaxWaitBars>0)
         {
            datetime curBar=iTime(_Symbol,Timeframe,0);
            if(curBar!=g_lastSeenBar){ g_lastSeenBar=curBar; g_waitBarCount++; }
            if(g_waitBarCount>=MaxWaitBars)
            {
               Log("WAIT_TIMEOUT","bars="+IntegerToString(g_waitBarCount)+" -- re-evaluating direction");
               g_state=GS_IDLE; g_dir=0;
               return;
            }
         }
         double ma; if(!GetMA(ma)) return;
         double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
         bool touched=(g_dir>0)?(bid<=ma):(bid>=ma);
         if(!touched) return;

         if(!DoFirstEntry()) return; // retry next tick
         double step=GetStep();
         PlaceGrid(step);
         return;
      }

      case GS_BASKET:
      {
         FinalizeBasketIfFlat();
         if(g_state==GS_BASKET) UpdateBasketTrail();
         return;
      }
   }
}
//+------------------------------------------------------------------+
