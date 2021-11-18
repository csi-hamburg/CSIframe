#!/bin/bash

# SET VARIABLES FOR CONTAINER TO BE USED
FSL_VERSION=fsl-6.0.3
FREESURFER_VERSION=freesurfer-7.1.1
MRTRIX_VERSION=mrtrix3-3.0.2
###############################################################################################################################################################
FSL_CONTAINER=$ENV_DIR/$FSL_VERSION
FREESURFER_CONTAINER=$ENV_DIR/$FREESURFER_VERSION
MRTRIX_CONTAINER=$ENV_DIR/$MRTRIX_VERSION
ANTSRNET_CONTAINER=$ENV_DIR/antsrnet
###############################################################################################################################################################
singularity="singularity run --cleanenv --userns -B $(readlink -f $ENV_DIR) -B $PROJ_DIR -B $TMP_DIR/:/tmp"
###############################################################################################################################################################

# set output directors
OUT_DIR=data/$PIPELINE/$1/ses-${SESSION}/anat/
ALGORITHM_OUT_DIR=$OUT_DIR/$ALGORITHM/





##############################################################################################################################################################################################################################################################################################################################
# Register segmentation in T1 and MNI
###############################################################################################################################################################

# Define inputs
SEGMENTATION=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
T1=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz
MNI_TEMPLATE=$ENV_DIR/standard/tpl-MNI152NLin2009cAsym_res-01_desc-brain_T1w.nii.gz
T1_TO_MNI_WARP=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_from-T1w_to-MNI152NLin2009cAsym_mode-image_xfm.h5
FLAIR_TO_T1_WARP=$OUT_DIR/${1}_ses-${SESSION}_from-T1_to-FLAIR_InverseComposite.h5

# Define outputs
SEGMENTATION_T1=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
SEGMENTATION_MNI=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-MNI_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz

# Define commands
CMD_SEGMENTATION_TO_T1="antsApplyTransforms -d 3 -i $SEGMENTATION -r $T1 -t $FLAIR_TO_T1_WARP -o $SEGMENTATION_T1"
CMD_SEGMENTATION_TO_MNI="antsApplyTransforms -d 3 -i $SEGMENTATION -r $MNI_TEMPLATE -t $FLAIR_TO_T1_WARP -t $T1_TO_MNI_WARP -o $SEGMENTATION_MNI"

# Execute
$singularity $MRTRIX_CONTAINER /bin/bash -c "$CMD_SEGMENTATION_TO_T1; $CMD_SEGMENTATION_TO_MNI"


###############################################################################################################################################################
# Lesion Filling with FSL -> in T1 space
###############################################################################################################################################################

# Define inputs
T1=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz
SEGMENTATION_T1=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
# Define outputs
T1_FILLED=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_desc-preproc_desc-desc-${ALGORITHM}filled_T1w.nii.gz
# Define commands
CMD_LESION_FILLING="LesionFilling 3 $T1 $SEGMENTATION_T1 $T1_FILLED"
# Execute
$singularity $MRTRIX_CONTAINER /bin/bash -c "$CMD_LESION_FILLING"


###############################################################################################################################################################
# create NAWM mask
###############################################################################################################################################################

# Define inputs
SEGMENTATION=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
WMMASK_T1=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-wm_mask.nii.gz 
FLAIR=data/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz
T1_TO_FLAIR_WARP=$OUT_DIR/${1}_ses-${SESSION}_from-T1_to-FLAIR_Composite.h5
MNI_TEMPLATE=$ENV_DIR/standard/tpl-MNI152NLin2009cAsym_res-01_desc-brain_T1w.nii.gz
T1_TO_MNI_WARP=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_from-T1w_to-MNI152NLin2009cAsym_mode-image_xfm.h5
T1=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz
FLAIR_TO_T1_WARP=$OUT_DIR/${1}_ses-${SESSION}_from-T1_to-FLAIR_InverseComposite.h5

# Define outputs
WMMASK_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wm_mask.nii.gz 
NAWM_MASK=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-nawm_desc-${ALGORITHM}_mask.nii.gz
NAWM_MASK_MNI=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-MNI_desc-masked_desc-nawm_desc-${ALGORITHM}_mask.nii.gz
NAWM_MASK_T1=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-masked_desc-nawm_desc-${ALGORITHM}_mask.nii.gz

# Define commands
CMD_WMMASK_TO_FLAIR="antsApplyTransforms -i $WMMASK_T1 -r $FLAIR -t $T1_TO_FLAIR_WARP -o $WMMASK_FLAIR"
CMD_BIN_WMMASK_FLAIR="fslmaths $WMMASK_FLAIR -bin $WMMASK_FLAIR"
CMD_NAWM_MASK="fslmaths $WMMASK_FLAIR -sub $SEGMENTATION $NAWM_MASK"
CMD_NAWM_MASK_TO_T1="antsApplyTransforms -d 3 -i $NAWM_MASK -r $T1 -t $FLAIR_TO_T1_WARP -o $NAWM_MASK_T1"
CMD_NAWM_MASK_TO_MNI="antsApplyTransforms -d 3 -i $NAWM_MASK -r $MNI_TEMPLATE -t $FLAIR_TO_T1_WARP -t $T1_TO_MNI_WARP -o $NAWM_MASK_MNI"
# Execute
$singularity $MRTRIX_CONTAINER /bin/bash -c "$CMD_WMMASK_TO_FLAIR"
$singularity $FSL_CONTAINER /bin/bash -c "$CMD_BIN_WMMASK_FLAIR; $CMD_NAWM_MASK"
$singularity $MRTRIX_CONTAINER /bin/bash -c "$CMD_NAWM_MASK_TO_T1; $CMD_NAWM_MASK_TO_MNI"


###############################################################################################################################################################
# create periventricular / deep WMH masks
###############################################################################################################################################################

# Define inputs
SEGMENTATION=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
WMMASK_peri=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmperi_mask.nii.gz
WMMASK_deep=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmdeep_mask.nii.gz

# Define outputs
SEGMENTATION_peri=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmhperi_desc-${ALGORITHM}_mask.nii.gz
SEGMENTATION_deep=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmhdeep_desc-${ALGORITHM}_mask.nii.gz

# Define commands
CMD_segmentation_filterperi="fslmaths $SEGMENTATION -mas $WMMASK_peri $SEGMENTATION_peri"
CMD_segmentation_filterdeep="fslmaths $SEGMENTATION -mas $WMMASK_deep $SEGMENTATION_deep"

# Execute
$singularity $FSL_CONTAINER /bin/bash -c "$CMD_segmentation_filterperi; $CMD_segmentation_filterdeep"

    