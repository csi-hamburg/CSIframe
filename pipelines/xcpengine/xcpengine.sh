#!/bin/bash

# Set specific environment for pipeline
XCPENGINE_VERSION=xcpengine-1.2.3

# To make I/O more efficient read/write outputs from/to scratch #
TMP_IN=$TMP_DIR/input
TMP_OUT=$TMP_DIR/output
[ ! -d $TMP_IN ] && mkdir -p $TMP_IN && cp -rf $DATA_DIR/fmriprep/$1 $BIDS_DIR/dataset_description.json $TMP_IN 
[ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT/xcpengine

# Create cohort file
#########################
COHORT_FILE=$TMP_DIR/${1}_ses-${SESSION}_cohort_file.txt

if [ $MODIFIER == struc ];then

   T1_IMG=$1/ses-$SESSION/anat/${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz
   echo "id0,img" > $COHORT_FILE
   echo "$1,$T1_IMG" >> $COHORT_FILE

   design=struc.dsn

elif [ $MODIFIER == fc ];then

   BOLD_IMG=$1/ses-$SESSION/func/${1}_ses-${SESSION}_task-rest_space-MNI152NLin6Asym_desc-preproc_bold.nii.gz
   echo "id0,img" > $COHORT_FILE
   echo "$1,$BOLD_IMG" >> $COHORT_FILE

   design=fc-36p_spkreg.dsn

fi


CMD="
   singularity run --cleanenv --userns -B $PROJ_DIR/data:/data -B $TMP_DIR/:/tmp -B $TMP_IN:/tmp_in -B $TMP_OUT:/tmp_out \
   $ENV_DIR/$XCPENGINE_VERSION \
   -d code/pipelines/xcpengine/$design \
   -c /tmp/${1}_ses-${SESSION}_cohort_file.txt \
   -i /tmp \
   -r /tmp_in \
   -o /tmp_out \
   -t 1"
$CMD

cp -ruvf $TMP_OUT/xcpengine $DATA_DIR


