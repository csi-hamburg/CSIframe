#!/bin/bash

# Set specific environment for pipeline
export MRTRIX_TMPFILE_DIR=$SCRATCH_DIR

# Get input and output dataset directory trees
datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_BIDS_DIR/$1
datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/qsiprep 
datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/qsiprep/$1 
datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/qsirecon
datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/qsirecon/$1

# Remove other participants than $1 in qsiprep output (otherwise qsirecon confuses subjects)
find data/qsiprep -maxdepth 1 -name 'sub-*' -type d -a ! -name '*'"$1"'*' -exec rm -rv {} +
echo ls qsiprep directory: $(ls data/qsiprep)

# Checkout unique branches (names derived from jobIDs) of result subdatasets
# to enable pushing the results without interference from other jobs.
# In a setup with no subdatasets, "-C <subds-name>" would be stripped,
# and a new branch would be checked out in the superdataset instead.
git -C $CLONE_DATA_DIR/qsiprep/$1 checkout -b "$PIPE_ID"
git -C $CLONE_DATA_DIR/qsiprep checkout -b "$PIPE_ID"
git -C $CLONE_DATA_DIR/qsirecon/$1 checkout -b "$PIPE_ID"
git -C $CLONE_DATA_DIR/qsirecon checkout -b "$PIPE_ID"


# Remove job outputs in dataset clone to prevent issues when rerunning
# $1/* matches all content in subject subdataset but dotfiles (.git, .datalad, .gitattributes)
(cd $CLONE_DATA_DIR/qsiprep && rm -rf logs $1/* "${1}.html" dwiqc.json dataset_description.json .bidsignore)
(cd $CLONE_DATA_DIR/qsirecon && rm -rf logs $1/* "${1}.html" dwiqc.json dataset_description.json .bidsignore)

cd $CLONE

# Run pipeline with datalad
datalad containers-run \
   -m "$PIPE_ID" \
   --explicit \
   --input "$CLONE_BIDS_DIR/$1" \
   --output $CLONE_DATA_DIR/qsiprep -o $CLONE_DATA_DIR/qsiprep/$1 -o $CLONE_DATA_DIR/qsirecon -o $CLONE_DATA_DIR/qsirecon/$1 \
   --container-name qsiprep \
    data/raw_bids data participant \
    -w .git/tmp/wdir \
    --participant-label $1 \
    --recon_input data/qsiprep/$1 \
    --recon_spec mrtrix_multishell_msmt \
    --nthreads $SLURM_CPUS_PER_TASK \
    --skip-bids-validation \
    --use-syn-sdc \
    --denoise-method dwidenoise \
    --unringing-method mrdegibbs \
    --skull-strip-template OASIS \
    --stop-on-first-crash \
    --output-resolution 1.3 \
    --stop-on-first-crash \
    --fs-license-file envs/freesurfer_license.txt

echo $(ls -lah $CLONE_DATA_DIR/qsiprep)
echo $(ls -lah $CLONE_DATA_DIR/qsiprep/$1)
echo $(ls -lah $CLONE_DATA_DIR/qsirecon)
echo $(ls -lah $CLONE_DATA_DIR/qsirecon/$1)

# Push results from clone to original dataset
flock $DSLOCKFILE datalad push -d $CLONE_DATA_DIR/qsiprep --to origin
flock $DSLOCKFILE datalad push -d $CLONE_DATA_DIR/qsiprep/$1 --to origin
flock $DSLOCKFILE datalad push -d $CLONE_DATA_DIR/qsirecon --to origin
flock $DSLOCKFILE datalad push -d $CLONE_DATA_DIR/qsirecon/$1 --to origin