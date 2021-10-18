#!/bin/bash

# Set specific environment for pipeline
XCPENGINE_VERSION=xcpengine-1.2.3


# Create cohort file
#########################
COHORT_FILE=$TMP_DIR/${1}_ses-${SESSION}_cohort_file.txt

if [ $MODIFIER == struct ];then

   BOLD_IMG=$1/$SESSION/func/${1}_ses-${SESSION}_task-rest_space-MNI152NLin6Asym_desc-preproc_bold.nii.gz
   REFERENCE_DIR=data/fmriprep
   echo "$1 $BOLD_IMG" > $COHORT_FILE

   OUT_DIR=data/xcpengine/
   [ ! -d $OUT_DIR ] && mkdir -p $OUT_DIR

elif [ $MODIFIER == fc ];then

   BOLD_IMG=$1/$SESSION/func/${1}_ses-${SESSION}_task-rest_space-MNI152NLin6Asym_desc-preproc_bold.nii.gz
   REFERENCE_DIR=data/fmriprep
   echo "id0, img" > $COHORT_FILE
   echo "$1 $BOLD_IMG" > $COHORT_FILE

   OUT_DIR=data/xcpengine/
   [ ! -d $OUT_DIR ] && mkdir -p $OUT_DIR

fi

CMD="
   singularity run --cleanenv --userns -B $PROJ_DIR -B $TMP_DIR/:/tmp \
   $ENV_DIR/$XCPENGINE_VERSION \
   -d code/pipelines/xcpengine/$DESIGN \
   -c /tmp/${1}_ses-${SESSION}_cohort_file.txt \
   -r $REFERENCE_DIR \
   -i /tmp \
   -o $OUT_DIR \
   -t 1"
$CMD


