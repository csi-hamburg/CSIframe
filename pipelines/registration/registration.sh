#!/usr/bin/env bash

###################################################################################################################
# Registration pipeline that allows for flexible registration between volumes                                     #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - nothing mandatory, but the input files should be computed                                               #
#   [container]                                                                                                   #
#       - mrtrix-3.0.2.sif                                                                                      #
###################################################################################################################

# Get verbose outputs
set -x

# Define subject specific temporary directory on $SCRATCH_DIR
export TMP_DIR=$SCRATCH_DIR/$1/tmp/;   [ ! -d $TMP_DIR ] && mkdir -p $TMP_DIR
TMP_IN=$TMP_DIR/input;                 [ ! -d $TMP_IN ] && mkdir -p $TMP_IN/moving $TMP_IN/target $TMP_IN/transform
TMP_OUT=$TMP_DIR/output;               [ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT

###################################################################################################################

# Pipeline-specific environment
##################################

# Singularity container version and command
container_mrtrix=mrtrix-3.0.2
singularity_qsiprep="singularity run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_mrtrix"

MOVING_DIR=$DATA_DIR/registration/$TASK/moving
TARGET_DIR=$DATA_DIR/registration/$TASK/target

# To make I/O more efficient read/write outputs from/to $SCRATCH
[ -d $TMP_IN ] && cp -rf $MOVING_DIR/${1}* $TMP_IN/moving 
[ -d $TMP_IN ] && cp -rf $TARGET_DIR/${1}* $TMP_IN/target
if [ $METHOD == "ants_apply_transform" ]; then
    cp -rf $MOVING_DIR/${1}* $TMP_IN/moving  
fi

# Pipeline execution
##################################

# Define command

MOVING=$TMP_IN/moving/*
TARGET=$TMP_IN/target/*

if [ $REGISTRATION_METHOD == ants_rigid ]; then
elif [ $REGISTRATION_METHOD == ants_affine ]; then
elif [ $REGISTRATION_METHOD == ants_syn ]; then
    CMD="
        $singularity_mrtrix antsRegistrationSyn.sh \
        -d 3 \
        -f $TMP_IN/target/${1}* \
        -m $TMP_IN/moving/${1}* \
        -o $TMP_OUT/${1} \
        -t s \
        -n $OMP_NTHREADS \

    "
elif [[ $REGISTRATION_METHOD == ants_apply_transform ]]; then
else
    echo "ERROR: registration method '${REGISTRATION_METHOD}' not available"
    exit 1
fi

# Execute command
eval $CMD

# Copy outputs to $DATA_DIR
cp -ruvf $TMP_OUT/ $DATA_DIR/registration/$TASK/$1