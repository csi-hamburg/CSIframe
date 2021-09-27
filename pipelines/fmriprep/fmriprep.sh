#!/bin/bash

# To make I/O more efficient write outputs to scratch
BIDS_DIR_CACHED=$(echo $BIDS_DIR | sed 's/^\/work/\/work_cached/g')
TMP_OUT=$TMP_DIR/output
[ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT

CMD="
   singularity run --cleanenv --userns -B $PROJ_DIR -B $TMP_DIR:/tmp -B $TMP_OUT:/tmp_out -B $BIDS_DIR_CACHED:/bids_cached\
   $ENV_DIR/fmriprep-unstable21.0.0rc1 \
   /bids_cached /tmp_out participant \
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

cp -ruvf $TMP_OUT/* $DATA_DIR