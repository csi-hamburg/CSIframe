#!/bin/bash

# Get input and output dataset directory trees
datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_BIDS_DIR/$1
datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/mriqc
datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/mriqc/$1

# Checkout unique branches (names derived from jobIDs) of result subdatasets
# to enable pushing the results without interference from other jobs.
# In a setup with no subdatasets, "-C <subds-name>" would be stripped,
# and a new branch would be checked out in the superdataset instead.
git -C $CLONE_DATA_DIR/mriqc checkout -b "$PIPE_ID"
git -C $CLONE_DATA_DIR/mriqc/$1 checkout -b "$PIPE_ID"

# Remove job outputs in dataset clone to prevent issues when rerunning
# $1/* matches all content in subject subdataset but dotfiles (.git, .datalad, .gitattributes)
(cd $CLONE_DATA_DIR/mriqc && rm -rf $1/* ${1}*.html dataset_description.json .bidsignore)

cd $CLONE

datalad containers-run \
   -m "$PIPE_ID" \
   --explicit \
   --input "$CLONE_BIDS_DIR/$1" --input "$CLONE_BIDS_DIR/dataset_description.json" \
   --output $CLONE_DATA_DIR/mriqc -o $CLONE_DATA_DIR/mriqc/$1 \
   --container-name mriqc \
    data/raw_bids data/mriqc participant \
    -w .git/tmp/wdir \
    --participant-label $1 \
    --modalities T1w T2w bold \
    --no-sub \
    --ica \
    --float32 \
    --nprocs $SLURM_CPUS_PER_TASK 

echo $(ls -lah $CLONE_DATA_DIR/mriqc)
echo $(ls -lah $CLONE_DATA_DIR/mriqc/$1)

datalad save -m "$PIPE_ID output" $CLONE_DATA_DIR/mriqc/
datalad save -m "$PIPE_ID output" $CLONE_DATA_DIR/mriqc/$1/

flock $DSLOCKFILE datalad push -d $CLONE_DATA_DIR/mriqc --to origin
flock $DSLOCKFILE datalad push -d $CLONE_DATA_DIR/mriqc/$1 --to origin