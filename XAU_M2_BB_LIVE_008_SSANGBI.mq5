//+------------------------------------------------------------------+
//| XAU_M2_BB_LIVE_008_SSANGBI.mq5                                    |
//| Mechanical "쌍비" (double-bottom/double-top) entry strategy, first  |
//| from a discretionary gold-trading reference document reviewed      |
//| this project (주노짜앙/지킬 공통분석), now redesigned (v3) after a    |
//| TradingView Pine Script reference ("W/M REVERSAL + MULTI BB + 1M   |
//| SSANGBI PRESET") the user shared turned up two structural gaps in   |
//| v1/v2. Standalone entry signal -- not a filter/exit bolted onto     |
//| 001's existing BB20+BB4 trend/fade logic.                           |
//|                                                                     |
//| v1 (fixed points): n=6,773, WR 37.47%, NET -$12,477.64, PF 0.876,   |
//| MaxDD $12,744.30. REJECTED -- root cause: gold moved ~$2,600 to     |
//| ~$4,100 (+58%) over the backtest window, so fixed-point thresholds  |
//| were badly miscalibrated; the SL floor also dominated almost every  |
//| trade, so the intended "tight structural stop" never actually       |
//| governed sizing.                                                    |
//| v2 (ATR-relative sizing, same shape logic as v1): never backtested  |
//| separately -- superseded by v3 below once the reference script      |
//| revealed the shape logic itself (not just the sizing) was wrong.    |
//|                                                                     |
//| What the reference script does differently, now adopted here:       |
//|  1. TOUCH 1/2 must be genuine PIVOT lows/highs (price strictly       |
//|     below/above PivotLeft bars before AND PivotRight bars after),   |
//|     not just "any bar whose low/high crossed a band" -- v1/v2       |
//|     treated ordinary noise wiggles as touches.                      |
//|  2. CONFIRMATION requires a NECKLINE BREAK: the high (for a W) or    |
//|     low (for an M) BETWEEN the two pivots must be broken by a       |
//|     later close, not just "the second-touch bar itself closed in    |
//|     the reversal direction" -- v1/v2 entered on a guess, not a       |
//|     confirmed break. This was almost certainly the main missing      |
//|     ingredient behind v1's 37% WR.                                   |
//| Kept from this project's own design (the reference script doesn't   |
//| anchor to a band or use Stochastic at all): pivot 1 must still sit   |
//| at/beyond the BB20 band (the "매물대" anchor the source document      |
//| emphasizes), and Stochastic must be oversold/overbought AT pivot 2   |
//| (combining the band/structure condition with the momentum           |
//| condition, per this project's own earlier design choice).           |
//|                                                                      |
//| Mechanical definition (v3):                                          |
//|  1. PIVOT 1: a confirmed pivot low (PivotLeft/PivotRight bars) at or  |
//|     beyond the BB20 lower band (buy) / pivot high at or beyond the    |
//|     BB20 upper band (sell). Start tracking the "live neckline" = the  |
//|     highest high (buy) / lowest low (sell) seen since pivot 1.        |
//|  2. PIVOT 2: a second confirmed pivot low/high, occurring             |
//|     MinPatternBars-MaxPatternBars after pivot 1, within               |
//|     ToleranceATR*ATR of pivot 1's price, AND with Stochastic          |
//|     oversold/overbought at that bar. The neckline freezes at          |
//|     whatever the live neckline reached by then.                       |
//|  3. CONFIRMATION: within MaxConfirmBars after pivot 2, price must      |
//|     CLOSE back through the frozen neckline (above it for a buy,       |
//|     below it for a sell) -- that close is the entry trigger.          |
//|     Invalidated if price closes beyond pivot 1's own extreme first    |
//|     (support/resistance failed) or the window times out.              |
//|  4. ENTRY: at market, right after the confirming bar closes.          |
//|  5. STOP: beyond the tighter of pivot 1/pivot 2's own extreme, minus   |
//|     SLBufferATR*ATR further, floored at MinStopATR*ATR. TARGET:       |
//|     TP_R multiple of that stop distance (R=|entry-SL|).               |
//|                                                                      |
//| Diagnostic fields in MAE_OUTCOME (gapATR, rawR_ATR, flooredR_ATR,    |
//| barsPivot1ToPivot2, barsPivot2ToConfirm) for bucketed tuning.         |
//|                                                                      |
//| v3 RESULT: n=989, WR 40.85%, NET $3,967.74, PF 1.078, MaxDD          |
//| $4,073.53 -- the neckline-break fix flipped this from a clear loser  |
//| (v1: NET -$12,477.64) to a thin net winner, confirming that was the  |
//| main missing piece. Still far short of the reference document's      |
//| claimed high manual win rate, and Recovery Factor <1 (MaxDD > NET)   |
//| means it's fragile. Bucketing the diagnostics found 3 sub-ranges     |
//| that carry nearly all the profit: gapATR 0.1-0.2 (a small but        |
//| non-trivial difference between the two pivots -- NEAR-EXACT matches  |
//| <0.1 ATR apart were net NEGATIVE, -$4,412 over 343 trades, maybe      |
//| just chop rather than a real structure), barsP1toP2>=5 (very fast    |
//| double-touches <5 bars apart were net NEGATIVE, -$2,705 over 446     |
//| trades), and barsP2toConfirm>=4 (neckline breaks confirmed within    |
//| 2-3 bars of pivot 2 were net NEGATIVE, -$1,522 over 117 trades --     |
//| likely whipsaws/false breaks rather than genuine follow-through).    |
//| Applying all three as a post-hoc filter on the SAME v3 data (so this  |
//| is an in-sample estimate, not yet forward-validated) gave n=356, WR   |
//| 43.82%, NET $7,970.16 (+101% vs unfiltered), PF 1.393. MinGapATR,     |
//| the MinPatternBars default (3->5), and MinBarsToConfirm below         |
//| implement these three findings as actual entry gates for a proper    |
//| ground-truth backtest, not just a retroactive filter.                 |
//|                                                                      |
//| v4 RESULT (forward-validated, not in-sample): n=516, WR 42.05%, NET   |
//| $7,768.30 (+95.8% vs v3's $3,967.74), PF 1.280, MaxDD $2,454.45       |
//| (-40% vs v3's $4,073.53 -- an unexpected bonus, Recovery Factor went   |
//| from <1 to ~3.16). The in-sample estimate held up well on fresh data. |
//| Finer bucketing of barsP2toConfirm within the now-allowed >=4 range    |
//| showed PF keeps climbing the longer the neckline stays broken before   |
//| entry (PF 1.28 at >=4 bars, 1.46 at >=8, 1.61 at >=10, 2.22 at >=15,   |
//| though n shrinks from 516 to 71 over that range) -- BUT this surfaced  |
//| a real bug in how MinBarsToConfirm was being checked: it only          |
//| required "the bar where the wait happens to end is ALSO currently      |
//| above the neckline", not that the neckline stayed broken continuously  |
//| the whole time. A break-pullback-rebreak sequence could satisfy it by   |
//| coincidence, and a late entry effectively CHASES price (buying well    |
//| above the original breakout point) rather than confirming genuine      |
//| follow-through -- so part of that PF climb may just reflect bigger R   |
//| from chasing, not real signal quality. Fixed here: g_buyNeckHoldBars/  |
//| g_sellNeckHoldBars now count CONSECUTIVE bars beyond the neckline,      |
//| resetting to 0 on any pullback, so MinBarsToConfirm now means "the      |
//| breakout has held continuously for N bars" and entry still fires at    |
//| the earliest bar that becomes true (not a fixed wait-then-check).      |
//| Still uses MinBarsToConfirm=4 as the input default pending its own      |
//| fresh ground-truth test under this corrected definition.                |
//|                                                                      |
//| v5 bucketing (fresh ground-truth backtests, not retroactive filters,   |
//| since entry timing is path-dependent on MinBarsToConfirm's definition):|
//| ToleranceATR 0.40->0.25, SLBufferATR 0.30->0.15, TP_R 1.5->4.0,         |
//| MaxPatternBars 25->30 all confirmed as new defaults; MinGapATR (0.10), |
//| BandAnchorATR (0.50), MaxConfirmBars (20), MinStopATR (floor never     |
//| binds in the tested range) left unchanged. Result: NET $7,009->$16,132,|
//| PF 1.303->2.114 (n=188, WR 26.06%) -- lower win rate but much better   |
//| R:R from letting winners run further (TP_R=4.0).                       |
//|                                                                      |
//| v6: optional filters ported from a 주노짜앙/지킬 reference document     |
//| (double-checked against the full PDF, not just the two screenshots)   |
//| the user wanted tried to raise the win rate: (1) UseTangleGate --     |
//| the doc's "가단" (17-weighted MA + 20-simple MA, i.e. the BB base      |
//| line) must have crossed >=MinTangleCount times in the lookback before |
//| pivot1 is accepted, since "가단이 꼬이지 않으면 변곡은 나올 수 없다";    |
//| (2) Use17BreakConfirm -- close must also clear the 17-weighted MA,     |
//| not just the neckline, before a hold-bar counts, since "각질에서 잡지   |
//|말고 적어도 17까지 보라" (4-period MA fakeouts are common, 17-period     |
//| ones rarely are); (3) UseHTFCrossGate -- a higher-timeframe (default   |
//| M5) 4/17-weighted-MA pair must be in golden(buy)/dead(sell) state at   |
//| pivot2, since "최소 5분 골든크로스가 나야" is one of the doc's three      |
//| named preconditions for trusting a 쌍비 setup; (4) UseMACDGate -- MACD  |
//| main must sit on the trade's side of its signal line AND the          |
//| histogram must be turning further that way at pivot2, per "맥디가       |
//| 방향을 틀고 교차하는지" from the user's own checklist. The doc's        |
//| "매물대" (volume/supply-demand zone) condition is intentionally NOT     |
//| implemented -- MT5 has no reliable volume-profile data for this, and   |
//| the existing BB20-band anchor (BandAnchorATR) already stands in for    |
//| the document's own admission that "모든 건 다 매물대입니다. 볼밴도"     |
//| (bands themselves count as one of its matter-of-fact 매물대 proxies).   |
//| All four default OFF so the v5-confirmed baseline above reproduces     |
//| exactly; each is independently toggleable for its own ground-truth     |
//| backtest before any combination is tried.                              |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input ENUM_TIMEFRAMES Timeframe   = PERIOD_M2; // signal timeframe
input double Lots                 = 0.1; // Lot size
input int    BBPeriod             = 20; // Bollinger Bands period (the "매물대" band)
input double BBDev                = 2.0; // Bollinger Bands deviation
input int    StochK_Period        = 8; // Stoch %K period
input int    StochD_Period        = 3; // Stoch %D period
input int    StochSlowing         = 3; // Stoch slowing
input double StochOverbought      = 70.0; // Stoch overbought level (pivot-2 condition for sell)
input double StochOversold        = 30.0; // Stoch oversold level (pivot-2 condition for buy)
input int    ATRPeriod            = 14; // ATR period used to scale every distance threshold below
input int    PivotLeft            = 2; // Bars before the pivot that must be less extreme (ported from reference preset)
input int    PivotRight           = 1; // Bars after the pivot that must be less extreme (ported from reference preset)
input int    MinPatternBars       = 5; // Min bars between pivot 1 and pivot 2 (CONFIRMED from v3 bucketing, see header)
input int    MaxPatternBars       = 30; // Max bars between pivot 1 and pivot 2 (CONFIRMED from v5 bucketing: 30 is the NET peak across 15-50 sweep)
input double ToleranceATR         = 0.25; // Max distance between pivot 1 and pivot 2 extremes, as ATR multiple (CONFIRMED from v5 bucketing: 0.25 beats 0.40 on NET/WR/PF/MaxDD)
input double MinGapATR            = 0.10; // Min distance between pivot 1 and pivot 2 extremes, as ATR multiple (CONFIRMED from v3 bucketing, see header)
input double BandAnchorATR        = 0.50; // Max distance pivot 1 may sit short of the BB20 band, as ATR multiple (0=must touch/pierce exactly)
input int    MaxConfirmBars       = 20; // Max bars after pivot 2 to wait for the neckline break
input int    MinBarsToConfirm     = 4; // Min bars after pivot 2 before a neckline break is accepted (CONFIRMED from v3 bucketing, see header)
input double NecklineBreakBufferATR = 0.0; // Extra buffer beyond the neckline required for a break, as ATR multiple
input double SLBufferATR          = 0.15; // Extra buffer beyond pivot 1/2's tighter extreme for the stop, as ATR multiple (CONFIRMED from v5 bucketing: 0.15 beats 0.30 on NET/WR/PF/MaxDD)
input double TP_R                 = 4.0; // Take profit as a multiple of the stop distance (R) (CONFIRMED from v5 bucketing: 4.0 is the NET/PF peak across 1.0-5.0 sweep)
input double MinStopATR           = 1.0; // Floor on the stop distance, as ATR multiple, 0=no floor

input bool   UseTangleGate        = false; // Require the 17-weighted/20-simple MA pair ("가단") to have crossed >=MinTangleCount times before pivot1 is accepted
input int    WMA17Period          = 17; // Period of the 17-weighted MA ("가단"'s fast leg; also the fakeout-filter/target MA)
input int    TangleLookbackBars   = 30; // Bars scanned backward from pivot1 for WMA17/SMA20 crossovers
input int    MinTangleCount       = 2; // Min WMA17/SMA20 crossovers required in that lookback for the tangle gate to pass
input bool   Use17BreakConfirm    = false; // Also require the close to be beyond WMA17 (not just the neckline) before counting a neckline-hold bar -- targets the "각질에서 잡지 말고 17까지 보라" fakeout filter
input bool   UseHTFCrossGate      = false; // Require a higher-timeframe fast/slow WMA pair to be in golden(buy)/dead(sell) cross state at pivot2
input ENUM_TIMEFRAMES HTFTimeframe = PERIOD_M5; // Higher timeframe for the cross gate (source material: "최소 5분봉 골든/데드크로스")
input int    HTFFastPeriod        = 4; // HTF fast WMA period ("4가중")
input int    HTFSlowPeriod        = 17; // HTF slow WMA period ("17가중")
input bool   UseMACDGate          = false; // Require MACD main/signal relationship and histogram direction to agree with trade direction at pivot2
input int    MACDFastPeriod       = 12; // MACD fast EMA period
input int    MACDSlowPeriod       = 26; // MACD slow EMA period
input int    MACDSignalPeriod     = 9; // MACD signal period

// -- 매물대 (supply/demand zone) anchor, ported from the 주노짜앙/지킬 reference -
// doc + [매물대]/HHJ TradingView scripts, same infrastructure as 001 M2's
// UseSupplyZoneFilter. On 001, a simple distance-based TREND block did NOT
// show a robust, replicated edge (see that file's header) -- here it is
// applied differently: as an ADDITIONAL required condition on pivot1 itself
// (stacked onto the existing BB20 band anchor via AND), since 008's whole
// premise is that pivot1 sits at a 매물대 already; this tests whether a
// RICHER zone definition (session boxes, day high/low, prev NY high/low)
// makes that anchor more selective/reliable than BB20 alone. Default OFF so
// the confirmed baseline reproduces exactly.
input bool   UseSupplyZoneAnchor   = false; // Also require pivot1 within SupplyZoneATR of >=1 enabled 매물대 zone level (stacks onto BandAnchorATR, does not replace it)
input double SupplyZoneATR         = 0.5; // Proximity threshold, as ATR(Timeframe) multiple
input bool   UseAsiaBoxZone        = true; // Include the Asia-session opening-hour candle's high/low
input int    AsiaOpenHourKST       = 8; // KST hour whose candle defines the Asia session open box
input bool   UseNYBoxZone          = true; // Include the NY/US-session opening-hour candle's high/low
input double NYOpenHourKST         = 22.5; // KST hour (decimal) whose candle defines the NY session open box
input bool   UseTodayHighLowZone   = true; // Include today's running high/low (so far, KST calendar day)
input bool   UsePrevDayHighLowZone = true; // Include the previous KST calendar day's high/low
input bool   UsePrevNYHighLowZone  = true; // Include the previous day's NY-session-window high/low
input double NYSessionStartHourKST = 20.0; // KST hour (decimal) the NY session window starts (wraps past midnight)
input double NYSessionEndHourKST   = 6.0; // KST hour (decimal) the NY session window ends

// -- v7 redesign, per the user's own re-think after UseTangleGate/Use17BreakConfirm/
// UseSupplyZoneAnchor all failed to beat the baseline: question whether the FIXED
// ATR-buffered stop + fixed TP_R target were the wrong shape to begin with, vs the
// source material's own structural stop (pivot extreme, no padding) and dynamic
// target (20-MA or the nearest 원비 band edge, whichever is CLOSER). Also adds a
// 4-weighted/17-weighted MA "올라타기" confirmation at entry, per "4가중과 17선
// 확인". Each independently toggleable, default OFF so the confirmed baseline
// reproduces exactly.
input bool   UseRawPivotStop      = false; // SL = the more extreme pivot exactly (no SLBufferATR, no MinStopATR floor) -- "손절은 피봇1/2 중 더 고점/저점인 봉"
input bool   UseDynamicTP         = false; // TP = whichever is CLOSER of {20-SMA, nearest 원비(44/4 band) edge} in the favorable direction, instead of TP_R*R -- "익절은 20이평 또는 가까운 원비지점"
input int    WMA4Period           = 4; // Period of the 4-weighted MA ("4가중")
input bool   UseMA4_17EntryConfirm = false; // Also require the close beyond BOTH WMA4 and WMA17 (not just the neckline hold) before firing entry -- "진입시 4가중과 17선 확인"
input bool   UseDoubleBAnchor     = false; // Also require pivot1 within BandAnchorATR of the BB4(44band) edge, not just BB20 -- genuine "더블비" anchor (001/005/007's own entry trigger is already this dual-band condition; 008 has only ever used BB20 alone). Neckline-break timing unchanged.

input ulong  MagicNumber          = 95016108; // Magic number
input int    MaxDeviationPts      = 50; // Max price deviation (points)
input bool   EnableLiveOrders     = false; // Enable live orders

int hBB=INVALID_HANDLE, hStoch=INVALID_HANDLE, hATR=INVALID_HANDLE;
int hWMA17=INVALID_HANDLE, hHTFFastMA=INVALID_HANDLE, hHTFSlowMA=INVALID_HANDLE, hMACD=INVALID_HANDLE;
int hWMA4=INVALID_HANDLE, hBB4=INVALID_HANDLE;

// -- supply-zone state (all in KST calendar-day terms), ported from 001 M2 --
int    g_szLastDay=-1;
bool   g_szAsiaBoxSet=false; double g_szAsiaHigh=0, g_szAsiaLow=0;
bool   g_szNYBoxSet=false;   double g_szNYHigh=0, g_szNYLow=0;
double g_szTodayHigh=0, g_szTodayLow=0;
double g_szPrevDayHigh=0, g_szPrevDayLow=0; bool g_szHavePrevDay=false;
double g_szNYSessHigh=0, g_szNYSessLow=0;
double g_szPrevNYHigh=0, g_szPrevNYLow=0;   bool g_szHavePrevNY=false;
bool   g_szInNYSessPrevBar=false;
datetime last_bar=0;
int f_log=INVALID_HANDLE;

// -- buy (double-bottom / "W") setup state machine --
// stage: 0=waiting for pivot1, 1=waiting for pivot2, 2=waiting for neckline break
int    g_buyStage=0;
double g_buyPivot1=0, g_buyPivot2=0, g_buyNeckline=0;
int    g_buyPivot1Bar=0, g_buyPivot2Bar=0; // bar_index-equivalent counters (ever-increasing tick of new bars)
int    g_buyBarsSincePivot1=0, g_buyBarsSincePivot2=0;
int    g_buyNeckHoldBars=0; // consecutive bars closing above the neckline since it first broke

// -- sell (double-top / "M") setup state machine --
int    g_sellStage=0;
double g_sellPivot1=0, g_sellPivot2=0, g_sellNeckline=0;
int    g_sellPivot1Bar=0, g_sellPivot2Bar=0;
int    g_sellBarsSincePivot1=0, g_sellBarsSincePivot2=0;
int    g_sellNeckHoldBars=0; // consecutive bars closing below the neckline since it first broke

int    g_barCounter=0; // increments once per new bar, used as a simple bar-index clock

// -- outcome tracking (one in-flight position at a time, own-Magic MAX1) --
ulong  g_trackTicket=0;
double g_trackEntry=0, g_trackR=0;
double g_trackGapATR=0, g_trackRawR_ATR=0, g_trackFlooredR_ATR=0;
int    g_trackBarsP1toP2=0, g_trackBarsP2toConfirm=0;
int    g_trackDir=0;
string g_trackTag="";

string TS(datetime t){ return TimeToString(t,TIME_DATE|TIME_SECONDS); }

void Log(string event,string detail="")
{
   Print("XAU_M2_BB_LIVE_008_SSANGBI | ",event," | ",detail);
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

void ResetBuySetup(){ g_buyStage=0; g_buyPivot1=0; g_buyPivot2=0; g_buyNeckline=0; g_buyBarsSincePivot1=0; g_buyBarsSincePivot2=0; g_buyNeckHoldBars=0; }
void ResetSellSetup(){ g_sellStage=0; g_sellPivot1=0; g_sellPivot2=0; g_sellNeckline=0; g_sellBarsSincePivot1=0; g_sellBarsSincePivot2=0; g_sellNeckHoldBars=0; }

// Confirmed pivot low/high at shift = PivotRight+1 relative to the bar that just closed
// (shift 1 in iLow/iHigh terms) -- needs PivotRight bars after it (shifts 1..PivotRight)
// and PivotLeft bars before it (shifts PivotRight+2..PivotRight+1+PivotLeft) to be confirmed.
bool IsPivotLow(double &outLow)
{
   int pivotShift=1+PivotRight;
   double val=iLow(_Symbol,Timeframe,pivotShift);
   for(int k=1;k<=PivotRight;k++) if(iLow(_Symbol,Timeframe,pivotShift-k)<val) return false;
   for(int k=1;k<=PivotLeft;k++)  if(iLow(_Symbol,Timeframe,pivotShift+k)<val) return false;
   outLow=val;
   return true;
}

bool IsPivotHigh(double &outHigh)
{
   int pivotShift=1+PivotRight;
   double val=iHigh(_Symbol,Timeframe,pivotShift);
   for(int k=1;k<=PivotRight;k++) if(iHigh(_Symbol,Timeframe,pivotShift-k)>val) return false;
   for(int k=1;k<=PivotLeft;k++)  if(iHigh(_Symbol,Timeframe,pivotShift+k)>val) return false;
   outHigh=val;
   return true;
}

// -- optional filters ported from the 주노짜앙/지킬 reference document --
// All default OFF so the existing confirmed baseline reproduces exactly;
// each is independently toggleable for its own ground-truth backtest.

bool GetWMA17(double &outVal)
{
   double buf[1];
   if(CopyBuffer(hWMA17,0,1,1,buf)!=1) return false;
   outVal=buf[0];
   return true;
}

bool GetWMA4(double &outVal)
{
   double buf[1];
   if(CopyBuffer(hWMA4,0,1,1,buf)!=1) return false;
   outVal=buf[0];
   return true;
}

// Dynamic TP (UseDynamicTP): whichever of {20-SMA (BB base line), nearest 원비
// (44/4-band) edge} sits CLOSER to ref in the favorable direction. Falls back
// to the caller's own TP_R*R value if neither candidate lies beyond ref.
double ComputeDynamicTP(int dir,double ref,double fallbackTP)
{
   double sma20buf[1];
   if(CopyBuffer(hBB,0,1,1,sma20buf)!=1) return fallbackTP;
   double sma20=sma20buf[0];

   double bb4up[1], bb4lo[1];
   bool haveBB4=(CopyBuffer(hBB4,1,1,1,bb4up)==1 && CopyBuffer(hBB4,2,1,1,bb4lo)==1);

   double best=0; bool haveBest=false;
   if(dir==+1)
   {
      if(sma20>ref){ best=sma20; haveBest=true; }
      if(haveBB4 && bb4up[0]>ref && (!haveBest || bb4up[0]<best)){ best=bb4up[0]; haveBest=true; }
   }
   else
   {
      if(sma20<ref){ best=sma20; haveBest=true; }
      if(haveBB4 && bb4lo[0]<ref && (!haveBest || bb4lo[0]>best)){ best=bb4lo[0]; haveBest=true; }
   }
   return haveBest ? best : fallbackTP;
}

// "가단" = the 17-weighted/20-simple MA pair (BB base line = SMA(BBPeriod), reused
// here rather than a second handle). Counts how many times they crossed in the
// lookback window right before pivot1 -- the source material's "가단이 몇 차례
// 꼬였다" precondition for trusting a reversal pattern.
bool TangleGateOk()
{
   if(!UseTangleGate) return true;
   int n=TangleLookbackBars+1;
   double w[], s[];
   ArraySetAsSeries(w,true); ArraySetAsSeries(s,true);
   if(CopyBuffer(hWMA17,0,1,n,w)!=n) return false;
   if(CopyBuffer(hBB,0,1,n,s)!=n) return false; // BB base line (buffer 0) = SMA(BBPeriod)
   int crosses=0;
   bool prevAbove=(w[n-1]>s[n-1]);
   for(int i=n-2;i>=0;i--)
   {
      bool above=(w[i]>s[i]);
      if(above!=prevAbove) crosses++;
      prevAbove=above;
   }
   return crosses>=MinTangleCount;
}

// Higher-timeframe fast/slow WMA state (golden=fast>slow, dead=fast<slow) at the
// last closed HTF bar -- the source material's "최소 5분 골든/데드크로스" precondition.
bool HTFCrossGateOk(int dir)
{
   if(!UseHTFCrossGate) return true;
   double f[1],s[1];
   if(CopyBuffer(hHTFFastMA,0,1,1,f)!=1) return false;
   if(CopyBuffer(hHTFSlowMA,0,1,1,s)!=1) return false;
   return (dir==+1) ? (f[0]>s[0]) : (f[0]<s[0]);
}

// MACD must sit on the trade's side of its signal line AND the histogram must be
// turning further that way (not just crossed once and flattening) -- the source
// material's "맥디가 방향을 틀고 교차하는지" check.
bool MACDGateOk(int dir)
{
   if(!UseMACDGate) return true;
   double main[], signal[];
   ArraySetAsSeries(main,true); ArraySetAsSeries(signal,true);
   if(CopyBuffer(hMACD,0,1,2,main)!=2) return false;
   if(CopyBuffer(hMACD,1,1,2,signal)!=2) return false;
   double hist0=main[0]-signal[0], hist1=main[1]-signal[1];
   if(dir==+1) return (main[0]>signal[0]) && (hist0>hist1);
   else        return (main[0]<signal[0]) && (hist0<hist1);
}

// -- 매물대 (supply/demand zone) tracking, ported from 001 M2 (same logic,
// same KST calendar-day semantics) --
bool IsEUDST_SZ(datetime server_now)
{
   MqlDateTime t; TimeToStruct(server_now,t);
   MqlDateTime dstStartT; dstStartT.year=t.year; dstStartT.mon=3; dstStartT.day=31; dstStartT.hour=0; dstStartT.min=0; dstStartT.sec=0;
   datetime dstStart=StructToTime(dstStartT);
   MqlDateTime cur1; TimeToStruct(dstStart,cur1); dstStart-=cur1.day_of_week*86400;
   MqlDateTime dstEndT; dstEndT.year=t.year; dstEndT.mon=10; dstEndT.day=31; dstEndT.hour=0; dstEndT.min=0; dstEndT.sec=0;
   datetime dstEnd=StructToTime(dstEndT);
   MqlDateTime cur2; TimeToStruct(dstEnd,cur2); dstEnd-=cur2.day_of_week*86400;
   return (server_now>=dstStart && server_now<dstEnd);
}

int KST_Hour_SZ(datetime server_now)
{
   int offsetHours=IsEUDST_SZ(server_now)?6:7;
   MqlDateTime t; TimeToStruct(server_now+offsetHours*3600,t);
   return t.hour;
}

int KSTDayIndex(datetime server_now)
{
   int offsetHours=IsEUDST_SZ(server_now)?6:7;
   datetime kst=server_now+offsetHours*3600;
   return (int)(kst/86400);
}

bool InWindowKST_SZ(int minOfDay,double startHour,double endHour)
{
   int start=(int)MathRound(startHour*60);
   int end=(int)MathRound(endHour*60);
   if(start<=end) return (minOfDay>=start && minOfDay<end);
   return (minOfDay>=start || minOfDay<end);
}

void UpdateSupplyZones(datetime sig,double h,double l)
{
   int day=KSTDayIndex(sig);
   int hourKST=KST_Hour_SZ(sig);
   int offsetHours=IsEUDST_SZ(sig)?6:7;
   MqlDateTime t; TimeToStruct(sig+offsetHours*3600,t);
   int minOfDay=t.hour*60+t.min;

   if(g_szLastDay<0)
   {
      g_szLastDay=day; g_szTodayHigh=h; g_szTodayLow=l;
      g_szAsiaBoxSet=false; g_szNYBoxSet=false;
   }
   else if(day!=g_szLastDay)
   {
      g_szPrevDayHigh=g_szTodayHigh; g_szPrevDayLow=g_szTodayLow; g_szHavePrevDay=true;
      g_szTodayHigh=h; g_szTodayLow=l;
      g_szAsiaBoxSet=false; g_szNYBoxSet=false;
      g_szLastDay=day;
   }
   else
   {
      if(h>g_szTodayHigh) g_szTodayHigh=h;
      if(l<g_szTodayLow)  g_szTodayLow=l;
   }

   if(!g_szAsiaBoxSet && hourKST==AsiaOpenHourKST)
   { g_szAsiaHigh=h; g_szAsiaLow=l; g_szAsiaBoxSet=true; }

   int nyOpenMin=(int)MathRound(NYOpenHourKST*60);
   if(!g_szNYBoxSet && minOfDay>=nyOpenMin && minOfDay<nyOpenMin+60)
   { g_szNYHigh=h; g_szNYLow=l; g_szNYBoxSet=true; }

   bool inNYSess=InWindowKST_SZ(minOfDay,NYSessionStartHourKST,NYSessionEndHourKST);
   if(inNYSess)
   {
      if(!g_szInNYSessPrevBar){ g_szNYSessHigh=h; g_szNYSessLow=l; }
      else { if(h>g_szNYSessHigh) g_szNYSessHigh=h; if(l<g_szNYSessLow) g_szNYSessLow=l; }
   }
   else if(g_szInNYSessPrevBar)
   {
      g_szPrevNYHigh=g_szNYSessHigh; g_szPrevNYLow=g_szNYSessLow; g_szHavePrevNY=true;
   }
   g_szInNYSessPrevBar=inNYSess;
}

double DistanceToNearestZone(double price,double atr)
{
   if(atr<=0) return 999.0;
   double best=999.0;
   if(UseAsiaBoxZone && g_szAsiaBoxSet)
   { best=MathMin(best,MathAbs(price-g_szAsiaHigh)/atr); best=MathMin(best,MathAbs(price-g_szAsiaLow)/atr); }
   if(UseNYBoxZone && g_szNYBoxSet)
   { best=MathMin(best,MathAbs(price-g_szNYHigh)/atr); best=MathMin(best,MathAbs(price-g_szNYLow)/atr); }
   if(UseTodayHighLowZone)
   { best=MathMin(best,MathAbs(price-g_szTodayHigh)/atr); best=MathMin(best,MathAbs(price-g_szTodayLow)/atr); }
   if(UsePrevDayHighLowZone && g_szHavePrevDay)
   { best=MathMin(best,MathAbs(price-g_szPrevDayHigh)/atr); best=MathMin(best,MathAbs(price-g_szPrevDayLow)/atr); }
   if(UsePrevNYHighLowZone && g_szHavePrevNY)
   { best=MathMin(best,MathAbs(price-g_szPrevNYHigh)/atr); best=MathMin(best,MathAbs(price-g_szPrevNYLow)/atr); }
   return best;
}

bool NearSupplyZone(double price,double atr)
{
   if(!UseSupplyZoneAnchor) return true;
   return DistanceToNearestZone(price,atr)<=SupplyZoneATR;
}

void OpenTrade(int dir,double sl,double atr,double gapATR,int barsP1toP2,int barsP2toConfirm,string tag)
{
   if(HasOurPosition()){ Log("ENTRY_SKIPPED","own-Magic position already exists"); return; }

   MqlTick q; if(!SymbolInfoTick(_Symbol,q)){ Log("ORDER_FAIL","no current tick"); return; }
   double ref=(dir==+1 ? q.ask : q.bid);
   double R=MathAbs(ref-sl);
   double rawR_ATR=(atr>0) ? R/atr : 0;
   if(!UseRawPivotStop && MinStopATR>0 && atr>0 && R<MinStopATR*atr)
   {
      double need=MinStopATR*atr-R;
      sl=sl-dir*need;
      R=MathAbs(ref-sl);
   }
   double flooredR_ATR=(atr>0) ? R/atr : 0;
   double tp=UseDynamicTP ? ComputeDynamicTP(dir,ref,ref+dir*TP_R*R) : ref+dir*TP_R*R;

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
   R=MathAbs(ref-sl);

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
      Log("ENTRY_OK",(dir==1?"BUY":"SELL")+" R="+DoubleToString(R,_Digits)+" ATR="+DoubleToString(atr,_Digits)+
          " SL="+DoubleToString(sl,_Digits)+" TP="+DoubleToString(tp,_Digits)+" | "+tag);
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong tk=PositionGetTicket(i);
         if(tk==0 || !PositionSelectByTicket(tk)) continue;
         if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
         g_trackTicket=tk; g_trackEntry=ref; g_trackR=R; g_trackDir=dir; g_trackTag=tag;
         g_trackGapATR=gapATR; g_trackRawR_ATR=rawR_ATR; g_trackFlooredR_ATR=flooredR_ATR;
         g_trackBarsP1toP2=barsP1toP2; g_trackBarsP2toConfirm=barsP2toConfirm;
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

   double o=iOpen(_Symbol,Timeframe,1),c=iClose(_Symbol,Timeframe,1);

   double upper[1],lower[1];
   if(CopyBuffer(hBB,1,1,1,upper)!=1 || CopyBuffer(hBB,2,1,1,lower)!=1)
   { Log("COPYBUFFER_FAIL","BB bands"); return; }

   double bb4up[1],bb4lo[1]; bool haveBB4Now=false;
   if(UseDoubleBAnchor)
   {
      haveBB4Now=(CopyBuffer(hBB4,1,1,1,bb4up)==1 && CopyBuffer(hBB4,2,1,1,bb4lo)==1);
      if(!haveBB4Now){ Log("COPYBUFFER_FAIL","BB4 bands"); return; }
   }

   double kbuf[1];
   if(CopyBuffer(hStoch,0,1,1,kbuf)!=1){ Log("STOCH_FAIL","no stochastic value"); return; }
   double stochK=kbuf[0];

   double atrbuf[1];
   if(CopyBuffer(hATR,0,1,1,atrbuf)!=1){ Log("ATR_FAIL","no ATR value"); return; }
   double atr=atrbuf[0];
   if(atr<=0) return;

   UpdateSupplyZones(iTime(_Symbol,Timeframe,1),iHigh(_Symbol,Timeframe,1),iLow(_Symbol,Timeframe,1));

   bool haveOpenPos=HasOurPosition();

   double pivLow, pivHigh;
   bool gotPivotLow=IsPivotLow(pivLow);
   bool gotPivotHigh=IsPivotHigh(pivHigh);
   // the confirmed pivot bar is PivotRight+1 bars back from the one that just closed
   int pivotBarIndex=g_barCounter-PivotRight;

   // ============================= BUY (W) =============================
   if(g_buyStage==0)
   {
      if(gotPivotLow && pivLow<=lower[0]+BandAnchorATR*atr && TangleGateOk() && NearSupplyZone(pivLow,atr) &&
         (!UseDoubleBAnchor || pivLow<=bb4lo[0]+BandAnchorATR*atr))
      {
         g_buyStage=1; g_buyPivot1=pivLow; g_buyPivot1Bar=pivotBarIndex;
         g_buyNeckline=iHigh(_Symbol,Timeframe,1); g_buyBarsSincePivot1=0;
         Log("SSANGBI_PIVOT1_BUY","low="+DoubleToString(pivLow,_Digits)+" lowerBB="+DoubleToString(lower[0],_Digits));
      }
   }
   else if(g_buyStage==1)
   {
      g_buyBarsSincePivot1=g_barCounter-g_buyPivot1Bar;
      if(iHigh(_Symbol,Timeframe,1)>g_buyNeckline) g_buyNeckline=iHigh(_Symbol,Timeframe,1);

      if(g_buyBarsSincePivot1>MaxPatternBars){ Log("SSANGBI_EXPIRE_BUY","no pivot2 within MaxPatternBars"); ResetBuySetup(); }
      else if(gotPivotLow && pivLow<g_buyPivot1 && (g_barCounter-PivotRight)<=g_buyPivot1Bar+MaxPatternBars)
      {
         // a new, more extreme low before pivot2 forms -- rebase pivot1 to it
         g_buyPivot1=pivLow; g_buyPivot1Bar=pivotBarIndex; g_buyBarsSincePivot1=0;
         g_buyNeckline=iHigh(_Symbol,Timeframe,1);
      }
      else if(gotPivotLow && g_buyBarsSincePivot1>=MinPatternBars &&
              MathAbs(pivLow-g_buyPivot1)>=MinGapATR*atr && MathAbs(pivLow-g_buyPivot1)<=ToleranceATR*atr && pivotBarIndex>g_buyPivot1Bar)
      {
         bool stochOk=(stochK<=StochOversold);
         if(stochOk && HTFCrossGateOk(+1) && MACDGateOk(+1))
         {
            g_buyPivot2=pivLow; g_buyPivot2Bar=pivotBarIndex; g_buyBarsSincePivot2=0; g_buyNeckHoldBars=0; g_buyStage=2;
            Log("SSANGBI_PIVOT2_BUY","pivot1="+DoubleToString(g_buyPivot1,_Digits)+" pivot2="+DoubleToString(g_buyPivot2,_Digits)+
                " neckline="+DoubleToString(g_buyNeckline,_Digits)+" stochK="+DoubleToString(stochK,2)+
                " barsP1toP2="+IntegerToString(g_buyPivot2Bar-g_buyPivot1Bar));
         }
      }
   }
   else if(g_buyStage==2)
   {
      g_buyBarsSincePivot2=g_barCounter-g_buyPivot2Bar;
      bool invalid=(c<g_buyPivot1-ToleranceATR*atr);
      bool timeout=(g_buyBarsSincePivot2>MaxConfirmBars);

      if(invalid || timeout)
      {
         Log("SSANGBI_EXPIRE_BUY",(invalid?"support broken":"neckline break timeout"));
         ResetBuySetup();
      }
      else
      {
         bool aboveNeck=(c>g_buyNeckline+NecklineBreakBufferATR*atr);
         if(Use17BreakConfirm)
         {
            double wma17;
            aboveNeck=aboveNeck && GetWMA17(wma17) && c>wma17;
         }
         if(UseMA4_17EntryConfirm)
         {
            double wma4b,wma17b;
            aboveNeck=aboveNeck && GetWMA4(wma4b) && GetWMA17(wma17b) && c>wma4b && c>wma17b;
         }
         // CONSECUTIVE hold, not just "still above on whichever bar the wait
         // happens to end on" -- a dip back below the neckline resets the
         // streak, so a real whipsaw (break, pull back, break again) has to
         // re-earn the full MinBarsToConfirm from scratch, instead of being
         // credited for bars spent below the neckline in between.
         if(aboveNeck) g_buyNeckHoldBars++; else g_buyNeckHoldBars=0;

         if(g_buyNeckHoldBars>=MinBarsToConfirm)
         {
            double gapATR=MathAbs(g_buyPivot2-g_buyPivot1)/atr;
            int barsP1toP2=g_buyPivot2Bar-g_buyPivot1Bar;
            int barsP2toConfirm=g_buyBarsSincePivot2;
            Log("SSANGBI_NECKBREAK_BUY","neckline="+DoubleToString(g_buyNeckline,_Digits)+
                " close="+DoubleToString(c,_Digits)+" gapATR="+DoubleToString(gapATR,2)+
                " holdBars="+IntegerToString(g_buyNeckHoldBars));
            if(!haveOpenPos)
            {
               double sl=UseRawPivotStop ? MathMin(g_buyPivot1,g_buyPivot2) : MathMin(g_buyPivot1,g_buyPivot2)-SLBufferATR*atr;
               OpenTrade(+1,sl,atr,gapATR,barsP1toP2,barsP2toConfirm,"SSANGBI_BUY");
            }
            else
               Log("ENTRY_SKIPPED","SSANGBI_BUY neckline break but position already open");
            ResetBuySetup();
         }
      }
   }

   // ============================= SELL (M) =============================
   if(g_sellStage==0)
   {
      if(gotPivotHigh && pivHigh>=upper[0]-BandAnchorATR*atr && TangleGateOk() && NearSupplyZone(pivHigh,atr) &&
         (!UseDoubleBAnchor || pivHigh>=bb4up[0]-BandAnchorATR*atr))
      {
         g_sellStage=1; g_sellPivot1=pivHigh; g_sellPivot1Bar=pivotBarIndex;
         g_sellNeckline=iLow(_Symbol,Timeframe,1); g_sellBarsSincePivot1=0;
         Log("SSANGBI_PIVOT1_SELL","high="+DoubleToString(pivHigh,_Digits)+" upperBB="+DoubleToString(upper[0],_Digits));
      }
   }
   else if(g_sellStage==1)
   {
      g_sellBarsSincePivot1=g_barCounter-g_sellPivot1Bar;
      if(iLow(_Symbol,Timeframe,1)<g_sellNeckline) g_sellNeckline=iLow(_Symbol,Timeframe,1);

      if(g_sellBarsSincePivot1>MaxPatternBars){ Log("SSANGBI_EXPIRE_SELL","no pivot2 within MaxPatternBars"); ResetSellSetup(); }
      else if(gotPivotHigh && pivHigh>g_sellPivot1 && (g_barCounter-PivotRight)<=g_sellPivot1Bar+MaxPatternBars)
      {
         g_sellPivot1=pivHigh; g_sellPivot1Bar=pivotBarIndex; g_sellBarsSincePivot1=0;
         g_sellNeckline=iLow(_Symbol,Timeframe,1);
      }
      else if(gotPivotHigh && g_sellBarsSincePivot1>=MinPatternBars &&
              MathAbs(pivHigh-g_sellPivot1)>=MinGapATR*atr && MathAbs(pivHigh-g_sellPivot1)<=ToleranceATR*atr && pivotBarIndex>g_sellPivot1Bar)
      {
         bool stochOk=(stochK>=StochOverbought);
         if(stochOk && HTFCrossGateOk(-1) && MACDGateOk(-1))
         {
            g_sellPivot2=pivHigh; g_sellPivot2Bar=pivotBarIndex; g_sellBarsSincePivot2=0; g_sellNeckHoldBars=0; g_sellStage=2;
            Log("SSANGBI_PIVOT2_SELL","pivot1="+DoubleToString(g_sellPivot1,_Digits)+" pivot2="+DoubleToString(g_sellPivot2,_Digits)+
                " neckline="+DoubleToString(g_sellNeckline,_Digits)+" stochK="+DoubleToString(stochK,2)+
                " barsP1toP2="+IntegerToString(g_sellPivot2Bar-g_sellPivot1Bar));
         }
      }
   }
   else if(g_sellStage==2)
   {
      g_sellBarsSincePivot2=g_barCounter-g_sellPivot2Bar;
      bool invalid=(c>g_sellPivot1+ToleranceATR*atr);
      bool timeout=(g_sellBarsSincePivot2>MaxConfirmBars);

      if(invalid || timeout)
      {
         Log("SSANGBI_EXPIRE_SELL",(invalid?"resistance broken":"neckline break timeout"));
         ResetSellSetup();
      }
      else
      {
      bool belowNeck=(c<g_sellNeckline-NecklineBreakBufferATR*atr);
      if(Use17BreakConfirm)
      {
         double wma17;
         belowNeck=belowNeck && GetWMA17(wma17) && c<wma17;
      }
      if(UseMA4_17EntryConfirm)
      {
         double wma4s,wma17s;
         belowNeck=belowNeck && GetWMA4(wma4s) && GetWMA17(wma17s) && c<wma4s && c<wma17s;
      }
      if(belowNeck) g_sellNeckHoldBars++; else g_sellNeckHoldBars=0;

      if(g_sellNeckHoldBars>=MinBarsToConfirm)
      {
         double gapATR=MathAbs(g_sellPivot2-g_sellPivot1)/atr;
         int barsP1toP2=g_sellPivot2Bar-g_sellPivot1Bar;
         int barsP2toConfirm=g_sellBarsSincePivot2;
         Log("SSANGBI_NECKBREAK_SELL","neckline="+DoubleToString(g_sellNeckline,_Digits)+
             " close="+DoubleToString(c,_Digits)+" gapATR="+DoubleToString(gapATR,2)+
             " holdBars="+IntegerToString(g_sellNeckHoldBars));
         if(!haveOpenPos)
         {
            double sl=UseRawPivotStop ? MathMax(g_sellPivot1,g_sellPivot2) : MathMax(g_sellPivot1,g_sellPivot2)+SLBufferATR*atr;
            OpenTrade(-1,sl,atr,gapATR,barsP1toP2,barsP2toConfirm,"SSANGBI_SELL");
         }
         else
            Log("ENTRY_SKIPPED","SSANGBI_SELL neckline break but position already open");
         ResetSellSetup();
      }
      }
   }
}

int OnInit()
{
   hBB=iBands(_Symbol,Timeframe,BBPeriod,0,BBDev,PRICE_CLOSE);
   hStoch=iStochastic(_Symbol,Timeframe,StochK_Period,StochD_Period,StochSlowing,MODE_SMA,STO_LOWHIGH);
   hATR=iATR(_Symbol,Timeframe,ATRPeriod);
   hWMA17=iMA(_Symbol,Timeframe,WMA17Period,0,MODE_LWMA,PRICE_CLOSE);
   hHTFFastMA=iMA(_Symbol,HTFTimeframe,HTFFastPeriod,0,MODE_LWMA,PRICE_CLOSE);
   hHTFSlowMA=iMA(_Symbol,HTFTimeframe,HTFSlowPeriod,0,MODE_LWMA,PRICE_CLOSE);
   hMACD=iMACD(_Symbol,Timeframe,MACDFastPeriod,MACDSlowPeriod,MACDSignalPeriod,PRICE_CLOSE);
   hWMA4=iMA(_Symbol,Timeframe,WMA4Period,0,MODE_LWMA,PRICE_CLOSE);
   hBB4=iBands(_Symbol,Timeframe,4,0,4.0,PRICE_OPEN);
   if(hBB==INVALID_HANDLE || hStoch==INVALID_HANDLE || hATR==INVALID_HANDLE ||
      hWMA17==INVALID_HANDLE || hHTFFastMA==INVALID_HANDLE || hHTFSlowMA==INVALID_HANDLE || hMACD==INVALID_HANDLE ||
      hWMA4==INVALID_HANDLE || hBB4==INVALID_HANDLE)
   { Print("Indicator handle creation failed"); return INIT_FAILED; }

   f_log=FileOpen("XAU_M2_BB_LIVE_008_SSANGBI_LOG.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
   if(f_log!=INVALID_HANDLE) FileSeek(f_log,0,SEEK_END);

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(MaxDeviationPts);
   trade.SetTypeFillingBySymbol(_Symbol);

   Log("START","TF="+EnumToString(Timeframe)+" | BB("+IntegerToString(BBPeriod)+","+DoubleToString(BBDev,1)+")"+
       " | Stoch("+IntegerToString(StochK_Period)+","+IntegerToString(StochD_Period)+","+IntegerToString(StochSlowing)+")"+
       " OB="+DoubleToString(StochOverbought,1)+" OS="+DoubleToString(StochOversold,1)+
       " | ATRPeriod="+IntegerToString(ATRPeriod)+
       " | PivotLeft="+IntegerToString(PivotLeft)+" PivotRight="+IntegerToString(PivotRight)+
       " MinPatternBars="+IntegerToString(MinPatternBars)+" MaxPatternBars="+IntegerToString(MaxPatternBars)+
       " | ToleranceATR="+DoubleToString(ToleranceATR,2)+" MinGapATR="+DoubleToString(MinGapATR,2)+
       " BandAnchorATR="+DoubleToString(BandAnchorATR,2)+
       " MaxConfirmBars="+IntegerToString(MaxConfirmBars)+" MinBarsToConfirm="+IntegerToString(MinBarsToConfirm)+
       " NecklineBreakBufferATR="+DoubleToString(NecklineBreakBufferATR,2)+
       " | SLBufferATR="+DoubleToString(SLBufferATR,2)+" TP_R="+DoubleToString(TP_R,2)+" MinStopATR="+DoubleToString(MinStopATR,2)+
       " | UseTangleGate="+(UseTangleGate?"true":"false")+" WMA17Period="+IntegerToString(WMA17Period)+
       " TangleLookbackBars="+IntegerToString(TangleLookbackBars)+" MinTangleCount="+IntegerToString(MinTangleCount)+
       " Use17BreakConfirm="+(Use17BreakConfirm?"true":"false")+
       " | UseHTFCrossGate="+(UseHTFCrossGate?"true":"false")+" HTFTimeframe="+EnumToString(HTFTimeframe)+
       " HTFFastPeriod="+IntegerToString(HTFFastPeriod)+" HTFSlowPeriod="+IntegerToString(HTFSlowPeriod)+
       " | UseMACDGate="+(UseMACDGate?"true":"false")+" MACD("+IntegerToString(MACDFastPeriod)+","+IntegerToString(MACDSlowPeriod)+","+IntegerToString(MACDSignalPeriod)+")"+
       " | UseSupplyZoneAnchor="+(UseSupplyZoneAnchor?"true":"false")+" SupplyZoneATR="+DoubleToString(SupplyZoneATR,2)+
       " UseAsiaBoxZone="+(UseAsiaBoxZone?"true":"false")+" AsiaOpenHourKST="+IntegerToString(AsiaOpenHourKST)+
       " UseNYBoxZone="+(UseNYBoxZone?"true":"false")+" NYOpenHourKST="+DoubleToString(NYOpenHourKST,2)+
       " UseTodayHighLowZone="+(UseTodayHighLowZone?"true":"false")+" UsePrevDayHighLowZone="+(UsePrevDayHighLowZone?"true":"false")+
       " UsePrevNYHighLowZone="+(UsePrevNYHighLowZone?"true":"false")+
       " NYSessionWindow="+DoubleToString(NYSessionStartHourKST,2)+"-"+DoubleToString(NYSessionEndHourKST,2)+"KST"+
       " | UseRawPivotStop="+(UseRawPivotStop?"true":"false")+
       " UseDynamicTP="+(UseDynamicTP?"true":"false")+
       " WMA4Period="+IntegerToString(WMA4Period)+" UseMA4_17EntryConfirm="+(UseMA4_17EntryConfirm?"true":"false")+
       " UseDoubleBAnchor="+(UseDoubleBAnchor?"true":"false")+
       " | Lots="+DoubleToString(Lots,2)+" | Magic="+IntegerToString((int)MagicNumber)+
       " | orders="+(EnableLiveOrders?"ENABLED":"DRY"));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(f_log!=INVALID_HANDLE){ FileFlush(f_log); FileClose(f_log); }
   if(hBB!=INVALID_HANDLE) IndicatorRelease(hBB);
   if(hStoch!=INVALID_HANDLE) IndicatorRelease(hStoch);
   if(hATR!=INVALID_HANDLE) IndicatorRelease(hATR);
   if(hWMA17!=INVALID_HANDLE) IndicatorRelease(hWMA17);
   if(hHTFFastMA!=INVALID_HANDLE) IndicatorRelease(hHTFFastMA);
   if(hHTFSlowMA!=INVALID_HANDLE) IndicatorRelease(hHTFSlowMA);
   if(hMACD!=INVALID_HANDLE) IndicatorRelease(hMACD);
   if(hWMA4!=INVALID_HANDLE) IndicatorRelease(hWMA4);
   if(hBB4!=INVALID_HANDLE) IndicatorRelease(hBB4);
}

void OnTick()
{
   CheckNewBar();
}

// Sums profit+swap+commission across EVERY deal belonging to a closed
// position (entry AND exit), not just the exit deal that triggered this
// transaction. BUG FOUND via ground-truth cross-check (on the M1 001
// sibling file, same pattern here) against MT5's own xlsx tester report:
// this broker charges commission on the ENTRY deal only (the exit deal's
// own commission is always 0), so reading only trans.deal (the exit/OUT
// deal) silently dropped the entry commission ($1.50/0.1 lot here) from
// every single logged trade. Affected every CSV-log-derived ground-truth
// figure in this project's history that used the old trans.deal-only
// pattern.
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
   if(g_trackTicket==0 || posId!=g_trackTicket) return;

   double profit=SumPositionProfit(posId);
   string outcome=(profit>0?"WIN":"LOSS");
   Log("MAE_OUTCOME","outcome="+outcome+" profit="+DoubleToString(profit,2)+" R="+DoubleToString(g_trackR,_Digits)+
       " gapATR="+DoubleToString(g_trackGapATR,2)+" rawR_ATR="+DoubleToString(g_trackRawR_ATR,2)+
       " flooredR_ATR="+DoubleToString(g_trackFlooredR_ATR,2)+
       " barsP1toP2="+IntegerToString(g_trackBarsP1toP2)+" barsP2toConfirm="+IntegerToString(g_trackBarsP2toConfirm)+
       " | "+g_trackTag);
   g_trackTicket=0;
}
