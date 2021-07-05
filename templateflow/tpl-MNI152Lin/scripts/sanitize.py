def sanitize(input_fname):
    im = nb.load(str(input_fname))
    hdr = im.header.copy()
    hdr['scl_inter'] = 0.0
    hdr['scl_slope'] = 1.0
    sform = hdr.get_sform()
    hdr.set_sform(sform, 4)
    hdr.set_qform(sform, 4)
    dtype = 'int16'
    if str(input_fname).endswith('_brainmask.nii.gz') or str(input_fname).endswith('_roi.nii.gz') or str(input_fname).endswith('_atlas.nii.gz'):
        dtype = 'uint8'
    hdr.set_data_dtype(dtype)
    nb.Nifti1Image(im.get_data().astype(dtype), im.affine, hdr).to_filename(str(input_fname))
for f in Path().glob('tpl-*.nii.gz'):
    sanitize(f)

