#!/bin/bash

# To make I/O more efficient read/write outputs from/to scratch #
TMP_IN=$TMP_DIR/input
TMP_OUT=$TMP_DIR/output
[ ! -d $TMP_IN ] && mkdir -p $TMP_IN && cp -rf $BIDS_DIR/$1 $BIDS_DIR/dataset_description.json $TMP_IN 
[ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT
[ -d $DATA_DIR/freesurfer/$1 ] && rm -rf $DATA_DIR/freesurfer/$1


CMD="
   singularity run --cleanenv --userns -B $PROJ_DIR -B $TMP_DIR:/tmp -B $TMP_IN:/tmp_in -B $TMP_OUT:/tmp_out \
   $ENV_DIR/fmriprep-21.0.0rc1 \
   /tmp_in /tmp_out participant \
   -w /tmp \
   --participant-label $1 \
   --output-spaces $OUTPUT_SPACES \
   --nthreads $SLURM_CPUS_PER_TASK \
   --omp-nthreads $OMP_NTHREADS \
   --mem-mb $MEM_MB \
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

cp -ruvf $TMP_OUT/freesurfer $DATA_DIR
cp -ruvf sub-* $DATA_DIR/fmriprep

#--bids-database-dir data/raw_bids/code/pybids_db \