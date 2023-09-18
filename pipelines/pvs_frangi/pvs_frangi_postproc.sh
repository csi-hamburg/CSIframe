#!/usr/bin/env bash

###################################################################################################################
# Postprocessing of PVS segmentation output. This includes thresholding of masks and extraction of individual volumes / counts.
#                                                                                                                 
# Pipeline specific dependencies:                                                                                 
#   [pipelines which need to be run first]                                                                        
#       - fmriprep
#   [container]                                                                                                   
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
OUT_DIR=$DATA_DIR/$PIPELINE/$1/ses-${SESSION}/Segmentation/PVS 
[ ! -d $OUT_DIR ] && mkdir -p $OUT_DIR
DERIVATIVE_dir=$DATA_DIR/$PIPELINE/derivatives
[ ! -d $DERIVATIVE_dir ] && mkdir -p $DERIVATIVE_dir
SOURCE_dir=$DATA_DIR/$PIPELINE/sourcedata

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
T1_TO_MNI_WARP=$DATA_DIR/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_from-T1w_to-MNI152NLin2009cAsym_mode-image_xfm.h5
T1=$DATA_DIR/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz
MANUAL_MASK=$SOURCE_dir/manual_mask_aqueduct_posterior_ventricles.nii.gz
MNI_TO_T1_WARP=$DATA_DIR/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_from-MNI152NLin2009cAsym_to-T1w_mode-image_xfm.h5

# Define outputs
MASK1_THRESH=$OUT_DIR/${1}_ses-1_PVS_LeftBG_NAWM_thresh.nii.gz
MASK2_THRESH=$OUT_DIR/${1}_ses-1_PVS_LeftCSO_NAWM_thresh.nii.gz
MASK3_THRESH=$OUT_DIR/${1}_ses-1_PVS_Midbrain_NAWM_thresh.nii.gz
MASK4_THRESH=$OUT_DIR/${1}_ses-1_PVS_RightBG_NAWM_thresh.nii.gz
MASK5_THRESH=$OUT_DIR/${1}_ses-1_PVS_RightCSO_NAWM_thresh.nii.gz
SEGMENTATION_PVS_CSO=$OUT_DIR/${1}_ses-1_space-T1_desc-pvs_desc-cso_mask.nii.gz
SEGMENTATION_PVS_Midbrain=$OUT_DIR/${1}_ses-1_space-T1_desc-pvs_desc-midbrain_mask.nii.gz
SEGMENTATION_PVS_BG=$OUT_DIR/${1}_ses-1_space-T1_desc-pvs_desc-bg_mask.nii.gz
SEGMENTATION_PVS=$OUT_DIR/${1}_ses-1_space-T1_desc-pvs_mask.nii.gz
SEGMENTATION_PVS_MNI=$OUT_DIR/${1}_ses-1_space-MNI_desc-pvs_mask.nii.gz
PVS_vol=$DERIVATIVE_dir/${1}_ses-1_pvsvolume.csv
PVS_count=$DERIVATIVE_dir/${1}_ses-1_pvscount.csv
PVS_vol_midbrain=$DERIVATIVE_dir/${1}_ses-1_desc-midbrain_pvsvolume.csv
PVS_count_midbrain=$DERIVATIVE_dir/${1}_ses-1_desc-midbrain_pvscount.csv
PVS_vol_cso=$DERIVATIVE_dir/${1}_ses-1_desc-cso_pvsvolume.csv
PVS_count_cso=$DERIVATIVE_dir/${1}_ses-1_desc-cso_pvscount.csv
PVS_vol_bg=$DERIVATIVE_dir/${1}_ses-1_desc-bg_pvsvolume.csv
PVS_count_bg=$DERIVATIVE_dir/${1}_ses-1_desc-bg_pvscount.csv
threshold=$DERIVATIVE_dir/${1}_thresh.csv
MANUAL_MASK_INDIVIDUAL=$OUT_DIR/${1}_ses-1_space-T1_manual_mask_aqueduct_posterior_ventricles.nii.gz

# Define commands 
CMD_REGISTER_MANUAL_MASK="antsApplyTransforms -d 3 -i $MANUAL_MASK -r $T1 -t $MNI_TO_T1_WARP -n NearestNeighbor -o $MANUAL_MASK_INDIVIDUAL"
$singularity_fsl /bin/bash -c "$(echo fslstats $MASK1 -r) > $threshold"
CMD_THRESH_MASK_1="fslmaths $MASK1 -sub $(cat $threshold | sed 's/\s.*$//') -bin $MASK1_THRESH"
CMD_THRESH_MASK_2="fslmaths $MASK2 -sub $(cat $threshold | sed 's/\s.*$//') -bin $MASK2_THRESH"
CMD_THRESH_MASK_3="fslmaths $MASK3 -sub $(cat $threshold | sed 's/\s.*$//') -bin $MASK3_THRESH"
CMD_THRESH_MASK_4="fslmaths $MASK4 -sub $(cat $threshold | sed 's/\s.*$//') -bin $MASK4_THRESH"
CMD_THRESH_MASK_5="fslmaths $MASK5 -sub $(cat $threshold | sed 's/\s.*$//') -bin $MASK5_THRESH"
CMD_ADD_ALL_MASKS="fslmaths $MASK1_THRESH -add $MASK2_THRESH -add $MASK3_THRESH -add $MASK4_THRESH -add $MASK5_THRESH -bin $SEGMENTATION_PVS"
CMD_EXCLUDE_MANUALMASK="fslmaths $SEGMENTATION_PVS -sub $MANUAL_MASK_INDIVIDUAL -thr 0 -bin $SEGMENTATION_PVS"
CMD_EXCLUDE_MANUAL_MIDBRAIN="fslmaths $MASK3_THRESH -sub $MANUAL_MASK_INDIVIDUAL -thr 0 -bin $SEGMENTATION_PVS_Midbrain"
CMD_EXCLUDE_MANUAL_CSO="fslmaths $MASK2_THRESH -add $MASK5_THRESH -sub $MANUAL_MASK_INDIVIDUAL -thr 0 -bin $SEGMENTATION_PVS_CSO"
CMD_EXCLUDE_MANUAL_BG="fslmaths $MASK1_THRESH -add $MASK4_THRESH -sub $MANUAL_MASK_INDIVIDUAL -thr 0 -bin $SEGMENTATION_PVS_BG"
CMD_SEGMENTATION_TO_MNI="antsApplyTransforms -d 3 -i $SEGMENTATION_PVS -r $MNI_TEMPLATE -t $T1_TO_MNI_WARP -n NearestNeighbor -o $SEGMENTATION_PVS_MNI"

# Execute
$singularity_mrtrix /bin/bash -c "$CMD_REGISTER_MANUAL_MASK"
$singularity_fsl /bin/bash -c "$CMD_THRESH_MASK_1; $CMD_THRESH_MASK_2; $CMD_THRESH_MASK_3; $CMD_THRESH_MASK_4; $CMD_THRESH_MASK_5; $CMD_ADD_ALL_MASKS; $CMD_EXCLUDE_MANUALMASK; $CMD_EXCLUDE_MANUAL_MIDBRAIN; $CMD_EXCLUDE_MANUAL_CSO; $CMD_EXCLUDE_MANUAL_BG"
rm $threshold
$singularity_mrtrix /bin/bash -c "$CMD_SEGMENTATION_TO_MNI"

$singularity_fsl /bin/bash -c "$(echo fslstats $SEGMENTATION_PVS -V) > $PVS_vol"
[ ! -f $SEGMENTATION_PVS ] && echo "na na" > $PVS_vol
$singularity_fsl /bin/bash -c "$(echo fslstats $SEGMENTATION_PVS_Midbrain -V) > $PVS_vol_midbrain"
[ ! -f $SEGMENTATION_PVS_Midbrain ] && echo "na na" > $PVS_vol_midbrain
$singularity_fsl /bin/bash -c "$(echo fslstats $SEGMENTATION_PVS_CSO -V) > $PVS_vol_cso"
[ ! -f $SEGMENTATION_PVS_CSO ] && echo "na na" > $PVS_vol_cso
$singularity_fsl /bin/bash -c "$(echo fslstats $SEGMENTATION_PVS_BG -V) > $PVS_vol_bg"
[ ! -f $SEGMENTATION_PVS_BG ] && echo "na na" > $PVS_vol_bg

$singularity_fsl /bin/bash -c "$(echo cluster --in=$SEGMENTATION_PVS --thresh=1) > $PVS_count"
echo $(cat $PVS_count | head -2 | tail -1 | cut -c1-4) > $PVS_count
[ ! -f $SEGMENTATION_PVS ] && echo "na na" > $PVS_count
$singularity_fsl /bin/bash -c "$(echo cluster --in=$SEGMENTATION_PVS_Midbrain --thresh=1) > $PVS_count_midbrain"
echo $(cat $PVS_count_midbrain | head -2 | tail -1 | cut -c1-4) > $PVS_count_midbrain
[ ! -f $SEGMENTATION_PVS_Midbrain ] && echo "na na" > $PVS_count_midbrain
$singularity_fsl /bin/bash -c "$(echo cluster --in=$SEGMENTATION_PVS_CSO --thresh=1) > $PVS_count_cso"
echo $(cat $PVS_count_cso | head -2 | tail -1 | cut -c1-4) > $PVS_count_cso
[ ! -f $SEGMENTATION_PVS_CSO ] && echo "na na" > $PVS_count_cso
$singularity_fsl /bin/bash -c "$(echo cluster --in=$SEGMENTATION_PVS_BG --thresh=1) > $PVS_count_bg"
echo $(cat $PVS_count_bg | head -2 | tail -1 | cut -c1-4) > $PVS_count_bg
[ ! -f $SEGMENTATION_PVS_BG ] && echo "na na" > $PVS_count_bg