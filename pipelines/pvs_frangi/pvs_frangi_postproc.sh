#!/usr/bin/env bash

###################################################################################################################
# Preprocessing of FLAIR and T1 and creation of input files for WMH segmentation 
#                                                                                                                 
# Pipeline specific dependencies:                                                                                 
#   [pipelines which need to be run first]                                                                        
#       -                                                                                                    
#   [container]                                                                                                   
#       - 
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

( cp -ruvfL $ENV_DIR/freesurfer_license.txt $ENV_DIR/$FREESURFER_CONTAINER/opt/$FREESURFER_VERSION/.license )

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
OUT_DIR=$DATA_DIR/$PIPELINE/$1/ses-${SESSION}/Segmentation/PVS 
[ ! -d $OUT_DIR ] && mkdir -p $OUT_DIR
DERIVATIVE_dir=$DATA_DIR/$PIPELINE/derivatives
[ ! -d $DERIVATIVE_dir ] && mkdir -p $DERIVATIVE_dir

# To make I/O more efficient read/write outputs from/to $SCRATCH
[ -d $TMP_IN ] && cp -rf $BIDS_DIR/$1 $BIDS_DIR/dataset_description.json $TMP_IN 
[ -d $TMP_OUT ] && mkdir -p $TMP_OUT/$PIPELINE $TMP_OUT/$PIPELINE

# $MRTRIX_TMPFILE_DIR should be big and writable
export MRTRIX_TMPFILE_DIR=/tmp

# Pipeline execution
##################################
# Define inputs 
MASK1=$OUT_DIR/${1}_ses-1_PVS_LeftBG_NAWM.nii.gz
MASK2=$OUT_DIR/${1}_ses-1_PVS_LeftCSO_NAWM.nii.gz
MASK3=$OUT_DIR/${1}_ses-1_PVS_Midbrain_NAWM.nii.gz
MASK4=$OUT_DIR/${1}_ses-1_PVS_RightBG_NAWM.nii.gz
MASK5=$OUT_DIR/${1}_ses-1_PVS_RightCSO_NAWM.nii.gz
MNI_TEMPLATE=$ENV_DIR/standard/tpl-MNI152NLin2009cAsym_res-01_desc-brain_T1w.nii.gz
T1_TO_MNI_WARP=$DATA_DIR/fmriprep/$sub/ses-${SESSION}/anat/${sub}_ses-${SESSION}_from-T1w_to-MNI152NLin2009cAsym_mode-image_xfm.h5
SEGMENTATION_WMH=$DATA_DIR/wmh/$sub/ses-${SESSION}/anat/LOCATE/${sub}_ses-${SESSION}_space-T1_desc-masked_desc-wmh_desc-LOCATE_mask.nii.gz

# Define outputs
SEGMENTATION_PVS=$OUT_DIR/${1}_ses-1_space-T1_desc-pvs_mask.nii.gz
SEGMENTATION_PVS_MNI=$OUT_DIR/${1}_ses-1_space-MNI_desc-pvs_mask.nii.gz
PVS_vol=$DERIVATIVE_dir/${sub}_ses-1_pvsvolume.csv
PVS_count=$DERIVATIVE_dir/${sub}_ses-1_pvscount.csv

# Define commands
CMD_ADD_ALL_MASKS="fslmaths $MASK1 -add $MASK2 -add $MASK3 -add $MASK4 -add $MASK5 -bin $MASK_TOTAL"
CMD_EXCLUDE_WMH="fslmaths $SEGMENTATION_PVS -sub $SEGMENTATION_WMH -thr 0 -bin $SEGMENTATION_PVS"
CMD_SEGMENTATION_TO_MNI="antsApplyTransforms -d 3 -i $SEGMENTATION_PVS -r $MNI_TEMPLATE -t $T1_TO_MNI_WARP -o $SEGMENTATION_PVS_MNI"

# Execute
$singularity_fsl /bin/bash -c "$CMD_ADD_ALL_MASKS; $CMD_EXCLUDE_WMH"
$singularity_mrtrix /bin/bash -c "$CMD_SEGMENTATION_TO_MNI"

$singularity_fsl /bin/bash -c "$(echo fslstats $SEGMENTATION_PVS -V) > $PVS_vol"
[ ! -f $SEGMENTATION_PVS ] && echo "na na" > $PVS_vol

$singularity_fsl /bin/bash -c "$(echo cluster -i $vesselness -t 1 | awk '{print $1'} | sed -n 2p) > $PVS_count"
[ ! -f $SEGMENTATION_PVS ] && echo "na na" > $PVS_count

