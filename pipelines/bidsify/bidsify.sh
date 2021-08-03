#!/bin/bash

# Get symlink tree of sourcedata
datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/dicoms
datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/dicoms/${1}
datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/raw_bids/sub-${1}

# Checkout new branch in bids subject directory dataset
git -C data/raw_bids/sub-${1} checkout -b "${PIPE_ID}"

# Remove previously produced outputs from CLONE to avoid clonflicts
( rm -rf data/raw_bids/sub-${1}/ses-* )

# Run heudiconv for dcm2nii and bidsification of its outputs
# heudiconv_heuristic.py is dataset specific
# FIXME: amend -d PATH according to your dicom directory structure 
# FIXME: amend -f PATH to the suitable heudiconv heuristic file
CMD="
    singularity run --cleanenv --userns\
    --home $PWD \
    -B $CODE_DIR:/code \
    -B $CLONE_BIDS_DIR:/bids \
    -B $CLONE_DCM_DIR:/dcm \
    -B $CLONE_TMP_DIR:/tmp \
    $ENV_DIR/heudiconv-0.9.0\
    heudiconv \
    -d /dcm/{{subject}}/ses-{{session}}.tar.gz\
    --subjects $1 \
    --ses $SESSION \
    --bids notop \
    -f /code/pipelines/bidsify/heudiconv_test.py\
    -c dcm2niix \
    --minmeta \
    --overwrite\
    --grouping accession_number \
    -o /bids"

    
datalad run -m "${PIPE_ID} heudiconv" \
   --explicit \
   --output $CLONE_BIDS_DIR/sub-${1} -o $CLONE_BIDS_DIR/participants.tsv -o $CLONE_BIDS_DIR/participants.json -o $CLONE_BIDS_DIR/dataset_description.json \
   --input $CLONE_DCM_DIR/$1 \
   $CMD
datalad save -d . -r -F .git/COMMIT_EDITMSG

# Deface	

T1=$CLONE_BIDS_DIR/sub-${1}/ses-${SESSION}/anat/sub-${1}_ses-${SESSION}_T1w.nii.gz
CMD_T1="pydeface $T1 --outfile $T1 --force --verbose"
datalad run \
   -m "${PIPE_ID} pydeface T1w" \
   --explicit \
   --output "$CLONE_BIDS_DIR/sub-${1}/*/*/*T1w.nii.gz" \
   --input "$CLONE_BIDS_DIR/sub-${1}/*/*/*T1w.nii.gz" \
   singularity run --cleanenv --userns -B . -B $PROJ_DIR -B $SCRATCH_DIR/:/tmp \
   $ENV_DIR/pydeface-2.0.0 \
   $CMD_T1

T2=$CLONE_BIDS_DIR/sub-${1}/ses-${SESSION}/anat/sub-${1}_ses-${SESSION}_T2w.nii.gz
CMD_T2="pydeface $T2 --outfile $T2 --force --verbose"
datalad run \
   -m "${PIPE_ID} pydeface T2w" \
   --explicit \
   --output "$CLONE_BIDS_DIR/sub-${1}/*/*/*T2w.nii.gz" \
   --input "$CLONE_BIDS_DIR/sub-${1}/*/*/*T2w.nii.gz" \
   singularity run --cleanenv --userns -B . -B $PROJ_DIR -B $SCRATCH_DIR/:/tmp \
   $ENV_DIR/pydeface-2.0.0 \
   $CMD_T2

FLAIR=$CLONE_BIDS_DIR/sub-${1}/ses-${SESSION}/anat/sub-${1}_ses-${SESSION}_FLAIR.nii.gz
CMD_FLAIR="pydeface $FLAIR --outfile $FLAIR --force --verbose"
datalad run \
   -m "${PIPE_ID} pydeface FLAIR" \
   --explicit \
   --output "$CLONE_BIDS_DIR/sub-${1}/*/*/*FLAIR.nii.gz" \
   --input "$CLONE_BIDS_DIR/sub-${1}/*/*/*FLAIR.nii.gz" \
   singularity run --cleanenv --userns -B . -B $PROJ_DIR -B $SCRATCH_DIR/:/tmp \
   $ENV_DIR/pydeface-2.0.0 \
   $CMD_FLAIR

# Remove problematic metadata from json sidecars
CMD="python $CODE_DIR/pipelines/$PIPELINE/handle_metadata.py $1"
datalad run -m '${PIPE_ID} handle metadata' \
   --explicit \
   --output "$CLONE_BIDS_DIR/sub-${1}/*/*/*.json" \
   --input "$CLONE_BIDS_DIR/sub-${1}/*/*/*.json" \
   $CMD

rm -rf $CLONE_BIDS_DIR/.heudiconv

# Push results from clone to original dataset
flock $DSLOCKFILE datalad push -d $CLONE_BIDS_DIR/sub-${1} --to origin