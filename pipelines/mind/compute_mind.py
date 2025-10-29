#!/usr/bin/env python3

###################################################################################################################

# compute_mind.py

# a) single-subject MIND computation 
# b) save MIND similarity matrix as csv-file
# c) compute and save the weighted nodal degrees

###################################################################################################################

import sys
import os
import argparse

p = argparse.ArgumentParser()
p.add_argument('--sub', required=True)
p.add_argument('--session', required=True)
p.add_argument('--mind_pipeline_dir', required=True)
p.add_argument('--surf_dir', required=True)
p.add_argument('--features', nargs='+', required=True)
p.add_argument('--parcellation', default='aparc')
p.add_argument('--mind_dir', required=True)
args=p.parse_args()

session = args.session if args.session.startswith('ses-') else f"ses-{args.session}"

## Import MIND function.
sys.path.insert(1, os.path.join(args.mind_pipeline_dir, 'MIND'))
from MIND import compute_MIND

#print(">>> DEBUG: surf_dir =", args.surf_dir)
#print(">>> DEBUG: label files:", os.listdir(os.path.join(args.surf_dir, "label")))
#print(">>> DEBUG: surf files:", os.listdir(os.path.join(args.surf_dir, "surf")))
#print(">>> DEBUG: parcellation =", args.parcellation)

## The MIND function returns a dataframe of regions X regions containing the final MIND network.
MIND = compute_MIND(
    surf_dir = args.surf_dir, 
    features = args.features, 
    parcellation = args.parcellation
)

## Save MIND similarity matrix as csv-file.
os.makedirs(args.mind_dir, exist_ok=True)
mind_filename = f"{args.sub}_{session}_desc-{args.parcellation}_mind_network.csv"
outpath = os.path.join(args.mind_dir, mind_filename)
MIND.to_csv(outpath, index=True)

####################################################################################################################

# WEIGHTED NODAL DEGREE (subject-level)

import numpy as np
import pandas as pd
from bct.algorithms import strengths_und

mind_df = pd.read_csv(outpath, index_col=0)
A_full = mind_df.values.copy()
np.fill_diagonal(A_full, 0)
N = A_full.shape[0]

# prepare density sweep
triu_idx = np.triu_indices(N, 1)
flat = A_full[triu_idx]

densities = np.arange(0.01, 1.01, 0.01)
record = {'sub_id': args.sub}
data = {}

# loop over each density
for D in densities:
    k = int(np.floor(D * flat.size))

    # a) threshold
    A_thr = np.zeros_like(A_full)
    if k > 0:
        cutoff = np.partition(flat, -k)[-k]
        A_thr = A_full.copy()
        A_thr[A_thr < cutoff] = 0
    
    # b) nodal weights (sum)
    strengths = strengths_und(A_thr)
    mean_strengths = strengths / (N - 1)

    # c) stash each node's mean degree under a density-suffix key
    key = f"{int(D*100):03d}"
    col = f"wnd_mean_d{key}"
    data[col] = mean_strengths

df = pd.DataFrame(data, index=mind_df.index)
df.index.name = args.sub

df.index.name = record['sub_id']

os.makedirs(args.mind_dir, exist_ok=True)
outname = f"{args.sub}_{session}_desc-{args.parcellation}_weighted_nodal_degrees.csv"
outcsv = os.path.join(args.mind_dir, outname)
df.to_csv(outcsv, index=True)