import nibabel as nb
from pathlib import Path

def sanitize(input_fname):
    im = nb.as_closest_canonical(nb.squeeze_image(nb.load(str(input_fname))))
    hdr = im.header.copy()
    dtype = 'int16'
    data = None
    if str(input_fname).endswith('_mask.nii.gz'):
        dtype = 'uint8'
        data = im.get_fdata() > 0

    if str(input_fname).endswith('_probseg.nii.gz'):
        dtype = 'float32'
        hdr['cal_max'] = 1.0
        hdr['cal_min'] = 0.0
        data = im.get_fdata()
        data[data < 0] = 0

    if input_fname.name.split('_')[-1].split('.')[0] in ('T1w', 'T2w', 'PD'):
        data = im.get_fdata()
        data[data < 0] = 0

    hdr.set_data_dtype(dtype)
    nii = nb.Nifti1Image(data if data is not None else im.get_fdata().astype(dtype), im.affine, hdr)

    sform = nii.header.get_sform()
    nii.header.set_sform(sform, 4)
    nii.header.set_qform(sform, 4)

    nii.header.set_xyzt_units(xyz='mm')
    nii.to_filename(str(input_fname))

def main():
    for f in Path().glob('cohort-*/tpl-*_res-2_*.nii.gz'):
        print('Sanitizing file %s' % f)
        sanitize(f)

if __name__ == '__main__':
    main()

