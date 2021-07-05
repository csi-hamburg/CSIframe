# MNI ICBM152 non-linear 6th generation symmetric Average Brain Stereotaxic Registration Model

This is a version of the ICBM Average Brain - an average of 152
T1-weighted MRI scans, linearly and non-linearly (6 iterations)
transformed to form a symmetric model in Talairach space - that 
is specially adapted for use with the MNI Linear Registration 
Package (``mni_autoreg``).

Please note that this volume here is different from the mni305 model
(average\_305) that was originally (back in ancient times) included
with ``mni_autoreg``.

 Included in this package are the following files:

     ``icbm_avg_152_t1_tal_nlin_symmetric_VI.mnc``
	a version of the average MRI that covers the whole brain
        (unlike the original Talairach atlas), sampled with 1mm cubic
        voxels
     ``icbm_avg_152_t1_tal_nlin_symmetric_VI_mask.mnc``
	a mask of the average brain in icbm_avg_152_t1_tal_nlin_symmetric_VI.mnc,
	semi-automatically created by Dr. Louis Collins.  Note that
	this mask has had holes filled in, so it is a connected volume
	but includes non-brain tissue (eg. the CSF in the ventricles)
     ``icbm_avg_152_t1_tal_nlin_symmetric_VI_headmask.mnc``
	another mask (full head mask), required for nonlinear mode
     ``icbm_avg_152_t1_tal_nlin_symmetric_VI_eye_mask.mnc``
        a mask of the eyes


Reference:
  G. Grabner, A. L. Janke, M. M. Budge, D. Smith, J. Pruessner, and
  D. L. Collins, "Symmetric atlasing and model based segmentation:
  an application to the hippocampus in older adults", Med Image Comput
  Comput Assist Interv Int Conf Med Image Comput Comput Assist Interv,
  vol. 9, pp. 58-66, 2006.

