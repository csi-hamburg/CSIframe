#!/usr/bin/env bash

###################################################################################################################
# Preprocessing of FLAIR and T1 and creation of input files for WMH segmentation 
#                                                                                                                 
# Pipeline specific dependencies:                                                                                 
#   [pipelines which need to be run first]                                                                        
#       - wmh_01_prep in wmh
#       - wmh_02_segment in wmh
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

# Define subject specific temporary directory on $SCRATCH_DIR
export TMP_DIR=$SCRATCH_DIR/$1/tmp/;   [ ! -d $TMP_DIR ] && mkdir -p $TMP_DIR
TMP_IN=$TMP_DIR/input;                 [ ! -d $TMP_IN ] && mkdir -p $TMP_IN
TMP_OUT=$TMP_DIR/output;               [ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT

###################################################################################################################

# Pipeline-specific environment
##################################

# Singularity container version and command
container_fsl=fsl-6.0.3
singularity_fsl="singularity run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_fsl" 

# Set output directories
OUT_DIR=$DATA_DIR/$PIPELINE/$1/ses-${SESSION}/anat/
[ ! -d $OUT_DIR ] && mkdir -p $OUT_DIR
ALGORITHM=${ALGORITHM1}X${ALGORITHM2}
ALGORITHM_OUT_DIR=$OUT_DIR/$ALGORITHM/
[ ! -d $ALGORITHM_OUT_DIR ] && mkdir -p $ALGORITHM_OUT_DIR


# To make I/O more efficient read/write outputs from/to $SCRATCH
[ -d $TMP_IN ] && cp -rf $BIDS_DIR/$1 $BIDS_DIR/dataset_description.json $TMP_IN 
[ -d $TMP_OUT ] && mkdir -p $TMP_OUT/wmh $TMP_OUT/wmh

# $MRTRIX_TMPFILE_DIR should be big and writable
export MRTRIX_TMPFILE_DIR=/tmp

# Pipeline execution
##################################

# Define inputs
SEGMENTATION1=$OUT_DIR/$ALGORITHM1/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM1}_mask.nii.gz
SEGMENTATION2=$OUT_DIR/$ALGORITHM2/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM2}_mask.nii.gz

# Define outputs
SEGMENTATION_COMBI=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz

# Define commands
CMD_COMBINE_SEGS="fslmaths $SEGMENTATION1 -add $SEGMENTATION2 -bin $SEGMENTATION_COMBI"

# Execute
$singularity_fsl /bin/bash -c "$CMD_COMBINE_SEGS"
