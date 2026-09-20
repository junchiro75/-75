#!/usr/bin/env python3
"""Parse an MT5 Strategy Tester XLSX report's Deals table into a clean
trade-level DataFrame (one row per closed position, paired from the in/out
deal records), using the exact realized MT5 P&L -- this is ground truth,
not a re-simulation.
"""
import argparse
import re
import sys

import openpyxl
import pandas as pd


def find_deals_start(ws):
    for i, row in enumerate(ws.iter_rows(min_row=1, max_row=ws.max_row, values_only=True), start=1):
        if row[0] == '거래':
            return i
    raise ValueError("Could not find '거래' (Deals) section header")


def parse_deals(path):
    wb = openpyxl.load_workbook(path, data_only=True)
    ws = wb[wb.sheetnames[0]]
    start = find_deals_start(ws)

    rows = []
    for row in ws.iter_rows(min_row=start + 2, max_row=ws.max_row, values_only=True):
        if row[0] is None:
            continue
        rows.append(row)

    # A position can close over MULTIPLE 'out' deals (partial + final, as in
    # 007's +1.0R half-close). Track remaining open volume so every 'out'
    # deal is kept as its own fill row -- dropping any of them silently
    # under-counts trades and corrupts the P&L total.
    trades = []
    pending = None
    for r in rows:
        time_, dealid, sym, side, dirn, vol, price, order, comm, swap, profit, bal, comment = r[:13]
        vol = float(vol) if vol is not None else 0.0
        if dirn == 'in':
            pending = {'entry_time': time_, 'entry_price': price, 'entry_side': side,
                       'entry_volume': vol, 'remaining': vol, 'commission_in': comm or 0.0,
                       'commission_in_charged': False}
        elif dirn == 'out' and pending is not None:
            pos_dir = 1 if pending['entry_side'] == 'buy' else -1
            gross = profit or 0.0
            comm_out = comm or 0.0
            swap_v = swap or 0.0
            # MT5 charges the round-turn commission on the entry ('in') deal;
            # attribute it to the FIRST fill only so a partial+final pair
            # sums to the same total commission as a single-fill trade.
            comm_this = (pending['commission_in'] if not pending['commission_in_charged'] else 0.0) + comm_out
            pending['commission_in_charged'] = True
            net = gross + comm_this + swap_v
            trades.append({
                'entry_time': pending['entry_time'], 'entry_price': pending['entry_price'],
                'volume': vol, 'dir': pos_dir,
                'exit_time': time_, 'exit_price': price, 'reason': comment,
                'gross_pnl': gross, 'commission': comm_this,
                'swap': swap_v, 'net_pnl': net, 'partial': pending['remaining'] > vol + 1e-9,
            })
            pending['remaining'] = round(pending['remaining'] - vol, 6)
            if pending['remaining'] <= 1e-6:
                pending = None
    df = pd.DataFrame(trades)
    df['entry_dt'] = pd.to_datetime(df['entry_time'], format='%Y.%m.%d %H:%M:%S')
    df['exit_dt'] = pd.to_datetime(df['exit_time'], format='%Y.%m.%d %H:%M:%S')
    df['hold_min'] = (df['exit_dt'] - df['entry_dt']).dt.total_seconds() / 60.0
    return df


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('xlsx')
    ap.add_argument('--out', default=None)
    args = ap.parse_args()
    df = parse_deals(args.xlsx)
    print(f"parsed {len(df)} trades")
    print(f"net_pnl total = {df['net_pnl'].sum():.2f}")
    print(f"gross_pnl total = {df['gross_pnl'].sum():.2f}")
    print(f"commission total = {df['commission'].sum():.2f}")
    print(f"win rate (net>0) = {(df['net_pnl']>0).mean()*100:.2f}%")
    if args.out:
        df.to_csv(args.out, index=False)
        print("saved to", args.out)


if __name__ == '__main__':
    sys.exit(main())
