import pandas as pd
import glob
import random
import string
import numpy as np
from numpy.random import randn
np.random.seed(42)

subject=sys.argv[1]
if not subject.startswith('sub-'): subject = 'sub-' + subject

# Make list of the scans.tsv files to edit
print("Found sessions:", glob.glob(f"data/raw_bids/{subject}/ses-*"))
tsv_path=glob.glob(f'data/raw_bids/{subject}/ses-*/*_scans.tsv')
print(f'Editing scans.tsv metadata of {subject}:', tsv_path)

df = pd.read_csv(tsv_path[0], sep = '\t')

# append to each tsv file ASL-Nifti file
df2 = pd.DataFrame([[f'perf/{subject}_ses-1_asl.nii.gz', "NaN", "NaN", 'NaN']], columns = df.columns)

if not (df['filename'] == f'perf/{subject}_ses-1_asl.nii.gz').any():
    df= df.append(df2)

# For each tsv substitute contents of problematic metadata fields with new data
df[['acq_time','operator']]="NaN"
def enter_random(x):
    y=''.join(random.choices(string.ascii_lowercase + string.digits, k=8))
    return y
df['randstr']=df['randstr'].apply(enter_random)

df.to_csv(tsv_path[0], sep='\t', index=False)