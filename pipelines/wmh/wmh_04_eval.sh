#!/usr/bin/env bash

###################################################################################################################
# This pipeline calculates dice and jaccard scores based on manual and automated WMH segmentations.               #
# WMH volumes are collected from individual subjects and stored in a common dataframe.                            #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - fmriprep                                                                                                #
#       - freesurfer (if not included in fmriprep)                                                                #
#       - qsiprep                                                                                                 #
#       - wmh_01_prep in wmh                                                                                      #
#       - wmh_02_segment in wmh                                                                                   #
#       - wmh_03_postproc in wmh                                                                                  #
#   [container]                                                                                                   #
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
###############################

# Apptainer container version and command
container_freesurfer=freesurfer-7.4.1.sif
apptainer_freesurfer="apptainer run --cleanenv --userns \
    -B $PROJ_DIR/../ \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_freesurfer" 


###################################################################################################################

# Pipeline execution
################################## 

# Set up directories
####################

MAN_SEGMENTATION_DIR=$DATA_DIR/$PIPELINE/sourcedata/manual_segmentations/

OUT_DIR_DER=$DATA_DIR/$PIPELINE/derivatives/$ALGORITHM
[ ! -d $OUT_DIR_DER ] && mkdir -p $OUT_DIR_DER

accuracy_file=$OUT_DIR_DER/${ALGORITHM}_ses-${SESSION}_accuracy.csv
echo "sub_id,dice,jaccard" > $accuracy_file

volume_file=$OUT_DIR_DER/${ALGORITHM}_ses-${SESSION}_volumes.csv
echo "sub_id,wmh_total,wmh_peri,wmh_deep" > $volume_file

###################################################################################################################
#                                       Evaluate segmentation accuracy                                            # 
###################################################################################################################

input_subject_array=($@)

for sub in $(echo ${input_subject_array[@]}); do 
    
    # Set directory
    ALGORITHM_OUT_DIR=$DATA_DIR/$PIPELINE/$sub/ses-${SESSION}/anat/$ALGORITHM
    
    [[ $(ls -A $MAN_SEGMENTATION_DIR/${sub}) ]] && SUB_GROUP=training || SUB_GROUP=testing

    if [ $SUB_GROUP == "training" ]; then   
        
        # Define inputs
        SEGMENTATION=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
        SEGMENTATION_MAN=$MAN_SEGMENTATION_DIR/$sub/anat/${sub}_DC_FLAIR_label4.nii.gz
                
        # Define outputs
        JSON_FILE_DICE=$OUT_DIR_DER/${sub}_ses-${SESSION}_desc-diceindex_desc-${ALGORITHM}.txt
        JSON_FILE_JACCARD=$OUT_DIR_DER/${sub}_ses-${SESSION}_desc-jaccardindex_desc-${ALGORITHM}.txt
        
        # Define commands
        CMD_CALCULATE_DICE="mri_seg_overlap -x $SEGMENTATION $SEGMENTATION_MAN -o $JSON_FILE_DICE"
        CMD_CALCULATE_JACCARD="mri_seg_overlap -x -m jaccard $SEGMENTATION $SEGMENTATION_MAN -o $JSON_FILE_JACCARD"

        # Execute
        $apptainer_freesurfer /bin/bash -c "$CMD_CALCULATE_DICE; $CMD_CALCULATE_JACCARD"
        dice_value=$(cat $JSON_FILE_DICE| grep '"mean":' | awk '{print $2}' | cut -d "," -f 1)
        jaccard_value=$(cat $JSON_FILE_JACCARD| grep '"mean":' | awk '{print $2}' | cut -d "," -f 1)
        echo "$sub,$dice_value,$jaccard_value" >> $accuracy_file

        # Clean up
        rm $JSON_FILE_DICE $JSON_FILE_JACCARD
    
    fi

    ###################################################################################################################
    #                                               Collect volumes                                                   #
    ###################################################################################################################

    # Define inputs
    WMH_vol=$ALGORITHM_OUT_DIR/${sub}_ses-1_${ALGORITHM}_desc-wmh_volume.csv
    WMH_peri_vol=$ALGORITHM_OUT_DIR/${sub}_ses-1_${ALGORITHM}_desc-wmhperi_volume.csv
    WMH_deep_vol=$ALGORITHM_OUT_DIR/${sub}_ses-1_${ALGORITHM}_desc-wmhdeep_volume.csv

    # Execute
    wmh_total=$(cat $WMH_vol | awk '{print $2}')
    wmh_peri=$(cat $WMH_peri_vol | awk '{print $2}')
    wmh_deep=$(cat $WMH_deep_vol | awk '{print $2}')
    echo "$sub,$wmh_total,$wmh_peri,$wmh_deep" >> $volume_file

done

