import os
import sys
import nibabel as nib
import nilearn.plotting
import matplotlib as plt

mod_eroded = sys.argv[1]
mod_skel = sys.argv[2]
overlay = sys.argv[3]

img = nib.load(f"{mod_eroded}")
skel = nib.load(f"{mod_skel}")

nilearn.plotting.plot_stat_map(skel, img, display_mode='z', colorbar=True, cmap=plt.cm.viridis, output_file=f"{overlay}")