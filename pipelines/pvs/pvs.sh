#!/usr/bin/env bash

###################################################################################################################
# Postprocessing of PVS segmentation output.                                                                      #
# This includes thresholding of masks and extraction of individual volumes / counts.                              #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - fmriprep (for freesurfer output)                                                                        #
#       - fmriprep (for anat preprocessing incl. spatial normalization)                                           #
#   [container]                                                                                                   #
#       - pvsseg-4.0.sif                                                                                          #      
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

# apptainer container version and command
container_pvsseg=pvsseg-4.0.sif      
apptainer_pvsseg="apptainer run --cleanenv --no-home --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_pvsseg"

container_fsl=fsl-6.0.7.13.sif
apptainer_fsl="apptainer run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_fsl" 

container_ants=ants-2.5.4.sif      
apptainer_ants="apptainer run --cleanenv --no-home --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_ants"

# # To make I/O more efficient read/write outputs from/to $SCRATCH
# [ -d $TMP_IN ] && mkdir -p $TMP_IN/fmriprep/$1/ses-${SESSION}/anat/ $TMP_IN/freesurfer
# [ -f $DATA_DIR/freesurfer/$1/stats/aseg.stats ] && cp -rvf $DATA_DIR/freesurfer/$1 $TMP_IN/freesurfer
# if [ -d $DATA_DIR/fmriprep/$1 ]; then
#     ANAT_TO_MNI_WARP=$DATA_DIR/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_from-${ORIG_SPACE}_to-MNI152NLin2009cAsym_mode-image_xfm.h5
#     ANAT=$DATA_DIR/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-preproc_${ORIG_SPACE}.nii.gz
#     MNI_TO_ANAT_WARP=$DATA_DIR/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_from-MNI152NLin2009cAsym_to-${ORIG_SPACE}_mode-image_xfm.h5
#     cp -v $ANAT $TMP_IN/fmriprep/$1/ses-${SESSION}/anat/
#     cp -v $ANAT_TO_MNI_WARP $TMP_IN/fmriprep/$1/ses-${SESSION}/anat/
#     cp -v $MNI_TO_ANAT_WARP $TMP_IN/fmriprep/$1/ses-${SESSION}/anat/
# fi

######################
# Pipeline execution #
######################

if [ $ANALYSIS_LEVEL = "subject" ]; then
    
    ###################################################################################################################
    #                                           Part A - PVS segementation                                            #
    ###################################################################################################################

    # Set up paths
    ##############
   
    PVS_DIR=$DATA_DIR/$PIPELINE/$1/ses-${SESSION}/anat/pvs 
    [ ! -d $PVS_DIR ] && mkdir -p $PVS_DIR
    
    # 1. Segmentation
    ###################################################################################################################

    # Define input
    ##############

    CONFIG_FILE=$CODE_DIR/pipelines/$PIPELINE/pvs_config.m

    # Define command
    ################

    CMD_SEGMENTATION="$apptainer_pvsseg ConfigScript $CONFIG_FILE SubjectID $1 SessionID $SESSION"

    # Execute command
    #################
    
    eval $CMD_SEGMENTATION

    # 2. Postprocessing
    ###################################################################################################################

    # Define inputs
    ###############

    MANUAL_MASK=$ENV_DIR/standard/pvsseg_manual_mask_aqueduct_posterior_ventricles.nii.gz
    MASK1=$PVS_DIR/${1}_ses-${SESSION}_PVS_LeftBG_NAWM.nii.gz
    MASK2=$PVS_DIR/${1}_ses-${SESSION}_PVS_LeftCSO_NAWM.nii.gz
    MASK3=$PVS_DIR/${1}_ses-${SESSION}_PVS_Midbrain_NAWM.nii.gz
    MASK4=$PVS_DIR/${1}_ses-${SESSION}_PVS_RightBG_NAWM.nii.gz
    MASK5=$PVS_DIR/${1}_ses-${SESSION}_PVS_RightCSO_NAWM.nii.gz
    
    MNI_TEMPLATE=$ENV_DIR/standard/tpl-MNI152NLin2009cAsym_res-01_${ORIG_SPACE}.nii.gz
    ANAT_TO_MNI_WARP=$DATA_DIR/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_from-${ORIG_SPACE}_to-MNI152NLin2009cAsym_mode-image_xfm.h5
    ANAT=$DATA_DIR/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-preproc_${ORIG_SPACE}.nii.gz
    MNI_TO_ANAT_WARP=$DATA_DIR/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_from-MNI152NLin2009cAsym_to-${ORIG_SPACE}_mode-image_xfm.h5

    # Define outputs
    ################

    MASK1_THRESH=$PVS_DIR/${1}_ses-${SESSION}_space-${ORIG_SPACE}_label-leftbg_desc-pvs_mask.nii.gz
    MASK2_THRESH=$PVS_DIR/${1}_ses-${SESSION}_space-${ORIG_SPACE}_label-leftcso_desc-pvs_mask.nii.gz
    MASK3_THRESH=$PVS_DIR/${1}_ses-${SESSION}_space-${ORIG_SPACE}_label-midbrain_desc-pvs_mask.nii.gz
    MASK4_THRESH=$PVS_DIR/${1}_ses-${SESSION}_space-${ORIG_SPACE}_label-rightbg_desc-pvs_mask.nii.gz
    MASK5_THRESH=$PVS_DIR/${1}_ses-${SESSION}_space-${ORIG_SPACE}_label-rightcso_desc-pvs_mask.nii.gz
    SEGMENTATION_PVS_CSO=$PVS_DIR/${1}_ses-${SESSION}_space-${ORIG_SPACE}_label-cso_desc-pvs_mask.nii.gz
    SEGMENTATION_PVS_Midbrain=$PVS_DIR/${1}_ses-${SESSION}_space-${ORIG_SPACE}_label-midbrain_desc-pvs_mask.nii.gz
    SEGMENTATION_PVS_BG=$PVS_DIR/${1}_ses-${SESSION}_space-${ORIG_SPACE}_label-bg_desc-pvs_mask.nii.gz
    SEGMENTATION_PVS=$PVS_DIR/${1}_ses-${SESSION}_space-${ORIG_SPACE}_desc-pvs_mask.nii.gz
    SEGMENTATION_PVS_MNI=$PVS_DIR/${1}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-pvs_mask.nii.gz
    MANUAL_MASK_INDIVIDUAL=$PVS_DIR/${1}_ses-${SESSION}_space-${ORIG_SPACE}_desc-aqueductposteriorventricles_desc-manual_mask.nii.gz

    PVS_vol=$PVS_DIR/${1}_ses-${SESSION}_pvsvolume.csv
    PVS_count=$PVS_DIR/${1}_ses-${SESSION}_pvscount.csv
    PVS_vol_midbrain=$PVS_DIR/${1}_ses-${SESSION}_desc-midbrain_pvsvolume.csv
    PVS_count_midbrain=$PVS_DIR/${1}_ses-${SESSION}_desc-midbrain_pvscount.csv
    PVS_vol_cso=$PVS_DIR/${1}_ses-${SESSION}_desc-cso_pvsvolume.csv
    PVS_count_cso=$PVS_DIR/${1}_ses-${SESSION}_desc-cso_pvscount.csv
    PVS_vol_bg=$PVS_DIR/${1}_ses-${SESSION}_desc-bg_pvsvolume.csv
    PVS_count_bg=$PVS_DIR/${1}_ses-${SESSION}_desc-bg_pvscount.csv
    threshold=$PVS_DIR/${1}_ses-${SESSION}_thresh.csv

    # Define commands
    #################

    CMD_REGISTER_MANUAL_MASK="antsApplyTransforms -d 3 -i $MANUAL_MASK -r $ANAT -t $MNI_TO_ANAT_WARP -n NearestNeighbor -o $MANUAL_MASK_INDIVIDUAL"
    $apptainer_fsl /bin/bash -c "$(echo fslstats $MASK1 -r) > $threshold"
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
    CMD_SEGMENTATION_TO_MNI="antsApplyTransforms -d 3 -i $SEGMENTATION_PVS -r $MNI_TEMPLATE -t $ANAT_TO_MNI_WARP -n NearestNeighbor -o $SEGMENTATION_PVS_MNI"

    # Execute commands
    ##################

    $apptainer_ants /bin/bash -c "$CMD_REGISTER_MANUAL_MASK"
    $apptainer_fsl /bin/bash -c "$CMD_THRESH_MASK_1; $CMD_THRESH_MASK_2; $CMD_THRESH_MASK_3; $CMD_THRESH_MASK_4; $CMD_THRESH_MASK_5; $CMD_ADD_ALL_MASKS; $CMD_EXCLUDE_MANUALMASK; $CMD_EXCLUDE_MANUAL_MIDBRAIN; $CMD_EXCLUDE_MANUAL_CSO; $CMD_EXCLUDE_MANUAL_BG"
    #rm $threshold
    $apptainer_ants /bin/bash -c "$CMD_SEGMENTATION_TO_MNI"

    $apptainer_fsl /bin/bash -c "$(echo fslstats $SEGMENTATION_PVS -V) > $PVS_vol"
    [ ! -f $SEGMENTATION_PVS ] && echo "na na" > $PVS_vol
    $apptainer_fsl /bin/bash -c "$(echo fslstats $SEGMENTATION_PVS_Midbrain -V) > $PVS_vol_midbrain"
    [ ! -f $SEGMENTATION_PVS_Midbrain ] && echo "na na" > $PVS_vol_midbrain
    $apptainer_fsl /bin/bash -c "$(echo fslstats $SEGMENTATION_PVS_CSO -V) > $PVS_vol_cso"
    [ ! -f $SEGMENTATION_PVS_CSO ] && echo "na na" > $PVS_vol_cso
    $apptainer_fsl /bin/bash -c "$(echo fslstats $SEGMENTATION_PVS_BG -V) > $PVS_vol_bg"
    [ ! -f $SEGMENTATION_PVS_BG ] && echo "na na" > $PVS_vol_bg

    $apptainer_fsl fsl-cluster --in=$SEGMENTATION_PVS --thresh=1 > $PVS_count
    echo $(cat $PVS_count | head -2 | tail -1 | awk '{print $1}') > $PVS_count
    [ ! -f $SEGMENTATION_PVS ] && echo "na na" > $PVS_count
    [ $(cat $PVS_count) == "Cluster" ] && echo "0" > $PVS_count

    $apptainer_fsl fsl-cluster --in=$SEGMENTATION_PVS_Midbrain --thresh=1 > $PVS_count_midbrain
    echo $(cat $PVS_count_midbrain | head -2 | tail -1 | awk '{print $1}') > $PVS_count_midbrain
    [ ! -f $SEGMENTATION_PVS_Midbrain ] && echo "na na" > $PVS_count_midbrain
    [ $(cat $PVS_count_midbrain) == "Cluster" ] && echo "0" > $PVS_count_midbrain

    $apptainer_fsl fsl-cluster --in=$SEGMENTATION_PVS_CSO --thresh=1 > $PVS_count_cso
    echo $(cat $PVS_count_cso | head -2 | tail -1 | awk '{print $1}') > $PVS_count_cso
    [ ! -f $SEGMENTATION_PVS_CSO ] && echo "na na" > $PVS_count_cso
    [ $(cat $PVS_count_cso) == "Cluster" ] && echo "0" > $PVS_count_cso

    $apptainer_fsl fsl-cluster --in=$SEGMENTATION_PVS_BG --thresh=1 > $PVS_count_bg
    echo $(cat $PVS_count_bg | head -2 | tail -1 | awk '{print $1}') > $PVS_count_bg
    [ ! -f $SEGMENTATION_PVS_BG ] && echo "na na" > $PVS_count_bg
    [ $(cat $PVS_count_bg) == "Cluster" ] && echo "0" > $PVS_count_bg

elif [ $ANALYSIS_LEVEL = "group" ]; then

    ###############################
    # Part B - summary statistics #
    ###############################

    # Set up output directory
    #########################
    
    PVS_DIR=$DATA_DIR/$PIPELINE/$1/ses-${SESSION}/anat/pvs 
    DERIVATIVE_DIR=$DATA_DIR/$PIPELINE/derivatives/ses-${SESSION}/anat
    [ ! -d $DERIVATIVE_DIR ] && mkdir -p $DERIVATIVE_DIR

    # Set up output file
    #####################

    echo "sub_id pvs_count pvs_volume bg_pvs_count bg_pvs_volume cso_pvs_count cso_pvs_volume midbrain_pvs_count midbrain_pvs_volume" > $DERIVATIVE_DIR/pvs_ses-${SESSION}_summary.csv

    for sub in $sublist; do  

        # Set subject-specific output directories
        PVS_DIR=$DATA_DIR/$PIPELINE/$sub/ses-${SESSION}/anat/pvs

        ###################################################################################################################
        # Pipeline execution
        ###################################################################################################################

        if [ -f $PVS_DIR/${sub}_ses-${SESSION}_pvscount.csv ]; then 

            echo $sub | tr '\n' ' ' >> $DERIVATIVE_DIR/pvs_ses-${SESSION}_summary.csv
            cat $PVS_DIR/${sub}_ses-${SESSION}_pvscount.csv | awk '{print $1}' | tr '\n' ' ' >> $DERIVATIVE_DIR/pvs_ses-${SESSION}_summary.csv
            cat $PVS_DIR/${sub}_ses-${SESSION}_pvsvolume.csv | awk '{print $2}' | tr '\n' ' ' >> $DERIVATIVE_DIR/pvs_ses-${SESSION}_summary.csv 
            cat $PVS_DIR/${sub}_ses-${SESSION}_desc-bg_pvscount.csv | awk '{print $1}' | tr '\n' ' ' >> $DERIVATIVE_DIR/pvs_ses-${SESSION}_summary.csv 
            cat $PVS_DIR/${sub}_ses-${SESSION}_desc-bg_pvsvolume.csv | awk '{print $2}' | tr '\n' ' ' >> $DERIVATIVE_DIR/pvs_ses-${SESSION}_summary.csv 
            cat $PVS_DIR/${sub}_ses-${SESSION}_desc-cso_pvscount.csv | awk '{print $1}' | tr '\n' ' ' >> $DERIVATIVE_DIR/pvs_ses-${SESSION}_summary.csv 
            cat $PVS_DIR/${sub}_ses-${SESSION}_desc-cso_pvsvolume.csv | awk '{print $2}' | tr '\n' ' ' >> $DERIVATIVE_DIR/pvs_ses-${SESSION}_summary.csv 
            cat $PVS_DIR/${sub}_ses-${SESSION}_desc-midbrain_pvscount.csv | awk '{print $1}' | tr '\n' ' ' >> $DERIVATIVE_DIR/pvs_ses-${SESSION}_summary.csv 
            cat $PVS_DIR/${sub}_ses-${SESSION}_desc-midbrain_pvsvolume.csv | awk '{print $2}' >> $DERIVATIVE_DIR/pvs_ses-${SESSION}_summary.csv 

        fi
        
    done
fi