#!/bin/bash

# Get symlink tree of sourcedata
datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/dicoms
datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/dicoms/${1}
datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/raw_bids/sub-${1}

# Checkout new branch in bids subject directory dataset
#git -C data/raw_bids/ checkout -b "${PIPE_ID}"
git -C data/raw_bids/sub-${1} checkout -b "${PIPE_ID}"

( rm -rf data/raw_bids/sub-${1}/ses-* )

# Run heudiconv for dcm2nii and bidsification of its outputs
# heudiconv_heuristic.py is dataset specific
# FIXME: amend -d PATH according to your dicom directory structure 
# FIXME: amend -f PATH to the suitable heudicon heuristic file
CMD="
    singularity run --cleanenv --userns\
    --home $PWD \
    -B $CODE_DIR:/code \
    -B $CLONE_BIDS_DIR:/bids \
    -B $CLONE_DCM_DIR:/dcm \
    -B $CLONE_TMP_DIR:/tmp \
    $ENV_DIR/heudiconv-0.9.0.sif\
    -d /dcm/{{subject}}/ses-{{session}}.tar.gz\
    --subjects $1 \
    --ses 1 \
    --bids notop \
    -f /code/pipelines/bidsify/heudiconv_test.py\
    -c dcm2niix \
    --overwrite\
    --minmeta \
    --grouping accession_number \
    -o /bids"

datalad run -m "${PIPE_ID} heudiconv" \
   --explicit \
   --output $CLONE_BIDS_DIR/sub-${1} -o $CLONE_BIDS_DIR/participants.tsv -o $CLONE_BIDS_DIR/participants.json -o $CLONE_BIDS_DIR/dataset_description.json \
   --input $CLONE_DCM_DIR/$1 \
   $CMD
      
# Deface T1	
T1=$CLONE_BIDS_DIR/sub-${1}/ses-1/anat/sub-${1}_ses-1_T1w.nii.gz
datalad containers-run \
   -m "${PIPE_ID} pydeface T1w" \
   --explicit \
   --output "$CLONE_BIDS_DIR/sub-${1}/*/*/*T1w.nii.gz" \
   --input "$CLONE_BIDS_DIR/sub-${1}/*/*/*T1w.nii.gz" \
   --container-name pydeface \
           pydeface $T1 \
    --outfile $T1 \
    --force

# Deface FLAIR
FLAIR=$CLONE_BIDS_DIR/sub-${1}/ses-1/anat/sub-${1}_ses-1_FLAIR.nii.gz
datalad containers-run \
   -m "${PIPE_ID} pydeface FLAIR" \
   --explicit \
   --output "$CLONE_BIDS_DIR/sub-${1}/*/*/*FLAIR.nii.gz" \
   --input "$CLONE_BIDS_DIR/sub-${1}/*/*/*FLAIR.nii.gz" \
   --container-name pydeface \
           pydeface $FLAIR \
    --outfile $FLAIR \
    --force

# Remove problematic metadata from json sidecars
CMD="python $CODE_DIR/pipelines/$PIPELINE/handle_metadata.py $1"
datalad run -m '${PIPE_ID} handle metadata' \
   --explicit \
   --output "$CLONE_BIDS_DIR/sub-${1}/*/*/*.json" \
   --input "$CLONE_BIDS_DIR/sub-${1}/*/*/*.json" \
   $CMD

rm -rf $CLONE_BIDS_DIR/.heudiconv

# Push results from clone to original dataset
#flock $DSLOCKFILE datalad push -d $CLONE_BIDS_DIR/ --to origin
flock $DSLOCKFILE datalad push -d $CLONE_BIDS_DIR/sub-${1} --to origin