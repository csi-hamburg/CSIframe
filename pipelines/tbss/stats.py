import os
import sys
import pandas as pd
import seaborn as sns
import matplotlib as plt

branch = sys.argv[1]
mod = sys.argv[2]
csv = sys.argv[3]
histfig = sys.argv[4]
boxfig = sys.argv[5]
zscore = sys.argv[6]

# Read in CSV file containing mean across skeleton
df = pd.read_csv(f"{csv}")

# Histogram
hist = sns.displot(df[f'tbss{branch}_skeleton_mean_{mod}'], kde=True)
hist.savefig(f'{histfig}')
plt.pyplot.close()

# Boxplot
box = sns.boxplot(df[f'tbss{branch}_skeleton_mean_{mod}'])
plt.pyplot.savefig(f'{boxfig}')

# Calculate zscores for outlier detection
df = pd.read_csv(f'{csv}')
df_z = df.apply(zscore)
df_z.to_csv(f'{zscore}')