#!/usr/bin/env bash

###################################################################################################################
# Submission script for distributed parallelism
# Subjects are submitted in batches depending on pipeline choice
# arg1 - subject subset (if not provided all subjects will be processed)
# e.g. bash pipelines_processing.sh sub-test001 
###################################################################################################################

# Define environment
export SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
set -o allexport
source $SCRIPT_DIR/environment.conf
set +o allexport

# Provide option for interactive execution
echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"
echo "Do you want to compute interactively? (y/n); default: 'y'"
read INTERACTIVE; [ -z $INTERACTIVE ] && INTERACTIVE=y
export INTERACTIVE

# Define pipeline
echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"
echo "Which pipeline do you want to execute?"
echo "Please choose from: $(ls $CODE_DIR/pipelines | tr '\n' ' ')"
read PIPELINE; export PIPELINE
export PIPELINE_SUFFIX=""


# Define session to process
echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"
if [[ "aslprep fmriprep mriqc qsiprep smriprep" == *"$PIPELINE"* ]]; then
	echo "aslprep, fmriprep, mriqc, qsiprep and smriprep do not require session input"
else 
	echo "Which session do you want to process?"
	[ -d $BIDS_DIR ] && echo "Choose from: $(ls $DATA_DIR/raw_bids/sub-*/* -d | xargs -n 1 basename | sort | uniq | cut -d "-" -f 2 | tr '\n' ' ') $([[ "bidsify freesurfer" == *"$PIPELINE"* ]] && echo -e "all")"
	read SESSION; export SESSION
fi


# Define subjects
echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"
if [ $# != 0 ];then
	subj_array=($@)
    echo "Processing subject(s) ${subj_array[@]}"
	sleep 1
else
	subj_array=($(ls $BIDS_DIR/sub-* -d -1 | xargs -n 1 basename))
	[ -d $BIDS_DIR ] && echo "No subjects as arguments supplied." && echo "Reading subjects from $BIDS_DIR" && sleep 1
fi
subj_array_length=${#subj_array[@]}


# Empirical job config
if [ $PIPELINE == "bidsify" ];then
	
	export SUBJS_PER_NODE=16
	export ANALYSIS_LEVEL=subject
	batch_time_default="04:00:00"
	partition_default="std"

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"
	echo "Reading subjects from $DCM_DIR"
	subj_array=(${@-$(ls $DCM_DIR/* -d -1 | grep -v -e code -e sourcedata -e README | xargs -n 1 basename)}) # subjects in data/dicoms
	subj_array_length=${#subj_array[@]}

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"		
	echo "Which bidsify pipeline do you want to perform? Leave empty for core or type 'asl'."
	read BIDSIFY_PIPE; export BIDSIFY_PIPE
	export PIPELINE_SUFFIX=_${BIDSIFY_PIPE}

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"
	echo "Which heuristic do you want to apply?"
	echo "Choose from" $(ls $CODE_DIR/pipelines/bidsify/heudiconv_*.py | xargs -n 1 basename)
	read HEURISTIC; export HEURISTIC

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"	
	echo "Do you want to deface participants? (y/n)"
	read MODIFIER; export MODIFIER

	
elif [ $PIPELINE == "qsiprep" ];then
	
	# Mind limitation by /scratch and memory capacity (23gb temporary files, 15gb max RAM usage)
	export SUBJS_PER_NODE=4
	export ANALYSIS_LEVEL=subject
	batch_time_default="14:00:00"
	partition_default="std" # ponder usage of gpu for eddy speed up

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"		
	echo "What is the desired output resolution? e.g. '1.3'"
	echo "Leave empty if you want to use default (2)"
	read $OUTPUT_RESOLUTION; [ -z $OUTPUT_RESOLUTION ] && export OUTPUT_RESOLUTION=2

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"	
	echo "Which reconstruction pipeline do you want to apply after preprocessing? (mrtrix_singleshell_ss3t, mrtrix_multishell_msmt)"
	echo "Leave empty if you want to use none"
	read RECON; export RECON

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"	
	echo "Choose additional arguments you want to provide to qsiprep call; e.g. '--dwi-only'"
	read MODIFIER; export MODIFIER

elif [ $PIPELINE == "smriprep" ];then
	
	export SUBJS_PER_NODE=8 
	export ANALYSIS_LEVEL=subject
	batch_time_default="23:00:00"
	partition_default="std"

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"	
	echo "Please enter specific templates if you want to use them."
	echo "Choose from tested adult templates (fsnative fsaverage MNI152NLin6Asym anat)"
	echo "or infant templates (MNIPediatricAsym:cohort-1:res-native)"
	echo "Enter nothing to keep defaults (fsnative fsaverage MNI152NLin6Asym anat)"
	read OUTPUT_SPACES; export OUTPUT_SPACES

	[ -z $OUTPUT_SPACES ] && export OUTPUT_SPACES="fsnative fsaverage MNI152NLin6Asym anat"

elif [ $PIPELINE == "freesurfer" ];then
	
	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"	
	echo "Which pipeline level do you want to perform? (reconall/sub2avg)"
	echo "For default ('reconall') leave empty"
	read FS_LEVEL; export FS_LEVEL
	[ -z $FS_LEVEL ] && export FS_LEVEL=reconall
	export PIPELINE_SUFFIX=_${FS_LEVEL}

	if [ $FS_LEVEL == reconall ];then

		export SUBJS_PER_NODE=4
		export ANALYSIS_LEVEL=subject
		batch_time_default="2-00:00:00"
		partition_default="big"

	elif [ $FS_LEVEL == sub2avg ];then

		export SUBJS_PER_NODE=16
		export ANALYSIS_LEVEL=subject
		batch_time_default="03:00:00"
		partition_default="std"

	fi

elif [ $PIPELINE == "mriqc" ];then

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"	
	echo "Choose between participant and group level anaylsis (participant/group)." 
	echo "Please make sure participant level is finished before running group level analysis."
	read MRIQC_LEVEL; export MRIQC_LEVEL

	if [ $MRIQC_LEVEL == "participant" ]; then

		export SUBJS_PER_NODE=4
		export ANALYSIS_LEVEL=subject
		batch_time_default="24:00:00"
		partition_default="std"

	elif [ $MRIQC_LEVEL == "group" ]; then

		export SUBJS_PER_NODE=$subj_array_length
		export ANALYSIS_LEVEL=group
		batch_time_default="01:00:00"
		partition_default="std"

	fi

elif [ $PIPELINE == "fmriprep" ];then
	
	export SUBJS_PER_NODE=4
	export ANALYSIS_LEVEL=subject
	batch_time_default="1-00:00:00"
	partition_default="std"

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"	
	echo "Please enter specific templates if you want to use them."
	echo "Choose from tested adult templates (fsnative fsaverage MNI152NLin6Asym T1w)"
	echo "or infant templates (MNIPediatricAsym:cohort-1:res-native)"
	echo "Enter nothing to keep defaults (fsnative fsaverage MNI152NLin6Asym T1w)"
	read OUTPUT_SPACES; export OUTPUT_SPACES

	[ -z $OUTPUT_SPACES ] && export OUTPUT_SPACES="fsnative fsaverage MNI152NLin6Asym T1w"

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"	
	echo "Choose additional arguments you want to provide to fmriprep call; e.g. '--anat-only'"
	read MODIFIER; export MODIFIER
	
elif [ $PIPELINE == "xcpengine" ];then
	
	export SUBJS_PER_NODE=16
	export ANALYSIS_LEVEL=subject
	batch_time_default="16:00:00"
	partition_default="std"

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"	
	echo "Which xcpengine subanalysis do you want to use? (fc/struc)"
	read MODIFIER; export MODIFIER

elif [ $PIPELINE == "freewater" ];then

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"	
	echo "Which pipeline level do you want to perform? (core/2mni)"
	echo "For default ('core') leave empty"
	read FW_LEVEL; export FW_LEVEL
	[ -z $FW_LEVEL ] && export FW_LEVEL=core
	export PIPELINE_SUFFIX=_${FW_LEVEL}

	if [ $FW_LEVEL == core ];then

		export SUBJS_PER_NODE=4
		export ANALYSIS_LEVEL=subject
		batch_time_default="02:00:00"
		partition_default="std"

	elif [ $FW_LEVEL == 2mni ];then

		export SUBJS_PER_NODE=8
		export ANALYSIS_LEVEL=subject
		batch_time_default="03:00:00"
		partition_default="std"

	fi

elif [ $PIPELINE == "tbss" ];then

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"		
	echo "Which TBSS pipeline would you like to run? Choose between 'mni' and 'fixel'"
	read TBSS_PIPELINE; export TBSS_PIPELINE
	
	if [ $TBSS_PIPELINE != "mni" ] && [ $TBSS_PIPELINE != "fixel" ]; then
		echo "$TBSS_PIPELINE TBSS pipeline is not supported."
		exit
	fi

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"	
	echo "Which part of the TBSS pipeline do you want to perform? (1/2/3/4)"
	read TBSS_LEVEL; export TBSS_LEVEL
	export PIPELINE_SUFFIX=_${TBSS_LEVEL}

	if [ $TBSS_LEVEL == 1 ]; then

		export SUBJS_PER_NODE=16
		export ANALYSIS_LEVEL=subject
		batch_time_default="02:00:00"
		partition_default="std"

	elif [ $TBSS_LEVEL == 2 ]; then

		export SUBJS_PER_NODE=$subj_array_length
		export ANALYSIS_LEVEL=group
		batch_time_default="02:00:00"
		partition_default="std"

	elif [ $TBSS_LEVEL == 3 ]; then

		export SUBJS_PER_NODE=16
		export ANALYSIS_LEVEL=subject
		batch_time_default="02:00:00"
		partition_default="std"
	
	elif [ $TBSS_LEVEL == 4 ]; then

		echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"	
		echo "Please specify list of subjects whose skeletons you want to merge."
		echo "If you want to merge all subjects type 'all', otherwise choose from the following options:"
		
		ls $DATA_DIR/${PIPELINE}_${TBSS_PIPELINE}/code/merge* | cut -d "_" -f 2 | cut -d "." -f 1
		read TBSS_MERGE_LIST; export TBSS_MERGE_LIST

		export SUBJS_PER_NODE=$subj_array_length
		export ANALYSIS_LEVEL=group
		batch_time_default="6:00:00"
		partition_default="std"
	
	fi

elif [ $PIPELINE == "fba" ];then

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"		
	echo "Which FBA_LEVEL do you want to perform? (1/2/3/4/5)"
	read FBA_LEVEL; export FBA_LEVEL
	export PIPELINE_SUFFIX=_${FBA_LEVEL}

	if [ $FBA_LEVEL == 1 ];then
		
		export SUBJS_PER_NODE=$subj_array_length
		export ANALYSIS_LEVEL=group
		batch_time_default="03-00:00:00"
		partition_default="stl"

	elif [ $FBA_LEVEL == 2 ];then
		
		export SUBJS_PER_NODE=4
		export ANALYSIS_LEVEL=subject
		batch_time_default="24:00:00"
		partition_default="std"

	elif [ $FBA_LEVEL == 3 ];then
		
		export SUBJS_PER_NODE=$subj_array_length
		export ANALYSIS_LEVEL=group
		batch_time_default="03-00:00:00"
		partition_default="stl"

	elif [ $FBA_LEVEL == 4 ];then
		
		export SUBJS_PER_NODE=$subj_array_length
		export ANALYSIS_LEVEL=group
		batch_time_default="07-00:00:00"
		partition_default="big"

	elif [ $FBA_LEVEL == 5 ];then
		
		export SUBJS_PER_NODE=$subj_array_length
		export ANALYSIS_LEVEL=group
		batch_time_default="03-00:00:00"
		partition_default="stl"

	elif [ -z $FBA_LEVEL ];then
		
		echo "FBA level needs to be set"
		exit 0

	fi

elif [ $PIPELINE == "connectomics" ];then

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"		
	echo "On which connectome flavor do you want to apply network analysis? (sc/fc)"
	read MODIFIER; export MODIFIER

	if [ -z $MODIFIER ];then

		echo "Connectome type needs to be set"
		exit 0

	fi

	export SUBJS_PER_NODE=$subj_array_length
	export ANALYSIS_LEVEL=group
	batch_time_default="1-00:00:00"
	partition_default="std"

elif [ $PIPELINE == "psmd" ];then
	
	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"	
	echo "On which level you like to run the PSMD pipeline? Choose between 'subject' and 'group'. Subject level needs to be run first."
	read PSMD_LEVEL

	if [ $PSMD_LEVEL == "subject" ]; then
		
		export SUBJS_PER_NODE=16
		export ANALYSIS_LEVEL=subject
		batch_time_default="03:00:00"
		partition_default="std"

	elif [ $PSMD_LEVEL == "group" ];then
		
		export SUBJS_PER_NODE=$subj_array_length
		export ANALYSIS_LEVEL=group
		batch_time_default="00:30:00"
		partition_default="std"

	else
	 	echo "$PSMD_LEVEL for $PIPELINE pipeline not supported."
	 	exit
	 fi

elif [ $PIPELINE == "obseg" ];then
	
	export SUBJS_PER_NODE=1
	export ANALYSIS_LEVEL=subject
	batch_time_default="03:00:00"
	partition_default="std"

elif [ $PIPELINE == "cat12" ];then
	
	export SUBJS_PER_NODE=8
	export ANALYSIS_LEVEL=subject
	batch_time_default="08:00:00"
	partition_default="std"

elif [ $PIPELINE == "wmh" ];then
	
	export SUBJS_PER_NODE=16
	export ANALYSIS_LEVEL=subject
	batch_time_default="02:00:00"
	partition_default="std"

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"	
	echo "which part of analysis you want to do? currently available: antsrnet / bianca / lga / lpa / samseg"
	read ALGORITHM; export ALGORITHM

	if [ $ALGORITHM == "samseg" ]; then

		batch_time_default="04:00:00"

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
	
elif [ $PIPELINE == "statistics" ];then

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"		
	echo "Which method do you want to perform? (cfe)"
	read STAT_METHOD; export STAT_METHOD
	export PIPELINE_SUFFIX=_${STAT_METHOD}

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"		
	echo "Define hypothesis short (-> becomes name of subdirectory in data/statistics), e.g. 'cfe_group_comparison_postcovid_controls' or 'tfce_linear_relationship_fa_tmtb'"
	read MODIFIER; export MODIFIER

	if [ $STAT_METHOD == cfe ];then
		
		export SUBJS_PER_NODE=$subj_array_length
		export ANALYSIS_LEVEL=group
		batch_time_default="04:00:00"
		partition_default="std"

	fi
else
	
	echo "Pipeline $PIPELINE not supported"
	exit
fi

if [ $INTERACTIVE != y ];then
	# Set batch time to allocate and partition
	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"
	echo "How much time do you want to allocate? Default is $(echo $batch_time_default)"
	echo "Leave empty to choose default"
	read batch_time
	[ -z $batch_time ] && batch_time=$batch_time_default

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"
	echo "Which partition do you want to submit to? Default is $(echo $partition_default)"
	echo "Leave empty to choose default"
	read partition
	[ -z $partition ] && partition=$partition_default
fi

# Define batch script
script_name="02_pipelines_batch.sh"
SCRIPT_PATH=$CODE_DIR/$script_name

# If subject array length < subjects per node -> match subjects per node to array length
[ $subj_array_length -lt $SUBJS_PER_NODE ] && export SUBJS_PER_NODE=$subj_array_length
echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"	
echo Submitting $subj_array_length subjects for $PIPELINE processing

batch_amount=$(($subj_array_length / $SUBJS_PER_NODE))
export ITER=0

# If modulo of subject array length and subjects per node is not 0 -> add one iteration to make sure all subjects will be submitted
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
