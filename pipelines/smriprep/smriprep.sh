#!/bin/bash

# Run pipeline
# FIXME: --output-spaces
CMD="
   singularity run --cleanenv --userns -B $PROJ_DIR -B $TMP_DIR/:/tmp \
   $ENV_DIR/smriprep-0.8.0rc2
    data/raw_bids data participant \
    -w $TMP_DIR \
    --participant-label $1 \
    --output-spaces fsnative fsaverage MNI152NLin6Asym T1w T2w \
    --nthreads $SLURM_CPUS_PER_TASK \
    --fs-subjects-dir data/freesurfer \
    --stop-on-first-crash \
    --fs-license-file envs/freesurfer_license.txt"
$CMD