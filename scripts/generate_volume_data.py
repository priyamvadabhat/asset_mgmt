"""
Synthetic volume-data generator for the scaling test (scenario 5).
Standard library only.   Usage:
    python scripts/generate_volume_data.py --txns 10000 100000 1000000
Writes data/volume/transactions_<N>.csv and positions_<N>.csv (~2% dirty rows,
~1% duplicate transaction ids, so the DQ rules are exercised at scale).
"""
import argparse, csv, os, random
from collections import defaultdict

SECURITIES = [f"SEC{i:03d}" for i in range(1, 10)]   # SEC001-009: valid for all Oct dates (SEC010 starts 2026-10-25)
DIRTY = ["", "SEC999"]                               # missing portfolio / unknown security

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--txns", type=int, nargs="+", default=[10_000])
    ap.add_argument("--out", default="data/volume")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    random.seed(42)                                  # reproducible

    for n in a.txns:
        portfolios = [f"PF{i:05d}" for i in range(1, max(10, n // 100) + 1)]
        qty = defaultdict(int)
        with open(f"{a.out}/transactions_{n}.csv", "w", newline="") as f:
            w = csv.writer(f)
            w.writerow(["transaction_id", "portfolio_id", "security_id", "trade_date",
                        "txn_type", "quantity", "price", "currency"])
            for i in range(1, n + 1):
                pf, sec = random.choice(portfolios), random.choice(SECURITIES)
                day = random.randint(1, 28)
                q = random.randint(1, 1000)
                row = [f"V{i}", pf, sec, f"2026-10-{day:02d}", "BUY", q,
                       round(random.uniform(5, 300), 2), "USD"]
                r = random.random()
                if r < 0.01:   row[1] = ""           # missing portfolio -> rejected
                elif r < 0.02: row[2] = "SEC999"     # unknown security  -> rejected
                else:          qty[(pf, sec)] += q   # position only reflects good rows
                w.writerow(row)
                if random.random() < 0.01:           # duplicate delivery of same id
                    w.writerow(row)
        with open(f"{a.out}/positions_{n}.csv", "w", newline="") as f:
            w = csv.writer(f)
            w.writerow(["portfolio_id", "security_id", "position_date", "quantity", "book_value", "currency"])
            for (pf, sec), q in qty.items():
                w.writerow([pf, sec, "2026-10-29", q, round(q * 100.0, 2), "USD"])
        print(f"generated {n} transactions, {len(qty)} positions")

if __name__ == "__main__":
    main()
