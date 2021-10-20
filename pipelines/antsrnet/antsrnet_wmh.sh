#!/bin/bash

# Set output directory
OUT_DIR=data/lst/$1/ses-${SESSION}/anat/
[ ! -d $OUT_DIR ] && mkdir -p $OUT_DIR

# SET VARIABLES FOR CONTAINER TO BE USED
FSL_VERSION=fsl-6.0.3
FSL_CONTAINER=$ENV_DIR/$FSL_VERSION
FREESURFER_VERSION=freesurfer-7.1.1
FREESURFER_CONTAINER=$ENV_DIR/$FREESURFER_VERSION
###############################################################################################################################################################

singularity="singularity run --cleanenv --userns -B $PROJ_DIR -B $TMP_DIR/:/tmp"

###############################################################################################################################################################
















###############################################################################################################################################################
##### STEP 1: CREATE A WM MASK
###############################################################################################################################################################
# Define inputs
ASEG_freesurfer=data/freesurfer/$1/mri/aseg.mgz
TEMPLATE_native=data/freesurfer/$1/mri/rawavg.mgz 

# Define outputs
ASEG_native=/tmp/${1}_ses-${SESSION}_space-T1_aseg.mgz
ASEG_nii=/tmp/${1}_ses-${SESSION}_space-T1_aseg.nii.gz
WM_right=/tmp/${1}_ses-${SESSION}_space-T1_hemi-R_desc-wm_mask.nii.gz 
WM_left=/tmp/${1}_ses-${SESSION}_space-T1_hemi-L_desc-wm_mask.nii.gz 
WMMASK_T1=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-wm_mask.nii.gz 

# Define commands
CMD_prepare_wmmask="mri_label2vol --seg $ASEG_freesurfer --temp $TEMPLATE_native --o $ASEG_native --regheader $ASEG_freesurfer"
CMD_convert_wmmask="mri_convert $ASEG_native $ASEG_nii"
CMD_create_wmmask_right="fslmaths $ASEG_nii -thr 41 -uthr 41 -bin $WM_right"
CMD_create_wmmask_left="fslmaths $ASEG_nii -thr 2 -uthr 2 -bin $WM_left"
CMD_merge_wmmasks="fslmaths $WM_right -add $WM_left -bin $WMMASK_T1"

#( cp -ruvfL $ENV_DIR/freesurfer_license.txt $FREESURFER_CONTAINER/opt/$FREESURFER_VERSION/.license )

export FS_LICENSE=$ENV_DIR/freesurfer_license.txt

# Execute 
$singularity $FREESURFER_CONTAINER \
/bin/bash -c "$CMD_prepare_wmmask; $CMD_convert_wmmask"

$singularity $FSL_CONTAINER \
/bin/bash -c "$CMD_create_wmmask_right; $CMD_create_wmmask_left; $CMD_merge_wmmasks"

###############################################################################################################################################################








###############################################################################################################################################################
##### STEP 2: CREATE, REGISTER & THRESHOLD VENTRICLE MASK
###############################################################################################################################################################
# Define inputs
ASEG_nii=/tmp/${1}_ses-${SESSION}_space-T1_aseg.nii.gz
WMMASK_T1=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-wm_mask.nii.gz 

# Define outputs
FREESURFER_WMH=/tmp/${1}_ses-${SESSION}_space-T1_desc-freesurferwmh_mask.nii.gz
VENTRICLE_right=/tmp/${1}_ses-${SESSION}_space-T1_hemi-R_desc-ventricle_mask.nii.gz
VENTRICLE_left=/tmp/${1}_ses-${SESSION}_space-T1_hemi-L_desc-ventricle_mask.nii.gz
VENTRICLEMASK=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-ventricle_mask.nii.gz
VENTRICLEWMWMHMASK=/tmp/${1}_ses-${SESSION}_space-T1_desc-ventriclewmwmh_mask.nii.gz

# Define commands
CMD_create_freesurferwmh_mask="fslmaths $ASEG_nii -thr 77 -uthr 77 -bin $FREESURFER_WMH"
CMD_create_ventriclemask_right="fslmaths $ASEG_nii -thr 43 -uthr 43 -bin $VENTRICLE_right"
CMD_create_ventriclemask_left="fslmaths $ASEG_nii -thr 4 -uthr 4 -bin $VENTRICLE_left"
CMD_merge_ventriclemasks="fslmaths $VENTRICLE_right -add $VENTRICLE_left -bin $VENTRICLEMASK"
CMD_create_ventriclewmmask="fslmaths $VENTRICLEMASK -add $WMMASK_T1 -add $FREESURFER_WMH -bin $VENTRICLEWMWMHMASK"

# Execute 
$singularity $FSL_CONTAINER \
/bin/bash -c "$CMD_create_freesurferwmh_mask; $CMD_create_ventriclemask_right; $CMD_create_ventriclemask_left; $CMD_merge_ventriclemasks; $CMD_create_ventriclewmmask"
###############################################################################################################################################################










###############################################################################################################################################################
##### STEP 3: PREPARE MASK FOR THRESHOLDING WMH 
###############################################################################################################################################################
# Define inputs
ASEG_nii=/tmp/${1}_ses-${SESSION}_space-T1_aseg.nii.gz
T1_MASK=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-brain_mask.nii.gz
VENTRICLEWMWMHMASK=/tmp/${1}_ses-${SESSION}_space-T1_desc-ventriclewmwmh_mask.nii.gz


# Define outputs
RIBBON_right=/tmp/${1}_ses-${SESSION}_space-T1_hemi-R_desc-ribbon_mask.nii.gz 
RIBBON_left=/tmp/${1}_ses-${SESSION}_space-T1_hemi-L_desc-ribbon_mask.nii.gz 
RIBBONMASK=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-ribbon_mask.nii.gz
BRAINWITHOUTRIBBON_MASK=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-brainwithoutribbon_mask.nii.gz


# Define commands
CMD_create_ribbonmask_right="fslmaths $ASEG_nii -thr 42 -uthr 42 -bin $RIBBON_right"
CMD_create_ribbonmask_left="fslmaths $ASEG_nii -thr 3 -uthr 3 -bin $RIBBON_left"
CMD_merge_ribbonmasks="fslmaths $RIBBON_right -add $RIBBON_left -bin $RIBBONMASK"
CMD_dilate_ribbonmask="fslmaths $RIBBONMASK -dilM $RIBBONMASK"
CMD_new_brainmask="fslmaths $T1_MASK -sub $RIBBONMASK $BRAINWITHOUTRIBBON_MASK"
CMD_final_mask="fslmaths $BRAINWITHOUTRIBBON_MASK -mul $VENTRICLEWMWMHMASK $BRAINWITHOUTRIBBON_MASK "


# Execute 
$singularity $FSL_CONTAINER \
/bin/bash -c "$CMD_create_ribbonmask_right; $CMD_create_ribbonmask_left; $CMD_merge_ribbonmasks; $CMD_dilate_ribbonmask; $CMD_new_brainmask; $CMD_final_mask"
###############################################################################################################################################################









###############################################################################################################################################################
##### STEP 4: REGSITER FLAIR IN T1 & RUN ANTSRNET
###############################################################################################################################################################
# Define inputs
FLAIR=data/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz
T1=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz
T1_MASK=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-brain_mask.nii.gz


# Define outputs
FLAIR_IN_T1=$OUT_DIR/${1}_ses-${SESSION}_space-T1_FLAIR.nii.gz
FLAIR_TO_T1_WARP=$OUT_DIR/${1}_ses-${SESSION}_from-FLAIR_to-T1_mode-image_xfm.txt
FLAIR_BIASCORR=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-biascorr_FLAIR.nii.gz
FLAIR_BRAIN=data/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_space-T1_desc-brain_FLAIR.nii.gz


# Define commands
CMD_FLAIR_TO_T1="flirt -in $FLAIR -ref $T1 -omat $FLAIR_TO_T1_WARP -out $FLAIR_IN_T1 -v"
CMD_BIASCORR_FLAIR="N4BiasFieldCorrection -d 3 -i $FLAIR_IN_T1 -x $T1_MASK_IN_FLAIR -o $FLAIR_BIASCORR --verbose 1"
CMD_MASK_FLAIR="flsmaths $FLAIR -mul $T1_MASK $FLAIR_BRAIN"

CMD_ANTSRNET="R -e '(sysuMediaWmhSegmentation())'"

# Execute 

###############################################################################################################################################################












##############################################################################################################################################################
##### STEP 5: RUN POST-PROCESSING OF SEGMENTATION
###############################################################################################################################################################

# Define inputs
SEGMENTATION=$OUT_DIR/ples_${ALGORITHM}_${kappa}_rm${1}_ses-${SESSION}_FLAIR.nii
BRAINWITHOUTRIBBON_MASK=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-brainwithoutribbon_mask.nii.gz

# Define outputs
SEGMENTATION2=$OUT_DIR/ples_${ALGORITHM}_${kappa}_rm${1}_ses-${SESSION}_FLAIR2.nii

# Define commands
CMD_filter_segmentation="fslmaths $SEGMENTATION -mul $BRAINWITHOUTRIBBON_MASK -bin $SEGMENTATION2"

# Execute
$singularity $FSL_CONTAINER \
/bin/bash -c "$CMD_filter_segmentation"
###############################################################################################################################################################











###############################################################################################################################################################
##### STEP 6: CREATE & THRESHOLD DISTANCEMAP
###############################################################################################################################################################
# Define inputs
VENTRICLEMASK=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-ventricle_mask.nii.gz
T1_MASK=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-brain_mask.nii.gz

# Define outputs
DISTANCEMAP=$OUT_DIR/${1}_ses-${SESSION}_space-T1_distancemap.nii.gz
WMMASK_peri=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-wmperi_mask.nii.gz
WMMASK_deep=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-wmdeep_mask.nii.gz

# Define commands
CMD_create_distancemap="distancemap -i $VENTRICLEMASK -m $T1_MASK -o $DISTANCEMAP"
CMD_upperthreshold_distancemap="fslmaths $DISTANCEMAP -uthr 10 -bin $WMMASK_peri"
CMD_threshold_distancemap="fslmaths $DISTANCEMAP -thr 10 -bin $WMMASK_deep"

# Execute 
$singularity $FSL_CONTAINER \
/bin/bash -c "$CMD_create_distancemap; $CMD_upperthreshold_distancemap; $CMD_threshold_distancemap"
###############################################################################################################################################################










###############################################################################################################################################################
##### STEP 7: MASK SEGMENTATION FOR PERIVENTRICULAR / DEEP WHITE MATTER
###############################################################################################################################################################
# Define inputs
SEGMENTATION2=$OUT_DIR/ples_${ALGORITHM}_${kappa}_rm${1}_ses-${SESSION}_FLAIR2.nii
WMMASK_peri=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-wmperi_mask.nii.gz
WMMASK_deep=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-wmdeep_mask.nii.gz

# Define outputs
SEGMENTATION_peri=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-wmhperi_mask.nii
SEGMENTATION_deep=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-wmhdeep_mask.nii

# Define commands
CMD_segementation_filterperi="fslmaths $SEGMENTATION2 -mas $WMMASK_peri $SEGMENTATION_peri"
CMD_segmentation_filterdeep="fslmaths $SEGMENTATION2 -mas $WMMASK_deep $SEGMENTATION_deep"

# Execute 
$singularity $FSL_CONTAINER \
/bin/bash -c "$CMD_segementation_filterperi; $CMD_segmentation_filterdeep"
###############################################################################################################################################################








###############################################################################################################################################################
##### STEP 8: ADDITIONAL OUTPUT WHICH MIGHT BE USEFUL IN THE FUTURE
###############################################################################################################################################################
# for future analysis, we also create:
    # brain extracted T1
    # FLAIR in MNI
    # WMH total, WMH peri and WMH deep in MNI


# maybe also?:
    # a NAWM mask 
    # a brain extracted FLAIR -> missing FLAIR mask (create with ants brain extraction?)
###############################################################################################################################################################

# Define inputs
T1=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz
T1_MASK=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-brain_mask.nii.gz
FLAIR=data/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz
MNI_TEMPLATE=/opt/$FSL_VERSION/data/standard/MNI152_T1_1mm_brain.nii.gz 
SEGMENTATION2=$OUT_DIR/ples_${ALGORITHM}_${kappa}_rm${1}_ses-${SESSION}_FLAIR2.nii
SEGMENTATION_peri=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-wmhperi_mask.nii
SEGMENTATION_deep=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-wmhdeep_mask.nii
T1_TO_MNI_WARP=$OUT_DIR/${1}_ses-${SESSION}_from-T1w_to-MNI152NLin2009cAsym_mode-image_xfm.h5

# Define outputs
T1=$OUT_DIR/${1}_ses-${SESSION}_desc-brain_T1w.nii.gz
FLAIR_TO_MNI_WARP=$OUT_DIR/${1}_ses-${SESSION}_from_FLAIR_to-MNI_mode-image_xfm.txt
FLAIR_IN_MNI=$OUT_DIR/${1}_ses-${SESSION}_space-MNI_FLAIR.nii.gz
WMH_IN_MNI=$OUT_DIR/ples_${ALGORITHM}_${kappa}_rm${1}_ses-${SESSION}_space-MNI_FLAIR.nii
PERI_IN_MNI=$OUT_DIR/${1}_ses-${SESSION}_space-MNI_desc-wmhperi_mask.nii
DEEP_IN_MNI=$OUT_DIR/${1}_ses-${SESSION}_space-MNI_desc-wmhdeep_mask.nii

# Define commands
CMD_MASK_T1="mrcalc $T1_MASK $T1 -mult $T1_BRAIN --force"
CMD_FLAIR_in_MNI="flirt -in $FLAIR -ref $MNI_TEMPLATE -omat $FLAIR_TO_MNI_WARP -out $FLAIR_IN_MNI -v "
CMD_WMH_in_MNI="flirt -in $SEGMENTATION2 -ref $MNI_TEMPLATE -applyxfm -init $T1_TO_MNI_WARP -out $WMH_IN_MNI -v "
CMD_PERI_in_MNI="flirt -in $SEGMENTATION_peri -ref $MNI_TEMPLATE -applyxfm -init $T1_TO_MNI_WARP -out $PERI_IN_MNI -v "
CMD_DEEP_in_MNI="flirt -in $SEGMENTATION_deep -ref $MNI_TEMPLATE -applyxfm -init $T1_TO_MNI_WARP -out $DEEP_IN_MNI -v "

# Execute
$singularity $FREESURFER_CONTAINER \
/bin/bash -c "$CMD_MASK_T1"

$singularity $FSL_CONTAINER \
/bin/bash -c "$CMD_FLAIR_in_MNI; $CMD_WMH_in_MNI; $CMD_PERI_in_MNI; $CMD_DEEP_in_MNI"

###############################################################################################################################################################

