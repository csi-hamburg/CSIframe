#!/bin/bash

# heudiconv first pass

# Import cluster modules
source /sw/batch/init.sh
module switch singularity singularity/3.5.2-overlayfix

# export project env variables
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
export PROJ_DIR=$(realpath $SCRIPT_DIR/../../..) # project root; should be 1 level above code
export CODE_DIR=$PROJ_DIR/code
export ENV_DIR=$PROJ_DIR/envs
export DATA_DIR=$PROJ_DIR/data
export DCM_DIR=$PROJ_DIR/data/dicoms
export BIDS_DIR=$PROJ_DIR/data/raw_bids
export TMPDIR=$WORK/tmp

# Define singularity command and srun flags
CMD="singularity run --cleanenv --userns \
    -B $SCRIPT_DIR:/out -B $DCM_DIR:/dcm \
    -B $TMPDIR:/tmp $ENV_DIR/heudiconv-0.9.0.sif \
    -d /dcm/{subject}/ses-1/* \
    -s $(ls ${DCM_DIR} | sort -R | tail -3) \
    -f convertall \
    -c none \
    -o /out"

# execute command
$CMD
