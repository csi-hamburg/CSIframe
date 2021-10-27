#!/bin/bash

# Set specific environment for pipeline
export MRTRIX_TMPFILE_DIR=$TMP_DIR

CMD="
   singularity run --cleanenv --userns -B $PROJ_DIR -B $TMP_DIR/:/tmp \
   $ENV_DIR/qsiprep-0.14.2 \
   data/raw_bids data participant \
   -w /tmp \
   --participant-label $1 \
   --skip-bids-validation \
   --bids-database-dir data/raw_bids/code/pybids_db \
   --use-syn-sdc \
   --force-syn \
   --output-space T1w \
   --nthreads $SLURM_CPUS_PER_TASK \
   --omp-nthreads $OMP_NTHREADS \
   --mem_mb $MEM_MB \
   --denoise-method dwidenoise \
   --unringing-method mrdegibbs \
   --skull-strip-template OASIS \
   --stop-on-first-crash \
   --output-resolution $OUTPUT_RESOLUTION \
   --fs-license-file envs/freesurfer_license.txt"
[ ! -z $RECON ] && CMD="${CMD} --recon_input data/qsiprep/$1 --recon_spec $RECON"
[ ! -z $MODIFIER ] && CMD="${CMD} $MODIFIED"
$CMD


