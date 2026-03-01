"""
Fits the cost model factors from empirical measurements.

Cost model:
    T_transfer_in  = transfer_factor * input_bytes
    T_decode       = (plain_factor * num_values_plain + hybrid_factor * num_values_hybrid)
                     * (decompress_factor if compressed else 1.0)
    T_transfer_out = transfer_factor * output_bytes
    T_setup        = setup_factor * num_pages

    total_cost = max(T_transfer_in, T_decode) + T_transfer_out + T_setup

Non-linear due to max(), solved with scipy least_squares with bounds >= 0.
"""

import sys
import numpy as np
import pandas as pd
from scipy.optimize import least_squares


def compute_cost(params, df):
    transfer_factor, decompress_factor, plain_factor, hybrid_factor, setup_factor = params

    T_transfer_in = transfer_factor * (df["input_bytes_plain"] + df["input_bytes_hybrid"])
    T_decode = (plain_factor * df["num_values_plain"] + hybrid_factor * df["num_values_hybrid"])
    T_decode = T_decode * np.where(df["compressed"] != 0, decompress_factor, 1.0)
    T_transfer_out = transfer_factor * (df["output_bytes_plain"] + df["output_bytes_hybrid"])
    T_setup = setup_factor * df["num_pages"]

    return np.maximum(T_transfer_in, T_decode) + T_transfer_out + T_setup


def residuals(params, df, b):
    return compute_cost(params, df) - b


def fit_factors(csv_path: str):
    df = pd.read_csv(csv_path)

    b = df["time"].to_numpy(dtype=float)

    # Initial guess
    x0 = np.array([1e-4, 8.0, 1e-4, 1e-4, 1.0])

    result = least_squares(
        residuals,
        x0,
        args=(df, b),
        bounds=(0, np.inf),  # all factors >= 0
        method="trf",
        ftol=1e-12,
        xtol=1e-12,
        gtol=1e-12,
        max_nfev=10000,
    )

    transfer_factor, decompress_factor, plain_factor, hybrid_factor, setup_factor = result.x
    predictions = compute_cost(result.x, df)

    ss_res = np.sum((b - predictions) ** 2)
    ss_tot = np.sum((b - b.mean()) ** 2)
    r2 = 1.0 - ss_res / ss_tot
    mae = np.mean(np.abs(b - predictions))
    mape = np.mean(np.abs((b - predictions) / b)) * 100

    print("=" * 50)
    print("Fitted factors:")
    print(f"  transfer_factor   = {transfer_factor:.6e}")
    print(f"  decompress_factor = {decompress_factor:.6e}")
    print(f"  plain_factor      = {plain_factor:.6e}")
    print(f"  hybrid_factor     = {hybrid_factor:.6e}")
    print(f"  setup_factor      = {setup_factor:.6e}")
    print()
    print("Fit quality:")
    print(f"  R²   = {r2:.6f}")
    print(f"  MAE  = {mae:.2f}")
    print(f"  MAPE = {mape:.2f}%")
    print("=" * 50)


if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else "calibration.csv"
    fit_factors(path)
