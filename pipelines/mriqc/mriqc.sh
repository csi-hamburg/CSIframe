#!/usr/bin/env bash

###################################################################################################################
# Structural and functional quality assessment (https://mriqc.readthedocs.io/en/latest/)                          #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - none                                                                                                    #
#   [container]                                                                                                   #
#       - mriqc-24.0.2.sif                                                                                        #
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

# Apptainer container version and command
container_mriqc=mriqc-24.0.2.sif
apptainer_mriqc="apptainer run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_mriqc" 


if [ $ANALYSIS_LEVEL == "subject" ]; then

    cp -rf $BIDS_DIR/$1 $BIDS_DIR/dataset_description.json $TMP_IN 

    CMD="
    $apptainer_mriqc \
        /tmp_in data/mriqc participant \
        --work-dir /tmp \
        --participant-label $1 \
        --modalities T1w T2w bold \
        --no-sub \
        --notrack \
        --mem-gb $MEM_GB \
        --float32 \
        --nprocs $GNU_CPUS_PER_TASK \
        --omp-nthreads $OMP_NTHREADS"
    $CMD

elif [ $ANALYSIS_LEVEL == "group" ]; then

    CMD="
    $apptainer_mriqc \
        data/raw_bids data/mriqc group \
        --work-dir /tmp \
        --modalities T1w T2w bold \
        --no-sub \
        --notrack \
        --mem-gb $MEM_GB \
        --float32 \
        --nprocs $GNU_CPUS_PER_TASK \
        --omp-nthreads $OMP_NTHREADS"
    $CMD

fi