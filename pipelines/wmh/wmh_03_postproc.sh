#!/usr/bin/env bash

###################################################################################################################
# This pipeline contains the postprocessing of the segmented WMH.                                                 #
#                                                                                                                 #
# Anatomy of this script:                                                                                         #
#                                                                                                                 #
#     Registration of WMH segmentation to T1 and MNI space                                                        #
#     Create deep and periventricular WMH                                                                         #
#     Create normal-appearing white matter masks                                                                  #
#     Read out WMH volume                                                                                         #
#     Lesion Filling of T1                                                                                        #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - fmriprep                                                                                                #
#       - freesurfer (if not included in fmriprep)                                                                #
#       - qsiprep                                                                                                 #
#       - wmh_01_prep in wmh                                                                                      #
#       - wmh_02_segment in wmh                                                                                   #
#   [container]                                                                                                   #
#       - fsl-6.0.7.13.sif                                                                                        #
#       - ants-2.5.4.sif                                                                                          #
#                                                                                                                 #
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
###############################

# Apptainer container version and command
container_fsl=fsl-6.0.7.13.sif
apptainer_fsl="apptainer run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_fsl" 

container_ants=ants-2.5.4.sif
apptainer_ants="apptainer run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN \
    -B $TMP_OUT \
    $ENV_DIR/$container_ants"

# Set output directories
OUT_DIR=$DATA_DIR/$PIPELINE/$1/ses-${SESSION}/anat/
[ ! -d $OUT_DIR ] && echo "Necessary input data are not available. Note: 01_prep and 02_segment need to be run first. Exiting ..." && exit 1
ALGORITHM_OUT_DIR=$OUT_DIR/$ALGORITHM/
[ ! -d $ALGORITHM_OUT_DIR ] && echo "Necessary input data are not available. Note: 02_segment need to be run first. Exiting ..." && exit 1

###################################################################################################################
#               Register segmentation in T1 and MNI and differentiate deep and periventricular WMH                #
###################################################################################################################

# Define inputs
###############

T1=$DATA_DIR/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz
MNI_TEMPLATE=$ENV_DIR/standard/tpl-MNI152NLin2009cAsym_res-01_desc-brain_T1w.nii.gz
T1_TO_MNI_WARP=$DATA_DIR/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_from-T1w_to-MNI152NLin2009cAsym_mode-image_xfm.h5
FLAIR_TO_T1_WARP=$OUT_DIR/${1}_ses-${SESSION}_from-T1w_to-FLAIR_InverseComposite.h5
SEGMENTATION=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
VENTRICLEMASK_T1=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-ventricle_mask.nii.gz
WMMASK_peri=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmperi_mask.nii.gz
WMMASK_deep=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmdeep_mask.nii.gz
WMMASK_peri_MNI=$OUT_DIR/${1}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-wmperi_mask.nii.gz
WMMASK_deep_MNI=$OUT_DIR/${1}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-wmdeep_mask.nii.gz
WMMASK_peri_T1=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-wmperi_mask.nii.gz
WMMASK_deep_T1=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-wmdeep_mask.nii.gz

# Define outputs
################

SEGMENTATION_T1=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
SEGMENTATION_MNI=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
SEGMENTATION_peri=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmhperi_desc-${ALGORITHM}_mask.nii.gz
SEGMENTATION_deep=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmhdeep_desc-${ALGORITHM}_mask.nii.gz
SEGMENTATION_T1_peri=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-masked_desc-wmhperi_desc-${ALGORITHM}_mask.nii.gz
SEGMENTATION_T1_deep=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-masked_desc-wmhdeep_desc-${ALGORITHM}_mask.nii.gz
SEGMENTATION_MNI_peri=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-masked_desc-wmhperi_desc-${ALGORITHM}_mask.nii.gz
SEGMENTATION_MNI_deep=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-masked_desc-wmhdeep_desc-${ALGORITHM}_mask.nii.gz  

# Define commands
#################

CMD_SEGMENTATION_TO_T1="antsApplyTransforms -d 3 -i $SEGMENTATION -r $T1 -t $FLAIR_TO_T1_WARP -o $SEGMENTATION_T1"
CMD_BINARIZE_SEGMENTATION_T1="fslmaths $SEGMENTATION_T1 -bin $SEGMENTATION_T1"
CMD_SEGMENTATION_TO_MNI="antsApplyTransforms -d 3 -i $SEGMENTATION -r $MNI_TEMPLATE -t $FLAIR_TO_T1_WARP -t $T1_TO_MNI_WARP -o $SEGMENTATION_MNI"
CMD_BINARIZE_SEGMENTATION_MNI="fslmaths $SEGMENTATION_MNI -bin $SEGMENTATION_MNI"
CMD_create_WMH_peri_FLAIR="fslmaths $SEGMENTATION -mas $WMMASK_peri $SEGMENTATION_peri"
CMD_create_WMH_deep_FLAIR="fslmaths $SEGMENTATION -mas $WMMASK_deep $SEGMENTATION_deep"
CMD_create_WMH_peri_MNI="fslmaths $SEGMENTATION_MNI -mas $WMMASK_peri_MNI $SEGMENTATION_MNI_peri"
CMD_create_WMH_deep_MNI="fslmaths $SEGMENTATION_MNI -mas $WMMASK_deep_MNI $SEGMENTATION_MNI_deep"
CMD_create_WMH_peri_T1="fslmaths $SEGMENTATION_T1 -mas $WMMASK_peri_T1 $SEGMENTATION_T1_peri"
CMD_create_WMH_deep_T1="fslmaths $SEGMENTATION_T1 -mas $WMMASK_deep_T1 $SEGMENTATION_T1_deep"

# Execute commands
##################

$apptainer_ants /bin/bash -c "$CMD_SEGMENTATION_TO_T1; $CMD_SEGMENTATION_TO_MNI"
$apptainer_fsl /bin/bash -c "$CMD_BINARIZE_SEGMENTATION_T1; $CMD_BINARIZE_SEGMENTATION_MNI"
$apptainer_fsl /bin/bash -c "$CMD_create_WMH_peri_FLAIR; $CMD_create_WMH_deep_FLAIR; $CMD_create_WMH_peri_T1; $CMD_create_WMH_deep_T1; $CMD_create_WMH_peri_MNI; $CMD_create_WMH_deep_MNI"


###################################################################################################################
#                                                  Create NAWM masks                                              #               
###################################################################################################################

# Define inputs
###############

WMMASK_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wm_mask.nii.gz 
WMMASK_MNI=$OUT_DIR/${1}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-wm_mask.nii.gz 
WMMASK_T1=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-wm_mask.nii.gz 
SEGMENTATION_T1=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
SEGMENTATION_MNI=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
SEGMENTATION=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz

# Define outputs
################

NAWM_MASK=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-nawm_desc-${ALGORITHM}_mask.nii.gz
NAWM_MASK_MNI=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-masked_desc-nawm_desc-${ALGORITHM}_mask.nii.gz
NAWM_MASK_T1=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-masked_desc-nawm_desc-${ALGORITHM}_mask.nii.gz

# Define commands
#################

CMD_NAWM_MASK_FLAIR="fslmaths $WMMASK_FLAIR -sub $SEGMENTATION $NAWM_MASK"
CMD_NAWM_MASK_T1="fslmaths $WMMASK_T1 -sub $SEGMENTATION_T1 $NAWM_MASK_T1"
CMD_NAWM_MASK_MNI="fslmaths $WMMASK_MNI -sub $SEGMENTATION_MNI $NAWM_MASK_MNI"

# Execute commands
##################

$apptainer_fsl /bin/bash -c "$CMD_NAWM_MASK_FLAIR; $CMD_NAWM_MASK_T1; $CMD_NAWM_MASK_MNI"


###################################################################################################################
#                                                  Read out WMH volume                                            #
###################################################################################################################

# Define inputs
###############

SEGMENTATION=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
SEGMENTATION_peri=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmhperi_desc-${ALGORITHM}_mask.nii.gz
SEGMENTATION_deep=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmhdeep_desc-${ALGORITHM}_mask.nii.gz

# Define outputs
################
WMH_vol=$ALGORITHM_OUT_DIR/${1}_ses-1_${ALGORITHM}_desc-wmh_volume.csv
WMH_peri_vol=$ALGORITHM_OUT_DIR/${1}_ses-1_${ALGORITHM}_desc-wmhperi_volume.csv
WMH_deep_vol=$ALGORITHM_OUT_DIR/${1}_ses-1_${ALGORITHM}_desc-wmhdeep_volume.csv

# Define commands & Execute
###########################
$apptainer_fsl /bin/bash -c "$(echo fslstats $SEGMENTATION -V) > $WMH_vol"
[ ! -f $SEGMENTATION ] && echo "na na" > $WMH_vol
$apptainer_fsl /bin/bash -c "$(echo fslstats $SEGMENTATION_peri -V) > $WMH_peri_vol"
[ ! -f $SEGMENTATION_peri ] && echo "na na" > $WMH_peri_vol
$apptainer_fsl /bin/bash -c "$(echo fslstats $SEGMENTATION_deep -V) > $WMH_deep_vol"
[ ! -f $SEGMENTATION_deep ] && echo "na na" > $WMH_deep_vol


###################################################################################################################
#                                               Lesion Filling of T1w                                             #
###################################################################################################################

# Define inputs
###############

T1=$DATA_DIR/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz
SEGMENTATION_T1=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz

# Define outputs
################

T1_FILLED=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_desc-preproc_desc-${ALGORITHM}_desc-filled_T1w.nii.gz

# Define commands
#################

CMD_LESION_FILLING="LesionFilling 3 $T1 $SEGMENTATION_T1 $T1_FILLED"

# Execute commands
##################

[ ! -f $T1_FILLED ] && $apptainer_ants /bin/bash -c "$CMD_LESION_FILLING"