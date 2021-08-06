#!/usr/bin/env bash

#SBATCH --nodes=1
#SBATCH --export=PIPELINE,SESSION,SUBJS_PER_NODE,ITER,MODIFIED

####################
# batch script for across subject parallelization
# test this script interactively by running 'srun script.sh' after salloc
####################

source /sw/batch/init.sh
start=$(date +%s)

# -x to get verbose logfiles
set -x

# Load HPC environment modules
module unload singularity
module switch singularity/3.5.2-overlayfix
module load parallel

# Source project environment
export SCRIPT_DIR=${SLURM_SUBMIT_DIR-$(dirname "$0")} # should be code
export PROJ_DIR=$(realpath $SCRIPT_DIR/..) # project root; should be 1 level above code
export CODE_DIR=$PROJ_DIR/code
export ENV_DIR=$PROJ_DIR/envs
export DATA_DIR=$PROJ_DIR/data
export DCM_DIR=$PROJ_DIR/data/dicoms
export BIDS_DIR=$PROJ_DIR/data/raw_bids

#source $SCRIPT_DIR/.projectrc
source /work/fatx405/set_envs/miniconda
source activate datalad # env with python>=3.8, datalad, pybids

# Define subarray of subjects to process
subjs=($@)
SUBJS_PER_NODE=${SUBJS_PER_NODE-5}
export ITER=${ITER-0}
subjs_start_idx=$(expr $ITER \* 1000 + ${SLURM_ARRAY_TASK_ID-0})

if [ $PIPELINE == bidsify ];then
	subjs=(${subjs[@]-$(ls $DCM_DIR/* -d -1 | grep -v -e code -e sourcedata)})
else
	subjs=(${subjs[@]-$(ls $BIDS_DIR/sub-* -d -1)})
fi

subjs_subarr=($(basename -a ${subjs[@]:$subjs_start_idx:$SUBJS_PER_NODE}))

echo starting processing with $PIPELINE from index: $subjs_start_idx ...
echo for n=$SUBJS_PER_NODE subjects
echo subjects to process: ${subjs_subarr[@]}
echo submission script directory: $SCRIPT_DIR
echo current TMPDIR: $TMPDIR
echo ITERator: $ITER

#################################################################
# Usage notes for parallelization with srun and GNU parallel
#
# Command example: "parallel --delay 0.2 -j2 'srun --exclusive -N1 -n1 
# --cpus-per-task 16 script.sh' ::: ${input_array[@]}"
#
# parallel -jX -> X tasks that GNU parallel invokes in parallel
# each  provided with a consecutive array element
#
# srun -nY -cpus-per-task Z -> Y tasks that slurm spawns, Z threads per task
# $parallel_script gets executed Y times with same!! array element
#
# To achieve across subject parallelization X = number of subjects
# to process per node, Y = 1 (execute script once per subject),
# Z = number of available threads / X -> drop floating point
#################################################################

# 32 threads per node on hummel but we allocate only 30 threads (empirical!)
threads_per_sub=$(awk "BEGIN {print int(30/$SUBJS_PER_NODE); exit}")
mem_per_sub=$(awk "BEGIN {print int(64000/$SUBJS_PER_NODE); exit}")

srun="srun --label --exclusive -N1 -n1 --cpus-per-task $threads_per_sub --mem-per-cpu=16000" 

parallel="parallel --ungroup --delay 0.2 -j$SUBJS_PER_NODE --joblog $CODE_DIR/log/parallel_runtask.log"

proc_script=$CODE_DIR/pipelines_processing.sh
echo -e "running:\n $parallel $srun $proc_script {} ::: ${subjs_subarr[@]}"
$parallel "$srun $proc_script" ::: ${subjs_subarr[@]}

# Monitor usage of /scratch partition
df -h /scratch

# Output script runtime
runtime_s=$(expr $(expr $(date +%s) - $start))
echo "script runtime: $(date -d@$runtime_s -u +%H:%M:%S) hours"
