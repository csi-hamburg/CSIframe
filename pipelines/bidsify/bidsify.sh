#!/bin/bash


if [ -z $HEURISTIC ];then
	echo "What heuristic do you want to apply?"
	echo "Choose from" $(ls $CODE_DIR/pipelines/bidsify/heudiconv_*)
	read HEURISTIC; export HEURISTIC
fi

# Run heudiconv for dcm2nii and bidsification of its outputs
# heudiconv_heuristic.py is dataset specific
CMD="
   heudiconv \
   -d /dcm/{subject}/ses-{session}.tar.gz\
   --subjects $1 \
   --ses $SESSION \
   --bids notop \
   -f /code/pipelines/bidsify/$HEURISTIC\
   -c dcm2niix \
   --minmeta \
   --overwrite\
   --grouping accession_number \
   -o /bids"
singularity run --cleanenv --userns \
--home $PWD \
-B $CODE_DIR:/code \
-B $BIDS_DIR:/bids \
-B $DCM_DIR:/dcm \
-B $TMP_DIR:/tmp \
$ENV_DIR/heudiconv-0.9.0 \
$CMD

chmod 770 -R $BIDS_DIR/sub-${1}

# Deface	
singularity="singularity run --cleanenv --userns -B . -B $TMP_DIR/:/tmp"

T1=$BIDS_DIR/sub-${1}/ses-${SESSION}/anat/sub-${1}_ses-${SESSION}_T1w.nii.gz
CMD_T1="pydeface $T1 --outfile $T1 --force --verbose"
$singularity \
$ENV_DIR/pydeface-2.0.0 \
/bin/bash -c "$CMD_T1"

T2=$BIDS_DIR/sub-${1}/ses-${SESSION}/anat/sub-${1}_ses-${SESSION}_T2w.nii.gz
CMD_T2="pydeface $T2 --outfile $T2 --force --verbose"
$singularity \
$ENV_DIR/pydeface-2.0.0 \
$CMD_T2

FLAIR=$BIDS_DIR/sub-${1}/ses-${SESSION}/anat/sub-${1}_ses-${SESSION}_FLAIR.nii.gz
CMD_FLAIR="pydeface $FLAIR --outfile $FLAIR --force --verbose"
$singularity \
$ENV_DIR/pydeface-2.0.0 \
$CMD_FLAIR

# Remove problematic metadata from json sidecars
CMD="python $CODE_DIR/pipelines/$PIPELINE/handle_metadata.py $1"
$CMD

rm -rf $BIDS_DIR/.heudiconv