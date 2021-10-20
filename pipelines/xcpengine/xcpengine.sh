#!/bin/bash

# Set specific environment for pipeline
XCPENGINE_VERSION=xcpengine-1.2.3


# Create cohort file
#########################
COHORT_FILE=$TMP_DIR/${1}_ses-${SESSION}_cohort_file.txt

if [ $MODIFIER == struc ];then

   T1_IMG=fmriprep/$1/ses-$SESSION/func/${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz
   echo "$1 $T1_IMG" > $COHORT_FILE

   OUT_DIR=data/xcpengine/
   [ ! -d $OUT_DIR ] && mkdir -p $OUT_DIR

elif [ $MODIFIER == fc ];then

   BOLD_IMG=fmriprep/$1/ses-$SESSION/func/${1}_ses-${SESSION}_task-rest_space-MNI152NLin6Asym_desc-preproc_bold.nii.gz
   echo "id0,img" > $COHORT_FILE
   echo "$1,$BOLD_IMG" >> $COHORT_FILE

   OUT_DIR=data/xcpengine/
   [ ! -d $OUT_DIR ] && mkdir -p $OUT_DIR

fi

CMD="
   singularity run --cleanenv --userns -B $PROJ_DIR/data:/data -B $TMP_DIR/:/tmp \
   $ENV_DIR/$XCPENGINE_VERSION \
   -d code/pipelines/xcpengine/$DESIGN \
   -c /tmp/${1}_ses-${SESSION}_cohort_file.txt \
   -i /tmp \
   -r /data \
   -o $OUT_DIR \
   -t 1"
$CMD



