#!/bin/sh

####################
# submission script for distributed parallelism
# subjects are submitted in batches depending on pipeline choice
# provide pipeline name as argument (heudiconv, qsiprep, smriprep, fmriprep, mriqc, xcpengine, wmhprep, bianca_train, bianca_predict)
####################

set -x

# export project env variables
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source $SCRIPT_DIR/.projectrc
export PIPELINE=$1

# define subjects
subjs=($(ls $PROJ_DIR/sub-* -d -1)) 
subj_array_length=$(expr ${#subjs[@]} - 1)

# define batch script
script_name="pipelines_parallelization.sh"
script_path=$CODE_DIR/$script_name

# empirical job config
if [ $PIPELINE == "bidsify" ];then
	export SUBJS_PER_NODE=10
	batch_time="02:00:00"
	partition="std"
	at_once=
	subjs=($(ls $DCM_DIR/* -d -1)) # subjects in sourcedata
elif [ $PIPELINE == "qsiprep" ];then
	export SUBJS_PER_NODE=2
	batch_time="12:00:00"
	partition="std" # ponder usage of gpu for eddy speed up
	at_once=
elif [ $PIPELINE == "smriprep" ];then
	export SUBJS_PER_NODE=2
	batch_time="15:00:00"
	partition="std"
	at_once=
elif [ $PIPELINE == "mriqc" ];then
	export SUBJS_PER_NODE=2
	batch_time="08:00:00"
	partition="std"
	at_once=
elif [ $PIPELINE == "fmriprep" ];then
	export SUBJS_PER_NODE=4
	batch_time="16:00:00"
	partition="std"
	at_once=
elif [ $PIPELINE == "xcpengine" ];then
	export SUBJS_PER_NODE=16
	batch_time="12:00:00"
	partition="std"
	at_once=
elif [ $PIPELINE == "wmhprep" ];then
	export SUBJS_PER_NODE=16
	batch_time="04:00:00"
	partition="std"
else
	echo "Pipeline $PIPELINE not supported"
	exit
fi

# subdivision of subjs in batches <= 1000 since max slurm array size = 1000
times_1000=$(expr $subj_array_length / 1000 + 1)
if [ $subj_array_length -ge 1000  ];then
	batchsize=1000
else
	batchsize=$subj_array_length	
fi

# submission for every 1000 subjs
# passed to batchscript for array slicing
echo submitting $subj_array_length subjects for $PIPELINE processing

for i in $(seq $times_1000);do                

    # ITER used for proper array slicing in batch script
    export ITER=$(expr $i - 1)                       

    # for last batch batchsize = remaining subjects (<= 1000)
    if [ $i == $times_1000 ]; then
        batchsize=$(expr $subj_array_length - $ITER \* $batchsize)
    fi

    CMD="sbatch --job-name $PIPELINE \
        --array=[0-$batchsize:$SUBJS_PER_NODE]${at_once} \
        --time ${batch_time} \
        --partition $partition \
	--tasks-per-node=$SUBJS_PER_NODE \
        --output $CODE_DIR/slurm_output/"%A_%a_${script_name}.out" \
        --error $CODE_DIR/slurm_output/"%A_%a_${script_name}.err" \
    $script_path "${subjs[@]}""
    ${CMD}
done
