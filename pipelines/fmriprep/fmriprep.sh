#!/usr/bin/env bash

###################################################################################################################
# fMRI preprocessing (https://fmriprep.org/en/stable/)                                                            #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - none                                                                                                    #
#   [container]                                                                                                   #
#       - fmriprep-20.2.6.sif                                                                                     #
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
container_fmriprep=fmriprep-20.2.6
singularity_fmriprep="singularity run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_fmriprep" 

# To make I/O more efficient read/write outputs from/to scratch #
[ -d $TMP_IN ] && cp -rf $BIDS_DIR/$1 $BIDS_DIR/dataset_description.json $TMP_IN 
[ -d $TMP_OUT ] && mkdir -p $TMP_OUT/freesurfer
[ ! -f $DATA_DIR/freesurfer/$1/stats/aseg.stats ] && rm -rf $DATA_DIR/freesurfer/$1 || cp -rf $DATA_DIR/freesurfer/$1 $TMP_OUT/freesurfer

# Pipeline execution
##################################

# Define command
CMD="
   $singularity_fmriprep \
   /tmp_in /tmp_out participant \
   -w /tmp \
   --participant-label $1 \
   --output-spaces $OUTPUT_SPACES \
   --nthreads $SLURM_CPUS_PER_TASK \
   --omp-nthreads $OMP_NTHREADS \
   --mem-mb $MEM_MB \
   --stop-on-first-crash \
   --ignore t2w \
   --fs-subjects-dir /tmp_out/freesurfer \
   --use-aroma \
   --cifti-output 91k \
   --random-seed 12345 \
   --use-syn-sdc \
   --force-syn \
   --notrack \
   --skip_bids_validation \
   --fs-license-file envs/freesurfer_license.txt"
[ ! -z $MODIFIER ] && CMD="${CMD} ${MODIFIER}"

# Execute command
eval $CMD

# Copy outputs to $DATA_DIR
cp -ruvf $TMP_OUT/freesurfer $DATA_DIR
cp -ruvf $TMP_OUT/fmriprep $DATA_DIR