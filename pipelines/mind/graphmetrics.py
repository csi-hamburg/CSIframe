#!/usr/bin/env python3

###################################################################################################################
##### graphmetrics.py #############################################################################################
###################################################################################################################

import os
import pandas as pd
import numpy as np
from joblib import Parallel, delayed
import argparse
from bct.algorithms import (
    null_model_und_sign,        # Maslov-Sneppen rewiring (degree/strength-preserving)
    clustering_coef_wu,         # weighted clustering (nonnegative)
    efficiency_wei,             # global efficiency (weighted)
    strengths_und,
)       

p = argparse.ArgumentParser(description="Compute normalized graph metrics for a single MIND network.")
p.add_argument("--sub", required=True, help="Subject ID, e.g. sub-001")
p.add_argument("--session", required=True, help="Session label, e.g. 1 or ses-1")
p.add_argument("--parcellation", required=True, help="Parcellation name, e.g. Schaefer2018_100Parcels_7Networks_order")
p.add_argument("--mind_csv", required=True, help="Path to subject-specific MIND network CSV")
p.add_argument("--mind_data_dir", required=True, help="Output directory for graph metrics")
args = p.parse_args()

###################################################################################################################

session = args.session if args.session.startswith("ses-") else f"ses-{args.session}"
sub = args.sub
parcellation = args.parcellation
mind_network_path = args.mind_csv
mind_data_dir = args.mind_data_dir

print(f"\nProcessing subject: {sub}, session: {session}")
print(f"Network file: {mind_network_path}")

###################################################################################################################

min_density = 0.05
max_density = 1
step = 0.025
n_null = 100

###################################################################################################################

mind_network_df = pd.read_csv(mind_network_path, index_col=0)
adj = mind_network_df.values

###################################################################################################################

def density_threshold(matrix, density):
    n = matrix.shape[0]
    n_edges = int(density * n * (n - 1) / 2)
    triu_vals = matrix[np.triu_indices(n, 1)]
    thresh = np.sort(triu_vals)[-n_edges] if n_edges > 0 else np.inf
    adj_bin = (matrix >= thresh).astype(int)
    return adj_bin

def _null_metrics_once(adj_thresholded, seed_i):
    null_thresholded = null_model_und_sign(adj_thresholded, seed=seed_i)
    mat = null_thresholded[0]
    E_null = efficiency_wei(mat)
    C_null = np.nanmean(clustering_coef_wu(mat))
    return E_null, C_null

###################################################################################################################

degrees_dict = dict()
E_norm_dict = dict()
C_norm_dict = dict()
SW_dict = dict()

for density in [1]: #np.arange(min_density,max_density,step):
    print(f"  Density: {density:.3f}")

    # Threshold adjacency at this density
    adj_binary = density_threshold(adj, density)
    adj_thresholded = adj * adj_binary

    # Node strengths (weighted degree)
    deg = strengths_und(adj_thresholded)
    degrees_dict[density] = deg

    # Empirical metrics
    E_density = efficiency_wei(adj_thresholded)
    C_density = np.nanmean(clustering_coef_wu(adj_thresholded))

    # Parallel nulls
    results = Parallel(n_jobs=-1, backend="loky", verbose=0)(
        delayed(_null_metrics_once)(adj_thresholded, seed_i)
        for seed_i in range(n_null)
    )

    E_null_arr = np.array([r[0] for r in results])
    C_null_arr = np.array([r[1] for r in results])

    # Mean null metrics
    E_null_avg = np.nanmean(E_null_arr)
    C_null_avg = np.nanmean(C_null_arr)

    # Normalized metrics
    E_density_norm = E_density / E_null_avg if E_null_avg > 0 else np.nan
    C_density_norm = C_density / C_null_avg if C_null_avg > 0 else np.nan
    SW_density = C_density_norm / E_density_norm if E_density_norm > 0 else np.nan

    E_norm_dict[density] = E_density_norm
    C_norm_dict[density] = C_density_norm
    SW_dict[density] = SW_density

###################################################################################################################

degrees_output_path = os.path.join(mind_data_dir, f"{sub}_{session}_{parcellation}_degrees.csv")
E_norm_output_path  = os.path.join(mind_data_dir, f"{sub}_{session}_{parcellation}_normalized_efficiency.csv")
C_norm_output_path  = os.path.join(mind_data_dir, f"{sub}_{session}_{parcellation}_normalized_clustering_coefficient.csv")
SW_output_path      = os.path.join(mind_data_dir, f"{sub}_{session}_{parcellation}_smallworld_index.csv")

degrees_df = pd.DataFrame(degrees_dict, index=mind_network_df.index).T
E_norm_df  = pd.DataFrame(E_norm_dict.values(), index=E_norm_dict.keys(), columns=["E_norm"])
C_norm_df  = pd.DataFrame(C_norm_dict.values(), index=C_norm_dict.keys(), columns=["C_norm"])
SW_df      = pd.DataFrame(SW_dict.values(), index=SW_dict.keys(), columns=["SW_index"])

os.makedirs(mind_data_dir, exist_ok=True)
degrees_df.to_csv(degrees_output_path)
E_norm_df.to_csv(E_norm_output_path)
C_norm_df.to_csv(C_norm_output_path)
SW_df.to_csv(SW_output_path)

print(f"\nSaved results for {sub}:")
print(f"  → {degrees_output_path}")
print(f"  → {E_norm_output_path}")
print(f"  → {C_norm_output_path}")
print(f"  → {SW_output_path}")