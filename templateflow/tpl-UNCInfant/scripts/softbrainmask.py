"""softbrainmask."""
from pathlib import Path
from skimage.morphology import ball
from scipy import ndimage as ndi
import nibabel as nb
import numpy as np


def softbrainmask(brain_mask, cerebrum_probseg, out_name, gen_regmask=True):
    """Create a probseg file off of the brain mask."""
    msk = nb.load(brain_mask)
    data = np.asanyarray(msk.dataobj).astype(bool)
    data = ndi.binary_closing(data, ball(2))
    dilate1 = ndi.binary_dilation(data, ball(1))
    dilate2 = ndi.binary_dilation(dilate1, ball(1))
    soft = 0.95 * dilate2
    soft[dilate1] = 1.0
    gauss = ndi.gaussian_filter(soft.astype('float32'), 1)
    header = msk.header.copy()
    header.set_data_dtype('float32')
    # Synthetic brain softmask
    dbrain = gauss.astype("float32")

    # Cerebrum mask (from template)
    dcereb = nb.load(cerebrum_probseg).get_fdata(dtype="float32")

    # remainder
    remainder = dbrain - dcereb
    remainder[remainder < 0] = 0

    opened = ndi.grey_opening(remainder, size=5)
    bopened = opened.copy()
    bopened[bopened < 0.1] = 0
    bopened[bopened > 0] = 1

    sumbrain = dcereb.copy()
    sumbrain[bopened.astype(bool)] += remainder[bopened.astype(bool)]
    sumbrain = np.clip(sumbrain, 0, 1)

    sumbrain[ndi.binary_erosion(data, ball(2))] = 1.0
    nb.Nifti1Image(sumbrain, msk.affine, header).to_filename(out_name)

    dilated_mask = brain_mask.replace("brain", "BrainCerebellumExtraction")
    if gen_regmask and not Path(dilated_mask).exists():
        header.set_data_dtype("uint8")
        nb.Nifti1Image(
            ndi.binary_dilation(data, ball(4), iterations=3).astype("uint8"),
            msk.affine,
            header
        ).to_filename(dilated_mask)
