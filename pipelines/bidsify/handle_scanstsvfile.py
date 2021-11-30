import pandas as pd
import os
import sys
import random
import string
import numpy as np
from numpy.random import randn
np.random.seed(42)

subject = sys.argv[1]
session = sys.argv[2]
bids_dir = sys.argv[3]

if not subject.startswith('sub-'): subject = 'sub-' + subject

# Define path of scans.tsv file to edit

tsv_path = f'{bids_dir}/{subject}/ses-{session}/{subject}_ses-{session}_scans.tsv'
print(f'Editing scans.tsv metadata of {subject} for ses-{session}:', tsv_path)

# Read in scans.tsv

df = pd.read_csv(tsv_path, sep = '\t')

# Check if ASL data is present and update tsv file accordingly

if os.path.exists(f'{bids_dir}/{subject}/ses-{session}/perf/{subject}_ses-{session}_asl.nii.gz'):

    drop_asl = df[df['filename'].str.contains('asl')].index
    drop_m0 = df[df['filename'].str.contains('m0scan')].index

    df.drop(axis = 0, index = drop_asl, inplace = True)
    df.drop(axis = 0, index = drop_m0, inplace = True)

    df_append = pd.DataFrame([[f'perf/{subject}_ses-{session}_asl.nii.gz', "NaN", "NaN", 'NaN'],
        [f'perf/{subject}_ses-{session}_m0scan.nii.gz', "NaN", "NaN", 'NaN']], columns = df.columns)
    
    df = df.append(df_append)

# Substitute contents of problematic metadata fields with new data

df[['acq_time','operator']]="NaN"

def enter_random(x):
    y=''.join(random.choices(string.ascii_lowercase + string.digits, k=8))
    return y

df['randstr'] = df['randstr'].apply(enter_random)

# Write updated scans.tsv

df.to_csv(tsv_path, sep='\t', index=False)