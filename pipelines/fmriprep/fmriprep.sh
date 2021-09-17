#!/bin/bash

CMD="
   singularity run --cleanenv --userns -B $PROJ_DIR -B $TMP_DIR:/tmp \
   $ENV_DIR/fmriprep-unstable21.0.0rc1 \
   data/raw_bids data participant \
   -w /tmp \
   --participant-label $1 \
   --output-spaces $OUTPUT_SPACES \
   --nthreads $SLURM_CPUS_PER_TASK \
   --omp-nthreads $OMP_NTHREADS \
   --mem-mb $MEM_MB \
   --bids-database-dir data/raw_bids/code/pybids_db \
   --stop-on-first-crash \
   --ignore t2w \
   --fs-subjects-dir data/freesurfer \
   --use-aroma \
   --cifti-output 91k \
   --random-seed 12345 \
   --use-syn-sdc \
   --notrack \
   --skip_bids_validation \
   --fs-license-file envs/freesurfer_license.txt"
[ ! -z $MODIFIER ] && CMD="${CMD} ${MODIFIER}"
$CMD
