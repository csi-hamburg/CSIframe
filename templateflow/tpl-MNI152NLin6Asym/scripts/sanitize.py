import numpy as np
import nibabel as nb
from pathlib import Path

def sanitize(input_fname):
    im = nb.as_closest_canonical(nb.load(str(input_fname)))
    hdr = im.header.copy()
    dtype = 'int16'
    if str(input_fname).endswith('_mask.nii.gz'):
        dtype = 'uint8'
    hdr.set_data_dtype(dtype)
    data = np.asanyarray(im._dataobj, dtype=dtype)
    nii = nb.Nifti1Image(data, im.affine, hdr)

    sform = nii.header.get_sform()
    nii.header.set_sform(sform, 4)
    nii.header.set_qform(sform, 4)
    nii.header.set_xyzt_units(xyz='mm')
    # print(nii.shape)
    # print(nii.affine)
    nii.to_filename(str(input_fname))

for f in Path().glob('tpl-*.nii.gz'):
    print('Sanitizing file %s' % f)
    sanitize(f)

