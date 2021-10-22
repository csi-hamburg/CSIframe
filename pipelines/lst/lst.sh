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
##### STEP 4: RUN LESION SEGMENTATION TOOLBOX
###############################################################################################################################################################
module load matlab/2019b
###############################################################################################################################################################

# Define inputs
T1=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz
FLAIR=data/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz

# Define outputs
T1_nii_name=${1}_ses-${SESSION}_desc-preproc_T1w.nii
T1_nii=$OUT_DIR/$T1_nii_name
FLAIR_nii_name=${1}_ses-${SESSION}_FLAIR.nii
FLAIR_nii=$OUT_DIR/$FLAIR_nii_name

# Define commands
CMD_convert_T1="mri_convert $T1 $T1_nii"
CMD_convert_FLAIR="mri_convert $FLAIR $FLAIR_nii"

# Execute
$singularity $FREESURFER_CONTAINER \
/bin/bash -c "$CMD_convert_T1; $CMD_convert_FLAIR"


if [ $ALGORITHM == "lga" ]; then

    # ps_LST_lga   Lesion segmentation by a lesion growth algorithm (LGA)
    # Part of the LST toolbox, www.statistical-modelling.de/lst.html
    # 
    # ps_LST_lga Lesion segmentation by the LGA requires a T1 and a FLAIR 
    # image. Furthermore, the user has to specify an initial threshold
    # (kappa). See Schmidt et al. (2012) for details.
    # 
    # This routine produces lesion probability maps (ples...), coregistered
    # bias corrected versions of the FLAIR inputs, a .mat-file with
    # information about the segmentation that is needed for a re-run of the 
    # algorithm, and a HTML report along with a folder if this option has 
    # been chosen desired.
    # 
    # ps_LST_lga asks the user for the input images (T1 and FLAIR) and sets
    # kappa to its default value (0.3). MRF parameter is set to 1 and, number 
    # of maximum iterations are 50 and a HTML report is produced.
    # 
    # ps_LST_lga(Vt1, Vf2, kappa, phi, maxiter, html) performs lesion 
    # segmentation for the image volumes given in Vt1 and Vf2. Both must be 
    # characters like a call from from spm_select. Initial thresholds are 
    # colectedInitial in kappa, MRF parameter in phi, number of maximum 
    # iterations in maxiter and a dummy for the HTML report in html. If the
    # last four arguments are missing they are replaced by their default
    # values, see above.
    # 
    # ps_LST_lga(job) Same as above but with job being a harvested job data
    # structure (see matlabbatch help).
    #
    # References
    # P. Schmidt, Gaser C., Arsic M., Buck D., F�rschler A., Berthele A., 
    # Hoshi M., Ilg R., Schmid V.J., Zimmer C., Hemmer B., and M�hlau M. An 
    # automated tool for detec- tion of FLAIR-hyperintense white-matter 
    # lesions in Multiple Sclerosis. NeuroImage, 59:3774?3783, 2012.

    # set an initial threshold for WMH segmentation
    
    # if not specified differently, following options of LGA algoritm are set: a MRT parameter in phi (default 1), the number of maximum iterations in maxiter (default 50) and HTML report (default yes).
    # ps_LST_lga(Vt1, Vf2, kappa, phi, maxiter, html)

    ###############################################################################################################################################################
    # Outputs generated:
        # lesion probability maps (ples...) in T1
        # coregistered bias corrected version of the FLAIR inputs
        # a .mat-file with information about the segmentation that is needed for a re-run of the algorithm 
        # a HTML report along with a folder if this option has been chosen desired
    ###############################################################################################################################################################

    kappa=0.15

    # Execute 
    matlab -nosplash -nodesktop -nojvm -batch \
    "addpath(genpath('$ENV_DIR/spm12')); ps_LST_lga('/work/fatx405/projects/CSI_TEST/data/lst/$1/ses-${SESSION}/anat/$T1_nii_name', '/work/fatx405/projects/CSI_TEST/data/lst/$1/ses-${SESSION}/anat/$FLAIR_nii_name', $kappa); quit"

fi

###############################################################################################################################################################
###############################################################################################################################################################

if [ $ALGORITHM == "lpa" ]; then

    # ps_LST_lpa   Lesion segmentation by a lesion predicialgorithm (LGA)
    # Part of the LST toolbox, www.statistical-modelling.de/lst.html
    #
    # ps_LST_lpa Lesion segmentation by the LPA requires a FLAIR image only. 
    # However, the user is free to choose an additional image that serves as 
    # a reference image during a coregistration step before the main lesion 
    # segmentation. This may be helpful if the dimension of the FLAIR image 
    # is low or if the goal of the lesion segmentation is to fill lesions in 
    # T1 images. Beside that no additional parameters need to be set. No
    # other parameters need to be set by the user.
    #
    # This routine produces lesion probability maps (ples...), [coregistered]
    # bias corrected versions of the FLAIR inputs, a .mat-file with
    # information about the segmentation that is needed for a re-run of the 
    # algorithm, and a HTML report along with a folder if this option has 
    # been chosen desired. See the documentation for details.
    #
    # ps_LST_lpa asks the user for the input images (FLAIR and optional
    # reference images). A HTML report is produced by default.
    #
    # ps_LST_lpa(Vf2, Vref, html) performs lesion 
    # segmentation for the FLAIR volumes given in Vf2 and reference volumes 
    # given in Vref. The letter can be left empty. If specified, both must be
    # characters like a call from from spm_select. The last argument is  a 
    # dummy for the HTML reports. If the last argument ismissing it is
    # replaced by its default value, see above.
    #
    # ps_LST_lpa(job) Same as above but with job being a harvested job data
    # structure (see matlabbatch help).

    ###############################################################################################################################################################
    # Outputs generated:
        # lesion probability maps (ples...) in FLAIR and - if given - in reference space (T1)
        # coregistered bias corrected version of the FLAIR inputs
        # a .mat-file with information about the segmentation that is needed for a re-run of the algorithm 
        # a HTML report along with a folder if this option has been chosen desired
    ###############################################################################################################################################################

    # Execute 
    matlab -nosplash -nodesktop -nojvm -batch \
    "addpath(genpath('$ENV_DIR/spm12')); ps_LST_lpa('/work/fatx405/projects/CSI_TEST/data/lst/$1/ses-${SESSION}/anat/$FLAIR_nii_name', '/work/fatx405/projects/CSI_TEST/data/lst/$1/ses-${SESSION}/anat/$T1_nii_name'); quit"

fi
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

