#!/bin/bash

CMD="
   singularity run --cleanenv --userns -B $PROJ_DIR -B /work/fatx405/tmp/:/tmp \
   $ENV_DIR/fmriprep-21.0.0rc0 \
   data/raw_bids data participant \
   -w /tmp \
   --participant-label $1 \
   --output-spaces $OUTPUT_SPACES \
   --nthreads $SLURM_CPUS_PER_TASK \
   --omp-nthreads $OMP_NTHREADS \
   --mem-mb $MEM_MB \
   --bids-database-dir $CODE_DIR/bids_database \
   --stop-on-first-crash \
   --ignore t2w \
   --fs-subjects-dir data/freesurfer \
   --use-aroma \
   --random-seed 12345 \
   --use-syn-sdc \
   --notrack \
   --skip_bids_validation \
   --fs-license-file envs/freesurfer_license.txt"
$CMD

# --cifti-output 91k \