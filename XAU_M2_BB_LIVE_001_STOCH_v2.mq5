//+------------------------------------------------------------------+
//| XAU_M2_BB_LIVE_001_STOCH_v2.mq5                                    |
//| New strategy (user-designed): same M2 dual-BB signal-candle       |
//| detection used throughout this project (BB20 dev2.0 on Close +   |
//| BB4 dev4.0 on Open, PERIOD_M2), but direction is decided by the   |
//| Stochastic reading AT THE CLOSE of that signal candle instead of  |
//| always countertrend:                                              |
//|                                                                    |
//|   Bull signal candle (up breakout):                                |
//|     Stoch %K >= StochOverbought (70) -> SELL (countertrend, fade   |
//|       the move -- stochastic confirms it's overextended)          |
//|     Stoch %K <  StochOverbought      -> BUY  (trend-following --  |
//|       stochastic does NOT confirm overextension, so follow it)    |
//|   Bear signal candle (down breakout):                              |
//|     Stoch %K <  StochOversold (30)   -> BUY  (countertrend, fade) |
//|     Stoch %K >= StochOversold        -> SELL (trend-following)    |
//|                                                                    |
//| Entry is IMMEDIATE at market right when the signal candle closes   |
//| -- no Extension/Pullback staging like the 005-family EAs. R is    |
//| the signal candle's body (|close-open|), same definition as       |
//| elsewhere in this project. Exit is a single fixed bracket, no      |
//| protect-lock: SL = entry -+ SL_R*R, TP = entry +- TP_R*R.          |
//| MAX1 position at a time (own magic number).                        |
//| V2: added AllowSellFade -- ground-truth backtest (2025.01-2026.09, |
//| SL_R=4.0, MinR_Points=400) showed the bull+overbought SELL-fade    |
//| case is the ONE structurally losing direction (PF 0.88, -$4,848),  |
//| consistent with gold's persistent uptrend bias found elsewhere in  |
//| this project (005's own SELL-disable finding). The other three    |
//| cases were all net profitable (combined +$15,050). Confirmed      |
//| default is now false (skips that case); set true to reproduce V1  |
//| exactly. SL_R/TP_R defaults were also corrected from a stale       |
//| 1.0/0.5 to the confirmed 4.0/0.45 used in every backtest referenced|
//| throughout this file's header.                                     |
//| _v2 build: same logic as the live XAU_M2_BB_STOCH_V2 EA this      |
//| replaces, plus diagnostic logging on previously-silent failure    |
//| paths in CheckNewM2Bar() (BAR_DATA_FAIL / COPYBUFFER_FAIL) to      |
//| catch a repeat of a multi-hour silent-signal window seen live on  |
//| 2026.09.23.                                                        |
//| SkipTrendBearAsiaSession=true (confirmed default) skips            |
//| STOCH_TREND_BEAR specifically during the Asia session (06-16 KST)  |
//| where it's a structural loser, while it's solidly profitable in    |
//| Europe (16-22) and US (22-06) hours. A real backtest confirmed a    |
//| clean improvement on every metric (NET, PF, and drawdown all       |
//| better); see the input's own comment for numbers.                  |
//| MaxMinutesWithoutProgress (default 0, disabled) closes a position   |
//| early once it's been open this many minutes, regardless of P&L --   |
//| motivated by TP-hit trades resolving in ~3min median vs SL-hit      |
//| trades taking ~36min median. UNTESTED as a live rule; see the       |
//| input's own comment for the caveat before trusting it.              |
//| MAE-milestone tracking (diagnostic only, no trading effect): logs   |
//| MAE_MILESTONE when a position's adverse excursion crosses 50%/75%   |
//| of SL_R, and MAE_OUTCOME with the final win/loss at close -- lets   |
//| the CSV log answer "given a trade reached 50%/75% of its stop,      |
//| what fraction still won" (not available from the xlsx report).     |
//| Also tags firstBarOneWay on that same MAE_OUTCOME line: true when    |
//| the very next M2 bar after entry never moved favorably by even 1     |
//| point (BUY: bar's high never exceeded entry; SELL: bar's low never  |
//| went below it) before closing -- tests whether an immediate,        |
//| zero-pullback move against the position predicts a one-way run      |
//| into the stop.                                                      |
//| threeBarOneWay extends this over the entry candle + next 2 (3        |
//| candles total): true when the running favorable extreme across all   |
//| 3 (highest high for a BUY, lowest low for a SELL) never crossed      |
//| entry -- i.e. the position was never in profit at any point during   |
//| those 3 candles, not just that each one individually closed          |
//| unfavorably.                                                          |
//| UseThreeBarExit (UNTESTED): acts on threeBarOneWay -- force-closes a  |
//| position right when the 3rd candle closes if it was never profitable  |
//| during those 3. Ground truth on the confirmed baseline (3,273         |
//| trades): 1,946 already resolved before 3 candles (TP typically hits   |
//| in ~1-2 candles); of the 1,327 that survived, threeBarOneWay=true     |
//| (111 trades) loses 30.63% of the time vs 17.11% for the rest (1,216)  |
//| -- both already far above the 7.88% overall rate, but the gap nearly  |
//| doubles conditional loss risk. Needs its own backtest before trusting |
//| it: cutting here forfeits the ~69% of threeBarOneWay=true trades that |
//| still recover to a win.                                               |
//| UseFirstBarExit (REJECTED): a broader, weaker variant of UseThreeBarExit|
//| -- acts on firstBarOneWay (just the entry candle's own high/low vs     |
//| entry, not the running 3-candle extreme) instead of threeBarOneWay,    |
//| and only for TREND_BULL/FADE_BEAR_OS tags (TREND_BEAR showed ~zero     |
//| lift on this diagnostic: 11.5% vs 11.8%). Diagnostic motivation: on    |
//| the pre-combo baseline, TREND_BULL firstBarOneWay=true (87 trades)     |
//| loses 18.4% vs 13.0% for the rest (687) -- only a 1.4x lift, net       |
//| -$2,772.06 on those 87. FADE_BEAR_OS shows a stronger lift: 22.1% (95  |
//| trades) vs 10.9% (896) -- 2.0x, net -$3,180.84 on those 95. Ground-    |
//| truth backtest against the ComboExit-confirmed baseline (NET           |
//| $27,148.70, WR 92.01%, n=3,273) REJECTED it: NET $25,062.64 (-7.7%),   |
//| WR 87.61% (-4.40pp), n=3,350 (+77). Of the 188 forced exits, 186 were  |
//| losses (net -$7,923.70) -- forcing the exit after just 1 candle cut   |
//| off recovery for most of the 78-82% of this group that would have     |
//| eventually won if left alone, converting them into realized losses,   |
//| plus the same faster-MAX1-turnover harm seen in every other rejected   |
//| early-exit idea here. A 1-candle bar is too early a checkpoint for     |
//| this signal; only the surgical threeBarOneWay+danger combo survives.   |
//| nextBarOppose/UseNextBarOpposeExit (REJECTED): a variant of             |
//| firstBarOneWay/UseFirstBarExit above, but using the next bar's own      |
//| CANDLE COLOR (close vs open) instead of its high/low EXTREME vs entry   |
//| price -- e.g. for a SELL, did the very next bar simply close green,     |
//| regardless of whether price ever ticked favorably first. Applied to ALL |
//| four tags (TREND_BULL, TREND_BEAR, FADE_BULL_OB, FADE_BEAR_OS), unlike  |
//| UseFirstBarExit which only covered TREND_BULL/FADE_BEAR_OS (FADE_BULL_OB |
//| had zero trades in the test run, since AllowSellFade=false). Ground-    |
//| truth backtest against the ComboExit-confirmed baseline (NET            |
//| $27,148.70, WR 92.01%, PF 1.382, n=3,273) REJECTED it hard: NET          |
//| $3,935.10 (-85.5%), WR 56.91% (-35.1pp), PF 1.058, n=3,729 (+456). Of    |
//| the 1,567 forced exits (42% of all trades), 99.1-99.7% were losses in   |
//| every one of the three tags that fired (FADE_BEAR_OS: 753 flagged,      |
//| 99.73% loss, avg -$38.96; TREND_BEAR: 228 flagged, 99.12% loss, avg     |
//| -$29.52; TREND_BULL: 586 flagged, 99.15% loss, avg -$24.68) -- the      |
//| opposite-color next bar is itself just normal noise around entry       |
//| (near coin-flip), so forcing a close on it realizes a loss on almost    |
//| every trade before TP_R=0.45 ever has a chance to be hit, exactly the   |
//| same checking-too-early failure as UseFirstBarExit, just far more       |
//| severe because the trigger condition fires far more often.              |
//| trend10Oppose/UseEntryTrend10OpposeExit (REJECTED): unlike every        |
//| early-exit idea above (all checked within 1-3 candles of entry and all  |
//| failed the same way -- cutting off recovery before it had time to       |
//| happen), this requires a much longer confirmation window. Condition:    |
//| (1) the entry bar itself closed opposite trade direction (same as       |
//| nextBarOppose above), AND (2) the AVERAGE candle body (mean of           |
//| close-open) over the Trend10LookbackBars (default 10) bars AFTER the    |
//| entry bar is ALSO net opposite. Only acts once both are known, i.e.     |
//| only on positions that are still open ~20+ min after entry -- closer in |
//| spirit to the CONFIRMED ComboExit's danger-zone dwell-time approach     |
//| than to the rejected 1-candle checks, since a sustained 10-candle       |
//| adverse drift is a much lower-noise signal than one candle's color.     |
//| Diagnostic ground truth (no forced exit) showed this combo DOES isolate |
//| a genuinely bad cohort -- trades flagged nextBarOppose=true AND         |
//| trend10Oppose=true (n=389) lost money even left alone naturally (32.4%  |
//| loss rate vs ~8% baseline, avg -$61.08/trade, net -$23,759.56). But     |
//| acting on it made things WORSE, not better: ground-truth backtest       |
//| against the ComboExit-confirmed baseline (NET $27,148.70, WR 92.01%,    |
//| n=3,273) gave NET $22,292.21 (-17.9%), WR 84.04% (-7.97pp), n=3,490.    |
//| The 412 forced exits averaged -$79 to -$106/trade across all three      |
//| tags (worse than the -$61.08 natural average of that same cohort),      |
//| because forcing the close at the 11-bar checkpoint realizes a loss on   |
//| the 67.6% of the cohort that would have eventually WON, while only      |
//| modestly shortening the loss on the 32.4% that would have hit full SL   |
//| anyway -- the former outweighs the latter. The diagnostic has real      |
//| post-hoc explanatory power but, like every other pre/mid-trade signal   |
//| tried this project, isn't strong enough to act on profitably; only      |
//| ComboExit's surgical threeBarOneWay+danger-zone combo clears that bar.  |
//| UseDangerWindowFilter (REJECTED) / UseFridayFilter (CONFIRMED=all day,  |
//| but see UseFridayNarrowWindow below, which supersedes it as the live    |
//| default):                                                                |
//| unlike everything above (all post-entry diagnostics/exits on THIS EA's  |
//| own signals), these are pre-entry time-of-day/day-of-week ENTRY BLOCKS  |
//| sourced from an outside reference (a discretionary gold-trading         |
//| methodology writeup) that names specific KST windows as session-        |
//| ownership handoff points where whipsaw/one-way risk concentrates:       |
//| 09:30-10:30 (China open), 14:00-18:00 (Asia close -> Europe open/       |
//| "London surge", two adjacent windows per the source's own naming),      |
//| 20:00-22:30 (US pre-market independent window), 00:30-03:30 (Europe     |
//| close/reversal hour) -- UseDangerWindowFilter blocks new entries (all   |
//| four tags) during any of these. UseFridayFilter separately blocks       |
//| Friday entries from FridayFilterFromHourKST onward (0=all day), per     |
//| the same source's specific Friday warning. Motivation: cross-checking   |
//| these named windows against the live account's actual 2-week trade     |
//| history (not this EA's own backtest) found ALL of the net loss falling  |
//| inside them -- 67 of 147 trades (45.6%) fell in the 5 danger windows    |
//| and totaled -$1,646.67, while the other 80 trades totaled +$203.70;     |
//| Friday alone was -$1,408.50 across 32 trades vs every other weekday     |
//| combined being roughly flat-to-positive. Ground-truth backtest against  |
//| the ComboExit-confirmed baseline (NET $27,148.70, WR 92.01%, PF 1.382,  |
//| MaxDD $2,254.80, n=3,273) split the two: UseDangerWindowFilter alone    |
//| gave NET $17,067.52 (-37.1%), WR 91.41%, PF 1.438, MaxDD $2,225.00      |
//| (~flat) on n=1,781 (-45.6%, matching the live sample's block rate) --   |
//| REJECTED, since the 2-week sample's "almost all losses in this window"  |
//| pattern did NOT reproduce at full-backtest scale (the blocked trades    |
//| were only mildly worse than average, not catastrophic), same failure    |
//| mode as every other filter that looked strong on a small/post-hoc       |
//| slice this session. UseFridayFilter alone gave NET $29,833.29 (+9.9%),  |
//| WR 92.38%, PF 1.561 on n=2,717 (-17.0%) -- a clean win on every return   |
//| metric with FEWER trades, so CONFIRMED (MaxDD ticked up slightly to      |
//| $2,423.10, so it improves returns without reducing tail risk). Both      |
//| together gave NET $15,297.30 (-43.6%), PF 1.527, MaxDD $1,533.90        |
//| (-32.0%) on n=1,444 -- combining them cuts worst-case drawdown          |
//| substantially but at a steep NET cost, so it's a deliberate             |
//| return-for-safety trade rather than a clear win; left off by default.   |
//| UseFridayNarrowWindow (CONFIRMED, now the live default) vs              |
//| UseTradingWindowFilter (REJECTED): two different "only trade some       |
//| hours" ideas tested head-to-head against each other and against         |
//| UseFridayFilter's all-day Friday block. UseFridayNarrowWindow allows     |
//| Friday entries only in 10:30-15:00 KST (other days unaffected, other     |
//| Friday hours blocked) instead of skipping Friday entirely.               |
//| UseTradingWindowFilter is the inverse framing of UseDangerWindowFilter   |
//| above -- a POSITIVE allow-list applied every day: only entries falling   |
//| inside 10:30-15:00, 16:00-21:00, or 22:30-02:50 KST are let through,     |
//| blocking the gaps 02:50-10:30, 15:00-16:00, 21:00-22:30 (notably still   |
//| swallowing UseDangerWindowFilter's 00:30-03:30/09:30-10:30 windows but   |
//| allowing straight through its 14:00-18:00/20:00-22:30 windows).          |
//| Ground-truth backtest against the ComboExit-confirmed baseline (NET      |
//| $27,148.70, WR 92.01%, PF 1.382, MaxDD $2,254.80, n=3,273) and against   |
//| UseFridayFilter's own confirmed result (NET $29,833.29, WR 92.38%,       |
//| PF 1.561, MaxDD $2,423.10, n=2,717):                                     |
//|  - UseTradingWindowFilter alone: NET $16,173.30 (-40.4%), WR 91.42%,     |
//|    PF 1.324 (WORSE than baseline), MaxDD $3,180.71 (+41.1%, WORSE on     |
//|    every metric), n=2,157. REJECTED -- concentrating trades into fewer   |
//|    daily windows apparently concentrates risk too (losses cluster in     |
//|    the allowed windows rather than being diluted across the day).        |
//|  - UseTradingWindowFilter + UseFridayFilter: NET $15,324.31 (-43.6%),    |
//|    PF 1.422, MaxDD $2,807.20 (+24.5%), n=1,720. Also worse than either   |
//|    filter alone -- REJECTED.                                             |
//|  - UseFridayNarrowWindow alone: NET $30,035.69 (+10.6% vs baseline,      |
//|    and +$202.40 better than UseFridayFilter's own all-day block), WR     |
//|    92.30%, PF 1.541, MaxDD $2,423.10 (identical to UseFridayFilter's     |
//|    own MaxDD -- the worst drawdown period apparently doesn't involve     |
//|    Friday trading either way), n=2,807 (keeps 90 more trades than the    |
//|    all-day block). A clean improvement over the already-confirmed        |
//|    all-day block on every metric except a very slightly lower PF, so     |
//|    CONFIRMED and promoted to the new live default in place of            |
//|    UseFridayFilter (left in place, now off by default, for reference/    |
//|    future comparison -- the two are meant as alternatives, not combined).|
//| UseTradingWindowFilter's 3 windows were later parameterized              |
//| (Window1/2/3 Start/EndHourKST, decimal hours, e.g. 10.5=10:30; a window  |
//| wraps past midnight whenever its end<=start) so new window combinations  |
//| can be tried via .set file alone -- the REJECTED verdict above is tied   |
//| specifically to the original hardcoded defaults (10:30-15:00/           |
//| 16:00-21:00/22:30-02:50), which remain the input defaults; a different   |
//| set of bounds is a fresh, untested hypothesis and needs its own          |
//| ground-truth run.                                                        |
//| ComboExitDangerMin/UseComboExit (CONFIRMED=10min/true): an AND of the  |
//| two ideas above instead of either alone -- only closes when a         |
//| position is BOTH threeBarOneWay=true AND has spent ComboExitDangerMin |
//| in the danger zone. Diagnostic motivation: of the 111                 |
//| threeBarOneWay=true trades in the confirmed baseline, the small       |
//| subset (26) that ALSO spent >=5min in the danger zone lost 84.6% of   |
//| the time (18 trades at >=10min: 83.3%) vs just 28.3% for              |
//| threeBarOneWay=true trades that stayed under 30min in the danger      |
//| zone. Ground-truth backtest confirmed this holds despite the tiny     |
//| slice (only 7 trades affected, 0.2% of all 3,273): a CLEAN            |
//| improvement on every metric -- NET $26,138.92 -> $27,148.70 (+3.9%),  |
//| PF 1.363 -> 1.382, MaxDD $2,483.70 -> $2,254.80 (-9.2%), Recovery     |
//| Factor 10.524 -> 12.040 (+14.4%), WR essentially unchanged (92.09%->  |
//| 92.01%) -- unlike UseProtectStop/UseDangerTimeStop/UseThreeBarExit    |
//| above (all individually REJECTED), this surgical AND-combination is   |
//| the one idea from this whole early-exit investigation that works.     |
//| UseTrend10ComboExit (default false, UNTESTED): tries the same         |
//| AND-with-danger-time recipe that made UseComboExit work, but swaps    |
//| in trend10Oppose instead of threeBarOneWay -- closes when BOTH        |
//| trend10Oppose=true AND timeDangerMin>=ComboExitDangerMin. A DIFFERENT |
//| version of trend10Oppose as an exit (UseEntryTrend10OpposeExit, gated |
//| on a fixed ~20min/11-bar delay instead of actual danger-zone dwell    |
//| time) was already REJECTED despite the diagnostic cohort being         |
//| genuinely bad (nextBarOppose=true AND trend10Oppose=true, n=389, 32.4% |
//| natural loss rate vs ~8% baseline) -- forcing the close there realized |
//| a loss on the 67.6% that would have eventually won, outweighing the    |
//| shortened losses on the 32.4% that would have hit SL anyway. This      |
//| swaps the fixed-delay gate for ComboExit's own danger-time gate (and   |
//| drops the extra nextBarOppose AND-condition) to see if that same       |
//| "only act once the position has actually dwelled in danger, not just  |
//| waited out a fixed bar count" distinction that saved threeBarOneWay    |
//| also rescues this signal. Needs its own ground-truth run.              |
//| UseTrendFilter (default false, REJECTED): skips an entry when a      |
//| strong opposing trend is already established on TrendFilterTimeframe |
//| (default M15) -- ADX >= ADXThreshold and the dominant DI points      |
//| against the intended direction. Theory: one-way losses happen when   |
//| the opposing trend was already in place before entry, not created    |
//| by the trade itself. Ground-truth backtest against the ComboExit-     |
//| confirmed baseline (NET $27,148.70, WR 92.01%, PF 1.382, n=3,273):    |
//| REJECTED -- NET $12,727.79 (-53.1%), WR 91.35% (-0.66pp), PF 1.238,   |
//| n=2,324 (-949, -29.0%). The 949 entries the ADX filter blocked were   |
//| worth more per trade ($15.19 avg) than the overall average ($8.30),   |
//| i.e. it disproportionately blocked GOOD trades, not the specific      |
//| one-way-persistence losers it was meant to catch -- this strategy's   |
//| core edge is fading BB breakouts, and a strong ADX reading often      |
//| just means a clean, tradeable breakout rather than a danger sign.     |
//| oppSignalSeen (diagnostic, always logged regardless of                |
//| UseOppositeSignalExit): true if a NEW opposite-direction M2 signal   |
//| candle (same BB20/BB4 breakout + R filter as entries) appeared at    |
//| any point while the position was open -- answers "of trades that     |
//| hit SL, what fraction had an opposite signal candle appear before    |
//| the loss" and "of trades where an opposite signal appeared, what     |
//| fraction still hit TP anyway" straight from the CSV log.             |
//| UseOppositeSignalExit (default false, UNTESTED as of the current      |
//| reached75-gated form -- see the input's own comment): when true,     |
//| ACTS on the opposite-signal detection above, but only once the       |
//| position has ALSO reached 75% of SL_R, by closing it at market       |
//| immediately. An earlier version acted on ANY opposite signal with    |
//| no 75% gate and was ground-truth REJECTED (NET $17,746 -> $12,245,   |
//| losses 218 -> 471) because it also cut ~131 shallow-pullback trades  |
//| that had a 100% natural win rate. That test also exposed a same-tick |
//| close+reopen logging race (fixed by moving tracking from single      |
//| scalars to TRACK_SLOTS-indexed arrays keyed by ticket) -- the CSV    |
//| had silently dropped 349 trade outcomes, which is why the corrupted  |
//| CSV first looked like a huge improvement before the official xlsx    |
//| report was checked.                                                   |
//| reachedFav50/75/90 (diagnostic only, no trading effect): the MFE       |
//| (Maximum Favorable Excursion) mirror of reached50/75 -- true if price |
//| moved that fraction of the way to TP_R at any point before the        |
//| position closed. Answers "of trades that got close to TP, what        |
//| fraction still reversed all the way to a LOSS" -- tests whether a      |
//| breakeven/lock-in rule near TP would be favorable. Unlike the MAE-side |
//| cuts (all rejected), the asymmetry here should run the other way:      |
//| giving up a small remaining slice of TP_R to avoid a full SL_R loss.   |
//| SLOPE_CALC / SLOPE_SIM_OUTCOME (diagnostic only, no trading effect):   |
//| tests the user's hypothesis that the 20-period MA's slope at a BB      |
//| signal candle predicts whether the breakout continues (trade WITH the  |
//| candle's direction) or fails (trade AGAINST it). MT5 has no native     |
//| "MA angle" value -- a raw price-per-bar slope is meaningless without   |
//| a scale, since the same slope looks like 5 degrees or 60 degrees       |
//| depending on chart zoom -- so the angle here is a deliberately-defined |
//| pseudo-angle, normalized by R (this strategy's own volatility unit),   |
//| not a real chart angle: slopeDeg = arctan((MA[now]-MA[N bars ago]) /   |
//| (N*R)) in degrees. |slopeDeg| <= SlopeThresholdDeg is classified FLAT  |
//| (hypothesis: fade the breakout); above it, STEEP (hypothesis: follow   |
//| the breakout). SLOPE_CALC logs this classification for EVERY signal    |
//| candle regardless of whether Stochastic/session filters would trade    |
//| it, so goal 1 (does the hypothesis alone reach SlopeSimTargetR) can be  |
//| checked against the full signal population. A separate, independent   |
//| forward simulation (its own tracking slots, no real order placed)      |
//| checks whether price reaches SlopeSimTargetR (default 0.5R) in the     |
//| slope-implied direction, logged as SLOPE_SIM_OUTCOME once it hits or   |
//| SlopeSimExpiryHours elapses. Goal 2 (does adding this to the existing  |
//| Stochastic decision help) is answered by cross-referencing SLOPE_CALC  |
//| against the real trade's own MAE_OUTCOME on trades that did place an   |
//| order -- both logged with the same TimeCurrent() timestamp and the     |
//| same signal candle, so they join directly in the CSV.                 |
//| Ground truth on the slope hypothesis (IgnoreStochastic + cross-        |
//| referencing SLOPE_CALC against real outcomes): Stochastic itself       |
//| turned out to matter mostly for tail-risk control, not raw win rate    |
//| (IgnoreStochastic=true kept win rate at 89.26% vs baseline 90.93%, but |
//| NET fell 67% and max holding time went from ~30h to ~132h). MA slope   |
//| does NOT reproduce that role: within TREND-decided trades, FLAT vs     |
//| STEEP win rates were statistically indistinguishable (~91% both), and  |
//| skipping TREND+FLAT entirely would forfeit 763 wins to avoid only 74    |
//| losses (net +47R cost) -- rejected as a Stochastic substitute/filter.  |
//| UseSlopeFilterTrendBull/SlopeFilterTrendBullDeg (UNTESTED): a narrower, |
//| later finding than the broad SlopeThresholdDeg=20 rejection above --    |
//| that test used a threshold so high (20deg) it almost never fired (only |
//| 3/3,282 signals classified STEEP; median |slopeDeg| is just 2.84, p95   |
//| 9.51). Re-examining at realistic thresholds, specifically for TREND_BULL|
//| (buying a bull signal candle while the 5-bar BB20 slope, deg5/the       |
//| SlopeLookbackBars-based slopeDeg, is still pointed DOWN -- i.e. buying  |
//| into what's still a short-term decline) shows a real, monotonic         |
//| pattern the broad test missed: fighting a >2deg opposing slope (n=87)   |
//| loses 16.09% vs 8.63% for the rest, net -$950.69 vs +$8,147.84; at      |
//| >3deg (n=41) 19.51% vs 8.81%, net -$572.20 (avg -$13.96/trade) vs       |
//| +$6.71/trade; at >5deg (n=14) 28.57% loss rate, avg -$38.34/trade.      |
//| FADE_BEAR_OS shows the same direction but much weaker (already trades   |
//| into declines by design), and TREND_BEAR shows the OPPOSITE pattern     |
//| (fighting an opposing slope did BETTER there, n=27, 0% losses) -- so    |
//| this filter is scoped to TREND_BULL only, not applied symmetrically.    |
//| Default SlopeFilterTrendBullDeg=3.0 matches the diagnostic's clearest   |
//| break point. Needs its own ground-truth backtest -- this is a           |
//| retrospective crosstab on the confirmed baseline's own log, not yet     |
//| confirmed as an entry-time filter.                                      |
//| effRatio= / htfAligned= / atrExpansion= (diagnostic only, no trading    |
//| effect): three independent candidates for detecting a persistent        |
//| one-way move at entry time, motivated by live trading on 2026.09.28 and |
//| 2026.10.02 where multiple models (different timeframes, same fade       |
//| design) entered within minutes of each other and lost together during   |
//| a sustained directional move -- i.e. the "diversification" across       |
//| timeframes breaks down exactly during these events. ADX size and MA-    |
//| slope size (see SlopeFilterTrendBullDeg/adxRiseDiff above) did NOT      |
//| predict this for FADE_BEAR_OS -- if anything strong momentum into the   |
//| oversold/overbought extreme predicted a BETTER outcome there (comes off |
//| as capitulation/exhaustion, not persistence) -- so these three measure  |
//| different things than raw momentum size:                                |
//|  - effRatio: Kaufman Efficiency Ratio over EfficiencyRatioPeriod (30)    |
//|    bars on the main Timeframe -- |net move|/sum(|bar-to-bar moves|).     |
//|    Near 1.0 = a clean one-way run with little back-and-forth; near 0 =   |
//|    pure chop. Distinguishes HOW a move got there, not just how far/fast. |
//|  - htfAligned: true when the most recently closed HigherTFForTrend       |
//|    (default H1) candle is ITSELF a BB20/BB4 breakout candle in the same  |
//|    direction as this M2 signal -- i.e. confirmed on a slower timeframe,  |
//|    not just a local M2 wiggle.                                           |
//|  - atrExpansion: current HigherTFForTrend ATR(ATRPeriod) divided by its  |
//|    own ATRAvgPeriod-bar average -- >1 means today's volatility regime is |
//|    expanding above its recent norm (candidate "trend day" flag).         |
//| No backtest yet for any of the three -- all new log fields, nothing to   |
//| cross-reference in an existing log.                                      |
//| CIRCUIT_BREAKER_TRIGGERED / CIRCUIT_BREAKER_(WOULD_)SKIP (diagnostic   |
//| always on; UseCircuitBreaker ACTS): after CircuitBreakerLossCount      |
//| consecutive LOSS outcomes (any tag), pauses new entries for            |
//| CircuitBreakerCooldownHours, on the theory that a losing streak may    |
//| flag a temporarily bad regime rather than being pure noise -- a        |
//| different mechanism from every previously-tested idea, which all       |
//| acted on individual trades rather than withholding entries during a    |
//| bad stretch. UNTESTED as a live rule.                                  |
//| Entry-parameter re-optimization (sequential 1-at-a-time sweep via MT5   |
//| Optimizer, Recovery Factor max, after every cut-early idea above was    |
//| tested and rejected): StochK_Period 16->8, StochOverbought 70->85,      |
//| StochOversold unchanged at 30, MinR_Points 400->350. Ground-truth       |
//| confirmed result: NET $16,858.10 -> $24,529.78 (+45.5%), PF 1.286,      |
//| Recovery Factor 10.33, MaxDD 4.05% -> 2.14%.                            |
//| BE_TRIGGER / BE_RETRACE / BE_STOP_MOVED (diagnostic always on;          |
//| UseBreakevenStop ACTS): tests whether moving the stop to breakeven      |
//| (entry price) once a position reaches BreakevenTriggerFrac of TP_R in   |
//| its favor can shrink the size of individual losses without giving up    |
//| much on winners -- distinct from the already-rejected MFE-based         |
//| "give up a slice of TP" idea (reachedFav50/75/90 above), since this     |
//| resets to ~$0 instead of locking in a partial profit, and the trigger   |
//| threshold is independently configurable rather than reusing those      |
//| fixed 50/75/90% milestones. BE_TRIGGER logs when the threshold is first |
//| crossed; BE_RETRACE logs if price later comes back to the entry level   |
//| (the only way this could actually matter, since SL_R >> TP_R here means |
//| a trade can only reach the real SL by first passing back through        |
//| breakeven). The key question answerable from BE_RETRACE trades' own     |
//| MAE_OUTCOME: of trades that retrace all the way back to breakeven after |
//| triggering, what fraction still recover to a WIN (the cost of this      |
//| rule, since UseBreakevenStop would have converted that WIN into ~$0)    |
//| vs continue on to the full LOSS (the benefit, since it would have been  |
//| capped at ~$0 instead). Given SL_R is roughly 9-11x TP_R here, this     |
//| rule is net positive only if the recovered-WIN fraction among retraced  |
//| trades is well below roughly TP_R/(TP_R+SL_R). UNTESTED as a live rule. |
//| Ground truth: rejected -- 90.6% of trades that retraced to breakeven    |
//| after triggering still recovered to a WIN, ~9x above the ~10.1%        |
//| breakeven threshold; going live would have cost the +$5,253 this       |
//| bucket actually made. Diagnostic-only, kept off (UseBreakevenStop=false)|
//| ProtectTriggerR/ProtectR/UseProtectStop (diagnostic always on;          |
//| UseProtectStop ACTS, UNTESTED): a different idea from the rejected      |
//| breakeven stop above -- instead of moving SL to exactly breakeven at    |
//| BreakevenTriggerFrac of TP_R, this locks in a SMALL PROFIT (ProtectR,   |
//| default 0.05R, not 0) at an earlier, TP_R-independent trigger           |
//| (ProtectTriggerR, default 0.25R -- for TP_R~0.45-0.5 this is roughly    |
//| half of TP_R, same shape as 007/005's own protect-lock stage). The      |
//| rejected breakeven test showed giving back the WHOLE favorable move     |
//| at the 50%-of-TP point was too costly (90.6% of retraces still          |
//| recovered to a win); locking a small profit instead of exactly $0,      |
//| and arming earlier, could behave differently -- needs its own           |
//| backtest (PROTECT_TRIGGER logs every arm regardless of UseProtectStop,  |
//| PROTECT_MOVED/PROTECT_MOVE_FAIL log the live SL modify outcome).        |
//| timeMildMin/timeDangerMin (diagnostic only, no trading effect):         |
//| minutes a position spends with adverse excursion below MildZoneR        |
//| (default 2.0, half of SL_R=4.0) vs at/above it. Motivated by a real     |
//| hold-time-vs-loss pattern found in the confirmed baseline (3,273        |
//| trades): losses hold far longer than wins (avg 212min vs 31min) and     |
//| the loss rate jumps sharply past a ~30min threshold (3.5% under 30min   |
//| -> 25-33% beyond it) rather than scaling smoothly with time (plain      |
//| correlation only 0.18) -- this breaks total hold time down by how much  |
//| of it was spent already deep against the position vs still mild.       |
//| DangerTimeStopMin/UseDangerTimeStop (REJECTED): acts on the above --   |
//| force-closes a position once its cumulative timeDangerMin reaches      |
//| DangerTimeStopMin (default 20min). Ground truth on the confirmed       |
//| baseline (3,273 trades) motivating this: NO trade stays under          |
//| MildZoneR(2R) and still loses (0/2,732); of the 541 that ever cross    |
//| into the danger zone, loss rate climbs with time spent there --        |
//| 28.5% under 5min, 53.5% at 5-15min, 61.4% at 15-30min, 70.6% at        |
//| 30-60min -- far stronger than total hold time alone (corr 0.23 vs      |
//| 0.18) or mild-zone time alone (corr 0.05). Distinct from               |
//| MaxMinutesWithoutProgress (fires on total hold time regardless of      |
//| favorable/adverse) and from ProtectTriggerR/ProtectR above (price-     |
//| level based, already shown to hurt NET/WR at a shallow 0.25R trigger)  |
//| -- this is a TIME cutoff conditional on being meaningfully against     |
//| the position. Re-tested at 20min against the ComboExit-confirmed       |
//| baseline (NET $27,148.70, WR 92.01%, n=3,273): REJECTED -- NET         |
//| $22,268.81 (-18.0%), WR 90.07% (-1.94pp), n=3,413 (+140). Of the 160   |
//| forced exits, ALL 160 were losses (net -$30,757.10) -- the diagnostic's|
//| own 61-71% loss rate at this dwell time means roughly a third would    |
//| have recovered if left alone, and cutting every one of them at 20min   |
//| forfeits that fraction entirely, on top of the same faster-MAX1-       |
//| turnover harm seen in every other standalone early-exit idea here.     |
//| ProtectStopEuropeOnly (REJECTED): the all-hours ProtectTriggerR=0.25/   |
//| ProtectR=0.05 test was REJECTED (NET -33% at 0.1-lot-equivalent, WR    |
//| 92.09%->84.19%, trade count 3,273->3,523 -- the early SL move freed    |
//| MAX1 up faster, letting in more, worse re-entries). Restricting the    |
//| SL-move to only arm while the CURRENT time (when favR crosses          |
//| ProtectTriggerR) falls in the Europe session (16-22 KST) was tested    |
//| against the ComboExit-confirmed baseline (NET $27,148.70, WR 92.01%,   |
//| n=3,273) and still REJECTED: NET $24,015.48 (-11.5%), WR 89.66%        |
//| (-2.35pp), n=3,346 (+73). Of the 866 trades where the SL actually      |
//| moved, WR was even higher than average (95.8%) -- the harm isn't from |
//| those trades themselves, it's the same faster-MAX1-turnover mechanism |
//| as the all-hours test, just reduced in scope (866 vs all 3,176         |
//| triggers) rather than eliminated. Restricting to EU hours only does    |
//| NOT recover the benefit.                                               |
//| ProtectStopAsiaOnly (REJECTED): same mechanism, restricted instead to  |
//| the Asia session (AsiaSessionStartHour-AsiaSessionEndHour KST, default |
//| 6-16). Also tested against the ComboExit-confirmed baseline (NET       |
//| $27,148.70, WR 92.01%, n=3,273) and REJECTED, though less severely     |
//| than the Europe-only test: NET $25,287.65 (-6.9%), WR 88.74%           |
//| (-3.27pp), n=3,348 (+75). Of the 1,020 trades where the SL actually    |
//| moved, WR was again above average (95.5%) on their own -- same        |
//| faster-MAX1-turnover mechanism, just scoped to the wider 10h Asia      |
//| window (vs Europe's 6h) instead of eliminated. Both session-restricted |
//| variants of the protect-lock idea are now REJECTED.                    |
//| SIGNAL's touch=BODY/WICK and MAE_OUTCOME's touch= (diagnostic always   |
//| on; SkipFadeBearOSWickTouch ACTS): the entry condition only requires   |
//| the signal candle's high/low (wick) to reach BB20; this additionally   |
//| checks whether the CLOSE (body) also broke the band ("BODY") vs        |
//| wicked through and closed back inside ("WICK") -- tests whether a body |
//| break (more conviction) behaves differently from a rejection wick.     |
//| Ground truth (2025.01-2026.09, StochK_Period=8/OB=85/OS=30/MinR=350):  |
//| BODY beat WICK consistently on every tag, both on win rate and $/trade:|
//| overall 92.32% ($10.46/trade) vs 89.70% ($0.58/trade, z=2.14) --       |
//| FADE_BEAR_OS 92.7%/+$18,282 vs 88.7%/-$325 (net NEGATIVE, the only     |
//| losing tag x touch combination), TREND_BEAR 93.8%/+$5,378 vs 89.7%/    |
//| +$109, TREND_BULL 91.3%/+$6,031 vs 90.4%/+$563. Only FADE_BEAR_OS+WICK |
//| is actually net negative, so SkipFadeBearOSWickTouch filters only that |
//| combination rather than all WICK touches (TREND_BEAR/TREND_BULL WICK   |
//| are still profitable, just weaker than BODY). CONFIRMED default=true:  |
//| ground-truth backtest showed NET $24,877.21 -> $26,237.13 (+5.5%), PF   |
//| 1.304 -> 1.342, Recovery Factor 9.14 -> 9.58, WR 91.86% -> 92.12%, DD    |
//| essentially unchanged (~2.2%) -- a clean improvement on every metric.  |
//| AsiaSessionStartHour/EndHour (default 6/16, Korea time): the           |
//| SkipTrendBearAsiaSession window bounds. An hour-by-hour breakdown of    |
//| the same data found losses actually concentrate in 06-11 KST, while     |
//| 12-17 KST is profitable -- try narrowing EndHour to 11 to test keeping  |
//| those hours active. Hourly samples are much smaller (20-45 trades/hour  |
//| vs 200+ for the 8h blocks), so treat this as a follow-up experiment,    |
//| not a confirmed result yet.                                            |
//| MAE_OUTCOME's prior5Same= (diagnostic only, no trading effect): checks  |
//| the 5 candles immediately BEFORE the signal candle (shifts 2-6) -- true |
//| when all 5 ran in the same direction as the signal candle's own         |
//| breakout (all bearish into a bear/down signal candle, all bullish into  |
//| a bull/up one). Motivated by the question of whether a longer one-way   |
//| run right before a countertrend fade entry (FADE_BEAR_OS buying after a |
//| bear signal candle, or FADE_BULL_OB selling after a bull one) predicts  |
//| the fade's outcome. Ground truth on the confirmed baseline: FADE_BEAR_OS|
//| shows essentially no effect (true: 135 trades, 8.1% loss vs false: 1,513|
//| trades, 7.4% loss -- within noise). Not pursued further for 001.       |
//| MAE_OUTCOME's adxRiseDiff= (diagnostic only, no trading effect, BEAR    |
//| signal candles only): on the M2-timeframe ADX (its own hADXM2 handle,  |
//| distinct from UseTrendFilter's M15 hADX), compares candle "1" (furthest|
//| of the 5 pre-signal candles, shift 6) against candle "5" (closest,     |
//| shift 2) -- adxRiseDiff = ADX[shift2]-ADX[shift6]. Tests whether a      |
//| rising ADX (trend strengthening) into a FADE_BEAR_OS buy predicts a     |
//| worse outcome than a flat/falling one. No backtest yet -- needs a fresh |
//| one since this is a new field (not in any already-logged run).         |
//|                                                                      |
//| UseSupplyZoneFilter (OFF by default): 매물대 proximity gate ported from  |
//| the 주노짜앙/지킬 reference doc + the [매물대]/HHJ TradingView scripts    |
//| the user shared -- requires the signal close within SupplyZoneATR of   |
//| at least one enabled zone level: Asia/NY session opening-hour box,     |
//| today's running high/low, previous KST day's high/low, and the         |
//| previous NY-session-window's own high/low (user-requested addition,    |
//| tracked separately from the whole-day high/low since a session's       |
//| range can differ from the full calendar day's). Each zone is its own   |
//| toggle so they can be bucketed individually before combining.          |
//|                                                                      |
//| FIRST bucketing pass (n=1,903 trades) ran on a log with                |
//| UseTradingWindowFilter=true drifted from this file's own defaults --   |
//| it showed zoneDistATR 0-0.3 as the ONLY negative-NET bucket for        |
//| TREND_BULL/BEAR (n=216, NET -$1,239.40, PF 0.834), which looked like a  |
//| clean confirmation of the user's hypothesis (매물대 at the breakout      |
//| close resists TREND continuation but not FADE). UseSupplyZoneFilter     |
//| was built as a TREND-only block on that basis and set SupplyZoneATR=0.3|
//| by default.                                                            |
//|                                                                      |
//| THAT DID NOT REPLICATE under corrected settings (UseTradingWindowFilter|
//| =false, matching this file's real defaults). A clean head-to-head       |
//| (filter ON vs OFF, otherwise identical settings) showed PF improving     |
//| slightly (TREND 1.423->1.459) but NET actually FALLING ($11,707.73->    |
//| $9,455.81, -$2,251.92) -- re-bucketing the OFF run showed 0-0.3 was      |
//| actually net-POSITIVE ($2,065.94 over n=318) under correct settings,     |
//| just lower-PF than most other buckets (1.268, second-lowest of 5) --     |
//| not an actual loss bucket. Blocking it cut a still-profitable slice.     |
//| The one pattern that DID replicate across both datasets: 0.3-0.6 was     |
//| consistently TREND's best bucket by far (PF 2.198, then 2.289).          |
//|                                                                        |
//| Currently re-testing a tighter SupplyZoneATR=0.15 cutoff to see if an    |
//| even narrower "right at the wall" zone is the real danger zone (vs       |
//| 0-0.3 being too wide and catching profitable trades along with bad       |
//| ones). Not yet validated either way -- treat UseSupplyZoneFilter as      |
//| experimental until a tighter cutoff's own clean head-to-head confirms    |
//| a real NET improvement, not just a PF one.                               |
//|                                                                        |
//| zoneDistATR= in MAE_OUTCOME (diagnostic, always logged regardless of    |
//| UseSupplyZoneFilter's on/off state): distance from the signal close to   |
//| the NEAREST enabled zone level, in ATR(Timeframe) units ("n/a" if no     |
//| enabled zone has a value yet).                                          |
//|                                                                        |
//| DI= in MAE_OUTCOME (diagnostic, UNTESTED, no trading effect): DI        |
//| (이격도/disparity index) = signal candle close / SMA(DIPeriod) * 100 --   |
//| >100 means price is trading above its own MA by that many percent,      |
//| <100 means below. Tests whether how far price has already run from its |
//| MA predicts the signal's outcome (e.g. a FADE bought/sold deep into      |
//| over-extension vs a TREND entry chasing an already-stretched move).     |
//| Needs a backtest to read the DI crosstab vs TREND/FADE outcome before    |
//| considering turning it into an active filter.                           |
//|                                                                        |
//| diBaseAgainst=/diCrossSeen=/diCrossR= in MAE_OUTCOME (diagnostic,       |
//| UNTESTED, no trading effect): tests the user's "exit on DI reversal"     |
//| proposal -- enter normally, but if the M2-timeframe +DI/-DI (hADXM2)     |
//| crosses against the trade's direction before the hard SL, would exiting  |
//| right there have been better? diBaseAgainst = was DI ALREADY against     |
//| the trade's direction at entry (common for FADE, which buys/sells into  |
//| a signal candle breaking the opposite way -- no "reversal" to detect,    |
//| "n/a" skips those). diCrossSeen/diCrossR (only meaningful when            |
//| diBaseAgainst=false) = did DI later flip against the trade, and what     |
//| R-multiple price was at when that first happened (what an early exit     |
//| there would have banked, vs the trade's actual MAE_OUTCOME profit/R).    |
//| Needs a backtest to compare diCrossR against the trade's eventual         |
//| outcome before considering wiring this up as an active exit.             |
//|                                                                        |
//| UseRSIInsteadOfStoch (default false, UNTESTED): swaps the entire         |
//| TREND/FADE oscillator from Stochastic %K (StochOverbought/Oversold,      |
//| 85/30) to RSI(RSIPeriod) against RSIOverbought/RSIOversold (default       |
//| 70/30, RSIPeriod=8 to match StochK_Period) -- the BULL/FADE/TREND         |
//| branch logic itself (AllowSellFade, SkipFadeBearOSWickTouch, Asia-        |
//| session handling) is completely unchanged, only which oscillator and      |
//| thresholds decide the OB/OS branch. User's question: does RSI classify    |
//| overbought/oversold meaningfully differently from Stochastic on this      |
//| M2 signal, given RSI is a pure momentum oscillator (no %K/%D smoothing     |
//| over a lookback range) vs Stochastic's range-position measure? Trade        |
//| comment tag suffix changes from K<value> to R<value> when this is on, so    |
//| live/backtest trade history stays distinguishable either way. Needs its     |
//| own ground-truth run against the StochOverbought=85/StochOversold=30        |
//| confirmed baseline.                                                         |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input ENUM_TIMEFRAMES Timeframe = PERIOD_M2; // signal-candle timeframe
input double Lots               = 0.1; // Lot size
input int    StochK_Period      = 8;    // Stoch %K period
input int    StochD_Period      = 3; // Stoch %D period
input int    StochSlowing       = 3; // Stoch slowing
input double StochOverbought    = 85.0; // Stoch overbought level
input double StochOversold      = 30.0; // Stoch oversold level

// -- RSI-instead-of-Stochastic swap (UNTESTED, see header): when true, the
//    TREND/FADE oscillator branch below reads RSI(RSIPeriod) against
//    RSIOverbought/RSIOversold instead of Stochastic %K against
//    StochOverbought/StochOversold -- the BULL/FADE/TREND branch logic
//    itself (AllowSellFade, SkipFadeBearOSWickTouch, Asia-session handling)
//    is unchanged, only which oscillator/thresholds decide the branch.
input bool   UseRSIInsteadOfStoch = false; // Swap the TREND/FADE oscillator from Stochastic to RSI (UNTESTED, see header)
input int    RSIPeriod            = 8; // RSI period (only used when UseRSIInsteadOfStoch=true)
input double RSIOverbought        = 70.0; // RSI overbought level (only used when UseRSIInsteadOfStoch=true)
input double RSIOversold          = 30.0; // RSI oversold level (only used when UseRSIInsteadOfStoch=true)
input double SL_R               = 4.0;  // Stop loss (R)
input double TP_R               = 0.45; // Take profit (R)
input double MinR_Points        = 350;  // Min signal-candle body (points) to trade, 0=no filter
input ulong  MagicNumber        = 95016101; // Magic number
input int    MaxDeviationPts    = 50; // Max price deviation (points)
input bool   EnableLiveOrders   = false; // Enable live orders
input bool   AllowSellFade      = false; // Allow bull+overbought SELL-fade case (CONFIRMED false, see header)
input bool   SkipTrendBearAsiaSession = true; // Skip TREND_BEAR during Asia session (CONFIRMED, see header)
input int    AsiaSessionStartHour = 6;   // Asia-session skip window start hour, Korea time
input int    AsiaSessionEndHour   = 16;  // Asia-session skip window end hour, Korea time
input bool   ReverseTrendBearAsiaSession = false; // Reverse TREND_BEAR in Asia session to BUY (UNTESTED, see header)
input int    MaxMinutesWithoutProgress = 0; // Close position after N min regardless of P&L, 0=disabled (UNTESTED, see header)

input bool   UseTradingWindowFilter = false; // Only allow new entries inside Window1/2/3 (REJECTED with defaults below, see header)
input double Window1StartHourKST = 10.5; // Window 1 start, KST, decimal hour (10.5=10:30)
input double Window1EndHourKST   = 15.0; // Window 1 end, KST, decimal hour
input double Window2StartHourKST = 16.0; // Window 2 start, KST, decimal hour
input double Window2EndHourKST   = 21.0; // Window 2 end, KST, decimal hour
input double Window3StartHourKST = 22.5; // Window 3 start, KST, decimal hour (wraps past midnight if end<start)
input double Window3EndHourKST   = 2.8333; // Window 3 end, KST, decimal hour (2.8333=02:50)
input bool   UseDangerWindowFilter = false; // Block new entries (all tags) during 5 KST session-transition windows (REJECTED, see header)
input bool   UseFridayFilter    = false; // Block new entries (all tags) on Friday from FridayFilterFromHourKST onward (SUPERSEDED by UseFridayNarrowWindow, see header)
input int    FridayFilterFromHourKST = 0; // Hour (KST) from which Friday entries are blocked when UseFridayFilter=true (0 = all day Friday)
input bool   UseFridayNarrowWindow = true; // Alternative to UseFridayFilter: on Friday, only allow entries 10:30-15:00 KST, other days unaffected (CONFIRMED, see header)
input bool   UseTrendFilter     = false; // Skip entry if opposing trend on higher TF (REJECTED, see header)
input ENUM_TIMEFRAMES TrendFilterTimeframe = PERIOD_M15; // Higher timeframe for UseTrendFilter
input int    ADXPeriod          = 14;    // ADX period for UseTrendFilter
input double ADXThreshold       = 25.0;  // ADX trending threshold for UseTrendFilter

input bool   UseOppositeSignalExit = false; // Close on opposite signal past 75% SL_R (UNTESTED, see header)

input int    SlopeLookbackBars  = 5;     // MA slope diagnostic: lookback bars (no trading effect)
input double SlopeThresholdDeg  = 20.0;  // MA slope diagnostic: FLAT/STEEP threshold (degrees)
input double SlopeSimTargetR    = 0.5;   // MA slope diagnostic: simulated target (R)
input double SlopeSimExpiryHours = 6.0;  // MA slope diagnostic: simulation expiry (hours)

input double SlopeFilterTrendBullDeg = 3.0; // Opposing BB20 slope (deg, SlopeLookbackBars) that blocks a TREND_BULL entry (UNTESTED, see header)
input bool   UseSlopeFilterTrendBull = false; // Skip TREND_BULL entry if opposing slope exceeds SlopeFilterTrendBullDeg (UNTESTED, see header)

input int    EfficiencyRatioPeriod = 30; // Kaufman Efficiency Ratio lookback, Timeframe bars (diagnostic, no trading effect)

input ENUM_TIMEFRAMES HigherTFForTrend = PERIOD_H1; // Higher timeframe for HTF BB alignment + ATR expansion (diagnostic, no trading effect)
input int    ATRPeriod          = 14;    // ATR period on HigherTFForTrend (diagnostic, no trading effect)
input int    ATRAvgPeriod       = 20;    // Bars to average ATR over, on HigherTFForTrend (diagnostic, no trading effect)

input bool   IgnoreStochastic   = false; // Bypass Stochastic decision entirely (UNTESTED, see header)

input int    CircuitBreakerLossCount    = 2;    // Consecutive losses that trigger a pause
input double CircuitBreakerCooldownHours = 6.0; // Pause duration after circuit breaker trips (hours)
input bool   UseCircuitBreaker  = false; // Actually pause entries after a losing streak (UNTESTED, see header)

input double BreakevenTriggerFrac = 0.5; // Fraction of TP_R to arm breakeven stop
input bool   UseBreakevenStop   = false; // Move SL to breakeven once armed (REJECTED, see header)

input double ProtectTriggerR    = 0.25; // Favorable R to arm protect-lock stop (UNTESTED, see header)
input double ProtectR           = 0.05; // SL level once armed, in R (UNTESTED, see header)
input bool   UseProtectStop     = false; // Move SL to ProtectR once armed (UNTESTED, see header)
input bool   ProtectStopEuropeOnly = false; // Restrict ProtectStop arming to Europe session (16-22 KST) only (REJECTED, see header)
input bool   ProtectStopAsiaOnly = false; // Restrict ProtectStop arming to Asia session (AsiaSessionStartHour-AsiaSessionEndHour KST) only (REJECTED, see header)

input double MildZoneR          = 2.0; // Adverse-R boundary for dwell-time diagnostic (no trading effect)
input double DangerTimeStopMin  = 20.0; // Minutes in danger zone before force-close (REJECTED, see header)
input bool   UseDangerTimeStop  = false; // Close position once DangerTimeStopMin reached (REJECTED, see header)

input bool   UseThreeBarExit    = false; // Close position if never profitable in first 3 candles (UNTESTED, see header)

input bool   UseFirstBarExit    = false; // Close TREND_BULL/FADE_BEAR_OS position if firstBarOneWay=true (REJECTED, see header)

input bool   UseNextBarOpposeExit = false; // Close any position if the next bar's candle color opposes trade direction (REJECTED, see header)

input int    Trend10LookbackBars = 10; // Bars after entry bar averaged for trend10Oppose (see header)
input bool   UseEntryTrend10OpposeExit = false; // Close position if entry bar AND avg of next Trend10LookbackBars bars both oppose trade direction (REJECTED, see header)

input double ComboExitDangerMin = 10.0; // Danger-zone minutes required, combined with threeBarOneWay (CONFIRMED, see header)
input bool   UseComboExit       = true; // Close only when BOTH threeBarOneWay AND ComboExitDangerMin are met (CONFIRMED, see header)
input bool   UseTrend10ComboExit = false; // Close when BOTH trend10Oppose=true AND ComboExitDangerMin dwell time are met (UNTESTED, see header -- a fixed bar-count-delay version of this signal, UseEntryTrend10OpposeExit, was REJECTED; this swaps in ComboExit's own danger-time gate instead)

input bool   SkipFadeBearOSWickTouch = true; // Skip FADE_BEAR_OS wick-only touches (CONFIRMED, see header)

// -- 매물대 (supply/demand zone) proximity filter, ported from the 주노짜앙/지킬 -
// reference doc + [매물대]/HHJ TradingView scripts the user shared: require the
// signal close to be within SupplyZoneATR of at least one enabled zone level
// (session opening-hour box, today/prev-day high-low, prev NY-session high-low).
// Master OFF by default; each zone independently toggleable for its own
// ground-truth backtest before combining.
input bool   UseSupplyZoneFilter   = false; // Block TREND_BULL/BEAR (continuation) entries when zoneDistATR<=SupplyZoneATR; FADE entries are never blocked (CONFIRMED by zoneDistATR bucketing, see header)
input double SupplyZoneATR         = 0.15; // TREND-block threshold, as ATR(Timeframe) multiple (0.30 tested CLEAN head-to-head: PF +0.036 but NET -$2,251.92 on TREND since that whole bucket was actually net-positive on corrected settings, see header -- re-testing a tighter cutoff)
input bool   UseAsiaBoxZone        = true; // Include the Asia-session opening-hour candle's high/low
input int    AsiaOpenHourKST       = 8; // KST hour whose candle defines the Asia session open box (source doc: 아시아 7-8시 시작)
input bool   UseNYBoxZone          = true; // Include the NY/US-session opening-hour candle's high/low
input double NYOpenHourKST         = 22.5; // KST hour (decimal) whose candle defines the NY session open box (source doc: 22:30 본장)
input bool   UseTodayHighLowZone   = true; // Include today's running high/low (so far, KST calendar day)
input bool   UsePrevDayHighLowZone = true; // Include the previous KST calendar day's high/low
input bool   UsePrevNYHighLowZone  = true; // Include the previous day's NY-session-window high/low (user-requested: "미국장 전일 고가저가")
input double NYSessionStartHourKST = 20.0; // KST hour (decimal) the NY session window starts, for 전일 미장 고가/저가 tracking (wraps past midnight)
input double NYSessionEndHourKST   = 6.0; // KST hour (decimal) the NY session window ends

// -- DI (이격도/disparity index) diagnostic (UNTESTED, no trading effect):
//    DI = signal candle close / SMA(DIPeriod) * 100. >100 = price trading
//    above its own MA by that many percent, <100 = below. Tests whether
//    how far price has already run from its MA predicts the signal's
//    outcome (e.g. a FADE bought/sold deep into over-extension vs a TREND
//    entry chasing an already-stretched move). Diagnostic only -- logged
//    on every trade so it can be bucketed before considering a filter.
input int    DIPeriod              = 20; // SMA period for the 이격도 baseline

int hBB20=INVALID_HANDLE,hBB4=INVALID_HANDLE,hStoch=INVALID_HANDLE,hADX=INVALID_HANDLE,hADXM2=INVALID_HANDLE,hRSI=INVALID_HANDLE;
int hBB20_HTF=INVALID_HANDLE,hBB4_HTF=INVALID_HANDLE,hATR_HTF=INVALID_HANDLE,hMA_DI=INVALID_HANDLE;
int hATR_Sig=INVALID_HANDLE;
datetime last_m2_bar=0;
int f_log=INVALID_HANDLE;

// -- supply-zone state (all in KST calendar-day terms) --
int    g_szLastDay=-1;          // KST day index of the last processed bar, -1=uninitialized
bool   g_szAsiaBoxSet=false;    // today's Asia open-hour box already captured
double g_szAsiaHigh=0, g_szAsiaLow=0;
bool   g_szNYBoxSet=false;      // today's NY open-hour box already captured
double g_szNYHigh=0, g_szNYLow=0;
double g_szTodayHigh=0, g_szTodayLow=0;
double g_szPrevDayHigh=0, g_szPrevDayLow=0;
bool   g_szHavePrevDay=false;
double g_szNYSessHigh=0, g_szNYSessLow=0;     // running NY-session-window high/low (in progress)
double g_szPrevNYHigh=0, g_szPrevNYLow=0;     // finalized previous NY-session-window high/low
bool   g_szHavePrevNY=false;
bool   g_szInNYSessPrevBar=false;             // was the previously processed bar inside the NY session window

// -- consecutive-loss circuit breaker (diagnostic always on; ACTS only if
//    UseCircuitBreaker=true) --------------------------------------------
int      g_consecutiveLosses=0;
datetime g_breakerActiveUntil=0;

// -- MAE-milestone tracking (diagnostic only except UseOppositeSignalExit) --
// Tracks, for open position(s), whether the adverse excursion has crossed
// 50%/75% of the SL_R distance, and logs the eventual win/loss outcome
// alongside those flags -- lets us answer "given a trade reached 50%/75% of
// its stop, what fraction still won vs lost" from the CSV log, which the
// MT5 Strategy Tester xlsx report does not expose per-trade.
//
// Kept as small parallel arrays (a slot per in-flight tracked position),
// NOT a single set of scalars, because UseOppositeSignalExit can close a
// position and OpenTrade() can open its replacement within the SAME
// CheckNewM2Bar() call, before OnTradeTransaction's close notification for
// the old ticket has been delivered -- with scalars, the new position's
// StartMAETracking() call overwrote the old ticket's tracking data first,
// so the old position's own MAE_OUTCOME line never got logged (confirmed:
// 349 trades silently dropped from the CSV in one such backtest, all of
// them opposite-signal-exit closes -- the official xlsx trade/loss counts
// didn't match what the "corrupted" CSV appeared to show). Slots are found
// by ticket, not by position/order, so a same-tick close+reopen can never
// collide.
#define TRACK_SLOTS 4
ulong  g_trackTicket[TRACK_SLOTS];
double g_trackEntry[TRACK_SLOTS], g_trackR[TRACK_SLOTS];
int    g_trackDir[TRACK_SLOTS];
bool   g_reached50[TRACK_SLOTS], g_reached75[TRACK_SLOTS];
string g_trackTag[TRACK_SLOTS];

// -- first-bar-after-entry direction (diagnostic only) ----------------------
// Checks whether the very next M2 bar to close after entry moved WITH or
// AGAINST the trade's direction -- tests the hypothesis that an immediate
// opposite-direction bar predicts a one-way move into the stop.
bool   g_waitingFirstBar[TRACK_SLOTS];
bool   g_firstBarKnown[TRACK_SLOTS], g_firstBarOneWay[TRACK_SLOTS];

// -- next-bar-closes-opposite (diagnostic always on; UseNextBarOpposeExit
//    ACTS): different from firstBarOneWay above -- that one compares the
//    bar's high/low EXTREME against the entry price (did price ever tick
//    favorably). This instead looks at the bar's own CANDLE COLOR (close
//    vs open), independent of where it sits relative to entry: for a BUY,
//    did the very next bar close red (bearish candle)? For a SELL, did it
//    close green? Applied to all four tags (TREND_BULL, TREND_BEAR,
//    FADE_BULL_OB, FADE_BEAR_OS), unlike UseFirstBarExit above which only
//    covers TREND_BULL/FADE_BEAR_OS. ------------------------------------
bool   g_waitingNextBar[TRACK_SLOTS];
bool   g_nextBarKnown[TRACK_SLOTS], g_nextBarOppose[TRACK_SLOTS];

// -- entry-bar-plus-10-bar-average-opposite (diagnostic always on;
//    UseEntryTrend10OpposeExit ACTS): extends nextBarOppose above with a
//    much longer, lower-noise confirmation window -- see header. Starts
//    accumulating from the bar AFTER the entry bar (g_trend10JustArmed
//    skips that first call so the entry bar itself, already captured by
//    nextBarOppose, isn't double-counted in the 10-bar average). ---------
bool   g_waitingTrend10[TRACK_SLOTS], g_trend10JustArmed[TRACK_SLOTS];
int    g_trend10Count[TRACK_SLOTS];
double g_trend10Sum[TRACK_SLOTS];
bool   g_trend10Known[TRACK_SLOTS], g_trend10Oppose[TRACK_SLOTS];

// -- first-3-bars-after-entry direction (diagnostic only) --------------------
// Extends the above over the entry candle plus the next 2 (3 candles total):
// tracks the running favorable extreme (highest high for a BUY, lowest low
// for a SELL) across all 3 and checks whether it EVER closed above entry
// (BUY) / below entry (SELL) at any point -- i.e. whether the position was
// ever in profit during those 3 candles, not just whether each candle
// individually closed favorably.
bool   g_waitingBar3[TRACK_SLOTS];
int    g_bar3Count[TRACK_SLOTS];
double g_bar3Extreme[TRACK_SLOTS];
bool   g_bar3Known[TRACK_SLOTS], g_bar3OneWay[TRACK_SLOTS];
bool   g_comboExited[TRACK_SLOTS]; // UseComboExit already force-closed this slot (prevents a double-close attempt)
bool   g_trend10ComboExited[TRACK_SLOTS]; // UseTrend10ComboExit already force-closed this slot (prevents a double-close attempt)

// -- band-reentry tracking (diagnostic only) ---------------------------------
// The entry signal is a BB20 breakout; this checks whether price later
// crosses back to the OTHER side of that same (frozen, as-of-entry) BB20
// level -- i.e. the breakout "gave back" and failed to hold. Cheap to check
// every tick (no waiting for a bar close), unlike the opposite-signal-candle
// idea, which only fires on a full new breakout in the other direction and
// would already be very late. Logged as its own milestone, and also cross-
// referenced with reached50/75 on the outcome line. Ground-truth result:
// bandReentry=true overlapped 100% with reached75=true, so it added no
// separating power beyond MAE depth alone.
double g_lastBandLevel=0; // transient handoff value, set right before OpenTrade()
double g_trackBandLevel[TRACK_SLOTS];
bool   g_bandReentered[TRACK_SLOTS];

// -- BODY vs WICK touch tracking (diagnostic only, no trading effect) -------
// Tests whether a signal candle whose CLOSE also broke the band ("BODY")
// behaves differently from one where only the high/low wicked through it
// while closing back inside ("WICK") -- a body break arguably shows more
// conviction/follow-through than a rejection wick.
bool   g_lastBodyTouch=true; // transient handoff value, set right before OpenTrade()
bool   g_trackBodyTouch[TRACK_SLOTS];

// -- prior-5-candle-same-direction tracking (diagnostic only, no trading
//    effect): checks the 5 candles immediately BEFORE the signal candle
//    (shifts 2-6) -- for a FADE_BEAR_OS (buy after a bear/down signal
//    candle) or FADE_BULL_OB (sell after a bull/up signal candle), this
//    tests whether entering a countertrend trade is better/worse when the
//    run leading into the signal candle was unanimously in the breakout's
//    own direction (i.e. a longer one-way move right before the fade).
bool   g_lastPrior5Same=false; // transient handoff value, set right before OpenTrade()
bool   g_trackPrior5Same[TRACK_SLOTS];

// -- signal-candle rejection-wick length tracking (diagnostic only, no
//    trading effect): the user's observation is that when the signal
//    candle's own wick on the OPPOSITE side of its close (the "rejection"
//    side -- e.g. a long upper wick on a bull breakout candle, showing
//    price got rejected back down after poking higher) is long, the
//    direction tends to reverse soon after rather than continue. Measured
//    as that wick's length in ATR(Timeframe) units: for sigdir=+1,
//    high-MAX(open,close); for sigdir=-1, MIN(open,close)-low.
double g_lastWickLenATR=999.0; // transient handoff value, set right before OpenTrade()
double g_trackWickLenATR[TRACK_SLOTS];

// -- 매물대 proximity at entry (diagnostic only, no trading effect unless
//    UseSupplyZoneFilter=true): distance from the signal close to the
//    NEAREST enabled zone level, in ATR(Timeframe) units. Logged on every
//    trade regardless of the filter's on/off state so TREND_BULL/BEAR
//    (continuation) outcomes can be bucketed by "was there a supply zone
//    right at the breakout close" without needing a fresh backtest per
//    threshold -- the user's hypothesis is that a zone there acts as
//    resistance against the continuation, explaining some one-way/against-
//    trend losses in 001's TREND tags specifically (not FADE, where the
//    zone is the expected target, not an obstacle).
double g_lastZoneDistATR=999.0; // transient handoff value, set right before OpenTrade()
double g_trackZoneDistATR[TRACK_SLOTS];

// -- DI (이격도) tracking (diagnostic only, no trading effect) --
double g_lastDI=0; bool g_lastDIKnown=false; // transient handoff, set right before OpenTrade()
double g_trackDI[TRACK_SLOTS]; bool g_trackDIKnown[TRACK_SLOTS];

// -- pre-signal ADX rise tracking (diagnostic only, no trading effect):
//    for a BEAR signal candle, compares the M2-timeframe ADX at the
//    candle furthest from the signal among the prior 5 (shift 6, "candle
//    1") against the candle closest to it (shift 2, "candle 5") -- tests
//    whether a rising ADX (trend strengthening) into a FADE_BEAR_OS buy
//    predicts the fade's outcome. Uses its own M2-timeframe ADX handle
//    (hADXM2), distinct from UseTrendFilter's M15 one (hADX).
double g_lastAdxRiseDiff=0; bool g_lastAdxRiseKnown=false; // transient handoff, set right before OpenTrade()
double g_trackAdxRiseDiff[TRACK_SLOTS]; bool g_trackAdxRiseKnown[TRACK_SLOTS];

// -- Kaufman Efficiency Ratio tracking (diagnostic only, no trading effect):
//    ER = |net move over EfficiencyRatioPeriod bars| / sum(|bar-to-bar moves|)
//    over the same bars, on the main Timeframe. ER near 1.0 = a clean,
//    one-way directional run (little back-and-forth); ER near 0 = pure
//    chop. Tests whether entering a fade when the market is already running
//    efficiently in one direction predicts a worse outcome. ----------------
double g_lastEffRatio=0; bool g_lastEffRatioKnown=false;
double g_trackEffRatio[TRACK_SLOTS]; bool g_trackEffRatioKnown[TRACK_SLOTS];

// -- higher-timeframe BB breakout alignment tracking (diagnostic only, no
//    trading effect): true when the most recently closed HigherTFForTrend
//    candle is ITSELF a BB20/BB4 breakout candle in the same direction as
//    the M2 signal -- i.e. the move is confirmed on a slower timeframe too,
//    not just a local M2 wiggle. -------------------------------------------
bool g_lastHtfAligned=false; bool g_lastHtfKnown=false;
bool g_trackHtfAligned[TRACK_SLOTS]; bool g_trackHtfKnown[TRACK_SLOTS];

// -- ATR expansion ratio tracking (diagnostic only, no trading effect):
//    current HigherTFForTrend ATR(ATRPeriod) divided by its own average
//    over the last ATRAvgPeriod bars -- >1 means volatility is currently
//    expanding above its recent norm (a possible "trend day" regime). -----
double g_lastAtrExpansion=0; bool g_lastAtrKnown=false;
double g_trackAtrExpansion[TRACK_SLOTS]; bool g_trackAtrKnown[TRACK_SLOTS];

// -- opposite-signal tracking (diagnostic, always on; ACTS only if
//    UseOppositeSignalExit=true AND reached75=true for that slot) ----------
// Tracks whether a NEW opposite-direction M2 signal candle (same BB20/BB4
// breakout + R filter used for entries) appeared at any point while the
// position was open. Logged regardless of UseOppositeSignalExit so we can
// ask "of trades that hit SL, what fraction had an opposite signal candle
// appear before the loss" and "of trades where it appeared, what fraction
// still hit TP anyway" with zero trading effect. Ground truth: unconditional
// opposite-signal exit (any occurrence) was net negative (NET $17,746 ->
// $12,245) because it also cut ~131 trades that never got past a shallow
// pullback and had a 100% natural win rate -- requiring reached75 too
// targets only the already-known 26%-win-rate danger zone instead.
bool   g_trackOppSignalSeen[TRACK_SLOTS];

// -- DI (+DI/-DI) reversal-exit diagnostic (UNTESTED, no trading effect):
//    at entry, records whether the M2-timeframe +DI/-DI (hADXM2) ALREADY
//    favors the OPPOSITE of the trade's direction (common for FADE, which
//    buys/sells into a signal candle breaking the opposite way -- there's
//    no "reversal" to detect there, DI was already against from the start).
//    For trades where it was NOT against at entry, watches each later M2
//    bar for the first time DI flips to favor the opposite side -- a
//    genuine mid-trade DI reversal -- and records the R-multiple price was
//    at that moment (what "exit on DI cross against" would have banked).
//    Tests the user's proposal: enter normally, but if +DI/-DI crosses
//    against the trade before the hard SL, exit early on that signal.
bool   g_trackDIBaseKnown[TRACK_SLOTS], g_trackDIBaseAgainst[TRACK_SLOTS];
bool   g_trackDICrossSeen[TRACK_SLOTS];
double g_trackDICrossR[TRACK_SLOTS];

// -- Stochastic rollover-exit diagnostic (UNTESTED, no trading effect):
//    TREND trades only (tag contains "TREND" -- a FADE entry already starts
//    in the extreme zone by construction, so there's no "reaching the
//    extreme" to detect there). Watches each later M2 bar for stochK first
//    reaching the favorable extreme (>=StochOverbought for a BUY,
//    <=StochOversold for a SELL -- i.e. the move is still accelerating),
//    then rolling back out of that zone (a classic momentum-exhaustion
//    signal) -- and records the R-multiple price was at when the rollover
//    was first detected. Tests the user's proposal: enter on the breakout's
//    own direction as usual, but exit early once Stochastic shows the move
//    peaked and is turning back.
bool   g_trackStochPeaked[TRACK_SLOTS];
bool   g_trackStochRolloverSeen[TRACK_SLOTS];
double g_trackStochRolloverR[TRACK_SLOTS];

// -- MFE (Maximum Favorable Excursion) tracking (diagnostic only, no
//    trading effect) ---------------------------------------------------
// Mirrors the MAE tracking above but for the FAVORABLE direction: tracks
// whether price moved 50%/75%/90% of the way to TP_R (in R terms) at any
// point before the position closed. Since a real TP fill closes the
// position immediately, this can only ever show "got close to TP, then
// ended in outcome X" -- not "hit TP and still lost". Answers: of trades
// that got to 75%/90% of the way to TP, what fraction still reversed all
// the way to a LOSS instead of continuing on to the TP? Given SL_R is far
// larger than TP_R here, if that reversal rate is low, a breakeven/lock-in
// rule once price is most of the way to TP could be asymmetrically
// favorable (small give-up vs a large avoided loss) -- the OPPOSITE
// asymmetry from the MAE-side cuts already tested and rejected.
bool   g_reachedFav50[TRACK_SLOTS], g_reachedFav75[TRACK_SLOTS], g_reachedFav90[TRACK_SLOTS];

// -- breakeven-stop simulation (diagnostic always on; ACTS only if
//    UseBreakevenStop=true) -- see header for the BE_TRIGGER/BE_RETRACE
//    hypothesis --------------------------------------------------------
bool   g_beTriggered[TRACK_SLOTS]; // favFrac >= BreakevenTriggerFrac reached at least once
bool   g_beRetraced[TRACK_SLOTS];  // price came back to the entry level AFTER g_beTriggered
bool   g_beMoved[TRACK_SLOTS];     // live SL was actually moved to breakeven (UseBreakevenStop only)

// -- protect-lock stop simulation (diagnostic always on; ACTS only if
//    UseProtectStop=true) -- see header for the ProtectTriggerR/ProtectR
//    hypothesis. Distinct from the already-rejected breakeven-stop above:
//    this locks a small PROFIT (ProtectR, not 0) at an earlier trigger
//    (ProtectTriggerR, independent of TP_R) rather than moving to
//    breakeven at a fraction of TP_R ----------------------------------
bool   g_protectTriggered[TRACK_SLOTS]; // favR >= ProtectTriggerR reached at least once
bool   g_protectMoved[TRACK_SLOTS];     // live SL was actually moved to the protect-lock level (UseProtectStop only)

// -- dwell-time tracking (diagnostic only, no trading effect): how many
//    minutes a position spends with adverse excursion BELOW MildZoneR
//    (default 2.0, i.e. under half of SL_R=4.0 -- "not yet dangerous") vs
//    AT/ABOVE it ("danger zone", closer to the stop). Answers: does time
//    spent in the mild zone before eventually stopping out differ from
//    winning trades, separate from total hold time? ---------------------
datetime g_trackLastSample[TRACK_SLOTS];
double   g_timeMildMin[TRACK_SLOTS];   // minutes spent with adverseR < MildZoneR
double   g_timeDangerMin[TRACK_SLOTS]; // minutes spent with adverseR >= MildZoneR

// -- MA-slope hypothesis simulation (diagnostic only, no trading effect,
//    independent of TRACK_SLOTS/real positions -- see header comment) ------
// One slot per signal candle (not per position), since this tests every
// signal regardless of whether Stochastic/session filters would trade it.
#define SLOPE_SLOTS 32
bool     g_slopeActive[SLOPE_SLOTS];
double   g_slopeEntry[SLOPE_SLOTS], g_slopeR[SLOPE_SLOTS];
int      g_slopeDir[SLOPE_SLOTS];
bool     g_slopeHit[SLOPE_SLOTS];
datetime g_slopeStart[SLOPE_SLOTS];
double   g_slopeDegVal[SLOPE_SLOTS];
string   g_slopeTag[SLOPE_SLOTS];

void StartSlopeSim(double entry,double R,int dir,double degVal,string tag)
{
   int i=-1;
   for(int k=0;k<SLOPE_SLOTS;k++) if(!g_slopeActive[k]){ i=k; break; }
   if(i<0){ Log("SLOPE_SLOTS_FULL","dropping slope simulation | "+tag); return; }
   g_slopeActive[i]=true; g_slopeEntry[i]=entry; g_slopeR[i]=R; g_slopeDir[i]=dir;
   g_slopeHit[i]=false; g_slopeStart[i]=TimeCurrent(); g_slopeDegVal[i]=degVal; g_slopeTag[i]=tag;
}

void CheckSlopeSims()
{
   bool anyActive=false;
   for(int i=0;i<SLOPE_SLOTS;i++) if(g_slopeActive[i]){ anyActive=true; break; }
   if(!anyActive) return;
   MqlTick q; if(!SymbolInfoTick(_Symbol,q)) return;

   for(int i=0;i<SLOPE_SLOTS;i++)
   {
      if(!g_slopeActive[i]) continue;
      if(!g_slopeHit[i])
      {
         double favR=(g_slopeDir[i]==+1) ? (q.bid-g_slopeEntry[i])/g_slopeR[i] : (g_slopeEntry[i]-q.ask)/g_slopeR[i];
         if(favR>=SlopeSimTargetR) g_slopeHit[i]=true;
      }
      double hoursElapsed=(double)(TimeCurrent()-g_slopeStart[i])/3600.0;
      if(g_slopeHit[i] || hoursElapsed>=SlopeSimExpiryHours)
      {
         Log("SLOPE_SIM_OUTCOME","hit="+(g_slopeHit[i]?"true":"false")+" hours="+DoubleToString(hoursElapsed,2)+
             " slopeDeg="+DoubleToString(g_slopeDegVal[i],2)+" | "+g_slopeTag[i]);
         g_slopeActive[i]=false;
      }
   }
}

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
   if(i<0){ Log("TRACK_SLOTS_FULL","dropping MAE tracking for ticket="+IntegerToString((int)ticket)); return; }
   g_trackTicket[i]=ticket; g_trackEntry[i]=entry; g_trackR[i]=R; g_trackDir[i]=dir;
   g_reached50[i]=false; g_reached75[i]=false; g_trackTag[i]=tag;
   g_waitingFirstBar[i]=true; g_firstBarKnown[i]=false; g_firstBarOneWay[i]=false;
   g_waitingNextBar[i]=true; g_nextBarKnown[i]=false; g_nextBarOppose[i]=false;
   g_waitingTrend10[i]=false; g_trend10JustArmed[i]=false; g_trend10Count[i]=0; g_trend10Sum[i]=0;
   g_trend10Known[i]=false; g_trend10Oppose[i]=false;
   g_waitingBar3[i]=true; g_bar3Count[i]=0; g_bar3Extreme[i]=0; g_bar3Known[i]=false; g_bar3OneWay[i]=false;
   g_comboExited[i]=false;
   g_trend10ComboExited[i]=false;
   g_trackBandLevel[i]=g_lastBandLevel; g_bandReentered[i]=false;
   g_trackOppSignalSeen[i]=false;
   g_reachedFav50[i]=false; g_reachedFav75[i]=false; g_reachedFav90[i]=false;
   g_beTriggered[i]=false; g_beRetraced[i]=false; g_beMoved[i]=false;
   g_protectTriggered[i]=false; g_protectMoved[i]=false;
   g_trackLastSample[i]=TimeCurrent(); g_timeMildMin[i]=0; g_timeDangerMin[i]=0;
   g_trackBodyTouch[i]=g_lastBodyTouch;
   g_trackPrior5Same[i]=g_lastPrior5Same;
   g_trackWickLenATR[i]=g_lastWickLenATR;
   g_trackZoneDistATR[i]=g_lastZoneDistATR;
   g_trackDI[i]=g_lastDI; g_trackDIKnown[i]=g_lastDIKnown;
   g_trackAdxRiseDiff[i]=g_lastAdxRiseDiff; g_trackAdxRiseKnown[i]=g_lastAdxRiseKnown;
   g_trackEffRatio[i]=g_lastEffRatio; g_trackEffRatioKnown[i]=g_lastEffRatioKnown;
   g_trackHtfAligned[i]=g_lastHtfAligned; g_trackHtfKnown[i]=g_lastHtfKnown;
   g_trackAtrExpansion[i]=g_lastAtrExpansion; g_trackAtrKnown[i]=g_lastAtrKnown;

   {
      double diP[1],diM[1];
      bool gotDI=(CopyBuffer(hADXM2,1,1,1,diP)==1 && CopyBuffer(hADXM2,2,1,1,diM)==1);
      g_trackDIBaseKnown[i]=gotDI;
      g_trackDIBaseAgainst[i]=gotDI ? ((dir==+1) ? (diM[0]>diP[0]) : (diP[0]>diM[0])) : false;
      g_trackDICrossSeen[i]=false;
      g_trackDICrossR[i]=0;
   }

   g_trackStochPeaked[i]=false;
   g_trackStochRolloverSeen[i]=false;
   g_trackStochRolloverR[i]=0;
}

// Called from CheckNewM2Bar with the new bar's raw breakout direction
// (sigdir, before the stochastic fade/trend decision -- that decision only
// matters for what a NEW entry would trade, not for detecting that the
// opposite technical signal fired). If UseOppositeSignalExit is on AND the
// slot has already reached 75% of SL, also closes the position at market.
void CheckOppositeSignal(int sigdir)
{
   if(sigdir==0) return;
   for(int i=0;i<TRACK_SLOTS;i++)
   {
      if(g_trackTicket[i]==0) continue;
      if(sigdir!=-g_trackDir[i]) continue; // only the OPPOSITE of the position's direction counts

      if(!g_trackOppSignalSeen[i])
      {
         g_trackOppSignalSeen[i]=true;
         Log("MAE_MILESTONE","opposite signal candle appeared | "+g_trackTag[i]);
      }

      if(!UseOppositeSignalExit) continue;
      if(!g_reached75[i]) continue; // only act in the already-known danger zone (see input comment)
      if(!PositionSelectByTicket(g_trackTicket[i])) continue; // already closed

      double profit=PositionGetDouble(POSITION_PROFIT);
      if(!EnableLiveOrders)
      {
         Log("OPP_SIGNAL_EXIT_DRY","ticket="+IntegerToString((int)g_trackTicket[i])+" profit="+DoubleToString(profit,2)+
             " (would close, EnableLiveOrders=false) | "+g_trackTag[i]);
         continue;
      }
      if(trade.PositionClose(g_trackTicket[i]))
         Log("OPP_SIGNAL_EXIT_CLOSE","ticket="+IntegerToString((int)g_trackTicket[i])+" profit="+DoubleToString(profit,2)+
             " | "+g_trackTag[i]);
      else
         Log("OPP_SIGNAL_EXIT_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
   }
}

// Called once per new M2 bar (unconditionally, regardless of this bar's own
// signal) -- scans all active TRACK_SLOTS for a +DI/-DI reversal against the
// trade's own direction, on the M2-timeframe ADX (hADXM2). Diagnostic only:
// records the R-multiple price was at when the cross was first detected,
// does not close anything. See the g_trackDICrossSeen header comment.
void CheckDICrossExit()
{
   bool anyActive=false;
   for(int i=0;i<TRACK_SLOTS;i++) if(g_trackTicket[i]!=0){ anyActive=true; break; }
   if(!anyActive) return;

   double diP[1],diM[1];
   if(CopyBuffer(hADXM2,1,1,1,diP)!=1 || CopyBuffer(hADXM2,2,1,1,diM)!=1) return;
   MqlTick q; if(!SymbolInfoTick(_Symbol,q)) return;

   for(int i=0;i<TRACK_SLOTS;i++)
   {
      if(g_trackTicket[i]==0) continue;
      if(!g_trackDIBaseKnown[i] || g_trackDIBaseAgainst[i]) continue; // no clean baseline, or already against at entry (nothing to "cross")
      if(g_trackDICrossSeen[i]) continue; // already recorded

      bool nowAgainst=(g_trackDir[i]==+1) ? (diM[0]>diP[0]) : (diP[0]>diM[0]);
      if(!nowAgainst) continue;

      g_trackDICrossSeen[i]=true;
      double px=(g_trackDir[i]==+1) ? q.bid : q.ask;
      g_trackDICrossR[i]=(g_trackDir[i]==+1) ? (px-g_trackEntry[i])/g_trackR[i] : (g_trackEntry[i]-px)/g_trackR[i];
      Log("MAE_MILESTONE","DI crossed against trade direction | wouldExitR="+DoubleToString(g_trackDICrossR[i],3)+" | "+g_trackTag[i]);
   }
}

// Called once per new M2 bar (unconditionally) -- scans active TRACK_SLOTS
// for a Stochastic momentum-exhaustion rollover on TREND trades only (see
// the g_trackStochRolloverSeen header comment). Diagnostic only: records
// the R-multiple price was at when the rollover was first detected, does
// not close anything.
void CheckStochRolloverExit()
{
   bool anyActive=false;
   for(int i=0;i<TRACK_SLOTS;i++) if(g_trackTicket[i]!=0){ anyActive=true; break; }
   if(!anyActive) return;

   double kbuf[1];
   if(CopyBuffer(hStoch,0,1,1,kbuf)!=1) return;
   double stochK=kbuf[0];
   MqlTick q; if(!SymbolInfoTick(_Symbol,q)) return;

   for(int i=0;i<TRACK_SLOTS;i++)
   {
      if(g_trackTicket[i]==0) continue;
      if(StringFind(g_trackTag[i],"TREND")<0) continue; // TREND only, see header
      if(g_trackStochRolloverSeen[i]) continue;

      if(!g_trackStochPeaked[i])
      {
         bool peaked=(g_trackDir[i]==+1) ? (stochK>=StochOverbought) : (stochK<=StochOversold);
         if(peaked) g_trackStochPeaked[i]=true;
         continue; // can't roll over before reaching the extreme
      }

      bool rolledOver=(g_trackDir[i]==+1) ? (stochK<StochOverbought) : (stochK>StochOversold);
      if(!rolledOver) continue;

      g_trackStochRolloverSeen[i]=true;
      double px=(g_trackDir[i]==+1) ? q.bid : q.ask;
      g_trackStochRolloverR[i]=(g_trackDir[i]==+1) ? (px-g_trackEntry[i])/g_trackR[i] : (g_trackEntry[i]-px)/g_trackR[i];
      Log("MAE_MILESTONE","Stochastic rolled over after reaching extreme | wouldExitR="+DoubleToString(g_trackStochRolloverR[i],3)+" | "+g_trackTag[i]);
   }
}

void CheckMAEProgress()
{
   bool anyActive=false;
   for(int i=0;i<TRACK_SLOTS;i++) if(g_trackTicket[i]!=0){ anyActive=true; break; }
   if(!anyActive) return;
   MqlTick q; if(!SymbolInfoTick(_Symbol,q)) return;

   for(int i=0;i<TRACK_SLOTS;i++)
   {
      if(g_trackTicket[i]==0) continue;
      if(!PositionSelectByTicket(g_trackTicket[i])) continue; // closed; OnTradeTransaction logs the outcome
      double adverseR=(g_trackDir[i]==+1) ? (g_trackEntry[i]-q.bid)/g_trackR[i] : (q.ask-g_trackEntry[i])/g_trackR[i];
      double frac=adverseR/SL_R;
      if(frac>=0.5  && !g_reached50[i]){ g_reached50[i]=true; Log("MAE_MILESTONE","50% of SL reached | "+g_trackTag[i]); }
      if(frac>=0.75 && !g_reached75[i]){ g_reached75[i]=true; Log("MAE_MILESTONE","75% of SL reached | "+g_trackTag[i]); }

      datetime now=TimeCurrent();
      double elapsedMin=(double)(now-g_trackLastSample[i])/60.0;
      if(elapsedMin>0)
      {
         if(adverseR<MildZoneR) g_timeMildMin[i]+=elapsedMin;
         else                   g_timeDangerMin[i]+=elapsedMin;
         g_trackLastSample[i]=now;
      }

      if(UseComboExit && !g_comboExited[i] && g_bar3Known[i] && g_bar3OneWay[i] && g_timeDangerMin[i]>=ComboExitDangerMin)
      {
         g_comboExited[i]=true;
         double profit=PositionGetDouble(POSITION_PROFIT);
         if(!EnableLiveOrders)
            Log("COMBO_EXIT_DRY","ticket="+IntegerToString((int)g_trackTicket[i])+" timeDangerMin="+DoubleToString(g_timeDangerMin[i],1)+
                " profit="+DoubleToString(profit,2)+" (would close, EnableLiveOrders=false) | "+g_trackTag[i]);
         else if(trade.PositionClose(g_trackTicket[i]))
            Log("COMBO_EXIT_CLOSE","ticket="+IntegerToString((int)g_trackTicket[i])+" timeDangerMin="+DoubleToString(g_timeDangerMin[i],1)+
                " profit="+DoubleToString(profit,2)+" | "+g_trackTag[i]);
         else
            Log("COMBO_EXIT_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
         continue;
      }

      if(UseTrend10ComboExit && !g_trend10ComboExited[i] && g_trend10Known[i] && g_trend10Oppose[i] && g_timeDangerMin[i]>=ComboExitDangerMin)
      {
         g_trend10ComboExited[i]=true;
         double profit=PositionGetDouble(POSITION_PROFIT);
         if(!EnableLiveOrders)
            Log("TREND10_COMBO_EXIT_DRY","ticket="+IntegerToString((int)g_trackTicket[i])+" timeDangerMin="+DoubleToString(g_timeDangerMin[i],1)+
                " profit="+DoubleToString(profit,2)+" (would close, EnableLiveOrders=false) | "+g_trackTag[i]);
         else if(trade.PositionClose(g_trackTicket[i]))
            Log("TREND10_COMBO_EXIT_CLOSE","ticket="+IntegerToString((int)g_trackTicket[i])+" timeDangerMin="+DoubleToString(g_timeDangerMin[i],1)+
                " profit="+DoubleToString(profit,2)+" | "+g_trackTag[i]);
         else
            Log("TREND10_COMBO_EXIT_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
         continue;
      }

      double favR=(g_trackDir[i]==+1) ? (q.bid-g_trackEntry[i])/g_trackR[i] : (g_trackEntry[i]-q.ask)/g_trackR[i];
      double favFrac=favR/TP_R;
      if(favFrac>=0.5  && !g_reachedFav50[i]){ g_reachedFav50[i]=true; Log("MAE_MILESTONE","50% of TP reached (favorable) | "+g_trackTag[i]); }
      if(favFrac>=0.75 && !g_reachedFav75[i]){ g_reachedFav75[i]=true; Log("MAE_MILESTONE","75% of TP reached (favorable) | "+g_trackTag[i]); }
      if(favFrac>=0.9  && !g_reachedFav90[i]){ g_reachedFav90[i]=true; Log("MAE_MILESTONE","90% of TP reached (favorable) | "+g_trackTag[i]); }

      if(!g_protectTriggered[i] && favR>=ProtectTriggerR)
      {
         g_protectTriggered[i]=true;
         Log("PROTECT_TRIGGER","favR="+DoubleToString(favR,3)+" | "+g_trackTag[i]);
         if(UseProtectStop && (!ProtectStopEuropeOnly || InEuropeSessionKST(TimeCurrent()))
                            && (!ProtectStopAsiaOnly   || InAsiaSessionKST(TimeCurrent())))
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

      if(!g_bandReentered[i] && g_trackBandLevel[i]!=0)
      {
         bool reentered=(g_trackDir[i]==+1) ? (q.bid<g_trackBandLevel[i]) : (q.ask>g_trackBandLevel[i]);
         if(reentered){ g_bandReentered[i]=true; Log("MAE_MILESTONE","band reentry (breakout failed) | "+g_trackTag[i]); }
      }

      if(!g_beTriggered[i] && favFrac>=BreakevenTriggerFrac)
      {
         g_beTriggered[i]=true;
         Log("BE_TRIGGER","favFrac="+DoubleToString(favFrac,3)+" | "+g_trackTag[i]);
         if(UseBreakevenStop)
         {
            double curTP=PositionGetDouble(POSITION_TP);
            double be=NormalizeDouble(g_trackEntry[i],_Digits);
            if(!EnableLiveOrders)
               Log("BE_STOP_MOVE_DRY","would move SL->"+DoubleToString(be,_Digits)+" (EnableLiveOrders=false) | "+g_trackTag[i]);
            else if(trade.PositionModify(g_trackTicket[i],be,curTP))
            {
               g_beMoved[i]=true;
               Log("BE_STOP_MOVED","SL->"+DoubleToString(be,_Digits)+" | "+g_trackTag[i]);
            }
            else
               Log("BE_STOP_MOVE_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
         }
      }
      if(g_beTriggered[i] && !g_beRetraced[i])
      {
         bool retraced=(g_trackDir[i]==+1) ? (q.bid<=g_trackEntry[i]) : (q.ask>=g_trackEntry[i]);
         if(retraced){ g_beRetraced[i]=true; Log("BE_RETRACE","price returned to entry after BE trigger | "+g_trackTag[i]); }
      }
   }
}

string TS(datetime t){ return TimeToString(t,TIME_DATE|TIME_MINUTES|TIME_SECONDS); }

void Log(string event,string detail="")
{
   Print("XAU_M2_BB_LIVE_001_STOCH_v2 | ",event," | ",detail);
   if(f_log!=INVALID_HANDLE){ FileWrite(f_log,TS(TimeCurrent()),event,detail); FileFlush(f_log); }
}

double MinStopDistance()
{
   long stops=0,freeze=0;
   SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL,stops);
   SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL,freeze);
   return (double)MathMax(stops,freeze)*_Point;
}

// -- Korea-time session helpers (server clock -> KST, EU-DST aware) --------
// This broker's server runs 6h behind Korea time during EU summer time
// (DST) and 7h behind during EU winter time -- measured directly (6h
// confirmed live in Sep 2026), not assumed. EU DST: last Sunday of March
// 01:00 UTC-ish to last Sunday of October, approximated here by date only
// (the exact hour of the switchover is immaterial at this granularity).
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

bool InAsiaSessionKST(datetime server_now)
{
   int h=KST_Hour(server_now);
   return (h>=AsiaSessionStartHour && h<AsiaSessionEndHour);
}

// -- Session-transition "danger window" filter (see header for sourcing and
//    the live-data correlation that motivated it) -- blocks new entries
//    (all four tags) during 5 KST windows where session ownership hands
//    off and whipsaw/one-way risk is reportedly concentrated: 09:30-10:30
//    (China open), 14:00-18:00 (Asia close -> Europe open/London surge,
//    kept as two windows to match the source's naming), 20:00-22:30 (US
//    pre-market independent window), 00:30-03:30 (Europe close/reversal
//    hour). -------------------------------------------------------------
bool InDangerWindowKST(datetime server_now)
{
   int offsetHours=IsEUDST(server_now)?6:7;
   MqlDateTime t; TimeToStruct(server_now+offsetHours*3600,t);
   int minOfDay=t.hour*60+t.min;
   int starts[5]={570,840,960,1200,30};
   int ends[5]  ={630,960,1080,1350,210};
   for(int i=0;i<5;i++) if(minOfDay>=starts[i] && minOfDay<ends[i]) return true;
   return false;
}

bool IsFridayKST(datetime server_now)
{
   int offsetHours=IsEUDST(server_now)?6:7;
   MqlDateTime t; TimeToStruct(server_now+offsetHours*3600,t);
   return (t.day_of_week==5); // MQL5 day_of_week: 0=Sunday
}

// -- Friday narrow-window filter (alternative to UseFridayFilter's full-day
//    block): on Friday only, require entries to fall in 10:30-15:00 KST;
//    every other day of the week is unaffected (always returns true). -----
bool InFridayNarrowAllowedWindowKST(datetime server_now)
{
   if(!IsFridayKST(server_now)) return true;
   int offsetHours=IsEUDST(server_now)?6:7;
   MqlDateTime t; TimeToStruct(server_now+offsetHours*3600,t);
   int minOfDay=t.hour*60+t.min;
   return (minOfDay>=630 && minOfDay<900); // 10:30-15:00
}

// -- Allowed-trading-window filter (user-specified, positive allow-list --
//    the inverse framing of UseDangerWindowFilter above): only new entries
//    (all four tags) falling inside one of 3 configurable KST windows are
//    allowed; everything else is blocked. Each window takes a start/end
//    decimal-hour pair (e.g. 10.5=10:30); a window wraps past midnight
//    whenever its end <= its start. Default bounds (REJECTED, see header):
//    10:30-15:00, 16:00-21:00, 22:30-02:50. -------------------------------
bool InWindowKST(int minOfDay,double startHour,double endHour)
{
   int start=(int)MathRound(startHour*60);
   int end=(int)MathRound(endHour*60);
   if(start<=end) return (minOfDay>=start && minOfDay<end);
   return (minOfDay>=start || minOfDay<end); // wraps past midnight
}

bool InAllowedTradingWindowKST(datetime server_now)
{
   int offsetHours=IsEUDST(server_now)?6:7;
   MqlDateTime t; TimeToStruct(server_now+offsetHours*3600,t);
   int minOfDay=t.hour*60+t.min;
   if(InWindowKST(minOfDay,Window1StartHourKST,Window1EndHourKST)) return true;
   if(InWindowKST(minOfDay,Window2StartHourKST,Window2EndHourKST)) return true;
   if(InWindowKST(minOfDay,Window3StartHourKST,Window3EndHourKST)) return true;
   return false;
}

bool InEuropeSessionKST(datetime server_now)
{
   int h=KST_Hour(server_now);
   return (h>=16 && h<22);
}

// -- 매물대 (supply/demand zone) tracking, all in KST calendar-day terms --
int KSTDayIndex(datetime server_now)
{
   int offsetHours=IsEUDST(server_now)?6:7;
   datetime kst=server_now+offsetHours*3600;
   return (int)(kst/86400);
}

// Called once per new signal-timeframe bar with that bar's own high/low --
// rolls today's running high/low into "previous day" at KST midnight,
// captures the Asia/NY session opening-hour boxes the first time each
// day's clock reaches them, and finalizes the previous NY-session-window
// high/low the moment that window closes (so it reads as "어제 미장
// 고가/저가" for the whole of the following session).
void UpdateSupplyZones(datetime sig,double h,double l)
{
   int day=KSTDayIndex(sig);
   int hourKST=KST_Hour(sig);
   int offsetHours=IsEUDST(sig)?6:7;
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

   bool inNYSess=InWindowKST(minOfDay,NYSessionStartHourKST,NYSessionEndHourKST);
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

// Distance from price to the NEAREST enabled zone level, in ATR units
// (999.0 = no enabled zone has a value yet, e.g. before the first Asia/NY
// box of the backtest has formed).
double DistanceToNearestZone(double price,double atr)
{
   if(atr<=0) return 999.0;
   double best=999.0;

   if(UseAsiaBoxZone && g_szAsiaBoxSet)
   {
      best=MathMin(best,MathAbs(price-g_szAsiaHigh)/atr);
      best=MathMin(best,MathAbs(price-g_szAsiaLow)/atr);
   }
   if(UseNYBoxZone && g_szNYBoxSet)
   {
      best=MathMin(best,MathAbs(price-g_szNYHigh)/atr);
      best=MathMin(best,MathAbs(price-g_szNYLow)/atr);
   }
   if(UseTodayHighLowZone)
   {
      best=MathMin(best,MathAbs(price-g_szTodayHigh)/atr);
      best=MathMin(best,MathAbs(price-g_szTodayLow)/atr);
   }
   if(UsePrevDayHighLowZone && g_szHavePrevDay)
   {
      best=MathMin(best,MathAbs(price-g_szPrevDayHigh)/atr);
      best=MathMin(best,MathAbs(price-g_szPrevDayLow)/atr);
   }
   if(UsePrevNYHighLowZone && g_szHavePrevNY)
   {
      best=MathMin(best,MathAbs(price-g_szPrevNYHigh)/atr);
      best=MathMin(best,MathAbs(price-g_szPrevNYLow)/atr);
   }
   return best;
}

bool NearSupplyZone(double price,double atr)
{
   return DistanceToNearestZone(price,atr)<=SupplyZoneATR;
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

// Skips an entry if a strong opposing trend is already established on
// TrendFilterTimeframe: ADX >= ADXThreshold (a trend, by the standard
// convention) AND the dominant DI is pointed against our intended direction.
bool OpposingTrendTooStrong(int dir)
{
   if(!UseTrendFilter) return false;
   double adxBuf[1],plusDI[1],minusDI[1];
   if(CopyBuffer(hADX,0,1,1,adxBuf)!=1) return false;
   if(CopyBuffer(hADX,1,1,1,plusDI)!=1) return false;
   if(CopyBuffer(hADX,2,1,1,minusDI)!=1) return false;
   if(adxBuf[0]<ADXThreshold) return false;
   if(dir==+1 && minusDI[0]>plusDI[0]) return true; // trying to BUY into a strong downtrend
   if(dir==-1 && plusDI[0]>minusDI[0]) return true; // trying to SELL into a strong uptrend
   return false;
}

void CheckTimeStop()
{
   if(MaxMinutesWithoutProgress<=0) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);
      if(tk==0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;

      datetime opened=(datetime)PositionGetInteger(POSITION_TIME);
      double minutesOpen=(double)(TimeCurrent()-opened)/60.0;
      if(minutesOpen<MaxMinutesWithoutProgress) continue;

      double profit=PositionGetDouble(POSITION_PROFIT);
      if(!EnableLiveOrders)
      {
         Log("TIME_STOP_DRY","ticket="+IntegerToString((int)tk)+" minutesOpen="+DoubleToString(minutesOpen,1)+
             " profit="+DoubleToString(profit,2)+" (would close, EnableLiveOrders=false)");
         continue;
      }
      if(trade.PositionClose(tk))
         Log("TIME_STOP_CLOSE","ticket="+IntegerToString((int)tk)+" minutesOpen="+DoubleToString(minutesOpen,1)+
             " profit="+DoubleToString(profit,2));
      else
         Log("TIME_STOP_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
   }
}

// Force-closes a position once it has spent DangerTimeStopMin cumulative
// minutes with adverse excursion >= MildZoneR (see timeDangerMin header
// note) -- distinct from CheckTimeStop/MaxMinutesWithoutProgress, which
// fires on TOTAL hold time regardless of how favorable/adverse price was.
void CheckDangerTimeStop()
{
   if(!UseDangerTimeStop) return;
   for(int i=0;i<TRACK_SLOTS;i++)
   {
      if(g_trackTicket[i]==0) continue;
      if(g_timeDangerMin[i]<DangerTimeStopMin) continue;
      if(!PositionSelectByTicket(g_trackTicket[i])) continue; // already closed

      double profit=PositionGetDouble(POSITION_PROFIT);
      if(!EnableLiveOrders)
      {
         Log("DANGER_TIME_STOP_DRY","ticket="+IntegerToString((int)g_trackTicket[i])+
             " timeDangerMin="+DoubleToString(g_timeDangerMin[i],1)+" profit="+DoubleToString(profit,2)+
             " (would close, EnableLiveOrders=false) | "+g_trackTag[i]);
         continue;
      }
      if(trade.PositionClose(g_trackTicket[i]))
         Log("DANGER_TIME_STOP_CLOSE","ticket="+IntegerToString((int)g_trackTicket[i])+
             " timeDangerMin="+DoubleToString(g_timeDangerMin[i],1)+" profit="+DoubleToString(profit,2)+
             " | "+g_trackTag[i]);
      else
         Log("DANGER_TIME_STOP_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
   }
}

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

void OpenTrade(int dir,double R,string tag)
{
   if(HasOurPosition()){ Log("ENTRY_SKIPPED","own-Magic position already exists"); return; }
   if(OpposingTrendTooStrong(dir)){ Log("ENTRY_SKIPPED","opposing trend too strong (ADX filter) | "+tag); return; }
   if(TimeCurrent()<g_breakerActiveUntil)
   {
      Log(UseCircuitBreaker?"CIRCUIT_BREAKER_SKIP":"CIRCUIT_BREAKER_WOULD_SKIP",
          "until="+TS(g_breakerActiveUntil)+" | "+tag);
      if(UseCircuitBreaker) return;
   }
   tag=TFPrefix()+tag;

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

void CheckNewM2Bar()
{
   datetime t=iTime(_Symbol,Timeframe,0);
   if(t==0 || t==last_m2_bar) return;
   last_m2_bar=t;

   double o=iOpen(_Symbol,Timeframe,1),h=iHigh(_Symbol,Timeframe,1);
   double l=iLow(_Symbol,Timeframe,1),c=iClose(_Symbol,Timeframe,1);
   datetime sig=iTime(_Symbol,Timeframe,1);
   if(sig==0){ Log("BAR_DATA_FAIL","iTime(1) returned 0"); return; }

   UpdateSupplyZones(sig,h,l);

   for(int i=0;i<TRACK_SLOTS;i++)
   {
      if(!g_waitingFirstBar[i]) continue;
      // "one-way against": price never moved favorably by even 1 point during
      // this bar -- for a BUY, the bar's high never exceeded the entry price;
      // for a SELL, the bar's low never went below it. Uses h/l (the bar's
      // extremes), not open/close, since a bar can close red while still
      // having ticked favorably first.
      g_firstBarOneWay[i]=(g_trackDir[i]==+1) ? (h<=g_trackEntry[i]) : (l>=g_trackEntry[i]);
      g_firstBarKnown[i]=true;
      g_waitingFirstBar[i]=false;

      if(UseFirstBarExit && g_firstBarOneWay[i] &&
         (StringFind(g_trackTag[i],"TREND_BULL")>=0 || StringFind(g_trackTag[i],"FADE_BEAR_OS")>=0) &&
         PositionSelectByTicket(g_trackTicket[i]))
      {
         double profit=PositionGetDouble(POSITION_PROFIT);
         if(!EnableLiveOrders)
            Log("FIRST_BAR_EXIT_DRY","ticket="+IntegerToString((int)g_trackTicket[i])+
                " profit="+DoubleToString(profit,2)+" (would close, EnableLiveOrders=false) | "+g_trackTag[i]);
         else if(trade.PositionClose(g_trackTicket[i]))
            Log("FIRST_BAR_EXIT_CLOSE","ticket="+IntegerToString((int)g_trackTicket[i])+
                " profit="+DoubleToString(profit,2)+" | "+g_trackTag[i]);
         else
            Log("FIRST_BAR_EXIT_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
      }
   }

   for(int i=0;i<TRACK_SLOTS;i++)
   {
      if(!g_waitingNextBar[i]) continue;
      // Candle color of this just-closed bar, independent of entry price:
      // for a BUY, opposing = bearish candle (c<o); for a SELL, opposing =
      // bullish candle (c>o).
      g_nextBarOppose[i]=(g_trackDir[i]==+1) ? (c<o) : (c>o);
      g_nextBarKnown[i]=true;
      g_waitingNextBar[i]=false;

      if(UseNextBarOpposeExit && g_nextBarOppose[i] && PositionSelectByTicket(g_trackTicket[i]))
      {
         double profit=PositionGetDouble(POSITION_PROFIT);
         if(!EnableLiveOrders)
            Log("NEXT_BAR_OPPOSE_EXIT_DRY","ticket="+IntegerToString((int)g_trackTicket[i])+
                " profit="+DoubleToString(profit,2)+" (would close, EnableLiveOrders=false) | "+g_trackTag[i]);
         else if(trade.PositionClose(g_trackTicket[i]))
            Log("NEXT_BAR_OPPOSE_EXIT_CLOSE","ticket="+IntegerToString((int)g_trackTicket[i])+
                " profit="+DoubleToString(profit,2)+" | "+g_trackTag[i]);
         else
            Log("NEXT_BAR_OPPOSE_EXIT_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
      }

      // Arm the trend10 window now that the entry bar itself is resolved --
      // accumulation starts on the NEXT call (g_trend10JustArmed skips this
      // one), so the entry bar is never counted twice.
      g_waitingTrend10[i]=true; g_trend10JustArmed[i]=true;
      g_trend10Count[i]=0; g_trend10Sum[i]=0;
   }

   for(int i=0;i<TRACK_SLOTS;i++)
   {
      if(!g_waitingTrend10[i]) continue;
      if(g_trend10JustArmed[i]){ g_trend10JustArmed[i]=false; continue; } // skip entry bar, already covered by nextBarOppose

      g_trend10Sum[i]+=(c-o);
      g_trend10Count[i]++;
      if(g_trend10Count[i]>=Trend10LookbackBars)
      {
         double avgBody=g_trend10Sum[i]/Trend10LookbackBars;
         g_trend10Oppose[i]=(g_trackDir[i]==+1) ? (avgBody<0) : (avgBody>0);
         g_trend10Known[i]=true;
         g_waitingTrend10[i]=false;

         if(UseEntryTrend10OpposeExit && g_nextBarOppose[i] && g_trend10Oppose[i] && PositionSelectByTicket(g_trackTicket[i]))
         {
            double profit=PositionGetDouble(POSITION_PROFIT);
            if(!EnableLiveOrders)
               Log("ENTRY_TREND10_EXIT_DRY","ticket="+IntegerToString((int)g_trackTicket[i])+
                   " profit="+DoubleToString(profit,2)+" (would close, EnableLiveOrders=false) | "+g_trackTag[i]);
            else if(trade.PositionClose(g_trackTicket[i]))
               Log("ENTRY_TREND10_EXIT_CLOSE","ticket="+IntegerToString((int)g_trackTicket[i])+
                   " profit="+DoubleToString(profit,2)+" | "+g_trackTag[i]);
            else
               Log("ENTRY_TREND10_EXIT_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
         }
      }
   }

   for(int i=0;i<TRACK_SLOTS;i++)
   {
      if(!g_waitingBar3[i]) continue;
      if(g_bar3Count[i]==0) g_bar3Extreme[i]=(g_trackDir[i]==+1 ? h : l);
      else g_bar3Extreme[i]=(g_trackDir[i]==+1 ? MathMax(g_bar3Extreme[i],h) : MathMin(g_bar3Extreme[i],l));
      g_bar3Count[i]++;
      if(g_bar3Count[i]>=3)
      {
         g_bar3OneWay[i]=(g_trackDir[i]==+1) ? (g_bar3Extreme[i]<=g_trackEntry[i]) : (g_bar3Extreme[i]>=g_trackEntry[i]);
         g_bar3Known[i]=true;
         g_waitingBar3[i]=false;

         if(UseThreeBarExit && g_bar3OneWay[i] && PositionSelectByTicket(g_trackTicket[i]))
         {
            double profit=PositionGetDouble(POSITION_PROFIT);
            if(!EnableLiveOrders)
               Log("THREE_BAR_EXIT_DRY","ticket="+IntegerToString((int)g_trackTicket[i])+
                   " profit="+DoubleToString(profit,2)+" (would close, EnableLiveOrders=false) | "+g_trackTag[i]);
            else if(trade.PositionClose(g_trackTicket[i]))
               Log("THREE_BAR_EXIT_CLOSE","ticket="+IntegerToString((int)g_trackTicket[i])+
                   " profit="+DoubleToString(profit,2)+" | "+g_trackTag[i]);
            else
               Log("THREE_BAR_EXIT_FAIL",IntegerToString((int)trade.ResultRetcode())+" | "+trade.ResultRetcodeDescription());
         }
      }
   }

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

   int sigdir=0;
   if(c>o && h>=up20[0] && h>=up4[0]) sigdir=+1;      // bull (up) signal candle
   else if(c<o && l<=lo20[0] && l<=lo4[0]) sigdir=-1; // bear (down) signal candle
   if(sigdir==0) return;

   if(UseTradingWindowFilter && !InAllowedTradingWindowKST(sig))
   { Log("SIGNAL_SKIPPED","Entry blocked by UseTradingWindowFilter (outside 10:30-15:00/16:00-21:00/22:30-02:50 KST)"); return; }
   if(UseDangerWindowFilter && InDangerWindowKST(sig))
   { Log("SIGNAL_SKIPPED","Entry blocked by UseDangerWindowFilter (session-transition danger window)"); return; }
   if(UseFridayFilter && IsFridayKST(sig) && KST_Hour(sig)>=FridayFilterFromHourKST)
   { Log("SIGNAL_SKIPPED","Entry blocked by UseFridayFilter (Friday, hour>="+IntegerToString(FridayFilterFromHourKST)+" KST)"); return; }
   if(UseFridayNarrowWindow && !InFridayNarrowAllowedWindowKST(sig))
   { Log("SIGNAL_SKIPPED","Entry blocked by UseFridayNarrowWindow (Friday, outside 10:30-15:00 KST)"); return; }

   // BODY vs WICK touch (diagnostic): the entry condition above only requires
   // the candle's high/low (wick) to reach BB20 -- this checks whether the
   // CLOSE (body) also closed beyond BB20, i.e. a "real" break vs a rejection
   // wick that poked through and closed back inside.
   bool bodyTouch=(sigdir==+1) ? (c>=up20[0]) : (c<=lo20[0]);

   // Rejection-wick length (diagnostic): the signal candle's wick on the
   // side OPPOSITE its close, in ATR units -- tests whether a long
   // rejection wick on the breakout candle itself predicts a reversal.
   double wickLenATR=999.0;
   {
      double tail=(sigdir==+1) ? (h-MathMax(o,c)) : (MathMin(o,c)-l);
      double atrDiag[1];
      if(CopyBuffer(hATR_Sig,0,1,1,atrDiag)==1 && atrDiag[0]>0) wickLenATR=tail/atrDiag[0];
   }

   // Prior-5-candle-same-direction (diagnostic): were the 5 candles right
   // before the signal candle (shifts 2-6) ALL in the breakout's own
   // direction (all bullish for sigdir=+1, all bearish for sigdir=-1)?
   bool prior5Same=true;
   for(int k=2;k<=6;k++)
   {
      double po=iOpen(_Symbol,Timeframe,k), pc=iClose(_Symbol,Timeframe,k);
      bool thisBarMatches=(sigdir==+1) ? (pc>po) : (pc<po);
      if(!thisBarMatches){ prior5Same=false; break; }
   }

   // Pre-signal ADX rise (diagnostic, BEAR signal candles only): candle "1"
   // (furthest of the prior 5, shift 6) vs candle "5" (closest, shift 2) --
   // adxRiseDiff = ADX[shift2] - ADX[shift6], on the M2-timeframe ADX.
   double adxRiseDiff=0; bool adxRiseKnown=false;
   if(sigdir==-1)
   {
      double adxFar[1],adxNear[1];
      if(CopyBuffer(hADXM2,0,6,1,adxFar)==1 && CopyBuffer(hADXM2,0,2,1,adxNear)==1)
      {
         adxRiseDiff=adxNear[0]-adxFar[0];
         adxRiseKnown=true;
      }
   }

   // Kaufman Efficiency Ratio over the last EfficiencyRatioPeriod closed bars
   // (shift 1 .. shift 1+EfficiencyRatioPeriod) on the main Timeframe.
   double effRatio=0; bool effRatioKnown=false;
   {
      double closes[];
      ArraySetAsSeries(closes,true);
      int got=CopyClose(_Symbol,Timeframe,1,EfficiencyRatioPeriod+1,closes);
      if(got==EfficiencyRatioPeriod+1)
      {
         double netMove=MathAbs(closes[0]-closes[EfficiencyRatioPeriod]);
         double sumMove=0;
         for(int k=0;k<EfficiencyRatioPeriod;k++) sumMove+=MathAbs(closes[k]-closes[k+1]);
         if(sumMove>0){ effRatio=netMove/sumMove; effRatioKnown=true; }
      }
   }

   // DI (이격도): signal candle close vs its own SMA(DIPeriod), as a percent.
   double di=0; bool diKnown=false;
   {
      double maBuf[1];
      if(CopyBuffer(hMA_DI,0,1,1,maBuf)==1 && maBuf[0]>0)
      {
         di=c/maBuf[0]*100.0;
         diKnown=true;
      }
   }

   // Higher-timeframe BB breakout alignment: is the most recently closed
   // HigherTFForTrend candle ITSELF a BB20/BB4 breakout in the same
   // direction as this M2 signal?
   bool htfAligned=false; bool htfKnown=false;
   {
      double h_o=iOpen(_Symbol,HigherTFForTrend,1), h_h=iHigh(_Symbol,HigherTFForTrend,1);
      double h_l=iLow(_Symbol,HigherTFForTrend,1),  h_c=iClose(_Symbol,HigherTFForTrend,1);
      double hup20[1],hlo20[1],hup4[1],hlo4[1];
      if(h_o!=0 && CopyBuffer(hBB20_HTF,1,1,1,hup20)==1 && CopyBuffer(hBB20_HTF,2,1,1,hlo20)==1 &&
         CopyBuffer(hBB4_HTF,1,1,1,hup4)==1 && CopyBuffer(hBB4_HTF,2,1,1,hlo4)==1)
      {
         htfKnown=true;
         if(sigdir==+1) htfAligned=(h_c>h_o && h_h>=hup20[0] && h_h>=hup4[0]);
         else           htfAligned=(h_c<h_o && h_l<=hlo20[0] && h_l<=hlo4[0]);
      }
   }

   // ATR expansion ratio: current HigherTFForTrend ATR vs its own average
   // over the last ATRAvgPeriod bars.
   double atrExpansion=0; bool atrKnown=false;
   {
      double atrBuf[];
      ArraySetAsSeries(atrBuf,true);
      int got=CopyBuffer(hATR_HTF,0,1,ATRAvgPeriod,atrBuf);
      if(got==ATRAvgPeriod)
      {
         double curATR=atrBuf[0];
         double sumATR=0;
         for(int k=0;k<ATRAvgPeriod;k++) sumATR+=atrBuf[k];
         double avgATR=sumATR/ATRAvgPeriod;
         if(avgATR>0){ atrExpansion=curATR/avgATR; atrKnown=true; }
      }
   }

   double R=MathAbs(c-o);
   double minR=MathMax(_Point,MinR_Points*_Point);
   if(R<=minR){ Log("SIGNAL_SKIPPED","R too small"); return; }

   CheckOppositeSignal(sigdir);
   CheckDICrossExit();
   CheckStochRolloverExit();

   // -- MA-slope hypothesis (diagnostic only, no trading effect) --------------
   // See header comment for the exact pseudo-angle definition and rationale.
   // Also computes the same pseudo-angle at fixed 2/3-bar lookbacks alongside
   // the configurable SlopeLookbackBars one, so a single backtest can compare
   // which lookback best separates eventual win/loss without re-running --
   // the user's own chart-watching suggests a short lookback (2-3 bars right
   // at the signal candle) may match what they see as "flat" better than a
   // longer one.
   double slopeDeg=0; bool slopeKnown=false; // hoisted so the TREND_BULL slope filter below can read it
   double maNow[1];
   int rNow=CopyBuffer(hBB20,0,1,1,maNow);
   if(rNow==1)
   {
      double maPrev2[1],maPrev3[1],maPrev5[1],maPrevCfg[1];
      int r2=CopyBuffer(hBB20,0,1+2,1,maPrev2);
      int r3=CopyBuffer(hBB20,0,1+3,1,maPrev3);
      int r5=CopyBuffer(hBB20,0,1+5,1,maPrev5);
      int rCfg=CopyBuffer(hBB20,0,1+SlopeLookbackBars,1,maPrevCfg);
      double deg2=(r2==1) ? MathArctan((maNow[0]-maPrev2[0])/(2*R))*180.0/M_PI : 0;
      double deg3=(r3==1) ? MathArctan((maNow[0]-maPrev3[0])/(3*R))*180.0/M_PI : 0;
      double deg5=(r5==1) ? MathArctan((maNow[0]-maPrev5[0])/(5*R))*180.0/M_PI : 0;

      if(rCfg==1)
      {
         double slopeNorm=(maNow[0]-maPrevCfg[0])/(SlopeLookbackBars*R);
         slopeDeg=MathArctan(slopeNorm)*180.0/M_PI;
         slopeKnown=true;
         bool   flat=(MathAbs(slopeDeg)<=SlopeThresholdDeg);
         int    slopeDir=flat ? -sigdir : sigdir; // FLAT=fade the breakout, STEEP=follow it
         string slopeClass=flat?"FLAT":"STEEP";
         string slopeTag=(sigdir==1?"BULL":"BEAR")+string("_")+slopeClass;
         Log("SLOPE_CALC","sigdir="+(sigdir==1?"BULL":"BEAR")+" slopeDeg="+DoubleToString(slopeDeg,2)+
             " class="+slopeClass+" hypDir="+(slopeDir==1?"BUY":"SELL")+
             " deg2="+DoubleToString(deg2,2)+" deg3="+DoubleToString(deg3,2)+" deg5="+DoubleToString(deg5,2));
         MqlTick sq; if(SymbolInfoTick(_Symbol,sq)) StartSlopeSim((sq.bid+sq.ask)/2.0,R,slopeDir,slopeDeg,slopeTag);
      }
      else
         Log("SLOPE_CALC_FAIL","BB20 basis (configured lookback) CopyBuffer failed");
   }
   else
      Log("SLOPE_CALC_FAIL","BB20 basis (now) CopyBuffer failed");

   double stochK=0; double oscOB=StochOverbought, oscOS=StochOversold; string oscTagLetter="K";
   if(!IgnoreStochastic)
   {
      if(UseRSIInsteadOfStoch)
      {
         double rbuf[1];
         if(CopyBuffer(hRSI,0,1,1,rbuf)!=1){ Log("RSI_FAIL","no RSI value"); return; }
         stochK=rbuf[0]; oscOB=RSIOverbought; oscOS=RSIOversold; oscTagLetter="R";
      }
      else
      {
         double kbuf[1];
         if(CopyBuffer(hStoch,0,1,1,kbuf)!=1){ Log("STOCH_FAIL","no stochastic value"); return; }
         stochK=kbuf[0];
      }
   }

   int dir=0; string tag="";
   if(IgnoreStochastic)
   {
      // UNTESTED -- always trades the breakout's own direction (trend-following),
      // bypassing the Stochastic OB/OS branch (and AllowSellFade, which only
      // applies to that branch) entirely. Session filters on TREND_BEAR still
      // apply since those are a separate, orthogonal finding.
      if(sigdir==+1) { dir=+1; tag="TREND_BULL_NOSTOCH"; }
      else
      {
         if(InAsiaSessionKST(sig))
         {
            if(ReverseTrendBearAsiaSession){ dir=+1; tag="TREND_BEAR_REV_ASIA_NOSTOCH"; }
            else if(SkipTrendBearAsiaSession)
            { Log("SIGNAL_SKIPPED","TREND-BEAR disabled during Asia session (06-16 KST) by SkipTrendBearAsiaSession=true"); return; }
            else { dir=-1; tag="TREND_BEAR_NOSTOCH"; }
         }
         else { dir=-1; tag="TREND_BEAR_NOSTOCH"; }
      }
   }
   else if(sigdir==+1) // bull signal candle
   {
      if(stochK>=oscOB)
      {
         if(!AllowSellFade){ Log("SIGNAL_SKIPPED","SELL-fade disabled by AllowSellFade=false"); return; }
         dir=-1; tag="STOCH_FADE_BULL_OB";
      }
      else
      {
         if(UseSlopeFilterTrendBull && slopeKnown && slopeDeg<-SlopeFilterTrendBullDeg)
         { Log("SIGNAL_SKIPPED","TREND_BULL blocked by opposing MA slope (UseSlopeFilterTrendBull) slopeDeg="+DoubleToString(slopeDeg,2)); return; }
         dir=+1; tag="STOCH_TREND_BULL";
      }
   }
   else // bear signal candle
   {
      if(stochK<oscOS)
      {
         if(!bodyTouch && SkipFadeBearOSWickTouch)
         { Log("SIGNAL_SKIPPED","FADE_BEAR_OS disabled on WICK-only touch by SkipFadeBearOSWickTouch=true"); return; }
         dir=+1; tag="STOCH_FADE_BEAR_OS";
      }
      else
      {
         if(InAsiaSessionKST(sig))
         {
            if(ReverseTrendBearAsiaSession){ dir=+1; tag="STOCH_TREND_BEAR_REV_ASIA"; }
            else if(SkipTrendBearAsiaSession)
            { Log("SIGNAL_SKIPPED","TREND-BEAR disabled during Asia session (06-16 KST) by SkipTrendBearAsiaSession=true"); return; }
            else { dir=-1; tag="STOCH_TREND_BEAR"; }
         }
         else { dir=-1; tag="STOCH_TREND_BEAR"; }
      }
   }

   // Band-reentry tracking only makes sense for trend-following trades (dir
   // matches the breakout direction) -- for a fade trade, price returning
   // toward/across that same band is the EXPECTED favorable direction, not
   // a failure signal, so disable the check there (0 = disabled).
   g_lastBandLevel=(dir==sigdir) ? (sigdir==+1 ? up20[0] : lo20[0]) : 0;
   g_lastBodyTouch=bodyTouch;
   {
      double atrSigDiag[1];
      g_lastZoneDistATR=(CopyBuffer(hATR_Sig,0,1,1,atrSigDiag)==1) ? DistanceToNearestZone(c,atrSigDiag[0]) : 999.0;
   }
   // TREND-only 매물대 block (CONFIRMED finding, see header): a supply zone
   // sitting right at a TREND_BULL/BEAR breakout close acts as resistance
   // against the continuation -- zoneDistATR 0-0.3 was the ONLY bucket with
   // negative NET for TREND trades (n=216, WR 88.89%, PF 0.834), while every
   // FADE bucket (same proximity included) stayed solidly profitable, since
   // for FADE the zone holding is the expected win, not an obstacle. Scoped
   // to dir==sigdir (continuation) only -- FADE entries are never blocked.
   if(UseSupplyZoneFilter && dir==sigdir && g_lastZoneDistATR<=SupplyZoneATR)
   {
      Log("SIGNAL_SKIPPED","TREND entry blocked by UseSupplyZoneFilter: zoneDistATR="+
          DoubleToString(g_lastZoneDistATR,3)+" <= "+DoubleToString(SupplyZoneATR,2));
      return;
   }
   g_lastPrior5Same=prior5Same;
   g_lastWickLenATR=wickLenATR;
   g_lastDI=di; g_lastDIKnown=diKnown;
   g_lastAdxRiseDiff=adxRiseDiff; g_lastAdxRiseKnown=adxRiseKnown;
   g_lastEffRatio=effRatio; g_lastEffRatioKnown=effRatioKnown;
   g_lastHtfAligned=htfAligned; g_lastHtfKnown=htfKnown;
   g_lastAtrExpansion=atrExpansion; g_lastAtrKnown=atrKnown;

   if(!IgnoreStochastic) tag=tag+oscTagLetter+IntegerToString((int)MathRound(stochK)); // comment length: keep short, MT5 caps at 31 chars

   Log("SIGNAL",(sigdir==1?"BULL":"BEAR")+" candle | stochK="+DoubleToString(stochK,2)+
       " | R="+DoubleToString(R,_Digits)+" | touch="+(bodyTouch?"BODY":"WICK")+
       " | decided dir="+(dir==1?"BUY":"SELL")+" | "+tag);
   OpenTrade(dir,R,tag);
}

int OnInit()
{
   hBB20=iBands(_Symbol,Timeframe,20,0,2.0,PRICE_CLOSE);
   hBB4 =iBands(_Symbol,Timeframe,4,0,4.0,PRICE_OPEN);
   hStoch=iStochastic(_Symbol,Timeframe,StochK_Period,StochD_Period,StochSlowing,MODE_LWMA,STO_LOWHIGH);
   hADX=iADX(_Symbol,TrendFilterTimeframe,ADXPeriod);
   hADXM2=iADX(_Symbol,Timeframe,ADXPeriod);
   hBB20_HTF=iBands(_Symbol,HigherTFForTrend,20,0,2.0,PRICE_CLOSE);
   hBB4_HTF =iBands(_Symbol,HigherTFForTrend,4,0,4.0,PRICE_OPEN);
   hATR_HTF =iATR(_Symbol,HigherTFForTrend,ATRPeriod);
   hATR_Sig =iATR(_Symbol,Timeframe,ATRPeriod);
   hMA_DI   =iMA(_Symbol,Timeframe,DIPeriod,0,MODE_SMA,PRICE_CLOSE);
   hRSI     =iRSI(_Symbol,Timeframe,RSIPeriod,PRICE_CLOSE);
   if(hBB20==INVALID_HANDLE || hBB4==INVALID_HANDLE || hStoch==INVALID_HANDLE || hADX==INVALID_HANDLE || hADXM2==INVALID_HANDLE ||
      hBB20_HTF==INVALID_HANDLE || hBB4_HTF==INVALID_HANDLE || hATR_HTF==INVALID_HANDLE || hATR_Sig==INVALID_HANDLE || hMA_DI==INVALID_HANDLE ||
      hRSI==INVALID_HANDLE) return INIT_FAILED;

   f_log=FileOpen("XAU_M2_BB_LIVE_001_STOCH_v2_LOG.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
   if(f_log!=INVALID_HANDLE)
   {
      FileSeek(f_log,0,SEEK_END);
      if(FileTell(f_log)==0) FileWrite(f_log,"TIME","EVENT","DETAIL");
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(MaxDeviationPts);
   trade.SetTypeFillingBySymbol(_Symbol);

   Log("START",string("TF=")+EnumToString(Timeframe)+" | Stoch("+IntegerToString(StochK_Period)+","+IntegerToString(StochD_Period)+
       ","+IntegerToString(StochSlowing)+") | OB="+DoubleToString(StochOverbought,1)+
       " OS="+DoubleToString(StochOversold,1)+" | SL_R="+DoubleToString(SL_R,2)+
       " | TP_R="+DoubleToString(TP_R,2)+" | MinR_Points="+DoubleToString(MinR_Points,1)+
       " | AllowSellFade="+(AllowSellFade?"true":"false")+
       " | SkipTrendBearAsiaSession="+(SkipTrendBearAsiaSession?"true":"false")+
       " | AsiaWindow="+IntegerToString(AsiaSessionStartHour)+"-"+IntegerToString(AsiaSessionEndHour)+"KST"+
       " | ReverseTrendBearAsiaSession="+(ReverseTrendBearAsiaSession?"true":"false")+
       " | MaxMinutesWithoutProgress="+IntegerToString(MaxMinutesWithoutProgress)+
       " | UseTradingWindowFilter="+(UseTradingWindowFilter?"true":"false")+
       " W1="+DoubleToString(Window1StartHourKST,2)+"-"+DoubleToString(Window1EndHourKST,2)+
       " W2="+DoubleToString(Window2StartHourKST,2)+"-"+DoubleToString(Window2EndHourKST,2)+
       " W3="+DoubleToString(Window3StartHourKST,2)+"-"+DoubleToString(Window3EndHourKST,2)+
       " | UseDangerWindowFilter="+(UseDangerWindowFilter?"true":"false")+
       " | UseFridayFilter="+(UseFridayFilter?"true":"false")+" FridayFilterFromHourKST="+IntegerToString(FridayFilterFromHourKST)+
       " | UseFridayNarrowWindow="+(UseFridayNarrowWindow?"true":"false")+
       " | UseTrendFilter="+(UseTrendFilter?"true":"false")+
       " | TrendFilterTF="+EnumToString(TrendFilterTimeframe)+" ADXPeriod="+IntegerToString(ADXPeriod)+
       " ADXThreshold="+DoubleToString(ADXThreshold,1)+
       " | UseOppositeSignalExit="+(UseOppositeSignalExit?"true":"false")+
       " | SlopeLookbackBars="+IntegerToString(SlopeLookbackBars)+" SlopeThresholdDeg="+DoubleToString(SlopeThresholdDeg,1)+
       " SlopeSimTargetR="+DoubleToString(SlopeSimTargetR,2)+" SlopeSimExpiryHours="+DoubleToString(SlopeSimExpiryHours,1)+
       " | SlopeFilterTrendBullDeg="+DoubleToString(SlopeFilterTrendBullDeg,1)+" UseSlopeFilterTrendBull="+(UseSlopeFilterTrendBull?"true":"false")+
       " | EfficiencyRatioPeriod="+IntegerToString(EfficiencyRatioPeriod)+
       " | HigherTFForTrend="+EnumToString(HigherTFForTrend)+" ATRPeriod="+IntegerToString(ATRPeriod)+" ATRAvgPeriod="+IntegerToString(ATRAvgPeriod)+
       " | IgnoreStochastic="+(IgnoreStochastic?"true":"false")+
       " | UseRSIInsteadOfStoch="+(UseRSIInsteadOfStoch?"true":"false")+" RSIPeriod="+IntegerToString(RSIPeriod)+
       " RSIOverbought="+DoubleToString(RSIOverbought,1)+" RSIOversold="+DoubleToString(RSIOversold,1)+
       " | CircuitBreakerLossCount="+IntegerToString(CircuitBreakerLossCount)+
       " CircuitBreakerCooldownHours="+DoubleToString(CircuitBreakerCooldownHours,1)+
       " UseCircuitBreaker="+(UseCircuitBreaker?"true":"false")+
       " | BreakevenTriggerFrac="+DoubleToString(BreakevenTriggerFrac,2)+
       " UseBreakevenStop="+(UseBreakevenStop?"true":"false")+
       " | ProtectTriggerR="+DoubleToString(ProtectTriggerR,2)+" ProtectR="+DoubleToString(ProtectR,2)+
       " UseProtectStop="+(UseProtectStop?"true":"false")+" ProtectStopEuropeOnly="+(ProtectStopEuropeOnly?"true":"false")+
       " ProtectStopAsiaOnly="+(ProtectStopAsiaOnly?"true":"false")+
       " | MildZoneR="+DoubleToString(MildZoneR,2)+" DangerTimeStopMin="+DoubleToString(DangerTimeStopMin,1)+
       " UseDangerTimeStop="+(UseDangerTimeStop?"true":"false")+
       " | UseThreeBarExit="+(UseThreeBarExit?"true":"false")+
       " | UseFirstBarExit="+(UseFirstBarExit?"true":"false")+
       " | UseNextBarOpposeExit="+(UseNextBarOpposeExit?"true":"false")+
       " | Trend10LookbackBars="+IntegerToString(Trend10LookbackBars)+" UseEntryTrend10OpposeExit="+(UseEntryTrend10OpposeExit?"true":"false")+
       " | ComboExitDangerMin="+DoubleToString(ComboExitDangerMin,1)+" UseComboExit="+(UseComboExit?"true":"false")+
       " UseTrend10ComboExit="+(UseTrend10ComboExit?"true":"false")+
       " | SkipFadeBearOSWickTouch="+(SkipFadeBearOSWickTouch?"true":"false")+
       " | UseSupplyZoneFilter="+(UseSupplyZoneFilter?"true":"false")+" SupplyZoneATR="+DoubleToString(SupplyZoneATR,2)+
       " UseAsiaBoxZone="+(UseAsiaBoxZone?"true":"false")+" AsiaOpenHourKST="+IntegerToString(AsiaOpenHourKST)+
       " UseNYBoxZone="+(UseNYBoxZone?"true":"false")+" NYOpenHourKST="+DoubleToString(NYOpenHourKST,2)+
       " UseTodayHighLowZone="+(UseTodayHighLowZone?"true":"false")+" UsePrevDayHighLowZone="+(UsePrevDayHighLowZone?"true":"false")+
       " UsePrevNYHighLowZone="+(UsePrevNYHighLowZone?"true":"false")+
       " NYSessionWindow="+DoubleToString(NYSessionStartHourKST,2)+"-"+DoubleToString(NYSessionEndHourKST,2)+"KST"+
       " | DIPeriod="+IntegerToString(DIPeriod)+
       " | Lots="+DoubleToString(Lots,2)+" | Magic="+IntegerToString((int)MagicNumber)+
       " | orders="+(EnableLiveOrders?"ENABLED":"DRY"));
   Log("NOTE","DI diagnostic: DI=signal close/SMA(DIPeriod)*100, logged on every trade (MAE_OUTCOME). Diagnostic only, does not block entries.");
   Log("NOTE","DI-cross-exit diagnostic: diBaseAgainst/diCrossSeen/diCrossR in MAE_OUTCOME track +DI/-DI (hADXM2) reversals against the trade's direction, and the R-multiple price was at when that first happened. Diagnostic only, does not close anything.");
   Log("NOTE","wickLenATR diagnostic: logs the signal candle's own rejection-wick length (opposite side from its close) in ATR units, on every trade (MAE_OUTCOME). Diagnostic only, does not block entries.");
   Log("NOTE","Stochastic rollover-exit diagnostic (TREND trades only): stochPeaked/stochRolloverSeen/stochRolloverR in MAE_OUTCOME track whether stochK reached the favorable extreme then rolled back out of it, and the R-multiple price was at when that first happened. Diagnostic only, does not close anything.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(f_log!=INVALID_HANDLE){ FileFlush(f_log); FileClose(f_log); }
   if(hBB20!=INVALID_HANDLE) IndicatorRelease(hBB20);
   if(hBB4!=INVALID_HANDLE)  IndicatorRelease(hBB4);
   if(hStoch!=INVALID_HANDLE) IndicatorRelease(hStoch);
   if(hADX!=INVALID_HANDLE) IndicatorRelease(hADX);
   if(hADXM2!=INVALID_HANDLE) IndicatorRelease(hADXM2);
   if(hBB20_HTF!=INVALID_HANDLE) IndicatorRelease(hBB20_HTF);
   if(hBB4_HTF!=INVALID_HANDLE) IndicatorRelease(hBB4_HTF);
   if(hATR_HTF!=INVALID_HANDLE) IndicatorRelease(hATR_HTF);
   if(hATR_Sig!=INVALID_HANDLE) IndicatorRelease(hATR_Sig);
   if(hMA_DI!=INVALID_HANDLE) IndicatorRelease(hMA_DI);
   if(hRSI!=INVALID_HANDLE) IndicatorRelease(hRSI);
}

void OnTick()
{
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;
   CheckMAEProgress();
   CheckDangerTimeStop();
   CheckSlopeSims();
   CheckTimeStop();
   CheckNewM2Bar();
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
   if(i<0) return; // not a ticket we're tracking (or already logged)

   // Includes DEAL_COMMISSION -- an earlier version omitted it, so a CSV-summed
   // NET was off from the official xlsx by ~$1.50/trade (the round-turn
   // commission on a 0.1-lot XAUUSD position on this broker).
   double profit=HistoryDealGetDouble(trans.deal,DEAL_PROFIT)+HistoryDealGetDouble(trans.deal,DEAL_SWAP)+
                 HistoryDealGetDouble(trans.deal,DEAL_COMMISSION);
   string outcome=(profit>0?"WIN":"LOSS");
   string firstBarStr=(!g_firstBarKnown[i] ? "unknown" : (g_firstBarOneWay[i]?"true":"false"));
   string nextBarStr=(!g_nextBarKnown[i] ? "unknown" : (g_nextBarOppose[i]?"true":"false"));
   string trend10Str=(!g_trend10Known[i] ? "unknown" : (g_trend10Oppose[i]?"true":"false"));
   string bar3Str=(!g_bar3Known[i] ? "unknown" : (g_bar3OneWay[i]?"true":"false"));
   string bandStr=(g_trackBandLevel[i]==0 ? "n/a(fade)" : (g_bandReentered[i]?"true":"false"));
   Log("MAE_OUTCOME","outcome="+outcome+" profit="+DoubleToString(profit,2)+
       " reached50="+(g_reached50[i]?"true":"false")+" reached75="+(g_reached75[i]?"true":"false")+
       " firstBarOneWay="+firstBarStr+" nextBarOppose="+nextBarStr+" trend10Oppose="+trend10Str+" threeBarOneWay="+bar3Str+" bandReentry="+bandStr+
       " oppSignalSeen="+(g_trackOppSignalSeen[i]?"true":"false")+
       " reachedFav50="+(g_reachedFav50[i]?"true":"false")+
       " reachedFav75="+(g_reachedFav75[i]?"true":"false")+
       " reachedFav90="+(g_reachedFav90[i]?"true":"false")+
       " beTriggered="+(g_beTriggered[i]?"true":"false")+
       " beRetraced="+(g_beRetraced[i]?"true":"false")+
       " beMoved="+(g_beMoved[i]?"true":"false")+
       " protectTriggered="+(g_protectTriggered[i]?"true":"false")+
       " protectMoved="+(g_protectMoved[i]?"true":"false")+
       " timeMildMin="+DoubleToString(g_timeMildMin[i],1)+
       " timeDangerMin="+DoubleToString(g_timeDangerMin[i],1)+
       " touch="+(g_trackBodyTouch[i]?"BODY":"WICK")+
       " prior5Same="+(g_trackPrior5Same[i]?"true":"false")+
       " wickLenATR="+(g_trackWickLenATR[i]>=999.0?"n/a":DoubleToString(g_trackWickLenATR[i],3))+
       " adxRiseDiff="+(g_trackAdxRiseKnown[i]?DoubleToString(g_trackAdxRiseDiff[i],2):"n/a")+
       " effRatio="+(g_trackEffRatioKnown[i]?DoubleToString(g_trackEffRatio[i],3):"n/a")+
       " htfAligned="+(!g_trackHtfKnown[i]?"n/a":(g_trackHtfAligned[i]?"true":"false"))+
       " atrExpansion="+(g_trackAtrKnown[i]?DoubleToString(g_trackAtrExpansion[i],3):"n/a")+
       " zoneDistATR="+(g_trackZoneDistATR[i]>=999.0?"n/a":DoubleToString(g_trackZoneDistATR[i],3))+
       " DI="+(g_trackDIKnown[i]?DoubleToString(g_trackDI[i],2):"n/a")+
       " diBaseAgainst="+(!g_trackDIBaseKnown[i]?"n/a":(g_trackDIBaseAgainst[i]?"true":"false"))+
       " diCrossSeen="+(g_trackDICrossSeen[i]?"true":"false")+
       " diCrossR="+(g_trackDICrossSeen[i]?DoubleToString(g_trackDICrossR[i],3):"n/a")+
       " stochPeaked="+(g_trackStochPeaked[i]?"true":"false")+
       " stochRolloverSeen="+(g_trackStochRolloverSeen[i]?"true":"false")+
       " stochRolloverR="+(g_trackStochRolloverSeen[i]?DoubleToString(g_trackStochRolloverR[i],3):"n/a")+
       " | "+g_trackTag[i]);
   g_trackTicket[i]=0; // free slot
   g_waitingFirstBar[i]=false;
   g_waitingNextBar[i]=false;
   g_waitingTrend10[i]=false;
   g_waitingBar3[i]=false;

   if(outcome=="LOSS")
   {
      g_consecutiveLosses++;
      if(g_consecutiveLosses>=CircuitBreakerLossCount)
      {
         g_breakerActiveUntil=TimeCurrent()+(datetime)(CircuitBreakerCooldownHours*3600);
         Log("CIRCUIT_BREAKER_TRIGGERED","consecutiveLosses="+IntegerToString(g_consecutiveLosses)+
             " cooldownUntil="+TS(g_breakerActiveUntil));
         g_consecutiveLosses=0; // require a fresh streak to trigger again after this cooldown
      }
   }
   else
      g_consecutiveLosses=0;
}
//+------------------------------------------------------------------+
