#!/bin/bash

# Get input and output dataset directory trees
datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_BIDS_DIR/$1
datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/freesurfer
datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/smriprep
datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/smriprep/$1

# Checkout unique branches (names derived from jobIDs) of result subdatasets
# to enable pushing the results without interference from other jobs.
# In a setup with no subdatasets, "-C <subds-name>" would be stripped,
# and a new branch would be checked out in the superdataset instead.
git -C $CLONE_DATA_DIR/freesurfer checkout -b "job-$SLURM_JOBID-freesurfer-$1"
#git -C $CLONE_DATA_DIR/freesurfer/$1 checkout -b "job-$SLURM_JOBID-freesurfer-$1"
git -C $CLONE_DATA_DIR/smriprep checkout -b "job-$SLURM_JOBID-smriprep-$1"
git -C $CLONE_DATA_DIR/smriprep/$1 checkout -b "job-$SLURM_JOBID-smriprep-$1"

# Remove job outputs in dataset clone to prevent issues when rerunning
# Freesurfer requires removal of output subject directory before processing, hence no subdataset structure only directories in data/freesurfer
(cd $CLONE_DATA_DIR/freesurfer && rm -rf fsaverage $1 .bidsignore)
(cd $CLONE_DATA_DIR/smriprep && rm -rf logs $1/* "${1}.html" dataset_description.json desc-aparcaseg_dseg.tsv desc-aseg_dseg.tsv .bidsignore)

CMD="
   singularity run --cleanenv --userns -B . -B $PROJ_DIR -B $SCRATCH_DIR/:/tmp \
   $ENV_DIR/smriprep-0.8.0rc2
    data/raw_bids data participant \
    -w .git/tmp/wdir \
    --participant-label $1 \
    --output-spaces fsnative fsaverage MNI152NLin6Asym T1w T2w \
    --nthreads $SLURM_CPUS_PER_TASK \
    --fs-subjects-dir data/freesurfer \
    --stop-on-first-crash \
    --fs-license-file envs/freesurfer_license.txt
"

datalad run \
   -m "$PIPE_ID" \
   --explicit \
   --output $CLONE_DATA_DIR/freesurfer -o $CLONE_DATA_DIR/smriprep -o $CLONE_DATA_DIR/smriprep/$1 \
   --input "$CLONE_BIDS_DIR/$1"\
    $CMD

echo $(ls -lah $CLONE_DATA_DIR/smriprep)
echo $(ls -lah $CLONE_DATA_DIR/smriprep/$1)
echo $(ls -lah $CLONE_DATA_DIR/freesurfer)
echo $(ls -lah $CLONE_DATA_DIR/freesurfer/$1)

#flock $DSLOCKFILE datalad push -d $CLONE_DATA_DIR/freesurfer/$1 --to origin
flock $DSLOCKFILE datalad push -d $CLONE_DATA_DIR/freesurfer --to origin
flock $DSLOCKFILE datalad push -d $CLONE_DATA_DIR/smriprep/$1 --to origin
flock $DSLOCKFILE datalad push -d $CLONE_DATA_DIR/smriprep --to origin