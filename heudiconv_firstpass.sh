#!/bin/bash

# heudiconv first pass

# Import cluster modules
source /sw/batch/init.sh
module switch singularity singularity/3.5.2-overlayfix

# export project env variables
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source $SCRIPT_DIR/.projectrc
export TMPDIR=$WORK/tmp

# Define singularity command and srun flags
CMD="singularity run --cleanenv --userns \
    -B $BIDS_DIR:/bids -B $DCM_DIR:/dcm \
    -B $TMPDIR:/tmp $ENV_DIR/heudiconv-0.9.0.sif \
    -d /dcm/{subject}/ses-1/* \
    -s $(ls ${DCM_DIR} | sort -R | tail -3) \
    -f convertall \
    -c none \
    -o /bids"

#| execute command
$CMD
