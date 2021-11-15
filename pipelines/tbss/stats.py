import os
import sys
import pandas as pd
import seaborn as sns
import matplotlib as plt

mod = sys.argv[1]
csv = sys.argv[2]
histfig = sys.argv [3]
boxfig = sys.argv [4]
zscore = sys.argv[5]

# Read in CSV file containing mean across skeleton
df = pd.read_csv(f"{csv}")

# Histogram
hist = sns.displot(df[f'mean_{mod}'], kde=True)
hist.savefig(f'{histfig}')
plt.pyplot.close()

# Boxplot
box = sns.boxplot(df[f'mean_{mod}'])
plt.pyplot.savefig(f'{boxfig}')

# Calculate zscores for outlier detection
df = pd.read_csv(f'{csv}')
df_z = df.apply(zscore)
df_z.to_csv(f'{zscore}')