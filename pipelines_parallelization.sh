#!/usr/bin/env bash

#SBATCH --nodes=1
#SBATCH --export=PIPELINE,SUBJS_PER_NODE,ITER

####################
# batch script for across subject parallelization
# test this script interactively by running 'srun script.sh' after salloc
####################

source /sw/batch/init.sh
start=$(date +%s)

# -x to get verbose logfiles
set -x

# subjs passed from submission script
subjs=($@)

# load HPC environment modules
module unload singularity
module switch singularity/3.5.2-overlayfix
module load parallel

# source project environment
SCRIPT_DIR=${SLURM_SUBMIT_DIR-$(dirname "$0")} # "$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"}
source $SCRIPT_DIR/.projectrc
source $WORK/set_envs/miniconda
source activate datalad # env with python>=3.8, datalad, pybids

# define subarray of subjects to process
SUBJS_PER_NODE=${SUBJS_PER_NODE-2}
ITER=${ITER-0}
subjs_start_idx=$(expr $ITER \* 1000 + ${SLURM_ARRAY_TASK_ID-0})

if [ $PIPELINE == bidsify ];then
	subjs=(${subjs[@]-$(ls $DCM_DIR/* -d -1)})
else
	subjs=(${subjs[@]-$(ls $PROJ_DIR/sub-* -d -1)})
fi

subjs_subarr=($(basename -a ${subjs[@]:$subjs_start_idx:$SUBJS_PER_NODE}))

echo starting processing with $PIPELINE from index: $subjs_start_idx ...
echo for n=$SUBJS_PER_NODE subjects
echo subjects to process: ${subjs_subarr[@]}
echo submission script directory: $SCRIPT_DIR
echo current TMPDIR: $TMPDIR
echo ITERator: $ITER

#################################################################
# usage notes for parallelization with srun and GNU parallel
#
# command example: "parallel --delay 0.2 -j2 'srun --exclusive -N1 -n1 
# --cpus-per-task 16 script.sh' ::: ${input_array[@]}"
#
# parallel -jX -> X tasks that GNU parallel invokes in parallel
# each  provided with a consecutive array element
#
# srun -nY -cpus-per-task Z -> Y tasks that slurm spawns, Z threads per task
# $parallel_script gets executed Y times with same!! array element
#
# to achieve across subject parallelization X = number of subjects
# to process per node, Y = 1 (execute script once per subject),
# Z = number of available threads / X -> drop floating point
#################################################################

# 32 threads per node on hummel but we allocate only 30 threads (empirical!)
threads_per_sub=$(awk "BEGIN {print int(30/$SUBJS_PER_NODE); exit}")
mem_per_sub=$(awk "BEGIN {print int(64000/$SUBJS_PER_NODE); exit}")

srun="srun --label --exclusive -N1 -n1 --cpus-per-task $threads_per_sub --mem-per-cpu=16000" 

parallel="parallel --ungroup --progress --delay 0.2 -j$SUBJS_PER_NODE --joblog $CODE_DIR/slurm_output/parallel_runtask.log"

proc_script=$CODE_DIR/05_2_pipeline_processing.sh
echo -e "running:\n $parallel $srun $proc_script ::: ${subjs_subarr[@]}"
$parallel "$srun $proc_script" ::: ${subjs_subarr[@]}

# monitor usage of /scratch partition
df -h /scratch

# output script runtime
runtime_s=$(expr $(expr $(date +%s) - $start))
echo "script runtime: $(date -d@$runtime_s -u +%H:%M:%S) hours"
