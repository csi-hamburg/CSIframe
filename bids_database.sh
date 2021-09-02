#!/bin/bash
# Do not forget to select a proper partition if the default
# one is no fit for the job! You can do that either in the sbatch
# command line or here with the other settings.
#SBATCH --job-name=adni2bids
#SBATCH --nodes=1
#SBATCH --partition=std
#SBATCH --time=10:00:00
# Never forget that! Strange happenings ensue otherwise.
#SBATCH --export=NONE

set -x # Good Idea to stop operation on first error.

source /sw/batch/init.sh

source $WORK/set_envs/miniconda

# export project env variables
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
export PROJ_DIR=$(realpath $SCRIPT_DIR/..) # project root; should be 1 level above code
export CODE_DIR=$PROJ_DIR/code
export ENV_DIR=$PROJ_DIR/envs
export DATA_DIR=$PROJ_DIR/data
export DCM_DIR=$PROJ_DIR/data/dicoms
export BIDS_DIR=$PROJ_DIR/data/raw_bids

export BIDS_DATABASE_DIR=$CODE_DIR/bids_database
[ -d $BIDS_DATABASE_DIR ] || mkdir -p $BIDS_DATABASE_DIR
pybids layout $BIDS_DIR $BIDS_DATABASE_DIR --no-validate --reset-db
