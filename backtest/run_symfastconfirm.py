#!/usr/bin/env python3
"""Run the SYMMETRIC fast-confirm idea (bear->BUY and bull->SELL both
get next-bar confirmation, reintroducing SELL trades) over all monthly
tick files, for both 005-style (M2) and 007-style (M10) exit economics."""

import argparse
import os
import sys
import time as _time

import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from engine.data_loader import iter_month_files, load_month
from engine.symfastconfirm_runner import SymFastConfirmRunner
from engine import metrics as M


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data-dir', default=os.path.join(os.path.dirname(__file__), 'data'))
    ap.add_argument('--results-dir', default=os.path.join(os.path.dirname(__file__), 'results_symfastconfirm'))
    ap.add_argument('--capital', type=float, default=10000.0)
    args = ap.parse_args()
    os.makedirs(args.results_dir, exist_ok=True)

    files = list(iter_month_files(args.data_dir))
    if not files:
        print(f"No tick files found in {args.data_dir}")
        return 1

    runner = SymFastConfirmRunner()
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
    for name in ['005_symfastconfirm', '007_symfastconfirm']:
        sub = df_all[df_all['strategy'] == name] if not df_all.empty else df_all
        summary = M.summarize(sub, args.capital, name)
        rows.append(summary)
        sub.to_csv(os.path.join(args.results_dir, f'trades_{name}.csv'), index=False)

        # Direction breakdown (BUY vs SELL) to see which side the new SELL fast-path helps/hurts
        if not sub.empty:
            for d, label in [(1, 'BUY'), (-1, 'SELL')]:
                dsub = sub[sub['dir'] == d]
                if len(dsub):
                    print(f"  {name} {label}: n={len(dsub)} net_pnl=${dsub['net_pnl'].sum():.2f} "
                          f"win_rate={100*(dsub['net_pnl']>0).mean():.1f}%")

    report = pd.DataFrame(rows)
    report.to_csv(os.path.join(args.results_dir, 'summary_symfastconfirm.csv'), index=False)
    pd.set_option('display.width', 200)
    cols = ['strategy', 'n_trades', 'net_pnl', 'total_return_pct', 'mdd_abs', 'mdd_pct',
            'win_rate_pct', 'profit_factor', 'sharpe', 'avg_hold_hours']
    print("\n=== SUMMARY ===")
    print(report[cols].to_string(index=False))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
