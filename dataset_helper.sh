#!/bin/bash


#################################################################
# Helper script for dataset setup and common datalad operations
# Works with absolute paths
# Script assumes to operate from directory container superdataset/s
#################################################################

source /sw/batch/init.sh
module load parallel
module load aws-cli
source /work/fatx405/set_envs/miniconda
source activate datalad

#################################################################
# Startup dialogue
#################################################################

# Read dataset name
echo "Script is run from $(realpath .); superdataset is assumed to be/become subdirectory"
echo "Enter name of dataset concerned / to create; e.g. CSI_HCHS"
read PROJ_NAME

echo "What do you want to do? (setup_superdataset, add_data_subds, import_raw_bids, convert_containers, add_ses_dcm, import_dcms, missing_outputs, create_participants_tsv, add_lzs_s3_remote, export_from_datalad)"
read PIPELINE

#################################################################
# Environment
#################################################################

# Define location of this very script and its name
export SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"  # "$0"
export SCRIPT_NAME="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"
echo $SCRIPT_DIR
echo $SCRIPT_NAME
export PROJ_DIR=$(realpath $SCRIPT_DIR/../../$PROJ_NAME)
export DATA_DIR=$PROJ_DIR/data
export DCM_DIR=$PROJ_DIR/data/dicoms
export BIDS_DIR=$PROJ_DIR/data/raw_bids
export CODE_DIR=$PROJ_DIR/code
export ENV_DIR=$PROJ_DIR/envs

export DATALAD_LOCATIONS_SOCKETS=$WORK/tmp

#################################################################
# Functions
#################################################################

# Define function for subdataset creation 

export parallel="parallel --ungroup --delay 0.2 -j32" 

create_data_subds () {
	subds=$1
	mkdir $DATA_DIR/$subds
	echo "Dataset README" >> $DATA_DIR/$subds/README.md
	[ -f $BIDS_DIR/dataset_description.json ] && cp $BIDS_DIR/dataset_description.json $DATA_DIR/$subds 
	}

import() {
	INPUT_PATH=$1
	OUTPUT_PATH=$2
	zip=$3
	time=$4

	# Define subject list
	subs=$(ls $INPUT_PATH)
	echo INPUT $INPUT_PATH OUTPUT $OUTPUT_PATH zip $zip sub $sub
	echo $subs

	# Define import loop to parallelize across
	import_loop() {

		seqs=$(find $1 -mindepth 2 -maxdepth 3 -type d -a ! -name '*'"ses-"'*' -exec basename {} \;     | sort | uniq)
		INPUT_PATH=$1
		OUTPUT_PATH=$2
		zip=$3
		sub=$4

		echo "Importing subject $sub"
		echo "Sequences to import: $seqs"
		OUTPUT_DIR=$OUTPUT_PATH/$sub
		INPUT_DIR=$INPUT_PATH/$sub
		for session in $(ls $INPUT_DIR/ses-* -d | xargs -n 1 basename);do
			if [ $zip == y ];then #&& [ ! -f $OUTPUT_DIR/${session}.tar.gz ]
				mkdir -p $OUTPUT_DIR
				pushd $INPUT_DIR
				tar -czvf $OUTPUT_DIR/${session}.tar.gz $session
				popd
			elif [ $zip == n ];then
				for seq in $seqs;do

				 	mkdir $OUTPUT_DIR 
					cp -ruvf $INPUT_DIR/$session/$seq $OUTPUT_DIR/$session/$seq
				done
			fi
		done

	}
	export -f import_loop
	CMD="$parallel import_loop $INPUT_PATH $OUTPUT_PATH $zip {} ::: $subs"
	echo $CMD

	# Calculate with ~1h for 150 subjects
	srun -p std -t $time $CMD
 }

#################################################################
# Dataset helper
#################################################################

[ -d $PROJ_DIR ] && pushd $PROJ_DIR
if [ $PIPELINE == setup_superdataset ];then
	
	## Setup YODA-compliant dataset structure

	# Create superdataset and enter PROJ_DIR
	mkdir $PROJ_DIR
	pushd $PROJ_DIR
	touch README.md
	touch CHANGELOG.md

	# Create code subdataset and insert copy of this script
	
	# Clone code from git
	git clone https://github.com/csi-hamburg/hummel_processing $PROJ_DIR/code

	# Create data directory (no datalad dataset)
	mkdir data

	# Clone envs subdataset from source
	echo "Where to clone envs/ from?"
	echo "Please provide absolute Path to datalad dataset or github URL; e.g. https://github.com/csi-hamburg/csi_envs"
	read envs_source

	datalad clone $envs_source $ENV_DIR

elif [ $PIPELINE == add_data_subds ];then

	# Add derivative subdataset/s in data/

	echo "Please provide space-separated list of subdataset names; e.g. 'smriprep freesurfer qsiprep bianca'"
	read subdataset_array
	
	for subds in ${subdataset_array[@]};do
		create_data_subds $subds
	done

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
	echo "Assumed path containing subject directories with DICOMs is $PROJ_DIR"
	echo "Assumed structure of this directory is dataset_directory/subject/sequence/DICOMS"
	echo "Final structure will be dataset_directory/subject/session/sequence/DICOMS"
	echo "Before you proceed please make sure that subject directories are the only instances in dataset_directory"
	echo "Which session to input? e.g. 'ses-1'"
	read ses

	for sub in $(ls $PROJ_DIR);do
		mkdir $PROJ_DIR/$sub/$ses/
		mv $PROJ_DIR/$sub/* $PROJ_DIR/$sub/$ses/
	done

elif [ $PIPELINE == import_dcms ];then

	## Import dicoms from dataset directory and convert them to tarballs
	echo "Define path containing subject directories with DICOMs"
	echo "data/dicoms/ subdataset should have been established (add_dcm_subds)"
	echo "Assumed structure of this directory is dataset_directory/subject/(session)/sequence/DICOMS"
	echo "Before you proceed please make sure that subject directories are the only instances in dataset_directory"
	read INPUT_PATH
	OUTPUT_PATH=$DCM_DIR

	echo "How much time do you want to allocate? e.g. '01:00:00' for one hour"
	read time

	echo "Converting subject dirs to tarballs and copying into data/dicoms"
	export zip=y
	
	import $INPUT_PATH $OUTPUT_PATH $zip $time

elif [ $PIPELINE == import_raw_bids ];then

	## Add subdataset for bidsified raw data in data/

	create_data_subds "raw_bids"

	echo "Do you want to import bidsified subjects in raw_bids?"
	read yn

	if [ $yn == y ];then
		echo "Please provide absolute path to BIDS root to import from. Please ensure BIDS adherence)" && \
		read INPUT_PATH
		echo "Please provide session; e.g. 'ses-1'"
		read session
		srun -t 01:00:00 import $INPUT_PATH $BIDS_DIR n $ses
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
		echo "Please provide search term you are looking for; e.g. 'dwi.nii.gz'"
		#echo "Please provide file or directory name you are looking for (search depth of 1, i.e. sub-xyz/?)"
		read search

		for ds in ${subds[@]};do
		pushd $DATA_DIR/$ds
			arr_search=($(find $DATA_DIR/$ds -type f | grep $search | grep sub | cut -d'/' -f 8))
			arr_template=($(ls $DATA_DIR/$template_dir/sub-* -d | cut -d'/' -f 8))
			echo "#####################################"
			echo ${arr_search[@]} ${arr_template[@]} | tr ' ' '\n' | sort | uniq -u
			echo ${arr_search[@]} ${arr_template[@]} | tr ' ' '\n' | sort | uniq -u > $out_file
			#find . -mindepth 1 -maxdepth 1 -type d '!' -exec test -e "{}/${search}" ';' -print | grep sub | cut -d"/" -f 2 > $out_file
		popd
		done
	fi

elif [ $PIPELINE == create_participants_tsv ];then

	# If heudiconv is run with "--bids notop" raw_bids lacks participants.tsv
	# Add participants.tsv after completing heudiconv application
	for subds in $(ls $DATA_DIR);do
		datalad unlock $DATA_DIR/$subds/participants.tsv
		echo participant_id > $DATA_DIR/$subds/participants.tsv
		for sub in $(ls $BIDS_DIR/sub-* -d);do
			echo $(basename $sub) >> $DATA_DIR/$subds/participants.tsv
		done
		datalad save -m "Add participants.tsv" -d^. $DATA_DIR/$subds
	done

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

elif [ $PIPELINE == export_from_datalad ];then


	# Define the subdataset concerned
	echo "Please provide space-separated list of subdatasets in data/ to copy to; e.g. 'fmriprep mriqc'"
	echo "Choose from: $(ls $PROJ_DIR/data)"
	read subds

	echo "Please provide source dataset"
	read source_ds

	for ds in ${subds[@]};do
		#for sub in $(ls $PROJ_DIR/../$source_ds/data/raw_bids/sub-* -d | xargs -n1 basename );do
		#	TARGET_DIR=$PROJ_DIR/data/$ds/$sub
		#	mkdir -p $TARGET_DIR
		#	cp -ruvfL $PROJ_DIR/../$source_ds/data/$ds/$sub/* $TARGET_DIR
		#	pushd $TARGET_DIR; git annex uninit; rm -rf .git .datalad .gitattributes; chmod 770 -R .; popd
		#done
		for_each -nthreads 7 -debug $(ls $PROJ_DIR/../$source_ds/data/raw_bids/sub-* -d | xargs -n1 basename ) : \
			mkdir -p $PROJ_DIR/data/$ds/NAME ";" \
			cp -ruvfL $PROJ_DIR/../$source_ds/data/$ds/NAME/* $PROJ_DIR/data/$ds/NAME ";" \
			pushd $PROJ_DIR/data/$ds/NAME ";" \
			git annex uninit ";" \
			rm -rf .git .datalad .gitattributes ";" \
			chmod 770 -R . ";"\
			popd
	done

else
	echo "$PIPELINE is not supported"
fi

popd
