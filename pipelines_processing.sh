#!/usr/bin/bash

#SBATCH --export=PIPELINE,SESSION,SLURM_CPUS_PER_TASK

####################
# Application of preconfigured neuroimaging pipelines for image processing
# datalad version 0.14.4
# qsiprep version 0.13.0
# smriprep version 0.8.0RC2
# mriqc version 0.16.1
# fmriprep version 20.2.0
# xcpengine version 1.2.3
####################

set -oux
source /sw/batch/init.sh

echo '###################################'
echo Started processing of $1
echo '###################################'

# Change default permissions for new files
umask u=rwx g=rwx

# define environment
SCRIPT_DIR=${SLURM_SUBMIT_DIR-$(dirname "$0")}
export PROJ_DIR=$(realpath $SCRIPT_DIR/..) # project root; should be 1 level above code
export CODE_DIR=$PROJ_DIR/code
export PIPELINE_DIR=$PROJ_DIR/code/pipelines/$PIPELINE
export ENV_DIR=$PROJ_DIR/envs
export DATA_DIR=$PROJ_DIR/data
export DCM_DIR=$PROJ_DIR/data/dicoms
export BIDS_DIR=$PROJ_DIR/data/raw_bids

export SLURM_CPUS_PER_TASK=${SLURM_CPUS_PER_TASK-10}
export SCRATCH_DIR=/scratch/${USER}.${SLURM_JOBID}/$1 
[ ! -d $SCRATCH_DIR ] && mkdir $SCRATCH_DIR
export SINGULARITY_CACHEDIR=$WORK/tmp/singularity_cache  #$SCRATCH_DIR 
export SINGULARITY_TMPDIR=$WORK/tmp/singularity_tmp  #$SCRATCH_DIR
export DSLOCKFILE=$WORK/tmp/pipeline.lock
export DATALAD_LOCATIONS_SOCKETS=$SCRATCH_DIR/sockets

echo hostname: $(hostname)
echo $(singularity --version)
echo TMPDIR: $TMPDIR
echo RRZ_LOCAL_TMPDIR: $RRZ_LOCAL_TMPDIR
echo SINGULARITY_CACHEDIR: $SINGULARITY_CACHEDIR
echo SINGULARITY_TMPDIR: $SINGULARITY_TMPDIR
echo DSLOCKFILE: $DSLOCKFILE
mkdir -p $DATALAD_LOCATIONS_SOCKETS && echo DATALAD_LOCATIONS_SOCKETS: $DATALAD_LOCATIONS_SOCKETS

# setup scratch dir
cd $SCRATCH_DIR
CLONE=$SCRATCH_DIR/clone
CLONE_DATA_DIR=$CLONE/data
CLONE_BIDS_DIR=$CLONE/data/raw_bids
CLONE_DCM_DIR=$CLONE/data/dicoms
CLONE_CODE_DIR=$CLONE/code/
CLONE_ENV_DIR=$CLONE/envs/
CLONE_TMP_DIR=$SCRATCH_DIR/tmp/ # $CLONE_DATA_DIR/.git/tmp/wdir

# Create temporary clone working directory
mkdir -p $CLONE_TMP_DIR 

# clone the analysis dataset. flock makes sure that this does not interfere
# with another job finishing and pushing results back at the same time
# remove clone beforehand for seamless interactive testing
[ -d $CLONE ] && datalad update -r --merge any -d $CLONE
flock $DSLOCKFILE datalad clone $PROJ_DIR $CLONE #&& { chmod 777 -R $CLONE; rm -rf $CLONE; }

#flock $DSLOCKFILE datalad install --reckless -r --source $PROJ_DIR $CLONE

# All in-container-paths relative to $CLONE
cd $CLONE

# Get necessary subdatasets and files
[ -f $CLONE_ENV_DIR/freesurfer_license.txt ] || datalad get $CLONE_ENV_DIR/freesurfer_license.txt
[ -d $CLONE_BIDS_DIR ] || datalad get -n $CLONE_BIDS_DIR
[ -f $CLONE_BIDS_DIR/dataset_description.json ] || datalad get $CLONE_BIDS_DIR/dataset_description.json
[ -f $CLONE_BIDS_DIR/participants.tsv ] || datalad get $CLONE_BIDS_DIR/participants.tsv
#datalad get data/raw_bids/.bidsignore

# Make git-annex disregard the clones - they are meant to be thrown away
git submodule foreach --recursive git annex dead here

# Prevent conflicts on master branch by setting up individual branch
git checkout -b "job-$SLURM_JOBID-$1" 


# Tell templateflow where to read/write
export TEMPLATEFLOW_HOME=$CODE_DIR/templateflow
export SINGULARITYENV_TEMPLATEFLOW_HOME=$TEMPLATEFLOW_HOME

# Remove other participants than $1 in bids (pybids gets angry when it sees dangling symlinks)
find $CLONE_BIDS_DIR -maxdepth 1 -name 'sub-*' -type d -a ! -name '*'"$1"'*' -exec rm -rv {} +
echo ls BIDS root: $(ls $CLONE_BIDS_DIR)

# Run pipeline; paths relative to project root and push back the results.

export PIPE_ID="job-$SLURM_JOBID-$PIPELINE-$1-$(date +%d%m%Y)"

source $PIPELINE_DIR/${PIPELINE}.sh $1

datalad remove --nocheck $CLONE

#if [ $PIPELINE == "bidsify" ];then
#
#	# Get symlink tree of sourcedata
#	datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/dicoms
#	datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/dicoms/${1}
#	datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/raw_bids/sub-${1}
#	
#	# Checkout new branch in bids subject directory dataset
#	#git -C data/raw_bids/ checkout -b "${PIPE_ID}"
#	git -C data/raw_bids/sub-${1} checkout -b "${PIPE_ID}"
#
#	( rm -rf data/raw_bids/sub-${1}/ses-* )
#
#	# Run heudiconv for dcm2nii and bidsification of its outputs
#	# heudiconv_heuristic.py is dataset specific
#	# FIXME: amend -d PATH according to your dicom directory structure 
#	# NOTE: Run again after cleaning dataset state
#	CMD="
#	    singularity run --cleanenv --userns\
#	    --home $PWD \
#	    -B $CODE_DIR:/code \
#	    -B $CLONE_BIDS_DIR:/bids \
#	    -B $CLONE_DCM_DIR:/dcm \
#	    -B $CLONE_TMP_DIR:/tmp \
#	    $ENV_DIR/heudiconv-0.9.0.sif\
#	    -d /dcm/{{subject}}/ses-1/*\
#	    --subjects $1 \
#	    --bids notop \
#	    -f /code/heudiconv_heuristic.py\
#	    -c dcm2niix \
#	    --overwrite\
#	    --minmeta \
#	    --grouping accession_number \
#	    -o /bids"
#
#	datalad run -m "${PIPE_ID} heudiconv" \
#	   --explicit \
#	   --output $CLONE_BIDS_DIR/sub-${1} -o $CLONE_BIDS_DIR/participants.tsv -o $CLONE_BIDS_DIR/participants.json -o $CLONE_BIDS_DIR/dataset_description.json \
#	   --input $CLONE_DCM_DIR/$1 \
#	   $CMD
#       
#	# Deface T1	
#	T1=$CLONE_BIDS_DIR/sub-${1}/ses-1/anat/sub-${1}_ses-1_T1w.nii.gz
#	datalad containers-run \
#	   -m "${PIPE_ID} pydeface T1w" \
#	   --explicit \
#	   --output "$CLONE_BIDS_DIR/sub-${1}/*/*/*T1w.nii.gz" \
#	   --input "$CLONE_BIDS_DIR/sub-${1}/*/*/*T1w.nii.gz" \
#	   --container-name pydeface \
#            pydeface $T1 \
#	    --outfile $T1 \
#	    --force
#
#	# Deface FLAIR
#	FLAIR=$CLONE_BIDS_DIR/sub-${1}/ses-1/anat/sub-${1}_ses-1_FLAIR.nii.gz
#	datalad containers-run \
#	   -m "${PIPE_ID} pydeface FLAIR" \
#	   --explicit \
#	   --output "$CLONE_BIDS_DIR/sub-${1}/*/*/*FLAIR.nii.gz" \
#	   --input "$CLONE_BIDS_DIR/sub-${1}/*/*/*FLAIR.nii.gz" \
#	   --container-name pydeface \
#            pydeface $FLAIR \
#	    --outfile $FLAIR \
#	    --force
#
#	# Remove problematic metadata from json sidecars
#	CMD="python $CODE_DIR/handle_metadata.py $1"
#	datalad run -m '${PIPE_ID} handle metadata' \
#	   --explicit \
#	   --output "$CLONE_BIDS_DIR/sub-${1}/*/*/*.json" \
#	   --input "$CLONE_BIDS_DIR/sub-${1}/*/*/*.json" \
#	   $CMD
#
#	rm -rf $CLONE_BIDS_DIR/.heudiconv
#
#	# Push results from clone to original dataset
#	#flock $DSLOCKFILE datalad push -d $CLONE_BIDS_DIR/ --to origin
#	flock $DSLOCKFILE datalad push -d $CLONE_BIDS_DIR/sub-${1} --to origin
#
#elif [ $PIPELINE == "qsiprep" ];then
#	
#	# Set specific environment for pipeline
#	export MRTRIX_TMPFILE_DIR=$SCRATCH_DIR
#
#	# Get input and output dataset directory trees
#	datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_BIDS_DIR/$1
#	datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/qsiprep 
#	datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/qsiprep/$1 
#	datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/qsirecon
#	datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/qsirecon/$1
#
#	# Remove other participants than $1 in qsiprep output (otherwise qsirecon confuses subjects)
#	find data/qsiprep -maxdepth 1 -name 'sub-*' -type d -a ! -name '*'"$1"'*' -exec rm -rv {} +
#	echo ls qsiprep directory: $(ls data/qsiprep)
#
#	# Checkout unique branches (names derived from jobIDs) of result subdatasets
#	# to enable pushing the results without interference from other jobs.
#	# In a setup with no subdatasets, "-C <subds-name>" would be stripped,
#	# and a new branch would be checked out in the superdataset instead.
#	git -C $CLONE_DATA_DIR/qsiprep/$1 checkout -b "$PIPE_ID"
#	git -C $CLONE_DATA_DIR/qsiprep checkout -b "$PIPE_ID"
#	git -C $CLONE_DATA_DIR/qsirecon/$1 checkout -b "$PIPE_ID"
#	git -C $CLONE_DATA_DIR/qsirecon checkout -b "$PIPE_ID"
#
#
#	# Remove job outputs in dataset clone to prevent issues when rerunning
#	# $1/* matches all content in subject subdataset but dotfiles (.git, .datalad, .gitattributes)
#	(cd $CLONE_DATA_DIR/qsiprep && rm -rf logs $1/* "${1}.html" dwiqc.json dataset_description.json .bidsignore)
#	(cd $CLONE_DATA_DIR/qsirecon && rm -rf logs $1/* "${1}.html" dwiqc.json dataset_description.json .bidsignore)
#
#	cd $CLONE
#
#	# Run pipeline with datalad
#	datalad containers-run \
#	   -m "$PIPE_ID" \
#	   --explicit \
#	   --input "$CLONE_BIDS_DIR/$1" \
#	   --output $CLONE_DATA_DIR/qsiprep -o $CLONE_DATA_DIR/qsiprep/$1 -o $CLONE_DATA_DIR/qsirecon -o $CLONE_DATA_DIR/qsirecon/$1 \
#	   --container-name qsiprep \
#	    data/raw_bids data participant \
#	    -w .git/tmp/wdir \
#	    --participant-label $1 \
#	    --recon_input data/qsiprep/$1 \
#	    --recon_spec mrtrix_multishell_msmt \
#	    --nthreads $SLURM_CPUS_PER_TASK \
#	    --skip-bids-validation \
#	    --use-syn-sdc \
#	    --denoise-method dwidenoise \
#	    --unringing-method mrdegibbs \
#	    --skull-strip-template OASIS \
#	    --stop-on-first-crash \
#	    --output-resolution 1.3 \
#	    --stop-on-first-crash \
#	    --fs-license-file envs/freesurfer_license.txt
#	
#	echo $(ls -lah $CLONE_DATA_DIR/qsiprep)
#	echo $(ls -lah $CLONE_DATA_DIR/qsiprep/$1)
#	echo $(ls -lah $CLONE_DATA_DIR/qsirecon)
#	echo $(ls -lah $CLONE_DATA_DIR/qsirecon/$1)
#
#	# Push results from clone to original dataset
#	flock $DSLOCKFILE datalad push -d $CLONE_DATA_DIR/qsiprep --to origin
#	flock $DSLOCKFILE datalad push -d $CLONE_DATA_DIR/qsiprep/$1 --to origin
#	flock $DSLOCKFILE datalad push -d $CLONE_DATA_DIR/qsirecon --to origin
#	flock $DSLOCKFILE datalad push -d $CLONE_DATA_DIR/qsirecon/$1 --to origin
#
#elif [ $PIPELINE == 'smriprep' ];then
#
#	# Get input and output dataset directory trees
#	datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_BIDS_DIR/$1
#	datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/freesurfer
#	#datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/freesurfer/$1
#	datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/smriprep
#	datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/smriprep/$1
#
#	# Checkout unique branches (names derived from jobIDs) of result subdatasets
#	# to enable pushing the results without interference from other jobs.
#	# In a setup with no subdatasets, "-C <subds-name>" would be stripped,
#	# and a new branch would be checked out in the superdataset instead.
#	git -C $CLONE_DATA_DIR/freesurfer checkout -b "job-$SLURM_JOBID-freesurfer-$1"
#	#git -C $CLONE_DATA_DIR/freesurfer/$1 checkout -b "job-$SLURM_JOBID-freesurfer-$1"
#	git -C $CLONE_DATA_DIR/smriprep checkout -b "job-$SLURM_JOBID-smriprep-$1"
#	git -C $CLONE_DATA_DIR/smriprep/$1 checkout -b "job-$SLURM_JOBID-smriprep-$1"
#
#	# Remove job outputs in dataset clone to prevent issues when rerunning
#	# Freesurfer requires removal of output subject directory before processing, hence no subdataset structure only directories in data/freesurfer
#	(cd $CLONE_DATA_DIR/freesurfer && rm -rf fsaverage $1 .bidsignore)
#	(cd $CLONE_DATA_DIR/smriprep && rm -rf logs $1/* "${1}.html" dataset_description.json desc-aparcaseg_dseg.tsv desc-aseg_dseg.tsv .bidsignore)
#
#	datalad containers-run \
#	   -m "$PIPE_ID" \
#	   --explicit \
#	   --output $CLONE_DATA_DIR/freesurfer -o $CLONE_DATA_DIR/smriprep -o $CLONE_DATA_DIR/smriprep/$1 \
#	   --input "$CLONE_BIDS_DIR/$1"\
#	   --container-name smriprep \
#	    data/raw_bids data participant \
#	    -w .git/tmp/wdir \
#	    --participant-label $1 \
#	    --output-spaces fsnative fsaverage MNI152NLin6Asym T1w T2w \
#	    --nthreads $SLURM_CPUS_PER_TASK \
#	    --fs-subjects-dir data/freesurfer \
#	    --stop-on-first-crash \
#	    --fs-license-file envs/freesurfer_license.txt
#
#	echo $(ls -lah $CLONE_DATA_DIR/smriprep)
#	echo $(ls -lah $CLONE_DATA_DIR/smriprep/$1)
#	echo $(ls -lah $CLONE_DATA_DIR/freesurfer)
#	echo $(ls -lah $CLONE_DATA_DIR/freesurfer/$1)
#
#	#flock $DSLOCKFILE datalad push -d $CLONE_DATA_DIR/freesurfer/$1 --to origin
#	flock $DSLOCKFILE datalad push -d $CLONE_DATA_DIR/freesurfer --to origin
#	flock $DSLOCKFILE datalad push -d $CLONE_DATA_DIR/smriprep/$1 --to origin
#	flock $DSLOCKFILE datalad push -d $CLONE_DATA_DIR/smriprep --to origin
#
#
#elif [ $PIPELINE == 'mriqc' ];then
#
#	# Get input and output dataset directory trees
#	datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_BIDS_DIR/$1
#	datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/mriqc
#	datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/mriqc/$1
#
#	# Checkout unique branches (names derived from jobIDs) of result subdatasets
#	# to enable pushing the results without interference from other jobs.
#	# In a setup with no subdatasets, "-C <subds-name>" would be stripped,
#	# and a new branch would be checked out in the superdataset instead.
#	git -C $CLONE_DATA_DIR/mriqc checkout -b "$PIPE_ID"
#	git -C $CLONE_DATA_DIR/mriqc/$1 checkout -b "$PIPE_ID"
#
#	# Remove job outputs in dataset clone to prevent issues when rerunning
#	# $1/* matches all content in subject subdataset but dotfiles (.git, .datalad, .gitattributes)
#	(cd $CLONE_DATA_DIR/mriqc && rm -rf $1/* ${1}*.html dataset_description.json .bidsignore)
#
#	cd $CLONE
#
#	datalad containers-run \
#	   -m "$PIPE_ID" \
#	   --explicit \
#	   --input "$CLONE_BIDS_DIR/$1" --input "$CLONE_BIDS_DIR/dataset_description.json" \
#	   --output $CLONE_DATA_DIR/mriqc -o $CLONE_DATA_DIR/mriqc/$1 \
#	   --container-name mriqc \
#	    data/raw_bids data/mriqc participant \
#	    -w .git/tmp/wdir \
#	    --participant-label $1 \
#	    --modalities T1w T2w bold \
#	    --no-sub \
#	    --ica \
#	    --float32 \
#	    --nprocs $SLURM_CPUS_PER_TASK 
#
#	echo $(ls -lah $CLONE_DATA_DIR/mriqc)
#	echo $(ls -lah $CLONE_DATA_DIR/mriqc/$1)
#
#	datalad save -m "$PIPE_ID output" $CLONE_DATA_DIR/mriqc/
#	datalad save -m "$PIPE_ID output" $CLONE_DATA_DIR/mriqc/$1/
#
#	flock $DSLOCKFILE datalad push -d $CLONE_DATA_DIR/mriqc --to origin
#	flock $DSLOCKFILE datalad push -d $CLONE_DATA_DIR/mriqc/$1 --to origin
#
#elif [ $PIPELINE == 'fmriprep' ];then
#
#	# Get input and output dataset directory trees
#	datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_BIDS_DIR/${1}
#	datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/smriprep
#	datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/smriprep/$1
#	datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/freesurfer
#	datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/freesurfer/$1
#	datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/fmriprep
#	datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/fmriprep/$1
#
#	# Checkout unique branches (names derived from jobIDs) of result subdatasets
#	# to enable pushing the results without interference from other jobs.
#	# In a setup with no subdatasets, "-C <subds-name>" would be stripped,
#	# and a new branch would be checked out in the superdataset instead.
#	git -C $CLONE_DATA_DIR/fmriprep checkout -b "$PIPE_ID"
#	git -C $CLONE_DATA_DIR/fmriprep/$1 checkout -b "$PIPE_ID"
#	git -C $CLONE_DATA_DIR/freesurfer checkout -b "$PIPE_ID"
#
#	# Remove job outputs in dataset clone to prevent issues when rerunning
#	# $1/* matches all content in subject subdataset but dotfiles (.git, .datalad, .gitattributes)
#	(cd $CLONE_DATA_DIR/fmriprep && rm -rf dataset_description.json desc-aseg_dseg.tsv desc-aparcaseg_dseg.tsv logs $1/*)
#	cd $CLONE
#	
#	datalad containers-run \
#	   -m "$PIPE_ID" \
#	   --explicit \
#	   --input "$CLONE_BIDS_DIR/$1" -i "$CLONE_DATA_DIR/smriprep/$1" -i "$CLONE_DATA_DIR/freesurfer/$1" \
#	   --output $CLONE_DATA_DIR/fmriprep -o $CLONE_DATA_DIR/fmriprep/$1 \
#	   --container-name fmriprep \
#	    data/raw_bids data participant \
#	    -w /tmp \
#	    --participant-label $1 \
#	    --output-spaces fsnative fsaverage MNI152NLin6Asym \
#	    --nthreads $SLURM_CPUS_PER_TASK \
#	    --stop-on-first-crash \
#	    --ignore t2w \
#	    --skip-bids-validation \
#	    --fs-subjects-dir data/freesurfer \
#	    --use-aroma \
#	    --random-seed 12345 \
#	    --use-syn-sdc \
#	    --fs-license-file envs/freesurfer_license.txt
#
#	echo $(ls -lah $CLONE_DATA_DIR/fmriprep)
#	echo $(ls -lah $CLONE_DATA_DIR/fmriprep/$1)
#
#	flock $DSLOCKFILE datalad push -d $CLONE_DATA_DIR/fmriprep --to origin
#	flock $DSLOCKFILE datalad push -d $CLONE_DATA_DIR/fmriprep/$1 --to origin
#	flock $DSLOCKFILE datalad push -d $CLONE_DATA_DIR/freesurfer --to origin
# 
#elif [ $PIPELINE == 'xcpengine' ];then
#
#	echo $PIPELINE
#
#elif [ $PIPELINE == 'wmhprep' ];then
#	
#	# Get input and output dataset directory trees
#	datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/$1
#	datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/smriprep
#	datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/smriprep/$1
#	datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/wmhprep
#	datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/wmhprep/$1
#
#	# Checkout unique branches (names derived from jobIDs) of result subdatasets
#	# to enable pushing the results without interference from other jobs.
#	# In a setup with no subdatasets, "-C <subds-name>" would be stripped,
#	# and a new branch would be checked out in the superdataset instead.
#	git -C $CLONE_DATA_DIR/wmhprep/$1 checkout -b "$PIPE_ID"
#
#	# Remove job outputs in dataset clone to prevent issues when rerunning
#	(cd $CLONE_DATA_DIR/wmhprep && rm -rf $1/*)
#
#	cd $CLONE
#
#	#source $WORK/set_envs/mrtrix3
#	#source $WORK/set_envs/fsl
#
#	#python -c "from templateflow.api import get; get(['OASIS30ANTs'])"
#
#	#T1_OASIS=$TEMPLATEFLOW_HOME/tpl-OASIS30ANTs/tpl-OASIS30ANTs_res-01_T1w-nii.gz
#	#PRIOR_OASIS=$TEMPLATEFLOW_HOME/tpl-OASIS30ANTs/tpl-OASIS30ANTs_res-01_desc-BrainCerebellumExtraction_mask.nii.gz
#
#	# Set pipeline variables as relative paths since datalad doesn't like absolute paths in eph. clone
#	OUT_DIR=data/wmhprep/$1/ses-1/anat/
#	[ ! -d $OUT_DIR ] && mkdir -p $OUT_DIR
#
#	# Define inputs
#	T1=data/smriprep/$1/ses-1/anat/${1}_ses-1_desc-preproc_T1w.nii.gz
#	T1_MASK=data/smriprep/$1/ses-1/anat/${1}_ses-1_desc-brain_mask.nii.gz
#	FLAIR=data/raw_bids/$1/ses-1/anat/${1}_ses-1_FLAIR.nii.gz
#
#	# Define outputs
#	T1_IN_FLAIR=$OUT_DIR/${1}_ses-1_space-FLAIR_desc-preproc_T1w.nii.gz
#	T1_TO_FLAIR_WARP=$OUT_DIR/${1}_ses-1_from-T1w_to-FLAIR_mode-image_xfm.txt
#	T1_MASK_IN_FLAIR=$OUT_DIR/${1}_ses-1_space-FLAIR_desc-brainmask_T1w.nii.gz
#	T1_BRAIN_IN_FLAIR=$OUT_DIR/${1}_ses-1_space-FLAIR_desc-brainex_T1w.nii.gz
#	T1_MASK_IN_FLAIR_THR=$OUT_DIR/${1}_ses-1_space-FLAIR_desc-brainmaskthresh_T1w.nii.gz
#	FLAIR_BRAIN=$OUT_DIR/${1}_ses-1_desc-brainex_FLAIR.nii.gz
#	MNI_T1=/opt/fsl-6.0.3/data/standard/MNI152_T1_1mm_brain.nii.gz
#	FLAIR_TO_MNI_WARP=$OUT_DIR/${1}_ses-1_from-FLAIR_to-MNI_mode-image_xfm.txt
#	T1_IN_MNI=$OUT_DIR/${1}_ses-1_space-MNI_desc-preproc_T1w.nii.gz
#
#
#	# Define commands
#	CMD_T1_TO_FLAIR="flirt -in $T1 -ref $FLAIR -omat $T1_TO_FLAIR_WARP -out $T1_IN_FLAIR -v"
#	CMD_T1_MASK_TO_FLAIR="flirt -in $T1_MASK -ref $FLAIR -init $T1_TO_FLAIR_WARP -out $T1_MASK_IN_FLAIR -v -applyxfm"
#	CMD_MASK_THRESH="mrthreshold $T1_MASK_IN_FLAIR -abs 0.95 $T1_MASK_IN_FLAIR_THR --force"
#	CMD_MASKING_T1_IN_FLAIR="mrcalc $T1_MASK_IN_FLAIR_THR $T1_IN_FLAIR -mult $T1_BRAIN_IN_FLAIR --force"
#	CMD_MASKING_FLAIR="mrcalc $T1_MASK_IN_FLAIR_THR $FLAIR -mult $FLAIR_BRAIN --force"
#	CMD_T1_FLAIR_TO_MNI="flirt -in $T1_BRAIN_IN_FLAIR -ref $MNI_T1 -omat $FLAIR_TO_MNI_WARP -out $T1_IN_MNI -v"
#
#	# Execute with datalad
#	datalad containers-run	\
#	-m "Warp preprocessed T1w + mask from smriprep output to FLAIR space; $1 $SLURM_JOBID" \
#	--explicit \
#	--input $T1 -i $FLAIR -i $T1_MASK \
#	--output $T1_IN_FLAIR -o $T1_TO_FLAIR_WARP -o $T1_MASK_IN_FLAIR  \
#	--container-name fsl \
#	"$CMD_T1_TO_FLAIR ; $CMD_T1_MASK_TO_FLAIR"
#
#	datalad containers-run	\
#	-m "Threshold T1_mask_in_FLAIR, Mask T1_in_FLAIR, Mask FLAIR;  $1 $SLURM_JOBID" \
#	--explicit \
#	--input $T1_MASK_IN_FLAIR -i $T1_IN_FLAIR -i $FLAIR \
#	--output $T1_MASK_IN_FLAIR_THR -o $T1_BRAIN_IN_FLAIR -o $FLAIR_BRAIN  \
#	--container-name mrtrix \
#	"$CMD_MASK_THRESH ; $CMD_MASKING_T1_IN_FLAIR ; $CMD_MASKING_FLAIR"
#
#	datalad containers-run	\
#	-m "T1_brain_in_FLAIR to MNI;  $1 $SLURM_JOBID" \
#	--explicit \
#	--input $T1_BRAIN_IN_FLAIR \
#	--output $FLAIR_TO_MNI_WARP -o $T1_IN_MNI  \
#	--container-name fsl \
#	"$CMD_T1_FLAIR_TO_MNI"
#
#
#	flock $DSLOCKFILE datalad push -d $CLONE_DATA_DIR/wmhprep/$1 --to origin
#
#
#fi

#################################################################
# After jobs have finished cd into result subdatasets of original dataset
#
# Pipeline results are for now located in git branches
# list branches with "git branch -l"
#
# Merge branches into master with 
# $ git merge -m "Merge results from job" $(git branch -l | grep 'job-' | tr -d ' ')
#
# Delete merged branches with
# $ git branch --merged | grep -i -v -E "git-annex|master|dev"| xargs git branch -d
#
# TODO Consider automation
#################################################################

exit 0
