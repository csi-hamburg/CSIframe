import os
import sys
import nibabel as nib
import nilearn.plotting
import matplotlib as plt

mod_masked = sys.argv[1]
mod_skel = sys.argv[2]
overlay = sys.argv[3]

img = nib.load(f"{mod_masked}")
skel = nib.load(f"{mod_skel}")

nilearn.plotting.plot_stat_map(skel, img, display_mode = 'z', cut_coords = (-37,-21,-7,9,22,35,49), colorbar = True, cmap = plt.cm.viridis, black_bg = True, output_file = f"{overlay}")