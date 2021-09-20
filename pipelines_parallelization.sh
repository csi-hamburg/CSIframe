#!/usr/bin/env bash

#SBATCH --nodes=1
#SBATCH --export=PIPELINE,SESSION,SUBJS_PER_NODE,ITER,ANALYSIS_LEVEL,OUTPUT_SPACES,HEURISTIC,RECON,MRIQC_LEVEL,TBSS_PIPELINE,MODIFIER

####################
# Batch script for across subject parallelization
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

#source /work/fatx405/set_envs/miniconda
#source activate datalad # env with python>=3.8, datalad, pybids

if [ -z $ANALYSIS_LEVEL ];then
	echo "Specify analysis level. (subject/group)"
	read ANALYSIS_LEVEL; export ANALYSIS_LEVEL
fi

# Define subarray of subjects to process
subj_batch_array=($@)

# For interactive tests define subj_batch_array if not defined
if [ $PIPELINE == bidsify ];then
	subj_batch_array=(${subj_batch_array[@]:-$(ls $DCM_DIR/* -d -1 | grep -v -e code -e sourcedata | xargs -n 1 basename)})
else
	subj_batch_array=(${subj_batch_array[@]:-$(ls $BIDS_DIR/sub-* -d -1 | xargs -n 1 basename)})
fi

SUBJS_PER_NODE=${SUBJS_PER_NODE-8}
export ITER=${ITER-0}

echo starting processing with $PIPELINE from index: $ITER ...
echo for n=$SUBJS_PER_NODE subjects
echo subjects to process: ${subj_batch_array[@]}
echo submission script directory: $SCRIPT_DIR
echo current TMPDIR: $TMPDIR
echo ITERator: $ITER

proc_script=$CODE_DIR/pipelines_processing.sh

if [ $ANALYSIS_LEVEL == subject ];then
	parallel="parallel --ungroup --delay 0.2 -j$SUBJS_PER_NODE --joblog $CODE_DIR/log/parallel_runtask.log"
	echo -e "running:\n $parallel $proc_script {} ::: ${subj_batch_array[@]}"
	$parallel $proc_script ::: ${subj_batch_array[@]}
elif [ $ANALYSIS_LEVEL == group ];then
	source $proc_script "${subj_batch_array[@]}"
fi

# Monitor usage of /scratch partition
df -h /scratch

# Output script runtime
runtime_s=$(expr $(expr $(date +%s) - $start))
echo "script runtime: $(date -d@$runtime_s -u +%H:%M:%S) hours"
