//+------------------------------------------------------------------+
//| XAU_M10_BB_LIVE_007_BUYONLY_V2.mq5                               |
//| V2: added LatestSignalOnly, ported from 005_RFILTER_V2's finding |
//| (gold M2: NET +15,135->+16,281, MaxDD -19,924->-5,658). A new BB- |
//| breakout signal candle discards any still-pending earlier        |
//| setup(s) in S[] instead of letting them keep waiting alongside   |
//| it. Default false reproduces the original file exactly.          |
//| ---- inherited from 007_PROTECT05_PARTIAL10_FIX_BUYONLY.mq5 ----  |
//| BUY-ONLY variant of 007 (AllowShort=false by default).          |
//| Real MT5 tick backtest (2025.01-2026.09): SELL trades alone were |
//| net -$1,196.19 vs BUY alone net -$185.63. Disabling SELL turns   |
//| the EA's 21-month result from -$1,381.82 to -$185.63. Re-enable  |
//| SELL via the AllowShort input if you want the original behavior. |
//| Forward-test EA: NEW-A +0.5R protect / +1.0R split                   |
//| M10 dual BB -> +0.95R extension -> 0.10R pullback -> countertrend|
//| SL2R; +0.5R arms +0.25R SL; +1R closes 0.01; final target          |
//| = ENTRY + countertrend 1.75R (FIXED -- was signal_close +            |
//| SignalOppositeTP_R*R (then 0.90), an inconsistent anchor vs every    |
//| other R-based level in this EA, which are all entry-relative).       |
//| Since entry is itself signal_close offset by                         |
//| (ExtensionR-PullbackR)*R in the countertrend direction, the old      |
//| formula put the real TP at (ExtensionR-PullbackR+0.90)=1.75R from    |
//| entry, not the 0.90R the input name/value implied -- user-requested  |
//| fix to anchor consistently on entry like every other level here.     |
//| SignalOppositeTP_R was WIDENED from 0.90 to 1.75 in the same change   |
//| (0.95-0.10+0.90=1.75), user-chosen over leaving it at 0.90 and         |
//| re-tuning everything downstream. CORRECTION to an earlier overclaim:   |
//| this reproduces the exact same final TP price as before ONLY for a     |
//| trade with ZERO extension overshoot (price touches the 0.95R           |
//| extension trigger and pulls back 0.10R immediately). Since the         |
//| pullback watch keeps updating S[i].extreme as price continues to run    |
//| favorably past that trigger before ever retracing 0.10R from its own    |
//| running peak, overshoot is routine, not an edge case -- for an          |
//| overshot trade, entry sits further from signal_close than the           |
//| (ExtensionR-PullbackR)*R minimum, so the new entry-anchored TP lands     |
//| at OLD_finaltp - dir*overshoot (closer to entry, i.e. a SMALLER real     |
//| target than before, growing with however far price ran past the         |
//| trigger). Every TESTED/CONFIRMED value below this point (InitialSL_R,   |
//| ProtectTriggerR, ProtectR, PartialTriggerR) is therefore NOT            |
//| guaranteed to still hold and needs a fresh ground-truth confirmation     |
//| run under this fix before being trusted again.                          |
//| BODY vs WICK touch (diagnostic only, no trading effect): tags     |
//| every trade's comment with _BODY/_WICK depending on whether the    |
//| SIGNAL candle's close also broke BB20 or only its high/low wicked  |
//| through it -- same distinction the 001 family confirmed matters    |
//| (FADE_BEAR_OS+WICK was a losing combination on M1/M2/M3 there).    |
//| Note the entry itself happens later (after the extension+pullback  |
//| sequence), always countertrend to the signal, so a BEAR signal's    |
//| touch quality is what's actually being tested here (BUY-only).      |
//| H1_TREND_CHECK / SkipIfH1TrendAgainst / SkipIfH1NotAgainst          |
//| (h1Against fixed at SIGNAL time in NewBar(), not re-evaluated at    |
//| the later entry time; flags ACT in SendEntry()): checks the two H1  |
//| bars immediately preceding the one in progress when the M10 signal  |
//| appeared (shift 1 and shift 2, both fully closed) -- if BOTH oppose |
//| the eventual entry direction (both bearish for a BUY), tagged       |
//| H1AGAINST, else H1OK. Original theory (SkipIfH1TrendAgainst) was    |
//| backwards: H1AGAINST trades were the GOOD ones, since a genuine     |
//| H1-aligned extension reads as real capitulation where the mean-     |
//| reversion bounce is more reliable. SkipIfH1NotAgainst (keep only    |
//| H1AGAINST) default=true reflects that finding, but the ground-truth |
//| numbers below (NET $7,579.88 -> $10,518.15, PF 1.216 -> 1.418,      |
//| Recovery Factor 2.806 -> 5.007, WR 86.34% -> 87.20%) were measured  |
//| on an earlier version of this check anchored at ENTRY time (shift 0 |
//| in-progress + shift 1 last-closed) -- needs a fresh backtest on     |
//| this signal-time/shift-1-2 version before re-confirming the exact   |
//| impact, though the same direction is expected to hold.              |
//| NEXT5_AFTER_SIGNAL (diagnostic only, no trading effect): for every   |
//| M10 signal candle, counts how many of the 5 M10 bars starting right  |
//| after it (inclusive) are bearish (close<open) -- answers "did a      |
//| losing (stopped-out) trade's signal get followed by a strong,        |
//| one-way continuation, or something choppier?" Independent of S[]'s   |
//| lifecycle (still completes even if LatestSignalOnly discards the     |
//| setup or it never becomes a real trade), joined externally against   |
//| a trade's own outcome via the shared sig= timestamp now also logged  |
//| on ENTRY_OK. A post-hoc correlation (2025.01-2026.09, H1CheckAtEntry  |
//| Time=true) found losing trades averaged bearCount 2.90 vs winning     |
//| trades' 2.65, and bearCount>=4 was 28.2% of losses vs only 18.3% of   |
//| wins (z=2.89) -- but that used bearCount values known only in         |
//| hindsight (whenever the 5 bars eventually closed, not necessarily by  |
//| the trade's own entry time). NEXT5_CHECK / SkipIfNext5Bearish         |
//| GROUND-TRUTH REJECTED once actually tried live: next5Ready was true   |
//| for only ~20 of 1336 trades AT their real entry moment (most entries  |
//| fire within the first 50 min, before the 5 bars even exist), and      |
//| filtering that tiny subset made every metric slightly worse (NET      |
//| $10,518.15 -> $9,959.27, PF 1.418 -> 1.399, Recovery Factor 5.007 ->  |
//| 4.523). Lesson: a correlation measured with hindsight-only data does  |
//| not automatically transfer to a real-time filter -- keep this false.  |
//| FRIDAY_NIGHT_CHECK / SkipFridayNightEntry (diagnostic always on; flag  |
//| ACTS): found by inspecting the ~50-hour "slow bleed" losses -- all 5   |
//| were Friday-night entries (22:30-23:41 server time) that sat over the |
//| closed weekend and got stopped right at Monday reopen (exit timestamp |
//| 01:01 on every single one, -$1,902.85 combined). 100% mechanical      |
//| weekend-gap risk, not market behavior. Blocks a real entry once it's  |
//| Friday at/after FridayNightCutoffHour (22:00) server time; the Setup   |
//| is dropped rather than held for Monday, since its extension+pullback  |
//| state is stale by then anyway. CONFIRMED default=true: NET $10,518.15 |
//| -> $12,479.87 (+18.6%), PF 1.418 -> 1.542, Recovery Factor 5.007 ->    |
//| 6.887, WR 87.20% -> 87.59%, DD 1.95%/2.07% -> 1.62%/1.78% -- a clean   |
//| win on every metric, bigger than the raw dollars removed.             |
//| SIGNAL_STREAK / SkipEarlySignalsInStreak (diagnostic always on; flag   |
//| ACTS): user's chart observation -- in a strong trend, the FIRST BB    |
//| signal in a same-direction run tends to get run over (stopped out),   |
//| while a LATER one in the run (closer to real exhaustion) works        |
//| better. Counts consecutive same-direction M10 signals, reset to 1 on  |
//| any direction flip; when SkipEarlySignalsInStreak=true, only the      |
//| EntryFromNthSignal'th (default 2nd) and later signals in a run are    |
//| ever allowed to become a real Setup -- earlier ones in the run are    |
//| skipped entirely (no extension/pullback tracking wasted on them).     |
//| GROUND-TRUTH REJECTED: on top of the confirmed SkipTuesdayEntry/       |
//| SkipHourAEntry/SkipHourBEntry baseline (650 trades, WR 84.31%, NET     |
//| $14,922.00, PF 2.236, Recovery Factor 8.234), turning this on cut      |
//| trades to 463 (-28.8%) and made every metric worse: NET $9,320.97      |
//| (-37.5%), WR 82.29%, PF 1.908, Recovery Factor 4.873 (nearly halved).  |
//| Keep this false.                                                       |
//| SkipTuesdayEntry / SkipHourAEntry / SkipHourBEntry (CONFIRMED          |
//| default=true, all three together): a KST day-of-week and 2h-bucket    |
//| breakdown of the confirmed-default backtest (2025.01-2026.09,         |
//| H1CheckAtEntryTime=true, SkipFridayNightEntry=true) using PER-ENTRY   |
//| accounting (see note below) -- 979 trades, WR 82.84%, NET             |
//| $12,479.87 -- found: Tuesday is the ONLY net-negative weekday (202    |
//| trades, WR 76.7%, NET -$2,342.43, vs every other weekday positive);   |
//| 08-10 KST (82 trades, WR 75.6%, NET -$569.95) and 16-18 KST (89       |
//| trades, WR 83.1%, NET -$1,857.95, large losses despite a decent win   |
//| rate) are the only two negative 2h buckets out of twelve. All three   |
//| flags block new entries (SendEntry) independently. Ground-truth       |
//| backtest with all three on together confirmed a clean improvement    |
//| on every metric: 979->650 trades (-33.6%), NET $12,479.87->$14,922.00 |
//| (+19.6%), PF 1.542->2.236, Recovery Factor 6.887->8.234, WR           |
//| 82.84%->84.31%, MaxDD 1.62%/1.78%->1.24%/1.75%. Tested only as a      |
//| combined group -- each flag's individual contribution isn't          |
//| isolated, but the combined effect is unambiguous.                     |
//| NOTE ON WIN RATE ACCOUNTING: every WR%/trade-count figure elsewhere    |
//| in this header (86.34%/87.20%/87.59% etc.) was read directly from     |
//| MT5's own report stat, which counts each PartialTriggerR=1.0 partial  |
//| close as a separate "trade" from its later final close -- inflating   |
//| both trade count and WR (a partial is always a win by construction).  |
//| Reconstructing PER-ENTRY outcomes (summing profit+commission+swap     |
//| across a position's partial+final deals, keyed to its own entry) on   |
//| the same 1313-deal-count backtest gives 979 real entries at WR        |
//| 82.84%, not 87.59% -- the NET total matches exactly either way        |
//| ($12,479.87), only the trade-count/WR denominator differs. Treat any  |
//| WR% in this file from before this note as the inflated MT5 figure.    |
//| MinR_Points (CONFIRMED=300): unlike every 001_STOCH/005_RFILTER       |
//| sibling in this project (each tuned its own MinR_Points per           |
//| timeframe -- M1=350-400, M2=200-350, M3=900), 007 never had a signal- |
//| candle-body floor at all -- only R>0 was required. A first 0-800      |
//| step-50 Optimizer sweep was confounded by SkipEarlySignalsInStreak    |
//| stuck at true (see prior revert in git history) and was discarded.    |
//| A clean re-sweep (SkipEarlySignalsInStreak=false, SkipTuesdayEntry/   |
//| SkipHourAEntry/SkipHourBEntry all true -- verified because its        |
//| MinR_Points=0 row reproduces the true baseline exactly: NET           |
//| $14,922.00, PF 2.236, RF 8.234) shows a plateau at 200-400 beating 0  |
//| on every metric, best at 300 (Recovery Factor sort):                  |
//|   MinR_Points=0   (old): NET $14,922.00, PF 2.236, RF 8.234, DD 1.7505% |
//|   MinR_Points=300 (new): NET $16,005.75, PF 2.560, RF 8.832, DD 1.7342% |
//| A single (non-optimizer) confirmation run at MinR_Points=300 gives    |
//| the true per-entry WR (007 has partial closes, see WIN RATE           |
//| ACCOUNTING note above): 483 entries (was 650), 433W/50L, WR 89.65%    |
//| (was 84.31%), NET matches the sweep exactly ($16,005.75).             |
//| InitialSL_R (TESTED, kept at 2.25): unlike every 001_STOCH/005_       |
//| RFILTER sibling (each got a clear win widening its stop to 3.5R),     |
//| a 1.50-4.50 step-0.25 Optimizer sweep on top of the confirmed         |
//| baseline (MinR_Points=300, Tuesday/HourA/HourB filters all true)      |
//| found no real signal: 2.00-4.25 all sit in a noisy RF 8.0-8.9 band    |
//| with no monotonic trend (RF dips at 3.50 then recovers at 3.75,       |
//| inconsistent with a genuine effect), 1.50-1.75 are clearly worse      |
//| (RF 4.9-7.3), the nominal best (4.00: NET $16,087.00, RF 8.877) beats |
//| the current default (2.25: NET $16,005.75, RF 8.832) by only +0.5%    |
//| NET while trading less (644 vs 657) -- inside noise, not a plateau.   |
//| Kept unchanged at 2.25 (opposite of every 001/005 sibling's finding). |
//| ProtectR (TESTED, kept at 0.25): the closest 007 analog to 005's      |
//| Lock_R (profit-protect SL level after trigger). A 0.10-0.45 step-0.05 |
//| sweep on the confirmed baseline is a genuine trade-off, not a free    |
//| win: 0.35/0.40 cut MaxDD sharply (1.734%->1.520%/1.513%, -12-13%,     |
//| driving RF up to 9.78) but at the cost of NET (-3.1% to -3.6%:        |
//| $16,005.75 -> $15,514.43 / $15,431.42) and fewer trades (657->624/    |
//| 601); every other tested value (0.10-0.30) is worse on both NET and   |
//| RF than the default. User chose to keep 0.25 (max NET) over trading   |
//| some return for a smoother equity curve. RE-SWEPT after                |
//| PartialTriggerR moved 1.0->1.5: same shape reproduced (0.35/0.40 cut  |
//| MaxDD to ~1.51-1.52% and push RF to ~10.1-10.3, but NET drops 5.4-     |
//| 7.5% from the new baseline's $17,235.17). Kept at 0.25 again, same    |
//| reasoning.                                                             |
//| ProtectTriggerR (TESTED, kept at 0.50): a 0.20-0.95 step-0.05 sweep    |
//| on the confirmed baseline found two things. (1) IMPORTANT SAFETY      |
//| FINDING: values >=0.70 (approaching PartialTriggerR=1.0) cause MaxDD  |
//| to jump from ~1.7% to 3.6%-4.7% -- protect-trigger and partial-close  |
//| logic interact badly once they're close together. DO NOT set         |
//| ProtectTriggerR >= 0.70. (2) 0.60 topped the sweep despite both       |
//| neighbors (0.55, 0.65) being worse than the 0.50 baseline; a single   |
//| (non-optimizer) confirmation run reproduced its NET exactly           |
//| ($16,348.15), ruling out a fluke -- true per-entry accounting:        |
//| 483->476 entries, 433W/50L->413W/63L, WR 89.65%->86.76% (down), NET   |
//| $16,005.75->$16,348.15 (+2.1%), RF 8.832->9.021, DD 1.7342%->1.7234%. |
//| Briefly set as the new default, then REVERTED to 0.50 by user choice: |
//| the +2.1% NET wasn't worth trading ~2.9pp of win rate for. RE-SWEPT   |
//| after PartialTriggerR moved 1.0->1.5 (in case the two interact) and   |
//| the exact same shape reproduced: 0.70+ still causes the MaxDD cliff,  |
//| and 0.60 is again an isolated spike above both its neighbors (0.50    |
//| baseline RF 9.511/NET $17,235.17 vs 0.60 RF 9.749/NET $17,666.42, but |
//| 0.55 RF 9.296 and 0.65 RF 9.389 both worse than baseline). Kept at    |
//| 0.50 again, same reasoning as before.                                 |
//| PartialTriggerR (CONFIRMED=1.5): a 0.60-2.00 step-0.10 sweep on the    |
//| confirmed baseline (ProtectTriggerR=0.50, ProtectR=0.25 both swept    |
//| under the OLD PartialTriggerR=1.0 and not yet re-verified under this  |
//| new value -- worth a re-sweep) found a clean, monotonic improvement   |
//| all the way to the swept ceiling (2.0): NET $16,005.75->$17,896.92    |
//| (+11.8%), RF 8.832->9.876, with DD roughly flat (~1.73%). STRUCTURAL  |
//| CAUSE (why this trend exists and why it plateaus near 2.0 -- still    |
//| valid after the TP anchor was later fixed to be entry-relative, see   |
//| the FIXED note atop this header: SignalOppositeTP_R was widened from  |
//| 0.90 to 1.75 in that same change specifically to keep this exact      |
//| ~1.75R distance and every number below unchanged): the R used here    |
//| is the fixed signal-candle body, and the broker's hard take-profit    |
//| sits at roughly 1.75R beyond entry at minimum (often more) -- so raising |
//| PartialTriggerR toward/past ~1.75R means most winners hit the full    |
//| TP before ever reaching the partial-close trigger, i.e. it            |
//| progressively DISABLES the partial-close feature rather than just     |
//| delaying it. Verified directly with two single-run confirmations:     |
//| both 1.5 and 2.0 give the IDENTICAL 483 entries/433W/50L/WR 89.65%    |
//| (losers all hit SL before any partial check, so WR has zero trade-off |
//| here) -- the only difference is how many winners still get a real     |
//| partial close: 120/483 (24.8%) at 1.5 vs only 26/483 (5.4%) at 2.0.   |
//| Chose 1.5 (NET $17,235.17, +7.7%, RF 9.511) over 2.0 (+11.8%, RF      |
//| 9.876) specifically to keep the partial-close risk-management         |
//| behavior meaningfully alive rather than let 2.0 all but remove it.    |
//| FINAL VALIDATION: also re-swept ProtectTriggerR (0.20-0.95) and       |
//| ProtectR (0.10-0.45) under PartialTriggerR=2.0 to check for           |
//| interaction -- both landed back on the same 0.50/0.25 optimum found   |
//| under 1.0 and 1.5, so ProtectTriggerR/ProtectR are robust to this     |
//| choice. Also tested fully DISABLING partial close (PartialTriggerR=   |
//| 999, single-run confirmed 0% partial rate): NET $18,129.47 (highest   |
//| of all three) but WR drops to 89.23% (431W/52L, vs 89.65%/433W/50L    |
//| at both 1.5 and 2.0) -- tracing the 2 flipped entries showed WHY:     |
//| e.g. one trade spiked to +1.5R (3281.74->3289.06) then round-tripped  |
//| back to near breakeven (3282.68). With partial, half locked in the    |
//| +1.5R excursion (+$36.60) and only the runner half gave it back       |
//| (net +$16.14, a win); without partial, the FULL position rode the     |
//| entire round trip and only captured the tiny net move, losing to      |
//| swap cost (net -$15.76, a loss). ProtectTriggerR only defends against |
//| price falling below the lock level -- it does nothing to bank an     |
//| excursion that later round-trips back down without breaching it.      |
//| Partial-close is the only mechanism that captures that upside before  |
//| it reverses. FINAL DECISION: keep PartialTriggerR=1.5 over both 2.0   |
//| and full removal -- it preserves this round-trip protection at a     |
//| meaningful 24.8% partial rate, trading some raw NET upside (2.0:      |
//| +3.8%, 999: +5.2% more) for that structural insurance.                |
//| zoneDistATR diagnostic (ported from 001_STOCH_v2/005_RFILTER_V2,      |
//| UNTESTED here): logs the distance (in ATR units) from the ACTUAL      |
//| ENTRY FILL price (not the signal candle, since entry can fire up to   |
//| MaxExtensionHours+MaxPullbackHours after the signal) to the nearest    |
//| enabled 매물대 zone (Asia/NY opening-hour boxes, today/previous-day     |
//| high-low, previous-NY-session high-low). Diagnostic only -- does NOT   |
//| block or alter any entry. Logged on every trade close as MANAGED_EXIT  |
//| (this EA had no outcome/profit log at all before this -- ManageOwn()'s |
//| own-position-just-disappeared branch now looks up the closed deal via  |
//| HistorySelectByPosition). Per the lesson learned on 001: do NOT turn   |
//| this into an active filter until a bucketed analysis of logged         |
//| zoneDistATR vs outcome shows a robust, replicating relationship.       |
//|                                                                        |
//| UseTrailingStop/TrailStopDistanceR and UseTrailingTP/TrailTPDistanceR |
//| (CONFIRMED, both true live): same idea already CONFIRMED on            |
//| 005_RFILTER_V2 -- gate on the EA's own LATEST already-proven safe      |
//| trigger instead of an earlier one. Here that's PartialTriggerR=1.5R    |
//| (the partial-close stage, extensively tuned already -- see its own     |
//| header section), not ProtectTriggerR=0.50R (the earlier whole-         |
//| position lock stage). Once the partial close completes, the "runner"   |
//| half, instead of sitting at a static +ProtectR=0.25R lock until it     |
//| either hits that lock or the final entry-relative TP                   |
//| (SignalOppositeTP_R=1.75R beyond entry), now continuously re-trails.    |
//| UseTrailingStop alone would trail the runner's SL at                   |
//| TrailStopDistanceR*R behind price every tick (only ever tightening).   |
//| UseTrailingTP ALSO removes the final TP cap so the runner can ride      |
//| further if the move continues, trailing SL at TrailTPDistanceR*R       |
//| behind price from that point on; with both enabled, UseTrailingTP's    |
//| own distance/TP-removal takes over once armed (same interaction as     |
//| 001/005) -- TrailStopDistanceR=0.03 stays live but is effectively      |
//| superseded on any trade where UseTrailingTP arms.                      |
//|                                                                        |
//| Discovered mid-port: the final TP (finaltp) was anchored to the         |
//| SIGNAL CANDLE'S CLOSE rather than the actual entry price, unlike every  |
//| other R-level in this EA (InitialSL_R/ProtectTriggerR/ProtectR/         |
//| PartialTriggerR, all entry-anchored) and unlike 005's equivalent. Fixed |
//| to anchor on entry; SignalOppositeTP_R widened 0.90->1.75 to preserve   |
//| the old effective target distance for zero-overshoot trades (not an     |
//| exact reproduction for all trades -- see commit history). Post-fix      |
//| clean OFF/ON baselines re-run and confirmed consistent with pre-fix     |
//| findings (trailing still mildly net-negative UNTUNED).                  |
//|                                                                        |
//| TrailTPDistanceR grid search (0.01-0.10, UseTrailingStop=true/          |
//| UseTrailingTP=true/SignalOppositeTP_R=1.75 fixed, 2025.01.01-           |
//| 2026.10.03): clear interior peak at 0.02 (NET $21,999.88, PF 3.279,     |
//| RF 12.14, n=550 deals/442 positions) -- 0.01 close second ($20,710.59), |
//| 0.03 drops off sharply ($18,027.36), 0.04-0.10 plateau ~$16,100-16,400. |
//| CONFIRMED at TrailTPDistanceR=0.02, single run reconciled exactly to    |
//| the optimizer (NET $21,999.88 to the penny; WR 89.14%, avg_win $78.63,  |
//| avg_loss -$187.11, PF 3.45 position-level -- optimizer's 3.279 is deal- |
//| level, splits each partial-close's own P&L into a separate win/loss     |
//| bucket, not a discrepancy). This beats the pre-grid OFF baseline (NET   |
//| $16,618.21) by +32%.                                                   |
//|                                                                        |
//| Isolated UseTrailingStop-alone (UseTrailingTP=false, like 005's own     |
//| isolated test), TrailStopDistanceR grid-searched 0.01-0.10: REJECTED --  |
//| unlike 005, every tested value underperforms the OFF baseline, nearly   |
//| monotonically decreasing from 0.01 (best, NET $16,485.36, still below    |
//| the $16,618.21 OFF baseline) down to 0.10 (NET $16,192.04). No interior  |
//| peak, no value beats OFF. UseTrailingTP (CONFIRMED above) is the only    |
//| live trailing mechanism worth using on this EA; UseTrailingStop stays    |
//| true only because it's harmlessly superseded on every trade where       |
//| UseTrailingTP arms. Entry-commission handling (GetClosedPositionProfit)  |
//| was already correct in this file before this port.                     |
//|                                                                        |
//| UseStochFadeConfirm (ported from 001_STOCH_v2's FADE_BEAR_OS/          |
//| STOCH_FADE_BULL_OB logic, UNTESTED here, default false): this EA       |
//| currently fades EVERY qualifying signal candle unconditionally (the    |
//| whole extension+pullback mechanism IS the fade, there's no trend-      |
//| following branch to compare against like 001 has). This adds an        |
//| optional gate at the signal candle itself: only start tracking a       |
//| setup if Stochastic ALSO confirms the fade direction at that bar       |
//| (oversold for a bear signal -> BUY fade, overbought for a bull         |
//| signal -> SELL fade). Needs its own ground-truth run before any        |
//| verdict. Same feature ported identically to 005_RFILTER_V2.            |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input double Lots=0.1; // Lot size
input bool EnableLiveOrders=false; // Enable live orders
input long MagicNumber=95011207; // Magic number
input double ExtensionR=0.95; // Extension (R) before pullback watch starts
input double PullbackR=0.10; // Pullback (R) from extension extreme to trigger entry
input double InitialSL_R=2.25; // Initial stop loss (R) (TESTED, kept unchanged, see header)
input double ProtectTriggerR=0.50; // Break-even/protect trigger (R) (TESTED, kept unchanged, see header)
input double PartialTriggerR=1.5; // Partial close trigger (R) (CONFIRMED, see header)
input double ProtectR=0.25; // Protect SL level (R) (TESTED, kept unchanged, see header)
input double SignalOppositeTP_R=1.75; // Final target beyond ENTRY (R) (CONFIRMED, see header -- anchor fixed to entry like every other level, value widened from 0.90 to (ExtensionR-PullbackR)+0.90=1.75 to reproduce the exact same final TP price as before the fix, preserving every other TESTED/CONFIRMED value below)
input int  MinR_Points=300; // Min signal-candle body (points) to trade, 0=no filter (CONFIRMED, see header)
input int MaxExtensionHours=72; // Max hours waiting for extension
input int MaxPullbackHours=72; // Max hours waiting for pullback
input int MaxPositionHours=168; // Max hours holding a position
input bool AllowShort=false; // Allow SELL entries (default BUY-only, see header)

input bool UseStochFadeConfirm=false; // Require Stochastic to confirm the fade direction at the signal candle (UNTESTED, see header)
input int StochK_Period=8; // Stoch %K period (only used when UseStochFadeConfirm=true)
input int StochD_Period=3; // Stoch %D period (only used when UseStochFadeConfirm=true)
input int StochSlowing=3; // Stoch slowing (only used when UseStochFadeConfirm=true)
input double StochOverbought=85.0; // Stoch overbought level, confirms a bull-signal SELL fade (only used when UseStochFadeConfirm=true)
input double StochOversold=30.0; // Stoch oversold level, confirms a bear-signal BUY fade (only used when UseStochFadeConfirm=true)
input bool LatestSignalOnly=true; // New signal cancels older pending setups (see header)
input bool SkipIfH1TrendAgainst=false; // H1 filter: skip when H1 against entry (REJECTED, see header)
input bool SkipIfH1NotAgainst=true; // H1 filter: keep only H1-against trades (CONFIRMED, see header)
input bool H1CheckAtEntryTime=false; // H1 filter anchor: false=signal time, true=entry time (see header)
input int  Next5BearThreshold=4; // NEXT5 diagnostic: bearish-bar threshold (see header)
input bool SkipIfNext5Bearish=false; // NEXT5 filter: skip if next5 bearish (REJECTED, see header)
input int  FridayNightCutoffHour=22; // Friday-night cutoff hour, server time (see header)
input bool SkipFridayNightEntry=true; // Block entries after Friday cutoff (CONFIRMED, see header)
input int  EntryFromNthSignal=2; // Min signal position in same-direction streak to allow entry
input bool SkipEarlySignalsInStreak=false; // Streak filter: skip early signals (REJECTED, see header)
input bool SkipTuesdayEntry=true; // Block all entries on Tuesday, KST (CONFIRMED, see header)
input int  SkipHourAStartKST=8; // Hour-dip A window start, KST (see header, SkipHourAEntry)
input int  SkipHourAEndKST=10; // Hour-dip A window end, KST, exclusive (see header, SkipHourAEntry)
input bool SkipHourAEntry=true; // Block entries in [SkipHourAStartKST,SkipHourAEndKST) KST (CONFIRMED, see header)
input int  SkipHourBStartKST=16; // Hour-dip B window start, KST (see header, SkipHourBEntry)
input int  SkipHourBEndKST=18; // Hour-dip B window end, KST, exclusive (see header, SkipHourBEntry)
input bool SkipHourBEntry=true; // Block entries in [SkipHourBStartKST,SkipHourBEndKST) KST (CONFIRMED, see header)
input bool UseFridayNarrowWindow=false; // On Friday, only allow entries 10:30-15:00 KST (ported from 001 M2_v2 where CONFIRMED; REJECTED here, see header)

input bool   UseTrailingStop     = true; // After the partial close (PartialTriggerR), continuously trail the runner's SL instead of the static +ProtectR lock (CONFIRMED true live, see header; superseded on any trade where UseTrailingTP arms)
input double TrailStopDistanceR  = 0.03; // Distance maintained between price and the trailing SL after the partial close, in R (only used when UseTrailingStop=true AND UseTrailingTP hasn't armed)
input bool   UseTrailingTP       = true; // After the partial close (PartialTriggerR), remove the final TP cap and trail SL on the runner instead of closing at SignalOppositeTP_R (CONFIRMED true live, see header)
input double TrailTPDistanceR    = 0.02; // Distance maintained between price and the trailing SL once the final TP cap is removed, in R (CONFIRMED, see header; only used when UseTrailingTP=true)

// -- 매물대 (supply/demand zone) diagnostic (ported from 001 M2_v2 / 005
//    RFILTER_V2): logs zoneDistATR on every trade close. Diagnostic
//    ONLY -- does not block or alter any entry.
input int    ATRPeriod             = 14; // ATR period used for zoneDistATR (does not affect SL/TP, those are R-based)
input bool   UseAsiaBoxZone        = true; // Include the Asia-session opening-hour candle's high/low
input int    AsiaOpenHourKST       = 8; // KST hour (integer) the Asia session opening candle starts
input bool   UseNYBoxZone          = true; // Include the NY/US-session opening-hour candle's high/low
input double NYOpenHourKST         = 22.5; // KST hour (decimal) the NY session opening candle starts
input bool   UseTodayHighLowZone   = true; // Include today's running high/low (so far, KST calendar day)
input bool   UsePrevDayHighLowZone = true; // Include the previous KST calendar day's high/low
input bool   UsePrevNYHighLowZone  = true; // Include the previous day's NY-session-window high/low (미국장 전일 고가저가)
input double NYSessionStartHourKST = 20.0; // KST hour (decimal) the NY session window starts, for 전일 미장 고가/저가 tracking (wraps past midnight)
input double NYSessionEndHourKST   = 6.0; // KST hour (decimal) the NY session window ends

int h20=INVALID_HANDLE,h4=INVALID_HANDLE,hATR_Sig=INVALID_HANDLE,hStoch=INVALID_HANDLE;
datetime lastbar=0;
int      g_consecSignalCount=0,g_lastSignalSd=0; // consecutive same-direction M10 signal streak
int f_log=INVALID_HANDLE;

// -- supply-zone state (all in KST calendar-day terms), ported from 001 M2_v2 --
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

double g_entryZoneDistATR=999.0; // zoneDistATR at the actual entry fill of the currently open trade
ulong  tracked_ticket=0;         // kept fresh to the currently open own-Magic position's ticket

string TS(datetime t){ return TimeToString(t,TIME_DATE|TIME_MINUTES|TIME_SECONDS); }
void Log(string event,string detail="")
{
   Print("LIVE007 | ",event," | ",detail);
   if(f_log!=INVALID_HANDLE){ FileWrite(f_log,TS(TimeCurrent()),event,detail); FileFlush(f_log); }
}

struct Setup{
 datetime sig,ct,exp;
 int sd;
 double R,o,h,l,c,extreme;
 bool ext;
 bool bodyTouch; // diagnostic: did the signal candle's CLOSE also break BB20, or only
                 // the high/low (wick)? See 001 family's ground truth on this same
                 // distinction (FADE_BEAR_OS+WICK was a losing combination there).
 bool h1Against; // does the eventual (countertrend) entry direction fight BOTH of the
                 // two H1 bars immediately preceding the one in progress at signal time
                 // (shift 1 and shift 2 as of NOW, when the M10 signal candle appears)?
                 // Fixed at signal time, not re-checked at the later entry time.
 int  next5BearCount; // -1 until CheckLookaheads() fills it in (5 bars after the signal
                 // have closed) -- how many of those 5 M10 bars were bearish. Ground-
                 // truth: losing trades average 2.90 vs winning trades' 2.65, and a
                 // bearCount>=4 more than doubles the loss-rate odds (28.2% vs 18.3% of
                 // trades, z=2.89) -- see header.
 bool next5Ready; // true once next5BearCount is actually known. Can still be false at
                 // entry time for fast setups (extension+pullback done within 50 min of
                 // the signal) -- SkipIfNext5Bearish only ever acts when this is true.
};
Setup S[];

// -- NEXT5_AFTER_SIGNAL lookahead (diagnostic only, no trading effect) ------
// For every M10 signal candle (regardless of whether LatestSignalOnly later
// discards it, or whether it ever turns into a real trade), counts how many
// of the 5 M10 bars starting right after the signal candle (inclusive) are
// bearish (close<open). Independent pool, not tied to Setup's lifecycle,
// since a signal can be discarded from S[] long before 5 more bars close.
#define LOOKAHEAD_SLOTS 32
bool     la_active[LOOKAHEAD_SLOTS];
datetime la_sig[LOOKAHEAD_SLOTS];
int      la_bearCount[LOOKAHEAD_SLOTS], la_totalCount[LOOKAHEAD_SLOTS];
int      la_sd[LOOKAHEAD_SLOTS];
bool     la_bodyTouch[LOOKAHEAD_SLOTS];

void StartLookahead(datetime sig,int sd,bool bodyTouch){
 int i=-1;
 for(int k=0;k<LOOKAHEAD_SLOTS;k++) if(!la_active[k]){i=k;break;}
 if(i<0){Log("LOOKAHEAD_SLOTS_FULL","dropping lookahead for sig="+TimeToString(sig));return;}
 la_active[i]=true;la_sig[i]=sig;la_bearCount[i]=0;la_totalCount[i]=0;la_sd[i]=sd;la_bodyTouch[i]=bodyTouch;
}

// Called once per new M10 bar, using the bar that just closed (shift 1).
void CheckLookaheads(datetime barTime,double barOpen,double barClose){
 bool anyActive=false;
 for(int k=0;k<LOOKAHEAD_SLOTS;k++) if(la_active[k]){anyActive=true;break;}
 if(!anyActive)return;
 bool bearBar=barClose<barOpen;
 for(int i=0;i<LOOKAHEAD_SLOTS;i++){
  if(!la_active[i])continue;
  if(barTime<=la_sig[i])continue; // only bars strictly after the signal bar
  la_totalCount[i]++;
  if(bearBar)la_bearCount[i]++;
  if(la_totalCount[i]>=5){
   Log("NEXT5_AFTER_SIGNAL","sig="+TimeToString(la_sig[i])+" sd="+(la_sd[i]==1?"BULL":"BEAR")+
       " touch="+(la_bodyTouch[i]?"BODY":"WICK")+" bearCount="+IntegerToString(la_bearCount[i])+"/5");
   // Write the result back into any still-pending Setup for this same signal
   // (a fast setup that already entered and left S[] just won't see this --
   // SkipIfNext5Bearish can only ever act when next5Ready is true at entry).
   for(int k=0;k<ArraySize(S);k++){
    if(S[k].sig==la_sig[i]){ S[k].next5BearCount=la_bearCount[i]; S[k].next5Ready=true; }
   }
   la_active[i]=false;
  }
 }
}

bool protection_armed=false;
bool managed_partial=false;
datetime tracked_entry_time=0;
double tracked_entry=0,tracked_R=0,tracked_sigclose=0;
int tracked_dir=0;
double trail_stop_level=0;    // UseTrailingStop: current trailing SL level post-partial (0 = not yet moved)
bool   trail_tp_armed=false;  // UseTrailingTP: final TP cap removed, now trailing via SL
double trail_tp_stop_level=0; // UseTrailingTP: current trailing SL level once armed (0 = not yet moved)

string GVKey(string name){
 return "LIVE007_"+IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN))+"_"+_Symbol+"_"+
        IntegerToString((int)MagicNumber)+"_"+name;
}
void SaveTrack(){
 GlobalVariableSet(GVKey("ENTRY_TIME"),(double)tracked_entry_time);
 GlobalVariableSet(GVKey("ENTRY"),tracked_entry);
 GlobalVariableSet(GVKey("R"),tracked_R);
 GlobalVariableSet(GVKey("SIGCLOSE"),tracked_sigclose);
 GlobalVariableSet(GVKey("DIR"),(double)tracked_dir);
 GlobalVariableSet(GVKey("PROTECTED"),protection_armed?1.0:0.0);
 GlobalVariableSet(GVKey("PARTIAL"),managed_partial?1.0:0.0);
 GlobalVariableSet(GVKey("TRAILTPARMED"),trail_tp_armed?1.0:0.0);
 GlobalVariablesFlush();
}
bool LoadTrack(){
 if(!GlobalVariableCheck(GVKey("R")))return false;
 tracked_entry_time=(datetime)GlobalVariableGet(GVKey("ENTRY_TIME"));
 tracked_entry=GlobalVariableGet(GVKey("ENTRY"));
 tracked_R=GlobalVariableGet(GVKey("R"));
 tracked_sigclose=GlobalVariableGet(GVKey("SIGCLOSE"));
 tracked_dir=(int)GlobalVariableGet(GVKey("DIR"));
 protection_armed=GlobalVariableGet(GVKey("PROTECTED"))>0.5;
 managed_partial=GlobalVariableGet(GVKey("PARTIAL"))>0.5;
 trail_tp_armed=GlobalVariableCheck(GVKey("TRAILTPARMED")) && GlobalVariableGet(GVKey("TRAILTPARMED"))>0.5;
 return tracked_entry_time>0 && tracked_entry>0 && tracked_R>0 && (tracked_dir==1||tracked_dir==-1);
}
void ClearTrack(){
 string names[]={"ENTRY_TIME","ENTRY","R","SIGCLOSE","DIR","PROTECTED","PARTIAL","TRAILTPARMED"};
 for(int i=0;i<ArraySize(names);i++)GlobalVariableDel(GVKey(names[i]));
}
bool TradeResultOK(){
 uint rc=trade.ResultRetcode();
 return rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_DONE_PARTIAL ||
        rc==TRADE_RETCODE_PLACED || rc==TRADE_RETCODE_NO_CHANGES;
}

void DS(int i){int n=ArraySize(S);for(int j=i;j<n-1;j++)S[j]=S[j+1];ArrayResize(S,n-1);}
bool OwnPosition(ulong &ticket){
 for(int i=PositionsTotal()-1;i>=0;i--){
  ulong t=PositionGetTicket(i);
  if(t>0 && PositionSelectByTicket(t) &&
     PositionGetString(POSITION_SYMBOL)==_Symbol &&
     (long)PositionGetInteger(POSITION_MAGIC)==MagicNumber){ticket=t;return true;}
 }
 return false;
}
void ResetTrack(){protection_armed=false;managed_partial=false;tracked_entry_time=0;tracked_entry=tracked_R=tracked_sigclose=0;tracked_dir=0;
 trail_stop_level=0;trail_tp_armed=false;trail_tp_stop_level=0;}

void NewBar(){
 datetime q=iTime(_Symbol,PERIOD_M10,0); if(!q||q==lastbar)return; lastbar=q;
 datetime st=iTime(_Symbol,PERIOD_M10,1);
 double o=iOpen(_Symbol,PERIOD_M10,1),h=iHigh(_Symbol,PERIOD_M10,1),l=iLow(_Symbol,PERIOD_M10,1),c=iClose(_Symbol,PERIOD_M10,1);
 CheckLookaheads(st,o,c); // every bar, regardless of whether THIS bar is itself a new signal
 UpdateSupplyZones(st,h,l);
 double u20[1],d20[1],u4[1],d4[1];
 if(CopyBuffer(h20,1,1,1,u20)!=1||CopyBuffer(h20,2,1,1,d20)!=1||
    CopyBuffer(h4,1,1,1,u4)!=1||CopyBuffer(h4,2,1,1,d4)!=1)return;
 bool bull=c>o&&h>=u20[0]&&h>=u4[0], bear=c<o&&l<=d20[0]&&l<=d4[0];
 if(!bull&&!bear)return;

 if(UseStochFadeConfirm){
  double kbuf[1];
  if(CopyBuffer(hStoch,0,1,1,kbuf)!=1){ Log("STOCH_FAIL","no stochastic value"); return; }
  double stochK=kbuf[0];
  bool fadeConfirmed=bull?(stochK>=StochOverbought):(stochK<StochOversold);
  if(!fadeConfirmed){
   Log("SIGNAL_SKIPPED","fade not confirmed by Stochastic: stochK="+DoubleToString(stochK,2)+" dir="+(bull?"BULL":"BEAR"));
   return;
  }
 }

 double R=MathAbs(c-o);if(R<=0)return;
 double minR=MathMax(_Point,MinR_Points*_Point);
 if(R<=minR){ Log("SIGNAL_SKIPPED","R too small ("+DoubleToString(R,_Digits)+" <= "+DoubleToString(minR,_Digits)+") by MinR_Points="+IntegerToString(MinR_Points)); return; }
 bool bodyTouch=bull?(c>=u20[0]):(c<=d20[0]);
 int sd=bull?1:-1;

 // Consecutive same-direction signal streak (SkipEarlySignalsInStreak ACTS):
 // user's chart observation -- in a strong trend, the FIRST BB signal in a
 // same-direction run tends to get run over (stopped out), while a LATER
 // one in the same run (closer to real exhaustion) works better. Counts
 // how many M10 signals in a row have fired in the same direction, reset
 // to 1 whenever the direction flips.
 if(sd==g_lastSignalSd) g_consecSignalCount++;
 else { g_consecSignalCount=1; g_lastSignalSd=sd; }
 Log("SIGNAL_STREAK","sd="+(bull?"BULL":"BEAR")+" count="+IntegerToString(g_consecSignalCount));
 if(SkipEarlySignalsInStreak && g_consecSignalCount<EntryFromNthSignal){
  Log("SIGNAL_SKIPPED","streak count="+IntegerToString(g_consecSignalCount)+" < EntryFromNthSignal="+
      IntegerToString(EntryFromNthSignal)+" by SkipEarlySignalsInStreak=true");
  StartLookahead(st,sd,bodyTouch); // NEXT5 diagnostic still tracks every signal, traded or not
  return;
 }

 // H1 trend-against check, evaluated NOW (at signal time), using the two H1
 // bars immediately preceding the one currently in progress -- i.e. shift 1
 // and shift 2, both fully closed, never the still-forming shift 0 bar.
 // Fixed here and carried with the setup, not re-evaluated at the later
 // entry time (which can be hours/days after the signal, after the
 // extension+pullback sequence completes).
 int entryDir=-(bull?1:-1); // the eventual (countertrend) entry direction
 double h1o1=iOpen(_Symbol,PERIOD_H1,1),h1c1=iClose(_Symbol,PERIOD_H1,1);
 double h1o2=iOpen(_Symbol,PERIOD_H1,2),h1c2=iClose(_Symbol,PERIOD_H1,2);
 bool h1_1_bear=h1c1<h1o1, h1_2_bear=h1c2<h1o2;
 bool h1_1_bull=h1c1>h1o1, h1_2_bull=h1c2>h1o2;
 bool h1Against=(entryDir==1) ? (h1_1_bear&&h1_2_bear) : (h1_1_bull&&h1_2_bull);
 Log("H1_TREND_CHECK","entryDir="+(entryDir==1?"BUY":"SELL")+" h1Against="+(h1Against?"true":"false")+
     " h1bar1="+(h1_1_bear?"BEAR":(h1_1_bull?"BULL":"FLAT"))+
     " h1bar2="+(h1_2_bear?"BEAR":(h1_2_bull?"BULL":"FLAT")));

 if(LatestSignalOnly && ArraySize(S)>0){
  Log("SIGNAL_SUPERSEDES","dropping "+IntegerToString(ArraySize(S))+" pending setup(s) for newer signal");
  ArrayResize(S,0);
 }
 int n=ArraySize(S);ArrayResize(S,n+1);
 S[n].sig=st;S[n].ct=st+PeriodSeconds(PERIOD_M10);S[n].exp=S[n].ct+MaxExtensionHours*3600;
 S[n].sd=bull?1:-1;S[n].R=R;S[n].o=o;S[n].h=h;S[n].l=l;S[n].c=c;S[n].extreme=c;S[n].ext=false;
 S[n].bodyTouch=bodyTouch;
 S[n].h1Against=h1Against;
 S[n].next5BearCount=-1;S[n].next5Ready=false;
 StartLookahead(st,S[n].sd,bodyTouch);
 Log("SIGNAL",(bull?"BULL":"BEAR")+" R="+DoubleToString(R,2)+" touch="+(bodyTouch?"BODY":"WICK"));
}

// Friday day_of_week==5 in MQL5 (0=Sunday...6=Saturday), server time.
bool IsFridayNightCutoff(datetime t){
 MqlDateTime dt; TimeToStruct(t,dt);
 return (dt.day_of_week==5 && dt.hour>=FridayNightCutoffHour);
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

// KST = server time + 6h (EU DST) or +7h (otherwise), same convention as the 001_STOCH family.
void KST_HourDow(datetime server_now,int &hour,int &dow)
{
   int offsetHours=IsEUDST(server_now)?6:7;
   MqlDateTime t; TimeToStruct(server_now+offsetHours*3600,t);
   hour=t.hour; dow=t.day_of_week; // 0=Sunday...6=Saturday
}

// -- 매물대 (supply/demand zone) tracking, ported verbatim from 001 M2_v2 --
int KSTDayIndex(datetime server_now)
{
   int offsetHours=IsEUDST(server_now)?6:7;
   datetime kst=server_now+offsetHours*3600;
   return (int)(kst/86400);
}

bool InWindowKST(int minOfDay,double startHour,double endHour)
{
   int start=(int)MathRound(startHour*60);
   int end=(int)MathRound(endHour*60);
   if(start<=end) return (minOfDay>=start && minOfDay<end);
   return (minOfDay>=start || minOfDay<end); // wraps past midnight
}

// Called once per new signal-timeframe bar with that bar's own high/low --
// rolls today's running high/low into "previous day" at KST midnight,
// captures the Asia/NY session opening-hour boxes the first time each
// day's clock reaches them, and finalizes the previous NY-session-window
// high/low the moment that window closes.
void UpdateSupplyZones(datetime sig,double h,double l)
{
   int kstHour,kstDow; KST_HourDow(sig,kstHour,kstDow);
   int day=KSTDayIndex(sig);
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

   if(!g_szAsiaBoxSet && kstHour==AsiaOpenHourKST)
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
// (999.0 = no enabled zone has a value yet).
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

// Looks up the realized profit (profit+swap+commission across all deals)
// for a position ticket that has already closed, via deal history.
double GetClosedPositionProfit(ulong posTicket)
{
   double profit=0;
   if(!HistorySelectByPosition(posTicket)) return profit;
   int total=HistoryDealsTotal();
   for(int i=0;i<total;i++)
   {
      ulong dt=HistoryDealGetTicket(i);
      if(dt==0) continue;
      profit+=HistoryDealGetDouble(dt,DEAL_PROFIT)+HistoryDealGetDouble(dt,DEAL_SWAP)+HistoryDealGetDouble(dt,DEAL_COMMISSION);
   }
   return profit;
}

// -- Friday narrow-window filter, ported from XAU_M2_BB_LIVE_001_STOCH_v2
//    (CONFIRMED there: NET +10.6% vs baseline, +$202.40 vs an all-day
//    Friday block, same WR/MaxDD, on the 001 M2 signal). Only allow entries
//    in 10:30-15:00 KST on Friday; every other day is unaffected. REJECTED
//    on this M10 extension/pullback signal, which already has its own
//    confirmed SkipFridayNightEntry (weekend-gap) and SkipTuesdayEntry
//    (worst day here is Tuesday, not Friday) findings: ground-truth
//    backtest against this file's own baseline (NET $16,946.22, WR
//    91.26%, PF 2.556, MaxDD $1,282.60, n=618) gave NET $14,245.31
//    (-15.9%), WR 91.78%, PF 2.701, MaxDD unchanged at $1,282.60, n=499.
//    Per-trade quality ticks up slightly (WR/PF) but total $ output drops
//    substantially from the lost volume, and the identical MaxDD shows
//    this file's worst drawdown sequence doesn't involve Friday either
//    way -- redundant with/dominated by the existing Tuesday and
//    Friday-night findings. --------------------------------------------
bool InFridayNarrowAllowedWindowKST(datetime server_now)
{
   int kstHour,kstDow; KST_HourDow(server_now,kstHour,kstDow);
   if(kstDow!=5) return true; // not Friday
   int offsetHours=IsEUDST(server_now)?6:7;
   MqlDateTime t; TimeToStruct(server_now+offsetHours*3600,t);
   int minOfDay=t.hour*60+t.min;
   return (minOfDay>=630 && minOfDay<900); // 10:30-15:00
}

bool SendEntry(int i,MqlTick &tk){
 ulong old; if(OwnPosition(old)){DS(i);return false;} // strict own-Magic MAX1; consume setup
 int dir=-S[i].sd; double R=S[i].R;
 if(dir==-1 && !AllowShort){
  Log("SIGNAL_SKIPPED","SELL disabled by AllowShort=false (data-driven direction filter)");
  DS(i);return false;
 }

 // Friday-night weekend-gap filter (SkipFridayNightEntry ACTS): root cause
 // found in the ~50-hour "slow bleed" losses -- all were Friday-night entries
 // that sat over the closed weekend and got stopped right at Monday reopen.
 datetime nowT=(datetime)(tk.time_msc/1000);
 bool fridayNight=IsFridayNightCutoff(nowT);
 Log("FRIDAY_NIGHT_CHECK","fridayNight="+(fridayNight?"true":"false")+" now="+TimeToString(nowT));
 if(fridayNight && SkipFridayNightEntry){
  Log("SIGNAL_SKIPPED","Friday >= "+IntegerToString(FridayNightCutoffHour)+
      ":00 server time (weekend-gap risk) by SkipFridayNightEntry=true");
  DS(i);return false;
 }

 // Day-of-week / hour-of-day dip filters (SkipTuesdayEntry/SkipHourAEntry/
 // SkipHourBEntry ACT): found via a KST day-of-week and 2h-bucket breakdown
 // of the confirmed-default backtest -- see header for the numbers.
 int kstHour,kstDow; KST_HourDow(nowT,kstHour,kstDow);
 bool isTuesday=(kstDow==2); // MQL5 day_of_week: 0=Sunday...6=Saturday
 bool inHourA=(kstHour>=SkipHourAStartKST && kstHour<SkipHourAEndKST);
 bool inHourB=(kstHour>=SkipHourBStartKST && kstHour<SkipHourBEndKST);
 Log("DOW_HOUR_CHECK","kstDow="+IntegerToString(kstDow)+" kstHour="+IntegerToString(kstHour)+
     " isTuesday="+(isTuesday?"true":"false")+" inHourA="+(inHourA?"true":"false")+
     " inHourB="+(inHourB?"true":"false"));
 if(isTuesday && SkipTuesdayEntry){
  Log("SIGNAL_SKIPPED","Tuesday KST (ground-truth: only NET-negative day) by SkipTuesdayEntry=true");
  DS(i);return false;
 }
 if(inHourA && SkipHourAEntry){
  Log("SIGNAL_SKIPPED","KST hour in ["+IntegerToString(SkipHourAStartKST)+","+IntegerToString(SkipHourAEndKST)+") by SkipHourAEntry=true");
  DS(i);return false;
 }
 if(inHourB && SkipHourBEntry){
  Log("SIGNAL_SKIPPED","KST hour in ["+IntegerToString(SkipHourBStartKST)+","+IntegerToString(SkipHourBEndKST)+") by SkipHourBEntry=true");
  DS(i);return false;
 }
 if(UseFridayNarrowWindow && !InFridayNarrowAllowedWindowKST(nowT)){
  Log("SIGNAL_SKIPPED","Entry blocked by UseFridayNarrowWindow (Friday, outside 10:30-15:00 KST)");
  DS(i);return false;
 }

 // H1 trend-against filter (SkipIfH1TrendAgainst/SkipIfH1NotAgainst ACT):
 // by default h1Against was fixed at signal time (see NewBar()), using the
 // two H1 bars immediately preceding the one in progress when the M10 signal
 // appeared. H1CheckAtEntryTime=true instead reproduces the earlier, more
 // profitable version: shift 0 (in progress) + shift 1 (last closed),
 // re-evaluated NOW since entry can happen hours/days after the signal.
 bool h1Against=S[i].h1Against;
 if(H1CheckAtEntryTime){
  double eh1o0=iOpen(_Symbol,PERIOD_H1,0),eh1c0=iClose(_Symbol,PERIOD_H1,0);
  double eh1o1=iOpen(_Symbol,PERIOD_H1,1),eh1c1=iClose(_Symbol,PERIOD_H1,1);
  bool eh1_0_bear=eh1c0<eh1o0, eh1_1_bear=eh1c1<eh1o1;
  bool eh1_0_bull=eh1c0>eh1o0, eh1_1_bull=eh1c1>eh1o1;
  h1Against=(dir==1) ? (eh1_0_bear&&eh1_1_bear) : (eh1_0_bull&&eh1_1_bull);
 }
 if(h1Against && SkipIfH1TrendAgainst){
  Log("SIGNAL_SKIPPED","H1 trend against entry direction (both current+previous H1 bars) by SkipIfH1TrendAgainst=true");
  DS(i);return false;
 }
 if(!h1Against && SkipIfH1NotAgainst){
  Log("SIGNAL_SKIPPED","H1 trend NOT against entry direction (ground-truth: H1OK bucket was net negative) by SkipIfH1NotAgainst=true");
  DS(i);return false;
 }

 // NEXT5_AFTER_SIGNAL filter (SkipIfNext5Bearish ACTS): only ever applies
 // when next5Ready is true, i.e. the 5 M10 bars after the signal already
 // closed by the time this setup is ready to enter (fast setups still get
 // no filtering at all here, by construction).
 Log("NEXT5_CHECK","ready="+(S[i].next5Ready?"true":"false")+
     " bearCount="+(S[i].next5Ready?IntegerToString(S[i].next5BearCount)+"/5":"n/a"));
 if(S[i].next5Ready && S[i].next5BearCount>=Next5BearThreshold && SkipIfNext5Bearish){
  Log("SIGNAL_SKIPPED","next5BearCount="+IntegerToString(S[i].next5BearCount)+"/5 >= threshold "+
      IntegerToString(Next5BearThreshold)+" by SkipIfNext5Bearish=true");
  DS(i);return false;
 }

 double entry=(dir==1?tk.ask:tk.bid);
 {
    double atrDiag[1];
    g_entryZoneDistATR=(CopyBuffer(hATR_Sig,0,1,1,atrDiag)==1) ? DistanceToNearestZone(entry,atrDiag[0]) : 999.0;
 }
 double sl=entry-dir*InitialSL_R*R;
 double finaltp=entry+dir*SignalOppositeTP_R*R;
 string tag="LIVE007_P05P10"+(S[i].bodyTouch?"_BODY":"_WICK")+(h1Against?"_H1AGAINST":"_H1OK");
 trade.SetExpertMagicNumber(MagicNumber);
 trade.SetTypeFillingBySymbol(_Symbol);
 bool ok=false;
 if(EnableLiveOrders){
  ok=(dir==1)?trade.Buy(Lots,_Symbol,0,sl,finaltp,tag)
             :trade.Sell(Lots,_Symbol,0,sl,finaltp,tag);
 }else{
  Log("DRY_ENTRY",(dir==1?"BUY":"SELL")+" entry~"+DoubleToString(entry,_Digits)+
      " R="+DoubleToString(R,2)+" SL="+DoubleToString(sl,_Digits)+" finalTP="+DoubleToString(finaltp,_Digits));
  DS(i);return false;
 }
 if(!ok){Log("ORDER_FAIL","retcode="+IntegerToString((int)trade.ResultRetcode())+" "+trade.ResultRetcodeDescription());DS(i);return false;}
 ulong t;
 if(OwnPosition(t)&&PositionSelectByTicket(t)){
  tracked_entry=PositionGetDouble(POSITION_PRICE_OPEN);
  tracked_entry_time=(datetime)PositionGetInteger(POSITION_TIME);
  tracked_ticket=t;
 }else{tracked_entry=entry;tracked_entry_time=(datetime)(tk.time_msc/1000);}
 tracked_R=R;tracked_sigclose=S[i].c;tracked_dir=dir;protection_armed=false;managed_partial=false;
 trail_stop_level=0;trail_tp_armed=false;trail_tp_stop_level=0;
 SaveTrack();
 Log("ENTRY_OK",(dir==1?"BUY":"SELL")+" entry="+DoubleToString(tracked_entry,_Digits)+
     " R="+DoubleToString(R,2)+" lots="+DoubleToString(Lots,2)+" sig="+TimeToString(S[i].sig)+
     " zoneDistATR="+(g_entryZoneDistATR>=999.0?"n/a":DoubleToString(g_entryZoneDistATR,3)));
 DS(i);return true;
}

void ManageSetups(MqlTick &tk){
 datetime now=(datetime)(tk.time_msc/1000);
 for(int i=ArraySize(S)-1;i>=0;i--){
  if(now<S[i].ct)continue;
  double px=S[i].sd==1?tk.bid:tk.ask;
  if(!S[i].ext){
   if(now>S[i].exp){DS(i);continue;}
   double ext=S[i].c+S[i].sd*ExtensionR*S[i].R;
   if(S[i].sd==1?px>=ext:px<=ext){S[i].ext=true;S[i].extreme=px;S[i].exp=now+MaxPullbackHours*3600;Log("EXT_HIT");}
  }else{
   if(now>S[i].exp){DS(i);continue;}
   if(S[i].sd==1&&px>S[i].extreme)S[i].extreme=px;
   if(S[i].sd==-1&&px<S[i].extreme)S[i].extreme=px;
   double tr=S[i].extreme-S[i].sd*PullbackR*S[i].R;
   if(S[i].sd==1?px<=tr:px>=tr){Log("PB_CONFIRM");SendEntry(i,tk);}
  }
 }
}

void ManageOwn(MqlTick &tk){
 ulong ticket;
 if(!OwnPosition(ticket)){
  if(tracked_entry_time!=0){
   // Position closed (SL/TP/manual) since the last tick -- log the matching
   // zoneDistATR outcome line, same diagnostic as 001/005, before clearing
   // the tracked state. No OnTradeTransaction hook in this EA, so this is
   // the only point it fires.
   double profit=GetClosedPositionProfit(tracked_ticket);
   Log("MANAGED_EXIT",(tracked_dir==1?"BUY":"SELL")+" ticket="+IntegerToString((int)tracked_ticket)+
       " entry="+DoubleToString(tracked_entry,_Digits)+" profit="+DoubleToString(profit,2)+
       " zoneDistATR="+(g_entryZoneDistATR>=999.0?"n/a":DoubleToString(g_entryZoneDistATR,3))+
       " trailStopLevel="+DoubleToString(trail_stop_level,_Digits)+
       " trailTPArmed="+(trail_tp_armed?"true":"false")+
       " trailTPStopLevel="+DoubleToString(trail_tp_stop_level,_Digits));
   g_entryZoneDistATR=999.0; tracked_ticket=0;
   ClearTrack();ResetTrack();
  }
  return;
 }
 tracked_ticket=ticket;
 if(!PositionSelectByTicket(ticket))return;

 int dir=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?1:-1;
 double entry=PositionGetDouble(POSITION_PRICE_OPEN);
 double vol=PositionGetDouble(POSITION_VOLUME);

 if(tracked_entry_time==0){
  // Restart/re-attach recovery. Prefer the exact state saved at entry.
  if(LoadTrack() && tracked_dir==dir && MathAbs(tracked_entry-entry)<=MathMax(_Point*10,0.02)){
   Log("RECOVERY_OK","saved state restored | entry="+DoubleToString(tracked_entry,_Digits)+
       " R="+DoubleToString(tracked_R,2)+" protected="+(protection_armed?"YES":"NO")+
       " partial="+(managed_partial?"YES":"NO"));
  }else{
   // Fallback for positions opened by older builds: infer R from the current SL.
   tracked_entry_time=(datetime)PositionGetInteger(POSITION_TIME);
   tracked_entry=entry; tracked_dir=dir;
   double sl=PositionGetDouble(POSITION_SL);
   bool initial_sl=(sl>0 && (dir==1?sl<entry:sl>entry));
   bool locked_sl=(sl>0 && (dir==1?sl>entry:sl<entry));
   if(initial_sl)tracked_R=MathAbs(entry-sl)/InitialSL_R;
   else if(locked_sl){tracked_R=MathAbs(sl-entry)/ProtectR;protection_armed=true;}
   if(tracked_R<=0){
    Log("RECOVERY_FAILED","R cannot be reconstructed; manual management required.");
    return;
   }
   double vstep=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   managed_partial=(vol<Lots-vstep/2.0);
   SaveTrack();
   Log("RECOVERY_FALLBACK_OK","R="+DoubleToString(tracked_R,2)+
       " protected="+(protection_armed?"YES":"NO")+" partial="+(managed_partial?"YES":"NO"));
  }
 }

 datetime now=(datetime)(tk.time_msc/1000);
 if(now>tracked_entry_time+MaxPositionHours*3600){
  if(EnableLiveOrders && trade.PositionClose(ticket))Log("TIMEOUT_CLOSE");
  return;
 }
 if(tracked_R<=0)return;

 double px=dir==1?tk.bid:tk.ask;
 double protect_trigger=tracked_entry+dir*ProtectTriggerR*tracked_R;
 double partial_trigger=tracked_entry+dir*PartialTriggerR*tracked_R;
 double lock=tracked_entry+dir*ProtectR*tracked_R;

 // Stage 1: once +0.5R is reached, protect the WHOLE 0.02 position at +0.25R.
 if(!protection_armed){
  bool reached05=dir==1?px>=protect_trigger:px<=protect_trigger;
  if(!reached05)return;

  if(!EnableLiveOrders){
   Log("DRY_PROTECT","+0.5R reached; would move whole-position SL to +0.25R");
   protection_armed=true;
  }else{
   trade.SetExpertMagicNumber(MagicNumber);
   double tp=PositionGetDouble(POSITION_TP);
   if(!trade.PositionModify(ticket,lock,tp) || !TradeResultOK()){
    Log("PROTECT_MODIFY_FAILED",IntegerToString((int)trade.ResultRetcode())+" "+trade.ResultRetcodeDescription());
    return; // retry on later ticks; do not mark armed until broker accepts it
   }
   protection_armed=true;
   SaveTrack();
   Log("PROTECT_ARMED","+0.5R reached; whole SL="+DoubleToString(lock,_Digits)+
       " | volume="+DoubleToString(vol,2));
  }
 }

 // Stage 2: at +1.0R, close half (0.01 from 0.02). Runner keeps +0.25R SL
 // (or continuous trailing instead, if UseTrailingStop/UseTrailingTP enabled).
 if(!managed_partial){
  bool reached10=dir==1?px>=partial_trigger:px<=partial_trigger;
  if(!reached10)return;

  double vmin=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
  double vstep=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
  double half=MathFloor((vol/2.0)/vstep+1e-8)*vstep;
  if(half<vmin)half=vmin;
  double remain=vol-half;
  if(remain+1e-8<vmin){
   Log("PARTIAL_IMPOSSIBLE","volume="+DoubleToString(vol,2));
   return;
  }

  if(!EnableLiveOrders){
   Log("DRY_PARTIAL","+1.0R reached; would close "+DoubleToString(half,2)+
       " and keep runner SL +0.25R");
   managed_partial=true;
   return;
  }

  trade.SetExpertMagicNumber(MagicNumber);
  double before_vol=vol;
  if(!trade.PositionClosePartial(ticket,half) || !TradeResultOK()){
   Log("PARTIAL_FAILED",IntegerToString((int)trade.ResultRetcode())+" "+trade.ResultRetcodeDescription());
   return;
  }

  // IMPORTANT: on a hedging account the remaining position may no longer be
  // selectable by the original ticket immediately after a partial close.
  // Mark the partial as completed FIRST, before any verification lookup, so a
  // flaky/delayed re-select on this tick can never let this block re-fire on
  // the next tick and send a second, unintended close against the runner.
  managed_partial=true;
  SaveTrack();

  // Re-find the surviving own-Magic position instead of assuming the old ticket survives.
  ulong runner_ticket=0;
  if(!OwnPosition(runner_ticket) || !PositionSelectByTicket(runner_ticket)){
   Log("PARTIAL_VERIFY_FAILED","close request accepted but runner not found; check account history.");
   return;
  }

  double tp=PositionGetDouble(POSITION_TP);
  double runner_vol=PositionGetDouble(POSITION_VOLUME);
  if(runner_vol>=before_vol-vstep/2.0){
   Log("PARTIAL_VERIFY_FAILED","volume unchanged at "+DoubleToString(runner_vol,2)+
       " | retcode="+IntegerToString((int)trade.ResultRetcode())+" "+trade.ResultRetcodeDescription());
   return;
  }

  // A partial close inherits the position's existing SL/TP. Re-sending the same
  // stops can be rejected as INVALID_STOPS when price is close to TP, so verify
  // the inherited protection instead of submitting a redundant modification.
  double runner_sl=PositionGetDouble(POSITION_SL);
  bool lock_kept=(runner_sl>0 && (dir==1?runner_sl>=lock-_Point:runner_sl<=lock+_Point));
  if(!lock_kept){
   Log("RUNNER_PROTECTION_WARNING","inherited SL="+DoubleToString(runner_sl,_Digits)+
       " expected="+DoubleToString(lock,_Digits)+" | manual check required");
   return;
  }

  Log("PARTIAL_OK","closed="+DoubleToString(half,2)+
      " runner="+DoubleToString(runner_vol,2)+
      " inherited_lock="+DoubleToString(runner_sl,_Digits)+
      " finalTP="+DoubleToString(tp,_Digits));
  return;
 }

 // -- post-partial continuous trailing on the runner (only reached once
 //    managed_partial=true, i.e. the partial close already completed) --
 if(!UseTrailingStop && !UseTrailingTP) return;

 if(UseTrailingTP && !trail_tp_armed)
 {
    double curSLforArm=PositionGetDouble(POSITION_SL);
    if(!EnableLiveOrders)
    {
       trail_tp_armed=true;
       Log("TRAIL_TP_ARM_DRY","would remove final TP cap and start trailing (EnableLiveOrders=false)");
    }
    else if(trade.PositionModify(ticket,curSLforArm,0.0) && TradeResultOK())
    {
       trail_tp_armed=true;
       SaveTrack();
       Log("TRAIL_TP_ARMED","final TP cap removed, now trailing");
    }
 }

 bool tpRemoved=trail_tp_armed;
 if(!UseTrailingStop && !tpRemoved) return; // TrailingTP not armed yet, TrailingStop off: nothing to do this tick

 double distanceR=(tpRemoved ? TrailTPDistanceR : TrailStopDistanceR);
 double candidateSL=NormalizeDouble(px-dir*distanceR*tracked_R,_Digits);
 double curSL=PositionGetDouble(POSITION_SL);
 bool improves=(curSL==0) || (dir==1 ? candidateSL>curSL : candidateSL<curSL);
 if(!improves) return;

 double desiredTP=(tpRemoved ? 0.0 : PositionGetDouble(POSITION_TP));
 if(!EnableLiveOrders)
 {
    Log(tpRemoved?"TRAIL_TP_STOP_DRY":"TRAIL_STOP_DRY","would move SL->"+DoubleToString(candidateSL,_Digits)+
        " (EnableLiveOrders=false)");
    return;
 }
 if(trade.PositionModify(ticket,candidateSL,desiredTP) && TradeResultOK())
 {
    if(tpRemoved) trail_tp_stop_level=candidateSL; else trail_stop_level=candidateSL;
    Log(tpRemoved?"TRAIL_TP_STOP_MOVED":"TRAIL_STOP_MOVED","SL->"+DoubleToString(candidateSL,_Digits));
 }
}
int OnInit(){
 if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING){
  Print("LIVE007 INIT FAILED: HEDGING account required.");return INIT_FAILED;
 }
 h20=iBands(_Symbol,PERIOD_M10,20,0,2.0,PRICE_CLOSE);
 h4=iBands(_Symbol,PERIOD_M10,4,0,4.0,PRICE_OPEN);
 hATR_Sig=iATR(_Symbol,PERIOD_M10,ATRPeriod);
 hStoch=iStochastic(_Symbol,PERIOD_M10,StochK_Period,StochD_Period,StochSlowing,MODE_LWMA,STO_LOWHIGH);
 if(h20==INVALID_HANDLE||h4==INVALID_HANDLE||hATR_Sig==INVALID_HANDLE||hStoch==INVALID_HANDLE)return INIT_FAILED;
 trade.SetExpertMagicNumber(MagicNumber);

 f_log=FileOpen("XAU_M10_LIVE_007_BUYONLY_V2_LOG.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
 if(f_log!=INVALID_HANDLE)
 {
    FileSeek(f_log,0,SEEK_END);
    if(FileTell(f_log)==0) FileWrite(f_log,"TIME","EVENT","DETAIL");
 }

 Log("START","M10 | PB=0.10R | SL="+DoubleToString(InitialSL_R,2)+
     "R | LatestSignalOnly="+(LatestSignalOnly?"true":"false")+
     " | UseStochFadeConfirm="+(UseStochFadeConfirm?"true":"false")+" Stoch("+IntegerToString(StochK_Period)+","+
     IntegerToString(StochD_Period)+","+IntegerToString(StochSlowing)+") OB="+DoubleToString(StochOverbought,1)+
     " OS="+DoubleToString(StochOversold,1)+
     " | SkipIfH1TrendAgainst="+(SkipIfH1TrendAgainst?"true":"false")+
     " | SkipIfH1NotAgainst="+(SkipIfH1NotAgainst?"true":"false")+
     " | H1CheckAtEntryTime="+(H1CheckAtEntryTime?"true":"false")+
     " | Next5BearThreshold="+IntegerToString(Next5BearThreshold)+
     " SkipIfNext5Bearish="+(SkipIfNext5Bearish?"true":"false")+
     " | FridayNightCutoffHour="+IntegerToString(FridayNightCutoffHour)+
     " SkipFridayNightEntry="+(SkipFridayNightEntry?"true":"false")+
     " | EntryFromNthSignal="+IntegerToString(EntryFromNthSignal)+
     " SkipEarlySignalsInStreak="+(SkipEarlySignalsInStreak?"true":"false")+
     " | SkipTuesdayEntry="+(SkipTuesdayEntry?"true":"false")+
     " | SkipHourAStartKST="+IntegerToString(SkipHourAStartKST)+" SkipHourAEndKST="+IntegerToString(SkipHourAEndKST)+
     " SkipHourAEntry="+(SkipHourAEntry?"true":"false")+
     " | SkipHourBStartKST="+IntegerToString(SkipHourBStartKST)+" SkipHourBEndKST="+IntegerToString(SkipHourBEndKST)+
     " SkipHourBEntry="+(SkipHourBEntry?"true":"false")+
     " | UseFridayNarrowWindow="+(UseFridayNarrowWindow?"true":"false")+
     " | UseTrailingStop="+(UseTrailingStop?"true":"false")+" TrailStopDistanceR="+DoubleToString(TrailStopDistanceR,2)+
     " | UseTrailingTP="+(UseTrailingTP?"true":"false")+" TrailTPDistanceR="+DoubleToString(TrailTPDistanceR,2)+
     " | Lots="+DoubleToString(Lots,2)+
     " | Magic="+IntegerToString((int)MagicNumber)+" | orders="+(EnableLiveOrders?"ENABLED":"DRY")+
     " | ATRPeriod="+IntegerToString(ATRPeriod)+
     " UseAsiaBoxZone="+(UseAsiaBoxZone?"true":"false")+" AsiaOpenHourKST="+IntegerToString(AsiaOpenHourKST)+
     " UseNYBoxZone="+(UseNYBoxZone?"true":"false")+" NYOpenHourKST="+DoubleToString(NYOpenHourKST,2)+
     " UseTodayHighLowZone="+(UseTodayHighLowZone?"true":"false")+" UsePrevDayHighLowZone="+(UsePrevDayHighLowZone?"true":"false")+
     " UsePrevNYHighLowZone="+(UsePrevNYHighLowZone?"true":"false")+
     " NYSessionWindow="+DoubleToString(NYSessionStartHourKST,2)+"-"+DoubleToString(NYSessionEndHourKST,2)+"KST");
 Log("NOTE","EXIT: +0.5R whole-position SL -> +0.25R; +1.0R close half; runner +0.25R; final signal-close opposite 0.90R");
 Log("NOTE","zoneDistATR diagnostic ported from 001/005: logs distance (ATR units) from the actual entry fill to the nearest enabled 매물대 zone on every trade close (MANAGED_EXIT). Diagnostic only, does not block entries.");
 return INIT_SUCCEEDED;
}
void OnTick(){
 MqlTick tk;if(!SymbolInfoTick(_Symbol,tk))return;
 NewBar();
 ManageSetups(tk);   // same ordering principle as validator
 ManageOwn(tk);
}
void OnDeinit(const int reason){
 if(f_log!=INVALID_HANDLE){ FileFlush(f_log); FileClose(f_log); }
 if(h20!=INVALID_HANDLE)IndicatorRelease(h20);
 if(h4!=INVALID_HANDLE)IndicatorRelease(h4);
 if(hATR_Sig!=INVALID_HANDLE)IndicatorRelease(hATR_Sig);
 if(hStoch!=INVALID_HANDLE)IndicatorRelease(hStoch);
}
//+------------------------------------------------------------------+
