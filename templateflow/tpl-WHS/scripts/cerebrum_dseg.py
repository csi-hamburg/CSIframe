"""
Generate WHS cerebrum images from V3 atlas
Eilidh MacNicol 25/02/20
"""

# import tools
import nibabel as nib
import numpy as np
import scipy.ndimage as spnd

# get original image data
img = nib.load('tpl-WHS_atlas-v3_dseg.nii.gz')
imgarray = img.get_fdata()
imghdr = img.header
imgaff = img.affine

# define white list 
GM = [2, 3,  10, 30, 31, 32, 39, 40, 43, 48, 50, 51, 55,
      64, 65, 66, 71,  77, 81, 82, 92, 93, 94, 95, 96, 97, 
      98, 99, 100, 108, 109, 110, 112, 113, 114, 115, 
      143, 145, 147, 148, 149, 150, 151, 152, 153, 164]
WM = [6, 34, 36, 37, 38,  46, 52, 53, 54, 59, 60, 
      61, 62, 63, 67, 68, 69, 73, 80, 83, 146, 157]
CSF = [33]

# mask array with white list
GMmasked_array = np.isin(imgarray,GM)
WMmasked_array = np.isin(imgarray,WM)
CSFmasked_array= np.isin(imgarray,CSF)

# morphological opening
GMmask_open = spnd.binary_opening(GMmasked_array)
WMmask_open = spnd.binary_opening(WMmasked_array)
CSFmask_open = spnd.binary_opening(CSFmasked_array)

# make new images
GMmask = nib.Nifti1Image(GMmask_open.astype(np.int), affine=imgaff, header=imghdr)
WMmask = nib.Nifti1Image(WMmask_open.astype(np.int), affine=imgaff, header=imghdr)
CSFmask = nib.Nifti1Image(CSFmask_open.astype(np.int), affine=imgaff, header=imghdr)

# save single tissue masks
nib.save(GMmask, 'tpl-WHS/tpl-WHS_desc-GMCerebrum_dseg.nii.gz')
nib.save(WMmask, 'tpl-WHS_desc-WMCerebrum_dseg.nii.gz')
nib.save(CSFmask, 'tpl-WHS_desc-CSFCerebrum_dseg.nii.gz')

# generate cerebrum label mask
label_mask = GMmasked_array.astype(np.int) + WMmasked_array.astype(np.int) + CSFmasked_array.astype(np.int)
label_mask_out = nib.Nifti1Image(label_mask, affine=imgaff, header=imghdr)
nib.save(label_mask_out, 'tpl-WHS_desc-CerebrumTissueLabels_mask.nii.gz')

# generate tissue discrete segmentation image
label_image_WM = WMmasked_array.astype(np.int) * 2 #label white matter as 2
label_image_CSF = CSFmasked_array.astype(np.int) * 3 # label csf as 3
label_array = GMmasked_array.astype(np.int) + label_image_WM + label_image_CSF # label grey matter as 1
final_label_image = nib.Nifti1Image(label_array, affine=imgaff, header=imghdr)
nib.save(final_label_image, 'tpl-WHS_desc-CerebrumTissueLabels_dseg.nii.gz')