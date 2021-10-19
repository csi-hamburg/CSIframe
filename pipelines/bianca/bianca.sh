#!/bin/bash

# Set output directory
OUT_DIR=data/bianca/$1/ses-${SESSION}/anat/
[ ! -d $OUT_DIR ] && mkdir -p $OUT_DIR

# SET VARIABLES FOR CONTAINER TO BE USED
FSL_VERSION=fsl-6.0.3
FSL_CONTAINER=$ENV_DIR/$FSL_VERSION
FREESURFER_VERSION=freesurfer-7.1.1
FREESURFER_CONTAINER=$ENV_DIR/$FREESURFER_VERSION
MRTRIX_CONTAINER=$ENV_DIR/mrtrix3-3.0.2
###############################################################################################################################################################

singularity="singularity run --cleanenv --userns -B $PROJ_DIR -B $TMP_DIR/:/tmp"

###############################################################################################################################################################
##### STEP 1: REGISTRATION OF T1 AND T1 MASK ON FLAIR
###############################################################################################################################################################
# Define inputs
T1=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz
T1_MASK=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-brain_mask.nii.gz
FLAIR=data/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz

# Define outputs
T1_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii.gz
T1_TO_FLAIR_WARP=$OUT_DIR/${1}_ses-${SESSION}_from-T1w_to-FLAIR_mode-image_xfm.txt
T1_MASK_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brain_mask.nii.gz

# Define commands
CMD_T1_TO_FLAIR="flirt -in $T1 -ref $FLAIR -omat $T1_TO_FLAIR_WARP -out $T1_IN_FLAIR -v"
CMD_T1_MASK_TO_FLAIR="flirt -in $T1_MASK -ref $FLAIR -init $T1_TO_FLAIR_WARP -out $T1_MASK_IN_FLAIR -v -applyxfm"

# Execute 
$singularity \
$FSL_CONTAINER \
/bin/bash -c "$CMD_T1_TO_FLAIR; $CMD_T1_MASK_TO_FLAIR"
###############################################################################################################################################################







###############################################################################################################################################################
##### STEP 2: MASKING OF T1 MASK IN FLAIR SPACE
###############################################################################################################################################################
# Define inputs
T1_MASK_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brain_mask.nii.gz
T1_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii.gz
FLAIR=data/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz

# Define outputs
FLAIR_BIASCORR=$OUT_DIR/${1}_ses-${SESSION}_desc-biascorr_FLAIR.nii.gz
T1_BRAIN_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brain_T1w.nii.gz
T1_MASK_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brain_mask.nii.gz
FLAIR_BRAIN=$OUT_DIR/${1}_ses-${SESSION}_desc-brain_FLAIR.nii.gz

# Define commands
CMD_MASK_THRESH="mrthreshold $T1_MASK_IN_FLAIR -abs 0.95 $T1_MASK_IN_FLAIR --force"
CMD_MASKING_T1_IN_FLAIR="mrcalc $T1_MASK_IN_FLAIR $T1_IN_FLAIR -mult $T1_BRAIN_IN_FLAIR --force"
CMD_BIASCORR_FLAIR="N4BiasFieldCorrection -d 3 -i $FLAIR -x $T1_MASK_IN_FLAIR -o $FLAIR_BIASCORR --verbose 1"
CMD_MASKING_FLAIR="mrcalc $T1_MASK_IN_FLAIR $FLAIR_BIASCORR -mult $FLAIR_BRAIN --force"

# Execute
$singularity \
$MRTRIX_CONTAINER \
/bin/bash -c "$CMD_MASK_THRESH; $CMD_MASKING_T1_IN_FLAIR; $CMD_BIASCORR_FLAIR; $CMD_MASKING_FLAIR"
###############################################################################################################################################################







###############################################################################################################################################################
##### STEP 3: REGISTER FLAIR IMAGE ON MNI
###############################################################################################################################################################
# Define inputs 
FLAIR_BRAIN=$OUT_DIR/${1}_ses-${SESSION}_desc-brain_FLAIR.nii.gz
MNI_TEMPLATE=/opt/$FSL_VERSION/data/standard/MNI152_T1_1mm_brain.nii.gz 

# Define outputs
FLAIR_TO_MNI_WARP=$OUT_DIR/${1}_ses-${SESSION}_from_FLAIR_to-MNI_mode-image_xfm.txt
FLAIR_IN_MNI=$OUT_DIR/${1}_ses-${SESSION}_space-MNI_desc-brain_FLAIR.nii.gz

# Define commands
CMD_flirt="flirt -in $FLAIR_BRAIN -ref $MNI_TEMPLATE -omat $FLAIR_TO_MNI_WARP -out $FLAIR_IN_MNI -v "

# Execute 
#-i $MNI_TEMPLATE also needed for command but datalad run first checks the existence of the file which will cause error prior to loading the fsl container
$singularity \
$FSL_CONTAINER \
$CMD_flirt
###############################################################################################################################################################








###############################################################################################################################################################
##### STEP 4: CREATE WM MASK 
###############################################################################################################################################################
# Define inputs
ASEG_freesurfer=data/freesurfer/$1/mri/aseg.mgz
TEMPLATE_native=data/freesurfer/$1/mri/rawavg.mgz
T1_TO_FLAIR_WARP=$OUT_DIR/${1}_ses-${SESSION}_from-T1w_to-FLAIR_mode-image_xfm.txt
FLAIR_BRAIN=$OUT_DIR/${1}_ses-${SESSION}_desc-brain_FLAIR.nii.gz


# Define outputs
ASEG_native=$OUT_DIR/${1}_ses-${SESSION}_space-T1_aseg.mgz
ASEG_nii=$OUT_DIR/${1}_ses-${SESSION}_space-T1_aseg.nii.gz
WM_right=$OUT_DIR/${1}_ses-${SESSION}_space-T1_hemi-R_desc-wm_mask.nii.gz 
WM_left=$OUT_DIR/${1}_ses-${SESSION}_space-T1_hemi-L_desc-wm_mask.nii.gz 
WMMASK_T1=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-wm_mask.nii.gz 
WMMASK_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wm_mask.nii.gz

# Define commands
CMD_prepare_wmmask="mri_label2vol --seg $ASEG_freesurfer --temp $TEMPLATE_native --o $ASEG_native --regheader $ASEG_freesurfer"
CMD_convert_wmmask="mri_convert $ASEG_native $ASEG_nii"
CMD_create_wmmask_right="fslmaths $ASEG_nii -thr 41 -uthr 41 -bin $WM_right"
CMD_create_wmmask_left="fslmaths $ASEG_nii -thr 2 -uthr 2 -bin $WM_left"
CMD_merge_wmmasks="fslmaths $WM_right -add $WM_left -bin $WMMASK_T1"
CMD_register_wmmask="flirt -in $WMMASK_T1 -ref $FLAIR_BRAIN -applyxfm -init $T1_TO_FLAIR_WARP -out $WMMASK_FLAIR"
CMD_threshold_wmmask="fslmaths $WMMASK_FLAIR -bin $WMMASK_FLAIR"

( cp -ruvfL $ENV_DIR/freesurfer_license.txt $FREESURFER_CONTAINER/opt/$FREESURFER_VERSION/.license )

# Execute 
$singularity \
$FREESURFER_CONTAINER \
/bin/bash -c "$CMD_prepare_wmmask; $CMD_convert_wmmask"

$singularity \
$FSL_CONTAINER \
/bin/bash -c "$CMD_create_wmmask_right; $CMD_create_wmmask_left; $CMD_merge_wmmasks; $CMD_register_wmmask; $CMD_threshold_wmmask"
###############################################################################################################################################################








###############################################################################################################################################################
##### STEP 5: CREATE, REGISTER & THRESHOLD VENTRICLE MASK
###############################################################################################################################################################
# Define inputs
ASEG_nii=$OUT_DIR/${1}_ses-${SESSION}_space-T1_aseg.nii.gz
FLAIR_BRAIN=$OUT_DIR/${1}_ses-${SESSION}_desc-brain_FLAIR.nii.gz
T1_TO_FLAIR_WARP=$OUT_DIR/${1}_ses-${SESSION}_from-T1w_to-FLAIR_mode-image_xfm.txt
WMMASK_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wm_mask.nii.gz

# Define outputs
FREESURFER_WMH=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-freesurferwmh_mask.nii.gz
FREESURFER_WMH_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-freesurferwmh_mask.nii.gz
VENTRICLE_right=$OUT_DIR/${1}_ses-${SESSION}_space-T1_hemi-R_desc-ventricle_mask.nii.gz
VENTRICLE_left=$OUT_DIR/${1}_ses-${SESSION}_space-T1_hemi-L_desc-ventricle_mask.nii.gz
VENTRICLEMASK_T1=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-ventricle_mask.nii.gz
VENTRICLEMASK_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-ventricle_mask.nii.gz
VENTRICLEWMWMHMASK_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-ventriclewmwmh_mask.nii.gz


# Define commands
CMD_create_freesurferwmh_mask="fslmaths $ASEG_nii -thr 77 -uthr 77 -bin $FREESURFER_WMH"
CMD_register_freesurferwmh_mask="flirt -in $FREESURFER_WMH -ref $FLAIR_BRAIN -applyxfm -init $T1_TO_FLAIR_WARP -out $FREESURFER_WMH_FLAIR"
CMD_create_ventriclemask_right="fslmaths $ASEG_nii -thr 43 -uthr 43 -bin $VENTRICLE_right"
CMD_create_ventriclemask_left="fslmaths $ASEG_nii -thr 4 -uthr 4 -bin $VENTRICLE_left"
CMD_merge_ventriclemasks="fslmaths $VENTRICLE_right -add $VENTRICLE_left -bin $VENTRICLEMASK_T1"
CMD_register_ventriclemask="flirt -in $VENTRICLEMASK_T1 -ref $FLAIR_BRAIN -applyxfm -init $T1_TO_FLAIR_WARP -out $VENTRICLEMASK_FLAIR"
CMD_threshold_ventriclemask="fslmaths $VENTRICLEMASK_FLAIR -thr 0.95 -bin $VENTRICLEMASK_FLAIR"
CMD_create_ventriclewmmask="fslmaths $VENTRICLEMASK_FLAIR -add $WMMASK_FLAIR -add $FREESURFER_WMH_FLAIR -bin $VENTRICLEWMWMHMASK_FLAIR"

# Execute 
$singularity \
$FSL_CONTAINER \
/bin/bash -c "$CMD_create_freesurferwmh_mask; $CMD_register_freesurferwmh_mask; $CMD_create_ventriclemask_right; $CMD_create_ventriclemask_left; $CMD_merge_ventriclemasks; $CMD_register_ventriclemask; $CMD_threshold_ventriclemask; $CMD_create_ventriclewmmask"
###############################################################################################################################################################





###############################################################################################################################################################
##### STEP 6: PREPARE MASK FOR BIANCA
###############################################################################################################################################################
# Define inputs
ASEG_nii=$OUT_DIR/${1}_ses-${SESSION}_space-T1_aseg.nii.gz
T1_TO_FLAIR_WARP=$OUT_DIR/${1}_ses-${SESSION}_from-T1w_to-FLAIR_mode-image_xfm.txt
FLAIR_BRAIN=$OUT_DIR/${1}_ses-${SESSION}_desc-brain_FLAIR.nii.gz
T1_MASK_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brain_mask.nii.gz
VENTRICLEWMWMHMASK_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-ventriclewmwmh_mask.nii.gz


# Define outputs
RIBBON_right=$OUT_DIR/${1}_ses-${SESSION}_space-T1_hemi-R_desc-ribbon_mask.nii.gz 
RIBBON_left=$OUT_DIR/${1}_ses-${SESSION}_space-T1_hemi-L_desc-ribbon_mask.nii.gz 
RIBBONMASK_T1=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-ribbon_mask.nii.gz
RIBBONMASK_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-ribbon_mask.nii.gz
BRAINWITHOUTRIBBON_MASK=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brainwithoutribbon_mask.nii.gz


# Define commands
CMD_create_ribbonmask_right="fslmaths $ASEG_nii -thr 42 -uthr 42 -bin $RIBBON_right"
CMD_create_ribbonmask_left="fslmaths $ASEG_nii -thr 3 -uthr 3 -bin $RIBBON_left"
CMD_merge_ribbonmasks="fslmaths $RIBBON_right -add $RIBBON_left -bin $RIBBONMASK_T1"
CMD_register_ribbonmask="flirt -in $RIBBONMASK_T1 -ref $FLAIR_BRAIN -applyxfm -init $T1_TO_FLAIR_WARP -out $RIBBONMASK_FLAIR"
CMD_threshold_ribbonmask="fslmaths $RIBBONMASK_FLAIR -bin -dilM $RIBBONMASK_FLAIR"
CMD_new_brainmask="fslmaths $T1_MASK_IN_FLAIR -sub $RIBBONMASK_FLAIR $BRAINWITHOUTRIBBON_MASK"
CMD_final_mask="fslmaths $BRAINWITHOUTRIBBON_MASK -mul $VENTRICLEWMWMHMASK_FLAIR $BRAINWITHOUTRIBBON_MASK "


# Execute 
$singularity \
$FSL_CONTAINER \
/bin/bash -c "$CMD_create_ribbonmask_right; $CMD_create_ribbonmask_left; $CMD_merge_ribbonmasks; $CMD_register_ribbonmask; $CMD_threshold_ribbonmask; $CMD_new_brainmask; $CMD_final_mask"

###############################################################################################################################################################









###############################################################################################################################################################
##### STEP 7: EXECUTE BIANCA AND POST PROCESS SEGMENTATION
###############################################################################################################################################################

# the classifier is trained on N=100 HCHS subjects.
# Input for the training was a brainextracted FLAIR, a T1 in FLAIR space, a mat file with the FLAIR-2-MNI warp and manually segmented WMH masks.
# Manually segmented WMH masks contain overlap of segmentation of Marvin and Carola.
# to have full documentation: the following command with the specified flags was executed for the training:
# bianca --singlefile=masterfile.txt --labelfeaturenum=4 --brainmaskfeaturenum=1 --querysubjectnum=1 --trainingnums=all --featuresubset=1,2 --matfeaturenum=3 \
# --trainingpts=2000 --nonlespts=10000 --selectpts=noborder -o sub-00012_bianca_output -v --saveclassifierdata=$SCRIPT_DIR/classifierdata

# we now determined to choose a threshold of 0.75 for the bianca segmentation, which is in between the very strict threshold of 0.95 which we applied in the \
# old analysis and the very generous threshold of 0.5 which looks a bit oversegmented but overall good.

###############################################################################################################################################################
# Define inputs 
FLAIR_BRAIN=$OUT_DIR/${1}_ses-${SESSION}_desc-brain_FLAIR.nii.gz
T1_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii.gz
FLAIR_TO_MNI_WARP=$OUT_DIR/${1}_ses-${SESSION}_from_FLAIR_to-MNI_mode-image_xfm.txt
CLASSIFIER=data/bianca/sourcedata/classifierdata_hchs100
BRAINWITHOUTRIBBON_MASK=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brainwithoutribbon_mask.nii.gz


# Define outputs
MASTERFILE=$OUT_DIR/${1}_ses-${SESSION}_masterfile.txt
echo "$FLAIR_BRAIN $T1_IN_FLAIR $FLAIR_TO_MNI_WARP" > $MASTERFILE
SEGMENTATION=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_mask.nii.gz
SEGMENTATION1=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_mask1.nii.gz
SEGMENTATION2=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_mask2.nii.gz
SEGMENTATION3=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_mask3.nii.gz


# Define commands
CMD_run_bianca="bianca --singlefile=$MASTERFILE --brainmaskfeaturenum=1 --querysubjectnum=1 --featuresubset=1,2 --matfeaturenum=3 -o $SEGMENTATION -v --loadclassifierdata=$CLASSIFIER"
CMD_overlay_wmmask="fslmaths $SEGMENTATION -mul $BRAINWITHOUTRIBBON_MASK $SEGMENTATION1"
CMD_threshold_segmentation="cluster --in=$SEGMENTATION1 --thresh=0.9 --osize=$SEGMENTATION2"
CMD_thresholdcluster_segmentation="fslmaths $SEGMENTATION2 -thr 3 -bin $SEGMENTATION3"


# Execute 
$singularity \
$FSL_CONTAINER \
/bin/bash -c "$CMD_run_bianca; $CMD_overlay_wmmask; $CMD_threshold_segmentation; $CMD_thresholdcluster_segmentation"
###############################################################################################################################################################










###############################################################################################################################################################
##### STEP 8: CREATE & THRESHOLD DISTANCEMAP
###############################################################################################################################################################
# Define inputs
VENTRICLEMASK_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-ventricle_mask.nii.gz
T1_MASK_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brain_mask.nii.gz

# Define outputs
DISTANCEMAP=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_distancemap.nii.gz
WMMASK_peri=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmperi_mask.nii.gz
WMMASK_deep=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmdeep_mask.nii.gz

# Define commands
CMD_create_distancemap="distancemap -i $VENTRICLEMASK_FLAIR -m $T1_MASK_IN_FLAIR -o $DISTANCEMAP"
CMD_upperthreshold_distancemap="fslmaths $DISTANCEMAP -uthr 10 -bin $WMMASK_peri"
CMD_threshold_distancemap="fslmaths $DISTANCEMAP -thr 10 -bin $WMMASK_deep"

# Execute 
$singularity \
$FSL_CONTAINER \
/bin/bash -c "$CMD_create_distancemap; $CMD_upperthreshold_distancemap; $CMD_threshold_distancemap"
###############################################################################################################################################################










###############################################################################################################################################################
##### STEP 9: MASK BIANCA OUTPUT FOR PERIVENTRICULAR / DEEP WHITE MATTER
###############################################################################################################################################################
# Define inputs
SEGMENTATION=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_mask.nii.gz
WMMASK_peri=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmperi_mask.nii.gz
WMMASK_deep=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmdeep_mask.nii.gz

# Define outputs
SEGMENTATION_peri=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmhperi_mask.nii.gz
SEGMENTATION_deep=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmhdeep_mask.nii.gz

# Define commands
CMD_segementation_filterperi="fslmaths $SEGMENTATION -mas $WMMASK_peri $SEGMENTATION_peri"
CMD_segmentation_filterdeep="fslmaths $SEGMENTATION -mas $WMMASK_deep $SEGMENTATION_deep"

# Execute 
$singularity \
$FSL_CONTAINER \
/bin/bash -c "$CMD_segementation_filterperi; $CMD_segmentation_filterdeep"
###############################################################################################################################################################











###############################################################################################################################################################
##### STEP 10: THRESHOLD WMH SEGMENTATION AND RUN BIANCA CLUSTER STATS
###############################################################################################################################################################
# Define inputs
SEGMENTATION=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_mask.nii.gz
SEGMENTATION_peri=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmhperi_mask.nii.gz
SEGMENTATION_deep=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmhdeep_mask.nii.gz

# Define outputs
STATS=$OUT_DIR/${1}_ses-${SESSION}_desc-wmh_mincluster5.txt
PERI_STATS=$OUT_DIR/${1}_ses-${SESSION}_desc-periwmh_mincluster5.txt
DEEP_STATS=$OUT_DIR/${1}_ses-${SESSION}_desc-deepwmh_mincluster5.txt

# Define commands
CMD_extract_stats_WMH="bianca_cluster_stats $SEGMENTATION 0 5 > $STATS"
CMD_extract_stats_periWMH="bianca_cluster_stats $SEGMENTATION_peri 0 5 > $PERI_STATS"
CMD_extract_stats_deepWMH="bianca_cluster_stats $SEGMENTATION_deep 0 5 > $DEEP_STATS"

# Execute 
$singularity \
$FSL_CONTAINER \
/bin/bash -c "$CMD_extract_stats_WMH; $CMD_extract_stats_periWMH; $CMD_extract_stats_deepWMH"
###############################################################################################################################################################
