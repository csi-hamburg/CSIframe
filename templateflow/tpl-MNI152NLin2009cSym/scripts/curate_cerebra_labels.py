import pandas as pd
data = pd.read_csv('CerebrA_LabelDetails.csv')
right = data.copy()
left = data.copy()
# Add hemisphere column
right['hemi'] = 'R'
left['hemi'] = 'L'
# Reassign headers, drop opposite hemi column
right = right.rename(columns={'Mindboggle ID': 'name', 'Label Name': 'label', 'RH Label': 'drop', 'LH LabelsNotes': 'notes', 'Dice Kappa': 'dice/kappa'})
left = left.rename(columns={'Mindboggle ID': 'name', 'Label Name': 'drop', 'RH Label': 'label', 'LH LabelsNotes': 'notes', 'Dice Kappa': 'dice/kappa'})
right = right.drop(columns=['drop'])
left = left.drop(columns=['drop'])
# Drop index
left.index.name = 'mindboggle mapping'
right.index.name = 'mindboggle mapping'
left = left.reset_index()
right = right.reset_index()
# Merge L/R tables
curated = pd.concat((right, left)).sort_values(by=['mindboggle mapping', 'hemi'])
curated[['label', 'name', 'hemi', 'mindboggle mapping', 'dice/kappa', 'notes']].to_csv('tpl-MNI152NLin2009cSym_atlas-CerebA_dseg.tsv', sep='\t', na_rep='n/a', header=True, index=False)
