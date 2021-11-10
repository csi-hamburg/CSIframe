#!/bin/bash

# Set specific environment for pipeline
export MRTRIX_TMPFILE_DIR=$TMP_DIR

# To make I/O more efficient read/write outputs from/to scratch #
TMP_IN=$TMP_DIR/input
TMP_OUT=$TMP_DIR/output
[ ! -d $TMP_IN ] && mkdir -p $TMP_IN && cp -rf $BIDS_DIR/$1 $BIDS_DIR/dataset_description.json $TMP_IN 
[ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT/qsiprep $TMP_OUT/qsirecon

CMD="
   singularity run --cleanenv --userns -B $PROJ_DIR -B $(readlink -f $ENV_DIR) -B $TMP_DIR/:/tmp -B $TMP_IN:/tmp_in -B $TMP_OUT:/tmp_out \
   $ENV_DIR/qsiprep-0.14.2 \
   /tmp_in /tmp_out participant \
   -w /tmp \
   --participant-label $1 \
   --skip-bids-validation \
   --use-syn-sdc \
   --force-syn \
   --output-space T1w template \
   --template MNI152NLin2009cAsym \
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

cp -ruvf $TMP_OUT/qsiprep $DATA_DIR
cp -ruvf $TMP_OUT/qsirecon $DATA_DIR


#   --bids-database-dir data/raw_bids/code/pybids_db \


