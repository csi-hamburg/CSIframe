#!/bin/sh

####################
# submission script for distributed parallelism
# subjects are submitted in batches depending on pipeline choice
# arg1 - pipeline
# arg2 - session
# arg3 - subject subset
# e.g. srun pipelines_processing.sh bidsify 1 sub-test001 
####################

set -x

# export project env variables
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
export PROJ_DIR=$(realpath $SCRIPT_DIR/..) # project root; should be 1 level above code
export CODE_DIR=$PROJ_DIR/code
export ENV_DIR=$PROJ_DIR/envs
export DATA_DIR=$PROJ_DIR/data
export DCM_DIR=$PROJ_DIR/data/dicoms
export BIDS_DIR=$PROJ_DIR/data/raw_bids

export PIPELINE=$1;shift
export SESSION=$1;shift
input_subject_array=($@)
echo ${input_subject_array[@]}

# Read if $1 is empty
if [ -z $PIPELINE ];then
	echo "Which pipeline do you want to execute?"
	echo "Please choose from: $(ls $CODE_DIR/pipelines)"
	read input
	export PIPELINE=$input
fi

if [ -z $SESSION ];then
	echo "Which session do you want to process? e.g. '1'"
	read input
	export SESSION=$input
fi

# Define subjects
subj_array=(${input_subject_array[@]-$(ls $BIDS_DIR/sub-* -d -1 | xargs -n 1 basename)}) 
subj_array_length=${#subj_array[@]}

# Empirical job config
if [ $PIPELINE == "bidsify" ];then
	export SUBJS_PER_NODE=16  # 6
	batch_time="04:00:00"
	partition="std"
	at_once=
	subj_array=(${input_subject_array[@]-$(ls $DCM_DIR/* -d -1 | grep -v -e code -e sourcedata | xargs -n 1 basename)}) # subjects in data/dicoms

elif [ $PIPELINE == "qsiprep" ];then
	# Mind limitation by /scratch and memory capacity (23gb temporary files, 15gb max RAM usage)
	export SUBJS_PER_NODE=4
	batch_time="10:00:00"
	partition="std" # ponder usage of gpu for eddy speed up
	at_once=
	
	echo "Do you want to perform preprocessing only; i.e. qsiprep but no qsirecon (y/n)"
	read MODIFIED
	export MODIFIED

elif [ $PIPELINE == "smriprep" ];then
	export SUBJS_PER_NODE=8 
	batch_time="23:00:00"
	partition="std"
	at_once=
elif [ $PIPELINE == "mriqc" ];then
	export SUBJS_PER_NODE=4
	batch_time="02:00:00"
	partition="std"
	at_once=
elif [ $PIPELINE == "fmriprep" ];then
	export SUBJS_PER_NODE=4
	batch_time="15:00:00"
	partition="std"
	at_once=
elif [ $PIPELINE == "xcpengine" ];then
	export SUBJS_PER_NODE=16
	batch_time="12:00:00"
	partition="std"
	at_once=
elif [ $PIPELINE == "wmhprep" ];then
	export SUBJS_PER_NODE=8
	batch_time="04:00:00"
	partition="std"
elif [ $PIPELINE == "freewater" ];then
	export SUBJS_PER_NODE=4
	batch_time="02:00:00"
	partition="std"
elif [ $PIPELINE == "bianca" ];then
	export SUBJS_PER_NODE=16
	batch_time="08:00:00"
	partition="std"
else
	echo "Pipeline $PIPELINE not supported"
	exit
fi

# define batch script
script_name="pipelines_parallelization.sh"
script_path=$CODE_DIR/$script_name

# If subject array length < subjects per node -> match subjects per node to array length
[ $subj_array_length -lt $SUBJS_PER_NODE ] && export SUBJS_PER_NODE=$subj_array_length
echo Submitting $subj_array_length subjects for $PIPELINE processing

batch_amount=$(($subj_array_length / $SUBJS_PER_NODE))
export ITER=0

# If modulo of subject array length and subjects per node is not 0 -> add one iteration
[ ! $(( $subj_array_length % $SUBJS_PER_NODE )) -eq 0 ] && batch_amount=$(($batch_amount + 1))

# Loop through subject batches for submission
for batch in $(seq $batch_amount);do
	subj_batch_array=${subj_array[@]:$ITER:$SUBJS_PER_NODE}
    CMD="sbatch --job-name $PIPELINE \
        --time ${batch_time} \
        --partition $partition \
        --output $CODE_DIR/log/"%A-${PIPELINE}-$ITER-$(date +%d%m%Y).out" \
        --error $CODE_DIR/log/"%A-${PIPELINE}-$ITER-$(date +%d%m%Y).err" \
    	$script_path "${subj_batch_array[@]}""
	export ITER=$(($ITER+$SUBJS_PER_NODE))
	$CMD
done