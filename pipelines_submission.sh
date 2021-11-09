#!/bin/sh

####################
# submission script for distributed parallelism
# subjects are submitted in batches depending on pipeline choice
# arg1 - subject subset (if not provided all subjects will be processed)
# e.g. srun pipelines_processing.sh bidsify 1 sub-test001 
####################

set -x

echo "Is this an interactive session for testing purposes? (y/n)"
read INTERACTIVE; export INTERACTIVE

# export project env variables
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
export PROJ_DIR=$(realpath $SCRIPT_DIR/..) # project root; should be 1 level above code
export CODE_DIR=$SCRIPT_DIR
export ENV_DIR=$PROJ_DIR/envs
export DATA_DIR=$PROJ_DIR/data
export DCM_DIR=$PROJ_DIR/data/dicoms
export BIDS_DIR=$PROJ_DIR/data/raw_bids

# Read pipeline and session information in
echo "Which pipeline do you want to execute?"
echo "Please choose from: $(ls $CODE_DIR/pipelines)"
read PIPELINE; export PIPELINE
export PIPELINE_SUFFIX=""

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

	echo "Do you want to deface participants? (y/n)"
	read MODIFIER; export MODIFIER

	echo "Which session do you want to process? e.g. '1' 'all'"
	read SESSION; export SESSION

elif [ $PIPELINE == "qsiprep" ];then
	
	# Mind limitation by /scratch and memory capacity (23gb temporary files, 15gb max RAM usage)
	export SUBJS_PER_NODE=4
	export ANALYSIS_LEVEL=subject
	batch_time="14:00:00"
	partition="std" # ponder usage of gpu for eddy speed up
	at_once=
	
	echo "What is the desired output resolution? e.g. '1.3'"
	echo "Leave empty if you want to use default (2)"
	read $OUTPUT_RESOLUTION; [ -z $OUTPUT_RESOLUTION ] && export OUTPUT_RESOLUTION=2

	echo "If you want to perform connectome reconstruction after preprocessing (i.e. qsiprep incl. qsirecon) please provide reconstruction pipeline (mrtrix_singleshell_ss3t, mrtrix_multishell_msmt)"
	echo "Leave empty if you want to use default (mrtrix_singleshell_ss3t)"
	read RECON; export RECON

	if [ -z $RECON ];then
		export RECON=mrtrix_singleshell_ss3t
	fi

	echo "Choose additional arguments you want to provide to qsiprep call; e.g. '--dwi-only'"
	read MODIFIER; export MODIFIER

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

elif [ $PIPELINE == "freesurfer" ];then
	export SUBJS_PER_NODE=4
	export ANALYSIS_LEVEL=subject
	batch_time="2-00:00:00"
	partition="big"
	at_once=

	echo "Which session do you want to process? e.g. '1' 'all'"
	read SESSION; export SESSION

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
	batch_time="1-00:00:00"
	partition="std"
	at_once=

	echo "Please enter specific templates if you want to use them."
	echo "Choose from tested adult templates (fsnative fsaverage MNI152NLin6Asym T1w)"
	echo "or infant templates (MNIPediatricAsym:cohort-1:res-native)"
	echo "Enter nothing to keep defaults (fsnative fsaverage MNI152NLin6Asym T1w)"
	read OUTPUT_SPACES; export OUTPUT_SPACES

	if [ -z $OUTPUT_SPACES ];then
		export OUTPUT_SPACES="fsnative fsaverage MNI152NLin6Asym T1w"
	fi

	echo "Choose additional arguments you want to provide to fmriprep call; e.g. '--anat-only'"
	read MODIFIER; export MODIFIER
	
elif [ $PIPELINE == "xcpengine" ];then
	export SUBJS_PER_NODE=8
	export ANALYSIS_LEVEL=subject
	batch_time="16:00:00"
	partition="std"
	at_once=

	echo "Which session do you want to process? e.g. '1' 'all'"
	read SESSION; export SESSION

	echo "Which xcpengine subanalysis do you want to use? (fc/struc)"
	read MODIFIER; export MODIFIER

	#echo "Pick design you want use"
	#echo "Choose from $(ls $CODE_DIR/pipelines/xcpengine/*.dsn | xargs -n 1 basename)"
	#read DESIGN; export DESIGN


elif [ $PIPELINE == "freewater" ];then

	echo "Which pipeline level do you want to perform? (core/2mni)"
	echo "For default ('core') leave empty"
	read FW_LEVEL; export FW_LEVEL
	[ -z $FW_LEVEL ] && export FW_LEVEL=core
	export PIPELINE_SUFFIX=_${FW_LEVEL}

	if [ $FW_LEVEL == core ];then
		export SUBJS_PER_NODE=4
		export ANALYSIS_LEVEL=subject
		batch_time="02:00:00"
		partition="std"
	elif [ $FW_LEVEL == 2mni ];then
		export SUBJS_PER_NODE=8
		export ANALYSIS_LEVEL=subject
		batch_time="03:00:00"
		partition="std"
	fi

	echo "Which session do you want to process? e.g. '1' 'all'"
	read SESSION; export SESSION

elif [ $PIPELINE == "tbss" ];then
	
	echo "Which TBSS pipeline would you like to run? Choose between 'enigma' and 'fmrib'"
	read TBSS_PIPELINE; export TBSS_PIPELINE
	
	if [ $TBSS_PIPELINE != "enigma" ] && [ $TBSS_PIPELINE != "fmrib" ]; then
		echo "$TBSS_PIPELINE TBSS pipeline not supported."
		exit
	else
		export SUBJS_PER_NODE=$subj_array_length
		export ANALYSIS_LEVEL=group
		batch_time="12:00:00"
		partition="std"
	fi

	echo "Which session do you want to process? e.g. '1' 'all'"
	read SESSION; export SESSION

elif [ $PIPELINE == "fba" ];then


	echo "Which FBA_LEVEL do you want to perform? (1/2/3/4/5)"
	read FBA_LEVEL; export FBA_LEVEL
	export PIPELINE_SUFFIX=_${FBA_LEVEL}

	if [ $FBA_LEVEL == 1 ];then
		export SUBJS_PER_NODE=$subj_array_length
		export ANALYSIS_LEVEL=group
		batch_time="01-00:00:00"
		partition="std"
	elif [ $FBA_LEVEL == 2 ];then
		export SUBJS_PER_NODE=4
		export ANALYSIS_LEVEL=subject
		batch_time="12:00:00"
		partition="std"
	elif [ $FBA_LEVEL == 3 ];then
		export SUBJS_PER_NODE=$subj_array_length
		export ANALYSIS_LEVEL=group
		batch_time="03-00:00:00"
		partition="big"
	elif [ $FBA_LEVEL == 4 ];then
		export SUBJS_PER_NODE=$subj_array_length
		export ANALYSIS_LEVEL=group
		batch_time="07-00:00:00"
		partition="big"
	elif [ $FBA_LEVEL == 5 ];then
		export SUBJS_PER_NODE=$subj_array_length
		export ANALYSIS_LEVEL=group
		batch_time="01-00:00:00"
		partition="std"
	elif [ -z $FBA_LEVEL ];then
		echo "FBA level needs to be set"
		exit 0
	fi



	echo "Which session do you want to process? e.g. '1' 'all'"
	read SESSION; export SESSION

elif [ $PIPELINE == "connectomics" ];then


	echo "On which connectome flavor do you want to apply network analysis? (sc/fc)"
	read MODIFIER; export MODIFIER

	if [ -z $MODIFIER ];then
		echo "Connectome type needs to be set"
		exit 0
	fi

	export SUBJS_PER_NODE=1
	export ANALYSIS_LEVEL=subject
	batch_time="00:30:00"
	partition="std"

	echo "Which session do you want to process? e.g. '1' 'all'"
	read SESSION; export SESSION

elif [ $PIPELINE == "psmd" ];then
	
	echo "On which level you like to run the PSMD pipeline? Choose between 'subject' and 'group'. Subject level needs to be run first."
	read PSMD_LEVEL

	if [ $PSMD_LEVEL == "subject" ]; then
		export SUBJS_PER_NODE=16
		export ANALYSIS_LEVEL=subject
		batch_time="02:00:00"
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

	echo "Which session do you want to process? e.g. '1' 'all'"
	read SESSION; export SESSION

elif [ $PIPELINE == "obseg" ];then
	
	export SUBJS_PER_NODE=1
	export ANALYSIS_LEVEL=subject
	batch_time="03:00:00"
	partition="std"

	echo "Which session do you want to process? e.g. '1' 'all'"
	read SESSION; export SESSION


elif [ $PIPELINE == "cat12" ];then
	
	export SUBJS_PER_NODE=8
	export ANALYSIS_LEVEL=subject
	batch_time="08:00:00"
	partition="std"

	echo "Which session do you want to process? e.g. '1' 'all'"
	read SESSION; export SESSION

elif [ $PIPELINE == "wmh" ];then
	
	export SUBJS_PER_NODE=16
	export ANALYSIS_LEVEL=subject
	batch_time="02:00:00"
	partition="std"

	echo "which part of analysis you want to do? currently available: antsrnet / bianca / lga / lpa / samseg"
	read ALGORITHM; export ALGORITHM

	if [ $ALGORITHM == "samseg" ]; then

		batch_time="04:00:00"

		echo "samseg does not recommend any bias-correction. Automatically set to NO."
		BIASCORR=n; export BIASCORR

	elif [ $ALGORITHM == "lga" ]; then

		echo "lga does not recommend any bias-correction. Automatically set to NO."
		BIASCORR=n; export BIASCORR

	elif [ $ALGORITHM == "lpa" ]; then

		echo "lpa does not recommend any bias-correction. Automatically set to NO."
		BIASCORR=n; export BIASCORR

	else

		echo "do you want to perform bias-correction? (y/n)"
		read BIASCORR; export BIASCORR

	fi

	echo "do you want to play the masking game? (y/n) | Caution: this may sound like fun, but is no fun at all."
	read MASKINGGAME; export MASKINGGAME

	echo "Which session do you want to process? e.g. '1' 'all'"
	read SESSION; export SESSION
	
elif [ $PIPELINE == "statistics" ];then

	echo "Which session do you want to process? e.g. '1' 'all'"
	read SESSION; export SESSION

	echo "Which method do you want to perform? (cfe)"
	read STAT_METHOD; export STAT_METHOD
	export PIPELINE_SUFFIX=_${STAT_METHOD}

	echo "Define hypothesis short (-> becomes name of subdirectory in data/statistics), e.g. 'cfe_group_comparison_postcovid_controls' or 'tfce_linear_relationship_fa_tmtb'"
	read MODIFIER; export MODIFIER

	if [ $STAT_METHOD == cfe ];then
		export SUBJS_PER_NODE=$subj_array_length
		export ANALYSIS_LEVEL=group
		batch_time="04:00:00"
		partition="std"
	fi
else
	
	echo "Pipeline $PIPELINE not supported"
	exit
fi

# Define batch script
script_name="pipelines_parallelization.sh"
SCRIPT_PATH=$CODE_DIR/$script_name

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

	# In case of interactive session run $SCRIPT_PATH directly
	if [ $INTERACTIVE == y ]; then
		srun $SCRIPT_PATH "${subj_batch_array[@]}"

	elif [ $INTERACTIVE == n ]; then
	    CMD="sbatch --job-name ${PIPELINE}${PIPELINE_SUFFIX} \
	        --time ${batch_time} \
	        --partition $partition \
	        --output $CODE_DIR/log/"%A-${PIPELINE}-$ITER-$(date +%d%m%Y).out" \
	        --error $CODE_DIR/log/"%A-${PIPELINE}-$ITER-$(date +%d%m%Y).err" \
	    	$SCRIPT_PATH "${subj_batch_array[@]}""
		$CMD
	else
		echo "\$INTERACTIVE is not 'y' or 'n'"
		echo "Exiting"
		exit 1
	fi
	# Increase ITER by SUBJS_PER_NODE
	export ITER=$(($ITER+$SUBJS_PER_NODE))
done
