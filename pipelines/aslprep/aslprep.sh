#!/usr/bin/env bash

######################################################################
# ASL analysis based on https://aslprep.readthedocs.io/en/latest/    #
#                                                                    #
# Pipeline specific dependencies:                                    #
#   [pipelines which need to be run first]                           #
#       - bidsify                                                    #
#   [container]                                                      #
#       - aslprep-0.2.7.sif                                          #
######################################################################

# Get verbose outputs
set -x

# Define subject specific temporary directory on $SCRATCH_DIR
export TMP_DIR=$SCRATCH_DIR/$1/tmp/;   [ ! -d $TMP_DIR ] && mkdir -p $TMP_DIR
TMP_IN=$TMP_DIR/input;                 [ ! -d $TMP_IN ] && mkdir -p $TMP_IN
TMP_OUT=$TMP_DIR/output;               [ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT

###################################################################################################################

# Define environment
####################
ENV_DIR=$PROJ_DIR/envs
container_aslprep=aslprep-0.2.7
singularity_aslprep="singularity run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_aslprep" 

# To make I/O more efficient read/write outputs from/to $SCRATCH
[ -d $TMP_IN ] && cp -rvf $BIDS_DIR/$1 $BIDS_DIR/dataset_description.json $TMP_IN 
[ -d $TMP_OUT ] && mkdir -p $TMP_OUT/aslprep

###########
# ASLprep #
###########

# Define command
################

CMD="
   $singularity_aslprep \
   /tmp_in /tmp_out participant \
   --participant-label $1 \
   --work-dir /tmp \
   --fs-license-file envs/freesurfer_license.txt \
   --skip-bids-validation \
   --nthreads $SLURM_CPUS_PER_TASK \
   --omp-nthreads $OMP_NTHREADS \
   --mem_mb $MEM_MB \
   --ignore fieldmaps slicetiming sbref \
   --output-spaces asl T1w MNI152NLin2009cAsym \
   --asl2t1w-init register \
   --asl2t1w-dof 6 \
   --force-bbr
   --use-syn-sdc
   --force-syn
   --m0_scale 10 \
   --scorescrub \
   --basil \
   --skull-strip-template OASIS30ANTs \
   --skull-strip-fixed-seed \
   --random-seed 42 \
   --skull-strip-t1w force \
   --notrack \
   --verbose"

# Execute command
#################

eval $CMD

# Copy outputs to $DATA_DIR
###########################

cp -ruvf $TMP_OUT/aslprep $DATA_DIR/
