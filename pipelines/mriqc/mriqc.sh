#!/bin/bash

if [ $MRIQC_LEVEL == "participant" ]; then
    CMD="
    singularity run --cleanenv --userns -B $PROJ_DIR -B $TMP_DIR/:/tmp \
    $ENV_DIR/mriqc-0.16.1 \
        data/raw_bids data/mriqc participant \
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
    singularity run --cleanenv --userns -B $PROJ_DIR -B $TMP_DIR/:/tmp \
    $ENV_DIR/mriqc-0.16.1 \
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