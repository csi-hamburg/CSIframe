#!/bin/bash

	# Get input and output dataset directory trees
    datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_BIDS_DIR/${1}
	datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/smriprep
	datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/smriprep/$1
	datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/freesurfer
	datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/freesurfer/$1
	datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/fmriprep
	datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/fmriprep/$1

	# Checkout unique branches (names derived from jobIDs) of result subdatasets
	# to enable pushing the results without interference from other jobs.
	# In a setup with no subdatasets, "-C <subds-name>" would be stripped,
	# and a new branch would be checked out in the superdataset instead.
	git -C $CLONE_DATA_DIR/fmriprep checkout -b "$PIPE_ID"
	git -C $CLONE_DATA_DIR/fmriprep/$1 checkout -b "$PIPE_ID"
	git -C $CLONE_DATA_DIR/freesurfer checkout -b "$PIPE_ID"

	# Remove job outputs in dataset clone to prevent issues when rerunning
	# $1/* matches all content in subject subdataset but dotfiles (.git, .datalad, .gitattributes)
	(cd $CLONE_DATA_DIR/fmriprep && rm -rf dataset_description.json desc-aseg_dseg.tsv desc-aparcaseg_dseg.tsv logs $1/*)
	cd $CLONE
	
	# datalad containers-run \
	#    -m "$PIPE_ID" \
	#    --explicit \
	#    --input "$CLONE_BIDS_DIR/$1" -i "$CLONE_DATA_DIR/smriprep/$1" -i "$CLONE_DATA_DIR/freesurfer/$1" \
	#    --output $CLONE_DATA_DIR/fmriprep -o $CLONE_DATA_DIR/fmriprep/$1 \
	#    --container-name fmriprep \
	#     data/raw_bids data participant \
	#     -w /tmp \
	#     --participant-label $1 \
	#     --output-spaces fsnative fsaverage MNI152NLin6Asym \
	#     --nthreads $SLURM_CPUS_PER_TASK \
	#     --stop-on-first-crash \
	#     --ignore t2w \
	#     --skip-bids-validation \
	#     --fs-subjects-dir data/freesurfer \
	#     --use-aroma \
	#     --random-seed 12345 \
	#     --use-syn-sdc \
	#     --fs-license-file envs/freesurfer_license.txt
    CDM="
        singularity run --cleanenv --userns -B . -B $PROJ_DIR -B $SCRATCH_DIR/:/tmp \
        $ENV_DIR/fmriprep-20.2.1 \
	    data/raw_bids data participant \
	    -w /tmp \
	    --participant-label $1 \
	    --output-spaces fsnative fsaverage MNI152NLin6Asym \
	    --nthreads $SLURM_CPUS_PER_TASK \
	    --stop-on-first-crash \
	    --ignore t2w \
	    --skip-bids-validation \
	    --fs-subjects-dir data/freesurfer \
	    --use-aroma \
	    --random-seed 12345 \
	    --use-syn-sdc \
	    --fs-license-file envs/freesurfer_license.txt
    "
	datalad run \
	   -m "$PIPE_ID" \
	   --explicit \
	   --input "$CLONE_BIDS_DIR/$1" -i "$CLONE_DATA_DIR/smriprep/$1" -i "$CLONE_DATA_DIR/freesurfer/$1" \
	   --output $CLONE_DATA_DIR/fmriprep -o $CLONE_DATA_DIR/fmriprep/$1 \
        $CMD

	echo $(ls -lah $CLONE_DATA_DIR/fmriprep)
	echo $(ls -lah $CLONE_DATA_DIR/fmriprep/$1)

	flock $DSLOCKFILE datalad push -d $CLONE_DATA_DIR/fmriprep --to origin
	flock $DSLOCKFILE datalad push -d $CLONE_DATA_DIR/fmriprep/$1 --to origin
	flock $DSLOCKFILE datalad push -d $CLONE_DATA_DIR/freesurfer --to origin
