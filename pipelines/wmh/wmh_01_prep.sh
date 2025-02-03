#!/usr/bin/env bash

###################################################################################################################
# Preprocessing of FLAIR and T1 and creation of input files for WMH segmentation                                  #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - fmriprep                                                                                                #
#       - freesurfer (if not included in fmriprep)                                                                #
#   [container]                                                                                                   #
#       - fsl-6.0.7.13.sif                                                                                        #      
#       - ants-2.5.4.sif                                                                                          #
#       - freesurfer-7.4.1.sif                                                                                    #
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
##################################

# apptainer container version and command
container_freesurfer=freesurfer-7.4.1.sif
apptainer_freesurfer="apptainer run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN \
    -B $TMP_OUT \
    $ENV_DIR/$container_freesurfer" 

#( cp -ruvfL $ENV_DIR/freesurfer_license.txt $ENV_DIR/$FREESURFER_CONTAINER/opt/$FREESURFER_VERSION/.license )

container_fsl=fsl-6.0.7.13.sif
apptainer_fsl="apptainer run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN \
    -B $TMP_OUT \
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
OUT_DIR=$TMP_OUT/$PIPELINE/$1/ses-${SESSION}/anat/
[ ! -d $OUT_DIR ] && mkdir -p $OUT_DIR

# To make I/O more efficient read/write outputs from/to $SCRATCH
[ -d $TMP_IN ] && mkdir -p $TMP_IN/raw_bids && cp -rf $BIDS_DIR/$1 $BIDS_DIR/dataset_description.json $TMP_IN/raw_bids
[ -f $DATA_DIR/freesurfer/$1/stats/aseg.stats ] && mkdir -p $TMP_IN/freesurfer && cp -rf $DATA_DIR/freesurfer/$1 $TMP_IN/freesurfer
if [ -d $DATA_DIR/fmriprep/$1 ]; then
    T1=$DATA_DIR/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz
    T1_MASK=$DATA_DIR/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-brain_mask.nii.gz
    T1_TO_MNI_WARP=$DATA_DIR/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_from-T1w_to-MNI152NLin2009cAsym_mode-image_xfm.h5
    mkdir -p $TMP_IN/fmriprep/$1/ses-${SESSION}/anat/
    cp -v $T1 $TMP_IN/fmriprep/$1/ses-${SESSION}/anat/
    cp -v $T1_MASK $TMP_IN/fmriprep/$1/ses-${SESSION}/anat/
    cp -v $T1_TO_MNI_WARP $TMP_IN/fmriprep/$1/ses-${SESSION}/anat/
fi

[ -d $TMP_OUT ] && mkdir -p $OUT_DIR

# Pipeline execution
##################################

# Define inputs 
###############

FLAIR=$TMP_IN/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz
T1=$TMP_IN/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz
T1_MASK=$TMP_IN/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-brain_mask.nii.gz
T1_TO_MNI_WARP=$TMP_IN/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_from-T1w_to-MNI152NLin2009cAsym_mode-image_xfm.h5
MNI_TEMPLATE=$ENV_DIR/standard/tpl-MNI152NLin2009cAsym_res-01_desc-brain_T1w.nii.gz
MNI_TEMPLATE_SKULL=$ENV_DIR/standard/tpl-MNI152NLin2009cAsym_res-01_T1w.nii.gz

# Define outputs
################

T1_BRAIN=$OUT_DIR/${1}_ses-${SESSION}_desc-preproc_desc-brain_T1w.nii.gz
T1_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii.gz
T1_TO_FLAIR_WARP_pre=$OUT_DIR/${1}_ses-${SESSION}_from-T1w_to-FLAIR_
T1_TO_FLAIR_WARP=$OUT_DIR/${1}_ses-${SESSION}_from-T1w_to-FLAIR_Composite.h5
T1_MASK_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brain_mask.nii.gz
T1_IN_FLAIR_nii=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii
FLAIR_TO_T1_WARP=$OUT_DIR/${1}_ses-${SESSION}_from-T1w_to-FLAIR_InverseComposite.h5
FLAIR_nii=$OUT_DIR/${1}_ses-${SESSION}_FLAIR.nii
FLAIR_BIASCORR=$OUT_DIR/${1}_ses-${SESSION}_desc-biascorr_FLAIR.nii.gz
FLAIR_BIASCORR_IN_T1=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-biascorr_FLAIR.nii.gz
FLAIR_BRAIN=$OUT_DIR/${1}_ses-${SESSION}_desc-brain_FLAIR.nii.gz
FLAIR_BRAIN_BIASCORR=$OUT_DIR/${1}_ses-${SESSION}_desc-biascorr_desc-brain_FLAIR.nii.gz
FLAIR_BRAIN_IN_T1=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-brain_FLAIR.nii.gz
FLAIR_BRAIN_BIASCORR_IN_T1=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-biascorr_desc-brain_FLAIR.nii.gz
FLAIR_BIASCORR_IN_MNI=$OUT_DIR/${1}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-biascorr_FLAIR.nii.gz
FLAIR_BRAIN_IN_MNI=$OUT_DIR/${1}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-brain_FLAIR.nii.gz
FLAIR_BRAIN_BIASCORR_IN_MNI=$OUT_DIR/${1}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-biascorr_desc-brain_FLAIR.nii.gz

# Define commands
#################

# T1 brain extraction
CMD_T1_EXTRACT_BRAIN="fslmaths $T1 -mul $T1_MASK $T1_BRAIN"

# Register T1 in FLAIR
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
--use-histogram-matching 1 \
--winsorize-image-intensities [ 0.005, 0.995 ] \
--write-composite-transform 1"

# Register T1 mask to FLAIR
CMD_T1_MASK_TO_FLAIR="antsApplyTransforms -d 3 -i $T1_MASK -r $FLAIR -t $T1_TO_FLAIR_WARP -o $T1_MASK_IN_FLAIR"
CMD_THRESHOLD_MASK="fslmaths $T1_MASK_IN_FLAIR -thr 0.95 -bin $T1_MASK_IN_FLAIR"

# FLAIR bias correction
CMD_BIASCORR_FLAIR="N4BiasFieldCorrection -d 3 -i $FLAIR -o $FLAIR_BIASCORR --verbose 1" 

# FLAIR brain extraction
CMD_FLAIR_BRAIN_EXTRACT="fslmaths $FLAIR -mul $T1_MASK_IN_FLAIR $FLAIR_BRAIN"
CMD_FLAIR_BRAIN_BIASCORR_EXTRACT="fslmaths $FLAIR_BIASCORR -mul $T1_MASK_IN_FLAIR $FLAIR_BRAIN_BIASCORR"

# Register all FLAIR images to T1
CMD_FLAIR_BRAIN_BIASCORR_IN_T1="antsApplyTransforms -d 3 -i $FLAIR_BRAIN_BIASCORR -r $T1_BRAIN -t $FLAIR_TO_T1_WARP -o $FLAIR_BRAIN_BIASCORR_IN_T1"
CMD_FLAIR_BIASCORR_IN_T1="antsApplyTransforms -d 3 -i $FLAIR_BIASCORR -r $T1 -t $FLAIR_TO_T1_WARP -o $FLAIR_BIASCORR_IN_T1"
CMD_FLAIR_BRAIN_IN_T1="antsApplyTransforms -d 3 -i $FLAIR_BRAIN -r $T1_BRAIN -t $FLAIR_TO_T1_WARP -o $FLAIR_BRAIN_IN_T1"

# Register all FLAIR images to MNI
CMD_FLAIR_BRAIN_BIASCORR_IN_MNI="antsApplyTransforms -d 3 -i $FLAIR_BRAIN_BIASCORR -r $MNI_TEMPLATE -o $FLAIR_BRAIN_BIASCORR_IN_MNI -t $FLAIR_TO_T1_WARP -t $T1_TO_MNI_WARP"
CMD_FLAIR_BIASCORR_IN_MNI="antsApplyTransforms -d 3 -i $FLAIR_BIASCORR -r $MNI_TEMPLATE_SKULL -o $FLAIR_BIASCORR_IN_MNI -t $FLAIR_TO_T1_WARP -t $T1_TO_MNI_WARP"
CMD_FLAIR_BRAIN_IN_MNI="antsApplyTransforms -d 3 -i $FLAIR_BRAIN -r $MNI_TEMPLATE -o $FLAIR_BRAIN_IN_MNI -t $FLAIR_TO_T1_WARP -t $T1_TO_MNI_WARP"

# # Convert T1 / FLAIR in nii for lpa/lga
# CMD_convert_T1="mri_convert $T1_IN_FLAIR $T1_IN_FLAIR_nii"
# CMD_convert_FLAIR="mri_convert $FLAIR $FLAIRnii"

# Execute commands
################## 

$apptainer_fsl /bin/bash -c "$CMD_T1_EXTRACT_BRAIN"
[ ! -f $T1_IN_FLAIR ] && $apptainer_ants /bin/bash -c "$CMD_T1_TO_FLAIR"
[ ! -f $T1_MASK_IN_FLAIR ] && $apptainer_ants /bin/bash -c "$CMD_T1_MASK_TO_FLAIR"

if [ ! -f $FLAIR_BRAIN_IN_MNI ]; then

    $apptainer_fsl /bin/bash -c "$CMD_THRESHOLD_MASK"
    $apptainer_ants /bin/bash -c "$CMD_BIASCORR_FLAIR"
    $apptainer_fsl /bin/bash -c "$CMD_FLAIR_BRAIN_EXTRACT; $CMD_FLAIR_BRAIN_BIASCORR_EXTRACT"
    $apptainer_ants /bin/bash -c "
        $CMD_FLAIR_BRAIN_BIASCORR_IN_T1;\
        $CMD_FLAIR_BIASCORR_IN_T1;\
        $CMD_FLAIR_BRAIN_IN_T1;\
        $CMD_FLAIR_BRAIN_BIASCORR_IN_MNI;\
        $CMD_FLAIR_BIASCORR_IN_MNI;\
        $CMD_FLAIR_BRAIN_IN_MNI"
    #$apptainer_freesurfer /bin/bash -c "$CMD_convert_T1; $CMD_convert_FLAIR"

fi


###############################################################################################################################################################
# The ultimate masking game - create wm masks for filtering of segmentations
###############################################################################################################################################################

# Define inputs
###############

ASEG_freesurfer=$TMP_IN/freesurfer/$1/mri/aseg.mgz
TEMPLATE_native=$TMP_IN/freesurfer/$1/mri/rawavg.mgz
T1_MASK=$TMP_IN/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-brain_mask.nii.gz
FLAIR=$TMP_IN/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz
T1_TO_FLAIR_WARP=$OUT_DIR/${1}_ses-${SESSION}_from-T1w_to-FLAIR_Composite.h5

# Define outputs
################

ASEG_native=/tmp/${1}_ses-${SESSION}_space-T1w_aseg.mgz
ASEG_nii=/tmp/${1}_ses-${SESSION}_space-T1w_aseg.nii.gz
WM_right=/tmp/${1}_ses-${SESSION}_space-T1w_hemi-R_desc-wm_mask.nii.gz 
WM_left=/tmp/${1}_ses-${SESSION}_space-T1w_hemi-L_desc-wm_mask.nii.gz 
WMMASK_T1=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-wm_mask.nii.gz 
FREESURFER_WMH=/tmp/${1}_ses-${SESSION}_space-T1w_desc-freesurferwmh_mask.nii.gz
VENTRICLE_right=/tmp/${1}_ses-${SESSION}_space-T1w_hemi-R_desc-ventricle_mask.nii.gz
VENTRICLE_left=/tmp/${1}_ses-${SESSION}_space-T1w_hemi-L_desc-ventricle_mask.nii.gz
VENTRICLEMASK_T1=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-ventricle_mask.nii.gz
VENTRICLEWMWMHMASK=/tmp/${1}_ses-${SESSION}_space-T1w_desc-ventriclewmwmh_mask.nii.gz
RIBBON_right=/tmp/${1}_ses-${SESSION}_space-T1w_hemi-R_desc-ribbon_mask.nii.gz 
RIBBON_left=/tmp/${1}_ses-${SESSION}_space-T1w_hemi-L_desc-ribbon_mask.nii.gz 
RIBBONMASK=/tmp/${1}_ses-${SESSION}_space-T1w_desc-ribbon_mask.nii.gz
CCMASK=/tmp/${1}_ses-${SESSION}_space-T1w_desc-corpcall_mask.nii.gz
CAUDATEMASK_LEFT=/tmp/${1}_ses-${SESSION}_space-T1w_desc-caudateleft_mask.nii.gz
CAUDATEMASK_RIGHT=/tmp/${1}_ses-${SESSION}_space-T1w_desc-caudateright_mask.nii.gz
PUTAMENMASK_LEFT=/tmp/${1}_ses-${SESSION}_space-T1w_desc-putamenleft_mask.nii.gz
PUTAMENMASK_RIGHT=/tmp/${1}_ses-${SESSION}_space-T1w_desc-putamenright_mask.nii.gz
PALLIDUMMASK_LEFT=/tmp/${1}_ses-${SESSION}_space-T1w_desc-pallidumleft_mask.nii.gz
PALLIDUMMASK_RIGHT=/tmp/${1}_ses-${SESSION}_space-T1w_desc-pallidumright_mask.nii.gz
VENTRICLEMASK_eroded=/tmp/${1}_ses-${SESSION}_space-T1w_desc-ventricle_desc-eroded_mask.nii.gz
BRAINWITHOUTRIBBON_MASK=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-brainwithoutribbon_mask.nii.gz
BRAINWITHOUTRIBBON_MASK_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brainwithoutribbon_mask.nii.gz

# Define commands
#################

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

# Execute commands
##################

$apptainer_freesurfer /bin/bash -c "$CMD_prepare_wmmask; $CMD_convert_wmmask"
$apptainer_fsl /bin/bash -c "
    $CMD_create_wmmask_right;\
    $CMD_create_wmmask_left;\
    $CMD_merge_wmmasks;\
    $CMD_create_freesurferwmh_mask;\
    $CMD_create_ventriclemask_right;\
    $CMD_create_ventriclemask_left;\
    $CMD_merge_ventriclemasks;\
    $CMD_create_ventriclewmmask;\
    $CMD_create_ribbonmask_right;\
    $CMD_create_ribbonmask_left;\
    $CMD_merge_ribbonmasks;\
    $CMD_threshold_ribbonmask;\
    $CMD_threshold_ribbonmaskagain;\
    $CMD_create_cc;\
    $CMD_dilate_cc;\
    $CMD_create_caudate_left;\
    $CMD_dilate_caudate_left;\
    $CMD_create_caudate_right;\
    $CMD_dilate_caudate_right;\
    $CMD_create_putamen_left;\
    $CMD_dilate_putamen_left;\
    $CMD_create_putamen_right;\
    $CMD_dilate_putamen_right;\
    $CMD_create_pallidum_left;\
    $CMD_dilate_pallidum_left;\
    $CMD_create_pallidum_right;\
    $CMD_dilate_pallidum_right;\
    $CMD_erode_ventriclemask;\
    $CMD_new_brainmask;\
    $CMD_final_mask"

$apptainer_ants /bin/bash -c "$CMD_final_mask_in_FLAIR"
$apptainer_fsl /bin/bash -c "$CMD_BINARIZE_FINAL_MASK_FLAIR"

###############################################################################################################################################################
# register output of masking game to T1 and MNI
###############################################################################################################################################################

# Define inputs
###############

WMMASK_T1=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-wm_mask.nii.gz 
FLAIR=$TMP_IN/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz
T1_TO_FLAIR_WARP=$OUT_DIR/${1}_ses-${SESSION}_from-T1w_to-FLAIR_Composite.h5
MNI_TEMPLATE=$ENV_DIR/standard/tpl-MNI152NLin2009cAsym_res-01_desc-brain_T1w.nii.gz
T1_TO_MNI_WARP=$TMP_IN/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_from-T1w_to-MNI152NLin2009cAsym_mode-image_xfm.h5
VENTRICLEMASK_T1=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-ventricle_mask.nii.gz
T1_MASK=$TMP_IN/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-brain_mask.nii.gz

# Define outputs
################

VENTRICLEMASK_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-ventricle_mask.nii.gz
WMMASK_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wm_mask.nii.gz 
WMMASK_MNI=$OUT_DIR/${1}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-wm_mask.nii.gz
VENTRICLEMASK_MNI=$OUT_DIR/${1}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-ventricle_mask.nii.gz
T1_MASK_IN_MNI=$OUT_DIR/${1}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-brain_mask.nii.gz

# Define commands
#################

CMD_VENTRICLEMASK_TO_FLAIR="antsApplyTransforms -i $VENTRICLEMASK_T1 -r $FLAIR -t $T1_TO_FLAIR_WARP -o $VENTRICLEMASK_FLAIR"
CMD_BINARIZE_VENTRICLEMASK_FLAIR="fslmaths $VENTRICLEMASK_FLAIR -bin $VENTRICLEMASK_FLAIR"
CMD_WMMASK_TO_FLAIR="antsApplyTransforms -i $WMMASK_T1 -r $FLAIR -t $T1_TO_FLAIR_WARP -o $WMMASK_FLAIR"
CMD_BINARIZE_WMMASK_FLAIR="fslmaths $WMMASK_FLAIR -bin $WMMASK_FLAIR"
CMD_WMMASK_TO_MNI="antsApplyTransforms -i $WMMASK_T1 -r $MNI_TEMPLATE -t $T1_TO_MNI_WARP -o $WMMASK_MNI"
CMD_BINARIZE_WMMASK_MNI="fslmaths $WMMASK_MNI -bin $WMMASK_MNI"
CMD_VENTRICLEMASK_TO_MNI="antsApplyTransforms -i $VENTRICLEMASK_T1 -r $MNI_TEMPLATE -t $T1_TO_MNI_WARP -o $VENTRICLEMASK_MNI"
CMD_BINARIZE_VENTRICLEMASK_MNI="fslmaths $VENTRICLEMASK_MNI -bin $VENTRICLEMASK_MNI"
CMD_BRAINMASK_TO_MNI="antsApplyTransforms -d 3 -i $T1_MASK -r $MNI_TEMPLATE -t $T1_TO_MNI_WARP -o $T1_MASK_IN_MNI"
CMD_BINARIZE_BRAINMASK_MNI="fslmaths $T1_MASK_IN_MNI -bin $T1_MASK_IN_MNI"

# Execute commands
##################

$apptainer_ants /bin/bash -c "
    $CMD_VENTRICLEMASK_TO_FLAIR;\
    $CMD_WMMASK_TO_FLAIR;\
    $CMD_WMMASK_TO_MNI;\
    $CMD_VENTRICLEMASK_TO_MNI;\
    $CMD_BRAINMASK_TO_MNI"

$apptainer_fsl /bin/bash -c "
    $CMD_BINARIZE_VENTRICLEMASK_FLAIR;\
    $CMD_BINARIZE_WMMASK_FLAIR;\
    $CMD_BINARIZE_WMMASK_MNI;\
    $CMD_BINARIZE_VENTRICLEMASK_MNI;\
    $CMD_BINARIZE_BRAINMASK_MNI"

###############################################################################################################################################################
# create distancemap in FLAIR, T1 and MNI space
###############################################################################################################################################################

# Define inputs
###############

VENTRICLEMASK_T1=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-ventricle_mask.nii.gz
T1_MASK_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brain_mask.nii.gz
VENTRICLEMASK_MNI=$OUT_DIR/${1}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-ventricle_mask.nii.gz
T1_MASK=$TMP_IN/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-brain_mask.nii.gz
T1_MASK_IN_MNI=$OUT_DIR/${1}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-brain_mask.nii.gz

# Define outputs
################

DISTANCEMAP=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_distancemap.nii.gz
DISTANCEMAP_T1=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_distancemap.nii.gz
DISTANCEMAP_MNI=$OUT_DIR/${1}_ses-${SESSION}_space-MNI152NLin2009cAsym_distancemap.nii.gz
WMMASK_peri=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmperi_mask.nii.gz
WMMASK_deep=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmdeep_mask.nii.gz
WMMASK_peri_MNI=$OUT_DIR/${1}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-wmperi_mask.nii.gz
WMMASK_deep_MNI=$OUT_DIR/${1}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-wmdeep_mask.nii.gz
WMMASK_peri_T1=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-wmperi_mask.nii.gz
WMMASK_deep_T1=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-wmdeep_mask.nii.gz

# Define commands
#################

# in FLAIR space
CMD_create_distancemap="distancemap -i $VENTRICLEMASK_FLAIR -o $DISTANCEMAP"
CMD_upperthreshold_distancemap="fslmaths $DISTANCEMAP -uthr 10 -bin $WMMASK_peri"
CMD_make_peri_beautiful="fslmaths $WMMASK_peri -add $VENTRICLEMASK_FLAIR -bin $WMMASK_peri"
CMD_threshold_distancemap="fslmaths $DISTANCEMAP -thr 10 -bin -mas $T1_MASK_IN_FLAIR $WMMASK_deep"

# in MNI space
CMD_create_distancemap_MNI="distancemap -i $VENTRICLEMASK_MNI -o $DISTANCEMAP_MNI"
CMD_upperthreshold_distancemap_MNI="fslmaths $DISTANCEMAP_MNI -uthr 10 -bin $WMMASK_peri_MNI"
CMD_make_peri_beautiful_MNI="fslmaths $WMMASK_peri_MNI -add $VENTRICLEMASK_MNI -bin $WMMASK_peri_MNI"
CMD_threshold_distancemap_MNI="fslmaths $DISTANCEMAP_MNI -thr 10 -bin -mas $T1_MASK_IN_MNI $WMMASK_deep_MNI"

# in T1 space
CMD_create_distancemap_T1="distancemap -i $VENTRICLEMASK_T1 -o $DISTANCEMAP_T1"
CMD_upperthreshold_distancemap_T1="fslmaths $DISTANCEMAP_T1 -uthr 10 -bin $WMMASK_peri_T1"
CMD_make_peri_beautiful_T1="fslmaths $WMMASK_peri_T1 -add $VENTRICLEMASK_T1 -bin $WMMASK_peri_T1"
CMD_threshold_distancemap_T1="fslmaths $DISTANCEMAP_T1 -thr 10 -bin -mas $T1_MASK $WMMASK_deep_T1"


# Execute commands
##################

if [ ! -f $DISTANCEMAP ]; then
    
    $apptainer_fsl /bin/bash -c "$CMD_create_distancemap; $CMD_upperthreshold_distancemap; $CMD_make_peri_beautiful; $CMD_threshold_distancemap"

fi

[ ! -f $DISTANCEMAP_T1 ] && $apptainer_fsl /bin/bash -c "$CMD_create_distancemap_T1"
[ ! -f $DISTANCEMAP_MNI ] && $apptainer_fsl /bin/bash -c "$CMD_create_distancemap_MNI"
$apptainer_fsl /bin/bash -c "
    $CMD_upperthreshold_distancemap_MNI;\
    $CMD_make_peri_beautiful_MNI;\
    $CMD_threshold_distancemap_MNI;\
    $CMD_upperthreshold_distancemap_T1;\
    $CMD_make_peri_beautiful_T1;\
    $CMD_threshold_distancemap_T1"

###############################################################################################################################################################
# Save output to $DATA_DIR
###############################################################################################################################################################

[ -d $TMP_OUT ] && cp -rf $TMP_OUT/$PIPELINE/* $DATA_DIR/$PIPELINE/