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

# Read in CSV file containing mean across skeleton
df = pd.read_csv(f"{csv}")
#col = [col for col in df.columns if f'tbss{branch}_skeleton_mean_{mod}' in col ]

# Histogram
hist = sns.displot(df[f'tbss{branch}_skeleton_mean_{mod}'], kde=True)
hist.savefig(f'{histfig}')
plt.pyplot.close()

# Boxplot
box = sns.boxplot(data = df[f'tbss{branch}_skeleton_mean_{mod}'])
plt.pyplot.savefig(f'{boxfig}')