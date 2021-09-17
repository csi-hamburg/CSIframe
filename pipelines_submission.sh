#!/bin/sh

####################
# submission script for distributed parallelism
# subjects are submitted in batches depending on pipeline choice
# arg1 - subject subset (if not provided all subjects will be processed)
# e.g. srun pipelines_processing.sh bidsify 1 sub-test001 
####################

set -x

echo "Is this an interactive session for testing purposes? (y/n)"
read INTERACTIVE

# export project env variables
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
export PROJ_DIR=$(realpath $SCRIPT_DIR/..) # project root; should be 1 level above code
export CODE_DIR=$PROJ_DIR/code
export ENV_DIR=$PROJ_DIR/envs
export DATA_DIR=$PROJ_DIR/data
export DCM_DIR=$PROJ_DIR/data/dicoms
export BIDS_DIR=$PROJ_DIR/data/raw_bids


# Read pipeline and session information in
echo "Which pipeline do you want to execute?"
echo "Please choose from: $(ls $CODE_DIR/pipelines)"
read PIPELINE; export PIPELINE

echo "Which session do you want to process? e.g. '1' 'all'"
read SESSION; export SESSION

# Define subjects
input_subject_array=($@)
subj_array=(${input_subject_array[@]-$(ls $BIDS_DIR/sub-* -d -1 | xargs -n 1 basename)}) 
subj_array_length=${#subj_array[@]}

# Empirical job config
if [ $PIPELINE == "bidsify" ];then
	
	export SUBJS_PER_NODE=16
	export ANALYSIS_LEVEL=subject
	batch_time="04:00:00"
	partition="std"
	at_once=
	subj_array=(${input_subject_array[@]-$(ls $DCM_DIR/* -d -1 | grep -v -e code -e sourcedata -e README | xargs -n 1 basename)}) # subjects in data/dicoms
	subj_array_length=${#subj_array[@]}

	echo "What heuristic do you want to apply?"
	echo "Choose from" $(ls $CODE_DIR/pipelines/bidsify/heudiconv_*.py | xargs -n 1 basename)
	read HEURISTIC; export HEURISTIC

elif [ $PIPELINE == "qsiprep" ];then
	
	# Mind limitation by /scratch and memory capacity (23gb temporary files, 15gb max RAM usage)
	export SUBJS_PER_NODE=4
	export ANALYSIS_LEVEL=subject
	batch_time="24:00:00"
	partition="std" # ponder usage of gpu for eddy speed up
	at_once=
	
	echo "Do you want to perform connectome reconstruction after preprocessing; i.e. qsiprep incl. qsirecon (y/n)"
	read RECON; export RECON

	if [ $RECON == y ];then
		echo "Choose reconstruction pipeline you want to apply (mrtrix_singleshell_ss3t, mrtrix_multishell_msmt)"
		read RECON_PIPELINE; export RECON_PIPELINE
	fi

elif [ $PIPELINE == "smriprep" ];then
	export SUBJS_PER_NODE=8 
	export ANALYSIS_LEVEL=subject
	batch_time="23:00:00"
	partition="std"
	at_once=

	echo "Please enter specific templates if you want to use them."
	echo "Choose from tested adult templates (fsnative fsaverage MNI152NLin6Asym anat)"
	echo "or infant templates (MNIPediatricAsym:cohort-1:res-native)"
	echo "Enter nothing to keep defaults (fsnative fsaverage MNI152NLin6Asym anat)"
	read OUTPUT_SPACES; export OUTPUT_SPACES

	if [ -z $OUTPUT_SPACES ];then
		export OUTPUT_SPACES="fsnative fsaverage MNI152NLin6Asym anat"
	fi

elif [ $PIPELINE == "mriqc" ];then

	echo "Choose between participant and group level anaylsis (participant/group)." 
	echo "Please make sure participant level is finished before running group level analysis."
	read MRIQC_LEVEL; export MRIQC_LEVEL

	if [ $MRIQC_LEVEL == "participant" ]; then
		export SUBJS_PER_NODE=4
		export ANALYSIS_LEVEL=subject
		batch_time="24:00:00"
		partition="std"
		at_once=
	elif [ $MRIQC_LEVEL == "group" ]; then
		export SUBJS_PER_NODE=$subj_array_length
		export ANALYSIS_LEVEL=group
		batch_time="01:00:00"
		partition="std"
		at_once=
	fi

elif [ $PIPELINE == "fmriprep" ];then
	export SUBJS_PER_NODE=4
	export ANALYSIS_LEVEL=subject
	batch_time="15:00:00"
	partition="std"
	at_once=

	echo "Please enter specific templates if you want to use them."
	echo "Choose from tested adult templates (fsnative fsaverage MNI152NLin6Asym anat)"
	echo "or infant templates (MNIPediatricAsym:cohort-1:res-native)"
	echo "Enter nothing to keep defaults (fsnative fsaverage MNI152NLin6Asym anat)"
	read OUTPUT_SPACES; export OUTPUT_SPACES

	if [ -z $OUTPUT_SPACES ];then
		export OUTPUT_SPACES="fsnative fsaverage MNI152NLin6Asym"
	fi

	echo "Choose additional arguments you want to provide to fmriprep call; e.g. '--anat-only'"
	read MODIFIER; export MODIFIER
	
elif [ $PIPELINE == "xcpengine" ];then
	export SUBJS_PER_NODE=16
	export ANALYSIS_LEVEL=subject
	batch_time="12:00:00"
	partition="std"
	at_once=

elif [ $PIPELINE == "wmhprep" ];then
	export SUBJS_PER_NODE=8
	export ANALYSIS_LEVEL=subject
	batch_time="04:00:00"
	partition="std"

elif [ $PIPELINE == "freewater" ];then
	export SUBJS_PER_NODE=4
	export ANALYSIS_LEVEL=subject
	batch_time="02:00:00"
	partition="std"

elif [ $PIPELINE == "tbss" ];then
	
	echo "Which TBSS pipeline would you like to run? Choose between 'enigma' and 'fmrib'"
	read TBSS_PIPELINE; export TBSS_PIPELINE
	
	if [ $TBSS_PIPELINE != "enigma" || "fmrib" ]; then
		echo "$TBSS_PIPELINE TBSS pipeline not supported."
		exit
	else
		export SUBJS_PER_NODE=$subj_array_length
		export ANALYSIS_LEVEL=group
		batch_time="01:00:00"
		partition="std"
	fi

elif [ $PIPELINE == "psmd" ];then
	
	echo "On which level you like to run the PSMD pipeline? Choose between 'subject' and 'group'"
	read PSMD_LEVEL

	if [ $PSMD_LEVEL == "subject" ]; then
		export SUBJS_PER_NODE=1
		export ANALYSIS_LEVEL=subject
		batch_time="00:20:00"
		partition="std"
	elif [ $PSMD_LEVEL == "group" ];then
		export SUBJS_PER_NODE=$subj_array_length
		export ANALYSIS_LEVEL=group
		batch_time="00:10:00"
		partition="std"
	else
	 	echo "$PSMD_LEVEL for $PIPELINE pipeline not supported."
	 	exit
	 fi

elif [ $PIPELINE == "bianca" ];then
	
	export SUBJS_PER_NODE=16
	export ANALYSIS_LEVEL=subject
	batch_time="08:00:00"
	partition="std"

elif [ $PIPELINE == "obseg" ];then
	
	export SUBJS_PER_NODE=1
	export ANALYSIS_LEVEL=subject
	batch_time="03:00:00"
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

	# Slice subj array from index $ITER for the amount of $SUBJS_PER_NODE subjects
	subj_batch_array=${subj_array[@]:$ITER:$SUBJS_PER_NODE}

	# In case of interactive session source $script_path directly
	if [ $INTERACTIVE == y ]; then
		srun $script_path "${subj_batch_array[@]}" #&& exit 0
		#source $script_path "${subj_batch_array[@]}" && exit 0
	elif [ $INTERACTIVE == n ]; then
	    CMD="sbatch --job-name $PIPELINE \
	        --time ${batch_time} \
	        --partition $partition \
	        --output $CODE_DIR/log/"%A-${PIPELINE}-$ITER-$(date +%d%m%Y).out" \
	        --error $CODE_DIR/log/"%A-${PIPELINE}-$ITER-$(date +%d%m%Y).err" \
	    	$script_path "${subj_batch_array[@]}""
		$CMD
	else
		echo "\$INTERACTIVE is not 'y' or 'n'"
		echo "Exiting"
		exit 1
	fi
	# Increase ITER by SUBJS_PER_NODE
	export ITER=$(($ITER+$SUBJS_PER_NODE))
done