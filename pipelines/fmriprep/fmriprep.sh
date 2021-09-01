#!/bin/bash

CMD="
   singularity run --cleanenv --userns -B $PROJ_DIR -B $TMP_DIR/:/tmp \
   $ENV_DIR/fmriprep-20.2.3 \
   data/raw_bids data participant \
   -w /tmp \
   --participant-label $1 \
   --output-spaces fsnative fsaverage MNI152NLin6Asym \
   --nthreads $SLURM_CPUS_PER_TASK \
   --omp-nthreads $OMP_NTHREADS \
   --mem-mb $MEM_MB \
   --stop-on-first-crash \
   --ignore t2w \
   --skip-bids-validation \
   --fs-subjects-dir data/freesurfer \
   --use-aroma \
   --random-seed 12345 \
   --use-syn-sdc \
   --fs-license-file envs/freesurfer_license.txt"
$CMD