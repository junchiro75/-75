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
//|                                                                     |
//| NINTH REVISION (2026-11-21, per user's own detailed strategy             |
//| description, REPLACES the 7th revision's H1 cross-alignment skip-gate):   |
//| H1's CURRENT price vs its own MAFastPeriod(20) MA now DECIDES the final    |
//| trade direction outright (DecideFinalDir()), rather than confirming or     |
//| skipping the M3 cross's direction -- e.g. an M3 golden cross + first       |
//| 120MA touch while H1 price sits BELOW H1's 20MA now enters SELL (counter   |
//| to the golden cross), not a skip; while H1 price is ABOVE enters BUY       |
//| (agrees with the golden cross). The user's own reasoning: early in a       |
//| golden-cross regime H1 often hasn't caught up yet (counter-trend SELL      |
//| likely on the FIRST such M3 signal), but by a LATER M3 golden-cross+touch  |
//| H1 has often caught up too (BUY likely then) -- this falls out naturally   |
//| from re-reading H1's live state at each touch, no explicit occurrence      |
//| count needed. CounterTrendTPShrink (0.5 default) shrinks the swing-TP      |
//| favorable distance from P0 whenever the H1-decided direction disagrees     |
//| with the M3 cross's own direction ("기존보다 다소 적은 범위로 익절"),         |
//| reflecting the lower conviction of a counter-trend entry. The 2nd-         |
//| timeframe check (H4, 8th revision) is now checked against this FINAL       |
//| direction, not the raw M3 cross direction. hMAHtfSlow (H1's 120MA)         |
//| removed -- H1's own cross is no longer used, only price-vs-20MA. Not yet   |
//| backtested.                                                              |
//|                                                                     |
//| TENTH REVISION (2026-11-21, per user request, confirmed theory         |
//| "기본비를 맞으면 보통 반대방향으로 간다"): UseHtfBB4Exhaustion added --        |
//| TAKES PRIORITY over the 9th revision's price-vs-20MA override. At a      |
//| golden cross, if HigherTFAlignment's last CLOSED candle is bullish AND    |
//| its high touches the upper BB4(4,4,PRICE_OPEN) band ("상단 기본비", the    |
//| SAME construct as 010-013's signal), the exhaustion fade overrides to     |
//| SELL regardless of what price-vs-20MA would say; symmetric for a dead     |
//| cross + bearish candle touching the lower band -> BUY. When it fires,     |
//| this still counts as counter-trend if it disagrees with the M3 cross's    |
//| own direction (CounterTrendTPShrink applies the same way). If it does     |
//| NOT fire, falls through to the 9th revision's price-vs-20MA override      |
//| unchanged. New hBB4Htf handle (iBands on HigherTFAlignment).               |
//|                                                                     |
//| EIGHTH BACKTEST (2026-11-21, 10th revision as above, new best of the      |
//| whole session): NET +$23,972.51, PF 1.153543, RF 0.792339, Sharpe         |
//| 0.880681, Balance DD 15.32% ($19,647), Equity DD 22.04% ($30,255,         |
//| WORSE than balance DD) on 1,147 baskets. Equity-vs-Balance DD gap          |
//| investigated via deal-level basket reconstruction: 87/349 baskets         |
//| (25%) reach full grid depth (all 5 DCA legs), of which 78 close at a      |
//| loss (avg -$1,484) and only 9 recover to profit -- but those 9            |
//| recoveries (one took 133 hours) sat on several-thousand-dollar            |
//| UNREALIZED losses the whole time, which is what inflates Equity DD        |
//| without touching Balance DD. Full-depth loss size formula derived and     |
//| confirmed exactly against the data: loss ≈ step*(GridCount+1)²/2*$10      |
//| (per 0.1 lot) -- for a FIXED total range, loss scales with GridCount,     |
//| not range alone, because more legs means more accumulated volume by       |
//| the time the shared SL is reached.                                       |
//|                                                                     |
//| ELEVENTH REVISION: GridCount/SLMult swept 5/5.5 -> 3/3.5 -> 2/2.5 ->      |
//| 1/1.5 (step fixed at $10 throughout). Results: RF 0.79 -> 1.31 -> 2.03    |
//| -> 1.43; NET $23,973 -> $25,103 -> $30,220 -> $14,795; Equity DD 22.0% -> |
//| 14.4% -> 11.7% -> 10.2%. GridCount=2 is the CONFIRMED local optimum --    |
//| every metric peaks there; GridCount=1 shrinks the DCA "rescue margin"     |
//| too far and NET/PF/RF/Sharpe all fall back, even though per-trade risk    |
//| keeps improving (payoff ratio climbs to 3.84:1, but win rate collapses    |
//| to 24.37%). SwingLookbackBars was separately tested at 20 (vs the         |
//| existing 50, GridCount=2 held constant): worse on every metric (NET       |
//| $30,220->$25,870, RF 2.03->1.49, Equity DD 11.7%->13.9%) -- 50 CONFIRMED. |
//|                                                                     |
//| TWELFTH REVISION (2026-11-21, per user's "탑다운 분석 매뉴얼" checklist     |
//| section "피해야 할 구간 4가지" (4 zones to avoid), user chose option 1):      |
//| two new entry-side skip-gates added, checked right after the existing     |
//| H4 alignment gate, before an armed episode is allowed to fire. Each is a  |
//| skip only (same pattern as the other gates) -- the armed episode stays    |
//| alive for a later touch, it is not discarded. Zone #1 (상위저항,           |
//| "H1 기본비+120이평 겹침"): UseAvoidBB4MAOverlap skips if HigherTFAlignment's |
//| upper OR lower BB4(4,4,PRICE_OPEN) band sits within AvoidBB4MAOverlapPts   |
//| of HigherTFAlignment's own 120-period MA (hMAHtfSlow, re-added for this    |
//| purpose -- H1's cross is still not used, only this band/MA distance).     |
//| Zone #2 (가짜돌파, "H1 전고/전저 가짜돌파"): UseAvoidFakeBreakout skips if    |
//| HigherTFAlignment's last CLOSED candle poked through the prior            |
//| FakeBreakoutLookbackBars swing high/low but closed back inside it, in the  |
//| SAME direction as the final (post-override) trade direction -- a failed   |
//| breakout trap. Zone #3 (새벽 2-8시 KST) was already implemented as          |
//| UseSkipHourKST. Zone #4 (5대 경제지표 발표) is OUT OF SCOPE -- needs the     |
//| MT5 economic calendar API, not built. Not yet backtested.                 |
//|                                                                     |
//| TWELFTH BACKTEST (2026-11-21, 12th revision as above, isolated 3-way     |
//| sweep of the two avoid zones vs the GridCount=2/SLMult=2.5/Swing=50       |
//| no-filter baseline (NET $30,220, RF 2.03, Equity DD 11.7%, PF ~1.21)):     |
//| zone #1 ONLY -> NET $31,651.25, PF 1.338244, RF 2.117905 (best of all 4   |
//| configs), Balance DD 9.88% ($10,224.76), Equity DD 11.75% ($14,944.60),   |
//| Sharpe 1.937987. zone #2 ONLY -> NET $30,383.12, PF 1.320711, RF          |
//| 1.876669 (WORSE than baseline's 2.03), Balance DD 10.26%, Equity DD       |
//| 12.76%, Sharpe 1.827618. BOTH ON -> NET $31,542.84, PF 1.338639, RF       |
//| 1.864183, Balance DD 10.19%, Equity DD 13.33% ($16,920.46, worst of all   |
//| 4). CONCLUSION: zone #1 (BB4/120MA overlap) drives essentially all of     |
//| the improvement and dominates every metric; zone #2 (fake breakout) is    |
//| net harmful on its own and is what drags RF/Equity DD down when BOTH are  |
//| on. UseAvoidFakeBreakout default CHANGED to false (zone #2 OFF); zone #1  |
//| (UseAvoidBB4MAOverlap=true) CONFIRMED as the new default going forward.   |
//|                                                                     |
//| THIRTEENTH BACKTEST (2026-11-21, SLMult sweep at fixed step=$10,          |
//| GridCount=2, zone #1 ON/zone #2 OFF per the 12th revision): SLMult=3.5    |
//| (SL $25->$35, buffer beyond last leg $5->$15, entries UNCHANGED at        |
//| 0/10/20) tested against the SLMult=2.5 confirmed baseline (NET           |
//| $31,651.25, PF 1.338244, RF 2.117905, Equity DD 11.75%): NET dropped to   |
//| $24,580.55, PF 1.218068, RF 1.365905, Equity DD 13.70% ($17,995.80),      |
//| Sharpe 1.343059 -- worse on every metric except a marginally smaller      |
//| Balance DD %. Same pattern as the GridCount/SLMult sweep in the 11th      |
//| revision: widening the SL (without adding legs) grows the loss size      |
//| per full-depth hit faster than it saves from fewer hits. SLMult=2.5      |
//| CONFIRMED to remain the optimum; user chose to keep it and move on.       |
//|                                                                     |
//| FOURTEENTH REVISION (2026-11-21, per checklist "피해야 할 구간 4가지"       |
//| zone #4, previously flagged out-of-scope -- user asked for it anyway):    |
//| UseAvoidEconCalendar added as a 4th skip-gate (same armed-episode-stays-  |
//| alive pattern as zones #1/#2). Uses MQL5's native CalendarValueHistory()/ |
//| CalendarEventById() -- NOT a new handle, just an API call each check.     |
//| Skips a touch if an AvoidEconCalendarCurrency (default "USD", proxy for   |
//| the "5대 경제지표" set since MT5's calendar isn't easily filtered to 5     |
//| specific named indicators) calendar event at >=AvoidEconCalendarMin-      |
//| Importance (default CALENDAR_IMPORTANCE_HIGH) has its release time within |
//| [-AvoidEconCalendarMinutesBefore,+AvoidEconCalendarMinutesAfter] minutes   |
//| (default 30/30) of the current tick. CAVEAT, UNCONFIRMED: MT5 Strategy    |
//| Tester's calendar support depends on the terminal/broker actually having  |
//| cached calendar data for the test's date range -- a CALENDAR_DIAG log     |
//| line was added at OnInit to report how many qualifying events it finds    |
//| across the backtest's 2025.01.01-2026.12.31 span; if that logs 0, this    |
//| filter is a silent no-op and the feature does not work in this tester.    |
//| Not yet backtested.                                                      |
//|                                                                     |
//| FOURTEENTH BACKTEST (2026-11-21, UseAvoidEconCalendar=true test):         |
//| result was BYTE-IDENTICAL to the zone-1-only baseline (NET $31,651.25,    |
//| PF 1.338244, RF 2.117905, 976 trades, all to the decimal) -- CONFIRMS     |
//| the filter never fired even once. Strategy Tester has no calendar data    |
//| cached for this period/symbol; the feature may still work live but is    |
//| unverifiable in this tester. Set aside per user request, not removed.    |
//|                                                                     |
//| FIFTEENTH BACKTEST (2026-11-21, UseHigherTFAlignment2=false test, H4      |
//| gate removed, everything else at the confirmed baseline): baskets        |
//| 429->670 (+56%), but NET $31,651.25->$11,756.32 (-63%), PF 1.338->1.087,  |
//| RF 2.118->0.611, Sharpe 1.938->0.673, Balance DD 9.88%->13.82%, Equity DD |
//| 11.75%->15.67%. H4 alignment CONFIRMED to earn its keep (filters bad      |
//| trades, not just volume) -- reverted, stays true going forward.           |
//|                                                                     |
//| BASKET-DEPTH DIAGNOSTIC (2026-11-21, custom Python reconstruction of the  |
//| zone-1-only baseline's order/deal tables, 429 baskets): close reason      |
//| breakdown -- SL 196 (45.7%, ALL losses, sum -$88,212.90, avg -$450.07),   |
//| FLIP/regime-flip-exit 166 (38.7%, 97.6% win rate, sum +$97,767.50, the    |
//| SINGLE BIGGEST profit source, bigger than TP), TP 66 (15.4%, 100% win     |
//| rate, sum +$20,029.30). By depth reached: 1-leg (114) and 2-leg (83)      |
//| baskets have a 0% SL rate and are PURE PROFIT ($87,851.20 combined,       |
//| zero losses); ALL 196 SL losses -- and 84.5% of the 232 full-depth        |
//| (3-leg) baskets -- occur ONLY once every grid leg has filled. An earlier  |
//| IQR-outlier pass (26 baskets, 6%, contributing +$74,173.20) had looked    |
//| like a few lucky trades carried the whole backtest, but re-examined by    |
//| close reason that turned out to be the FLIP mechanism working exactly as  |
//| designed (92% of those outliers closed via FLIP, avg hold 96.3h) -- not   |
//| noise. This depth breakdown directly motivated the 16th revision below.   |
//|                                                                     |
//| SIXTEENTH REVISION (2026-11-21, per user request, directly targeting the  |
//| basket-depth diagnostic above): two new checks, both reusing             |
//| BadSignalAgainstDir(dir) -- true if ANY of M3's own 20/120 cross, H1's    |
//| price-vs-20MA, or H4's fast/slow MA cross now disagrees with dir (NOT     |
//| the H1 BB4 exhaustion signal, which is an entry-timing trick, not a       |
//| sustained regime read). (1) UseLastLegConfirm: right before the LAST      |
//| grid leg would fill (GridCount-1 legs already in, one pending), re-run    |
//| BadSignalAgainstDir -- if true, cancel that leg so the basket caps below  |
//| the full-depth cohort where ALL SL losses occur. (2) UseFullDepthBad-     |
//| SignalExit: once a basket DOES reach full depth, if BadSignalAgainstDir   |
//| fires, arm the SAME breakeven-or-better close as UseRegimeFlipExit (sets  |
//| g_regimeFlippedAgainstBasket) -- a second, faster-reacting trigger source |
//| alongside RegimeFlipTimeframe's own slower M15 cross, not a replacement   |
//| for it. User's own framing: "구간매매하는 사람들" re-check direction        |
//| mid-ladder and bail at breakeven if it looks wrong, maximize if it still  |
//| looks right -- this is that, built on the exact depth/reason split found  |
//| above.                                                                   |
//|                                                                     |
//| SEVENTEENTH BACKTEST (2026-11-21, isolated 3-way A/B of the 16th         |
//| revision's two switches vs the no-filter baseline (NET $31,651.25, PF     |
//| 1.338244, RF 2.117905, Balance DD 9.88%, Equity DD 11.75%)): zone-1-only  |
//| i.e. UseLastLegConfirm ONLY -> NET $26,890.70, PF 1.319100, RF 2.635687,  |
//| Balance DD 9.41%, Equity DD 8.36% ($10,202.54, BEST of all 4 configs).    |
//| UseFullDepthBadSignalExit ONLY -> NET $22,053.91, PF 1.258319, RF         |
//| 1.752320 (WORSE than baseline's 2.118), Balance DD 11.83% (worse than     |
//| baseline), Equity DD 12.26% -- worse than baseline on nearly every        |
//| metric. BOTH ON -> NET $28,365.24, PF 1.343067, RF 2.680406 (best NET/RF  |
//| of the 4), Balance DD 9.81%, Equity DD 10.26% (worse than LastLegConfirm  |
//| alone). CONCLUSION: UseLastLegConfirm drives essentially all of the       |
//| improvement and gives the best Equity DD; UseFullDepthBadSignalExit is    |
//| net harmful alone but adds a little extra NET/RF on top of               |
//| LastLegConfirm at the cost of some Equity DD. User chose stability:       |
//| UseFullDepthBadSignalExit default CHANGED to false; UseLastLegConfirm     |
//| (true) CONFIRMED as the new default going forward.                       |
//|                                                                     |
//| EIGHTEENTH REVISION (2026-11-21, per user request, motivated by the      |
//| FLIP-dependent "occasional big win" structure feeling too unstable):     |
//| UseProfitTrail added -- distinct from the REMOVED UseBreakevenExit (4th   |
//| revision), which ran unconditionally from ANY profit level and cut       |
//| aligned-trend winners short. This only arms once favSteps EVER reaches   |
//| ProfitTrailActivateSteps (5.0 steps = $50 = 2x the current $25 SL, the    |
//| user's own framing), then trails the best favorable price by            |
//| ProfitTrailDistanceSteps (1.0 step = $10), FLOORED at breakeven so it     |
//| can never lock in a loss once armed. Runs every tick in UpdateBasketExits|
//| regardless of regime state, ahead of the existing regime-flip check --   |
//| an ADDITIONAL protective layer, not a replacement for UseSwingTP or      |
//| UseRegimeFlipExit (both unchanged and can still fire first). Intent:     |
//| catch a big unrealized gain (the kind that currently requires waiting    |
//| out a slow M15 regime-flip, sometimes 96+ hours per the basket-depth     |
//| diagnostic above) and lock most of it in well before it can fully        |
//| round-trip back to breakeven or a loss.                                  |
//|                                                                     |
//| NINETEENTH BACKTEST (2026-11-21, UseProfitTrail=true test, everything     |
//| else at the confirmed 17th-revision baseline): NET $26,890.70->$4,956.80  |
//| (-82%), PF 1.319100->1.038888 (near breakeven), RF 2.635687->0.385929     |
//| (collapsed), Sharpe 1.972821->0.531451, Balance DD 9.41%->11.34%, Equity  |
//| DD 8.36%->11.99% -- worse on every metric. Smoking gun: max winning       |
//| trade $3,434.01->$1,058.54 -- the $50-activate/$10-trail combo cut the    |
//| FLIP mechanism's big wins short almost exactly like the REMOVED (4th      |
//| revision) UseBreakevenExit, just at a higher trigger threshold. Trade     |
//| count rose 762->1,183 (closing more often, each for less). REJECTED --    |
//| UseProfitTrail default CHANGED to false; reverted to the confirmed        |
//| 17th-revision baseline (UseLastLegConfirm=true, UseFullDepthBadSignal-    |
//| Exit=false, everything else unchanged).                                  |
//|                                                                     |
//| TWENTIETH REVISION (2026-11-22, DIAGNOSTIC ONLY, no behavior change, per   |
//| user request): g_peakFavSteps tracks the running max of favSteps (the    |
//| same favorable-distance-in-steps already used by UseProfitTrail/         |
//| UseRegimeFlipExit) over each basket's WHOLE life, logged on the existing  |
//| BASKET_CLOSED line as "peakFavSteps=". Goal: cross-reference against     |
//| which baskets closed via SL (per the deals table's "sl ..." comment) to  |
//| find the average max-favorable-excursion among baskets that EVENTUALLY   |
//| lost, as a possible data-driven profit-lock threshold (the 19th          |
//| backtest's guessed $50/$10 trail was rejected -- this is step 1 toward a  |
//| better-calibrated number instead of another guess). Needs the EA's own   |
//| XAU_M3_MATOUCHGRID_test_LOG.csv (not the Strategy Tester's xlsx report)   |
//| to read back. The follow-up log-based MFE analysis found the loser/      |
//| winner MFE distributions overlap too heavily to support any clean        |
//| threshold-based early exit (SL median MFE $9.16 vs TP's own minimum      |
//| $8.65) -- that avenue was dropped. A max-wait-after-flip-armed time cap   |
//| was also checked and dropped: ALL 22 armed-then-SL baskets resolved      |
//| within 12h anyway (no loss-savings from any cap), while FLIP's rare      |
//| long-wait baskets (up to 136h) are worth $2,800+ and would be cut short.  |
//|                                                                     |
//| TWENTY-FIRST REVISION (2026-11-23, per user request: "1시간봉하고           |
//| 4시간봉하고 일치하지 않을때 반대방향으로 진입하면"): UseH1H4DisagreeReversal     |
//| added. Compares H1's OWN price-vs-20MA read (DecideFinalDir) against     |
//| H4's OWN fast/slow MA cross direction (new CrossDir() helper -- unlike   |
//| TFAligned, returns the actual direction, not just "does it match X") --  |
//| if they disagree with EACH OTHER (independent of what the BB4/H1-        |
//| override/M3-cross chain already decided), INVERTS finalDir instead of    |
//| entering it as-is. When true, this SUPERSEDES the existing               |
//| UseHigherTFAlignment2 skip-gate entirely (mutually exclusive by          |
//| construction: after inverting, finalDir always equals h4Dir, so the old  |
//| skip-gate would be a no-op anyway). isCounterTrend is recomputed after   |
//| any inversion so CounterTrendTPShrink still applies correctly. Default   |
//| false (UseHigherTFAlignment2=true stays the confirmed behavior).         |
//|                                                                     |
//| TWENTY-SECOND BACKTEST (2026-11-23, UseH1H4DisagreeReversal=true test,   |
//| everything else at the confirmed baseline): NET $26,890.70->$7,328.21    |
//| (-73%), PF 1.3191->1.057426 (near breakeven), RF 2.635687->0.644076      |
//| (collapsed), Sharpe 1.972821->0.467478, Equity DD 8.36%->10.59%. Trades  |
//| rose 762->1,068 (skip-gate rejections became forced reversed entries     |
//| instead). REJECTED -- H1/H4 disagreement is a low-conviction situation   |
//| the old skip-gate correctly avoided entirely; betting against both       |
//| directions made it worse, not better. UseH1H4DisagreeReversal stays      |
//| false (default).                                                         |
//|                                                                     |
//| TWENTY-THIRD REVISION (2026-11-23, per user request: "3분 장기이평매매는    |
//| 보통 하루 3번 나온다는데 우리껀 1번도 안 나온다" -- the gap is the 'first      |
//| touch per cross episode' design (deliberately chosen over the ORIGINAL   |
//| first backtest's 'every touch', which had PF~1.01, no edge) plus all the |
//| stacked filters since): UseSessionGatedEntry added as a different        |
//| frequency lever -- instead of consuming g_awaitDir after the first entry |
//| per cross, allow one entry per KST-defined session (Asia/Europe/US, new  |
//| SessionIndex() helper) block, keeping g_awaitDir armed across sessions   |
//| (still overwritten immediately by a fresh opposite cross via            |
//| UpdateRegimeAndCross as before). Still capped at one basket open at a    |
//| time by the existing state machine. Default false (existing 'first      |
//| touch, then consume' behavior unchanged). User also asked to test this  |
//| with UseSkipHourKST temporarily OFF (so the US-session window, which     |
//| wraps through 22:00-09:00 KST, isn't cut by the 02:00-08:00 ban).         |
//|                                                                     |
//| TWENTY-THIRD BACKTEST (2026-11-23, UseSessionGatedEntry=true +            |
//| UseSkipHourKST=false test): baskets only 429->467 (+9%, far short of the  |
//| ~3x needed to approach "3/day") -- the session cap wasn't the real        |
//| bottleneck; the 120MA touch itself doesn't recur reliably within every    |
//| session, and the prior basket is often still open into the next session. |
//| NET $26,890.70->$23,597.31 (-12%), PF 1.3191->1.259433, RF 2.635687->     |
//| 2.052999, Sharpe 1.972821->1.713588, Equity DD 8.36%->9.31% (Balance DD   |
//| improved slightly, 9.41%->8.51%). Net negative for a small frequency      |
//| gain -- user then asked whether "every touch" had ever been re-tested    |
//| WITH the current filter stack (only the very first, completely           |
//| unfiltered backtest ever tested "every touch", at PF~1.01).               |
//|                                                                     |
//| TWENTY-FOURTH REVISION (2026-11-23, per that question): UseEveryTouchEntry|
//| added -- g_awaitDir is never zeroed and no session cap is applied either |
//| (SUPERSEDES UseSessionGatedEntry entirely when true), so EVERY touch      |
//| while a cross regime persists can fire an entry, gated only by the        |
//| existing one-basket-at-a-time ceiling and all the filters added since    |
//| the original unfiltered "every touch" test (H1/BB4/H4/avoid-zones/last-  |
//| leg-confirm). Tests whether those filters alone can keep "every touch"    |
//| profitable at much higher frequency. Default false.                      |
//|                                                                     |
//| TWENTY-FIFTH BACKTEST (2026-11-23, UseEveryTouchEntry=true test,          |
//| UseSkipHourKST restored to true): baskets 429->473 (+10%) -- almost        |
//| IDENTICAL to the session-gated test's +9%. CONCLUSION: neither touch-     |
//| consumption rule (first-touch/session-gated/every-touch) is the real      |
//| bottleneck. The actual ceiling is the one-basket-at-a-time state machine  |
//| combined with long average holds (11-12h, up to 140h) -- most of the day  |
//| is spent with a basket already open, so loosening the touch-consumption   |
//| rule barely matters. NET $26,890.70->$23,288.81 (-13%), RF 2.636->1.885,  |
//| Sharpe 1.973->1.663, Equity DD 8.36%->10.16%. Net negative again.         |
//|                                                                     |
//| User then asked to remove UseRegimeFlipExit entirely to see how much of   |
//| the long holds are "waiting on it". TWENTY-SIXTH BACKTEST (2026-11-23,    |
//| UseRegimeFlipExit=false): catastrophic -- only 6 trades in the WHOLE      |
//| 22-month test, avg hold 3,792h (158 days), max 11,290h (470 days). With   |
//| no FLIP exit, a basket that doesn't reach the hard SL or swing TP just    |
//| never closes, and since only one basket can be open at a time, this       |
//| stalls the entire EA for months. UseRegimeFlipExit is not just the        |
//| biggest profit source -- it's a structural release valve the EA needs to  |
//| keep trading at all. Reverted to true immediately.                        |
//|                                                                     |
//| TWENTY-SEVENTH REVISION (2026-11-23, per user's 3-part request: given     |
//| the long-hold problem is structural (one basket at a time + wide SL/TP),  |
//| test (1) concurrent baskets, (2) tighter SL/TP with no concurrency, (3)   |
//| both together):                                                           |
//|                                                                     |
//| (1) MaxConcurrentBaskets: the WHOLE basket-state block (g_state/g_dir/    |
//| g_p0/g_step/g_sl/g_tp/g_basketOpenTime/g_regimeFlippedAgainstBasket/      |
//| g_lastLegChecked/g_profitTrailArmed/g_profitTrailBestPrice/               |
//| g_peakFavSteps) is now an array of MAX_BASKET_SLOTS slots instead of a    |
//| single scalar set. Each slot trades under its own magic number           |
//| (MagicNumber+slot, via SlotMagic()) so positions/orders stay cleanly      |
//| separated per slot using the existing magic-based IsMine() filtering      |
//| (now takes an explicit expectedMagic param). On a touch, the entry logic  |
//| finds the first IDLE slot and opens there instead of refusing outright    |
//| when a basket is already open; MaxConcurrentBaskets=1 reproduces the      |
//| ORIGINAL single-basket behavior exactly. RecoverState() now scans each    |
//| slot's magic range independently on restart. The shared cross-episode     |
//| signal (g_awaitDir) and session-gating state stay global (there is only   |
//| one M3 cross signal; "one entry per session" still means across ALL       |
//| slots collectively, not per slot).                                        |
//|                                                                     |
//| (2) UseFixedRRTp/FixedRRRatio: per user pushback that SwingLookbackBars   |
//| (bar-count based) doesn't reliably scale the ACTUAL price distance of the  |
//| TP target (fewer bars doesn't mean a closer high/low, it's still market-  |
//| dependent) -- added a true fixed-distance alternative: TP = P0 +/-        |
//| SLMult*step*FixedRRRatio, i.e. a hard multiple of the SAME SL distance     |
//| (e.g. SL=$12.5, FixedRRRatio=2.0 -> TP=$25; 1.5 -> TP=$18.75, exactly the  |
//| user's own framing). SUPERSEDES UseSwingTP entirely when true (mutually   |
//| exclusive -- CounterTrendTPShrink does NOT apply to this path, that was   |
//| designed specifically for the swing-target mechanism). Both this AND the  |
//| existing bar-count-based UseSwingTP (with a smaller SwingLookbackBars)    |
//| are left available so both of the user's proposed TP approaches can be    |
//| tested and compared.                                                       |
//|                                                                     |
//| TWENTY-EIGHTH BACKTEST (2026-11-23, MaxConcurrentBaskets 1/2/3/4/5 sweep   |
//| on top of the TIGHTSWING combo -- GridStepPoints=500, SwingLookbackBars=  |
//| 20): monotonically rising on EVERY quality metric, no peak found even at  |
//| the old hard cap of 5 -- baskets 619->966->1142->1242->1324 (basket-count |
//| gains shrinking: +347/+176/+100/+82), NET $13,372->$20,877->$38,138->     |
//| $50,096->$57,994, PF 1.157->1.162->1.253->1.310->1.341 (now ABOVE the     |
//| confirmed baseline's 1.319), RF 1.287->1.534->2.202->2.761->2.901, Sharpe |
//| 1.244->1.333->2.094->2.410->2.534 (well above baseline's 1.973). Balance  |
//| DD/Equity DD plateaued from 3 onward (~10%/~12-13%, not climbing further  |
//| even as NET keeps rising) -- diversification across slots, not just      |
//| more risk piled on. No reversal yet at the cap.                          |
//|                                                                     |
//| TWENTY-NINTH REVISION (2026-11-23, per user request): MAX_BASKET_SLOTS    |
//| raised 5->10 to continue the sweep (6/7/8/9/10) and find where the trend  |
//| actually turns.                                                          |
//|                                                                     |
//| THIRTIETH BACKTEST (2026-11-24, MT5 built-in Optimizer, MaxConcurrentBaskets|
//| 6/7/8/9/10 on the TIGHTSWING combo): the trend FINALLY turns -- 6: NET    |
//| $66,268/PF 1.377/RF 3.052/Sharpe 2.682/DD 12.97%; 7: NET $70,950/PF 1.398/|
//| RF 3.055 (PEAK)/Sharpe 2.746 (PEAK)/DD 13.34%; 8: NET $72,768 (PEAK)/PF   |
//| 1.399 (PEAK)/RF 2.942/Sharpe 2.702/DD 13.93%; 9: NET $70,632/PF 1.382/RF  |
//| 2.855/Sharpe 2.577/DD 14.10%; 10: NET $70,792/PF 1.381/RF 2.862/Sharpe    |
//| 2.541/DD 14.09%. Risk-adjusted metrics (RF/Sharpe) peak at 7; raw NET/PF  |
//| peak at 8; 9-10 are worse than both on every metric -- Equity DD also no |
//| longer plateaus past 6, climbing steadily through 9 (unlike the 1-5      |
//| sweep's plateau from 3 onward), confirming the diversification benefit   |
//| runs out and extra slots past ~8 add pure risk instead.                  |
//|                                                                     |
//| THIRTIETH REVISION (2026-11-24, per user's explicit choice of 7 over 8,  |
//| prioritizing risk-adjusted return): MaxConcurrentBaskets default 1->7,   |
//| UseATRStep default true->false, GridStepPoints default 1000->500 (the    |
//| TIGHTSWING combo is now baked into the file's defaults). SwingLookbackBars|
//| default changed 50->20, SUPERSEDING the old "CONFIRMED over 20" note     |
//| below -- that confirmation was measured under the single-basket (no      |
//| concurrency) architecture; under concurrent baskets the faster-resolving |
//| 20-bar swing target combined with 7 concurrent slots outperforms the old |
//| 50-bar/single-basket setup on every metric (NET $26,890->$70,950, PF     |
//| 1.319->1.398, RF ?->3.055, Sharpe 1.973->2.746). This is now the         |
//| confirmed default.                                                       |
//|                                                                     |
//| KNOWN DIAGNOSTIC-ONLY BUG (2026-11-24, found while cross-checking the    |
//| MaxConcurrentBaskets=7 confirmed run's LOG.csv against the real deals    |
//| table): when 2+ slots are finalized via FinalizeBasketIfFlat's           |
//| HistorySelect(g_basketOpenTime[slot]-1,TimeCurrent())+magic-filter scan  |
//| (line ~1429) in the SAME simultaneous REGIME_FLIP_CLOSE event (all       |
//| slots closing at the identical broker timestamp -- confirmed via         |
//| 2026.01.13 09:30:00: 7 baskets closed together), the logged              |
//| "basketProfit=" value is WRONG for every slot except the one processed   |
//| LAST in that tick -- most of the real pooled profit gets misattributed   |
//| onto that one slot's BASKET_CLOSED line (e.g. slot 6 logged              |
//| basketProfit=14752.08 while slots 0-5, whose REAL deals each show        |
//| +$1,100-1,600 per leg in the raw deals sheet, were all logged as a flat  |
//| -3.00/-commission-only). g_peakFavSteps (tracked live, not via           |
//| HistorySelect) is UNAFFECTED and correctly shows these baskets were      |
//| deep in profit. This is DIAGNOSTIC-ONLY -- order placement, SL/TP,       |
//| magic-number routing, and the real MT5 account ledger (hence every       |
//| NET/PF/RF/Sharpe number already reported, and the MaxConcurrentBaskets=7 |
//| decision) are all UNAFFECTED, since those come from MT5's own deal       |
//| history totals directly, not from this per-basket log line. Any past or |
//| future "profit broken down by concurrency level" analysis built from    |
//| basketProfit in the LOG.csv is UNRELIABLE and should be disregarded --   |
//| only the official MT5 report/optimizer totals are trustworthy for that.  |
//| Not fixed (diagnostic-only, no live-trading impact); root cause not      |
//| fully isolated -- suspect HistorySelect's single global deal-cursor      |
//| being re-queried per-slot within the same tick while multiple slots'     |
//| magics are in that cursor's window; a safe fix would track each slot's   |
//| own position ticket IDs at open time and sum only those specific         |
//| tickets' deals at close, instead of a magic+time-window scan.            |
//|                                                                     |
//| THIRTY-FIRST BACKTEST (2026-11-24, UseSkipHourKST off vs on, on the      |
//| confirmed MaxConcurrentBaskets=7+TIGHTSWING combo): OFF beat ON on       |
//| every metric -- NET $70,949.54->$83,537.62, PF 1.398->1.409, RF          |
//| 3.055->3.720, Sharpe 2.746->2.807, Balance DD 9.34%->8.72%, Equity DD    |
//| 13.34%->12.01%, baskets ~1405->1609. Per-basket reconstruction of the    |
//| OFF run (bypassing the basketProfit bug above, matching real deals       |
//| directly) confirmed WHY: baskets opened in the 02:00-08:00 KST window    |
//| are NOT disproportionately risky -- 319 of 1,609 baskets (19.8%)         |
//| contributed $14,329.89 (19.6% of realized profit), avg $44.92/basket    |
//| vs $45.64/basket elsewhere -- essentially proportional. The ban was      |
//| pure opportunity cost under this architecture, not real risk reduction.  |
//|                                                                     |
//| THIRTY-FIRST REVISION (2026-11-24, per user confirmation): UseSkipHourKST|
//| default true->false. This is now the confirmed default.                 |
//|                                                                     |
//| THIRTY-SECOND REVISION (2026-11-24, per user report while live-running   |
//| the confirmed combo: a SELL basket had no TP because the lowest low of   |
//| the last SwingLookbackBars(20) bars sat AT/ABOVE P0 -- no favorable swing|
//| target existed at all, not just "too close"): added UseSwingTPFallbackRR |
//| (default true) -- when UseSwingTP's target is rejected for ANY reason    |
//| (too close/behind, or no valid extreme), TP now falls back to the        |
//| UseFixedRRTp formula (SLMult*step*FixedRRRatio) instead of staying       |
//| unset. Previously such baskets ran with SL+UseRegimeFlipExit only, by    |
//| design -- user asked for every basket to get a real TP range. Not yet    |
//| backtested.                                                             |
//|                                                                     |
//| LIVE INCIDENT (2026-11-24, first live run, confirmed by user via MT5     |
//| terminal screenshot): a P0 position (ticket 1246314026, slot 0) was      |
//| found with BOTH SL and TP completely blank, while its basket's G1 leg    |
//| had the correct shared SL/TP and later closed normally via that SL.      |
//| The EA's own log showed NO GRID_SL_SET_FAIL for this basket -- PlaceGrid |
//| believed its PositionModify on P0 succeeded. Suspected root cause: a     |
//| position-list sync race right after the first-entry fill in LIVE        |
//| trading (never observed in Strategy Tester, which is synchronous) --    |
//| PositionsTotal() may not yet have included the brand-new position at    |
//| the moment PlaceGrid's modify-loop ran, so the loop silently iterated   |
//| zero times (no attempt made, hence no failure logged either).           |
//|                                                                     |
//| THIRTY-THIRD REVISION (2026-11-24, per user request, "한 바스켓 안의      |
//| 거래들은 한 개의 TP/SL로 끝나야 된다"): added an SL/TP resync safety net   |
//| at the top of UpdateBasketExits(), running every tick whenever          |
//| EnableLiveOrders -- re-reads every open position under the slot's magic |
//| and re-applies g_sl[slot]/g_tp[slot] via PositionModify if either one   |
//| doesn't match (logged as SL_TP_RESYNC / SL_TP_RESYNC_FAIL on failure).  |
//| Self-heals within one tick regardless of root cause (the race above,    |
//| or anything else that might desync a position's SL/TP later). Not yet   |
//| live- or backtested in this form.                                      |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;
#define MAX_BASKET_SLOTS 10 // RAISED 2026-11-23 from 5, per user request, after the 1-5 sweep showed NET/PF/RF/Sharpe still rising with no peak at the old cap

input group "=== Signal: 20/120 cross + first 120MA pullback touch (REVISED 2026-11-21, TEST/untested) ==="
input ENUM_TIMEFRAMES Timeframe  = PERIOD_M3; // signal timeframe (manual tool was fixed M3) (TEST, untested)
input int    MAFastPeriod         = 20;   // fast SMA, used ONLY to detect golden/dead cross against MAPeriod -- NEW, not in manual tool (TEST, untested)
input int    MAPeriod            = 120;  // long-term SMA period -- cross-detection slow leg AND the pullback-touch entry level (TEST, untested, ported from manual tool default)
input int    MaxWaitBars         = 0;    // give up on a cross episode (no entry) after N new signal-TF bars with no 120MA touch, 0 = wait indefinitely for THIS cross (a new opposite cross still overrides it immediately regardless of this setting) (TEST, untested)

input group "=== Session-gated entry (NEW 2026-11-23, per user request: 하루 세션당 1번 -- '3분 장기이평매매는 보통 하루 3번'이라는 통념과 지금 모델의 '크로스당 첫 터치만' 빈도 격차를 좁혀보는 실험) ==="
input bool   UseSessionGatedEntry   = false; // instead of the default 'first touch after a cross, then consume until the next opposite cross' gating, allow at most ONE entry per KST-defined session (Asia/Europe/US) block -- g_awaitDir is NOT zeroed after firing (stays armed for the next session's touch, using whatever direction is current) unless a new cross overwrites it; still capped at one basket open at a time by the existing state machine (TEST, untested, user-specified logic)
input int    AsiaSessionStartKST    = 9;    // Asia session start, KST hour (~Tokyo/Sydney open, 00:00 UTC) -- also marks the US session's end (TEST, untested)
input int    EuropeSessionStartKST  = 17;   // Europe session start, KST hour (~London open, 08:00 UTC) -- also marks the Asia session's end (TEST, untested)
input int    USSessionStartKST      = 22;   // US session start, KST hour (~New York open, 13:00 UTC) -- also marks the Europe session's end; the US session wraps past midnight to AsiaSessionStartKST (TEST, untested)
input bool   UseEveryTouchEntry     = false; // NEW 2026-11-23, per user request: re-test the ORIGINAL first backtest's "every touch" gating (g_awaitDir never zeroed, no session cap either) but WITH all the filters added since (H1/BB4/H4/avoid-zones/last-leg-confirm) -- the original "every touch" test (PF~1.01, no edge) had NONE of those filters yet, so this checks whether they alone can keep it profitable at much higher frequency. SUPERSEDES UseSessionGatedEntry entirely when true (no session cap applied, only the existing one-basket-at-a-time ceiling) (TEST, untested, user-specified logic)
input int    MaxConcurrentBaskets   = 7;    // NEW 2026-11-23, per user request: number of baskets allowed open AT THE SAME TIME (1 = original behavior, no concurrency). Each slot trades under its own magic number (MagicNumber+slot) so positions stay cleanly separated. Clamped to [1,10] at OnInit (CONFIRMED 2026-11-24: 6-10 sweep via MT5 Optimizer on the TIGHTSWING combo found RF/Sharpe peak at 7, NET/PF peak at 8, 9-10 worse on every metric -- user chose 7 for best risk-adjusted return, see header)

input group "=== Grid step sizing (manual tool had a user-typed box; this automates it, TEST/untested) ==="
input bool   UseATRStep          = false; // true: step=ATR(StepATRPeriod)*StepATRMult (price units); false: fixed GridStepPoints (CONFIRMED 2026-11-24: false, as part of the TIGHTSWING combo baked into defaults -- see THIRTIETH REVISION in header)
input int    StepATRPeriod       = 14;    // unused while UseATRStep=false (TEST, untested)
input double StepATRMult         = 0.2;   // unused while UseATRStep=false (TEST, untested)
input double GridStepPoints      = 500;   // used only when UseATRStep=false; multiplied by _Point (=$0.01 on this symbol), so 500 = $5 -- trader convention is 1 "포인트"=$1 for gold, NOT MQL5's native _Point (CONFIRMED 2026-11-24 at 500/$5, the TIGHTSWING value, over the old 1000/$10 -- see THIRTIETH REVISION in header)

input group "=== Grid/basket structure (REVISED 2026-11-21: GridCount/SLMult CONFIRMED by user after a 5/3/2/1 sweep -- see dated backtest note) ==="
input double Lots                = 0.1;   // lot size, SAME for every leg (first entry + all grid legs) -- max basket exposure = Lots*(1+GridCount) (TEST, untested)
input int    GridCount            = 2;    // additional DCA legs beyond the first entry (CONFIRMED: best of 5/3/2/1 sweep -- RF 0.79->1.31->2.03 peaked at 2, then RF 1.43/NET roughly halved at 1, so 2 is the local optimum, not just "smaller is better")
input double SLMult               = 2.5;  // shared basket SL = P0 -/+ SLMult*step, ALL legs share this one SL (CONFIRMED alongside GridCount=2, same "+0.5 buffer" convention as the manual tool's original 5/5.5)

input group "=== Take-profit: nearby swing high/low (REVISED 2026-11-21: was cross-regime extreme, hit only 3.8% of baskets -- now a rolling lookback at entry time) ==="
input bool   UseSwingTP           = true;  // BUY target = highest high over SwingLookbackBars bars at entry ("전고점 역전"); SELL target = lowest low over SwingLookbackBars bars at entry ("전저점 역전") (TEST, untested)
input int    SwingLookbackBars    = 20;    // lookback window (signal-TF bars, ending at the bar before entry) for the swing extreme (REVERSED 2026-11-24: the old "50 stays" confirmation below was measured under the single-basket architecture; under concurrent baskets (MaxConcurrentBaskets=7) the faster-resolving 20-bar target wins decisively -- see THIRTIETH REVISION in header. Old note for reference: CONFIRMED-THEN over 20 under single-basket: NET $30,220->$25,870, RF 2.03->1.49, DD worse at 20)
input double MinSwingTPStep       = 1.0;   // minimum favorable distance from P0 to the swing target, in steps -- if the swing level doesn't clear this (target too close/behind), the hard TP falls back to UseSwingTPFallbackRR below instead of going unset (REVISED 2026-11-24, see that input's comment)
input bool   UseSwingTPFallbackRR = true;  // NEW 2026-11-24, per user request: when UseSwingTP is on but the swing target is rejected (too close/behind P0, or no valid swing extreme at all -- e.g. a SELL entry where the lowest low of the last SwingLookbackBars bars sits AT or ABOVE P0, so there's no favorable low to target), set TP = P0 +/- SLMult*step*FixedRRRatio (the SAME formula as UseFixedRRTp) instead of leaving this basket with no hard TP at all. Logged as SWING_TP_FALLBACK_RR. Has no effect when UseFixedRRTp=true (that path never calls the swing branch) (TEST, untested, user-specified logic)
input bool   UseFixedRRTp         = false; // NEW 2026-11-23, per user request: TP = P0 +/- SLMult*step*FixedRRRatio -- a hard multiple of the SAME SL distance, so risk:reward stays constant regardless of market conditions (unlike the bar-count-based swing target above, which doesn't reliably scale the actual price distance). SUPERSEDES UseSwingTP entirely when true; CounterTrendTPShrink does NOT apply to this path (TEST, untested, user-specified logic)
input double FixedRRRatio         = 2.0;   // TP distance = SL distance * this ratio (e.g. SL=$12.5: 2.0->TP=$25, 1.5->TP=$18.75) -- ALSO used by UseSwingTPFallbackRR above (TEST, untested)

input group "=== Profit trail: lock in gains after N steps favorable (NEW 2026-11-21, per user request -- UseSwingTP/UseRegimeFlipExit are UNCHANGED and can still fire; this is an ADDITIONAL protective layer so a big unrealized gain can't fully round-trip before either of those would otherwise catch it) ==="
input bool   UseProfitTrail            = false; // once a basket's favorable move (avg entry to current price, in steps) reaches ProfitTrailActivateSteps, arm a trailing stop that follows the best favorable price by ProfitTrailDistanceSteps, FLOORED at breakeven (avg entry) so it can never lock in a loss once armed (REJECTED 2026-11-21: NET $26,890.70->$4,956.80, RF 2.636->0.386, max win $3,334->$1,059 -- cut the FLIP mechanism's big wins short just like the removed UseBreakevenExit; default now OFF, see dated backtest note)
input double ProfitTrailActivateSteps  = 5.0; // favorable steps required to arm the trail (5.0 steps * step=$10 = $50, i.e. 2x the current $25 SL, per user's own framing "손절 2배인 50포인트") (TEST, untested)
input double ProfitTrailDistanceSteps  = 1.0; // once armed, the trail follows the best favorable price by this many steps (1.0 step * step=$10 = $10, per user's own framing "일정 거리(예: 10포인트)") (TEST, untested)

input group "=== Regime-flip breakeven exit (RENAMED 2026-11-21: UseBreakevenExit REMOVED -- it ran unconditionally and cut aligned-trend winners short, see dated backtest note. '본절' ONLY applies per checklist '04 정배/역배 대응', confirmed by user: while regime stays ALIGNED with the basket, wait on UseSwingTP only; ONLY when the regime flips AGAINST it, close at breakeven+margin ASAP) ==="
input bool   UseRegimeFlipExit        = true; // if the regime flips AGAINST an open basket's direction, close immediately once avg price reaches breakeven+RegimeFlipMinProfitSteps; while still aligned, UseSwingTP/hard SL are the ONLY exits (TEST, untested)
input double RegimeFlipMinProfitSteps = 0;    // 0 = breakeven ("본절"); positive = require a small profit margin first ("약수익") (TEST, untested)
input ENUM_TIMEFRAMES RegimeFlipTimeframe = PERIOD_M15; // REVISED 2026-11-21: timeframe for the regime-flip check, DECOUPLED from the M3 entry cross. M3's own 20/120 cross flipped against 79% of baskets before they ever reached SL/TP (too noisy); the user also flagged H1 as too slow relative to typical basket lifetimes (1-5 hours) -- M15 is a first-guess middle ground, untested (TEST, untested)

input group "=== Late-grid direction re-confirm (NEW 2026-11-21, per user request, motivated by a basket-depth breakdown showing ALL SL losses -- 84.5% of full-depth baskets, $0 losses below full depth -- occur only once every grid leg has filled; '구간매매' traders reportedly re-check direction mid-ladder and bail at breakeven if it looks wrong) ==="
input bool   UseLastLegConfirm        = true; // right before the LAST grid leg (GridCount-th) is allowed to fill, re-check that M3's own 20/120 cross, H1's price-vs-20MA, and H4's fast/slow MA cross (ANY one disagreeing counts) still agree with the basket direction g_dir -- if not, cancel that leg's pending order so the basket caps at GridCount-1 legs instead of reaching the full-depth cohort where all SL losses occur (CONFIRMED 2026-11-21: isolated A/B showed this alone beats every other combination on Equity DD, see dated backtest note)
input bool   UseFullDepthBadSignalExit = false; // once the basket reaches FULL depth (every grid leg filled) AND the SAME M3/H1/H4 bad-signal check fires, arm the SAME breakeven-or-better close as UseRegimeFlipExit (reuses g_regimeFlippedAgainstBasket + RegimeFlipMinProfitSteps) -- an ADDITIONAL, faster-reacting trigger source alongside RegimeFlipTimeframe's own cross, not a replacement for it (REJECTED 2026-11-21: isolated A/B showed this ALONE is worse than the no-filter baseline on every metric except Equity DD; default now OFF, see dated backtest note)

input group "=== H1 price-vs-MA direction override (REVISED 2026-11-21, REPLACES the 7th revision's H1 skip-gate per user's own strategy description) ==="
input bool   UseHigherTFAlignment   = true;      // at the moment of entry, HigherTFAlignment's CURRENT price vs its own MAFastPeriod(20) MA DETERMINES the final trade direction -- overrides the M3 cross's direction when they disagree, rather than skipping (TEST, untested, user-specified logic)
input ENUM_TIMEFRAMES HigherTFAlignment = PERIOD_H1; // the timeframe read for this override (TEST, CONFIRMED as a cross-alignment skip-gate in the 7th backtest at NET $18,986/PF 1.089; now repurposed, not yet backtested in this new form)
input double CounterTrendTPShrink   = 0.5;       // when the override disagrees with the M3 cross direction (counter-trend trade), shrink the swing-TP favorable distance from P0 by this fraction ("기존보다 다소 적은 범위로 익절") (TEST, untested, user-specified logic)

input group "=== H1 BB4(4,4) exhaustion override (NEW 2026-11-21, per user request -- TAKES PRIORITY over the price-vs-20MA override above when it fires; theory confirmed by user: '기본비를 맞으면 보통 반대방향으로 간다' -- touching the band is itself a fade signal) ==="
input bool   UseHtfBB4Exhaustion = true; // at a golden cross, if HigherTFAlignment's last CLOSED candle is bullish AND its high touches the upper BB4(4,4,PRICE_OPEN) band ("상단 기본비"), override to SELL; at a dead cross, a bearish candle touching the lower band overrides to BUY. Same "기본비" construct as 010-013 in this repo. Counts as counter-trend (CounterTrendTPShrink applies) whenever it disagrees with the M3 cross direction (TEST, untested, user-specified logic)

input group "=== Second higher-timeframe alignment filter (NEW 2026-11-21, per user request -- UNCHANGED skip-gate semantics, now checked against the FINAL direction after the H1 override above) ==="
input bool   UseHigherTFAlignment2  = true;      // a SECOND higher timeframe that must ALSO be aligned with the FINAL (post-H1-override) direction, else this touch is skipped (TEST, untested)
input ENUM_TIMEFRAMES HigherTFAlignment2 = PERIOD_H4; // first guess for the second required timeframe (TEST, untested)

input group "=== H1/H4 disagreement reversal (NEW 2026-11-23, per user request: '1시간봉하고 4시간봉하고 일치하지 않을때 반대방향으로 진입하면') ==="
input bool   UseH1H4DisagreeReversal = false; // if HigherTFAlignment's price-vs-20MA direction (H1) and HigherTFAlignment2's own fast/slow MA cross direction (H4) disagree with EACH OTHER, INVERT the already-decided finalDir (from the BB4/H1-override/M3-cross chain above) instead of running the UseHigherTFAlignment2 skip-gate below -- when true, SUPERSEDES UseHigherTFAlignment2 entirely regardless of its own value (REJECTED 2026-11-23: NET $26,890.70->$7,328.21, RF 2.636->0.644 -- H1/H4 disagreement was a low-conviction situation the old skip-gate correctly avoided; betting against both made it worse, not better. Default stays false, see dated backtest note)

input group "=== Avoid zone #1: H1 기본비+장기이평 겹침 '상위저항' (NEW 2026-11-21, per checklist '피해야 할 구간 4가지': '상위 시간봉에서 기본비(박스)와 장기이평이 겹치는 자리. 뚫리면 한 방향으로 미친듯이 간다. 건드리면 손절 확정') ==="
input bool   UseAvoidBB4MAOverlap    = true; // skip ANY entry (regardless of direction) if HigherTFAlignment's BB4(4,4) upper OR lower band sits within AvoidBB4MAOverlapPts of HigherTFAlignment's own 120-period MA -- a "loaded" confluence level (TEST, untested, user-specified logic)
input double AvoidBB4MAOverlapPts   = 200;   // overlap tolerance, trader-points ($1 each, same GridStepPoints convention -- 200=$2) -- first guess (TEST, untested)

input group "=== Avoid zone #2: H1 전고/전저 가짜돌파 (NEW 2026-11-21, per checklist '피해야 할 구간 4가지': '상위 전저·전고를 트라이하고 실패한 뒤 꼬리 달고 내려온 자리. 세력의 함정일 확률 높음. 재진입 금지') ==="
input bool   UseAvoidFakeBreakout       = false; // skip entry if HigherTFAlignment's last CLOSED candle tried and failed to break the recent swing high/low in the SAME direction as this entry's finalDir (REJECTED 2026-11-21: isolated 3-way sweep showed this zone alone, and combined with zone #1, drags RF/Equity DD below zone-#1-only; default now OFF, see 13th-revision note below)
input int    FakeBreakoutLookbackBars   = 20;    // bars (on HigherTFAlignment, shift 2..N+1, excluding the candle being tested) used to find the prior swing high/low -- first guess (TEST, untested)

input group "=== Avoid zone #4: 5대 경제지표 발표 전후 30분 (NEW 2026-11-21, per checklist '피해야 할 구간 4가지': 고영향 경제지표 발표 전후는 변동성 급증 구간, 신규 진입 금지. 이전엔 OUT-OF-SCOPE로 남겨뒀으나 사용자 요청으로 구현) ==="
input bool   UseAvoidEconCalendar            = true; // skip NEW entries within [AvoidEconCalendarMinutesBefore,AvoidEconCalendarMinutesAfter] minutes of a >=AvoidEconCalendarMinImportance AvoidEconCalendarCurrency calendar event (MQL5 CalendarValueHistory()/CalendarEventById() -- see CALENDAR_DIAG log line at startup for whether Strategy Tester actually has calendar data for this test) (TEST, untested, user-specified logic)
input int    AvoidEconCalendarMinutesBefore  = 30;    // minutes BEFORE a qualifying event's release time to start blocking new entries (TEST, untested)
input int    AvoidEconCalendarMinutesAfter   = 30;    // minutes AFTER a qualifying event's release time to keep blocking new entries (TEST, untested)
input string AvoidEconCalendarCurrency       = "USD"; // only count calendar events for this currency -- gold's primary macro driver, used as a proxy for "5대 경제지표" since MT5's calendar isn't easily filtered to 5 specific named indicators (TEST, untested)
input ENUM_CALENDAR_EVENT_IMPORTANCE AvoidEconCalendarMinImportance = CALENDAR_IMPORTANCE_HIGH; // minimum calendar importance to count as a qualifying event (TEST, untested)

input group "=== Time filter (NEW 2026-11-21, per checklist '새벽 2시 이후 신규 금지'; window CONFIRMED by user as KST 02:00-08:00) ==="
input bool   UseSkipHourKST       = false; // block NEW entries in [SkipHourStartKST,SkipHourEndKST) KST; does not affect baskets already open (REVERSED 2026-11-24: on the MaxConcurrentBaskets=7+TIGHTSWING combo, turning this OFF raised NET $70,950->$83,538, RF 3.055->3.720, Sharpe 2.746->2.807, and LOWERED both DD%s -- per-basket reconstruction showed the 02-08 KST window contributes proportionally (19.8% of baskets, 19.6% of profit, avg profit/basket $44.92 vs $45.64 elsewhere), so the ban was pure opportunity cost with no real risk-avoidance benefit under this architecture. CONFIRMED false.)
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

// NEW 2026-11-23: the whole per-basket state block below is now an array of
// MAX_BASKET_SLOTS independent slots (see MaxConcurrentBaskets) instead of a
// single scalar basket -- slot[s] trades under magic SlotMagic(s). With
// MaxConcurrentBaskets=1 only slot 0 is ever used, reproducing the original
// single-basket behavior exactly.
int      g_maxSlots=1;                    // clamped copy of MaxConcurrentBaskets, set in OnInit
ENUM_GSTATE g_state[MAX_BASKET_SLOTS];
int      g_dir[MAX_BASKET_SLOTS];          // +1 long basket, -1 short basket
double   g_p0[MAX_BASKET_SLOTS];           // first-leg fill price
double   g_step[MAX_BASKET_SLOTS];         // step used for this basket (fixed once placed)
double   g_sl[MAX_BASKET_SLOTS];           // current shared SL for the whole basket
double   g_tp[MAX_BASKET_SLOTS];           // hard TP for the whole basket, 0 = none
datetime g_basketOpenTime[MAX_BASKET_SLOTS];
bool     g_regimeFlippedAgainstBasket[MAX_BASKET_SLOTS]; // set true when the RegimeFlipTimeframe regime flips while this slot is open and no longer matches g_dir[slot]
bool     g_lastLegChecked[MAX_BASKET_SLOTS];    // NEW 2026-11-21: consumed once per basket by the UseLastLegConfirm re-check right before the LAST grid leg is allowed to fill
bool     g_profitTrailArmed[MAX_BASKET_SLOTS];       // NEW 2026-11-21: true once favSteps has ever reached ProfitTrailActivateSteps for the current basket
double   g_profitTrailBestPrice[MAX_BASKET_SLOTS];   // NEW 2026-11-21: best (most favorable) price seen since the trail armed
double   g_peakFavSteps[MAX_BASKET_SLOTS];     // NEW 2026-11-22: diagnostic-only -- running max of favSteps over the basket's whole life, logged at BASKET_CLOSED

ulong SlotMagic(int slot){ return MagicNumber+(ulong)slot; } // NEW 2026-11-23

// Cross-episode state (REVISED 2026-11-21): g_awaitDir!=0 means a golden/dead
// cross has fired and we're waiting for the FIRST 120MA touch to trade it.
// SHARED across all slots -- there is only one M3 cross signal.
int      g_awaitDir=0;         // 0=no pending cross episode; +1=golden cross (wait to BUY); -1=dead cross (wait to SELL)
int      g_awaitBarsElapsed=0;
datetime g_lastBarSeen=0;      // shared new-bar detector for cross-check + wait-timeout counting

// Regime (fast-vs-slow MA) tracking on the ENTRY timeframe (M3), used ONLY
// for cross detection (ARM) -- NOT for the regime-flip exit, see below.
bool     g_regimeKnown=false;
bool     g_regimeBullish=false;

// Regime tracking on RegimeFlipTimeframe (REVISED 2026-11-21, decoupled from
// the entry cross -- M3's own cross flipped against 79% of baskets before
// they reached SL/TP). Used ONLY to detect a regime flip AGAINST open
// basket(s) (REGIME-FLIP exit, see UpdateFlipRegime/UpdateBasketExits).
bool     g_flipRegimeKnown=false;
bool     g_flipRegimeBullish=false;
datetime g_lastFlipBarSeen=0;
int      g_lastSessionIdx=-1;         // NEW 2026-11-23: which session (0=Asia,1=Europe,2=US, see SessionIndex()) as of the last tick
bool     g_sessionEntryUsed=false;    // NEW 2026-11-23: consumed once an entry fires in the current session block (UseSessionGatedEntry) -- shared across slots, "one per session" means across ALL slots collectively

int hMA=INVALID_HANDLE, hMAFast=INVALID_HANDLE, hATR=INVALID_HANDLE;
int hMAFlipSlow=INVALID_HANDLE, hMAFlipFast=INVALID_HANDLE;
int hMAHtfFast=INVALID_HANDLE; // H1 price-vs-MA direction override (REVISED 2026-11-21) -- only the fast(20) MA is needed now, no cross
int hMAHtfSlow=INVALID_HANDLE; // RE-ADDED 2026-11-21 for Avoid zone #1 (H1 120MA vs BB4 overlap) -- no longer used for a cross
int hBB4Htf=INVALID_HANDLE;    // H1 BB4(4,4) exhaustion override (NEW 2026-11-21) -- same "기본비" construct as 010-013
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

// BUGFIX (2026-11-26, found from a live case): a log file that was open and
// writing fine could silently stop (confirmed live: the file's last line was
// a normal START at 20:08:56, then NOTHING for hours afterward despite the
// Experts tab clearly showing the EA still running and logging events to
// Print() the whole time) -- neither FileWrite()'s nor FileFlush()'s return
// value was ever checked, so a write failure (file locked by another
// program, marked read-only, a sync conflict, disk full, ...) was silently
// swallowed and never surfaced anywhere. Now checks both return values: on
// failure, closes the stale handle, prints the error code, and shows a
// persistent on-chart Comment() so this is visible immediately instead of
// discovered hours later -- and retries reopening the file on every
// subsequent Log() call (here, and also if f_log was never opened
// successfully at all) rather than giving up for the rest of the session.
void Log(string event,string detail="")
{
   Print("XAU_M3_MATOUCHGRID_test | ",event," | ",detail);

   if(f_log==INVALID_HANDLE)
   {
      f_log=FileOpen("XAU_M3_MATOUCHGRID_test_LOG.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
      if(f_log!=INVALID_HANDLE)
      {
         FileSeek(f_log,0,SEEK_END);
         Print("XAU_M3_MATOUCHGRID_test | LOG_FILE_REOPENED | writing resumed");
         Comment("");
      }
   }

   if(f_log!=INVALID_HANDLE)
   {
      ResetLastError();
      FileWrite(f_log,TS(TimeCurrent()),event,detail); // both FileWrite() and FileFlush() return void in MQL5 -- GetLastError() is the only way to detect failure
      FileFlush(f_log);
      int err=GetLastError();
      if(err!=0)
      {
         Print("XAU_M3_MATOUCHGRID_test | LOG_WRITE_FAIL | err=",err," -- log file write/flush failed, closing handle and will retry next event");
         FileClose(f_log);
         f_log=INVALID_HANDLE;
         Comment("XAU_M3_MATOUCHGRID_test: LOG FILE WRITE FAILED (err="+IntegerToString(err)+") -- check if XAU_M3_MATOUCHGRID_test_LOG.csv is open in another program (e.g. Excel) or set read-only. Trading continues; only file logging is affected. Will keep retrying.");
      }
   }
   else
   {
      Comment("XAU_M3_MATOUCHGRID_test: LOG FILE NOT OPEN -- check if XAU_M3_MATOUCHGRID_test_LOG.csv is open in another program or set read-only. Trading continues; only file logging is affected. Will keep retrying.");
   }
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

   for(int slot=0;slot<g_maxSlots;slot++) // NEW 2026-11-23: check every open slot, not just one
   {
      if(g_state[slot]!=GS_BASKET || g_regimeFlippedAgainstBasket[slot]) continue;
      bool basketIsBullish=(g_dir[slot]>0);
      if(basketIsBullish!=bullish)
      {
         g_regimeFlippedAgainstBasket[slot]=true;
         Log("REGIME_FLIPPED_AGAINST_BASKET","slot="+IntegerToString(slot)+" ("+EnumToString(RegimeFlipTimeframe)+") basket dir="+(g_dir[slot]>0?"BUY":"SELL")+" -- will close at breakeven+"+DoubleToString(RegimeFlipMinProfitSteps,2)+" steps ASAP");
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
// REVISED 2026-11-26, per user request: was reading the last CLOSED H4 bar
// (shift=1), inconsistent with H1's DecideFinalDir() which reads the live,
// still-forming bar (shift=0) -- found when tracing a case where an armed
// cross episode sat blocked by this H4 check for 32 seconds of repeated
// touches, then fired hours later on an unrelated touch once H4 had long
// since moved on, because the stale closed-bar read kept disagreeing.
// Now reads the forming bar (shift=0), same convention as H1, so this
// check reacts to H4's current state rather than up to 4 hours of lag.
// Only ever called with H4's own MA handles (hMAHtf2Fast/hMAHtf2Slow) --
// not shared with any other timeframe check.
bool TFAligned(int dir,int hFast,int hSlow)
{
   double fast1[1],slow1[1];
   if(CopyBuffer(hFast,0,0,1,fast1)<1) return false;
   if(CopyBuffer(hSlow,0,0,1,slow1)<1) return false;
   bool bullish=fast1[0]>slow1[0];
   return (dir>0) ? bullish : !bullish;
}

//+------------------------------------------------------------------+
//| Raw cross direction (NEW 2026-11-23, for UseH1H4DisagreeReversal): |
//| +1 if fast>slow, -1 otherwise -- unlike TFAligned, this returns the|
//| ACTUAL direction rather than "does it match dir", so H1's and H4's |
//| own reads can be compared directly against each other.             |
//+------------------------------------------------------------------+
int CrossDir(int hFast,int hSlow,int fallback)
{
   double fast1[1],slow1[1];
   if(CopyBuffer(hFast,0,1,1,fast1)<1) return fallback;
   if(CopyBuffer(hSlow,0,1,1,slow1)<1) return fallback;
   return (fast1[0]>slow1[0]) ? +1 : -1;
}

//+------------------------------------------------------------------+
//| H1 price-vs-MA direction override (REVISED 2026-11-21, per user's   |
//| own strategy description): reads HigherTFAlignment's CURRENT price   |
//| vs its live MAFastPeriod(20) MA (hMAHtfFast, forming-bar value, same  |
//| convention as GetMA()) and returns +1/-1 accordingly -- this becomes  |
//| the basket's ACTUAL direction, which may differ from fallbackDir      |
//| (the M3 cross's own direction). Falls back to fallbackDir only if the |
//| MA value can't be read.                                               |
//+------------------------------------------------------------------+
int DecideFinalDir(int fallbackDir)
{
   double ma[1];
   if(CopyBuffer(hMAHtfFast,0,0,1,ma)<1) return fallbackDir;
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   return (bid>ma[0]) ? +1 : -1;
}

//+------------------------------------------------------------------+
//| H1 BB4(4,4) exhaustion override (NEW 2026-11-21, per user request:  |
//| "기본비를 맞으면 보통 반대방향으로 간다" -- touching the band is itself a |
//| fade signal, so it overrides even a just-fired golden/dead cross).  |
//| Reads HigherTFAlignment's last CLOSED candle only (not the forming  |
//| one, unlike DecideFinalDir -- need a settled candle to know its      |
//| direction and whether it touched the band). Sets fired=true and      |
//| returns the faded direction (+1/-1) only if crossDir's own extreme   |
//| band was touched by a candle moving WITH crossDir; otherwise fired=  |
//| false and the return value is meaningless (caller must check fired). |
//+------------------------------------------------------------------+
int DecideFinalDirByBB4(int crossDir,bool &fired)
{
   fired=false;
   double o=iOpen(_Symbol,HigherTFAlignment,1), c=iClose(_Symbol,HigherTFAlignment,1);
   double h=iHigh(_Symbol,HigherTFAlignment,1), l=iLow(_Symbol,HigherTFAlignment,1);
   if(o==0 || c==0) return 0;

   double up4[1],lo4[1];
   if(CopyBuffer(hBB4Htf,1,1,1,up4)<1) return 0;
   if(CopyBuffer(hBB4Htf,2,1,1,lo4)<1) return 0;

   if(crossDir>0 && c>o && h>=up4[0]) { fired=true; return -1; } // golden cross, bullish H1 candle touches upper band -> fade SELL
   if(crossDir<0 && c<o && l<=lo4[0]) { fired=true; return +1; } // dead cross, bearish H1 candle touches lower band -> fade BUY
   return 0;
}

//+------------------------------------------------------------------+
//| Late-grid re-confirm signal (NEW 2026-11-21, per user request):    |
//| true if ANY of M3's own 20/120 cross (g_regimeBullish), H1's       |
//| live price-vs-20MA (DecideFinalDir), or H4's fast/slow MA cross    |
//| (TFAligned) now disagrees with dir. Used both to gate the LAST     |
//| grid leg (UseLastLegConfirm) and to arm an early breakeven exit    |
//| once a basket is at full depth (UseFullDepthBadSignalExit). Does   |
//| NOT include the H1 BB4 exhaustion signal -- that is an entry-timing|
//| trick, not a sustained regime read.                                |
//+------------------------------------------------------------------+
bool BadSignalAgainstDir(int dir)
{
   if(g_regimeKnown && (g_regimeBullish!=(dir>0))) return true;
   if(DecideFinalDir(dir)!=dir) return true;
   if(!TFAligned(dir,hMAHtf2Fast,hMAHtf2Slow)) return true;
   return false;
}

//+------------------------------------------------------------------+
//| Avoid zone #1 (NEW 2026-11-21, per checklist '피해야 할 구간 4가지'    |
//| #1 "1시간 이상봉 기본비+장기이평"): true if HigherTFAlignment's BB4      |
//| upper OR lower band sits within AvoidBB4MAOverlapPts of its own       |
//| 120MA -- non-directional, applies to ANY entry regardless of dir.     |
//+------------------------------------------------------------------+
bool InAvoidZoneBB4MAOverlap()
{
   double up4[1],lo4[1],ma120[1];
   if(CopyBuffer(hBB4Htf,1,1,1,up4)<1) return false;
   if(CopyBuffer(hBB4Htf,2,1,1,lo4)<1) return false;
   if(CopyBuffer(hMAHtfSlow,0,1,1,ma120)<1) return false;
   double tol=AvoidBB4MAOverlapPts*_Point;
   return (MathAbs(up4[0]-ma120[0])<=tol) || (MathAbs(lo4[0]-ma120[0])<=tol);
}

//+------------------------------------------------------------------+
//| Avoid zone #2 (NEW 2026-11-21, per checklist '피해야 할 구간 4가지'    |
//| #2 "1시간 이상봉 전저·전고 매물 트라이 후 실패(가짜돌파)"): true if       |
//| HigherTFAlignment's last CLOSED candle tried and failed to break the  |
//| recent swing high/low (shift 2..FakeBreakoutLookbackBars+1, so the    |
//| tested candle itself is excluded) in the SAME direction as dir.       |
//+------------------------------------------------------------------+
bool InAvoidZoneFakeBreakout(int dir)
{
   int idxHigh=iHighest(_Symbol,HigherTFAlignment,MODE_HIGH,FakeBreakoutLookbackBars,2);
   int idxLow =iLowest (_Symbol,HigherTFAlignment,MODE_LOW, FakeBreakoutLookbackBars,2);
   if(idxHigh<0 || idxLow<0) return false;
   double priorHigh=iHigh(_Symbol,HigherTFAlignment,idxHigh);
   double priorLow =iLow (_Symbol,HigherTFAlignment,idxLow);

   double h1=iHigh(_Symbol,HigherTFAlignment,1), l1=iLow(_Symbol,HigherTFAlignment,1), c1=iClose(_Symbol,HigherTFAlignment,1);
   if(h1==0 || l1==0) return false;

   bool failedUp  =(h1>=priorHigh) && (c1<priorHigh); // tried to break the prior high, failed (closed back under)
   bool failedDown=(l1<=priorLow)  && (c1>priorLow);  // tried to break the prior low, failed (closed back over)

   if(dir>0 && failedUp)   return true; // about to chase a BUY right after a failed breakout UP
   if(dir<0 && failedDown) return true; // about to chase a SELL right after a failed breakdown
   return false;
}

//+------------------------------------------------------------------+
//| Avoid zone #4 (NEW 2026-11-21, per checklist '피해야 할 구간 4가지'    |
//| #4 "5대 경제지표 발표 전후"): true if an AvoidEconCalendarCurrency      |
//| calendar event at >=AvoidEconCalendarMinImportance has its release    |
//| time within [-AvoidEconCalendarMinutesBefore,+AvoidEconCalendarMinutes|
//| After] minutes of now. Non-directional, applies to ANY entry. Relies  |
//| on MT5's native calendar cache -- see CALENDAR_DIAG log at OnInit.    |
//+------------------------------------------------------------------+
bool InAvoidZoneEconCalendar()
{
   datetime now =TimeTradeServer();
   datetime from=now-AvoidEconCalendarMinutesBefore*60;
   datetime to  =now+AvoidEconCalendarMinutesAfter*60;
   MqlCalendarValue vals[];
   int n=CalendarValueHistory(vals,from,to,NULL,AvoidEconCalendarCurrency);
   for(int i=0;i<n;i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(vals[i].event_id,ev)) continue;
      if(ev.importance>=AvoidEconCalendarMinImportance) return true;
   }
   return false;
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

//+------------------------------------------------------------------+
//| Session index from a KST hour (NEW 2026-11-23, for                |
//| UseSessionGatedEntry): 0=Asia [AsiaSessionStartKST,EuropeSession-  |
//| StartKST), 1=Europe [EuropeSessionStartKST,USSessionStartKST),     |
//| 2=US -- everything else, i.e. [USSessionStartKST,24) U             |
//| [0,AsiaSessionStartKST), wrapping past midnight. Assumes the three |
//| inputs are given in increasing order (Asia < Europe < US).         |
//+------------------------------------------------------------------+
int SessionIndex(int kstHour)
{
   if(kstHour>=AsiaSessionStartKST && kstHour<EuropeSessionStartKST) return 0;
   if(kstHour>=EuropeSessionStartKST && kstHour<USSessionStartKST)  return 1;
   return 2;
}

bool IsMine(ulong magic,string sym,ulong expectedMagic){ return magic==expectedMagic && sym==_Symbol; } // NEW 2026-11-23: expectedMagic param (was hardcoded to MagicNumber) so each slot's own SlotMagic() can be checked

int CountPositions(int slot)
{
   ulong expectedMagic=SlotMagic(slot);
   int c=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0 || !PositionSelectByTicket(t)) continue;
      if(IsMine((ulong)PositionGetInteger(POSITION_MAGIC),PositionGetString(POSITION_SYMBOL),expectedMagic)) c++;
   }
   return c;
}

void DeletePendings(int slot)
{
   ulong expectedMagic=SlotMagic(slot);
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong t=OrderGetTicket(i);
      if(t==0 || !OrderSelect(t)) continue;
      if(!IsMine((ulong)OrderGetInteger(ORDER_MAGIC),OrderGetString(ORDER_SYMBOL),expectedMagic)) continue;
      if(!trade.OrderDelete(t))
         Log("PENDING_DELETE_FAIL",IntegerToString((int)trade.ResultRetcode())+" #"+IntegerToString((long)t));
   }
}

//+------------------------------------------------------------------+
//| Cancel just the LAST grid leg's pending order (NEW 2026-11-21, for |
//| UseLastLegConfirm) -- leaves any already-filled legs and any       |
//| earlier-numbered pending legs untouched.                           |
//+------------------------------------------------------------------+
void DeleteLastLegPending(int slot)
{
   ulong expectedMagic=SlotMagic(slot);
   string cmt=StringFormat("MTG_G%d",GridCount);
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong t=OrderGetTicket(i);
      if(t==0 || !OrderSelect(t)) continue;
      if(!IsMine((ulong)OrderGetInteger(ORDER_MAGIC),OrderGetString(ORDER_SYMBOL),expectedMagic)) continue;
      if(OrderGetString(ORDER_COMMENT)!=cmt) continue;
      if(!trade.OrderDelete(t))
         Log("LASTLEG_DELETE_FAIL",IntegerToString((int)trade.ResultRetcode())+" #"+IntegerToString((long)t));
   }
}

void CloseAllPositions(int slot)
{
   ulong expectedMagic=SlotMagic(slot);
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0 || !PositionSelectByTicket(t)) continue;
      if(!IsMine((ulong)PositionGetInteger(POSITION_MAGIC),PositionGetString(POSITION_SYMBOL),expectedMagic)) continue;
      if(!trade.PositionClose(t))
         Log("CLOSE_FAIL",IntegerToString((int)trade.ResultRetcode())+" #"+IntegerToString((long)t));
   }
}

//+------------------------------------------------------------------+
//| First entry (auto equivalent of manual tool's DoFirstEntry)        |
//+------------------------------------------------------------------+
bool DoFirstEntry(int slot)
{
   if(!EnableLiveOrders)
   {
      MqlTick q; if(!SymbolInfoTick(_Symbol,q)) return false;
      g_p0[slot]=(g_dir[slot]>0?q.ask:q.bid);
      Log("DRY_FIRST_ENTRY","slot="+IntegerToString(slot)+" "+(g_dir[slot]>0?"BUY":"SELL")+string(" @~")+DoubleToString(g_p0[slot],_Digits));
      return true;
   }

   trade.SetExpertMagicNumber(SlotMagic(slot)); // NEW 2026-11-23: route this slot's orders to its own magic
   double lot=NormLot(Lots);
   bool ok=(g_dir[slot]>0 ? trade.Buy(lot,_Symbol,0.0,0.0,0.0,"MTG_P0") : trade.Sell(lot,_Symbol,0.0,0.0,0.0,"MTG_P0"));
   if(!ok)
   {
      Log("FIRST_ENTRY_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
      return false;
   }

   g_p0[slot]=trade.ResultPrice();
   if(g_p0[slot]<=0)
   {
      ulong deal=trade.ResultDeal();
      if(deal>0 && HistoryDealSelect(deal)) g_p0[slot]=HistoryDealGetDouble(deal,DEAL_PRICE);
   }
   if(g_p0[slot]<=0) g_p0[slot]=(g_dir[slot]>0?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID));

   Log("FIRST_ENTRY_OK","slot="+IntegerToString(slot)+" "+(g_dir[slot]>0?"BUY":"SELL")+" @"+DoubleToString(g_p0[slot],_Digits));
   return true;
}

//+------------------------------------------------------------------+
//| Grid placement (auto equivalent of manual tool's PlaceGrid)        |
//+------------------------------------------------------------------+
void PlaceGrid(int slot,double step,double tpCandidate)
{
   g_step[slot]=step;
   g_sl[slot]=NP(g_p0[slot]-g_dir[slot]*SLMult*step);
   g_basketOpenTime[slot]=TimeCurrent();
   g_lastLegChecked[slot]=false; // NEW 2026-11-21: re-arm the UseLastLegConfirm check for this fresh basket
   g_profitTrailArmed[slot]=false; g_profitTrailBestPrice[slot]=0; // NEW 2026-11-21: re-arm the profit trail for this fresh basket
   g_peakFavSteps[slot]=-1000000; // NEW 2026-11-22: reset the diagnostic MFE tracker for this fresh basket

   //--- TP: either a fixed risk:reward multiple of the SL distance
   //    (UseFixedRRTp, NEW 2026-11-23) or the swing-extreme target validated
   //    to be favorable by at least MinSwingTPStep steps from P0 (if it
   //    doesn't clear this -- e.g. too close/behind -- fall back to no hard
   //    TP, hard SL / UseRegimeFlipExit only, for this basket).
   g_tp[slot]=0;
   if(UseFixedRRTp)
   {
      double fixedDist=SLMult*step*FixedRRRatio;
      double tpCand=g_p0[slot]+g_dir[slot]*fixedDist;
      double cushion=MinStopDistance()+_Point;
      MqlTick qtp; if(SymbolInfoTick(_Symbol,qtp))
      {
         if(g_dir[slot]>0){ if(tpCand<qtp.ask+cushion) tpCand=qtp.ask+cushion; }
         else             { if(tpCand>qtp.bid-cushion) tpCand=qtp.bid-cushion; }
      }
      g_tp[slot]=NP(tpCand);
   }
   else if(UseSwingTP)
   {
      double favDist=(tpCandidate>0) ? ((g_dir[slot]>0) ? (tpCandidate-g_p0[slot]) : (g_p0[slot]-tpCandidate)) : -1000000;
      bool swingValid=(tpCandidate>0 && favDist>=MinSwingTPStep*step);
      double cushion=MinStopDistance()+_Point;
      double tpCand;
      if(swingValid)
         tpCand=tpCandidate;
      else
      {
         Log("SWING_TP_REJECTED","slot="+IntegerToString(slot)+" target="+(tpCandidate>0?DoubleToString(tpCandidate,_Digits):"none")+" too close/behind (or no valid swing extreme) P0="+DoubleToString(g_p0[slot],_Digits)+" (favDist<"+DoubleToString(MinSwingTPStep,2)+" steps) -- "+(UseSwingTPFallbackRR?"falling back to fixed R:R TP":"no hard TP this basket"));
         if(!UseSwingTPFallbackRR) tpCand=0;
         else
         {
            tpCand=g_p0[slot]+g_dir[slot]*SLMult*step*FixedRRRatio;
            Log("SWING_TP_FALLBACK_RR","slot="+IntegerToString(slot)+" tp="+DoubleToString(tpCand,_Digits)+" ratio="+DoubleToString(FixedRRRatio,2));
         }
      }
      if(tpCand>0)
      {
         MqlTick qtp; if(SymbolInfoTick(_Symbol,qtp))
         {
            if(g_dir[slot]>0){ if(tpCand<qtp.ask+cushion) tpCand=qtp.ask+cushion; }
            else             { if(tpCand>qtp.bid-cushion) tpCand=qtp.bid-cushion; }
         }
         g_tp[slot]=NP(tpCand);
      }
   }

   if(!EnableLiveOrders)
   {
      Log("DRY_GRID","slot="+IntegerToString(slot)+" P0="+DoubleToString(g_p0[slot],_Digits)+" step="+DoubleToString(step,_Digits)+" SL="+DoubleToString(g_sl[slot],_Digits)+" TP="+DoubleToString(g_tp[slot],_Digits));
      g_state[slot]=GS_BASKET;
      return;
   }

   trade.SetExpertMagicNumber(SlotMagic(slot)); // NEW 2026-11-23
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID), ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   //--- already past the hard SL at the moment the grid would be placed -> close immediately (matches manual tool)
   if((g_dir[slot]>0 && bid<=g_sl[slot]) || (g_dir[slot]<0 && ask>=g_sl[slot]))
   {
      Log("GRID_ALREADY_PAST_SL","slot="+IntegerToString(slot)+" closing immediately, SL="+DoubleToString(g_sl[slot],_Digits));
      CloseAllPositions(slot);
      DeletePendings(slot);
      g_state[slot]=GS_IDLE;
      return;
   }

   //--- 1) set SL+TP on the first-entry position
   ulong expectedMagic=SlotMagic(slot);
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0 || !PositionSelectByTicket(t)) continue;
      if(!IsMine((ulong)PositionGetInteger(POSITION_MAGIC),PositionGetString(POSITION_SYMBOL),expectedMagic)) continue;
      if(!trade.PositionModify(t,g_sl[slot],g_tp[slot]))
         Log("GRID_SL_SET_FAIL",IntegerToString((int)trade.ResultRetcode()));
   }

   //--- 2) grid legs 1..GridCount, in the ADVERSE direction from P0
   double lot=NormLot(Lots);
   double minDist=MinStopDistance();
   for(int k=1;k<=GridCount;k++)
   {
      double level=NP(g_p0[slot]-g_dir[slot]*k*step);
      string cmt=StringFormat("MTG_G%d",k);
      bool ok;
      bool passed=(g_dir[slot]>0)?(ask<=level+minDist):(bid>=level-minDist);
      if(passed)
      {
         ok=(g_dir[slot]>0 ? trade.Buy(lot,_Symbol,0.0,g_sl[slot],g_tp[slot],cmt) : trade.Sell(lot,_Symbol,0.0,g_sl[slot],g_tp[slot],cmt));
         Log("GRID_LEG_MARKET","slot="+IntegerToString(slot)+" "+IntegerToString(k)+" level="+DoubleToString(level,_Digits)+" "+(ok?"FILLED":"FAILED"));
      }
      else
      {
         ok=(g_dir[slot]>0 ? trade.BuyLimit (lot,level,_Symbol,g_sl[slot],g_tp[slot],ORDER_TIME_GTC,0,cmt)
                           : trade.SellLimit(lot,level,_Symbol,g_sl[slot],g_tp[slot],ORDER_TIME_GTC,0,cmt));
         Log("GRID_LEG_PENDING","slot="+IntegerToString(slot)+" "+IntegerToString(k)+" level="+DoubleToString(level,_Digits)+" "+(ok?"PLACED":"FAILED"));
      }
      if(!ok) Log("GRID_LEG_RETCODE",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
      bid=SymbolInfoDouble(_Symbol,SYMBOL_BID); ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   }

   g_state[slot]=GS_BASKET;
   Log("GRID_COMPLETE","slot="+IntegerToString(slot)+" P0="+DoubleToString(g_p0[slot],_Digits)+" step="+DoubleToString(step,_Digits)+" SL="+DoubleToString(g_sl[slot],_Digits)+" TP="+DoubleToString(g_tp[slot],_Digits));
}

//+------------------------------------------------------------------+
//| Basket exits (NEW -- not in the manual tool): the ONLY exit handled  |
//| here is the regime-flip breakeven close (see comment inside).        |
//+------------------------------------------------------------------+
void UpdateBasketExits(int slot)
{
   //--- SL/TP resync safety net (NEW 2026-11-24, per live bug report: a P0
   //    position was left with NO SL/NO TP at all even though PlaceGrid's
   //    PositionModify call logged no failure -- suspected position-list
   //    sync race right after the first-entry fill, where PositionsTotal()
   //    didn't yet include the brand-new position at modify time, so the
   //    loop silently found nothing to modify. Rather than chase the exact
   //    race, this just re-asserts the invariant every tick: every open
   //    position under this slot's magic MUST carry SL=g_sl[slot] (and
   //    TP=g_tp[slot] when nonzero) -- fixes it within one tick regardless
   //    of root cause, self-healing even if something else clears it later.
   if(EnableLiveOrders && g_sl[slot]>0)
   {
      ulong expectedMagicRS=SlotMagic(slot);
      for(int ri=PositionsTotal()-1;ri>=0;ri--)
      {
         ulong rt=PositionGetTicket(ri);
         if(rt==0 || !PositionSelectByTicket(rt)) continue;
         if(!IsMine((ulong)PositionGetInteger(POSITION_MAGIC),PositionGetString(POSITION_SYMBOL),expectedMagicRS)) continue;
         double curSL=PositionGetDouble(POSITION_SL);
         double curTP=PositionGetDouble(POSITION_TP);
         bool slWrong=(MathAbs(curSL-g_sl[slot])>_Point);
         bool tpWrong=(g_tp[slot]>0 && MathAbs(curTP-g_tp[slot])>_Point);
         if(slWrong || tpWrong)
         {
            Log("SL_TP_RESYNC","slot="+IntegerToString(slot)+" ticket="+IntegerToString((long)rt)+" had SL="+DoubleToString(curSL,_Digits)+" TP="+DoubleToString(curTP,_Digits)+" -- reapplying SL="+DoubleToString(g_sl[slot],_Digits)+" TP="+DoubleToString(g_tp[slot],_Digits));
            if(!trade.PositionModify(rt,g_sl[slot],g_tp[slot]))
               Log("SL_TP_RESYNC_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription()+" #"+IntegerToString((long)rt));
         }
      }
   }

   //--- Late-grid re-confirm (NEW 2026-11-21, per user request): right before
   //    the LAST grid leg would fill (P0 + GridCount-1 legs already filled,
   //    one pending leg left), re-check M3/H1/H4 still agree with g_dir.
   //    Basket-depth breakdown showed ALL SL losses (84.5% of full-depth
   //    baskets, $0 below full depth) happen only once every leg has filled --
   //    this targets exactly that transition.
   if(UseLastLegConfirm && !g_lastLegChecked[slot] && GridCount>=1 && CountPositions(slot)==GridCount)
   {
      g_lastLegChecked[slot]=true;
      if(BadSignalAgainstDir(g_dir[slot]))
      {
         Log("LASTLEG_RECONFIRM_FAIL","slot="+IntegerToString(slot)+" M3/H1/H4 no longer agree with "+(g_dir[slot]>0?"BUY":"SELL")+" after "+IntegerToString(GridCount-1)+" grid leg(s) -- canceling the last leg");
         DeleteLastLegPending(slot);
      }
      else
         Log("LASTLEG_RECONFIRM_OK","slot="+IntegerToString(slot)+" direction still confirmed after "+IntegerToString(GridCount-1)+" grid leg(s) -- last leg stays armed");
   }

   //--- Full-depth bad-signal early exit (NEW 2026-11-21, per user request,
   //    "구간매매" convention -- re-check mid-ladder, bail at breakeven if
   //    wrong): once every leg is filled, if the SAME M3/H1/H4 signal turns
   //    against g_dir, arm the SAME breakeven-or-better close as
   //    UseRegimeFlipExit below. An ADDITIONAL, faster trigger source
   //    alongside RegimeFlipTimeframe's own (slower) cross -- not a
   //    replacement for it.
   if(UseFullDepthBadSignalExit && !g_regimeFlippedAgainstBasket[slot] &&
      CountPositions(slot)==GridCount+1 && BadSignalAgainstDir(g_dir[slot]))
   {
      Log("FULLDEPTH_BADSIGNAL_FLAG","slot="+IntegerToString(slot)+" M3/H1/H4 turned against "+(g_dir[slot]>0?"BUY":"SELL")+" at full depth -- arming breakeven-or-better close");
      g_regimeFlippedAgainstBasket[slot]=true;
   }

   ulong expectedMagic=SlotMagic(slot);
   double sumVolPrice=0, sumVol=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0 || !PositionSelectByTicket(t)) continue;
      if(!IsMine((ulong)PositionGetInteger(POSITION_MAGIC),PositionGetString(POSITION_SYMBOL),expectedMagic)) continue;
      double vol=PositionGetDouble(POSITION_VOLUME), op=PositionGetDouble(POSITION_PRICE_OPEN);
      sumVol+=vol; sumVolPrice+=vol*op;
   }
   if(sumVol<=0) return;
   double avgEntry=sumVolPrice/sumVol;

   MqlTick q; if(!SymbolInfoTick(_Symbol,q)) return;
   double curPrice=(g_dir[slot]>0)?q.bid:q.ask;
   double favSteps=(g_dir[slot]>0 ? (curPrice-avgEntry) : (avgEntry-curPrice))/g_step[slot];
   if(favSteps>g_peakFavSteps[slot]) g_peakFavSteps[slot]=favSteps; // NEW 2026-11-22: diagnostic-only MFE tracker, no behavior change

   //--- Profit trail (NEW 2026-11-21, per user request): once favSteps has
   //    EVER reached ProfitTrailActivateSteps (default 5.0 = $50, 2x the
   //    current $25 SL), arm a trailing stop at the best favorable price
   //    seen since -/+ ProfitTrailDistanceSteps (default 1.0 = $10), FLOORED
   //    at breakeven so it can never lock in a loss once armed. Runs
   //    regardless of regime state -- an ADDITIONAL layer protecting a big
   //    unrealized gain from fully round-tripping before UseSwingTP or the
   //    regime-flip exit below would otherwise catch it. Distinct from the
   //    4th-revision's REMOVED UseBreakevenExit, which ran unconditionally
   //    from ANY profit level and cut aligned-trend winners short (NET
   //    $611->-$4,410) -- this only engages after a much larger move.
   if(UseProfitTrail)
   {
      if(!g_profitTrailArmed[slot] && favSteps>=ProfitTrailActivateSteps)
      {
         g_profitTrailArmed[slot]=true;
         g_profitTrailBestPrice[slot]=curPrice;
         Log("PROFIT_TRAIL_ARMED","slot="+IntegerToString(slot)+" favSteps="+DoubleToString(favSteps,2)+" >= "+DoubleToString(ProfitTrailActivateSteps,2));
      }
      if(g_profitTrailArmed[slot])
      {
         if(g_dir[slot]>0) g_profitTrailBestPrice[slot]=MathMax(g_profitTrailBestPrice[slot],curPrice);
         else              g_profitTrailBestPrice[slot]=MathMin(g_profitTrailBestPrice[slot],curPrice);

         double trailStop=(g_dir[slot]>0) ? g_profitTrailBestPrice[slot]-ProfitTrailDistanceSteps*g_step[slot]
                                           : g_profitTrailBestPrice[slot]+ProfitTrailDistanceSteps*g_step[slot];
         trailStop=(g_dir[slot]>0) ? MathMax(trailStop,avgEntry) : MathMin(trailStop,avgEntry);

         bool trailHit=(g_dir[slot]>0) ? (curPrice<=trailStop) : (curPrice>=trailStop);
         if(trailHit)
         {
            Log("PROFIT_TRAIL_CLOSE","slot="+IntegerToString(slot)+" best="+DoubleToString(g_profitTrailBestPrice[slot],_Digits)+" trailStop="+DoubleToString(trailStop,_Digits)+" cur="+DoubleToString(curPrice,_Digits));
            if(EnableLiveOrders) CloseAllPositions(slot);
            else Log("PROFIT_TRAIL_CLOSE_DRY","would close now (EnableLiveOrders=false)");
            return;
         }
      }
   }

   //--- ONLY OTHER exit this function handles: regime flipped against this
   //    basket (checklist '04 정배/역배 대응', confirmed 2026-11-21) -- while
   //    the regime stays ALIGNED with g_dir and the profit trail above is
   //    unarmed or not yet hit, the basket just waits on UseSwingTP/the hard
   //    SL. A prior revision also ran an unconditional breakeven-recovery
   //    trail regardless of regime state (UseBasketTrailStop/UseBreakevenExit)
   //    -- REMOVED 2026-11-21 after a backtest (NET $611->-$4,410, win rate
   //    65%->54%, avg win $125->$56) showed it was cutting aligned-trend
   //    winners short before they reached the real target, exactly as the
   //    user flagged.
   if(!UseRegimeFlipExit || !g_regimeFlippedAgainstBasket[slot]) return;
   if(favSteps<RegimeFlipMinProfitSteps) return;

   Log("REGIME_FLIP_CLOSE","slot="+IntegerToString(slot)+" favSteps="+DoubleToString(favSteps,3)+" >= RegimeFlipMinProfitSteps="+DoubleToString(RegimeFlipMinProfitSteps,2));
   if(EnableLiveOrders) CloseAllPositions(slot);
   else Log("REGIME_FLIP_CLOSE_DRY","would close now (EnableLiveOrders=false)");
   g_regimeFlippedAgainstBasket[slot]=false; // consumed -- avoid repeated close attempts
}

//+------------------------------------------------------------------+
//| Basket close / finalize                                            |
//+------------------------------------------------------------------+
void FinalizeBasketIfFlat(int slot)
{
   if(CountPositions(slot)>0) return;
   DeletePendings(slot);

   ulong expectedMagic=SlotMagic(slot);
   double basketProfit=0;
   if(g_basketOpenTime[slot]>0 && HistorySelect(g_basketOpenTime[slot]-1,TimeCurrent()))
   {
      int total=HistoryDealsTotal();
      for(int d=0;d<total;d++)
      {
         ulong dt=HistoryDealGetTicket(d);
         if(dt==0) continue;
         if((ulong)HistoryDealGetInteger(dt,DEAL_MAGIC)!=expectedMagic) continue;
         if(HistoryDealGetString(dt,DEAL_SYMBOL)!=_Symbol) continue;
         basketProfit+=HistoryDealGetDouble(dt,DEAL_PROFIT)+HistoryDealGetDouble(dt,DEAL_SWAP)+HistoryDealGetDouble(dt,DEAL_COMMISSION);
      }
   }

   Log("BASKET_CLOSED","slot="+IntegerToString(slot)+" dir="+(g_dir[slot]>0?"BUY":"SELL")+" P0="+DoubleToString(g_p0[slot],_Digits)+
       " step="+DoubleToString(g_step[slot],_Digits)+" finalSL="+DoubleToString(g_sl[slot],_Digits)+
       " finalTP="+DoubleToString(g_tp[slot],_Digits)+" basketProfit="+DoubleToString(basketProfit,2)+
       " peakFavSteps="+DoubleToString(g_peakFavSteps[slot],3));

   g_state[slot]=GS_IDLE; g_dir[slot]=0; g_p0[slot]=0; g_step[slot]=0; g_sl[slot]=0; g_tp[slot]=0; g_basketOpenTime[slot]=0;
   g_regimeFlippedAgainstBasket[slot]=false;
}

//+------------------------------------------------------------------+
//| Restart recovery (auto equivalent of manual tool's RecoverState)   |
//| NEW 2026-11-23: scans each slot's own magic range independently.    |
//+------------------------------------------------------------------+
void RecoverState()
{
   for(int slot=0;slot<g_maxSlots;slot++)
   {
      g_state[slot]=GS_IDLE;
      ulong expectedMagic=SlotMagic(slot);
      ulong firstTicket=0; datetime earliest=0;
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong t=PositionGetTicket(i);
         if(t==0 || !PositionSelectByTicket(t)) continue;
         if(!IsMine((ulong)PositionGetInteger(POSITION_MAGIC),PositionGetString(POSITION_SYMBOL),expectedMagic)) continue;
         datetime ot=(datetime)PositionGetInteger(POSITION_TIME);
         if(earliest==0 || ot<earliest){ earliest=ot; firstTicket=t; }
      }
      if(firstTicket==0) continue; // slot stays idle

      PositionSelectByTicket(firstTicket);
      g_dir[slot]=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?1:-1;
      g_p0[slot]=PositionGetDouble(POSITION_PRICE_OPEN);
      g_sl[slot]=PositionGetDouble(POSITION_SL);
      g_tp[slot]=PositionGetDouble(POSITION_TP);
      g_basketOpenTime[slot]=earliest;
      g_step[slot]=(g_sl[slot]>0 && SLMult>0) ? MathAbs(g_p0[slot]-g_sl[slot])/SLMult : GetStep();
      g_state[slot]=GS_BASKET;
      Log("RECOVERED","slot="+IntegerToString(slot)+" dir="+(g_dir[slot]>0?"BUY":"SELL")+" P0="+DoubleToString(g_p0[slot],_Digits)+
          " step="+DoubleToString(g_step[slot],_Digits)+" SL="+DoubleToString(g_sl[slot],_Digits)+" TP="+DoubleToString(g_tp[slot],_Digits));
   }
}

//+------------------------------------------------------------------+
//| Events                                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   g_maxSlots=(int)MathMax(1,MathMin(MAX_BASKET_SLOTS,MaxConcurrentBaskets)); // NEW 2026-11-23
   hMA    =iMA(_Symbol,Timeframe,MAPeriod,0,MODE_SMA,PRICE_CLOSE);
   hMAFast=iMA(_Symbol,Timeframe,MAFastPeriod,0,MODE_SMA,PRICE_CLOSE);
   hATR   =iATR(_Symbol,Timeframe,StepATRPeriod);
   hMAFlipSlow=iMA(_Symbol,RegimeFlipTimeframe,MAPeriod,0,MODE_SMA,PRICE_CLOSE);
   hMAFlipFast=iMA(_Symbol,RegimeFlipTimeframe,MAFastPeriod,0,MODE_SMA,PRICE_CLOSE);
   hMAHtfFast =iMA(_Symbol,HigherTFAlignment,MAFastPeriod,0,MODE_SMA,PRICE_CLOSE);
   hMAHtfSlow =iMA(_Symbol,HigherTFAlignment,MAPeriod,0,MODE_SMA,PRICE_CLOSE); // RE-ADDED for Avoid zone #1
   hMAHtf2Slow=iMA(_Symbol,HigherTFAlignment2,MAPeriod,0,MODE_SMA,PRICE_CLOSE);
   hMAHtf2Fast=iMA(_Symbol,HigherTFAlignment2,MAFastPeriod,0,MODE_SMA,PRICE_CLOSE);
   hBB4Htf    =iBands(_Symbol,HigherTFAlignment,4,0,4.0,PRICE_OPEN); // "기본비", same construct as 010-013
   if(hMA==INVALID_HANDLE || hMAFast==INVALID_HANDLE || hATR==INVALID_HANDLE ||
      hMAFlipSlow==INVALID_HANDLE || hMAFlipFast==INVALID_HANDLE ||
      hMAHtfFast==INVALID_HANDLE || hMAHtfSlow==INVALID_HANDLE ||
      hMAHtf2Slow==INVALID_HANDLE || hMAHtf2Fast==INVALID_HANDLE ||
      hBB4Htf==INVALID_HANDLE) return INIT_FAILED;

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
       " | UseSessionGatedEntry="+(UseSessionGatedEntry?"true":"false")+" AsiaSessionStartKST="+IntegerToString(AsiaSessionStartKST)+
       " EuropeSessionStartKST="+IntegerToString(EuropeSessionStartKST)+" USSessionStartKST="+IntegerToString(USSessionStartKST)+
       " UseEveryTouchEntry="+(UseEveryTouchEntry?"true":"false")+" MaxConcurrentBaskets="+IntegerToString(g_maxSlots)+
       " | UseATRStep="+(UseATRStep?"true":"false")+" StepATRPeriod="+IntegerToString(StepATRPeriod)+
       " StepATRMult="+DoubleToString(StepATRMult,2)+" GridStepPoints="+DoubleToString(GridStepPoints,1)+
       " | Lots="+DoubleToString(Lots,2)+" GridCount="+IntegerToString(GridCount)+" SLMult="+DoubleToString(SLMult,2)+
       " | UseSwingTP="+(UseSwingTP?"true":"false")+" SwingLookbackBars="+IntegerToString(SwingLookbackBars)+
       " MinSwingTPStep="+DoubleToString(MinSwingTPStep,2)+" UseSwingTPFallbackRR="+(UseSwingTPFallbackRR?"true":"false")+
       " UseFixedRRTp="+(UseFixedRRTp?"true":"false")+" FixedRRRatio="+DoubleToString(FixedRRRatio,2)+
       " | UseProfitTrail="+(UseProfitTrail?"true":"false")+" ProfitTrailActivateSteps="+DoubleToString(ProfitTrailActivateSteps,2)+
       " ProfitTrailDistanceSteps="+DoubleToString(ProfitTrailDistanceSteps,2)+
       " | UseRegimeFlipExit="+(UseRegimeFlipExit?"true":"false")+" RegimeFlipMinProfitSteps="+DoubleToString(RegimeFlipMinProfitSteps,2)+
       " RegimeFlipTimeframe="+EnumToString(RegimeFlipTimeframe)+
       " | UseLastLegConfirm="+(UseLastLegConfirm?"true":"false")+" UseFullDepthBadSignalExit="+(UseFullDepthBadSignalExit?"true":"false")+
       " | UseHigherTFAlignment="+(UseHigherTFAlignment?"true":"false")+" HigherTFAlignment="+EnumToString(HigherTFAlignment)+
       " CounterTrendTPShrink="+DoubleToString(CounterTrendTPShrink,2)+
       " UseHtfBB4Exhaustion="+(UseHtfBB4Exhaustion?"true":"false")+
       " UseHigherTFAlignment2="+(UseHigherTFAlignment2?"true":"false")+" HigherTFAlignment2="+EnumToString(HigherTFAlignment2)+
       " | UseH1H4DisagreeReversal="+(UseH1H4DisagreeReversal?"true":"false")+
       " | UseAvoidBB4MAOverlap="+(UseAvoidBB4MAOverlap?"true":"false")+" AvoidBB4MAOverlapPts="+DoubleToString(AvoidBB4MAOverlapPts,1)+
       " UseAvoidFakeBreakout="+(UseAvoidFakeBreakout?"true":"false")+" FakeBreakoutLookbackBars="+IntegerToString(FakeBreakoutLookbackBars)+
       " | UseAvoidEconCalendar="+(UseAvoidEconCalendar?"true":"false")+" AvoidEconCalendarMinutesBefore="+IntegerToString(AvoidEconCalendarMinutesBefore)+
       " AvoidEconCalendarMinutesAfter="+IntegerToString(AvoidEconCalendarMinutesAfter)+" AvoidEconCalendarCurrency="+AvoidEconCalendarCurrency+
       " AvoidEconCalendarMinImportance="+EnumToString(AvoidEconCalendarMinImportance)+
       " | UseSkipHourKST="+(UseSkipHourKST?"true":"false")+" SkipHourStartKST="+IntegerToString(SkipHourStartKST)+
       " SkipHourEndKST="+IntegerToString(SkipHourEndKST)+
       " | Magic="+IntegerToString((int)MagicNumber)+" | orders="+(EnableLiveOrders?"ENABLED":"DRY"));

   if(UseAvoidEconCalendar)
   {
      MqlCalendarValue diagVals[];
      int diagCnt=CalendarValueHistory(diagVals,D'2025.01.01',D'2026.12.31',NULL,AvoidEconCalendarCurrency);
      int diagHighCnt=0;
      for(int i=0;i<diagCnt;i++)
      {
         MqlCalendarEvent ev;
         if(CalendarEventById(diagVals[i].event_id,ev) && ev.importance>=AvoidEconCalendarMinImportance) diagHighCnt++;
      }
      Log("CALENDAR_DIAG","CalendarValueHistory returned "+IntegerToString(diagCnt)+" "+AvoidEconCalendarCurrency+
          " events total over 2025.01.01-2026.12.31, "+IntegerToString(diagHighCnt)+" at importance>="+EnumToString(AvoidEconCalendarMinImportance)+
          " -- if this is 0, Strategy Tester has no calendar data cached and UseAvoidEconCalendar will never fire (check terminal calendar cache/internet access during the test)");
   }

   RecoverState(); // NEW 2026-11-23: initializes g_state[] for every slot (IDLE unless an open position is found)
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
   if(hMAHtfFast!=INVALID_HANDLE)  IndicatorRelease(hMAHtfFast);
   if(hMAHtfSlow!=INVALID_HANDLE)  IndicatorRelease(hMAHtfSlow);
   if(hMAHtf2Slow!=INVALID_HANDLE) IndicatorRelease(hMAHtf2Slow);
   if(hMAHtf2Fast!=INVALID_HANDLE) IndicatorRelease(hMAHtf2Fast);
   if(hBB4Htf!=INVALID_HANDLE)     IndicatorRelease(hBB4Htf);
}

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   ulong dealMagic=(ulong)HistoryDealGetInteger(trans.deal,DEAL_MAGIC);
   if(dealMagic<MagicNumber || dealMagic>=MagicNumber+(ulong)MAX_BASKET_SLOTS) return; // NEW 2026-11-23: any slot's magic range
   if(HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=_Symbol) return;
   if((long)HistoryDealGetInteger(trans.deal,DEAL_ENTRY)!=DEAL_ENTRY_OUT) return;

   ulong posId=(ulong)HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID);
   double profit=HistoryDealGetDouble(trans.deal,DEAL_PROFIT)+HistoryDealGetDouble(trans.deal,DEAL_SWAP)+HistoryDealGetDouble(trans.deal,DEAL_COMMISSION);
   Log("GRID_LEG_CLOSED","slot="+IntegerToString((int)(dealMagic-MagicNumber))+" posId="+IntegerToString((long)posId)+" profit="+DoubleToString(profit,2));
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

   //--- session bookkeeping (NEW 2026-11-23, for UseSessionGatedEntry):
   //    checked every tick (hour-based, not bar-based) -- re-arms
   //    g_sessionEntryUsed whenever the KST hour crosses into a new
   //    session block.
   int curSessionIdx=SessionIndex(KST_Hour(TimeCurrent()));
   if(curSessionIdx!=g_lastSessionIdx)
   {
      g_lastSessionIdx=curSessionIdx;
      g_sessionEntryUsed=false;
   }

   //--- per-slot maintenance (NEW 2026-11-23): every slot that currently has
   //    a basket open gets its exits checked/finalized, every tick,
   //    regardless of whether any OTHER slot is free or busy.
   for(int s=0;s<g_maxSlots;s++)
   {
      if(g_state[s]!=GS_BASKET) continue;
      FinalizeBasketIfFlat(s);
      if(g_state[s]==GS_BASKET) UpdateBasketExits(s);
   }

   //--- entry attempt (NEW 2026-11-23: across all basket slots) ---
   if(g_awaitDir==0) return; // no cross episode currently awaiting its first 120MA touch
   double ma; if(!GetMA(ma)) return;
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   bool touched=(g_awaitDir>0)?(bid<=ma):(bid>=ma);
   if(!touched) return;

   int freeSlot=-1;
   for(int s=0;s<g_maxSlots;s++) if(g_state[s]==GS_IDLE){ freeSlot=s; break; }
   if(freeSlot<0)
   {
      Log("ENTRY_SKIPPED","all "+IntegerToString(g_maxSlots)+" basket slot(s) busy -- episode stays armed, retry later");
      return;
   }

   if(!UseEveryTouchEntry && UseSessionGatedEntry && g_sessionEntryUsed)
   {
      Log("ENTRY_SKIPPED","session already used ("+IntegerToString(g_lastSessionIdx)+"=0:Asia/1:Europe/2:US) -- episode stays armed, retry next session");
      return;
   }

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

   //--- Decide the final direction. Priority order (highest first):
   //    1) H1 BB4(4,4) exhaustion fade (UseHtfBB4Exhaustion)
   //    2) H1 price-vs-20MA override (UseHigherTFAlignment)
   //    3) the M3 cross's own direction (g_awaitDir), unchanged
   int finalDir=g_awaitDir;
   bool bb4Fired=false;
   if(UseHtfBB4Exhaustion)
   {
      int bb4Dir=DecideFinalDirByBB4(g_awaitDir,bb4Fired);
      if(bb4Fired) finalDir=bb4Dir;
   }
   if(!bb4Fired && UseHigherTFAlignment) finalDir=DecideFinalDir(g_awaitDir);
   bool isCounterTrend=(finalDir!=g_awaitDir);
   if(bb4Fired)
      Log("HTF_BB4_EXHAUSTION_OVERRIDE","M3 cross dir="+(g_awaitDir>0?"BUY":"SELL")+" -> BB4 fade dir="+(finalDir>0?"BUY":"SELL")+" ("+EnumToString(HigherTFAlignment)+" candle touched the band)");
   else if(isCounterTrend)
      Log("H1_DIRECTION_OVERRIDE","M3 cross dir="+(g_awaitDir>0?"BUY":"SELL")+" -> H1 override dir="+(finalDir>0?"BUY":"SELL")+" (counter-trend, shrunk TP)");

   if(UseH1H4DisagreeReversal)
   {
      int h1Dir=DecideFinalDir(finalDir);
      int h4Dir=CrossDir(hMAHtf2Fast,hMAHtf2Slow,h1Dir);
      if(h1Dir!=h4Dir)
      {
         Log("H1H4_DISAGREE_REVERSE","H1 dir="+(h1Dir>0?"BUY":"SELL")+" H4 dir="+(h4Dir>0?"BUY":"SELL")+" disagree -- inverting finalDir "+(finalDir>0?"BUY":"SELL")+" -> "+(finalDir<0?"BUY":"SELL"));
         finalDir=-finalDir;
         isCounterTrend=(finalDir!=g_awaitDir);
      }
   }
   else if(UseHigherTFAlignment2 && !TFAligned(finalDir,hMAHtf2Fast,hMAHtf2Slow))
   {
      Log("ENTRY_SKIPPED","HigherTFAlignment2 ("+EnumToString(HigherTFAlignment2)+") not aligned with "+(finalDir>0?"BUY":"SELL")+" -- episode stays armed, retry on a later touch");
      return;
   }

   if(UseAvoidBB4MAOverlap && InAvoidZoneBB4MAOverlap())
   {
      Log("ENTRY_SKIPPED","Avoid zone #1: "+EnumToString(HigherTFAlignment)+" BB4+120MA overlap (상위저항) -- episode stays armed, retry on a later touch");
      return;
   }
   if(UseAvoidFakeBreakout && InAvoidZoneFakeBreakout(finalDir))
   {
      Log("ENTRY_SKIPPED","Avoid zone #2: "+EnumToString(HigherTFAlignment)+" failed breakout (가짜돌파) in dir="+(finalDir>0?"BUY":"SELL")+" -- episode stays armed, retry on a later touch");
      return;
   }
   if(UseAvoidEconCalendar && InAvoidZoneEconCalendar())
   {
      Log("ENTRY_SKIPPED","Avoid zone #4: "+AvoidEconCalendarCurrency+" high-importance calendar event within -"+IntegerToString(AvoidEconCalendarMinutesBefore)+"/+"+IntegerToString(AvoidEconCalendarMinutesAfter)+" min -- episode stays armed, retry on a later touch");
      return;
   }

   g_dir[freeSlot]=finalDir;
   if(!UseEveryTouchEntry && !UseSessionGatedEntry) g_awaitDir=0; // consume -- only the FIRST touch after this cross enters (UseSessionGatedEntry/UseEveryTouchEntry keep it armed for the next touch instead)

   if(!DoFirstEntry(freeSlot))
   {
      g_awaitDir=g_dir[freeSlot]; g_dir[freeSlot]=0; // restore, retry next tick
      return;
   }
   if(UseSessionGatedEntry) g_sessionEntryUsed=true; // NEW 2026-11-23: consumed only on a SUCCESSFUL entry, for this session block
   double step=GetStep();
   double tpCandidate=0;
   if(UseSwingTP)
   {
      double rawTarget=(g_dir[freeSlot]>0) ? SwingHigh(SwingLookbackBars) : SwingLow(SwingLookbackBars);
      if(rawTarget>0)
         tpCandidate = isCounterTrend ? (g_p0[freeSlot]+g_dir[freeSlot]*MathAbs(rawTarget-g_p0[freeSlot])*CounterTrendTPShrink) : rawTarget;
   }
   PlaceGrid(freeSlot,step,tpCandidate);
}
//+------------------------------------------------------------------+
