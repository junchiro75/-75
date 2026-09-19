#!/usr/bin/env python3
"""Run the 005-style/007-style logic across M1..H1 timeframes over all
monthly tick files, and dump per-(strategy,timeframe) metrics + trade logs."""

import argparse
import os
import sys
import time as _time

import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from engine.data_loader import iter_month_files, load_month
from engine.multi_tf_runner import MultiTFRunner, TIMEFRAMES
from engine import metrics as M


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data-dir', default=os.path.join(os.path.dirname(__file__), 'data'))
    ap.add_argument('--results-dir', default=os.path.join(os.path.dirname(__file__), 'results_multitf'))
    ap.add_argument('--capital', type=float, default=10000.0)
    args = ap.parse_args()
    os.makedirs(args.results_dir, exist_ok=True)

    files = list(iter_month_files(args.data_dir))
    if not files:
        print(f"No tick files found in {args.data_dir}")
        return 1

    runner = MultiTFRunner()
    t0 = _time.time()
    total_ticks = 0
    for path in files:
        print(f"[load] {os.path.basename(path)} ...", flush=True)
        df = load_month(path)
        n = len(df)
        total_ticks += n
        runner.process_array(df['ts'].to_numpy(), df['bid'].to_numpy(), df['ask'].to_numpy())
        elapsed = _time.time() - t0
        print(f"  -> {n:,} ticks (cumulative {total_ticks:,}, {elapsed:,.1f}s elapsed, "
              f"trades so far={len(runner.trades)})", flush=True)

    print(f"\nDone: {total_ticks:,} ticks in {_time.time()-t0:,.1f}s. Total fills: {len(runner.trades)}")

    df_all = M.trades_to_df(runner.trades)
    df_all.to_csv(os.path.join(args.results_dir, 'trades_all.csv'), index=False)

    rows = []
    for label, secs in TIMEFRAMES:
        for style in ['005', '007']:
            name = f'{style}_{label}'
            sub = df_all[df_all['strategy'] == name] if not df_all.empty else df_all
            summary = M.summarize(sub, args.capital, name)
            summary['style'] = style
            summary['timeframe'] = label
            summary['tf_seconds'] = secs
            rows.append(summary)
            sub.to_csv(os.path.join(args.results_dir, f'trades_{name}.csv'), index=False)

    report = pd.DataFrame(rows)
    report.to_csv(os.path.join(args.results_dir, 'summary_multitf.csv'), index=False)

    pd.set_option('display.width', 200)
    pd.set_option('display.max_columns', 30)
    print("\n=== SUMMARY BY TIMEFRAME ===")
    cols = ['strategy', 'n_trades', 'net_pnl', 'total_return_pct', 'mdd_abs', 'mdd_pct',
            'win_rate_pct', 'profit_factor', 'sharpe', 'avg_hold_hours']
    print(report[cols].to_string(index=False))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
