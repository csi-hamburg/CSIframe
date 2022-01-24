#!/usr/bin/env bash

###################################################################################################################
# Diffusion prepocessing and structural connectome reconstruction (https://qsiprep.readthedocs.io/en/latest/)     #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - none                                                                                                    #
#   [container]                                                                                                   #
#       - qsiprep-0.14.2.sif                                                                                      #
###################################################################################################################

# Get verbose outputs
set -x

# Define subject specific temporary directory on $SCRATCH_DIR
export TMP_DIR=$SCRATCH_DIR/$1/tmp/;   [ ! -d $TMP_DIR ] && mkdir -p $TMP_DIR
TMP_IN=$TMP_DIR/input;                 [ ! -d $TMP_IN ] && mkdir -p $TMP_IN
TMP_OUT=$TMP_DIR/output;               [ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT

###################################################################################################################

# Pipeline-specific environment
##################################

# Singularity container version and command
container_qsiprep=qsiprep-0.14.2
singularity_qsiprep="singularity run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_qsiprep" 

# To make I/O more efficient read/write outputs from/to $SCRATCH
[ -d $TMP_IN ] && cp -rf $BIDS_DIR/$1 $BIDS_DIR/dataset_description.json $TMP_IN 
[ -d $TMP_OUT ] && mkdir -p $TMP_OUT/qsiprep $TMP_OUT/qsirecon

# $MRTRIX_TMPFILE_DIR should be big and writable
export MRTRIX_TMPFILE_DIR=/tmp

# Pipeline execution
##################################

# Define command
CMD="
   $singularity_qsiprep \
   /tmp_in /tmp_out participant \
   -w /tmp \
   --participant-label $1 \
   --skip-bids-validation \
   --use-syn-sdc \
   --force-syn \
   --output-space T1w \
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

# Execute command
eval $CMD

# Copy outputs to $DATA_DIR
cp -ruvf $TMP_OUT/qsiprep $DATA_DIR
cp -ruvf $TMP_OUT/qsirecon $DATA_DIR
