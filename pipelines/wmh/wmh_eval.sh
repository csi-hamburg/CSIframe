#!/usr/bin/env bash

###################################################################################################################
# Preprocessing of FLAIR and T1 and creation of input files for WMH segmentation 
#                                                                                                                 
# Pipeline specific dependencies:                                                                                 
#   [pipelines which need to be run first]                                                                        
#       - freesurfer
#       - fmriprep 
#       - wmh_01_prep
#       - wmh_02_segment                                                                                                   
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
    -B $PROJ_DIR/../ \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_freesurfer" 

# $MRTRIX_TMPFILE_DIR should be big and writable
export MRTRIX_TMPFILE_DIR=/tmp


###################################################################################################################
# Pipeline execution
################################## 
MAN_SEGMENTATION_DIR=$PROJ_DIR/../CSI_WMH_MASKS_HCHS_pseud/HCHS/

OUT_DIR_der=$DATA_DIR/$PIPELINE/derivatives/$ALGORITHM
[ ! -d $OUT_DIR_der ] && mkdir -p $OUT_DIR_der

dice_indexfile=$OUT_DIR_der/diceindex_${ALGORITHM}.csv
jaccard_indexfile=$OUT_DIR_der/jaccardindex_${ALGORITHM}.csv

[ -f $dice_indexfile ] && rm $dice_indexfile
[ -f $jaccard_indexfile ] && rm $jaccard_indexfile

for sub in $(ls $DATA_DIR/$PIPELINE/sub-* -d | xargs -n 1 basename); do 

    # Set output directories
    ALGORITHM_OUT_DIR=$DATA_DIR/$PIPELINE/$sub/ses-${SESSION}/anat/$ALGORITHM
    OUT_DIR=$ALGORITHM_OUT_DIR/eval
    [ ! -d $OUT_DIR ] && mkdir -p $OUT_DIR
    
    # Define inputs
    SEGMENTATION=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
    SEGMENTATION_MAN=$MAN_SEGMENTATION_DIR/$sub/anat/${sub}_DC_FLAIR_label3.nii.gz
            
    # Define outputs
    JSON_FILE_DICE=$OUT_DIR/${sub}_ses-${SESSION}_desc-diceindex_desc-${ALGORITHM}.txt
    JSON_FILE_JACCARD=$OUT_DIR/${sub}_ses-${SESSION}_desc-jaccardindex_desc-${ALGORITHM}.txt
    

    # Define commands
    CMD_CALCULATE_DICE="mri_seg_overlap -x $SEGMENTATION $SEGMENTATION_MAN -o $JSON_FILE_DICE"
    CMD_CALCULATE_JACCARD="mri_seg_overlap -x -m jaccard $SEGMENTATION $SEGMENTATION_MAN -o $JSON_FILE_JACCARD"

    # Execute
    $singularity_freesurfer /bin/bash -c "$CMD_CALCULATE_DICE; $CMD_CALCULATE_JACCARD"
    dice_value=$(cat $JSON_FILE_DICE| grep '"mean":' | awk '{print $2}')
    jaccard_value=$(cat $JSON_FILE_JACCARD| grep '"mean":' | awk '{print $2}')
    echo "$sub,$dice_value" >> $dice_indexfile
    echo "$sub,$jaccard_value" >> $jaccard_indexfile

done