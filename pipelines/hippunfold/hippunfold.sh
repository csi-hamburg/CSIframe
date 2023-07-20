#!/usr/bin/env bash

###################################################################################################################
# Hippocampus volumetry and surface reconstruction (https://hippunfold.readthedocs.io/en/latest/index.html)       #
#                                                                                                                 #
# Internal documentation:                                                                                         #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - qsiprep                                                                                                 #
#   [container]                                                                                                   #
#       - hippunfold-1.2.0                                                                                        #
#                                                                                                                 #
# Author: Marvin Petersen (m-petersen)                                                                            #
###################################################################################################################

# Get verbose outputs
set -x

# Define subject specific temporary directory on $SCRATCH_DIR
export TMP_DIR=$SCRATCH_DIR/$1/tmp/;   [ ! -d $TMP_DIR ] && mkdir -p $TMP_DIR
TMP_IN=$TMP_DIR/input;                 [ ! -d $TMP_IN ] && mkdir -p $TMP_IN
TMP_OUT=$TMP_DIR/output;               [ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT

###################################################################################################################

# Pipeline-specific environment
##################################

# Singularity container version and command
container_hippunfold=hippunfold-1.2.0
singularity_hippunfold="singularity run --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_hippunfold" 

# To make I/O more efficient read/write outputs from/to $SCRATCH
[ -d $TMP_IN ] && cp -rf $BIDS_DIR/dataset_description.json $TMP_IN
[ ! -d $TMP_IN/$1/anat ] && mkdir -p $TMP_IN/$1/anat || rm -rf $TMP_IN/$1/anat/*

[ $INPUT_T1_HIPPUNFOLD == "qsiprep" ] && cp -rf $PROJ_DIR/data/qsiprep/$1/anat/${1}_desc-preproc_T1w.nii.gz $TMP_IN/$1/anat/${1}_ses-${SESSION}_T1w.nii.gz
[ $INPUT_T1_HIPPUNFOLD == "fmriprep" ] && cp -rf $PROJ_DIR/data/fmriprep/$1/ses-${SESSION}/anat/${1}_desc-preproc_T1w.nii.gz $TMP_IN/$1/anat/${1}_ses-${SESSION}_T1w.nii.gz
[ $INPUT_T1_HIPPUNFOLD == "raw_bids" ] && cp -rf $PROJ_DIR/data/raw_bids/$1/ses-${SESSION}/anat/*T1w.nii.gz $TMP_IN/$1/anat/${1}_ses-${SESSION}_T1w.nii.gz

[ -d $TMP_OUT ] && mkdir -p $TMP_OUT/hippunfold

# Pipeline execution
##################################

export SINGULARITY_BINDPATH=/data:/data
export SINGULARITYENV_XDG_CACHE_HOME=/tmp
export SINGULARITYENV_HIPPUNFOLD_CACHE_DIR=/tmp

# Define command
CMD="
   $singularity_hippunfold \
   /tmp_in data participant \
   --participant-label ${1#sub-*} \
   --modality T1w \
   --atlas bigbrain \
   --force-output \
   --cores $SLURM_CPUS_PER_TASK \
   --np \
   --debug-dag \
   --keep-work
"

[ ! -z $MODIFIER ] && CMD="${CMD} $MODIFIER"

# Execute command
eval $CMD

# Copy outputs to $DATA_DIR
cp -ruvf $TMP_OUT/hippunfold $DATA_DIR