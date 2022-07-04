#!/bin/bash


#################################################################
# Helper script for dataset setup and common datalad operations
# Works with absolute paths
# Script assumes to operate from directory superdataset/code
#
# Authors: 
# Marvin Petersen (m-petersen)
# Carola Mayer (carlo-may)
# Felix Naegele (felenae)
#################################################################

source /sw/batch/init.sh
module load parallel
module load aws-cli
module load zip
source /work/fatx405/set_envs/miniconda
source activate datalad

#################################################################
# Startup dialogue
#################################################################

echo "What do you want to do? (finalize_superdataset, add_ses_dcm, import_dcms, convert_containers, subdataset_import, missing_outputs, if_in_s3, templateflow_setup, qa_missings)"
read PIPELINE

#################################################################
# Environment
#################################################################

# Define location of this very script and its name
export SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"  # "$0"
export SCRIPT_NAME="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"
echo $SCRIPT_DIR
echo $SCRIPT_NAME
export PROJ_DIR=$(realpath $SCRIPT_DIR/../)
#export PROJ_DIR=$(realpath $SCRIPT_DIR/../../$PROJ_NAME)
export DATA_DIR=$PROJ_DIR/data
export DCM_DIR=$PROJ_DIR/data/dicoms
export BIDS_DIR=$PROJ_DIR/data/raw_bids
export CODE_DIR=$SCRIPT_DIR
export ENV_DIR=$PROJ_DIR/envs

export DATALAD_LOCATIONS_SOCKETS=$WORK/tmp

#################################################################
# Dataset helper
#################################################################

#[ -d $PROJ_DIR ] && pushd $PROJ_DIR
if [ $PIPELINE == finalize_superdataset ];then
	
	## Setup YODA-compliant dataset structure

	# Create superdataset and enter PROJ_DIR
	[ ! -d $PROJ_DIR ] && mkdir $PROJ_DIR || echo "superdataset $PROJ_DIR already exists"
	#pushd $PROJ_DIR
	[ ! -f $PROJ_DIR/README.md ] && touch $PROJ_DIR/README.md

	# Create code subdataset and insert copy of this script
	
	# Clone code from git
	[ ! -d $PROJ_DIR/code ] && git clone https://github.com/csi-hamburg/CSIframe $PROJ_DIR/code || echo "code/ already exists in superdataset"

	# Create data directory (no datalad dataset)
	[ ! -d $PROJ_DIR/data ] && mkdir $PROJ_DIR/data || echo "data/ already exists in superdataset"

	# Clone envs subdataset from source
	echo "Please provide absolute Path to datalad dataset cloned from https://github.com/csi-hamburg/envs"
	echo "In your superdataset 'envs/' will symlink to this dataset."
	read ENVS_SOURCE

	ln -rs $ENVS_SOURCE $PROJ_DIR/envs

elif [ $PIPELINE == 'convert_containers' ];then

	# Add singularity containers from env to project root
	
	echo "Please provide space-separated list of container image names to you want to convert to sandboxes; e.g. 'fmriprep-20.2.1.sif qsiprep-0.13.0.sif'"
	echo "Available container images are: $(ls $ENV_DIR)."
	echo "If you provide 'all', all of containers of envs/ are added"
	pushd $PROJ_DIR/envs; read -e container_list; popd

	[ "$container_list" == all ] && container_list=$(ls $PROJ_DIR/envs/*.sif | xargs -n1 basename)

	for container in $container_list;do
		echo "Converting $container to sandbox"
		datalad get -d $ENV_DIR $ENV_DIR/$container
		singularity build --sandbox $ENV_DIR/${container%.*} $ENV_DIR/$container
	done

elif [ $PIPELINE == add_ses_dcm ];then
	## Insert session to single session dcm directory
	echo "DICOM import requires existence of a session directory, e.g. 'ses-1'"
	echo "Please provide absolute PATH to directory to DICOMs directory you later want to import"
	read DICOM_PATH
	echo "Assumed path containing subject directories with DICOMs is $DICOM_PATH"
	echo "Assumed structure of this directory is dataset_directory/subject/sequence/DICOMS"
	echo "Final structure will be dataset_directory/subject/session/sequence/DICOMS"
	echo "Before you proceed please make sure that subject directories are the only instances in dataset_directory"
	echo "Which session to input? e.g. 'ses-1'"
	read ses

	for sub in $(ls $DICOM_PATH);do
		mkdir $DICOM_PATH/$sub/$ses/
		mv $DICOM_PATH/$sub/* $DICOM_PATH/$sub/$ses/
	done

elif [ $PIPELINE == import_dcms ];then

	## Import dicoms from dataset directory and convert them to tarballs
	echo "Define path containing subject directories with DICOMs"
	echo "data/dicoms/ subdataset should have been established (add_dcm_subds)"
	echo "Assumed structure of this directory is dataset_directory/subject/session/sequence/DICOMS"
	echo "Before you proceed please make sure that subject directories are the only instances in dataset_directory"
	read INPUT_PATH
	OUTPUT_PATH=$DCM_DIR

	[ ! -d $DCM_DIR ] && mkdir $DCM_DIR && echo "$DCM_DIR has been created" || echo "$DCM_DIR exists"

	echo "Converting subject dirs to tarballs and copying into data/dicoms"
	export zip=y
	
	echo "How much time do you want to allocate? e.g. '01:00:00' for one hour; default: '01:00:00'"
	echo "For instance assume ~1h for 150 subjects with HCHS acquisition"
	read alloc_time; [ -z $alloc_time ] && alloc_time="01:00:00"
	
	echo "Would you like tperform a new import or update an existing one? (new/update); default: 'new'"
	read IMPORT_TYPE; [ -z $IMPORT_TYPE ] && IMPORT_TYPE=new
	export IMPORT_TYPE

	echo "Do you want to perform import interactively or submit import job to a node? (interactive/submission); default: 'interactive'"
	echo "Longer imports should be submitted."	
	read INTERACTIVE; [ -z $INTERACTIVE ] && INTERACTIVE=interactive
	export INTERACTIVE

	export parallel="parallel --ungroup --delay 0.2 -j32" 

	# Define subject list

	subs=($(ls $INPUT_PATH))
	echo INPUT $INPUT_PATH OUTPUT $OUTPUT_PATH zip $zip
	echo $subs

	# Define import loop to parallelize across
	import_loop() {

		seqs=$(find $1 -mindepth 2 -maxdepth 3 -type d -a ! -name '*'"ses-"'*' -exec basename {} \;     | sort | uniq)
		INPUT_PATH=$1
		OUTPUT_PATH=$2
		zip=$3
		sub=$4
		IMPORT_TYPE=$5

		echo "Importing subject $sub"
		echo "Sequences to import: $seqs"
		OUTPUT_DIR=$OUTPUT_PATH/$sub
		INPUT_DIR=$INPUT_PATH/$sub
		for session in $(ls $INPUT_DIR/ses-* -d | xargs -n 1 basename);do
			if [ $zip == y ];then
				pushd $INPUT_DIR
				
				if [ $IMPORT_TYPE == "new" ]; then
					mkdir -p $OUTPUT_DIR
					tar -czvf $OUTPUT_DIR/${session}.tar.gz $session
				
				elif [ $IMPORT_TYPE == "update" ]; then
					gunzip $OUTPUT_DIR/${session}.tar.gz
					chmod 770 $OUTPUT_DIR/${session}.tar
					tar -f $OUTPUT_DIR/${session}.tar -v -u $session
					gzip $OUTPUT_DIR/${session}.tar
					echo "$sub $session $(date +%d%m%Y)" >> $CODE_DIR/log/dicom_update_$(date +%d%m%Y).log
				fi

			elif [ $zip == n ];then
				for seq in $seqs;do

				 	mkdir $OUTPUT_DIR 
					cp -ruvf $INPUT_DIR/$session/$seq $OUTPUT_DIR/$session/$seq
				done
			fi
		done

	}
	export -f import_loop


	if [ $INTERACTIVE == interactive ]; then 

		CMD="$parallel import_loop $INPUT_PATH $OUTPUT_PATH $zip {} $IMPORT_TYPE ::: ${subs[@]}"
		srun -p std -t $alloc_time $CMD

	elif [ $INTERACTIVE == submission ]; then

		cat <<- EOF > $CODE_DIR/import_dcms.sh
		#!/usr/bin/env bash
		source /sw/batch/init.sh
		module load parallel
		$parallel import_loop $INPUT_PATH $OUTPUT_PATH $zip {} $IMPORT_TYPE ::: ${subs[@]}
		EOF

		sbatch -p std -t $alloc_time --output $CODE_DIR/log/"%A-dicom_import-$(date +%d%m%Y).out" \
                --error $CODE_DIR/log/"%A-dicom_import-$(date +%d%m%Y).err" $CODE_DIR/import_dcms.sh

		rm $CODE_DIR/import_dcms.sh

	else
		echo "$INTERACTIVE not available mode";
	fi
 

elif [ $PIPELINE == subdataset_import ];then

	## Import files from dataset directory and convert them to tarballs
	echo "Define absolute path to directory to become a subdataset. For instance the path to a directory with bidsified raw data."
	read INPUT_PATH

	echo "Define target subdataset e.g. 'raw_bids'"
	echo "If not already available, it will be created in $PROJ_DIR/data/."
	read subdataset
	OUTPUT_PATH=$PROJ_DIR/data/$subdataset
	export $OUTPUT_PATH

	## Add subdataset in data/
	[ ! -d $OUTPUT_PATH ] && mkdir -p $OUTPUT_PATH
	echo "Dataset README" >> $OUTPUT_PATH/README.md
	[ -f $ENV_DIR/standard/dataset_description.json ] && cp $ENV_DIR/standard/dataset_description.json $OUTPUT_PATH 

	echo "Do you want to perform import interactively or submit import job to a node? (interactive/submission); default: 'interactive'"
	echo "Longer imports should be submitted."	
	read INTERACTIVE; [ -z $INTERACTIVE ] && INTERACTIVE=interactive

	echo "How much time do you want to allocate? e.g. '01:00:00' for one hour; default: '01:00:00'"
	echo "For instance assume ~1h for 150 subjects with HCHS acquisition"
	read alloc_time; [ -z $alloc_time ] && alloc_time="01:00:00"

	items=($(ls $INPUT_PATH))

	export parallel="parallel --ungroup --delay 0.2 -j32" 

	if [ $INTERACTIVE == interactive ]; then 

		CMD="$parallel cp -ruvf $INPUT_PATH/{} $OUTPUT_PATH ::: ${items[@]}"
		echo $CMD
		srun -p std -t $alloc_time $CMD

	elif [ $INTERACTIVE == submission ]; then

		cat <<- EOF > $CODE_DIR/import.sh
		#!/usr/bin/env bash
		source /sw/batch/init.sh
		module load parallel
		$parallel cp -ruvf $INPUT_PATH/{} $OUTPUT_PATH ::: ${items[@]}
		EOF

		sbatch -p std -t $alloc_time --output $CODE_DIR/log/"%A-import_$subdataset-$(date +%d%m%Y).out" \
                --error $CODE_DIR/log/"%A-import_$subdataset-$(date +%d%m%Y).err" $CODE_DIR/import.sh

		rm $CODE_DIR/import.sh

	else
		echo "$INTERACTIVE not available (only interactive/submission)";
	fi

elif [ $PIPELINE == missing_outputs ];then

	# Define the subdataset concerned
	echo "Please provide space-separated list of subdatasets in data/ to look for missing outputs; e.g. 'fmriprep mriqc'"
	echo "Choose from: $(ls $PROJ_DIR/data)"
	read subds

	echo "Are you looking for a subject directory or a file/directory within a subject directory? (subdir/in_subdir)"
	read file_or_subdir

	default_out=$CODE_DIR/log/missing_${subds}_$(date +%d%m%y).txt
	echo "Define output file for subject list"
	echo "If nothing is provided, output file will be $default_out"
	read out_file

	echo "Please provide subds in data/ to read subject names from; recommended: raw_bids/"
	echo "Here, subjects should be complete so they can be used to find potentially missing directories in subds to check"
	read template_dir

	[ -z $out_file ] && out_file=$default_out

	if [ $file_or_subdir == subdir ];then



		for ds in ${subds[@]};do
			pushd $DATA_DIR/$subds
			diff -q $DATA_DIR/$template_dir . | grep "Only in ${DATA_DIR}/${template_dir}: sub-" | cut -d' ' -f 4 > $out_file 
			popd
		done

		echo "Finished writing to $out_file"

	elif [ $file_or_subdir == in_subdir ];then
		echo "Please provide search term pattern you want to match; e.g. 'dwi.nii.gz' will match everything with that string."
		read search

		for ds in ${subds[@]};do
		pushd $DATA_DIR/$ds
			arr_search=($(find $DATA_DIR/$ds -type f | grep $search | grep sub | cut -d'/' -f 8))
			arr_template=($(ls $DATA_DIR/$template_dir/sub-*/ -d | rev | cut -d '/' -f 2 | rev))
			echo "#####################################"
			echo ${arr_search[@]} ${arr_template[@]} | tr ' ' '\n' | sort | uniq -u
			echo ${arr_search[@]} ${arr_template[@]} | tr ' ' '\n' | sort | uniq -u > $out_file
			#find . -mindepth 1 -maxdepth 1 -type d '!' -exec test -e "{}/${search}" ';' -print | grep sub | cut -d"/" -f 2 > $out_file
		popd
		done
	fi

elif [ $PIPELINE == if_in_s3 ];then

	echo "Which S3 bucket do you want to look at?"
	echo "Choose from: $(aws --endpoint-url https://s3-uhh.lzs.uni-hamburg.de s3 ls | awk '{print $3}')"
	read bucket

	# Define the subdataset concerned
	echo "Please provide subdataset in data/ to work in; e.g. 'fmriprep mriqc'"
	echo "Choose from: $(ls $PROJ_DIR/data)"
	read subds

	echo "Please provide search term you want to match; e.g. 'dwi.nii.gz'"
	read identifier

	echo "What do you want to do with local clone if you found files remotely? (list/count/remove)"
	read operation

	pushd $DATA_DIR
	if [ $operation == list ];then
		aws s3 --endpoint-url https://s3-uhh.lzs.uni-hamburg.de ls s3://$bucket/$subds/ --recursive | grep $identifier | awk '{print $4}' | xargs -n 4 echo
	elif [ $operation == count ];then
		aws s3 --endpoint-url https://s3-uhh.lzs.uni-hamburg.de ls s3://$bucket/$subds/ --recursive | grep $identifier | awk '{print $4}' | wc -l
	elif [ $operation == remove ];then
		aws s3 --endpoint-url https://s3-uhh.lzs.uni-hamburg.de ls s3://$bucket/$subds/ --recursive | grep $identifier | awk '{print $4}' | xargs -n 1 rm
	else echo $operation not provided. Please choose from list/count/remove
	fi
	popd

elif [ $PIPELINE == add_lzs_s3_remote ];then

	# Initialize S3 special remote in superds and create LZS S3 bucket as sibling
	echo "Please provide a repository name"
	read repo

	echo "Supply S3 bucket name to create or save to."
	echo "Please adhere to format uke-csi-<individual name>."
	echo "Naming the bucket according to the repository name is recommended. Like uke-csi-<repository name>."
	echo "Add '-test' if you don't want the LZS admins to establish a bucket mirror; e.g. uke-csi-dataset-test."
	read bucket

	echo "Enter AWS access key"
	read aws_access
	export AWS_ACCESS_KEY_ID=$aws_access
	echo $AWS_ACCESS_KEY_ID
	
	echo "Enter AWS secret access key"
	read aws_secret
	export AWS_SECRET_ACCESS_KEY=$aws_secret
	echo $AWS_SECRET_ACCESS_KEY

	remote_name=$RANDOM

	git annex initremote $remote_name type=S3 chunk=1GB datacenter=s3-uhh encryption=none bucket=$bucket public=no autoenable=true host=s3-uhh.lzs.uni-hamburg.de

	git annex enableremote $remote_name publicurl=https://${bucket}.s3-uhh.lzs.uni-hamburg.de

	datalad create-sibling-github -d $PROJ_DIR --publish-depends s3 --github-organization csi-hamburg --existing replace --private -s github $repo

elif [ $PIPELINE == templateflow_setup ];then

	export TEMPLATEFLOW_HOME=$BIDS_DIR/code/templateflow
	[ ! -d $TEMPLATEFLOW_HOME ] && mkdir -p $TEMPLATEFLOW_HOME
	python -c "from templateflow.api import get; get(['MNI152NLin2009cAsym', 'MNI152NLin6Asym', 'OASIS30ANTs'])"


elif [ $PIPELINE == qa_missings ]; then

	echo "For which session do you want to check the raw_bids output? please answer with single number."
	read SESSION; export SESSION

	export DERIVATIVES_dir=$BIDS_DIR/derivatives
	[ ! -d $DERIVATIVES_dir ] && mkdir -p $DERIVATIVES_dir

	# set up the output file
	export OUTPUT_FILE=$DERIVATIVES_dir/qa-raw_bids.csv
	echo "subjectID SESSION missing_flair missing_t1 missing_t2 missing_dwi missing_func missing_asl missing_m0 missing_aslprep missing_cat missing_conn_struc missing_conn_func missing_fba missing_fmriprep_struc missing_fmriprep_func missing_freesurfer missing_freewater missing_mriqcstruc missing_mriqcfunc missing_obseg missing_psmd missing_qsiprep missing_qsirecon missing_tbss missing_wmh missing_xcpengine" > $OUTPUT_FILE


	for sub in $(cat $BIDS_DIR/sourcedata/participants.tsv); do

		# raw_bids output
		FLAIR=$BIDS_DIR/sub-${sub}/ses-${SESSION}/anat/sub-${sub}_ses-${SESSION}_FLAIR.nii.gz
		T1=$BIDS_DIR/sub-${sub}/ses-${SESSION}/anat/sub-${sub}_ses-${SESSION}_T1w.nii.gz
		T2=$BIDS_DIR/sub-${sub}/ses-${SESSION}/anat/sub-${sub}_ses-${SESSION}_T2w.nii.gz
		DWI=$BIDS_DIR/sub-${sub}/ses-${SESSION}/dwi/sub-${sub}_ses-${SESSION}_acq-AP_dwi.nii.gz
		FUNC=$BIDS_DIR/sub-${sub}/ses-${SESSION}/func/sub-${sub}_ses-${SESSION}_task-rest_bold.nii.gz
		ASL=$BIDS_DIR/sub-${sub}/ses-${SESSION}/perf/sub-${sub}_ses-${SESSION}_asl.nii.gz
		M0=$BIDS_DIR/sub-${sub}/ses-${SESSION}/perf/sub-${sub}_ses-${SESSION}_m0scan.nii.gz

		# pipeline_specific output
		ASLPREP=$DATA_DIR/aslprep/sub-${sub}/ses-${SESSION}/perf/sub-${sub}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-basil_cbf.nii.gz
		CAT12=$DATA_DIR/cat12/sub-${sub}/surf/rh.thickness.T1
		CONNECTOMICS_STRUC=$DATA_DIR/connectomics/sub-${sub}/ses-${SESSION}/dwi/sub-${sub}_ses-${SESSION}_*_sc_sift_connectomics.csv
		CONNECTOMICS_FUNC=$DATA_DIR/connectomics/sub-${sub}/ses-${SESSION}/func/sub-${sub}_ses-${SESSION}_*_connectomics.csv
		FBA=$DATA_DIR/fba/derivatives/fdc_smooth/sub-${sub}.mif
		FMRIPREP_STRUC=$DATA_DIR/fmriprep/sub-${sub}/ses-${SESSION}/anat/sub-${sub}_ses-${SESSION}_desc-preproc_T1w.nii.gz
		FMRIPREP_FUNC=$DATA_DIR/fmriprep/sub-${sub}/ses-${SESSION}/func/sub-${sub}_ses-${SESSION}_task-rest_desc-preproc_bold.nii.gz
		FREESURFER=$DATA_DIR/freesurfer/sub-${sub}/stats/aseg.stats
		FREEWATER=$DATA_DIR/freewater/sub-${sub}/ses-1/dwi/sub-${sub}_ses-${SESSION}_space-MNI_FW.nii.gz
		MRIQC_STRUC=$DATA_DIR/mriqc/sub-${sub}/ses-${SESSION}/anat/sub-${sub}_ses-${SESSION}_T1w.json
		MRIQC_FUNC=$DATA_DIR/mriqc/sub-${sub}/ses-${SESSION}/func/sub-${sub}_ses-${SESSION}_task-rest_bold.json
		OBSEG=$DATA_DIR/obseg/sub-${sub}/stats/segmentation_stats.csv
		PSMD=$DATA_DIR/psmd*/sub-${sub}/ses-${SESSION}/dwi/tbss/stats/MD_skeletonised_masked_R.nii.gz
		QSIPREP=$DATA_DIR/qsiprep/sub-${sub}/ses-${SESSION}/dwi/sub-${sub}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_dwi.nii.gz
		QSIRECON=$DATA_DIR/qsirecon/sub-${sub}/ses-${SESSION}/dwi/sub-${sub}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_space-T1w_dhollanderconnectome.mat
		TBSS=$DATA_DIR/tbss_*/sub-${sub}/ses-${SESSION}/dwi/sub-${sub}_ses-${SESSION}_space-MNI_desc-eroded_desc-DTINoNeg_FA.nii.gz
		WMH=$DATA_DIR/wmh/sub-${sub}/ses-${SESSION}/anat/sub-${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmhperi_desc-*_mask.nii.gz
		XCPENGINE=$DATA_DIR/xcpengine/sub-${sub}/fcon/schaefer400x7/sub-${sub}_schaefer400x7_network.txt

		# editing
		CONNECTOMICS_STRUC=$(echo $CONNECTOMICS_STRUC | awk '{print $1}')
		CONNECTOMICS_FUNC=$(echo $CONNECTOMICS_FUNC | awk '{print $1}')
		TBSS=$(echo $TBSS | awk '{print $1}')
		WMH=$(echo $WMH | awk '{print $1}')

		# check status
		[ -f $FLAIR ] && missing_flair=0 || missing_flair=1 
		[ -f $T1 ] && missing_t1=0 || missing_t1=1 
		[ -f $T2 ] && missing_t2=0 || missing_t2=1 
		[ -f $DWI ] && missing_dwi=0 || missing_dwi=1 
		[ -f $FUNC ] && missing_func=0 || missing_func=1 
		[ -f $ASL ] && missing_asl=0 || missing_asl=1 
		[ -f $M0 ] && missing_m0=0 || missing_m0=1 
		[ -f $ASLPREP ] && missing_aslprep=0 || missing_aslprep=1 
		[ -f $CAT12 ] && missing_cat=0 || missing_cat=1 
		[ -f $CONNECTOMICS_STRUC ] && missing_conn_struc=0 || missing_conn_struc=1
		[ -f $CONNECTOMICS_FUNC ] && missing_conn_func=0 || missing_conn_func=1 
		[ -f $FBA ] && missing_fba=0 || missing_fba=1 
		[ -f $FMRIPREP_STRUC ] && missing_fmriprep_struc=0 || missing_fmriprep_struc=1 
		[ -f $FMRIPREP_FUNC ] && missing_fmriprep_func=0 || missing_fmriprep_func=1 
		[ -f $FREESURFER ] && missing_freesurfer=0 || missing_freesurfer=1 
		[ -f $FREEWATER ] && missing_freewater=0 || missing_freewater=1 
		[ -f $MRIQC_STRUC ] && missing_mriqcstruc=0 || missing_mriqcstruc=1 
		[ -f $MRIQC_FUNC ] && missing_mriqcfunc=0 || missing_mriqcfunc=1 
		[ -f $OBSEG ] && missing_obseg=0 || missing_obseg=1 
		[ -f $PSMD ] && missing_psmd=0 || missing_psmd=1 
		[ -f $QSIPREP ] && missing_qsiprep=0 || missing_qsiprep=1 
		[ -f $QSIRECON ] && missing_qsirecon=0 || missing_qsirecon=1 
		[ -f $TBSS ] && missing_tbss=0 || missing_tbss=1 
		[ -f $WMH ] && missing_wmh=0 || missing_wmh=1 
		[ -f $XCPENGINE ] && missing_xcpengine=0 || missing_xcpengine=1 

		# write in output file
		echo "sub-${sub} ses-${SESSION} $missing_flair $missing_t1 $missing_t2 $missing_dwi $missing_func $missing_asl $missing_m0 $missing_aslprep $missing_cat $missing_conn_struc $missing_conn_func $missing_fba $missing_fmriprep_struc $missing_fmriprep_func $missing_freesurfer $missing_freewater $missing_mriqcstruc $missing_mriqcfunc $missing_obseg $missing_psmd $missing_qsiprep $missing_qsirecon $missing_tbss $missing_wmh $missing_xcpengine" >> $OUTPUT_FILE

	done

	# example command for checking missing subjects on MASTER_NAS in the dicoms directory:
	# for i in `cat /media/sda/PhD/hummel_marvin/projects/CSI_HCHS/data/raw_bids/derivatives/qa-raw_bids.csv`; do missing_flair=$(echo $i | awk '{print $3}'); sub=$(echo $i | awk '{print $1}' | tail -c 9); if [ $missing_flair == 1 ]; then echo $sub $missing_flair; fi; if [ $missing_flair == 1 ]; then ls /media/sda/MASTER_NAS/HCHS/DICOMS_HCHS/DICOMS_HCHS/ds_10000/out/$sub/ses-1/* -d ; fi; done


else
	echo "$PIPELINE is not supported"
fi

#popd
