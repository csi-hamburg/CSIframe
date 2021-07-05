#!/usr/bin/bash

#SBATCH --export=PIPELINE

####################
# Application of preconfigured neuroimaging pipelines for image processing
# datalad version 0.14.4
# qsiprep version 0.13.0
# smriprep version 0.8.0RC2
# mriqc version 0.16.1
# fmriprep version 20.2.0
# xcpengine version 1.2.3
####################

set -eoux
source /sw/batch/init.sh

echo '###################################'
echo Started processing of $1
echo '###################################'

# define environment
SCRIPT_DIR=${SLURM_SUBMIT_DIR-$(dirname "$0")}
source $SCRIPT_DIR/.projectrc

export SCRATCH_DIR=/scratch/fatx405.${SLURM_JOBID}/$1 
[ ! -d $SCRATCH_DIR ] && mkdir $SCRATCH_DIR
export SINGULARITY_CACHEDIR=$WORK/tmp/singularity  #$SCRATCH_DIR 
export SINGULARITY_TMPDIR=$WORK/tmp/singularity  #$SCRATCH_DIR
export DSLOCKFILE=$SCRATCH_DIR/${PIPELINE}.lock
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
CLONE_DCM_DIR=$CLONE/sourcedata
CLONE_DERIV_DIR=$CLONE/derivatives
CLONE_ENV_DIR=$CLONE/envs/
CLONE_OUT_DIR=$CLONE_DERIV_DIR/$PIPELINE/
CLONE_TMP_DIR=$SCRATCH_DIR/tmp/ # $CLONE_DERIV_DIR/.git/tmp/wdir

# Create temporary clone working directory
mkdir -p $CLONE_TMP_DIR 

# clone the analysis dataset. flock makes sure that this does not interfere
# with another job finishing and pushing results back at the same time
# remove clone beforehand for seamless interactive testing
[ -d $CLONE ] && { chmod 777 -R $CLONE; rm -rf $CLONE; }
flock $DSLOCKFILE datalad clone $PROJ_DIR $CLONE
cd $CLONE

# Get necessary subdatasets and files
datalad get envs/freesurfer_license.txt
datalad get dataset_description.json

echo $(ls $CLONE)
echo $(ls derivatives)

# Make git-annex disregard the clones - they are meant to be thrown away
git submodule foreach --recursive git annex dead here

# Prevent conflicts on master branch by setting up individual branch
git checkout -b "job-$SLURM_JOBID-$1" 


# Tell templateflow where to read/write
export TEMPLATEFLOW_HOME=$CODE_DIR/templateflow
export SINGULARITYENV_TEMPLATEFLOW_HOME=$TEMPLATEFLOW_HOME

# Remove other participants than $1 in clone (pybids gets angry when it sees dangling symlinks)
find . -name 'sub-*' -maxdepth 1 -type d -a ! -name '*'"$1"'*' -exec rm -rv {} +
echo ls BIDS root: $(ls .)

# Run pipeline; paths relative to project root and push back the results.

export PIPE_ID="job-$SLURM_JOBID-$PIPELINE-$1"

if [ $PIPELINE == "bidsify" ];then

	# Get symlink tree of sourcedata
	datalad get -n -r -J $SLURM_CPUS_PER_TASK sourcedata
	datalad get -n -r -J $SLURM_CPUS_PER_TASK sub-${1}
	
	# Checkout new branch in bids subject directory dataset
	git -C $CLONE/sub-${1} checkout -b "${PIPE_ID}"

	( rm -rf $CLONE/sub-${1}/ses-* )

	cd $CLONE

	# Run heudiconv for dcm2nii and bidsification of its outputs
	CMD="
	    singularity run --cleanenv --userns\
	    -B $CODE_DIR:/code \
	    -B $CLONE:/bids \
	    -B $CLONE_DCM_DIR:/dcm \
	    -B $CLONE_TMP_DIR:/tmp \
	    $ENV_DIR/heudiconv-0.9.0.sif\
	    -d /dcm/{{subject}}/ses-1/*\
	    -s $1 \
	    --bids \
	    -f /code/heudiconv_ewgenia.py\
	    -c dcm2niix \
	    --overwrite\
	    --minmeta \
	    --grouping accession_number\
	    -o /bids"

	datalad run -m "${PIPE_ID} heudiconv" \
	   --explicit \
	   --output $CLONE/sub-${1} -o $CLONE/participants.tsv -o $CLONE/dataset_description.json \
	   --input "$CLONE/sourcedata/$1/" -i "$CLONE/sub-${1}" \
	   $CMD
       
	# Deface T1	
	T1=/bids/sub-${1}/ses-1/anat/sub-${1}_ses-1_T1w.nii.gz
	datalad containers-run \
	   -m "${PIPE_ID} pydeface T1w" \
	   --explicit \
	   --output "$CLONE/sub-${1}/*/*/*T1w.nii.gz" \
	   --input "$CLONE/sub-${1}/*/*/*T1w.nii.gz" \
	   --container-name pydeface \
            pydeface $T1 \
	    --outfile $T1 \
	    --force

	# Deface FLAIR
	FLAIR=/bids/sub-${1}/ses-1/anat/sub-${1}_ses-1_FLAIR.nii.gz
	datalad containers-run \
	   -m "${PIPE_ID} pydeface FLAIR" \
	   --explicit \
	   --output "$CLONE/sub-${1}/*/*/*FLAIR.nii.gz" \
	   --input "$CLONE/sub-${1}/*/*/*FLAIR.nii.gz" \
	   --container-name pydeface \
            pydeface $FLAIR \
	    --outfile $FLAIR \
	    --force

	# Remove problematic metadata from json sidecars
	CMD="python $CODE_DIR/handle_metadata.py $1"
	datalad run -m '${PIPE_ID} handle metadata' \
	   --explicit \
	   --output "$CLONE/sub-${1}/*/*/*.json" \
	   --input "$CLONE/sub-${1}/*/*/*.json" \
	   $CMD
	
	# Push results from clone to original dataset
	flock $DSLOCKFILE datalad push -d $CLONE/sub-${1} --to origin

elif [ $PIPELINE == "qsiprep" ];then

	# Set specific environment for pipeline
	export MRTRIX_TMPFILE_DIR=$SCRATCH_DIR

	# Get result dataset directory trees
	datalad get -n -r -J $SLURM_CPUS_PER_TASK ${1}
	datalad get -n -r -R1 -J $SLURM_CPUS_PER_TASK derivatives
	datalad get -n -r -J $SLURM_CPUS_PER_TASK $CLONE_DERIV_DIR/qsiprep 
	datalad get -n -r -J $SLURM_CPUS_PER_TASK $CLONE_DERIV_DIR/qsirecon

	# Checkout unique branches (names derived from jobIDs) of result subdatasets
	# to enable pushing the results without interference from other jobs.
	# In a setup with no subdatasets, "-C <subds-name>" would be stripped,
	# and a new branch would be checked out in the superdataset instead.
	git -C $CLONE_DERIV_DIR/qsiprep checkout -b "job-$SLURM_JOBID-qsiprep-$1"
	git -C $CLONE_DERIV_DIR/qsirecon checkout -b "job-$SLURM_JOBID-qsirecon-$1"

	# Remove job outputs in dataset clone to prevent issues when rerunning
	(cd $CLONE_DERIV_DIR/qsiprep && rm -rf logs "$1" "${1}.html" dwiqc.json dataset_description.json)
	(cd $CLONE_DERIV_DIR/qsirecon && rm -rf logs "$1" "${1}.html" dwiqc.json dataset_description.json)
	cd $CLONE

	# Run pipeline with datalad
	datalad containers-run \
	   -m "$PIPE_ID" \
	   --explicit \
	   --output $CLONE/derivatives/qsiprep/qsiprep -o $CLONE/derivatives/qsiprep/qsirecon \
	   --input "$CLONE/$1" \
	   --container-name qsiprep \
	    . derivatives participant \
	    -w .git/tmp/wdir \
	    --participant-label $1 \
	    --recon_input derivatives/qsiprep \
	    --recon_spec mrtrix_singleshell_ss3t \
	    --nthreads $SLURM_CPUS_PER_TASK \
	    --skip-bids-validation \
	    --use-syn-sdc \
	    --stop-on-first-crash \
	    --output-resolution 1.3 \
	    --low-mem \
	    --fs-license-file envs/freesurfer_license.txt
	
	# Push results from clone to original dataset
	flock $DSLOCKFILE datalad push -d $CLONE_DERIV_DIR/qsiprep --to origin
	flock $DSLOCKFILE datalad push -d $CLONE_DERIV_DIR/qsirecon --to origin

elif [ $PIPELINE == 'smriprep' ];then

	datalad get -n -r -J $SLURM_CPUS_PER_TASK ${1}
	datalad get -n -r -R1 -J $SLURM_CPUS_PER_TASK derivatives
	datalad get -n -r -J $SLURM_CPUS_PER_TASK $CLONE_DERIV_DIR/freesurfer
	datalad get -n -r -J $SLURM_CPUS_PER_TASK $CLONE_DERIV_DIR/smriprep

	git -C $CLONE_DERIV_DIR/freesurfer checkout -b "job-$SLURM_JOBID-freesurfer-$1"
	git -C $CLONE_DERIV_DIR/smriprep checkout -b "job-$SLURM_JOBID-smriprep-$1"
	(cd $CLONE_DERIV_DIR/freesurfer && rm -rf fsaverage "${1}")
	(cd $CLONE_DERIV_DIR/smriprep && rm -rf logs "$1" "${1}.html" dataset_description.json desc-aparcaseg_dseg.tsv desc-aseg_dseg.tsv)
	
	cd $CLONE

	datalad containers-run \
	   -m "$PIPE_ID" \
	   --explicit \
	   --output $CLONE_DERIV_DIR/freesurfer -o $CLONE_DERIV_DIR/smriprep \
	   --input "$CLONE/$1" \
	   --container-name smriprep \
	    . derivatives participant \
	    -w .git/tmp/wdir \
	    --participant-label $1 \
	    --output-spaces fsnative fsaverage MNI152NLin6Asym T1w T2w \
	    --nthreads $SLURM_CPUS_PER_TASK \
	    --stop-on-first-crash \
	    --fs-license-file envs/freesurfer_license.txt

	flock $DSLOCKFILE datalad push -d $CLONE_DERIV_DIR/freesurfer --to origin
	flock $DSLOCKFILE datalad push -d $CLONE_DERIV_DIR/smriprep --to origin

elif [ $PIPELINE == 'mriqc' ];then

	datalad get -n -r -J $SLURM_CPUS_PER_TASK ${1}
	datalad get -n -r -R1 -J $SLURM_CPUS_PER_TASK derivatives
	datalad get -n -r -J $SLURM_CPUS_PER_TASK $CLONE_DERIV_DIR/mriqc

	git -C $CLONE_DERIV_DIR/mriqc checkout -b "$PIPE_ID"

	(cd $CLONE_DERIV_DIR/mriqc && rm -rf "${1}" ${1}*.html dataset_description.json .bidsignore)

	cd $CLONE

	datalad containers-run \
	   -m "$PIPE_ID" \
	   --explicit \
	   --output $CLONE_DERIV_DIR/mriqc \
	   --input "$CLONE/$1" --input "$CLONE/dataset_description.json" \
	   --container-name mriqc \
	    . derivatives/mriqc participant \
	    -w .git/tmp/wdir \
	    --participant-label $1 \
	    --modalities T1w T2w bold \
	    --no-sub \
	    --ica \
	    --float32 \
	    --nprocs $SLURM_CPUS_PER_TASK \
	    --work-dir /tmp

	flock $DSLOCKFILE datalad push -d $CLONE_DERIV_DIR/mriqc --to origin

elif [ $PIPELINE == 'fmriprep' ];then

	datalad get -n -r -J $SLURM_CPUS_PER_TASK ${1}
	datalad get -n -r -R1 -J $SLURM_CPUS_PER_TASK derivatives
	datalad get -n -r -J $SLURM_CPUS_PER_TASK $CLONE_DERIV_DIR/fmriprep

	git -C $CLONE_DERIV_DIR/fmriprep checkout -b "$PIPE_ID"

	(cd $CLONE_DERIV_DIR/fmriprep && rm -rf dataset_description.json desc-aseg_dseg.tsv desc-aparcaseg_dseg.tsv logs "${1}")
	cd $CLONE
	
	datalad containers-run \
	   -m "$PIPE_ID" \
	   --explicit \
	   --output $CLONE_DERIV_DIR/fmriprep \
	   --input "$CLONE/$1" --input "$CLONE_DERIV_DIR/smriprep" --input "$CLONE_DERIV_DIR/freesurfer" \
	   --container-name fmriprep \
	    . derivatives participant \
	    -w /tmp \
	    --participant-label $1 \
	    --output-spaces fsnative fsaverage MNI152NLin6Asym \
	    --nthreads $SLURM_CPUS_PER_TASK \
	    --stop-on-first-crash \
	    --ignore t2w \
	    --skip-bids-validation \
	    --anat-derivatives derivatives/smriprep \
	    --fs-subjects-dir derivatives/freesurfer \
	    --fs-no-reconall \
	    --use-aroma \
	    --random-seed 12345 \
	    --use-syn-sdc \
	    --fs-license-file envs/freesurfer_license.txt

	flock $DSLOCKFILE datalad push -d $CLONE_DERIV_DIR/fmriprep --to origin
 
elif [ $PIPELINE == 'xcpengine' ];then

	echo $PIPELINE

elif [ $PIPELINE == 'wmhprep' ];then
	
	datalad get -n -r -J $SLURM_CPUS_PER_TASK ${1}
	datalad get -n -r -R1 -J $SLURM_CPUS_PER_TASK derivatives
	datalad -l debug get -n -r -J $SLURM_CPUS_PER_TASK $CLONE_DERIV_DIR/wmhprep

	git -C $CLONE_DERIV_DIR/wmhprep checkout -b "$PIPE_ID"

	(cd $CLONE_DERIV_DIR/wmhprep && rm -rf "${1}")

	cd $CLONE

	source $WORK/set_envs/mrtrix3
	source $WORK/set_envs/fsl

	T1_OASIS=$TEMPLATEFLOW_HOME/tpl-OASIS30ANTs/tpl-OASIS30ANTs_res-01_T1w-nii.gz
	PRIOR_OASIS=$TEMPLATEFLOW_HOME/tpl-OASIS30ANTs/tpl-OASIS30ANTs_res-01_desc-BrainCerebellumExtraction_mask.nii.gz

	# Set pipeline variables as
	# As relative paths since datalad doesn't like absolute paths in eph. clone
	OUT_DIR=derivatives/wmhprep/$1/ses-1/anat/
	[ ! -d $OUT_DIR ] && mkdir -p $OUT_DIR

	T1=derivatives/smriprep/$1/ses-1/anat/${1}_ses-1_desc-preproc_T1w.nii.gz
	T1_MASK=derivatives/smriprep/$1/ses-1/anat/${1}_ses-1_desc-brain_mask.nii.gz
	FLAIR=$1/ses-1/anat/${1}_ses-1_FLAIR.nii.gz
	T1_IN_FLAIR=$OUT_DIR/${1}_ses-1_space-FLAIR_desc-preproc_T1w.nii.gz
	T1_TO_FLAIR_WARP=$OUT_DIR/${1}_ses-1_from-T1w_to-FLAIR_mode-image_xfm.txt
	T1_MASK_IN_FLAIR=.git/tmp/wdir/${1}_ses-1_space-FLAIR_desc-brain_mask.nii.gz
	T1_BRAIN_IN_FLAIR=$OUT_DIR/${1}_ses-1_space-FLAIR_desc-brainex_T1w.nii.gz
	T1_MASK_IN_FLAIR_THR=$OUT_DIR/${1}_ses-1_space-FLAIR_desc-brain_mask.nii.gz
	FLAIR_BRAIN=$OUT_DIR/${1}_ses-1_desc-brainex_FLAIR.nii.gz

	# Define commands
	CMD_T1_TO_FLAIR="flirt -in $T1 -ref $FLAIR -omat $T1_TO_FLAIR_WARP -out $T1_IN_FLAIR"
	CMD_T1_MASK_TO_FLAIR="flirt -in $T1_MASK -ref $FLAIR -init $T1_TO_FLAIR_WARP -out $T1_MASK_IN_FLAIR"
	CMD_MASK_THRESH="mrthreshold $T1_MASK_IN_FLAIR -abs 95 $T1_MASK_IN_FLAIR_THR"
	CMD_MASKING_T1_IN_FLAIR="mrcalc $T1_MASK_IN_FLAIR_THR $T1_IN_FLAIR -mult $T1_BRAIN_IN_FLAIR"
	CMD_MASKING_FLAIR="mrcalc $T1_MASK_IN_FLAIR_THR $FLAIR -mult $FLAIR_BRAIN"
#	CMD="antsBrainExtraction.sh -d 3 -a $FLAIR -e $T1_OASIS -m $PRIOR_OASIS -o $CLONE_TMP_DIR/FLAIR"
	
	# Execute commands with datalad
	datalad -l debug run --explicit -m "Preprocessed T1w from smriprep output to FLAIR space $1 $SLURM_JOBID" \
	--input $T1 -i $FLAIR \
	--output $T1_IN_FLAIR -o $T1_TO_FLAIR_WARP \
	$CMD_T1_TO_FLAIR

	datalad run --explicit -m "T1w mask to FLAIR $1 $SLURM_JOBID" \
	--input $T1_MASK -i $FLAIR -i $T1_TO_FLAIR_WARP \
	--output $T1_MASK_IN_FLAIR \
	$CMD_T1_MASK_TO_FLAIR

	datalad run --explicit -m "Masking T1 in FLAIR $1 $SLURM_JOBID" \
	--input $T1_MASK_IN_FLAIR_THR -i $T1_IN_FLAIR \
	--output $T1_BRAIN_IN_FLAIR \
	$CMD_MASKING_T1_IN_FLAIR

	datalad run --explicit -m "Masking T1 in FLAIR $1 $SLURM_JOBID" \
	--input $T1_MASK_IN_FLAIR_THR -i $T1_IN_FLAIR \
	--output $T1_BRAIN_IN_FLAIR \
	$CMD_MASKING_T1_IN_FLAIR

	datalad run --explicit -m "Masking FLAIR with T1-derived mask $1 $SLURM_JOBID" \
	--input $T1_MASK_IN_FLAIR_THR -i $FLAIR \
	--output $FLAIR_BRAIN \
	$CMD_MASKING_FLAIR

	#flock $DSLOCKFILE datalad push -d $CLONE_DERIV_DIR/wmhprep --to origin
fi

#################################################################
# After jobs have finished cd into result subdatasets of original dataset
#
# Pipeline results are for now located in git branches
# list branches with "git branch -l"
#
# Merge branches into master with 
# $ git merge -m "Merge results from job cluster XY" $(git branch -l | grep 'job-' | tr -d ' ')
#
# Delete merged branches with
# $ git branch --merged | grep -i -v -E "git-annex|master|dev"| xargs git branch -d
#
# TODO Consider automation
#################################################################

exit 0
