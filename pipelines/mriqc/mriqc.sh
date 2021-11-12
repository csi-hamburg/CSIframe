#!/usr/bin/env bash

###################################################################################################################
# Structural and functional quality assessment (https://mriqc.readthedocs.io/en/latest/)                          #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - none                                                                                                    #
#   [container]                                                                                                   #
#       - mriqc-0.16.1.sif                                                                                        #
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
container_mriqc=mriqc-0.16.1
singularity_mriqc="singularity run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_mriqc" 


if [ $MRIQC_LEVEL == "participant" ]; then

    TMP_IN=$TMP_DIR/input
    [ ! -d $TMP_IN ] && mkdir -p $TMP_IN && cp -rf $BIDS_DIR/$1 $BIDS_DIR/dataset_description.json $TMP_IN 

    CMD="
    $singularity_mriqc \
        /tmp_in data/mriqc participant \
        -w /tmp \
        --participant-label $1 \
        --modalities T1w T2w bold \
        --no-sub \
        --mem_gb $MEM_GB \
        --ica \
        --float32 \
        --nprocs $SLURM_CPUS_PER_TASK"
    $CMD

elif [ $MRIQC_LEVEL == "group" ]; then
    CMD="
    $singularity_mriqc \
        data/raw_bids data/mriqc group \
        -w /tmp \
        --modalities T1w T2w bold \
        --no-sub \
        --mem_gb $MEM_GB \
        --ica \
        --float32 \
        --nprocs $SLURM_CPUS_PER_TASK"
    $CMD

fi