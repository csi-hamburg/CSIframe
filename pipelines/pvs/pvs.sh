#!/usr/bin/env bash

###################################################################################################################
# PVS segmentation based on the published paper by Sepehrband et al. with slight adaptations (see github wiki for details) 
#                                                                                                                 
# Pipeline specific dependencies:                                                                                 
#   [pipelines which need to be run first]                                                                        
#       - fmriprep
#       - freesurfer
#       - wmh                                                                                                   
#   [container]                                                                                                   
#       - freesurfer
#       - fsl
#       - mrtrix
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
    -B $ENV_DIR/freesurfer_license.txt:/opt/$container_freesurfer/license.txt
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

# Set output directories
OUT_DIR=$DATA_DIR/$PIPELINE/$1/ses-${SESSION}/anat/test_without77
[ ! -d $OUT_DIR ] && mkdir -p $OUT_DIR

# To make I/O more efficient read/write outputs from/to $SCRATCH
[ -d $TMP_IN ] && cp -rf $BIDS_DIR/$1 $BIDS_DIR/dataset_description.json $TMP_IN 
[ -d $TMP_OUT ] && mkdir -p $TMP_OUT/pvs $TMP_OUT/pvs

# $MRTRIX_TMPFILE_DIR should be big and writable
export MRTRIX_TMPFILE_DIR=/tmp

# Pipeline execution
##################################
# Define inputs
T1_image=$DATA_DIR/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz
brain_mask=$DATA_DIR/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-brain_mask.nii.gz
TEMPLATE_native=$DATA_DIR/freesurfer/$1/mri/rawavg.mgz
ASEG_freesurfer=$DATA_DIR/freesurfer/$1/mri/aseg.mgz
WMMASK_T1=$DATA_DIR/wmh/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_space-T1_desc-wm_mask.nii.gz 
wmh_mask=$DATA_DIR/wmh/$1/ses-${SESSION}/anat/LOCATE/${1}_ses-${SESSION}_space-T1_desc-masked_desc-wmh_desc-LOCATE_mask.nii.gz
total_mask=$OUT_DIR/../${1}_ses-${SESSION}_space-T1_desc-finalfiltering_mask.nii.gz
corrected_T1=$OUT_DIR/../${1}_ses-${SESSION}_space-T1_desc-preproc_desc-Riciandenoised_T1w.nii.gz

# Define outputs
ASEG_native=/tmp/${1}_ses-${SESSION}_space-T1_aseg.mgz
ASEG_nii=/tmp/${1}_ses-${SESSION}_space-T1_aseg.nii.gz
FREESURFER_WMH=/tmp/${1}_ses-${SESSION}_space-T1_desc-freesurferwmh_mask.nii.gz
total_mask_new=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-finalfiltering_mask.nii.gz
vesselness_map_T1=$OUT_DIR/${1}_ses-${SESSION}_space-T1_vesselnessmap.nii.gz
vesselness_map_T1_filtered=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-thresholded_vesselnessmap.nii.gz
vesselness_map_T1_filtered_sized=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-thresholded_desc-filtered_vesselnessmap.nii.gz

# Define commands
CREATE_WM_MASK_1="mri_label2vol --seg $ASEG_freesurfer --temp $TEMPLATE_native --o $ASEG_native --regheader $ASEG_freesurfer"
CREATE_WM_MASK_2="mri_convert $ASEG_native $ASEG_nii"
CREATE_WM_MASK_11="fslmaths $ASEG_nii -thr 77 -uthr 77 -dilM -bin $FREESURFER_WMH"
CREATE_WM_MASK_12="fslmaths $total_mask -sub $FREESURFER_WMH -bin $total_mask_new"
# -> -> -> now follows the QIT command, see below in execute
THRESHOLD_VM="fslmaths $vesselness_map_T1 -thr 0.0023 -bin $vesselness_map_T1_filtered"
FILTER_VM="fslmaths $vesselness_map_T1_filtered -sub $wmh_mask -thr 1 -bin $vesselness_map_T1_filtered"
CLUSTER_VM="cluster --in=$vesselness_map_T1_filtered --thresh=0.1 --connectivity=6 --osize=$vesselness_map_T1_filtered_sized"
THRESHOLD_CLUSTER_VM="fslmaths $vesselness_map_T1_filtered_sized -thr 5 -bin $vesselness_map_T1_filtered_sized"

# Execute
## 1. PART COMMANDS
$singularity_freesurfer /bin/bash -c "$CREATE_WM_MASK_1; $CREATE_WM_MASK_2"
$singularity_fsl /bin/bash -c "$CREATE_WM_MASK_11; $CREATE_WM_MASK_12"
$singularity_mrtrix /bin/bash -c "$DENOISING"
## QIT
qitdir=/work/bax0929/software/qit-build-linux-latest
export qitdir
PATH=${qitdir}/bin:${PATH}
export qitdir PATH
qit VolumeFilterFrangi --input $corrected_T1 --mask $total_mask_new --dark --output $vesselness_map_T1
# 2. PART COMMANDS
$singularity_fsl /bin/bash -c "$THRESHOLD_VM; $FILTER_VM; $CLUSTER_VM; $THRESHOLD_CLUSTER_VM"
