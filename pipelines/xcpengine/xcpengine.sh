#!/usr/bin/env bash

###################################################################################################################
# Functional connectome reconstruction (and structural preproc) (https://xcpengine.readthedocs.io/)               #
#                                                                                                                 #
# Internal documentation:                                                                                         #
#   https://github.com/csi-hamburg/hummel_processing/wiki/Functional-Connectome-Reconstruction                    #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - fmriprep                                                                                                #
#   [container]                                                                                                   #
#       - xcpengine-1.2.3.sif                                                                                     #
#                                                                                                                 #
# Author: Marvin Petersen (m-petersen)                                                                            #
###################################################################################################################

# Get verbose outputs
set -x

# Define subject specific temporary directory on $SCRATCH_DIR
export TMP_DIR=$SCRATCH_DIR/$1/tmp/;   [ ! -d $TMP_DIR ] && mkdir -p $TMP_DIR
TMP_IN=$TMP_DIR/input;                 [ ! -d $TMP_IN ] && mkdir -p $TMP_IN
TMP_OUT=$TMP_DIR/output;               [ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT

###################################################################################################################

# Pipeline-specific environment
##################################

# Singularity container version and command
container_xcpengine=xcpengine-1.2.3
singularity_xcpengine="singularity run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_xcpengine" 

# To make I/O more efficient read/write outputs from/to scratch
[ -d $TMP_IN ] && cp -rf $DATA_DIR/fmriprep/$1 $TMP_IN 
[ ! -d $TMP_OUT/xcpengine ] && mkdir -p $TMP_OUT/xcpengine

# Create cohort file
#########################
COHORT_FILE=$TMP_DIR/${1}_ses-${SESSION}_cohort_file.txt

BOLD_IMG=$1/ses-$SESSION/func/${1}_ses-${SESSION}_task-rest_space-MNI152NLin2009cAsym_desc-preproc_bold.nii.gz
echo "id0,img" > $COHORT_FILE
echo "$1,$BOLD_IMG" >> $COHORT_FILE

design=${MODIFIER%.*}
echo $design
# elif [ $MODIFIER == fc_aromagsr ];then

#    BOLD_IMG=$1/ses-$SESSION/func/${1}_ses-${SESSION}_task-rest_space-MNI152NLin2009cAsym_desc-preproc_bold.nii.gz
#    echo "id0,img" > $COHORT_FILE
#    echo "$1,$BOLD_IMG" >> $COHORT_FILE

#    design=fc-aroma-gsr.dsn

# fi


CMD="
   $singularity_xcpengine \
   -d code/pipelines/xcpengine/$MODIFIER \
   -c /tmp/${1}_ses-${SESSION}_cohort_file.txt \
   -i /tmp \
   -r /tmp_in \
   -o /tmp_out/xcpengine \
   -t 3"
$CMD

OUTPUT_DESIGN_DIR=$DATA_DIR/xcpengine/${design}
[ ! -d $OUTPUT_DESIGN_DIR ] && mkdir -p $OUTPUT_DESIGN_DIR
cp -ruvf $TMP_OUT/xcpengine/* $OUTPUT_DESIGN_DIR