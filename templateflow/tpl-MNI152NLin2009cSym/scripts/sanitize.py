import numpy as np
import nibabel as nb
from pathlib import Path

def sanitize(input_fname):
    im = nb.as_closest_canonical(nb.load(str(input_fname)))
    hdr = im.header.copy()
    dtype = 'int16'
    if str(input_fname).rstrip('.gz').endswith('_mask.nii'):
        dtype = 'uint8'
    if str(input_fname).rstrip('.gz').endswith('_probseg.nii'):
        dtype = 'float32'
    
    hdr.set_data_dtype(dtype)
    data = np.asanyarray(im._dataobj, dtype=dtype)
    nii = nb.Nifti1Image(data, im.affine, hdr)

    affine = nii.affine
    nii.header.set_sform(affine, 4)
    nii.header.set_qform(affine, 4)
    nii.header.set_xyzt_units(xyz='mm')
    nii.to_filename(f"{str(input_fname).rstrip('.gz')}.gz")

for f in Path().glob('tpl-*.nii.gz'):
    print('Sanitizing file %s' % f)
    sanitize(f)
