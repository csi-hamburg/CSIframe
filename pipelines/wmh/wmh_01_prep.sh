#!/usr/bin/env bash

###################################################################################################################
# Preprocessing of FLAIR and T1 and creation of input files for WMH segmentation 
#                                                                                                                 
# Pipeline specific dependencies:                                                                                 
#   [pipelines which need to be run first]                                                                        
#       - freesurfer
#       - fmriprep                                                                                                    
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
OUT_DIR=$DATA_DIR/$PIPELINE/$1/ses-${SESSION}/anat/
[ ! -d $OUT_DIR ] && mkdir -p $OUT_DIR

# To make I/O more efficient read/write outputs from/to $SCRATCH
[ -d $TMP_IN ] && cp -rf $BIDS_DIR/$1 $BIDS_DIR/dataset_description.json $TMP_IN 
[ -d $TMP_OUT ] && mkdir -p $TMP_OUT/wmh $TMP_OUT/wmh

# $MRTRIX_TMPFILE_DIR should be big and writable
export MRTRIX_TMPFILE_DIR=/tmp

# Pipeline execution
##################################
# Define inputs 
FLAIR=$DATA_DIR/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz
T1=$DATA_DIR/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz
T1_MASK=$DATA_DIR/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-brain_mask.nii.gz
T1_TO_MNI_WARP=$DATA_DIR/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_from-T1w_to-MNI152NLin2009cAsym_mode-image_xfm.h5
MNI_TEMPLATE=$ENV_DIR/standard/tpl-MNI152NLin2009cAsym_res-01_desc-brain_T1w.nii.gz
MNI_TEMPLATE_SKULL=$ENV_DIR/standard/tpl-MNI152NLin2009cAsym_res-01_T1w.nii.gz

# Define outputs
T1_BRAIN=$OUT_DIR/${1}_ses-${SESSION}_desc-preproc_desc-brain_T1w.nii.gz
T1_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii.gz
T1_TO_FLAIR_WARP_pre=$OUT_DIR/${1}_ses-${SESSION}_from-T1_to-FLAIR_
T1_TO_FLAIR_WARP=$OUT_DIR/${1}_ses-${SESSION}_from-T1_to-FLAIR_Composite.h5
T1_MASK_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brain_mask.nii.gz
T1_IN_FLAIR_nii=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii
FLAIR_TO_T1_WARP=$OUT_DIR/${1}_ses-${SESSION}_from-T1_to-FLAIR_InverseComposite.h5
FLAIR_nii=$OUT_DIR/${1}_ses-${SESSION}_FLAIR.nii
FLAIR_BIASCORR=$OUT_DIR/${1}_ses-${SESSION}_desc-biascorr_FLAIR.nii.gz
FLAIR_BIASCORR_IN_T1=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-biascorr_FLAIR.nii.gz
FLAIR_BRAIN=$OUT_DIR/${1}_ses-${SESSION}_desc-brain_FLAIR.nii.gz
FLAIR_BRAIN_BIASCORR=$OUT_DIR/${1}_ses-${SESSION}_desc-biascorr_desc-brain_FLAIR.nii.gz
FLAIR_BRAIN_IN_T1=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-brain_FLAIR.nii.gz
FLAIR_BRAIN_BIASCORR_IN_T1=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-biascorr_desc-brain_FLAIR.nii.gz
FLAIR_BIASCORR_IN_MNI=$OUT_DIR/${1}_ses-${SESSION}_space-MNI_desc-biascorr_FLAIR.nii.gz
FLAIR_BRAIN_IN_MNI=$OUT_DIR/${1}_ses-${SESSION}_space-MNI_desc-brain_FLAIR.nii.gz
FLAIR_BRAIN_BIASCORR_IN_MNI=$OUT_DIR/${1}_ses-${SESSION}_space-MNI_desc-biascorr_desc-brain_FLAIR.nii.gz

# Define commands
# T1 brain extraction
CMD_T1_EXTRACT_BRAIN="fslmaths $T1 -mul $T1_MASK $T1_BRAIN"
# register T1 in FLAIR
CMD_T1_TO_FLAIR="antsRegistration \
--output [ $T1_TO_FLAIR_WARP_pre, $T1_IN_FLAIR ] \
--collapse-output-transforms 0 \
--dimensionality 3 \
--initial-moving-transform [ $FLAIR, $T1, 1 ] \
--initialize-transforms-per-stage 0 \
--interpolation Linear \
--transform Rigid[ 0.1 ] \
--metric MI[ $FLAIR, $T1, 1, 32, Regular, 0.25 ] \
--convergence [ 10000x111110x11110x100, 1e-08, 10 ] \
--smoothing-sigmas 3.0x2.0x1.0x0.0vox \
--shrink-factors 8x4x2x1 \
--use-estimate-learning-rate-once 1 \
--use-histogram-matching 1 \
--winsorize-image-intensities [ 0.005, 0.995 ] \
--write-composite-transform 1"

# register T1 mask to FLAIR
CMD_T1_MASK_TO_FLAIR="antsApplyTransforms -d 3 -i $T1_MASK -r $FLAIR -t $T1_TO_FLAIR_WARP -o $T1_MASK_IN_FLAIR"
CMD_THRESHOLD_MASK="fslmaths $T1_MASK_IN_FLAIR -thr 0.95 -bin $T1_MASK_IN_FLAIR"

# flair bias correction
CMD_BIASCORR_FLAIR="N4BiasFieldCorrection -d 3 -i $FLAIR -o $FLAIR_BIASCORR --verbose 1" 

# flair brain extraction
CMD_FLAIR_BRAIN_EXTRACT="fslmaths $FLAIR -mul $T1_MASK_IN_FLAIR $FLAIR_BRAIN"
CMD_FLAIR_BRAIN_BIASCORR_EXTRACT="fslmaths $FLAIR_BIASCORR -mul $T1_MASK_IN_FLAIR $FLAIR_BRAIN_BIASCORR"

# register all FLAIR images to T1
CMD_FLAIR_BRAIN_BIASCORR_IN_T1="antsApplyTransforms -d 3 -i $FLAIR_BRAIN_BIASCORR -r $T1_BRAIN -t $FLAIR_TO_T1_WARP -o $FLAIR_BRAIN_BIASCORR_IN_T1"
CMD_FLAIR_BIASCORR_IN_T1="antsApplyTransforms -d 3 -i $FLAIR_BIASCORR -r $T1 -t $FLAIR_TO_T1_WARP -o $FLAIR_BIASCORR_IN_T1"
CMD_FLAIR_BRAIN_IN_T1="antsApplyTransforms -d 3 -i $FLAIR_BRAIN -r $T1_BRAIN -t $FLAIR_TO_T1_WARP -o $FLAIR_BRAIN_IN_T1"

# register all FLAIR images to MNI
CMD_FLAIR_BRAIN_BIASCORR_IN_MNI="antsApplyTransforms -d 3 -i $FLAIR_BRAIN_BIASCORR -r $MNI_TEMPLATE -o $FLAIR_BRAIN_BIASCORR_IN_MNI -t $FLAIR_TO_T1_WARP -t $T1_TO_MNI_WARP"
CMD_FLAIR_BIASCORR_IN_MNI="antsApplyTransforms -d 3 -i $FLAIR_BIASCORR -r $MNI_TEMPLATE_SKULL -o $FLAIR_BIASCORR_IN_MNI -t $FLAIR_TO_T1_WARP -t $T1_TO_MNI_WARP"
CMD_FLAIR_BRAIN_IN_MNI="antsApplyTransforms -d 3 -i $FLAIR_BRAIN -r $MNI_TEMPLATE -o $FLAIR_BRAIN_IN_MNI -t $FLAIR_TO_T1_WARP -t $T1_TO_MNI_WARP"

# convert T1 / FLAIR in nii for lpa/lga
CMD_convert_T1="mri_convert $T1_IN_FLAIR $T1_IN_FLAIR_nii"
CMD_convert_FLAIR="mri_convert $FLAIR $FLAIR_nii"

# Execute 
$singularity_fsl /bin/bash -c "$CMD_T1_EXTRACT_BRAIN"
[ ! -f $T1_IN_FLAIR ] && $singularity_mrtrix /bin/bash -c "$CMD_T1_TO_FLAIR"
[ ! -f $T1_MASK_IN_FLAIR ] && $singularity_mrtrix /bin/bash -c "$CMD_T1_MASK_TO_FLAIR"

if [ ! -f $FLAIR_BRAIN_IN_MNI ]; then

    $singularity_fsl /bin/bash -c "$CMD_THRESHOLD_MASK"
    $singularity_mrtrix /bin/bash -c "$CMD_BIASCORR_FLAIR"
    $singularity_fsl /bin/bash -c "$CMD_FLAIR_BRAIN_EXTRACT; $CMD_FLAIR_BRAIN_BIASCORR_EXTRACT"
    $singularity_mrtrix /bin/bash -c "$CMD_FLAIR_BRAIN_BIASCORR_IN_T1; $CMD_FLAIR_BIASCORR_IN_T1; $CMD_FLAIR_BRAIN_IN_T1; $CMD_FLAIR_BRAIN_BIASCORR_IN_MNI; $CMD_FLAIR_BIASCORR_IN_MNI; $CMD_FLAIR_BRAIN_IN_MNI"
    $singularity_freesurfer /bin/bash -c "$CMD_convert_T1; $CMD_convert_FLAIR"

fi



###############################################################################################################################################################
# The ultimate masking game - create wm masks for filtering of segmentations
###############################################################################################################################################################
# Define inputs
ASEG_freesurfer=$DATA_DIR/freesurfer/$1/mri/aseg.mgz
TEMPLATE_native=$DATA_DIR/freesurfer/$1/mri/rawavg.mgz
T1_MASK=$DATA_DIR/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-brain_mask.nii.gz
FLAIR=$DATA_DIR/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz
T1_TO_FLAIR_WARP=$OUT_DIR/${1}_ses-${SESSION}_from-T1_to-FLAIR_Composite.h5

# Define outputs
ASEG_native=/tmp/${1}_ses-${SESSION}_space-T1_aseg.mgz
ASEG_nii=/tmp/${1}_ses-${SESSION}_space-T1_aseg.nii.gz
WM_right=/tmp/${1}_ses-${SESSION}_space-T1_hemi-R_desc-wm_mask.nii.gz 
WM_left=/tmp/${1}_ses-${SESSION}_space-T1_hemi-L_desc-wm_mask.nii.gz 
WMMASK_T1=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-wm_mask.nii.gz 
FREESURFER_WMH=/tmp/${1}_ses-${SESSION}_space-T1_desc-freesurferwmh_mask.nii.gz
VENTRICLE_right=/tmp/${1}_ses-${SESSION}_space-T1_hemi-R_desc-ventricle_mask.nii.gz
VENTRICLE_left=/tmp/${1}_ses-${SESSION}_space-T1_hemi-L_desc-ventricle_mask.nii.gz
VENTRICLEMASK_T1=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-ventricle_mask.nii.gz
VENTRICLEWMWMHMASK=/tmp/${1}_ses-${SESSION}_space-T1_desc-ventriclewmwmh_mask.nii.gz
RIBBON_right=/tmp/${1}_ses-${SESSION}_space-T1_hemi-R_desc-ribbon_mask.nii.gz 
RIBBON_left=/tmp/${1}_ses-${SESSION}_space-T1_hemi-L_desc-ribbon_mask.nii.gz 
RIBBONMASK=/tmp/${1}_ses-${SESSION}_space-T1_desc-ribbon_mask.nii.gz
CCMASK=/tmp/${1}_ses-${SESSION}_space-T1_desc-corpcall_mask.nii.gz
CAUDATEMASK_LEFT=/tmp/${1}_ses-${SESSION}_space-T1_desc-caudateleft_mask.nii.gz
CAUDATEMASK_RIGHT=/tmp/${1}_ses-${SESSION}_space-T1_desc-caudateright_mask.nii.gz
PUTAMENMASK_LEFT=/tmp/${1}_ses-${SESSION}_space-T1_desc-putamenleft_mask.nii.gz
PUTAMENMASK_RIGHT=/tmp/${1}_ses-${SESSION}_space-T1_desc-putamenright_mask.nii.gz
PALLIDUMMASK_LEFT=/tmp/${1}_ses-${SESSION}_space-T1_desc-pallidumleft_mask.nii.gz
PALLIDUMMASK_RIGHT=/tmp/${1}_ses-${SESSION}_space-T1_desc-pallidumright_mask.nii.gz
VENTRICLEMASK_eroded=/tmp/${1}_ses-${SESSION}_space-T1_desc-ventricle_desc-eroded_mask.nii.gz
BRAINWITHOUTRIBBON_MASK=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-brainwithoutribbon_mask.nii.gz
BRAINWITHOUTRIBBON_MASK_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brainwithoutribbon_mask.nii.gz

# Define commands
CMD_prepare_wmmask="mri_label2vol --seg $ASEG_freesurfer --temp $TEMPLATE_native --o $ASEG_native --regheader $ASEG_freesurfer"
CMD_convert_wmmask="mri_convert $ASEG_native $ASEG_nii"
CMD_create_wmmask_right="fslmaths $ASEG_nii -thr 41 -uthr 41 -bin $WM_right"
CMD_create_wmmask_left="fslmaths $ASEG_nii -thr 2 -uthr 2 -bin $WM_left"
CMD_merge_wmmasks="fslmaths $WM_right -add $WM_left -bin $WMMASK_T1"
CMD_create_freesurferwmh_mask="fslmaths $ASEG_nii -thr 77 -uthr 77 -bin $FREESURFER_WMH"
CMD_create_ventriclemask_right="fslmaths $ASEG_nii -thr 43 -uthr 43 -bin $VENTRICLE_right"
CMD_create_ventriclemask_left="fslmaths $ASEG_nii -thr 4 -uthr 4 -bin $VENTRICLE_left"
CMD_merge_ventriclemasks="fslmaths $VENTRICLE_right -add $VENTRICLE_left -bin $VENTRICLEMASK_T1"
CMD_create_ventriclewmmask="fslmaths $VENTRICLEMASK_T1 -add $WMMASK_T1 -add $FREESURFER_WMH -bin $VENTRICLEWMWMHMASK"
CMD_create_ribbonmask_right="fslmaths $ASEG_nii -thr 42 -uthr 42 -bin $RIBBON_right"
CMD_create_ribbonmask_left="fslmaths $ASEG_nii -thr 3 -uthr 3 -bin $RIBBON_left"
CMD_merge_ribbonmasks="fslmaths $RIBBON_right -add $RIBBON_left -bin $RIBBONMASK"
CMD_threshold_ribbonmask="fslmaths $RIBBONMASK -bin -dilM $RIBBONMASK"
CMD_threshold_ribbonmaskagain="fslmaths $RIBBONMASK -bin -dilM $RIBBONMASK"
CMD_create_cc="fslmaths $ASEG_nii -thr 251 -bin $CCMASK"
CMD_dilate_cc="fslmaths $CCMASK -dilM -bin $CCMASK"
CMD_create_caudate_left="fslmaths $ASEG_nii -thr 11 -uthr 11 -bin $CAUDATEMASK_LEFT"
CMD_dilate_caudate_left="fslmaths $CAUDATEMASK_LEFT -dilM -bin $CAUDATEMASK_LEFT"
CMD_create_caudate_right="fslmaths $ASEG_nii -thr 50 -uthr 50 -bin $CAUDATEMASK_RIGHT"
CMD_dilate_caudate_right="fslmaths $CAUDATEMASK_RIGHT -dilM -bin $CAUDATEMASK_RIGHT"
CMD_create_putamen_left="fslmaths $ASEG_nii -thr 12 -uthr 12 -bin $PUTAMENMASK_LEFT"
CMD_dilate_putamen_left="fslmaths $PUTAMENMASK_LEFT -dilM -bin $PUTAMENMASK_LEFT"
CMD_create_putamen_right="fslmaths $ASEG_nii -thr 51 -uthr 51 -bin $PUTAMENMASK_RIGHT"
CMD_dilate_putamen_right="fslmaths $PUTAMENMASK_RIGHT -dilM -bin $PUTAMENMASK_RIGHT"
CMD_create_pallidum_left="fslmaths $ASEG_nii -thr 13 -uthr 13 -bin $PALLIDUMMASK_LEFT"
CMD_dilate_pallidum_left="fslmaths $PALLIDUMMASK_LEFT -dilM -bin $PALLIDUMMASK_LEFT"
CMD_create_pallidum_right="fslmaths $ASEG_nii -thr 52 -uthr 52 -bin $PALLIDUMMASK_RIGHT"
CMD_dilate_pallidum_right="fslmaths $PALLIDUMMASK_RIGHT -dilM -bin $PALLIDUMMASK_RIGHT"
CMD_erode_ventriclemask="fslmaths $VENTRICLEMASK_T1 -ero $VENTRICLEMASK_eroded"
CMD_new_brainmask="fslmaths $T1_MASK -sub $RIBBONMASK -sub $CCMASK -sub $CAUDATEMASK_LEFT -sub $CAUDATEMASK_RIGHT -sub $PUTAMENMASK_LEFT -sub $PUTAMENMASK_RIGHT -sub $PALLIDUMMASK_LEFT -sub $PALLIDUMMASK_RIGHT -sub $VENTRICLEMASK_eroded $BRAINWITHOUTRIBBON_MASK"
CMD_final_mask="fslmaths $BRAINWITHOUTRIBBON_MASK -mul $VENTRICLEWMWMHMASK $BRAINWITHOUTRIBBON_MASK"
CMD_final_mask_in_FLAIR="antsApplyTransforms -i $BRAINWITHOUTRIBBON_MASK -r $FLAIR -t $T1_TO_FLAIR_WARP -o $BRAINWITHOUTRIBBON_MASK_FLAIR"
CMD_BINARIZE_FINAL_MASK_FLAIR="fslmaths $BRAINWITHOUTRIBBON_MASK_FLAIR -bin $BRAINWITHOUTRIBBON_MASK_FLAIR"

# Execute 
$singularity_freesurfer /bin/bash -c "$CMD_prepare_wmmask; $CMD_convert_wmmask"
$singularity_fsl /bin/bash -c "$CMD_create_wmmask_right; $CMD_create_wmmask_left; $CMD_merge_wmmasks; $CMD_create_freesurferwmh_mask; $CMD_create_ventriclemask_right; $CMD_create_ventriclemask_left; $CMD_merge_ventriclemasks; $CMD_create_ventriclewmmask; $CMD_create_ribbonmask_right; $CMD_create_ribbonmask_left; $CMD_merge_ribbonmasks; $CMD_threshold_ribbonmask; $CMD_threshold_ribbonmaskagain; $CMD_create_cc; $CMD_dilate_cc; $CMD_create_caudate_left; $CMD_dilate_caudate_left; $CMD_create_caudate_right; $CMD_dilate_caudate_right; $CMD_create_putamen_left; $CMD_dilate_putamen_left; $CMD_create_putamen_right; $CMD_dilate_putamen_right; $CMD_create_pallidum_left; $CMD_dilate_pallidum_left; $CMD_create_pallidum_right; $CMD_dilate_pallidum_right; $CMD_erode_ventriclemask; $CMD_new_brainmask; $CMD_final_mask"
$singularity_mrtrix /bin/bash -c "$CMD_final_mask_in_FLAIR; $CMD_BINARIZE_FINAL_MASK_FLAIR"

###############################################################################################################################################################
# create distancemap
###############################################################################################################################################################
# Define inputs
VENTRICLEMASK_T1=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-ventricle_mask.nii.gz
FLAIR=$DATA_DIR/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz
T1_TO_FLAIR_WARP=$OUT_DIR/${1}_ses-${SESSION}_from-T1_to-FLAIR_Composite.h5
T1_MASK_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brain_mask.nii.gz

# Define outputs
VENTRICLEMASK_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-ventricle_mask.nii.gz
DISTANCEMAP=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_distancemap.nii.gz
WMMASK_peri=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmperi_mask.nii.gz
WMMASK_deep=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmdeep_mask.nii.gz

# Define commands
CMD_VENTRICLEMASK_TO_FLAIR="antsApplyTransforms -i $VENTRICLEMASK_T1 -r $FLAIR -t $T1_TO_FLAIR_WARP -o $VENTRICLEMASK_FLAIR"
CMD_BINARIZE_VENTRICLEMASK_FLAIR="fslmaths $VENTRICLEMASK_FLAIR -bin $VENTRICLEMASK_FLAIR"
CMD_create_distancemap="distancemap -i $VENTRICLEMASK_FLAIR -m $T1_MASK_IN_FLAIR -o $DISTANCEMAP"
CMD_upperthreshold_distancemap="fslmaths $DISTANCEMAP -uthr 10 -bin $WMMASK_peri"
CMD_make_peri_beautiful="fslmaths $WMMASK_peri -add $VENTRICLEMASK_FLAIR -bin $WMMASK_peri"
CMD_threshold_distancemap="fslmaths $DISTANCEMAP -thr 10 -bin $WMMASK_deep"

# Execute 
if [ ! -f $DISTANCEMAP ]; then
    
    $singularity_mrtrix /bin/bash -c "$CMD_VENTRICLEMASK_TO_FLAIR"
    $singularity_fsl /bin/bash -c "$CMD_BINARIZE_VENTRICLEMASK_FLAIR; $CMD_create_distancemap; $CMD_upperthreshold_distancemap; $CMD_make_peri_beautiful; $CMD_threshold_distancemap"

fi
###############################################################################################################################################################

