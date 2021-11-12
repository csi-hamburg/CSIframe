import pandas as pd
import glob
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

# Substitute contents of problematic metadata fields with new data

df[['acq_time','operator']]="NaN"

def enter_random(x):
    y=''.join(random.choices(string.ascii_lowercase + string.digits, k=8))
    return y

df['randstr'] = df['randstr'].apply(enter_random)

# Check if ASL data is present and update tsv file accordingly

if os.path.exists(f'{bids_dir}/{subject}/ses-{session}/perf/{subject}_ses-{session}_asl.nii.gz'):
    
    df_append = pd.DataFrame([[f'perf/{subject}_ses-{session}_asl.nii.gz', "NaN", "NaN", 'NaN']], columns = df.columns)
    
    if not (df['filename'] == f'perf/{subject}_ses-{session}_asl.nii.gz').any():
        df = df.append(df_append)

    drop_control = df[df['filename'] == f'perf/{subject}_ses-{session}_desc-control_asl.nii.gz'].index
    df.drop(axis = 0, index = drop_control, inplace = True)

    drop_label = df[df['filename'] == f'perf/{subject}_ses-{session}_desc-label_asl.nii.gz'].index
    df.drop(axis = 0, index = drop_control, inplace = True)



# Write updated scans.tsv

df.to_csv(tsv_path, sep='\t', index=False)