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
echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"
echo "Do you want to compute interactively? (y/n); default: 'y'"
read INTERACTIVE; [ -z $INTERACTIVE ] && INTERACTIVE=y
export INTERACTIVE

# Define pipeline
echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"
echo "Which pipeline do you want to execute?"
echo "Please choose from: $(ls $CODE_DIR/pipelines | tr '\n' ' ')"
read PIPELINE; export PIPELINE
export PIPELINE_SUFFIX=""


# Define session to process
echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"
if [[ "aslprep fmriprep mriqc qsiprep smriprep statistics" == *"$PIPELINE"* ]]; then
	echo "aslprep, fmriprep, mriqc, qsiprep, smriprep and statistics do not require session input"
else 
	echo "Which session do you want to process? (e.g., for ses-1 type '1')"
	[ -d $BIDS_DIR ] && echo "Choose from: $(ls $DATA_DIR/raw_bids/sub-*/* -d | xargs -n 1 basename | sort | uniq | cut -d "-" -f 2 | tr '\n' ' ') $([[ "bidsify freesurfer" == *"$PIPELINE"* ]] && echo -e "all")"
	read SESSION; export SESSION
fi


# Define subjects
echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"
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
	
	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"
	echo "Reading subjects from $DCM_DIR"
	subj_array=(${@-$(ls $DCM_DIR/* -d -1 | grep -v -e code -e sourcedata -e README | xargs -n 1 basename)}) # subjects in data/dicoms
	subj_array_length=${#subj_array[@]}

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"
	echo "Would you like to run heudiconv or edit ASL output of previous heudiconv run? (heudiconv/asl)"
	read BIDS_PIPE; export BIDS_PIPE

	if [ $BIDS_PIPE == "heudiconv" ]; then

		echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"
		echo "Which heuristic do you want to apply?"
		echo "Choose from" $(ls $ENV_DIR/bidsify/heudiconv_*.py | xargs -n 1 basename)
		read HEURISTIC; export HEURISTIC

		echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"	
		echo "Do you want to deface participants? (y/n)"
		read MODIFIER; export MODIFIER

		export SUBJS_PER_NODE=16
		export ANALYSIS_LEVEL=subject
		batch_time_default="04:00:00"
		partition_default="std"
	
	elif [ $BIDS_PIPE == "asl" ]; then
	
		echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"		
		echo "Which ASL metadata do you want to add?"
		echo "Choose from" $(ls $ENV_DIR/bidsify/metadataextra_*.json | xargs -n 1 basename)
		read METADATA_EXTRA; export METADATA_EXTRA

		export SUBJS_PER_NODE=16
		export ANALYSIS_LEVEL=subject
		batch_time_default="02:00:00"
		partition_default="std"
		
	fi

elif [ $PIPELINE == "nice" ];then

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"	
	echo "Please provide the name of directory (in DATA_DIR) containing lesion masks."
	echo "Choose from:"
	ls -1 $DATA_DIR
	read LESION_DIR; export LESION_DIR

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"	
	echo "Please provide the space of original lesion segmentation"
	echo "Currently available: FLAIR"
	read ORIG_SPACE; export ORIG_SPACE

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"	
	echo "Would you like to perform tissue fate analysis (longitudinal processing)?"
	echo "This only works if you have chosen ses-1 in this submission."
	echo "Type in 'yes' or 'no' to proceed."
	read MODIFIER; export MODIFIER

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"	
	echo "Which standard space would you like to use?"
	echo "Currently available: 'brainder' or 'miplab'. Note, when choosing brainder, ROI extraction for vascular territories will be performed."
	read TEMP_SPACE; export TEMP_SPACE

	export SUBJS_PER_NODE=8
	export ANALYSIS_LEVEL=subject
	batch_time_default="06:00:00"
	partition_default="std"

elif [ $PIPELINE == "arctic" ];then

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼"	
	echo "Note: ASLprep needs to be run first for preprocessing of T1w images."

	export SUBJS_PER_NODE=8
	export ANALYSIS_LEVEL=subject
	batch_time_default="02:00:00"
	partition_default="std"

elif [ $PIPELINE == "qsiprep" ];then
	
	# Mind limitation by /scratch and memory capacity (23gb temporary files, 15gb max RAM usage)
	export SUBJS_PER_NODE=4
	export ANALYSIS_LEVEL=subject
	batch_time_default="14:00:00"
	partition_default="std" # ponder usage of gpu for eddy speed up

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"		
	echo "What is the desired output resolution? e.g. '1.3'"
	echo "Leave empty if you want to use default (2)"
	read $OUTPUT_RESOLUTION; [ -z $OUTPUT_RESOLUTION ] && export OUTPUT_RESOLUTION=2

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"	
	echo "Which reconstruction pipeline do you want to apply after preprocessing? (mrtrix_singleshell_ss3t_ACT-hsvs, mrtrix_multishell_msmt_ACT-hsvs, amico_noddi, pyafq_tractometry, mrtrix_multishell_msmt_pyafq_tractometry)"
	echo "Leave empty if you want to use none"
	read RECON; export RECON

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"	
	echo "Choose additional arguments you want to provide to qsiprep call; e.g. '--dwi-only --use-syn-sdc --force-syn'"
	read MODIFIER; export MODIFIER

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"	
	echo "Do you want to perform AMICO NODDI in addition to qsiprep call? (y, leave empty if no)'"
	read APPLY_NODDI; export APPLY_NODDI

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"	
	echo "Do you want to perform pyafq_tractometry in addition to qsiprep call? (pyafq_tractometry, mrtrix_multishell_msmt_pyafq_tractometry, leave empty if no)'"
	read APPLY_PYAFQ; export APPLY_PYAFQ

elif [ $PIPELINE == "smriprep" ];then
	
	export SUBJS_PER_NODE=8 
	export ANALYSIS_LEVEL=subject
	batch_time_default="23:00:00"
	partition_default="std"

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"	
	echo "Please enter specific templates if you want to use them."
	echo "Choose from tested adult templates (fsnative fsaverage MNI152NLin6Asym anat)"
	echo "or infant templates (MNIPediatricAsym:cohort-1:res-native)"
	echo "Enter nothing to keep defaults (fsnative fsaverage MNI152NLin6Asym anat)"
	read OUTPUT_SPACES; export OUTPUT_SPACES

	[ -z $OUTPUT_SPACES ] && export OUTPUT_SPACES="fsnative fsaverage MNI152NLin6Asym anat"

elif [ $PIPELINE == "freesurfer" ];then
	
	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"	
	echo "Which pipeline level do you want to perform? (reconall/sub2avg/long/brainstemseg)"
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

	elif [ $FS_LEVEL == long ];then

		export SUBJS_PER_NODE=4
		export ANALYSIS_LEVEL=subject
		batch_time_default="1-00:00:00"
		partition_default="std"

	elif [ $FS_LEVEL == brainstemseg ];then

		echo "For brainstem segmentation 'reconall' needs to be run first. <Enter> to proceed."
		read
		export SUBJS_PER_NODE=8
		export ANALYSIS_LEVEL=subject
		batch_time_default="08:00:00"
		partition_default="std"


	fi

elif [ $PIPELINE == "mriqc" ];then

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"	
	echo "Choose between participant and group level analysis (participant/group)." 
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

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"	
	echo "Please enter specific templates if you want to use them."
	echo "Choose from tested adult templates (fsnative fsaverage fsaverage5 MNI152NLin6Asym MNI152NLin2009cAsym T1w func)"
	echo "or infant templates (MNIPediatricAsym:cohort-1:res-native)"
	echo "Enter nothing to keep defaults (fsnative fsaverage fsaverage5 MNI152NLin6Asym MNI152NLin2009cAsym T1w func)"
	read OUTPUT_SPACES; export OUTPUT_SPACES

	[ -z $OUTPUT_SPACES ] && export OUTPUT_SPACES="fsnative fsaverage fsaverage5 MNI152NLin6Asym MNI152NLin2009cAsym T1w func"

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"	
	echo "Choose additional arguments you want to provide to fmriprep call; e.g. '--anat-only'"
	read MODIFIER; export MODIFIER
	[ $MODIFIER == "--anat-only" ] && export SUBJS_PER_NODE=16

elif [ $PIPELINE == "aslprep" ]; then
	
	export SUBJS_PER_NODE=4
	export ANALYSIS_LEVEL=subject
	batch_time_default="03:00:00"
	partition_default="std"

elif [ $PIPELINE == "xcpengine" ];then
	
	export SUBJS_PER_NODE=16
	export ANALYSIS_LEVEL=subject
	batch_time_default="05:00:00"
	partition_default="std"

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"	
	echo "Choose from" $(ls $CODE_DIR/pipelines/xcpengine/fc-*.dsn | xargs -n 1 basename)
	read MODIFIER; export MODIFIER

elif [ $PIPELINE == "hippunfold" ];then
	
	export SUBJS_PER_NODE=16
	export ANALYSIS_LEVEL=subject
	batch_time_default="04:00:00"
	partition_default="std"

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"	
	echo "Please enter which T1w shall serve as input to Hippunfold (raw_bids, qsiprep, fmriprep). Default is 'raw_bids'"
	read INPUT_T1_HIPPUNFOLD; export INPUT_T1_HIPPUNFOLD

	[ -z $INPUT_T1_HIPPUNFOLD ] && export INPUT_T1_HIPPUNFOLD="raw_bids"

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"	
	echo "Please enter which surface density you want to compute (0p5mm, 1mm, 2mm). Default is '0p5mm'"
	read HIPPUNFOLD_OUTPUT_DENSITY; export HIPPUNFOLD_OUTPUT_DENSITY

	[ -z $HIPPUNFOLD_OUTPUT_DENSITY ] && export HIPPUNFOLD_OUTPUT_DENSITY="0p5mm"

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"	
	echo "Choose additional arguments you want to provide to hippunfold call; e.g. '--skip_preproc'"
	read MODIFIER; export MODIFIER
	

elif [ $PIPELINE == "freewater" ];then

	export SUBJS_PER_NODE=8
	export ANALYSIS_LEVEL=subject
	batch_time_default="06:00:00"
	partition_default="std"

elif [ $PIPELINE == "tbss" ];then

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"		
	echo "Which TBSS pipeline would you like to run? Choose between 'mni' and 'fixel'"
	read TBSS_PIPELINE; export TBSS_PIPELINE
	
	if [ $TBSS_PIPELINE != "mni" ] && [ $TBSS_PIPELINE != "fixel" ]; then
		echo "$TBSS_PIPELINE TBSS pipeline is not supported."
		exit
	fi

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"	
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
		batch_time_default="04:00:00"
		partition_default="std"
	
	elif [ $TBSS_LEVEL == 4 ]; then

		echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"	
		echo "Please specify list of subjects whose skeletons you want to merge."
		echo "If you want to merge all subjects type 'all', otherwise choose from the following options:"
		
		ls $DATA_DIR/${PIPELINE}_${TBSS_PIPELINE}/code/merge* | cut -d "_" -f 2 | cut -d "." -f 1
		read TBSS_MERGE_LIST; export TBSS_MERGE_LIST

		export SUBJS_PER_NODE=$subj_array_length
		export ANALYSIS_LEVEL=group
		batch_time_default="4:00:00"
		partition_default="std"
	
	fi

elif [ $PIPELINE == "fba" ];then

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"		
	echo "Which FBA_LEVEL do you want to perform? (1/2/3/4/5/6)"
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
	
	elif [ $FBA_LEVEL == 6 ];then

		echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"
		echo "On which level do you want to perform ROI extraction (subject/group)?"
		echo "MIND: Subject level ROI extraction needs to be run first."
		read ROI_LEVEL; export ROI_LEVEL

		if [ $ROI_LEVEL == "subject" ]; then

			export SUBJS_PER_NODE=32
			export ANALYSIS_LEVEL=subject
			batch_time_default="02:00:00"
			partition_default="std"
		
		elif [ $ROI_LEVEL == "group" ]; then
			
			export SUBJS_PER_NODE=$subj_array_length
			export ANALYSIS_LEVEL=group
			batch_time_default="02:00:00"
			partition_default="std"
		
		fi

	elif [ -z $FBA_LEVEL ];then
		
		echo "FBA level needs to be set"
		exit 0

	fi

elif [ $PIPELINE == "connectomics" ];then

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"		
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
	
	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"	
	echo "Which PSMD pipeline would you like to run? (miac/csi)"
	read PSMD_PIPE; export PSMD_PIPE
	export PIPELINE_SUFFIX=_${PSMD_PIPE}

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"	
	echo "On which level you like to run the PSMD pipeline? (subject/group). Subject level needs to be run first."
	read PSMD_LEVEL; export PSMD_LEVEL

	if [ $PSMD_PIPE == miac ]; then

		echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"	
		echo "Which input data do you want to use? (preprocessed/fitted)"
		read MODIFIER; export MODIFIER
	
	fi

	if [ $PSMD_LEVEL == "subject" ]; then
		
		export SUBJS_PER_NODE=8
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
	 	exit 0
	 fi

elif [ $PIPELINE == "obseg" ];then
	
	export SUBJS_PER_NODE=16
	export ANALYSIS_LEVEL=subject
	batch_time_default="03:00:00"
	partition_default="std"

elif [ $PIPELINE == "cat12" ];then
	
	export SUBJS_PER_NODE=24
	export ANALYSIS_LEVEL=subject
	batch_time_default="12:00:00"
	partition_default="std"

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"		
	echo "Which cat pipeline do you want to perform? Leave empty for core or type 'sub2standard'."
	read CAT_PIPE; export CAT_PIPE
	[ -z $CAT_PIPE ] && export PIPELINE_SUFFIX="" || export PIPELINE_SUFFIX=_${CAT_PIPE}

elif [ $PIPELINE == "wmh" ];then
	
	export SUBJS_PER_NODE=16
	export ANALYSIS_LEVEL=subject
	partition_default="std"

	echo "Which ANALYSIS PART do you want to perform? currently available are: 01_prep / 02_segment / 03_combine / 04_postproc_define_subs / 04_postproc / eval / determine_thresh / threshold_finder_01 / threshold_finder_02 "
	read WMH_LEVEL
	export PIPELINE_SUFFIX=_${WMH_LEVEL}

	if [ $WMH_LEVEL == "01_prep" ]; then

		batch_time_default="08:00:00"
		export SUBJS_PER_NODE=32
		export ANALYSIS_LEVEL=subject

	elif [ $WMH_LEVEL == "02_segment" ]; then
	
		echo "Which SEGMENTATION ALGORITHM do you want to use? currently available: antsrnet / bianca / LOCATE / lga / lpa / samseg"
		read ALGORITHM; export ALGORITHM

		if [ $ALGORITHM == "samseg" ]; then

			batch_time_default="03:30:00"
			export SUBJS_PER_NODE=8

			echo "this algorithm does not recommend any bias-correction. Automatically set to NO."
			BIASCORR=n; export BIASCORR
		
		elif [ $ALGORITHM == "lga" ] || [ $ALGORITHM == "lpa" ]; then

			batch_time_default="01:00:00"
			export SUBJS_PER_NODE=8

			echo "this algorithm does not recommend any bias-correction. Automatically set to NO."
			BIASCORR=n; export BIASCORR

		elif [ $ALGORITHM == "antsrnet" ]; then

			batch_time_default="01:00:00"
			echo "do you want to perform bias-correction on the FLAIR image? (y/n)"
			read BIASCORR; export BIASCORR

		elif [ $ALGORITHM == "bianca" ]; then

			echo "because the data are training data, no bias correction happened. Automatically set to NO."
			BIASCORR=n; export BIASCORR

			echo "Do you want to train bianca or test bianca? ( training / validation / testing ) \
			Note: for training, you need manual masks. For testing, you either need a classifier created with TRAINING or train first."
			read BIANCA_LEVEL; export BIANCA_LEVEL

			[ $BIANCA_LEVEL == training ] && export SUBJS_PER_NODE=$subj_array_length
			[ $BIANCA_LEVEL == training ] && export ANALYSIS_LEVEL=group
			[ $BIANCA_LEVEL == training ] && batch_time_default="24:00:00"
			[ $BIANCA_LEVEL == validation ] && export SUBJS_PER_NODE=16
			[ $BIANCA_LEVEL == validation ] && export ANALYSIS_LEVEL=subject
			[ $BIANCA_LEVEL == validation ] && batch_time_default="05:30:00"
			[ $BIANCA_LEVEL == testing ] && export SUBJS_PER_NODE=16
			[ $BIANCA_LEVEL == testing ] && export ANALYSIS_LEVEL=subject
			[ $BIANCA_LEVEL == testing ] && batch_time_default="05:30:00"

		elif [ $ALGORITHM == "LOCATE" ]; then

			batch_time_default="00:30:00"
			echo "because the data are training data, no bias correction happened. Automatically set to NO."
			BIASCORR=n; export BIASCORR

			echo "Which step of LOCATE should be run? (training / validation (segmentation of training set) / testing) \
			Note: for validation and training, you need manual masks. \
			In addition: please run training before you start validation or testing."
			read LOCATE_LEVEL; export LOCATE_LEVEL

			[ $LOCATE_LEVEL == testing ] && export SUBJS_PER_NODE=16
			[ $LOCATE_LEVEL == testing ] && export ANALYSIS_LEVEL=subject
			[ $LOCATE_LEVEL == testing ] && batch_time_default="05:00:00"
			[ $LOCATE_LEVEL == training ] && export SUBJS_PER_NODE=$subj_array_length
			[ $LOCATE_LEVEL == training ] && export ANALYSIS_LEVEL=group
			[ $LOCATE_LEVEL == training ] && batch_time_default="2-00:00:00"
			[ $LOCATE_LEVEL == validation ] && export SUBJS_PER_NODE=$subj_array_length
			[ $LOCATE_LEVEL == validation ] && export ANALYSIS_LEVEL=group
			[ $LOCATE_LEVEL == validation ] && batch_time_default="2-00:00:00"
			

		fi

	elif [ $WMH_LEVEL == "03_combine" ]; then

		batch_time_default="00:02:00"
	
		echo "this script combines the segmented masks of different algorithms."
		echo "which is the first algorithm? currently available: $(ls $DATA_DIR/$PIPELINE/sub-*/ses-$SESSION/anat/*/ -d | xargs -n 1 basename | sort | uniq)"
		read ALGORITHM1; export ALGORITHM1

		echo "which is the second algorithm? please do not name the same algorithm twice. available: $(ls $DATA_DIR/$PIPELINE/sub-*/ses-$SESSION/anat/*/ -d | xargs -n 1 basename | sort | uniq)"
		read ALGORITHM2; export ALGORITHM2
		
		[ $ALGORITHM1 == $ALGORITHM2 ] && echo "$ALGORITHM1 == $ALGORITHM2 ... stupid" && exit 1

	elif [ $WMH_LEVEL == "04_postproc_define_subs" ]; then 

		INTERACTIVE==y
		SUBJS_PER_NODE=100 # DO NOT CHANGE !
		length=($(ls $BIDS_DIR/sub-* -d | xargs -n 1 basename | wc -l))
		number_of_scripts=$(echo "scale=2; $length/$SUBJS_PER_NODE" | bc)
		number_of_scripts_rounded=$(echo $number_of_scripts | awk '{print ($0-int($0)>0)?int($0)+1:int($0)}')
		DERIVATIVE_dir=$DATA_DIR/$PIPELINE/derivatives
		[ ! -d $DERIVATIVE_dir ] && mkdir $DERIVATIVE_dir

		for num in $(seq 1 $number_of_scripts_rounded); do
    		start=$(($num * $SUBJS_PER_NODE))
    		[ $start == 1 ] && echo $(ls $BIDS_DIR/sub-* -d -1 | xargs -n 1 basename | head -n $start ) > $DERIVATIVE_dir/sublist_${num}.csv
    		[ $start != 1 ] && echo $(ls $BIDS_DIR/sub-* -d -1 | xargs -n 1 basename | head -n $start | tail -n $SUBJS_PER_NODE) > $DERIVATIVE_dir/sublist_${num}.csv

		done

		exit 1

	elif [ $WMH_LEVEL == "04_postproc" ]; then 

		export sublist=${subj_array[@]}
		export SUBJS_PER_NODE=100 # DO NOT CHANGE!
		export ANALYSIS_LEVEL=group
		batch_time_default="2-00:00:00"

		[ $subj_array_length -gt $SUBJS_PER_NODE ] && echo "please define a subject list! subject lists are in $PIPELINE/derivatives or can be created with the option: 04_postproc_define_subs"
		[ $subj_array_length -gt $SUBJS_PER_NODE ] && exit 1

		echo "Which algorithm do you want to evaluate?"
		#echo "Choose from: $(ls $DATA_DIR/$PIPELINE/sub-*/ses-$SESSION/anat/*/ -d | xargs -n 1 basename | sort | uniq)"
		read ALGORITHM; export ALGORITHM
		
	elif [ $WMH_LEVEL == "eval" ]; then 

		export SUBJS_PER_NODE=$subj_array_length
		export ANALYSIS_LEVEL=group
		batch_time_default="01:00:00"

		echo "This script evaluates the segmented masks of different algorithms."
		echo "Which algorithm do you want to evaluate? Choose from: $(ls $DATA_DIR/$PIPELINE/sub-*/ses-$SESSION/anat/*/ -d | xargs -n 1 basename | sort | uniq)"
		read ALGORITHM; export ALGORITHM

	elif [ $WMH_LEVEL == "determine_thresh" ]; then 

		echo "which analysis level you want to perform? possible answers: subject / group. Please execute subject before group. Thx!"
		read ANALYSIS_LEVEL; export ANALYSIS_LEVEL

		export SUBJS_PER_NODE=8
		batch_time_default="01:00:00"
		[ $ANALYSIS_LEVEL == "group" ] && export SUBJS_PER_NODE=$subj_array_length

	elif [ $WMH_LEVEL == "threshold_finder_01" ]; then 

		echo "Do you want to threshold masks of a single algorithm (then answer with 'single'), or do you want to threshold combined masks or multiple algorithms (then answer with 'multiple')?"
		read ALGORITHM_COMBI; export ALGORITHM_COMBI

		if [ $ALGORITHM_COMBI == "multiple" ]; then 

			echo "which is the first algorithm?"
			#"currently available: $(ls $DATA_DIR/$PIPELINE/sub-*/ses-$SESSION/anat/*/ -d | xargs -n 1 basename | sort | uniq)"
			read ALGORITHM1; export ALGORITHM1

			echo "which is the second algorithm? please do not name the same algorithm twice." 
			#"available: $(ls $DATA_DIR/$PIPELINE/sub-*/ses-$SESSION/anat/*/ -d | xargs -n 1 basename | sort | uniq)"
			read ALGORITHM2; export ALGORITHM2
		
			[ $ALGORITHM1 == $ALGORITHM2 ] && echo "$ALGORITHM1 == $ALGORITHM2 ... stupid" && exit 1

		elif [ $ALGORITHM_COMBI == "single" ]; then 

			echo "which algorithm do you want to find a threshold for? currently available: antsrnet / antsrnetbias / bianca / lga / lpa / samseg ."
			read ALGORITHM; export ALGORITHM

		fi

		export ANALYSIS_LEVEL=group
		[ $ALGORITHM_COMBI == "single" ] && batch_time_default="01:00:00"
		[ $ALGORITHM_COMBI == "multiple" ] && batch_time_default="02:30:00"
		export SUBJS_PER_NODE=8

	elif [ $WMH_LEVEL == "threshold_finder_02" ]; then 

		echo "Do you want to threshold masks of a single algorithm (then answer with 'single'), or do you want to threshold combined masks or multiple algorithms (then answer with 'multiple')?"
		read ALGORITHM_COMBI; export ALGORITHM_COMBI

		if [ $ALGORITHM_COMBI == "multiple" ]; then 

			echo "which is the first algorithm?"
			#"currently available: $(ls $DATA_DIR/$PIPELINE/sub-*/ses-$SESSION/anat/*/ -d | xargs -n 1 basename | sort | uniq)"
			read ALGORITHM1; export ALGORITHM1

			echo "which is the second algorithm? please do not name the same algorithm twice. "
			#"available: $(ls $DATA_DIR/$PIPELINE/sub-*/ses-$SESSION/anat/*/ -d | xargs -n 1 basename | sort | uniq)"
			read ALGORITHM2; export ALGORITHM2
		
			[ $ALGORITHM1 == $ALGORITHM2 ] && echo "$ALGORITHM1 == $ALGORITHM2 ... stupid" && exit 1

		elif [ $ALGORITHM_COMBI == "single" ]; then 

			echo "which algorithm do you want to find a threshold for? currently available: antsrnet / antsrnetbias / bianca / lga / lpa / samseg ."
			read ALGORITHM; export ALGORITHM

		fi

		export ANALYSIS_LEVEL=group
		batch_time_default="06:00:00"
		export SUBJS_PER_NODE=$subj_array_length

	fi


elif [ $PIPELINE == "lesionanalysis" ];then
	
	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"	
	echo "Which part of the pipeline would you like to run? (1/2)"
	read LA_PART; export LA_PART
	export PIPELINE_SUFFIX=_${LA_PART}

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"	
	echo "Please define the original image space of the lesion mask(s)."
	echo "Currently available: 'T1w'."
	read ORIG_SPACE; export ORIG_SPACE

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"	
	echo "Please define the space in which lesion masks and shells are to be read out."
	echo "Currently available: 'dwi'"
	echo "Note: qsiprep output is expected. Therefore 'dwi' refers to T1w-space and not the original dwi-space!"
	read READOUT_SPACE; export READOUT_SPACE

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"	
	echo "Would you like to flip lesion mask / read out flipped lesion (shells)? (yes/no)"
	read FLIP; export MODIFIER=$FLIP
	
	if [ $LA_PART == "1" ]; then

		echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"	
		echo "Please provide absolute path to directory with subject directories containing the lesion masks."
		echo "Note: the expected naming convention of files is as follows <LESION_DIR>/<sub>/<ses>/<anat/dwi/perf/func>/<sub>_<ses>_<space>_desc-lesion_mask.nii.gz"
		read LESION_DIR; export LESION_DIR

		echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"	
		echo "Please specify which output of anatomical preprocessing shall be used (fmriprep/qsiprep)."
		echo "Note: it is assumed that freesurfer (recon-all) was run through the specified pipeline and therefore T1w-spaces match."
		read ANAT_PREPROC; export ANAT_PREPROC

		export SUBJS_PER_NODE=16
		export ANALYSIS_LEVEL=subject
		batch_time_default="01:00:00"
		partition_default="std"
	
	elif [ $LA_PART == "2" ]; then

		echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"	
		echo "On which level would you like to run Part 2? (subject/group)"
		read ANALYSIS_LEVEL; export ANALYSIS_LEVEL

		if [ $ANALYSIS_LEVEL == "subject" ]; then

			export SUBJS_PER_NODE=16
			export ANALYSIS_LEVEL=subject
			batch_time_default="01:00:00"
			partition_default="std"

		elif [ $ANALYSIS_LEVEL == "group" ]; then

			export SUBJS_PER_NODE=$subj_array_length
			export ANALYSIS_LEVEL=group
			batch_time_default="00:30:00"
			partition_default="std"

		fi
	
	else

	 	echo "Part $LA_PART for $PIPELINE pipeline is not supported."
	 	exit 0

	fi

elif [ $PIPELINE == "statistics" ];then

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"		
	echo "Which method do you want to perform? (cfe/tfce_tbss/nbs)"
	read STAT_METHOD; export STAT_METHOD
	export PIPELINE_SUFFIX=_${STAT_METHOD}

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"		
	echo "Define hypothesis short (-> has to be name of subdirectory in data/statistics)"
	echo $(ls $DATA_DIR/statistics/* -d -1 | xargs -n 1 basename | sort | uniq ) | tr " " "\n"
	read MODIFIER; export MODIFIER

	if [ $STAT_METHOD == cfe ];then
		
		export SUBJS_PER_NODE=$subj_array_length
		export ANALYSIS_LEVEL=group
		batch_time_default="3-00:00:00"
		partition_default="big"

	elif [ $STAT_METHOD == tfce_tbss ];then
	
		export SUBJS_PER_NODE=$subj_array_length
		export ANALYSIS_LEVEL=group
		batch_time_default="1-00:00:00"
		partition_default="big"

	elif [ $STAT_METHOD == nbs ];then
	
		export SUBJS_PER_NODE=$subj_array_length
		export ANALYSIS_LEVEL=group
		batch_time_default="1-00:00:00"
		partition_default="std"

	fi

elif [ $PIPELINE == "pvs_frangi" ] ;then

	echo "Which ANALYSIS PART do you want to perform? currently available are: postproc, summary"
	read ANALYSIS_PART
	export PIPELINE_SUFFIX=_${ANALYSIS_PART}

	if [ $ANALYSIS_PART == postproc ];then

		export ANALYSIS_LEVEL=subject
		export SUBJS_PER_NODE=120
		partition_default="std"
		batch_time_default="01:00:00"

	elif [ $ANALYSIS_PART == summary ];then

		export ANALYSIS_LEVEL=group
		export SUBJS_PER_NODE=$subj_array_length
		partition_default="std"
		batch_time_default="00:10:00"
		export sublist=${subj_array[@]}

	fi

elif [ $PIPELINE == "pvs_rorpo" ] ;then

	export SUBJS_PER_NODE=120
	export ANALYSIS_LEVEL=subject
	partition_default="std"
	batch_time_default="01:00:00"

	echo "Which ANALYSIS PART do you want to perform? currently available are: postproc"
	read ANALYSIS_PART
	export PIPELINE_SUFFIX=_${ANALYSIS_PART}

elif [ $PIPELINE == "registration" ];then

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"		
	echo "Which method do you want to perform? (ants_rigid/ants_affine/ants_syn/ants_apply_transform)"
	read REGISTRATION_METHOD; export REGISTRATION_METHOD

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"		
	echo "Define task directory (-> has to be name of subdirectory in data/registration)"
	echo $(ls $DATA_DIR/registration/* -d -1 | xargs -n 1 basename | sort | uniq ) | tr " " "\n"
	read REGISTRATION_TASK; export REGISTRATION_TASK

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"	
	echo "Please make sure that registration/moving/ and registration/target/ are present in the task directory."
	echo "These should contain moving and target files starting with the subject id (sub-XYZ_...) or"
	echo "a single template image (e.g. an MNI template)."
	echo "We recommend using symlinks instead of the actual files to save disk space."
	echo "Press enter to continue."
	read CHECK

	# echo "Is a template the moving or target image? (n/moving/target)"
	# echo "Given make sure that template is single file in moving/ or target"
	# read TEMPLATE_WARP; export TEMPLATE_WARP

	# echo "Do you want to lesion mask the registration? (y/n)"
	# echo "Please make sure that the lesion_mask/ is present in the task directory containing the lesions to mask during registration."
	# read LESION_MASKING; export LESION_MASKING

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"	
	echo "Is a template the moving or target image? (n/moving/target); Default: n"
	echo "Given that make sure that template is single file in moving/ or target"
	read TEMPLATE_WARP; export TEMPLATE_WARP
	[ -z $TEMPLATE_WARP ] && TEMPLATE_WARP="n"

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"	
	echo "Do you want to mask the registration? (y/n); Default: n"
	echo "Please make sure that the mask/ is present in the task directory defining the regions to consider during registration."
	read MASKING; export MASKING
	[ -z $MASKING ] && MASKING="n"

	if [ $MASKING == y ];then
		echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"	
		echo "Is the mask a lesion mask to exclude from registration? (y/n); Default: y"
		read LESION_MASKING; export LESION_MASKING
		[ -z $LESION_MASKING ] && LESION_MASKING="y"
	fi

	if [ $# != 0 ];then
		subj_array=($@)
    	echo "Processing subject(s) ${subj_array[@]}"
		sleep 1
	else
		subj_array=(${@-$(ls $DATA_DIR/registration/$REGISTRATION_TASK/moving/* -d -1 | xargs -n 1 basename)}) # subjects in data/registration/task/moving
		subj_array_length=${#subj_array[@]}
	fi

	if [ $REGISTRATION_METHOD == ants_rigid ];then
		export SUBJS_PER_NODE=128
		export ANALYSIS_LEVEL=subject
		batch_time_default="01:00:00"
		partition_default="std"

	elif [ $REGISTRATION_METHOD == ants_affine ];then
		export SUBJS_PER_NODE=128
		export ANALYSIS_LEVEL=subject
		batch_time_default="02:00:00"
		partition_default="std"
	
	elif [ $REGISTRATION_METHOD == ants_syn ];then
		export SUBJS_PER_NODE=64
		export ANALYSIS_LEVEL=subject
		batch_time_default="24:00:00"
		partition_default="std"

	elif [ $REGISTRATION_METHOD == ants_apply_transform ];then
		export SUBJS_PER_NODE=8
		export ANALYSIS_LEVEL=subject
		batch_time_default="02:00:00"
		partition_default="std"

		echo "Which interpolation do you want to use? (NearestNeighbor/BSpline/LanczosWindowedSinc)"
		read INTERPOLATION; export INTERPOLATION

	fi

else
	
	echo "Pipeline $PIPELINE not supported"
	exit
fi


if [ $INTERACTIVE != y ]; then

	# Set batch time to allocate and partition
	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"
	echo "How much time do you want to allocate? Default is $(echo $batch_time_default)"
	echo "Leave empty to choose default"
	read batch_time
	[ -z $batch_time ] && batch_time=$batch_time_default

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"
	echo "Which partition do you want to submit to? Default is $(echo $partition_default)"
	echo "Leave empty to choose default"
	read partition
	[ -z $partition ] && partition=$partition_default

	echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"
	echo "Do you want to provide additional flags for sbatch submission? e.g. '--hold' or '--dependency=afterok:job_id' or '--begin=16:00'"
	echo "Leave empty to choose default"
	read optional_slurm_flags

fi

# Define batch script
script_name="02_pipelines_batch.sh"
SCRIPT_PATH=$CODE_DIR/$script_name

# If subject array length < subjects per node -> match subjects per node to array length
[ $subj_array_length -lt $SUBJS_PER_NODE ] && export SUBJS_PER_NODE=$subj_array_length
echo "◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️◼️"	
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
	        --partition $partition $optional_slurm_flags \
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
