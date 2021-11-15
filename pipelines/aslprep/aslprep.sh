#!/bin/bash

# Set specific environment for pipeline
export MRTRIX_TMPFILE_DIR=$TMP_DIR

# To make I/O more efficient read/write outputs from/to scratch #
TMP_IN=$TMP_DIR/input
TMP_OUT=$TMP_DIR/output
[ ! -d $TMP_IN ] && mkdir -p $TMP_IN && cp -rf $BIDS_DIR/$1 $BIDS_DIR/dataset_description.json $TMP_IN 
[ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT/freesurfer
[ ! -f $DATA_DIR/freesurfer/$1/stats/aseg.stats ] && rm -rf $DATA_DIR/freesurfer/$1 || cp -rf $DATA_DIR/freesurfer/$1 $TMP_OUT/freesurfer

CMD="
   singularity run --cleanenv --userns -B $PROJ_DIR -B $TMP_DIR/:/tmp \
   $ENV_DIR/aslprep-0.2.7 \   # '-B' zuvor gesetzt, da Variable definiert wird?
   data/raw_bids $DATA_DIR/aslprep {participant} \
   --participant-label $1 \
   --work-dir /tmp \
   --clean-workdir \
   --skip-bids-validation \
   --use-syn-sdc \ # EXPERIMENTAL: Use fieldmap-free distortion correction; mit Vorteil behaftet? (Marvin). Ggf. --force-syn zusätzlich zu nutzen
   --output-space func T1w MNI152NLin2009cAsym \
   --nthreads $SLURM_CPUS_PER_TASK \
   --omp-nthreads $OMP_NTHREADS \
   --mem_mb $MEM_MB \
   --skull-strip-template OASIS \
   --skull-strip-fixed-seed 42
   --stop-on-first-crash \
   --notrack \
   --output-resolution $OUTPUT_RESOLUTION \
   --fs-license-file envs/freesurfer_license.txt"

#[ ! -z $RECON ] && CMD="${CMD} --recon_input data/qsiprep/$1 --recon_spec $RECON"
[# ! -z $MODIFIER ] && CMD="${CMD} $MODIFIED"
$CMD

cp -ruvf $TMP_OUT/freesurfer $DATA_DIR
cp -ruvf $TMP_OUT/sub-* $DATA_DIR/aslprep
cp -ruvf $TMP_OUT/d* $DATA_DIR/aslprep
cp -ruvf $TMP_OUT/logs $DATA_DIR/aslprep