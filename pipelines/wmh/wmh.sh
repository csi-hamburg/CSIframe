#!/bin/bash

# this script works with 2 additional options:
# 1) biascorrected FLAIR yes / no 
#     -> this option is only available for bianca and antsrnet algorithm. LGA / LPA & samseg makes automatic bias-correction intern
#     -> samseg moreover explicitly documents to not do any prior bias-correction
# 2) masking game yes / no
#     -> after segmentation, you can choose to overlay an wm mask to exclude all non-wm voxels from the segmentation
#     -> if chosen, this masking game is played in all algorithms

# Set output directory
SUBJECT_OUT_DIR=data/${PIPELINE}/$1/ses-${SESSION}/anat/
COMBINATION_OUT_DIR=data/${PIPELINE}/$1/ses-${SESSION}/anat/combinations

MIX=${BIASCORR}_${MASKINGGAME}

[ $MIX == y_y ] && ALGORITHM_OUT_DIR=data/${PIPELINE}/$1/ses-${SESSION}/anat/${ALGORITHM}_biascorr_masking/
[ $MIX == y_n ] && ALGORITHM_OUT_DIR=data/${PIPELINE}/$1/ses-${SESSION}/anat/${ALGORITHM}_biascorr/
[ $MIX == n_y ] && ALGORITHM_OUT_DIR=data/${PIPELINE}/$1/ses-${SESSION}/anat/${ALGORITHM}_masking/
[ $MIX == n_n ] && ALGORITHM_OUT_DIR=data/${PIPELINE}/$1/ses-${SESSION}/anat/${ALGORITHM}/

[ ! -d $SUBJECT_OUT_DIR ] && mkdir -p $SUBJECT_OUT_DIR
[ ! -d $ALGORITHM_OUT_DIR ] && mkdir -p $ALGORITHM_OUT_DIR

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













###############################################################################################################################################################
##### PREPARE IMAGES FOR SEGMENTATION. 
# all steps run independent from the algorithm chosen. 
###############################################################################################################################################################
# registration T1 / T1_MASK in FLAIR
###############################################################################################################################################################
# Define inputs 
FLAIR=data/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz
T1=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz
T1_MASK=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-brain_mask.nii.gz

# Define outputs
T1_IN_FLAIR=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii.gz
T1_TO_FLAIR_WARP=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_from-T1w_to-FLAIR_mode-image_xfm.txt
T1_MASK_IN_FLAIR=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brain_mask.nii.gz

# Define commands
CMD_T1_TO_FLAIR="flirt -in $T1 -ref $FLAIR -omat $T1_TO_FLAIR_WARP -out $T1_IN_FLAIR -v"
CMD_T1_MASK_TO_FLAIR="flirt -in $T1_MASK -ref $FLAIR -applyxfm -init $T1_TO_FLAIR_WARP -out $T1_MASK_IN_FLAIR -v"
CMD_MASK_THRESH="mrthreshold $T1_MASK_IN_FLAIR -abs 0.95 $T1_MASK_IN_FLAIR --force"

# Execute 
$singularity $FSL_CONTAINER /bin/bash -c "$CMD_T1_TO_FLAIR; $CMD_T1_MASK_TO_FLAIR"  
$singularity $MRTRIX_CONTAINER /bin/bash -c "$CMD_MASK_THRESH"

###############################################################################################################################################################
# convert T1 / FLAIR in nii for lpa/lga
###############################################################################################################################################################
# Define inputs 
FLAIR=data/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz
T1=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz

# Define outputs
T1_nii=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_desc-preproc_T1w.nii
FLAIR_nii=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_FLAIR.nii

# Define commands
CMD_convert_T1="mri_convert $T1 $T1_nii"
CMD_convert_FLAIR="mri_convert $FLAIR $FLAIR_nii"

# Execute 
$singularity $FREESURFER_CONTAINER /bin/bash -c "$CMD_convert_T1; $CMD_convert_FLAIR"

###############################################################################################################################################################
# FLAIR bias-correction 
###############################################################################################################################################################
# Define inputs 
FLAIR=data/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz
T1_MASK_IN_FLAIR=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brain_mask.nii.gz

# Define outputs
FLAIR_BIASCORR=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_desc-biascorr_FLAIR.nii.gz
FLAIR_BIASCORR_nii=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_desc-biascorr_FLAIR.nii

# Define commands
CMD_BIASCORR_FLAIR="N4BiasFieldCorrection -d 3 -i $FLAIR -x $T1_MASK_IN_FLAIR -o $FLAIR_BIASCORR --verbose 1" 
CMD_convert_FLAIR_BIASCORR="mri_convert $FLAIR_BIASCORR $FLAIR_BIASCORR_nii"

# Execute 
$singularity $MRTRIX_CONTAINER /bin/bash -c "$CMD_BIASCORR_FLAIR"
$singularity $FREESURFER_CONTAINER /bin/bash -c "$CMD_convert_FLAIR_BIASCORR"

###############################################################################################################################################################
# FLAIR brain-extraction
###############################################################################################################################################################
# Define inputs 
FLAIR=data/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz
FLAIR_BIASCORR=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_desc-biascorr_FLAIR.nii.gz
T1_MASK_IN_FLAIR=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brain_mask.nii.gz

# Define outputs
FLAIR_BRAIN=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_desc-brain_FLAIR.nii.gz
FLAIR_BRAIN_BIASCORR=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_desc-biascorr_desc-brain_FLAIR.nii.gz

# Define commands
CMD_MASKING_FLAIR="mrcalc $T1_MASK_IN_FLAIR $FLAIR -mult $FLAIR_BRAIN --force"
CMD_MASKING_FLAIR_BIASCORR="mrcalc $T1_MASK_IN_FLAIR $FLAIR_BIASCORR -mult $FLAIR_BRAIN_BIASCORR --force"

# Execute
$singularity $MRTRIX_CONTAINER /bin/bash -c "$CMD_MASKING_FLAIR; $CMD_MASKING_FLAIR_BIASCORR"

###############################################################################################################################################################
# registration of FLAIR in mni. happens automatically with bias corrected flair. 
###############################################################################################################################################################
# Define inputs 
# moving image
FLAIR_BRAIN_BIASCORR=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_desc-biascorr_desc-brain_FLAIR.nii.gz
# fixed image
MNI_TEMPLATE=$ENV_DIR/standard/tpl-MNI152NLin2009cAsym_res-01_desc-brain_T1w.nii.gz

# Define outputs
FLAIR_TO_T1_WARP=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_space-MNI_desc-biascorr_desc-brain_FLAIRInverseComposite.h5
FLAIR_TO_MNI_WARP=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_space-MNI_desc-biascorr_desc-brain_FLAIRComposite.h5
FLAIR_IN_MNI=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_space-MNI_desc-biascorr_desc-brain_FLAIR.nii.gz

# Define commands
CMD_ANTS_REGISTRATION="antsRegistration \
--output [ $FLAIR_TO_MNI_WARP, $FLAIR_IN_MNI ] \
--collapse-output-transforms 0 \
--dimensionality 3 \
--initial-moving-transform [ $MNI_TEMPLATE, $FLAIR_BRAIN_BIASCORR, 1 ] \
--initialize-transforms-per-stage 0 \
--interpolation Linear \
--transform Rigid[ 0.1 ] \
--metric MI[ $MNI_TEMPLATE, $FLAIR_BRAIN_BIASCORR, 1, 32, Regular, 0.25 ] \
--convergence [ 10000x111110x11110x100, 1e-08, 10 ] \
--smoothing-sigmas 3.0x2.0x1.0x0.0vox \
--shrink-factors 8x4x2x1 \
--use-estimate-learning-rate-once 1 \
--use-histogram-matching 1 \
--transform Affine[ 0.1 ] \
--metric MI[ $MNI_TEMPLATE, $FLAIR_BRAIN_BIASCORR, 1, 32, Regular, 0.25 ] \
--convergence [ 10000x111110x11110x100, 1e-08, 10 ] \
--smoothing-sigmas 3.0x2.0x1.0x0.0vox \
--shrink-factors 8x4x2x1 \
--use-estimate-learning-rate-once 1 \
--use-histogram-matching 1 \
--transform SyN[ 0.2, 3.0, 0.0 ] \
--metric CC[ $MNI_TEMPLATE, $FLAIR_BRAIN_BIASCORR, 1, 4 ] \
--convergence [ 100x50x30x20, 1e-08, 10 ] \
--smoothing-sigmas 3.0x2.0x1.0x0.0vox \
--shrink-factors 8x4x2x1 \
--use-estimate-learning-rate-once 1 \
--use-histogram-matching 1 -v \
--winsorize-image-intensities [ 0.005, 0.995 ] \
--write-composite-transform 1"

if [ ! -f $FLAIR_TO_MNI_WARP ]; then 

    # Execute
    $singularity $MRTRIX_CONTAINER /bin/bash -c "$CMD_ANTS_REGISTRATION"

fi

###############################################################################################################################################################
# The ultimate masking game - create wm masks for filtering of segmentations
###############################################################################################################################################################

# Define inputs
ASEG_freesurfer=data/freesurfer/$1/mri/aseg.mgz
TEMPLATE_native=data/freesurfer/$1/mri/rawavg.mgz
T1_MASK=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-brain_mask.nii.gz
FLAIR=data/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz
T1_TO_FLAIR_WARP=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_from-T1w_to-FLAIR_mode-image_xfm.txt

# Define outputs
ASEG_native=/tmp/${1}_ses-${SESSION}_space-T1_aseg.mgz
ASEG_nii=/tmp/${1}_ses-${SESSION}_space-T1_aseg.nii.gz
WM_right=/tmp/${1}_ses-${SESSION}_space-T1_hemi-R_desc-wm_mask.nii.gz 
WM_left=/tmp/${1}_ses-${SESSION}_space-T1_hemi-L_desc-wm_mask.nii.gz 
WMMASK_T1=/tmp/${1}_ses-${SESSION}_space-T1_desc-wm_mask.nii.gz 
FREESURFER_WMH=/tmp/${1}_ses-${SESSION}_space-T1_desc-freesurferwmh_mask.nii.gz
VENTRICLE_right=/tmp/${1}_ses-${SESSION}_space-T1_hemi-R_desc-ventricle_mask.nii.gz
VENTRICLE_left=/tmp/${1}_ses-${SESSION}_space-T1_hemi-L_desc-ventricle_mask.nii.gz
VENTRICLEMASK_T1=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-ventricle_mask.nii.gz
VENTRICLEWMWMHMASK=/tmp/${1}_ses-${SESSION}_space-T1_desc-ventriclewmwmh_mask.nii.gz
RIBBON_right=/tmp/${1}_ses-${SESSION}_space-T1_hemi-R_desc-ribbon_mask.nii.gz 
RIBBON_left=/tmp/${1}_ses-${SESSION}_space-T1_hemi-L_desc-ribbon_mask.nii.gz 
RIBBONMASK=/tmp/${1}_ses-${SESSION}_space-T1_desc-ribbon_mask.nii.gz
BRAINWITHOUTRIBBON_MASK=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-brainwithoutribbon_mask.nii.gz
BRAINWITHOUTRIBBON_MASK_FLAIR=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brainwithoutribbon_mask.nii.gz

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
CMD_final_mask_in_FLAIR="flirt -in $BRAINWITHOUTRIBBON_MASK -ref $FLAIR -applyxfm -init $T1_TO_FLAIR_WARP -out $BRAINWITHOUTRIBBON_MASK_FLAIR -v"

( cp -ruvfL $ENV_DIR/freesurfer_license.txt $FREESURFER_CONTAINER/opt/$FREESURFER_VERSION/.license )

if [ ! -f $BRAINWITHOUTRIBBON_MASK_FLAIR ]; then

# Execute 
    $singularity $FREESURFER_CONTAINER /bin/bash -c "$CMD_prepare_wmmask; $CMD_convert_wmmask"
    $singularity $FSL_CONTAINER /bin/bash -c "$CMD_create_wmmask_right; $CMD_create_wmmask_left; $CMD_merge_wmmasks; $CMD_create_freesurferwmh_mask; $CMD_create_ventriclemask_right; $CMD_create_ventriclemask_left; $CMD_merge_ventriclemasks; $CMD_create_ventriclewmmask; $CMD_create_ribbonmask_right; $CMD_create_ribbonmask_left; $CMD_merge_ribbonmasks; $CMD_threshold_ribbonmask; $CMD_threshold_ribbonmaskagain; $CMD_new_brainmask; $CMD_final_mask; $CMD_final_mask_in_FLAIR"

fi 

###############################################################################################################################################################
# create distancemap
###############################################################################################################################################################
# Define inputs
VENTRICLEMASK_T1=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-ventricle_mask.nii.gz
FLAIR=data/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz
T1_TO_FLAIR_WARP=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_from-T1w_to-FLAIR_mode-image_xfm.txt
T1_MASK_IN_FLAIR=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brain_mask.nii.gz

# Define outputs
VENTRICLEMASK_FLAIR=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-ventricle_mask.nii.gz
DISTANCEMAP=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_distancemap.nii.gz
WMMASK_peri=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmperi_mask.nii.gz
WMMASK_deep=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmdeep_mask.nii.gz

# Define commands
CMD_VENTRICLEMASK_TO_FLAIR="flirt -in $VENTRICLEMASK_T1 -ref $FLAIR -applyxfm -init $T1_TO_FLAIR_WARP -out $VENTRICLEMASK_FLAIR -v"
CMD_create_distancemap="distancemap -i $VENTRICLEMASK_FLAIR -m $T1_MASK_IN_FLAIR -o $DISTANCEMAP"
CMD_upperthreshold_distancemap="fslmaths $DISTANCEMAP -uthr 10 -bin $WMMASK_peri"
CMD_threshold_distancemap="fslmaths $DISTANCEMAP -thr 10 -bin $WMMASK_deep"

# Execute 
if [ ! -f $DISTANCEMAP ]; then
    
    $singularity $FSL_CONTAINER /bin/bash -c "$CMD_VENTRICLEMASK_TO_FLAIR; $CMD_create_distancemap; $CMD_upperthreshold_distancemap; $CMD_threshold_distancemap"

fi
###############################################################################################################################################################










###############################################################################################################################################################
##### THE HEART OF THE SCRIPT - WMH SEGMENTATION & ALGORITHM-SPECIFIC POST-PROCESSING
###############################################################################################################################################################

# please define for each algorithm the output segmentation. we need this for further processing. 

if [ $ALGORITHM == "antsrnet" ]; then

    # Define inputs
    [ $BIASCORR == n ] && FLAIR=$FLAIR
    [ $BIASCORR == y ] && FLAIR=$FLAIR_BIASCORR
    T1_IN_FLAIR=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii.gz

    # Define outputs
    SEGMENTATION=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_mask.nii.gz
    export SEGMENTATION

    # Execute 
    $singularity $ANTSRNET_CONTAINER \
    Rscript -e "flair<-antsImageRead('$FLAIR'); t1<-antsImageRead('$T1_IN_FLAIR'); probabilitymask<-sysuMediaWmhSegmentation(flair, t1); antsImageWrite(probabilitymask, '$SEGMENTATION')"

elif [ $ALGORITHM == "bianca" ]; then

    # Define inputs 
    [ $BIASCORR == n ] && FLAIR_BRAIN=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_desc-brain_FLAIR.nii.gz
    [ $BIASCORR == y ] && FLAIR_BRAIN=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_desc-biascorr_desc-brain_FLAIR.nii.gz
    T1_IN_FLAIR=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii.gz
    FLAIR_TO_MNI_WARP=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_space-MNI_desc-biascorr_desc-brain_FLAIRComposite.h5
    CLASSIFIER=data/wmh/sourcedata/classifierdata_hchs100
    # the classifier is trained on N=100 HCHS subjects.
    # Input for the training was a brainextracted FLAIR, a T1 in FLAIR space, a mat file with the FLAIR-2-MNI warp and manually segmented WMH masks.
    # Manually segmented WMH masks contain overlap of segmentation of Marvin and Carola.
    # to have full documentation: the following command with the specified flags was executed for the training:
    # bianca --singlefile=masterfile.txt --labelfeaturenum=4 --brainmaskfeaturenum=1 --querysubjectnum=1 --trainingnums=all --featuresubset=1,2 --matfeaturenum=3 \
    # --trainingpts=2000 --nonlespts=10000 --selectpts=noborder -o sub-00012_bianca_output -v --saveclassifierdata=$SCRIPT_DIR/classifierdata
    # we now determined to choose a threshold of 0.75 for the bianca segmentation, which is in between the very strict threshold of 0.95 which we applied in the \
    # old analysis and the very generous threshold of 0.5 which looks a bit oversegmented but overall good.

    # Write masterfile
    MASTERFILE=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_masterfile.txt
    echo "$FLAIR_BRAIN $T1_IN_FLAIR $FLAIR_TO_MNI_WARP" > $MASTERFILE

    # Define outputs
    SEGMENTATION_raw=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_mask_raw.nii.gz
    SEGMENTATION_sized=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_mask_sized.nii.gz
    SEGMENTATION=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_mask.nii.gz

    # Define commands
    CMD_BIANCA="bianca --singlefile=$MASTERFILE --brainmaskfeaturenum=1 --querysubjectnum=1 --featuresubset=1,2 --matfeaturenum=3 -o $SEGMENTATION_raw -v --loadclassifierdata=$CLASSIFIER"
    CMD_threshold_segmentation="cluster --in=$SEGMENTATION_raw --osize=$SEGMENTATION_sized"
    CMD_thresholdcluster_segmentation="fslmaths $SEGMENTATION_sized -thr 3 -bin $SEGMENTATION"

    # Execute
    $singularity $FSL_CONTAINER /bin/bash -c "$CMD_BIANCA; $CMD_threshold_segmentation; $CMD_thresholdcluster_segmentation"

elif [ $ALGORITHM == "lga" ]; then

    module load matlab/2019b

    # Define inputs 
    T1_nii=/work/fatx405/projects/CSI_DEV/$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_desc-preproc_T1w.nii
    FLAIR_nii=/work/fatx405/projects/CSI_DEV/$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_FLAIR.nii
    export T1_nii
    export FLAIR_nii

    for kappa in 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5; do

        # Define outputs
        SEGMENTATION=$ALGORITHM_OUT_DIR/ples_lga_${kappa}_rm${1}_ses-${SESSION}_FLAIR.nii

        # Execute 
        matlab -nosplash -nodesktop -nojvm -batch "addpath(genpath('$ENV_DIR/spm12')); ps_LST_lga('$T1_nii', '$FLAIR_nii', $kappa); quit"

        mv $SUBJECT_OUT_DIR/ples_lga_${kappa}_rm${1}_ses-${SESSION}_FLAIR.nii $SEGMENTATION
        mv $SUBJECT_OUT_DIR/LST_* $ALGORITHM_OUT_DIR/
        mv $SUBJECT_OUT_DIR/report_LST_* $ALGORITHM_OUT_DIR/
        
    done

elif [ $ALGORITHM == "lpa" ]; then

    module load matlab/2019b

    # Define inputs 
    T1_nii=/work/fatx405/projects/CSI_DEV/$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_desc-preproc_T1w.nii
    FLAIR_nii=/work/fatx405/projects/CSI_DEV/$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_FLAIR.nii
    export T1_nii
    export FLAIR_nii

    # Define outputs
    SEGMENTATION=$ALGORITHM_OUT_DIR/ples_lpa_mr${1}_ses-${SESSION}_FLAIR.nii

    # Execute 
    matlab -nosplash -nodesktop -nojvm -batch "addpath(genpath('$ENV_DIR/spm12')); ps_LST_lpa('$FLAIR_nii', '$T1_nii'); quit"

    mv $SUBJECT_OUT_DIR/ples_lpa_mr${1}_ses-${SESSION}_FLAIR.nii $SEGMENTATION
    mv $SUBJECT_OUT_DIR/LST_* $ALGORITHM_OUT_DIR/
    mv $SUBJECT_OUT_DIR/report_LST_* $ALGORITHM_OUT_DIR/

elif [ $ALGORITHM == "samseg" ]; then

    # Define inputs
    FLAIR=data/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz
    T1_IN_FLAIR=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii.gz

    # Define outputs 
    SEGMENTED_BRAIN=$ALGORITHM_OUT_DIR/seg.mgz
    SEGMENTED_BRAIN_NIIGZ=$ALGORITHM_OUT_DIR/seg.nii.gz
    SEGMENTATION=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_mask.nii.gz

    # Define commands
    CMD_SAMSEG="run_samseg --input $FLAIR $T1_IN_FLAIR --output $ALGORITHM_OUT_DIR"
    CMD_CONVERT_SEG="mri_convert $SEGMENTED_BRAIN $SEGMENTED_BRAIN_NIIGZ"
    CMD_EXTRACT_WMH="fslmaths $SEGMENTED_BRAIN_NIIGZ -uthr 77 -thr 77 -bin $SEGMENTATION"

    # Execute
    $singularity $FREESURFER_CONTAINER /bin/bash -c "$CMD_SAMSEG; $CMD_CONVERT_SEG"
    $singularity $FSL_CONTAINER /bin/bash -c "$CMD_EXTRACT_WMH"

fi

###############################################################################################################################################################













###############################################################################################################################################################
##### POST-PROCESSING & MASKING GAME
###############################################################################################################################################################
# Masking Segmentation -> in FLAIR space
###############################################################################################################################################################
if [ $MASKINGGAME == y ]; then

    if [ $ALGORITHM == "lga" ]; then

        for kappa in 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5; do

            # Define inputs
            SEGMENTATION=$ALGORITHM_OUT_DIR/ples_lga_${kappa}_rm${1}_ses-${SESSION}_FLAIR.nii
            BRAINWITHOUTRIBBON_MASK_FLAIR=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brainwithoutribbon_mask.nii.gz

            # Define outputs 
            SEGMENTATION_FILTERED=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-${kappa}_desc-masked_desc-wmh_mask.nii.gz

            # Define commands
            CMD_MASKING_GAME="fslmaths $SEGMENTATION -mul $BRAINWITHOUTRIBBON_MASK_FLAIR $SEGMENTATION_FILTERED"

            # Execute
            $singularity $FSL_CONTAINER /bin/bash -c "$CMD_MASKING_GAME"

        done

    else 

        # Define inputs
        # one input is the segmented file. Depending on algorithm, the file has different names - all saved under the variable $SEGMENTATION.
        BRAINWITHOUTRIBBON_MASK_FLAIR=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brainwithoutribbon_mask.nii.gz

        # Define outputs 
        SEGMENTATION_FILTERED=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_mask.nii.gz

        # Define commands
        CMD_MASKING_GAME="fslmaths $SEGMENTATION -mul $BRAINWITHOUTRIBBON_MASK_FLAIR $SEGMENTATION_FILTERED"

        # Execute
        $singularity $FSL_CONTAINER /bin/bash -c "$CMD_MASKING_GAME"

    fi

fi 

###############################################################################################################################################################
# Register segmentation in T1 and MNI
###############################################################################################################################################################
if [ $ALGORITHM == "lga" ]; then

    # define different inputs and outputs

    for kappa in 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5; do

        # Define inputs
        [ $MASKINGGAME == n ] && SEGMENTATION=$ALGORITHM_OUT_DIR/ples_lga_${kappa}_rm${1}_ses-${SESSION}_FLAIR.nii
        [ $MASKINGGAME == y ] && SEGMENTATION=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-${kappa}_desc-masked_desc-wmh_mask.nii.gz
        T1=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz
        T1_TO_FLAIR_WARP=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_from-T1w_to-FLAIR_mode-image_xfm.txt
        MNI_TEMPLATE=$ENV_DIR/standard/tpl-MNI152NLin2009cAsym_res-01_desc-brain_T1w.nii.gz
        FLAIR_TO_MNI_WARP=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_space-MNI_desc-biascorr_desc-brain_FLAIRComposite.h5

        # Define outputs 
        FLAIR_TO_T1_WARP=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_from-FLAIR_to-T1_mode-image_xfm.txt
        [ $MASKINGGAME == n ] && SEGMENTATION_T1=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-${kappa}_desc-wmh_mask.nii.gz
        [ $MASKINGGAME == n ] && SEGMENTATION_MNI=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-MNI_desc-${kappa}_desc-wmh_mask.nii.gz
        [ $MASKINGGAME == y ] && SEGMENTATION_T1=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-${kappa}_desc-masked_desc-wmh_mask.nii.gz
        [ $MASKINGGAME == y ] && SEGMENTATION_MNI=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-MNI_desc-${kappa}_desc-masked_desc-wmh_mask.nii.gz

    done

else 

    # Define inputs
    # one input is the segmented file. Depending on algorithm, the file has different names - all saved under the variable $SEGMENTATION. only true if [ $MASKINGGAME == n ]
    [ $MASKINGGAME == y ] && SEGMENTATION=$SEGMENTATION_FILTERED
    T1=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz
    T1_TO_FLAIR_WARP=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_from-T1w_to-FLAIR_mode-image_xfm.txt
    MNI_TEMPLATE=$ENV_DIR/standard/tpl-MNI152NLin2009cAsym_res-01_desc-brain_T1w.nii.gz
    FLAIR_TO_MNI_WARP=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_space-MNI_desc-biascorr_desc-brain_FLAIRComposite.h5

    # Define outputs
    FLAIR_TO_T1_WARP=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_from-FLAIR_to-T1_mode-image_xfm.txt
    [ $MASKINGGAME == n ] && SEGMENTATION_T1=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-wmh_mask.nii.gz
    [ $MASKINGGAME == n ] && SEGMENTATION_MNI=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-MNI_desc-wmh_mask.nii.gz
    [ $MASKINGGAME == y ] && SEGMENTATION_T1=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-masked_desc-wmh_mask.nii.gz
    [ $MASKINGGAME == y ] && SEGMENTATION_MNI=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-MNI_desc-masked_desc-wmh_mask.nii.gz

    # Define commands
    CMD_INVERT_WARP="convert_xfm -omat $FLAIR_TO_T1_WARP -inverse $T1_TO_FLAIR_WARP"
    CMD_SEGMENTATION_TO_T1="flirt -in $SEGMENTATION -ref $T1 -applyxfm -init $FLAIR_TO_T1_WARP -out $SEGMENTATION_T1 -v"
    CMD_SEGMENTATION_TO_MNI="antsApplyTransforms -d 3 -i $SEGMENTATION -r $MNI_TEMPLATE -t $FLAIR_TO_MNI_WARP -o $SEGMENTATION_MNI"

    # Execute
    $singularity $FSL_CONTAINER /bin/bash -c "$CMD_INVERT_WARP; $CMD_SEGMENTATION_TO_T1"
    $singularity $MRTRIX_CONTAINER /bin/bash -c "$CMD_SEGMENTATION_TO_MNI"

fi 

###############################################################################################################################################################
# Lesion Filling with FSL -> in T1 space
###############################################################################################################################################################
# Define inputs
if [ ! $ALGORITHM == "lga" ]; then

    T1=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz
    WMMASK_T1=/tmp/${1}_ses-${SESSION}_space-T1_desc-wm_mask.nii.gz 
    [ $MASKINGGAME == n ] && SEGMENTATION_T1=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-wmh_mask.nii.gz
    [ $MASKINGGAME == y ] && SEGMENTATION_T1=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-masked_desc-wmh_mask.nii.gz

    # Define outputs
    T1_FILLED=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_desc-preproc_desc-filled_T1w.nii.gz

    # Define commands
    CMD_LESION_FILLING="lesion_filling -i $T1 -l $SEGMENTATION_T1 -w $WMMASK_T1 -o $T1_FILLED"

    # Execute
    $singularity $FSL_CONTAINER / bin/bash -c "$CMD_LESION_FILLING"

fi 

###############################################################################################################################################################
# create NAWM mask
###############################################################################################################################################################
if [ ! $ALGORITHM == "lga" ]; then

    # Define inputs
    # one input is the segmented file. Depending on algorithm, the file has different names - all saved under the variable $SEGMENTATION. only true if [ $MASKINGGAME == n ]
    [ $MASKINGGAME == y ] && SEGMENTATION=$SEGMENTATION_FILTERED
    WM_MASK=data/fmriprep/${1}/ses-${SESSION}/anat/${1}_ses-${SESSION}_label-WM_probseg.nii.gz
    FLAIR=data/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz
    T1_TO_FLAIR_WARP=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_from-T1w_to-FLAIR_mode-image_xfm.txt
    MNI_TEMPLATE=$ENV_DIR/standard/tpl-MNI152NLin2009cAsym_res-01_desc-brain_T1w.nii.gz
    FLAIR_TO_MNI_WARP=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_space-MNI_desc-biascorr_desc-brain_FLAIRComposite.h5
    T1=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz
    FLAIR_TO_T1_WARP=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_from-FLAIR_to-T1_mode-image_xfm.txt

    # Define outputs
    WM_MASK_FLAIR=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_label-WM_probseg.nii.gz
    [ $MASKINGGAME == n ] && NAWM_MASK=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-nawm_mask.nii.gz
    [ $MASKINGGAME == y ] && NAWM_MASK=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-nawm_mask.nii.gz
    [ $MASKINGGAME == n ] && NAWM_MASK_MNI=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-MNI_desc-nawm_mask.nii.gz
    [ $MASKINGGAME == y ] && NAWM_MASK_MNI=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-MNI_desc-masked_desc-nawm_mask.nii.gz
    [ $MASKINGGAME == n ] && NAWM_MASK_T1=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-nawm_mask.nii.gz
    [ $MASKINGGAME == y ] && NAWM_MASK_T1=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-masked_desc-nawm_mask.nii.gz

    # Define commands
    CMD_WMMASK_TO_FLAIR="flirt -in $WM_MASK -ref $FLAIR -applyxfm -init $T1_TO_FLAIR_WARP -out $WM_MASK_FLAIR -v"
    CMD_NAWM_MASK="fslmaths $WM_MASK_FLAIR -sub $SEGMENTATION $NAWM_MASK"
    CMD_NAWM_MASK_TO_T1="flirt -in $NAWM_MASK -ref $T1 -applyxfm -init $FLAIR_TO_T1_WARP -out $NAWM_MASK_T1 -v"
    CMD_NAWM_MASK_TO_MNI="antsApplyTransforms -d 3 -i $NAWM_MASK -r $MNI_TEMPLATE -t $FLAIR_TO_MNI_WARP -o $NAWM_MASK_MNI"

    # Execute
    $singularity $FSL_CONTAINER /bin/bash -c "$CMD_WMMASK_TO_FLAIR; $CMD_NAWM_MASK; $CMD_NAWM_MASK_TO_T1"
    $singularity $MRTRIX_CONTAINER /bin/bash -c "$CMD_NAWM_MASK_TO_MNI"

fi

###############################################################################################################################################################
# create periventricular / deep WMH masks
###############################################################################################################################################################
if [ ! $ALGORITHM == "lga" ]; then

    # Define inputs
    # one input is the segmented file. Depending on algorithm, the file has different names - all saved under the variable $SEGMENTATION. only true if [ $MASKINGGAME == n ]
    [ $MASKINGGAME == y ] && SEGMENTATION=$SEGMENTATION_FILTERED
    WMMASK_peri=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmperi_mask.nii.gz
    WMMASK_deep=$SUBJECT_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmdeep_mask.nii.gz

    # Define outputs
    [ $MASKINGGAME == n ] && SEGMENTATION_peri=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmhperi_mask.nii.gz
    [ $MASKINGGAME == y ] && SEGMENTATION_peri=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmhperi_mask.nii.gz
    [ $MASKINGGAME == n ] && SEGMENTATION_deep=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmhdeep_mask.nii.gz
    [ $MASKINGGAME == y ] && SEGMENTATION_deep=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmhdeep_mask.nii.gz

    # Define commands
    CMD_segmentation_filterperi="fslmaths $SEGMENTATION -mas $WMMASK_peri $SEGMENTATION_peri"
    CMD_segmentation_filterdeep="fslmaths $SEGMENTATION -mas $WMMASK_deep $SEGMENTATION_deep"

    # Execute
    $singularity $FSL_CONTAINER /bin/bash -c "$CMD_segmentation_filterperi; $CMD_segmentation_filterdeep"

fi

###############################################################################################################################################################










###############################################################################################################################################################
##### COMBINATION OF ALGORITHMS
###############################################################################################################################################################

    