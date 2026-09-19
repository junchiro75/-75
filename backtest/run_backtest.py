#!/usr/bin/env python3
"""Run the 004/005/007 tick backtest over all monthly CSVs in backtest/data/.

Usage:
    python3 run_backtest.py [--data-dir DIR] [--results-dir DIR] [--capital N]
"""

import argparse
import os
import sys
import time as _time

import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from engine.data_loader import iter_month_files, load_month
from engine.runner import BacktestRunner
from engine import metrics as M


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data-dir', default=os.path.join(os.path.dirname(__file__), 'data'))
    ap.add_argument('--results-dir', default=os.path.join(os.path.dirname(__file__), 'results'))
    ap.add_argument('--capital', type=float, default=10000.0,
                     help='Initial capital used only for %% / MDD%% / Sharpe reporting; '
                          '$ P&L itself is independent of this (driven by the EAs\' fixed lot sizes).')
    args = ap.parse_args()

    os.makedirs(args.results_dir, exist_ok=True)

    files = list(iter_month_files(args.data_dir))
    if not files:
        print(f"No tick files found in {args.data_dir} (expected e.g. XAUUSD+_ticks_2025-01.csv)")
        return 1

    runner = BacktestRunner()
    t0 = _time.time()
    total_ticks = 0
    for path in files:
        print(f"[load] {os.path.basename(path)} ...", flush=True)
        df = load_month(path)
        n = len(df)
        total_ticks += n
        ts = df['ts'].to_numpy()
        bid = df['bid'].to_numpy()
        ask = df['ask'].to_numpy()
        runner.process_array(ts, bid, ask)
        elapsed = _time.time() - t0
        print(f"  -> {n:,} ticks processed (cumulative {total_ticks:,}, "
              f"{elapsed:,.1f}s elapsed, trades so far={len(runner.trades)})", flush=True)

    print(f"\nDone: {total_ticks:,} ticks in {_time.time()-t0:,.1f}s. "
          f"Total fills recorded: {len(runner.trades)}")

    df_all = M.trades_to_df(runner.trades)
    df_all.to_csv(os.path.join(args.results_dir, 'trades_all.csv'), index=False)

    rows = []
    for name in ['004', '005', '007']:
        sub = df_all[df_all['strategy'] == name] if not df_all.empty else df_all
        summary = M.summarize(sub, args.capital, name)
        rows.append(summary)
        sub.to_csv(os.path.join(args.results_dir, f'trades_{name}.csv'), index=False)

    portfolio = M.portfolio_summary(runner.trades, args.capital)
    rows.append(portfolio)

    report = pd.DataFrame(rows)
    report.to_csv(os.path.join(args.results_dir, 'summary.csv'), index=False)

    pd.set_option('display.width', 160)
    pd.set_option('display.max_columns', 30)
    print("\n=== SUMMARY ===")
    print(report.to_string(index=False))
    print(f"\nSaved: {args.results_dir}/summary.csv, trades_all.csv, trades_{{004,005,007}}.csv")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
