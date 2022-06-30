#!/usr/bin/env bash

###################################################################################################################
# Preprocessing of FLAIR and T1 and creation of input files for WMH segmentation 
#                                                                                                                 
# Pipeline specific dependencies:                                                                                 
#   [pipelines which need to be run first]                                                                        
#       - wmh_01_prep in wmh
#       - wmh_02_segment in wmh
#       - wmh_03_combine in wmh
#       - fmriprep  
#       - freesurfer                                                                                                    
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

for sub in $sublist; do 

    # Define subject specific temporary directory on $SCRATCH_DIR
    export TMP_DIR=$SCRATCH_DIR/$sub/tmp/;   [ ! -d $TMP_DIR ] && mkdir -p $TMP_DIR
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
    OUT_DIR=$DATA_DIR/$PIPELINE/$sub/ses-${SESSION}/anat/
    [ ! -d $OUT_DIR ] && mkdir -p $OUT_DIR
    ALGORITHM_OUT_DIR=$OUT_DIR/$ALGORITHM/
    DERIVATIVE_dir=$DATA_DIR/$PIPELINE/derivatives
    [ ! -d $DERIVATIVE_dir ] && mkdir -p $DERIVATIVE_dir

    # To make I/O more efficient read/write outputs from/to $SCRATCH
    [ -d $TMP_IN ] && cp -rf $BIDS_DIR/$sub $BIDS_DIR/dataset_description.json $TMP_IN 
    [ -d $TMP_OUT ] && mkdir -p $TMP_OUT/wmh $TMP_OUT/wmh

    # $MRTRIX_TMPFILE_DIR should be big and writable
    export MRTRIX_TMPFILE_DIR=/tmp

    # Pipeline execution
    ###############################################################################################################################################################
    # Register segmentation in T1 and MNI
    ###############################################################################################################################################################

    # Define inputs
    SEGMENTATION=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
    T1=$DATA_DIR/fmriprep/$sub/ses-${SESSION}/anat/${sub}_ses-${SESSION}_desc-preproc_T1w.nii.gz
    MNI_TEMPLATE=$ENV_DIR/standard/tpl-MNI152NLin2009cAsym_res-01_desc-brain_T1w.nii.gz
    T1_TO_MNI_WARP=$DATA_DIR/fmriprep/$sub/ses-${SESSION}/anat/${sub}_ses-${SESSION}_from-T1w_to-MNI152NLin2009cAsym_mode-image_xfm.h5
    FLAIR_TO_T1_WARP=$OUT_DIR/${sub}_ses-${SESSION}_from-T1_to-FLAIR_InverseComposite.h5

    # Define outputs
    SEGMENTATION_T1=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-T1_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
    SEGMENTATION_MNI=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-MNI_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz

    # Define commands
    CMD_SEGMENTATION_TO_T1="antsApplyTransforms -d 3 -i $SEGMENTATION -r $T1 -t $FLAIR_TO_T1_WARP -o $SEGMENTATION_T1"
    CMD_SEGMENTATION_TO_MNI="antsApplyTransforms -d 3 -i $SEGMENTATION -r $MNI_TEMPLATE -t $FLAIR_TO_T1_WARP -t $T1_TO_MNI_WARP -o $SEGMENTATION_MNI"

    # Execute
    $singularity_mrtrix /bin/bash -c "$CMD_SEGMENTATION_TO_T1; $CMD_SEGMENTATION_TO_MNI"


    ###############################################################################################################################################################
    # Lesion Filling with FSL -> in T1 space
    ###############################################################################################################################################################

    # Define inputs
    T1=$DATA_DIR/fmriprep/$sub/ses-${SESSION}/anat/${sub}_ses-${SESSION}_desc-preproc_T1w.nii.gz
    SEGMENTATION_T1=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-T1_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
    # Define outputs
    T1_FILLED=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-preproc_desc-desc-${ALGORITHM}filled_T1w.nii.gz
    # Define commands
    CMD_LESION_FILLING="LesionFilling 3 $T1 $SEGMENTATION_T1 $T1_FILLED"
    # Execute
    $singularity_mrtrix /bin/bash -c "$CMD_LESION_FILLING"


    ###############################################################################################################################################################
    # create NAWM mask
    ###############################################################################################################################################################

    # Define inputs
    SEGMENTATION=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
    WMMASK_T1=$OUT_DIR/${sub}_ses-${SESSION}_space-T1_desc-wm_mask.nii.gz 
    FLAIR=$DATA_DIR/raw_bids/$sub/ses-${SESSION}/anat/${sub}_ses-${SESSION}_FLAIR.nii.gz
    T1_TO_FLAIR_WARP=$OUT_DIR/${sub}_ses-${SESSION}_from-T1_to-FLAIR_Composite.h5
    MNI_TEMPLATE=$ENV_DIR/standard/tpl-MNI152NLin2009cAsym_res-01_desc-brain_T1w.nii.gz
    T1_TO_MNI_WARP=$DATA_DIR/fmriprep/$sub/ses-${SESSION}/anat/${sub}_ses-${SESSION}_from-T1w_to-MNI152NLin2009cAsym_mode-image_xfm.h5
    T1=$DATA_DIR/fmriprep/$sub/ses-${SESSION}/anat/${sub}_ses-${SESSION}_desc-preproc_T1w.nii.gz
    FLAIR_TO_T1_WARP=$OUT_DIR/${sub}_ses-${SESSION}_from-T1_to-FLAIR_InverseComposite.h5

    # Define outputs
    WMMASK_FLAIR=$OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-wm_mask.nii.gz 
    NAWM_MASK=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-nawm_desc-${ALGORITHM}_mask.nii.gz
    NAWM_MASK_MNI=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-MNI_desc-masked_desc-nawm_desc-${ALGORITHM}_mask.nii.gz
    NAWM_MASK_T1=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-T1_desc-masked_desc-nawm_desc-${ALGORITHM}_mask.nii.gz

    # Define commands
    CMD_WMMASK_TO_FLAIR="antsApplyTransforms -i $WMMASK_T1 -r $FLAIR -t $T1_TO_FLAIR_WARP -o $WMMASK_FLAIR"
    CMD_BIN_WMMASK_FLAIR="fslmaths $WMMASK_FLAIR -bin $WMMASK_FLAIR"
    CMD_NAWM_MASK="fslmaths $WMMASK_FLAIR -sub $SEGMENTATION $NAWM_MASK"
    CMD_NAWM_MASK_TO_T1="antsApplyTransforms -d 3 -i $NAWM_MASK -r $T1 -t $FLAIR_TO_T1_WARP -o $NAWM_MASK_T1"
    CMD_NAWM_MASK_TO_MNI="antsApplyTransforms -d 3 -i $NAWM_MASK -r $MNI_TEMPLATE -t $FLAIR_TO_T1_WARP -t $T1_TO_MNI_WARP -o $NAWM_MASK_MNI"

    # Execute
    $singularity_mrtrix /bin/bash -c "$CMD_WMMASK_TO_FLAIR"
    $singularity_fsl /bin/bash -c "$CMD_BIN_WMMASK_FLAIR; $CMD_NAWM_MASK"
    $singularity_mrtrix /bin/bash -c "$CMD_NAWM_MASK_TO_T1; $CMD_NAWM_MASK_TO_MNI"


    ###############################################################################################################################################################
    # create periventricular / deep WMH masks
    ###############################################################################################################################################################

    # Define inputs
    SEGMENTATION=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
    WMMASK_peri=$OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-wmperi_mask.nii.gz
    WMMASK_deep=$OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-wmdeep_mask.nii.gz
    T1=$DATA_DIR/fmriprep/$sub/ses-${SESSION}/anat/${sub}_ses-${SESSION}_desc-preproc_T1w.nii.gz
    MNI_TEMPLATE=$ENV_DIR/standard/tpl-MNI152NLin2009cAsym_res-01_desc-brain_T1w.nii.gz
    T1_TO_MNI_WARP=$DATA_DIR/fmriprep/$sub/ses-${SESSION}/anat/${sub}_ses-${SESSION}_from-T1w_to-MNI152NLin2009cAsym_mode-image_xfm.h5
    FLAIR_TO_T1_WARP=$OUT_DIR/${sub}_ses-${SESSION}_from-T1_to-FLAIR_InverseComposite.h5

    # Define outputs
    SEGMENTATION_peri=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmhperi_desc-${ALGORITHM}_mask.nii.gz
    SEGMENTATION_deep=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmhdeep_desc-${ALGORITHM}_mask.nii.gz
    SEGMENTATION_PERI_T1=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-T1_desc-masked_desc-wmhperi_desc-${ALGORITHM}_mask.nii.gz
    SEGMENTATION_DEEP_T1=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-T1_desc-masked_desc-wmhdeep_desc-${ALGORITHM}_mask.nii.gz
    SEGMENTATION_DEEP_T1=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-MNI_desc-masked_desc-wmhperi_desc-${ALGORITHM}_mask.nii.gz
    SEGMENTATION_DEEP_MNI=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-MNI_desc-masked_desc-wmhdeep_desc-${ALGORITHM}_mask.nii.gz

    # Define commands
    CMD_segmentation_filterperi="fslmaths $SEGMENTATION -mas $WMMASK_peri $SEGMENTATION_peri"
    CMD_segmentation_filterdeep="fslmaths $SEGMENTATION -mas $WMMASK_deep $SEGMENTATION_deep"
    CMD_SEGMENTATION_PERI_TO_T1="antsApplyTransforms -d 3 -i $SEGMENTATION -r $T1 -t $FLAIR_TO_T1_WARP -o $SEGMENTATION_PERI_T1"
    CMD_SEGMENTATION_PERI_TO_MNI="antsApplyTransforms -d 3 -i $SEGMENTATION -r $MNI_TEMPLATE -t $FLAIR_TO_T1_WARP -t $T1_TO_MNI_WARP -o $SEGMENTATION_PERI_MNI"
    CMD_SEGMENTATION_DEEP_TO_T1="antsApplyTransforms -d 3 -i $SEGMENTATION -r $T1 -t $FLAIR_TO_T1_WARP -o $SEGMENTATION_DEEP_T1"
    CMD_SEGMENTATION_DEEP_TO_MNI="antsApplyTransforms -d 3 -i $SEGMENTATION -r $MNI_TEMPLATE -t $FLAIR_TO_T1_WARP -t $T1_TO_MNI_WARP -o $SEGMENTATION_DEEP_MNI"
    CMD_PERI_IN_T1_BIN="fslmaths $SEGMENTATION_PERI_T1 -bin $SEGMENTATION_PERI_T1"
    CMD_PERI_IN_MNI_BIN="fslmaths $SEGMENTATION_DEEP_T1 -bin $SEGMENTATION_DEEP_T1"
    CMD_DEEP_IN_T1_BIN="fslmaths $SEGMENTATION_DEEP_T1 -bin $SEGMENTATION_DEEP_T1"
    CMD_DEEP_IN_MNI_BIN="fslmaths $SEGMENTATION_DEEP_MNI -bin $SEGMENTATION_DEEP_MNI"

    # Execute
    $singularity_fsl /bin/bash -c "$CMD_segmentation_filterperi; $CMD_segmentation_filterdeep"
    $singularity_mrtrix /bin/bash -c "$CMD_SEGMENTATION_PERI_TO_T1; $CMD_SEGMENTATION_PERI_TO_MNI; $CMD_SEGMENTATION_DEEP_TO_T1; $CMD_SEGMENTATION_DEEP_TO_MNI"
    $singularity_fsl /bin/bash -c "$CMD_PERI_IN_T1_BIN; $CMD_PERI_IN_MNI_BIN; $CMD_DEEP_IN_T1_BIN; $CMD_DEEP_IN_MNI_BIN"


    ###############################################################################################################################################################
    # create disconnectome
    ###############################################################################################################################################################
    module load aws-cli

    # Define inputs
    TRACKING_FILE=${sub}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_space-T1w_desc-tracks_ifod2.tck
    FODS=${sub}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_space-T1w_desc-siftweights_ifod2.csv
    SCHAEFER_PARC_1=${sub}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_space-T1w_desc-schaefer100x7_atlas.mif.gz
    SCHAEFER_PARC_2=${sub}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_space-T1w_desc-schaefer200x7_atlas.mif.gz
    SCHAEFER_PARC_3=${sub}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_space-T1w_desc-schaefer400x7_atlas.mif.gz
    SEGMENTATION_T1=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-T1_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz

    # Define outputs
    TRACKING_FILE_T1=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_space-T1w_desc-WMHconnectome_ifod2.tck
    OUTPUT_CSV_1_sift=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-schaefer100x7_desc-WMH_desc-sift_connectome.csv
    ASSIGNMENTS_1_sift=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-schaefer100x7_desc-WMH_desc-sift_assignments.csv
    OUTPUT_CSV_2_sift=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-schaefer200x7_desc-WMH_desc-sift_connectome.csv
    ASSIGNMENTS_2_sift=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-schaefer200x7_desc-WMH_desc-sift_assignments.csv
    OUTPUT_CSV_3_sift=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-schaefer400x7_desc-WMH_desc-sift_connectome.csv
    ASSIGNMENTS_3_sift=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-schaefer400x7_desc-WMH_desc-sift_assignments.csv
    OUTPUT_CSV_1=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-schaefer100x7_desc-WMH_connectome.csv
    ASSIGNMENTS_1=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-schaefer100x7_desc-WMH_assignments.csv
    OUTPUT_CSV_2=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-schaefer200x7_desc-WMH_connectome.csv
    ASSIGNMENTS_2=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-schaefer200x7_desc-WMH_assignments.csv
    OUTPUT_CSV_3=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-schaefer400x7_desc-WMH_connectome.csv
    ASSIGNMENTS_3=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-schaefer400x7_desc-WMH_assignments.csv


    # Define commands
    CMD_TCKEDIT="tckedit $OUT_DIR/$TRACKING_FILE $TRACKING_FILE_T1 -exclude $SEGMENTATION_T1 -inverse -force"
    CMD_CONNECTOME_1_sift="tck2connectome $TRACKING_FILE_T1 $OUT_DIR/$SCHAEFER_PARC_1 $OUTPUT_CSV_1_sift -tck_weights_in $OUT_DIR/$FODS -out_assignments $ASSIGNMENTS_1_sift -force"
    CMD_CONNECTOME_2_sift="tck2connectome $TRACKING_FILE_T1 $OUT_DIR/$SCHAEFER_PARC_2 $OUTPUT_CSV_2_sift -tck_weights_in $OUT_DIR/$FODS -out_assignments $ASSIGNMENTS_2_sift -force"
    CMD_CONNECTOME_3_sift="tck2connectome $TRACKING_FILE_T1 $OUT_DIR/$SCHAEFER_PARC_3 $OUTPUT_CSV_3_sift -tck_weights_in $OUT_DIR/$FODS -out_assignments $ASSIGNMENTS_3_sift -force"
    CMD_CONNECTOME_1="tck2connectome $TRACKING_FILE_T1 $OUT_DIR/$SCHAEFER_PARC_1 $OUTPUT_CSV_1 -out_assignments $ASSIGNMENTS_1 -force"
    CMD_CONNECTOME_2="tck2connectome $TRACKING_FILE_T1 $OUT_DIR/$SCHAEFER_PARC_2 $OUTPUT_CSV_2 -out_assignments $ASSIGNMENTS_2 -force"
    CMD_CONNECTOME_3="tck2connectome $TRACKING_FILE_T1 $OUT_DIR/$SCHAEFER_PARC_3 $OUTPUT_CSV_3 -out_assignments $ASSIGNMENTS_3 -force"

    # Execute
    aws s3 cp --endpoint-url https://s3-uhh.lzs.uni-hamburg.de s3://uke-csi-hchs/qsirecon/${sub}/ses-${SESSION}/dwi/$TRACKING_FILE $OUT_DIR/
    aws s3 cp --endpoint-url https://s3-uhh.lzs.uni-hamburg.de s3://uke-csi-hchs/qsirecon/${sub}/ses-${SESSION}/dwi/$FODS $OUT_DIR/
    aws s3 cp --endpoint-url https://s3-uhh.lzs.uni-hamburg.de s3://uke-csi-hchs/qsirecon/${sub}/ses-${SESSION}/dwi/$SCHAEFER_PARC_1 $OUT_DIR/
    aws s3 cp --endpoint-url https://s3-uhh.lzs.uni-hamburg.de s3://uke-csi-hchs/qsirecon/${sub}/ses-${SESSION}/dwi/$SCHAEFER_PARC_2 $OUT_DIR/
    aws s3 cp --endpoint-url https://s3-uhh.lzs.uni-hamburg.de s3://uke-csi-hchs/qsirecon/${sub}/ses-${SESSION}/dwi/$SCHAEFER_PARC_3 $OUT_DIR/

    $singularity_mrtrix /bin/bash -c "$CMD_TCKEDIT; $CMD_CONNECTOME_1_sift; $CMD_CONNECTOME_2_sift; $CMD_CONNECTOME_3_sift; $CMD_CONNECTOME_1; $CMD_CONNECTOME_2; $CMD_CONNECTOME_3"

    rm $OUT_DIR/$TRACKING_FILE
    rm $OUT_DIR/$FODS
    rm $OUT_DIR/$SCHAEFER_PARC_1
    rm $OUT_DIR/$SCHAEFER_PARC_2
    rm $OUT_DIR/$SCHAEFER_PARC_3


    ###############################################################################################################################################################
    # read out WMH volume
    ###############################################################################################################################################################

    # Define inputs
    SEGMENTATION=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
    SEGMENTATION_peri=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmhperi_desc-${ALGORITHM}_mask.nii.gz
    SEGMENTATION_deep=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmhdeep_desc-${ALGORITHM}_mask.nii.gz

    # Define outputs
    WMH_peri_vol=$DERIVATIVE_dir/${sub}_ses-1_${ALGORITHM}_peri_wmhvolume.csv
    WMH_deep_vol=$DERIVATIVE_dir/${sub}_ses-1_${ALGORITHM}_deep_wmhvolume.csv

    # Define commands and execute
    $singularity_fsl /bin/bash -c "$(echo fslstats $SEGMENTATION_peri -V) > $WMH_peri_vol"
    [ ! -f $SEGMENTATION_peri ] && echo "na na" > $WMH_peri_vol
    $singularity_fsl /bin/bash -c "$(echo fslstats $SEGMENTATION_deep -V) > $WMH_deep_vol"
    [ ! -f $SEGMENTATION_deep ] && echo "na na" > $WMH_deep_vol

done