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

# Set output directories
OUT_DIR=data/$PIPELINE/$1/ses-${SESSION}/anat/
[ ! -d $OUT_DIR ] && mkdir -p $OUT_DIR






# Define inputs 
FLAIR=data/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz
T1=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz
T1_MASK=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-brain_mask.nii.gz
T1_TO_MNI_WARP=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_from-T1w_to-MNI152NLin2009cAsym_mode-image_xfm.h5
MNI_TEMPLATE=$ENV_DIR/standard/tpl-MNI152NLin2009cAsym_res-01_desc-brain_T1w.nii.gz
MNI_TEMPLATE_SKULL=$ENV_DIR/standard/tpl-MNI152NLin2009cAsym_res-01_T1w.nii.gz

# Define outputs
T1_BRAIN=$OUT_DIR/${1}_ses-${SESSION}_desc-preproc_desc-brain_T1w.nii.gz
T1_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii.gz
T1_TO_FLAIR_WARP_pre=$OUT_DIR/${1}_ses-${SESSION}_from-T1_to-FLAIR_
T1_TO_FLAIR_WARP=$OUT_DIR/${1}_ses-${SESSION}_from-T1_to-FLAIR_Composite.h5
T1_MASK_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brain_mask.nii.gz
T1_IN_FLAIR_nii=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii # needed for lga + lpa algorithm
FLAIR_TO_T1_WARP=$OUT_DIR/${1}_ses-${SESSION}_from-T1_to-FLAIR_InverseComposite.h5
FLAIR_nii=$OUT_DIR/${1}_ses-${SESSION}_FLAIR.nii # needed for lga + lpa algorithm
FLAIR_BIASCORR=$OUT_DIR/${1}_ses-${SESSION}_desc-biascorr_FLAIR.nii.gz
FLAIR_BIASCORR_nii=$OUT_DIR/${1}_ses-${SESSION}_desc-biascorr_FLAIR.nii
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
CMD_BIASCORR_FLAIR="N4BiasFieldCorrection -d 3 -i $FLAIR -x $T1_MASK_IN_FLAIR -o $FLAIR_BIASCORR --verbose 1" 
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
CMD_convert_FLAIR_BIASCORR="mri_convert $FLAIR_BIASCORR $FLAIR_BIASCORR_nii"

# Execute 
[ ! -f $T1_IN_FLAIR ] && $singularity $FSL_CONTAINER /bin/bash -c "$CMD_T1_EXTRACT_BRAIN"
[ ! -f $T1_IN_FLAIR ] && $singularity $MRTRIX_CONTAINER /bin/bash -c "$CMD_T1_TO_FLAIR; $CMD_T1_MASK_TO_FLAIR"

if [ ! -f $FLAIR_BRAIN_IN_MNI ]; then

    $singularity $FSL_CONTAINER /bin/bash -c "$CMD_THRESHOLD_MASK"
    $singularity $MRTRIX_CONTAINER /bin/bash -c "$CMD_BIASCORR_FLAIR"
    $singularity $FSL_CONTAINER /bin/bash -c "$CMD_FLAIR_BRAIN_EXTRACT; $CMD_FLAIR_BRAIN_BIASCORR_EXTRACT"
    $singularity $MRTRIX_CONTAINER /bin/bash -c "$CMD_FLAIR_BRAIN_BIASCORR_IN_T1; $CMD_FLAIR_BIASCORR_IN_T1; $CMD_FLAIR_BRAIN_IN_T1; $CMD_FLAIR_BRAIN_BIASCORR_IN_MNI; $CMD_FLAIR_BIASCORR_IN_MNI; $CMD_FLAIR_BRAIN_IN_MNI"
    $singularity $FREESURFER_CONTAINER /bin/bash -c "$CMD_convert_T1; $CMD_convert_FLAIR; $CMD_convert_FLAIR_BIASCORR"

fi

###############################################################################################################################################################
# The ultimate masking game - create wm masks for filtering of segmentations
###############################################################################################################################################################
# Define inputs
ASEG_freesurfer=data/freesurfer/$1/mri/aseg.mgz
TEMPLATE_native=data/freesurfer/$1/mri/rawavg.mgz
T1_MASK=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-brain_mask.nii.gz
FLAIR=data/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz
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
CMD_new_brainmask="fslmaths $T1_MASK -sub $RIBBONMASK $BRAINWITHOUTRIBBON_MASK"
CMD_final_mask="fslmaths $BRAINWITHOUTRIBBON_MASK -mul $VENTRICLEWMWMHMASK $BRAINWITHOUTRIBBON_MASK"
CMD_final_mask_in_FLAIR="antsApplyTransforms -i $BRAINWITHOUTRIBBON_MASK -r $FLAIR -t $T1_TO_FLAIR_WARP -o $BRAINWITHOUTRIBBON_MASK_FLAIR"
CMD_BINARIZE_FINAL_MASK_FLAIR="fslmaths $BRAINWITHOUTRIBBON_MASK_FLAIR -bin $BRAINWITHOUTRIBBON_MASK_FLAIR"

( cp -ruvfL $ENV_DIR/freesurfer_license.txt $FREESURFER_CONTAINER/opt/$FREESURFER_VERSION/.license )

if [ ! -f $BRAINWITHOUTRIBBON_MASK_FLAIR ]; then

# Execute 
    $singularity $FREESURFER_CONTAINER /bin/bash -c "$CMD_prepare_wmmask; $CMD_convert_wmmask"
    $singularity $FSL_CONTAINER /bin/bash -c "$CMD_create_wmmask_right; $CMD_create_wmmask_left; $CMD_merge_wmmasks; $CMD_create_freesurferwmh_mask; $CMD_create_ventriclemask_right; $CMD_create_ventriclemask_left; $CMD_merge_ventriclemasks; $CMD_create_ventriclewmmask; $CMD_create_ribbonmask_right; $CMD_create_ribbonmask_left; $CMD_merge_ribbonmasks; $CMD_threshold_ribbonmask; $CMD_threshold_ribbonmaskagain; $CMD_new_brainmask; $CMD_final_mask"
    $singularity $MRTRIX_CONTAINER /bin/bash -c "$CMD_final_mask_in_FLAIR; $CMD_BINARIZE_FINAL_MASK_FLAIR"

fi 

###############################################################################################################################################################
# create distancemap
###############################################################################################################################################################
# Define inputs
VENTRICLEMASK_T1=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-ventricle_mask.nii.gz
FLAIR=data/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz
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
    
    $singularity $MRTRIX_CONTAINER /bin/bash -c "$CMD_VENTRICLEMASK_TO_FLAIR"
    $singularity $FSL_CONTAINER /bin/bash -c "$CMD_BINARIZE_VENTRICLEMASK_FLAIR; $CMD_create_distancemap; $CMD_upperthreshold_distancemap; $CMD_make_peri_beautiful; $CMD_threshold_distancemap"

fi
###############################################################################################################################################################

