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
//|  1) ARM: REVISED (2026-11-21, see dated note below) -- arming is no  |
//|     longer "whenever flat, check current bid vs MA" (that version    |
//|     took every touch indefinitely, backtested at PF~1.01, no edge).  |
//|     Per the user's confirmed reading of the cafe post's own title    |
//|     ("3분 장기이평 매매... 20,120 이평의 골크,데크 후 첫 120장기이평 눌림  |
//|     에서 진입"): a NEW fast MAFastPeriod (20) SMA is added purely for |
//|     cross detection against the existing 120 MAPeriod SMA. Only the  |
//|     FIRST touch of the 120 MA following a fresh golden/dead cross is |
//|     tradeable -- not every touch while the alignment merely persists.|
//|     A golden cross (fast crosses above slow) arms BUY; a dead cross  |
//|     arms SELL. If price never pulls back to touch the 120 MA before  |
//|     the NEXT opposite cross happens, that episode is discarded (no   |
//|     entry) and the new cross's direction takes over.                 |
//|  2) STEP: the manual tool's typed step-size box is replaced by      |
//|     UseATRStep (step=ATR(StepATRPeriod)*StepATRMult, price units)   |
//|     or, if false, a fixed GridStepPoints. The manual tool's author   |
//|     described eyeballing recent volatility and re-typing the step    |
//|     by hand (~$50 variance range / 5 steps = $10 step in their own   |
//|     example -- trader "포인트"=$1 for gold, matching GridStepPoints=  |
//|     1000's default here, i.e. 1000*_Point=$10 on this 2-decimal-     |
//|     digit symbol). ATR is the natural automatic stand-in for that    |
//|     eyeballed volatility read, but the original StepATRMult=0.2      |
//|     default produced only ~$0.12 (100x too small, see first-backtest |
//|     note below) -- UNRESOLVED how to rescale ATR-based step properly;|
//|     UseATRStep=false with the corrected GridStepPoints=1000 is the   |
//|     safer next test.                                                 |
//|  3) EXIT: the manual tool had NO take-profit mechanism at all        |
//|     (purely discretionary). REVISED several times since -- see the    |
//|     dated backtest notes below for the full history. CURRENT          |
//|     (2026-11-21, 5th revision): UseSwingTP sets a hard TP at the       |
//|     SwingLookbackBars rolling high/low read AT ENTRY TIME ("전고점"/    |
//|     "전저점"). While the 20/120 regime stays ALIGNED with the basket,   |
//|     that TP + the hard SL are the ONLY exits -- confirmed by the user  |
//|     after the 4th revision's unconditional breakeven-trail (then       |
//|     called UseBreakevenExit) was shown to cut aligned-trend winners     |
//|     short. UseRegimeFlipExit is the ONLY "본절" mechanism: if the        |
//|     regime flips AGAINST an open basket, close immediately once avg     |
//|     price reaches breakeven+RegimeFlipMinProfitSteps ("역배열: 본절       |
//|     or 약수익 오면 즉시 정리").                                           |
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
//| NOT YET IMPLEMENTED (flagged, not built -- see the FOURTH REVISION     |
//| note below for the fuller, more concrete version of this list):        |
//| this file takes EVERY cross's first touch, with no filter on WHICH     |
//| golden/dead-cross setups to skip ("변곡의 초입" avoidance / top-down     |
//| multi-timeframe confluence).                                           |
//|                                                                     |
//| Also not built: a re-arm cooldown. The moment a basket fully closes   |
//| (flat), the very next tick re-arms immediately off current price vs   |
//| MA -- there is no minimum gap enforced between baskets. If a          |
//| backtest shows pathological immediate-re-entry churn right at the     |
//| shared-SL exit price, a CooldownBars input is the straightforward      |
//| fix, deferred until that's actually observed.                         |
//|                                                                     |
//| FIRST BACKTEST (2026-11-21, StepATRMult=0.2/TrailTriggerStep=1.0/     |
//| TrailDistanceStep=0.5, REJECTED): NET -$61,760.29, PF 0.885345, RF    |
//| -0.725167, Sharpe -5.0, Balance DD 85.14% ($85,142.47) on 64,281      |
//| baskets (2025.01-2026.10), avg holding time 1:36 (min 1 second).      |
//| Order-level inspection found a UNIT-SCALE BUG: GridStepPoints and the |
//| ATR-based step both multiply by MQL5's native _Point (=$0.01 on this  |
//| 2-decimal-digit symbol), but the cafe-post example this was built     |
//| from ("변동폭 50포인트, 10포인트 간격") uses trader convention where 1  |
//| "포인트"=$1 for gold -- a 100x mismatch. The actual ATR-based step     |
//| that ran was ~$0.12 (confirmed from grid-leg level/SL spacing in the  |
//| report), not the ~$10 the article's own example implies, so the whole |
//| grid/trail structure operated at tick-noise scale instead of genuine  |
//| swing scale. This is the dominant cause of the overtrading/DD, well   |
//| above the trail-vs-step tightness also present at that scale.         |
//|                                                                     |
//| SECOND BACKTEST (2026-11-21, GridStepPoints=1000/UseATRStep=false,    |
//| scale bug fixed, REJECTED as no-edge, not as broken): NET +$3,709.99, |
//| PF 1.010433, RF 0.13063, Sharpe 0.13875, Balance DD 24.10% ($27,499)  |
//| on 4,338 baskets (-93% vs first backtest), avg holding 4:16:50 (was   |
//| 1:36). Confirms the scale fix: trade count and holding time both      |
//| normalized, NET flipped positive. But PF~1.01 is essentially          |
//| breakeven-after-costs -- no real edge, terrible DD-for-NET ($27,499   |
//| risked for $3,710 gained). Root cause: entry was STILL "any touch of  |
//| the 120 MA while price happens to be on one side of it," not the      |
//| article's actual "FIRST touch after a fresh 20/120 cross" -- i.e. the |
//| human-judgment step (is this a genuine new cross, not a stale/        |
//| already-extended alignment) was entirely missing, not just the       |
//| separately-flagged "변곡 초입" avoidance. Fixed by the ARM revision    |
//| above (MAFastPeriod cross-gating) -- not yet backtested.               |
//|                                                                     |
//| THIRD BACKTEST (2026-11-21, cross-gated ARM + regime-extreme swing     |
//| TP, REJECTED, slightly worse): NET +$611.03, PF 1.002278, RF 0.02497, |
//| Sharpe 0.029362, DD 22.59% ($23,712) on 3,286 baskets (-24%). Order    |
//| table showed the swing TP (전고점/전저점 defined as the just-ended       |
//| regime's extreme) was hit only 126/3,286 times (3.8%) -- a 20/120      |
//| cross on M3 flips too often for "the extreme since the last cross" to  |
//| be a meaningful structural level; 96% of baskets still closed via SL.  |
//|                                                                     |
//| FOURTH REVISION (2026-11-21, per two documents the user shared: a      |
//| "손절/익절", "정배/역배 대응", "피해야 할 구간 4가지", "체크리스트 요약"       |
//| screenshot set, and a "탑다운 분석 매뉴얼" docx). Changes made:           |
//|  - Swing TP decoupled from the cross-regime tracker (which the 3rd     |
//|    backtest showed rarely fires) -- now computed as a rolling          |
//|    SwingLookbackBars-bar high/low AT ENTRY TIME, matching "① 전저/전고   |
//|    무조건 익절" read literally as "the nearest meaningful swing point",  |
//|    not "whatever the last cross happened to produce."                  |
//|  - UseBasketTrailStop renamed/recalibrated to UseBreakevenExit, per     |
//|    "② 본절 복귀 시 구간 일괄 익절": arms at BreakevenTriggerStep=0 (exactly|
//|    breakeven, was 1.0 step) -- the checklist's own numbers are "1차     |
//|    본절, 2차 10포, 3차 20~30포", i.e. arm AT breakeven, not a full step   |
//|    past it.                                                            |
//|  - UseRegimeFlipExit added, per "04 정배/역배 대응": if the 20/120        |
//|    regime flips AGAINST an open basket's direction, close immediately   |
//|    the moment avg price reaches breakeven+RegimeFlipMinProfitSteps      |
//|    ("역배열: 본절 or 약수익 오면 즉시 정리") rather than waiting on the     |
//|    normal swing TP or the gentler breakeven-recovery arm/trail.         |
//|  - UseSkipHourKST added, per "새벽 2시 이후 신규 금지": blocks NEW         |
//|    entries in [02:00,08:00) KST, window CONFIRMED BY USER (2026-11-21). |
//|  - NOT IMPLEMENTED (scope flagged, needs the user's input before        |
//|    building): the "탑다운 분석 매뉴얼" docx describes a FULL 9-timeframe  |
//|    (주/일/8H/4H/2H/1H/30M/15M/3M) cascade, each checked for 5 things     |
//|    (골크/데크, 첫 BB4(4,4) 기본비 터치, 쌍비, 쌍봉/쌍바닥, 120MA 터치),      |
//|    before the M3 entry is even considered -- i.e. the M3 cross+touch    |
//|    this file already automates is only the FINAL step of a much larger  |
//|    discretionary multi-timeframe bias analysis. 쌍봉/쌍바닥 (visual       |
//|    double-top/bottom) and 매물대 (시가봉/AM/BOB/미장되돌림봉/박스권 zone    |
//|    types) are genuinely discretionary pattern reads with no precise      |
//|    enough definition given here to automate faithfully. The 5대 지표     |
//|    economic-calendar filter also needs MT5's calendar API, not built.    |
//|    One piece IS directly portable without more input needed: 기본비 is   |
//|    the SAME BB4(4,4,PRICE_OPEN) construct already used in 010-013 in     |
//|    this repo. The rest (how many/which higher timeframes to require      |
//|    alignment on) is asked of the user rather than guessed.               |
//|                                                                     |
//| FOURTH BACKTEST (2026-11-21, 4th revision as above, REJECTED): NET       |
//| -$4,410.88, PF 0.944281, RF -0.571292, Sharpe -1.383616, Balance DD      |
//| 7.06% ($7,254.18, much lower than before) on 2,471 baskets (-25%),       |
//| avg holding 1:08:53 (was 4:59:12), win rate 53.62% (was 65.34%), avg     |
//| win $56.42/avg loss -$65.84 (was $125.21/-$231.15). DD dropped a lot     |
//| but NET went negative and win rate collapsed toward a coin flip --      |
//| user identified the cause before this backtest even came back:          |
//| UseBreakevenExit ran UNCONDITIONALLY (any time avg price reached         |
//| breakeven, regardless of regime state), so it was constantly cutting     |
//| off baskets that were STILL regime-aligned and on track for the real     |
//| ① target, confirmed by the user's correction: "본절" in the checklist     |
//| ONLY applies when the regime flips AGAINST the basket (checklist '04     |
//| 정배/역배 대응'), not as a standalone always-on mechanism. FIFTH           |
//| REVISION: UseBreakevenExit/BreakevenTriggerStep/BreakevenTrailStep        |
//| REMOVED entirely; UseRegimeFlipExit is now the ONLY breakeven-related     |
//| exit, firing ONLY on a regime flip against the basket.                    |
//|                                                                     |
//| FIFTH BACKTEST (2026-11-21, 5th revision as above, REJECTED, worst DD     |
//| since the unit-scale bug): NET -$29,249.57, PF 0.866384, RF -0.899317,    |
//| Sharpe -2.034188, Balance DD 31.77% ($32,381.53) on 3,862 baskets, win    |
//| rate 64.45% (recovered, confirming the 5th revision's fix worked), avg    |
//| win $76.20/avg loss -$155.22. Order-table close-reason tally: only 480    |
//| closed via hard SL and 328 via swing TP -- the remaining ~3,054 (79%!)    |
//| closed via REGIME_FLIP_CLOSE. M3's own 20/120 cross flips so often that   |
//| "regime flip against an open basket" is the NORM on M3, not the rare      |
//| correction the checklist frames it as -- and each such close, even at    |
//| raw-price breakeven, nets a small realized LOSS once spread+commission    |
//| across up to 6 grid legs are included, which is the likely driver of      |
//| the loss-count inflation. User pushed back on a first proposal to fix     |
//| this by checking the regime-flip on H1 instead of M3: correctly pointed   |
//| out that H1 rarely/never flips within a basket's typical 1-5 hour         |
//| lifetime (per backtests 3-5's own holding-time stats), which would make   |
//| UseRegimeFlipExit nearly inert instead of fixing the over-triggering.     |
//| SIXTH REVISION: RegimeFlipTimeframe (default M15) added, decoupling the   |
//| regime-flip check from the M3 entry cross entirely -- M3 still drives     |
//| ARM/entry, a SEPARATE M15 20/120 cross (own handles, own bar-cadence      |
//| tracking) drives ONLY the regime-flip-against-basket detection. M15 is    |
//| a first-guess middle ground between M3 (too noisy) and H1 (too slow).    |
//|                                                                     |
//| SIXTH BACKTEST (2026-11-21, 6th revision as above): NET +$2,736.52, PF    |
//| 1.010037, RF 0.117275, Sharpe 0.100096, Balance DD 18.40% ($22,169.95,    |
//| best of backtests 3/5/6) on 2,188 baskets, avg holding 8:20:33 (was       |
//| 2:26:09), win rate 49.86% (near coin-flip), avg win $252.42/avg loss      |
//| -$245.56 (nearly symmetric). Close-reason tally: SL 804 (37%), TP 604     |
//| (28%, up sharply from BT3's 3.8%), REGIME_FLIP ~780 (36%) -- a much       |
//| healthier three-way split than BT5's 79% regime-flip domination; M15      |
//| fixed the over-triggering as intended. But PF~1.01 again -- across SIX    |
//| backtests spanning very different exit configurations (unconditional     |
//| breakeven, regime-flip-only on M3, regime-flip-only on M15), the          |
//| mechanical 20/120-cross + 120MA-touch + DCA-grid signal itself keeps      |
//| converging to PF~1.00-1.01, i.e. no real edge before costs, regardless    |
//| of exit tuning. This points at the ENTRY side, not further exit           |
//| iteration, as where the actual edge (if any) must come from.              |
//|                                                                     |
//| SEVENTH REVISION (2026-11-21, user's choice from two deferred options --  |
//| higher-TF alignment vs the avoid-zones filter -- picked alignment         |
//| first): UseHigherTFAlignment/HigherTFAlignment added, per 탑다운 분석       |
//| 매뉴얼's "탑다운 분석 방향과 일치하는지 확인". The docx checks NINE             |
//| timeframes (주/일/8H/4H/2H/1H/30M/15M) simultaneously; this is a scoped    |
//| first pass checking only ONE (default H1, a guess -- both documents       |
//| reference H1 specifically, e.g. the avoid-zone rule "1시간 이상봉 기본비+    |
//| 장기이평"). At the moment of entry, H1's own 20/120 (MAFastPeriod/          |
//| MAPeriod) alignment must match the entry direction, else that touch is    |
//| skipped and the cross episode stays armed for a later one.                |
//|                                                                     |
//| SEVENTH BACKTEST (2026-11-21, 7th revision as above, CONFIRMED WORKING -- |
//| first clear edge of the whole session): NET +$18,986.09, PF 1.08931, RF   |
//| 0.676713, Sharpe 0.74104, Balance DD 18.23% ($25,621.82) on 1,583         |
//| baskets (-28% vs BT6), avg holding 11:05:23 (up from 8:20:33), win rate   |
//| 48.33% (still near coin-flip) but avg win $302.71/avg loss -$256.98       |
//| (payoff ratio ~1.18:1, up from BT6's ~1.03:1), max win $3,242.51. First   |
//| time PF has cleared ~1.02 across all seven backtests -- H1 directional    |
//| alignment is a genuine filter, not just noise reduction.                  |
//|                                                                     |
//| EIGHTH REVISION (2026-11-21, per user request): UseHigherTFAlignment2/    |
//| HigherTFAlignment2 added -- a SECOND higher timeframe (default H4) that    |
//| must ALSO be aligned with the entry direction (AND, not OR, with the      |
//| H1 check). HigherTFAligned() generalized to TFAligned(dir,hFast,hSlow)    |
//| so both checks share one implementation. Not yet backtested.              |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input group "=== Signal: 20/120 cross + first 120MA pullback touch (REVISED 2026-11-21, TEST/untested) ==="
input ENUM_TIMEFRAMES Timeframe  = PERIOD_M3; // signal timeframe (manual tool was fixed M3) (TEST, untested)
input int    MAFastPeriod         = 20;   // fast SMA, used ONLY to detect golden/dead cross against MAPeriod -- NEW, not in manual tool (TEST, untested)
input int    MAPeriod            = 120;  // long-term SMA period -- cross-detection slow leg AND the pullback-touch entry level (TEST, untested, ported from manual tool default)
input int    MaxWaitBars         = 0;    // give up on a cross episode (no entry) after N new signal-TF bars with no 120MA touch, 0 = wait indefinitely for THIS cross (a new opposite cross still overrides it immediately regardless of this setting) (TEST, untested)

input group "=== Grid step sizing (manual tool had a user-typed box; this automates it, TEST/untested) ==="
input bool   UseATRStep          = true;  // true: step=ATR(StepATRPeriod)*StepATRMult (price units); false: fixed GridStepPoints (TEST, untested)
input int    StepATRPeriod       = 14;    // (TEST, untested)
input double StepATRMult         = 0.2;   // first-guess only, no backtest run yet (TEST, untested)
input double GridStepPoints      = 1000;  // used only when UseATRStep=false; multiplied by _Point (=$0.01 on this symbol), so 1000 = $10 -- trader convention is 1 "포인트"=$1 for gold, NOT MQL5's native _Point; matches manual tool author's own "10포인트 간격"=$10 example (REVISED from 10=$0.10 after first backtest's 100x unit-scale bug, see header) (TEST, untested)

input group "=== Grid/basket structure (same semantics as MATouchGridManual_EA.mq5) ==="
input double Lots                = 0.1;   // lot size, SAME for every leg (first entry + all grid legs) -- max basket exposure = Lots*(1+GridCount) (TEST, untested)
input int    GridCount            = 5;    // additional DCA legs beyond the first entry, ported unchanged from manual tool default (TEST, untested)
input double SLMult               = 5.5;  // shared basket SL = P0 -/+ SLMult*step, ALL legs share this one SL, ported unchanged from manual tool default (TEST, untested)

input group "=== Take-profit: nearby swing high/low (REVISED 2026-11-21: was cross-regime extreme, hit only 3.8% of baskets -- now a rolling lookback at entry time) ==="
input bool   UseSwingTP           = true;  // BUY target = highest high over SwingLookbackBars bars at entry ("전고점 역전"); SELL target = lowest low over SwingLookbackBars bars at entry ("전저점 역전") (TEST, untested)
input int    SwingLookbackBars    = 50;    // lookback window (signal-TF bars, ending at the bar before entry) for the swing extreme (TEST, untested, first guess)
input double MinSwingTPStep       = 1.0;   // minimum favorable distance from P0 to the swing target, in steps -- if the swing level doesn't clear this (target too close/behind), skip the hard TP for this basket and rely on SL/breakeven-exit only (TEST, untested)

input group "=== Regime-flip breakeven exit (RENAMED 2026-11-21: UseBreakevenExit REMOVED -- it ran unconditionally and cut aligned-trend winners short, see dated backtest note. '본절' ONLY applies per checklist '04 정배/역배 대응', confirmed by user: while regime stays ALIGNED with the basket, wait on UseSwingTP only; ONLY when the regime flips AGAINST it, close at breakeven+margin ASAP) ==="
input bool   UseRegimeFlipExit        = true; // if the regime flips AGAINST an open basket's direction, close immediately once avg price reaches breakeven+RegimeFlipMinProfitSteps; while still aligned, UseSwingTP/hard SL are the ONLY exits (TEST, untested)
input double RegimeFlipMinProfitSteps = 0;    // 0 = breakeven ("본절"); positive = require a small profit margin first ("약수익") (TEST, untested)
input ENUM_TIMEFRAMES RegimeFlipTimeframe = PERIOD_M15; // REVISED 2026-11-21: timeframe for the regime-flip check, DECOUPLED from the M3 entry cross. M3's own 20/120 cross flipped against 79% of baskets before they ever reached SL/TP (too noisy); the user also flagged H1 as too slow relative to typical basket lifetimes (1-5 hours) -- M15 is a first-guess middle ground, untested (TEST, untested)

input group "=== Higher-timeframe alignment filter (NEW 2026-11-21, per 탑다운 분석 매뉴얼 docx: '탑다운 분석 방향과 일치하는지 확인'. 7th revision added H1 alone (NET $2,737->$18,986, PF 1.01->1.089, confirmed working); 8th revision adds a SECOND required timeframe, per user request) ==="
input bool   UseHigherTFAlignment   = true;      // at the moment of entry, require HigherTFAlignment's own 20/120 (MAFastPeriod/MAPeriod) alignment to match the entry direction; mismatch skips this touch, episode stays armed for a later one (TEST, untested)
input ENUM_TIMEFRAMES HigherTFAlignment = PERIOD_H1; // CONFIRMED working (7th backtest) -- the docx checks W/D/H8/H4/H2/H1/M30/M15 ALL simultaneously; this + HigherTFAlignment2 are a 2-timeframe scoped version (TEST, confirmed as a filter, exact TF choice still a guess)
input bool   UseHigherTFAlignment2  = true;      // NEW 2026-11-21 (user request): a SECOND higher timeframe that must ALSO be aligned with the entry direction (TEST, untested)
input ENUM_TIMEFRAMES HigherTFAlignment2 = PERIOD_H4; // first guess for the second required timeframe (TEST, untested)

input group "=== Time filter (NEW 2026-11-21, per checklist '새벽 2시 이후 신규 금지'; window CONFIRMED by user as KST 02:00-08:00) ==="
input bool   UseSkipHourKST       = true; // block NEW entries in [SkipHourStartKST,SkipHourEndKST) KST; does not affect baskets already open (TEST, untested)
input int    SkipHourStartKST     = 2;    // source says "2시 이후" -- this part is direct (TEST, untested)
input int    SkipHourEndKST       = 8;    // CONFIRMED by user (2026-11-21): block [02:00,08:00) KST (TEST, untested)

input group "=== Misc ==="
input ulong  MagicNumber          = 95016300; // Magic number (unused by any other model in this repo)
input int    MaxDeviationPts      = 50;    // Max price deviation (points)
input bool   EnableLiveOrders     = false; // Enable live orders

//+------------------------------------------------------------------+
//| State                                                              |
//+------------------------------------------------------------------+
enum ENUM_GSTATE { GS_IDLE=0, GS_BASKET=1 };
ENUM_GSTATE g_state=GS_IDLE;
int      g_dir=0;          // +1 long basket, -1 short basket
double   g_p0=0;           // first-leg fill price
double   g_step=0;         // step used for this basket (fixed once placed)
double   g_sl=0;           // current shared SL for the whole basket
double   g_tp=0;           // hard swing-high/low TP for the whole basket, 0 = none
datetime g_basketOpenTime=0;

// Cross-episode state (REVISED 2026-11-21): g_awaitDir!=0 means a golden/dead
// cross has fired and we're waiting for the FIRST 120MA touch to trade it.
int      g_awaitDir=0;         // 0=no pending cross episode; +1=golden cross (wait to BUY); -1=dead cross (wait to SELL)
int      g_awaitBarsElapsed=0;
datetime g_lastBarSeen=0;      // shared new-bar detector for cross-check + wait-timeout counting

// Regime (fast-vs-slow MA) tracking on the ENTRY timeframe (M3), used ONLY
// for cross detection (ARM) -- NOT for the regime-flip exit, see below.
bool     g_regimeKnown=false;
bool     g_regimeBullish=false;

// Regime tracking on RegimeFlipTimeframe (REVISED 2026-11-21, decoupled from
// the entry cross -- M3's own cross flipped against 79% of baskets before
// they reached SL/TP). Used ONLY to detect a regime flip AGAINST an open
// basket (REGIME-FLIP exit, see UpdateBasketExits).
bool     g_flipRegimeKnown=false;
bool     g_flipRegimeBullish=false;
bool     g_regimeFlippedAgainstBasket=false; // set true when the RegimeFlipTimeframe regime flips while GS_BASKET is open and no longer matches g_dir
datetime g_lastFlipBarSeen=0;

int hMA=INVALID_HANDLE, hMAFast=INVALID_HANDLE, hATR=INVALID_HANDLE;
int hMAFlipSlow=INVALID_HANDLE, hMAFlipFast=INVALID_HANDLE;
int hMAHtfSlow=INVALID_HANDLE, hMAHtfFast=INVALID_HANDLE;   // higher-timeframe alignment filter #1 (NEW 2026-11-21)
int hMAHtf2Slow=INVALID_HANDLE, hMAHtf2Fast=INVALID_HANDLE; // higher-timeframe alignment filter #2 (NEW 2026-11-21)
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

//+------------------------------------------------------------------+
//| Regime (fast-vs-slow MA) cross detection on the ENTRY timeframe     |
//| (M3). Called once per newly CLOSED M3 bar. Only arms g_awaitDir     |
//| for the new cross -- does NOT touch the regime-flip exit (that's    |
//| on a separate, slower timeframe now, see UpdateFlipRegime).         |
//+------------------------------------------------------------------+
void UpdateRegimeAndCross()
{
   double fast1[1],slow1[1];
   if(CopyBuffer(hMAFast,0,1,1,fast1)<1) return;
   if(CopyBuffer(hMA,0,1,1,slow1)<1) return;
   bool bullish=fast1[0]>slow1[0];

   if(!g_regimeKnown){ g_regimeKnown=true; g_regimeBullish=bullish; return; }
   if(bullish==g_regimeBullish) return; // no flip

   g_regimeBullish=bullish;
   if(bullish)
   {
      g_awaitDir=+1; g_awaitBarsElapsed=0;
      Log("GOLDEN_CROSS","awaiting first 120MA pullback touch to BUY");
   }
   else
   {
      g_awaitDir=-1; g_awaitBarsElapsed=0;
      Log("DEAD_CROSS","awaiting first 120MA pullback touch to SELL");
   }
}

//+------------------------------------------------------------------+
//| Regime cross detection on RegimeFlipTimeframe (REVISED 2026-11-21, |
//| decoupled from the M3 entry cross). Called once per newly CLOSED    |
//| bar on THIS timeframe. On a flip, flags an open basket in the OLD   |
//| direction for the regime-flip exit (see UpdateBasketExits). Does    |
//| NOT touch g_awaitDir -- entry arming stays purely M3-driven.        |
//+------------------------------------------------------------------+
void UpdateFlipRegime()
{
   double fast1[1],slow1[1];
   if(CopyBuffer(hMAFlipFast,0,1,1,fast1)<1) return;
   if(CopyBuffer(hMAFlipSlow,0,1,1,slow1)<1) return;
   bool bullish=fast1[0]>slow1[0];

   if(!g_flipRegimeKnown){ g_flipRegimeKnown=true; g_flipRegimeBullish=bullish; return; }
   if(bullish==g_flipRegimeBullish) return; // no flip
   g_flipRegimeBullish=bullish;

   if(g_state==GS_BASKET && !g_regimeFlippedAgainstBasket)
   {
      bool basketIsBullish=(g_dir>0);
      if(basketIsBullish!=bullish)
      {
         g_regimeFlippedAgainstBasket=true;
         Log("REGIME_FLIPPED_AGAINST_BASKET","("+EnumToString(RegimeFlipTimeframe)+") basket dir="+(g_dir>0?"BUY":"SELL")+" -- will close at breakeven+"+DoubleToString(RegimeFlipMinProfitSteps,2)+" steps ASAP");
      }
   }
}

//+------------------------------------------------------------------+
//| Higher-timeframe alignment check (NEW 2026-11-21, per 탑다운 분석     |
//| 매뉴얼 '탑다운 분석 방향과 일치하는지 확인'; EXTENDED to a second         |
//| required timeframe 2026-11-21 per user request). Read fresh at       |
//| entry time, not bar-cached -- called once per prospective entry,     |
//| not every tick. Returns true iff the given fast/slow MA pair's        |
//| (closed-bar) alignment matches dir (bullish for BUY, bearish SELL).   |
//+------------------------------------------------------------------+
bool TFAligned(int dir,int hFast,int hSlow)
{
   double fast1[1],slow1[1];
   if(CopyBuffer(hFast,0,1,1,fast1)<1) return false;
   if(CopyBuffer(hSlow,0,1,1,slow1)<1) return false;
   bool bullish=fast1[0]>slow1[0];
   return (dir>0) ? bullish : !bullish;
}

//+------------------------------------------------------------------+
//| Swing high/low over a lookback window, read at entry time          |
//| (closed bars only, shift 1..SwingLookbackBars). Used as the        |
//| "전고점"/"전저점" TP target -- see header, REVISED 2026-11-21.        |
//+------------------------------------------------------------------+
double SwingHigh(int lookback)
{
   int idx=iHighest(_Symbol,Timeframe,MODE_HIGH,lookback,1);
   if(idx<0) return 0;
   return iHigh(_Symbol,Timeframe,idx);
}

double SwingLow(int lookback)
{
   int idx=iLowest(_Symbol,Timeframe,MODE_LOW,lookback,1);
   if(idx<0) return 0;
   return iLow(_Symbol,Timeframe,idx);
}

// -- Korea-time session helper (server clock -> KST, EU-DST aware), ported
//    unchanged from the live 001/005/006/007/010-013 files in this repo. ---
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
void PlaceGrid(double step,double tpCandidate)
{
   g_step=step;
   g_sl=NP(g_p0-g_dir*SLMult*step);
   g_basketOpenTime=TimeCurrent();

   //--- validate the swing-extreme TP: must be favorable by at least
   //    MinSwingTPStep steps from P0, else there's no real target to give
   //    (e.g. the prior swing extreme sits behind or too close to entry) --
   //    fall back to no hard TP (hard SL / UseRegimeFlipExit only) for this basket.
   g_tp=0;
   if(UseSwingTP && tpCandidate>0)
   {
      double favDist=(g_dir>0) ? (tpCandidate-g_p0) : (g_p0-tpCandidate);
      if(favDist>=MinSwingTPStep*step)
      {
         double cushion=MinStopDistance()+_Point;
         double tpCand=tpCandidate;
         MqlTick qtp; if(SymbolInfoTick(_Symbol,qtp))
         {
            if(g_dir>0){ if(tpCand<qtp.ask+cushion) tpCand=qtp.ask+cushion; }
            else       { if(tpCand>qtp.bid-cushion) tpCand=qtp.bid-cushion; }
         }
         g_tp=NP(tpCand);
      }
      else
         Log("SWING_TP_REJECTED","target="+DoubleToString(tpCandidate,_Digits)+" too close/behind P0="+DoubleToString(g_p0,_Digits)+" (favDist<"+DoubleToString(MinSwingTPStep,2)+" steps) -- no hard TP this basket");
   }

   if(!EnableLiveOrders)
   {
      Log("DRY_GRID","P0="+DoubleToString(g_p0,_Digits)+" step="+DoubleToString(step,_Digits)+" SL="+DoubleToString(g_sl,_Digits)+" TP="+DoubleToString(g_tp,_Digits));
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

   //--- 1) set SL+TP on the first-entry position
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0 || !PositionSelectByTicket(t)) continue;
      if(!IsMine((ulong)PositionGetInteger(POSITION_MAGIC),PositionGetString(POSITION_SYMBOL))) continue;
      if(!trade.PositionModify(t,g_sl,g_tp))
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
         ok=(g_dir>0 ? trade.Buy(lot,_Symbol,0.0,g_sl,g_tp,cmt) : trade.Sell(lot,_Symbol,0.0,g_sl,g_tp,cmt));
         Log("GRID_LEG_MARKET",IntegerToString(k)+" level="+DoubleToString(level,_Digits)+" "+(ok?"FILLED":"FAILED"));
      }
      else
      {
         ok=(g_dir>0 ? trade.BuyLimit (lot,level,_Symbol,g_sl,g_tp,ORDER_TIME_GTC,0,cmt)
                     : trade.SellLimit(lot,level,_Symbol,g_sl,g_tp,ORDER_TIME_GTC,0,cmt));
         Log("GRID_LEG_PENDING",IntegerToString(k)+" level="+DoubleToString(level,_Digits)+" "+(ok?"PLACED":"FAILED"));
      }
      if(!ok) Log("GRID_LEG_RETCODE",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
      bid=SymbolInfoDouble(_Symbol,SYMBOL_BID); ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   }

   g_state=GS_BASKET;
   Log("GRID_COMPLETE","P0="+DoubleToString(g_p0,_Digits)+" step="+DoubleToString(step,_Digits)+" SL="+DoubleToString(g_sl,_Digits)+" TP="+DoubleToString(g_tp,_Digits));
}

//+------------------------------------------------------------------+
//| Basket exits (NEW -- not in the manual tool): the ONLY exit handled  |
//| here is the regime-flip breakeven close (see comment inside).        |
//+------------------------------------------------------------------+
void UpdateBasketExits()
{
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

   //--- ONLY exit this function handles: regime flipped against this basket
   //    (checklist '04 정배/역배 대응', confirmed 2026-11-21) -- while the
   //    regime stays ALIGNED with g_dir, there is NO other exit here; the
   //    basket just waits on UseSwingTP/the hard SL. A prior revision also
   //    ran an unconditional breakeven-recovery trail regardless of regime
   //    state (UseBasketTrailStop/UseBreakevenExit) -- REMOVED 2026-11-21
   //    after a backtest (NET $611->-$4,410, win rate 65%->54%, avg win
   //    $125->$56) showed it was cutting aligned-trend winners short before
   //    they reached the real ① target, exactly as the user flagged.
   if(!UseRegimeFlipExit || !g_regimeFlippedAgainstBasket) return;
   if(favSteps<RegimeFlipMinProfitSteps) return;

   Log("REGIME_FLIP_CLOSE","favSteps="+DoubleToString(favSteps,3)+" >= RegimeFlipMinProfitSteps="+DoubleToString(RegimeFlipMinProfitSteps,2));
   if(EnableLiveOrders) CloseAllPositions();
   else Log("REGIME_FLIP_CLOSE_DRY","would close now (EnableLiveOrders=false)");
   g_regimeFlippedAgainstBasket=false; // consumed -- avoid repeated close attempts
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
       " finalTP="+DoubleToString(g_tp,_Digits)+" basketProfit="+DoubleToString(basketProfit,2));

   g_state=GS_IDLE; g_dir=0; g_p0=0; g_step=0; g_sl=0; g_tp=0; g_basketOpenTime=0;
   g_regimeFlippedAgainstBasket=false;
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
   g_tp=PositionGetDouble(POSITION_TP);
   g_basketOpenTime=earliest;
   g_step=(g_sl>0 && SLMult>0) ? MathAbs(g_p0-g_sl)/SLMult : GetStep();
   g_state=GS_BASKET;
   Log("RECOVERED","dir="+(g_dir>0?"BUY":"SELL")+" P0="+DoubleToString(g_p0,_Digits)+
       " step="+DoubleToString(g_step,_Digits)+" SL="+DoubleToString(g_sl,_Digits)+" TP="+DoubleToString(g_tp,_Digits));
}

//+------------------------------------------------------------------+
//| Events                                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   hMA    =iMA(_Symbol,Timeframe,MAPeriod,0,MODE_SMA,PRICE_CLOSE);
   hMAFast=iMA(_Symbol,Timeframe,MAFastPeriod,0,MODE_SMA,PRICE_CLOSE);
   hATR   =iATR(_Symbol,Timeframe,StepATRPeriod);
   hMAFlipSlow=iMA(_Symbol,RegimeFlipTimeframe,MAPeriod,0,MODE_SMA,PRICE_CLOSE);
   hMAFlipFast=iMA(_Symbol,RegimeFlipTimeframe,MAFastPeriod,0,MODE_SMA,PRICE_CLOSE);
   hMAHtfSlow =iMA(_Symbol,HigherTFAlignment,MAPeriod,0,MODE_SMA,PRICE_CLOSE);
   hMAHtfFast =iMA(_Symbol,HigherTFAlignment,MAFastPeriod,0,MODE_SMA,PRICE_CLOSE);
   hMAHtf2Slow=iMA(_Symbol,HigherTFAlignment2,MAPeriod,0,MODE_SMA,PRICE_CLOSE);
   hMAHtf2Fast=iMA(_Symbol,HigherTFAlignment2,MAFastPeriod,0,MODE_SMA,PRICE_CLOSE);
   if(hMA==INVALID_HANDLE || hMAFast==INVALID_HANDLE || hATR==INVALID_HANDLE ||
      hMAFlipSlow==INVALID_HANDLE || hMAFlipFast==INVALID_HANDLE ||
      hMAHtfSlow==INVALID_HANDLE || hMAHtfFast==INVALID_HANDLE ||
      hMAHtf2Slow==INVALID_HANDLE || hMAHtf2Fast==INVALID_HANDLE) return INIT_FAILED;

   f_log=FileOpen("XAU_M3_MATOUCHGRID_test_LOG.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
   if(f_log!=INVALID_HANDLE)
   {
      FileSeek(f_log,0,SEEK_END);
      if(FileTell(f_log)==0) FileWrite(f_log,"TIME","EVENT","DETAIL");
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(MaxDeviationPts);
   trade.SetTypeFillingBySymbol(_Symbol);

   Log("START",string("TF=")+EnumToString(Timeframe)+" | MAFastPeriod="+IntegerToString(MAFastPeriod)+
       " MAPeriod="+IntegerToString(MAPeriod)+" MaxWaitBars="+IntegerToString(MaxWaitBars)+
       " | UseATRStep="+(UseATRStep?"true":"false")+" StepATRPeriod="+IntegerToString(StepATRPeriod)+
       " StepATRMult="+DoubleToString(StepATRMult,2)+" GridStepPoints="+DoubleToString(GridStepPoints,1)+
       " | Lots="+DoubleToString(Lots,2)+" GridCount="+IntegerToString(GridCount)+" SLMult="+DoubleToString(SLMult,2)+
       " | UseSwingTP="+(UseSwingTP?"true":"false")+" SwingLookbackBars="+IntegerToString(SwingLookbackBars)+
       " MinSwingTPStep="+DoubleToString(MinSwingTPStep,2)+
       " | UseRegimeFlipExit="+(UseRegimeFlipExit?"true":"false")+" RegimeFlipMinProfitSteps="+DoubleToString(RegimeFlipMinProfitSteps,2)+
       " RegimeFlipTimeframe="+EnumToString(RegimeFlipTimeframe)+
       " | UseHigherTFAlignment="+(UseHigherTFAlignment?"true":"false")+" HigherTFAlignment="+EnumToString(HigherTFAlignment)+
       " UseHigherTFAlignment2="+(UseHigherTFAlignment2?"true":"false")+" HigherTFAlignment2="+EnumToString(HigherTFAlignment2)+
       " | UseSkipHourKST="+(UseSkipHourKST?"true":"false")+" SkipHourStartKST="+IntegerToString(SkipHourStartKST)+
       " SkipHourEndKST="+IntegerToString(SkipHourEndKST)+
       " | Magic="+IntegerToString((int)MagicNumber)+" | orders="+(EnableLiveOrders?"ENABLED":"DRY"));

   g_state=GS_IDLE;
   RecoverState();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(f_log!=INVALID_HANDLE){ FileFlush(f_log); FileClose(f_log); }
   if(hMA!=INVALID_HANDLE)         IndicatorRelease(hMA);
   if(hMAFast!=INVALID_HANDLE)     IndicatorRelease(hMAFast);
   if(hATR!=INVALID_HANDLE)        IndicatorRelease(hATR);
   if(hMAFlipSlow!=INVALID_HANDLE) IndicatorRelease(hMAFlipSlow);
   if(hMAFlipFast!=INVALID_HANDLE) IndicatorRelease(hMAFlipFast);
   if(hMAHtfSlow!=INVALID_HANDLE)  IndicatorRelease(hMAHtfSlow);
   if(hMAHtfFast!=INVALID_HANDLE)  IndicatorRelease(hMAHtfFast);
   if(hMAHtf2Slow!=INVALID_HANDLE) IndicatorRelease(hMAHtf2Slow);
   if(hMAHtf2Fast!=INVALID_HANDLE) IndicatorRelease(hMAHtf2Fast);
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

   //--- new-bar bookkeeping (M3, entry cross + wait-timeout counting),
   //    independent of g_state so a cross can arm/override while flat.
   datetime curBar=iTime(_Symbol,Timeframe,0);
   if(curBar!=0 && curBar!=g_lastBarSeen)
   {
      g_lastBarSeen=curBar;
      UpdateRegimeAndCross(); // may set/overwrite g_awaitDir, resets g_awaitBarsElapsed
      if(g_awaitDir!=0) g_awaitBarsElapsed++;
      if(MaxWaitBars>0 && g_awaitDir!=0 && g_awaitBarsElapsed>=MaxWaitBars)
      {
         Log("AWAIT_TIMEOUT","bars="+IntegerToString(g_awaitBarsElapsed)+" -- giving up on this cross episode (no entry)");
         g_awaitDir=0;
      }
   }

   //--- new-bar bookkeeping (RegimeFlipTimeframe, decoupled from the above --
   //    see UpdateFlipRegime). Runs on its own cadence regardless of Timeframe.
   datetime curFlipBar=iTime(_Symbol,RegimeFlipTimeframe,0);
   if(curFlipBar!=0 && curFlipBar!=g_lastFlipBarSeen)
   {
      g_lastFlipBarSeen=curFlipBar;
      UpdateFlipRegime(); // may set g_regimeFlippedAgainstBasket
   }

   switch(g_state)
   {
      case GS_IDLE:
      {
         if(g_awaitDir==0) return; // no cross episode currently awaiting its first 120MA touch
         double ma; if(!GetMA(ma)) return;
         double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
         bool touched=(g_awaitDir>0)?(bid<=ma):(bid>=ma);
         if(!touched) return;

         if(UseSkipHourKST)
         {
            int kstHour=KST_Hour(TimeCurrent());
            bool inSkip=(kstHour>=SkipHourStartKST && kstHour<SkipHourEndKST);
            if(inSkip)
            {
               Log("ENTRY_SKIPPED","KST hour in ["+IntegerToString(SkipHourStartKST)+","+IntegerToString(SkipHourEndKST)+") -- episode stays armed, retry on a later touch");
               return;
            }
         }

         if(UseHigherTFAlignment && !TFAligned(g_awaitDir,hMAHtfFast,hMAHtfSlow))
         {
            Log("ENTRY_SKIPPED","HigherTFAlignment ("+EnumToString(HigherTFAlignment)+") not aligned with "+(g_awaitDir>0?"BUY":"SELL")+" -- episode stays armed, retry on a later touch");
            return;
         }
         if(UseHigherTFAlignment2 && !TFAligned(g_awaitDir,hMAHtf2Fast,hMAHtf2Slow))
         {
            Log("ENTRY_SKIPPED","HigherTFAlignment2 ("+EnumToString(HigherTFAlignment2)+") not aligned with "+(g_awaitDir>0?"BUY":"SELL")+" -- episode stays armed, retry on a later touch");
            return;
         }

         g_dir=g_awaitDir;
         g_awaitDir=0; // consume -- only the FIRST touch after this cross enters

         if(!DoFirstEntry())
         {
            g_awaitDir=g_dir; g_dir=0; // restore, retry next tick
            return;
         }
         double step=GetStep();
         double tpCandidate=UseSwingTP ? (g_dir>0 ? SwingHigh(SwingLookbackBars) : SwingLow(SwingLookbackBars)) : 0;
         PlaceGrid(step,tpCandidate);
         return;
      }

      case GS_BASKET:
      {
         FinalizeBasketIfFlat();
         if(g_state==GS_BASKET) UpdateBasketExits();
         return;
      }
   }
}
//+------------------------------------------------------------------+
