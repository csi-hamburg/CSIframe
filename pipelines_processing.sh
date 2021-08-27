#!/usr/bin/bash

set -oux
source /sw/batch/init.sh

echo '###################################'
echo Started processing of $1
echo '###################################'

# Change default permissions for new files
umask u=rwx g=rwx

# Define environment
SCRIPT_DIR=${SLURM_SUBMIT_DIR-$(dirname "$0")}
export PROJ_DIR=$(realpath $SCRIPT_DIR/..) # project root; should be 1 level above code
export CODE_DIR=$PROJ_DIR/code
export PIPELINE_DIR=$PROJ_DIR/code/pipelines/$PIPELINE
export ENV_DIR=$PROJ_DIR/envs
export DATA_DIR=$PROJ_DIR/data
export DCM_DIR=$PROJ_DIR/data/dicoms
export BIDS_DIR=$PROJ_DIR/data/raw_bids

export SCRATCH_DIR=/scratch/${USER}.${SLURM_JOBID}/$1 
[ ! -d $SCRATCH_DIR ] && mkdir $SCRATCH_DIR
export SINGULARITY_CACHEDIR=$SCRATCH_DIR/singularity_cache 
export SINGULARITY_TMPDIR=$SCRATCH_DIR/singularity_tmp
export TMP_DIR=$SCRATCH_DIR/tmp/

# Define SLURM_CPUS_PER_TASK as 32 / Subject count. Make sure that SUBJS_PER_NODE is a power of two 
# 32 threads per node on hummel but we allocate only 30 threads (empirical!)
export SUBJS_PER_NODE=${SUBJS_PER_NODE-2}
if [ "$ANALYSIS_LEVEL" == "subject" ];then
    export SLURM_CPUS_PER_TASK=$(awk "BEGIN {print int(32/$SUBJS_PER_NODE); exit}")
    export MEM_MB=$(awk "BEGIN {print int(64000/$SUBJS_PER_NODE); exit}")
elif [ "$ANALYSIS_LEVEL" == "group" ];then
    export SLURM_CPUS_PER_TASK=32
    export MEM_MB=64000
fi
export OMP_NTHREADS=$(($SLURM_CPUS_PER_TASK - 1 ))
export MEM_GB=$(awk "BEGIN {print int($MEM_MB/1000); exit}")

echo hostname: $(hostname)
echo $(singularity --version)
echo TMPDIR: $TMPDIR
echo RRZ_LOCAL_TMPDIR: $RRZ_LOCAL_TMPDIR
echo SINGULARITY_CACHEDIR: $SINGULARITY_CACHEDIR
echo SINGULARITY_TMPDIR: $SINGULARITY_TMPDIR
echo DSLOCKFILE: $DSLOCKFILE
mkdir -p $DATALAD_LOCATIONS_SOCKETS && echo DATALAD_LOCATIONS_SOCKETS: $DATALAD_LOCATIONS_SOCKETS

# Create temporary clone working directory
mkdir -p $TMP_DIR 

# Tell templateflow where to read/write
export TEMPLATEFLOW_HOME=$CODE_DIR/templateflow
export SINGULARITYENV_TEMPLATEFLOW_HOME=$TEMPLATEFLOW_HOME

# All paths relative paths relate to project_dir
cd $PROJ_DIR

# Run pipeline
export PIPE_ID="$SLURM_JOBID-$PIPELINE-$1-$(date +%d%m%Y)"
source $PIPELINE_DIR/${PIPELINE}.sh $1
