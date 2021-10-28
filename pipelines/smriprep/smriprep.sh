#!/bin/bash

# Run pipeline
# FIXME: --output-spaces
CMD="
   singularity run --cleanenv --userns -B $PROJ_DIR -B $(readlink -f $ENV_DIR) -B $TMP_DIR/:/tmp \
   $ENV_DIR/smriprep-0.8.0rc2 \
    data/raw_bids data participant \
    -w /tmp \
    --participant-label $1 \
    --output-spaces $OUTPUT_SPACES \
    --nthreads $SLURM_CPUS_PER_TASK \
    --omp-nthreads $OMP_NTHREADS \
    --mem-gb $MEM_GB \
    --ignore t2w \
    --bids-database-dir data/raw_bids/code/pybids_db \
    --fs-subjects-dir data/freesurfer \
    --stop-on-first-crash \
    --notrack \
    --fs-license-file envs/freesurfer_license.txt"
$CMD