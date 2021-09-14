#!/bin/bash

# heudiconv first pass

# Import cluster modules
source /sw/batch/init.sh
module switch singularity singularity/3.5.2-overlayfix

# export project env variables
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
export PROJ_DIR=$(realpath $SCRIPT_DIR/../../..) # project root; should be 1 level above code
export CODE_DIR=$PROJ_DIR/code
export PIPELINE_DIR=$PROJ_DIR/code/pipelines/bidsify
export ENV_DIR=$PROJ_DIR/envs
export DATA_DIR=$PROJ_DIR/data
export DCM_DIR=$PROJ_DIR/data/dicoms
export BIDS_DIR=$PROJ_DIR/data/raw_bids
export TMPDIR=$WORK/tmp

echo "Provide session"
read session
subs=($@)
# Define commands
subs=${subs-$(ls $DCM_DIR/ | xargs -n 1 basename | sort -R | tail -n 3 )}
echo "Processing:" $subs
CMD="heudiconv
    -d $DCM_DIR/{subject}/ses-{session}.tar.gz \
    -s $subs \
    -ss $session \
    -f convertall \
    -c none \
    -o $PIPELINE_DIR"

# Execute command
$CMD
