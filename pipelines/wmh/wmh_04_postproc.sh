#!/usr/bin/env bash

###################################################################################################################
# Preprocessing of FLAIR and T1 and creation of input files for WMH segmentation 
#                                                                                                                 
# Pipeline specific dependencies:                                                                                 
#   [pipelines which need to be run first]                                                                        
#       - wmh_01_prep in wmh
#       - wmh_02_segment in wmh
#       - wmh_03_combine in wmh
#       - fmriprep  
#       - freesurfer                                                                                                    
#   [container]                                                                                                   
#       - fsl-6.0.3.sif
#       - freesurfer-7.1.1.sif     
#       - mrtrix3-3.0.2    
#       - antsrnet
#                                                                           
###################################################################################################################

# Get verbose outputs
set -x
ulimit -c 0

# Define subject specific temporary directory on $SCRATCH_DIR
export TMP_DIR=$SCRATCH_DIR/$1/tmp/;   [ ! -d $TMP_DIR ] && mkdir -p $TMP_DIR
TMP_IN=$TMP_DIR/input;                 [ ! -d $TMP_IN ] && mkdir -p $TMP_IN
TMP_OUT=$TMP_DIR/output;               [ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT

###################################################################################################################

# Pipeline-specific environment
##################################

# Singularity container version and command
container_freesurfer=freesurfer-7.1.1
singularity_freesurfer="singularity run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_freesurfer" 

container_fsl=fsl-6.0.3
singularity_fsl="singularity run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_fsl" 

container_mrtrix=mrtrix3-3.0.2
singularity_mrtrix="singularity run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_mrtrix" 

container_antsrnet=antsrnet
singularity_antsrnet="singularity run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_antsrnet" 

# Set output directories
OUT_DIR=$DATA_DIR/$PIPELINE/$1/ses-${SESSION}/anat/
[ ! -d $OUT_DIR ] && mkdir -p $OUT_DIR
ALGORITHM_OUT_DIR=$OUT_DIR/$ALGORITHM/

# To make I/O more efficient read/write outputs from/to $SCRATCH
[ -d $TMP_IN ] && cp -rf $BIDS_DIR/$1 $BIDS_DIR/dataset_description.json $TMP_IN 
[ -d $TMP_OUT ] && mkdir -p $TMP_OUT/wmh $TMP_OUT/wmh

# $MRTRIX_TMPFILE_DIR should be big and writable
export MRTRIX_TMPFILE_DIR=/tmp

# Pipeline execution
###############################################################################################################################################################
# Register segmentation in T1 and MNI
###############################################################################################################################################################

# Define inputs
SEGMENTATION=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
T1=$DATA_DIR/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz
MNI_TEMPLATE=$ENV_DIR/standard/tpl-MNI152NLin2009cAsym_res-01_desc-brain_T1w.nii.gz
T1_TO_MNI_WARP=$DATA_DIR/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_from-T1w_to-MNI152NLin2009cAsym_mode-image_xfm.h5
FLAIR_TO_T1_WARP=$OUT_DIR/${1}_ses-${SESSION}_from-T1_to-FLAIR_InverseComposite.h5

# Define outputs
SEGMENTATION_T1=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
SEGMENTATION_MNI=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-MNI_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz

# Define commands
CMD_SEGMENTATION_TO_T1="antsApplyTransforms -d 3 -i $SEGMENTATION -r $T1 -t $FLAIR_TO_T1_WARP -o $SEGMENTATION_T1"
CMD_SEGMENTATION_TO_MNI="antsApplyTransforms -d 3 -i $SEGMENTATION -r $MNI_TEMPLATE -t $FLAIR_TO_T1_WARP -t $T1_TO_MNI_WARP -o $SEGMENTATION_MNI"

# Execute
$singularity_mrtrix /bin/bash -c "$CMD_SEGMENTATION_TO_T1; $CMD_SEGMENTATION_TO_MNI"


###############################################################################################################################################################
# Lesion Filling with FSL -> in T1 space
###############################################################################################################################################################

# Define inputs
T1=$DATA_DIR/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz
SEGMENTATION_T1=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
# Define outputs
T1_FILLED=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_desc-preproc_desc-desc-${ALGORITHM}filled_T1w.nii.gz
# Define commands
CMD_LESION_FILLING="LesionFilling 3 $T1 $SEGMENTATION_T1 $T1_FILLED"
# Execute
$singularity_mrtrix /bin/bash -c "$CMD_LESION_FILLING"


###############################################################################################################################################################
# create NAWM mask
###############################################################################################################################################################

# Define inputs
SEGMENTATION=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
WMMASK_T1=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-wm_mask.nii.gz 
FLAIR=$DATA_DIR/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz
T1_TO_FLAIR_WARP=$OUT_DIR/${1}_ses-${SESSION}_from-T1_to-FLAIR_Composite.h5
MNI_TEMPLATE=$ENV_DIR/standard/tpl-MNI152NLin2009cAsym_res-01_desc-brain_T1w.nii.gz
T1_TO_MNI_WARP=$DATA_DIR/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_from-T1w_to-MNI152NLin2009cAsym_mode-image_xfm.h5
T1=$DATA_DIR/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz
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
$singularity_mrtrix /bin/bash -c "$CMD_WMMASK_TO_FLAIR"
$singularity_fsl /bin/bash -c "$CMD_BIN_WMMASK_FLAIR; $CMD_NAWM_MASK"
$singularity_mrtrix /bin/bash -c "$CMD_NAWM_MASK_TO_T1; $CMD_NAWM_MASK_TO_MNI"


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
$singularity_fsl /bin/bash -c "$CMD_segmentation_filterperi; $CMD_segmentation_filterdeep"

    