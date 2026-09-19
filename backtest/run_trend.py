#!/usr/bin/env python3
"""Run the Donchian/ATR trend-breakout tracker over all monthly tick files."""

import argparse
import os
import sys
import time as _time

import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from engine.data_loader import iter_month_files, load_month
from engine.trend_runner import TrendRunner, CONFIGS
from engine import metrics as M


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data-dir', default=os.path.join(os.path.dirname(__file__), 'data'))
    ap.add_argument('--results-dir', default=os.path.join(os.path.dirname(__file__), 'results_trend'))
    ap.add_argument('--capital', type=float, default=10000.0)
    ap.add_argument('--lots', type=float, default=0.01)
    ap.add_argument('--stop-atr-mult', type=float, default=2.0)
    args = ap.parse_args()
    os.makedirs(args.results_dir, exist_ok=True)

    files = list(iter_month_files(args.data_dir))
    if not files:
        print(f"No tick files found in {args.data_dir}")
        return 1

    runner = TrendRunner(stop_atr_mult=args.stop_atr_mult, lots=args.lots)
    t0 = _time.time()
    total_ticks = 0
    last_ts = last_bid = last_ask = None
    for path in files:
        print(f"[load] {os.path.basename(path)} ...", flush=True)
        df = load_month(path)
        n = len(df)
        total_ticks += n
        ts_arr = df['ts'].to_numpy(); bid_arr = df['bid'].to_numpy(); ask_arr = df['ask'].to_numpy()
        runner.process_array(ts_arr, bid_arr, ask_arr)
        last_ts, last_bid, last_ask = ts_arr[-1], bid_arr[-1], ask_arr[-1]
        elapsed = _time.time() - t0
        print(f"  -> {n:,} ticks (cumulative {total_ticks:,}, {elapsed:,.1f}s elapsed, "
              f"trades so far={len(runner.trades)})", flush=True)

    print(f"\nDone: {total_ticks:,} ticks in {_time.time()-t0:,.1f}s. Total fills: {len(runner.trades)}")

    # Mark-to-market any still-open position at the last available price so a
    # strategy that's mid-trend when the data ends isn't scored as if that
    # unrealized profit/loss never existed.
    for t in runner.trackers:
        tr = t['tracker']
        if tr.position is not None:
            px = last_bid if tr.position['dir'] == 1 else last_ask
            print(f"  marking-to-market open {t['label']} position at {px}")
            tr._close(last_ts, px, 'MARK_TO_MARKET', runner.trades)

    df_all = M.trades_to_df(runner.trades)
    df_all.to_csv(os.path.join(args.results_dir, 'trades_all.csv'), index=False)

    rows = []
    for label, secs, n1, n2 in CONFIGS:
        name = f'trend_{label}'
        sub = df_all[df_all['strategy'] == name] if not df_all.empty else df_all
        summary = M.summarize(sub, args.capital, name)
        summary['entry_n'] = n1
        summary['exit_n'] = n2
        summary['tf_seconds'] = secs
        rows.append(summary)
        sub.to_csv(os.path.join(args.results_dir, f'trades_{name}.csv'), index=False)

    report = pd.DataFrame(rows)
    report.to_csv(os.path.join(args.results_dir, 'summary_trend.csv'), index=False)

    pd.set_option('display.width', 200)
    pd.set_option('display.max_columns', 30)
    print("\n=== SUMMARY ===")
    cols = ['strategy', 'n_trades', 'net_pnl', 'total_return_pct', 'mdd_abs', 'mdd_pct',
            'win_rate_pct', 'profit_factor', 'sharpe', 'avg_hold_hours']
    print(report[cols].to_string(index=False))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
