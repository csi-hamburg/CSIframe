#!/bin/bash

# Set specific environment for pipeline
XCPENGINE_VERSION=xcpengine-1.2.3

OUT_DIR=data/xcpengine/$1/ses-${SESSION}/func/
[ ! -d $OUT_DIR ] && mkdir -p $OUT_DIR

# Create cohort file
#########################
BOLD_IMG=$1/$SESSION/func/${1}_ses-${SESSION}_task-rest_space-MNI152NLin6Asym_desc-preproc_bold.nii.gz
COHORT_FILE=$TMP_DIR/${1}_ses-${SESSION}_cohort_file.txt
REFERENCE_DIR=data/fmriprep
echo "$1 $T1_IN_FLAIR $FLAIR_TO_MNI_WARP" > $COHORT_FILE


CMD="
   singularity run --cleanenv --userns -B $PROJ_DIR -B $TMP_DIR/:/tmp \
   $ENV_DIR/$XCPENGINE_VERSION \
   -d code/pipelines/xpengine/$DESIGN \
   -c /tmp/${1}_ses-${SESSION}_cohort_file.txt \
   -r $REFERENCE_DIR \
   -o $OUT_DIR"
[ ! -z $MODIFIER ] && CMD="${CMD} $MODIFIED"
$CMD


