#!/usr/bin/env bash

###################################################################################################################
# Structural imaging analysis with Computational Anatomy Toolbox 12                                               #
# https://github.com/m-wierzba/cat-container                                                                      #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - none (optional 'wmh' for lesion filling -> change paths accordingly)                                    #
#   [container]                                                                                                   #
#       - mrtrix-3.0.2.sif (mrconvert for nii.gz-->.nii; unexpected things occur when using hpc gunzip on nii.gz) #
#       - cat12_standalone.sif                                                                                    #
###################################################################################################################

# Get verbose outputs
set -x

# Define subject specific temporary directory on $SCRATCH_DIR
export TMP_DIR=$SCRATCH_DIR/$1/tmp/;   [ ! -d $TMP_DIR ] && mkdir -p $TMP_DIR
TMP_IN=$TMP_DIR/input;                 [ ! -d $TMP_IN ] && mkdir -p $TMP_IN
TMP_OUT=$TMP_DIR/output;               [ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT

###################################################################################################################

# Define environment
#########################
module load parallel

FBA_DIR=$DATA_DIR/fba
FBA_GROUP_DIR=$FBA_DIR/derivatives; [ ! -d $FBA_GROUP_DIR ] && mkdir -p $FBA_GROUP_DIR
TEMPLATE_SUBJECTS_TXT=$FBA_DIR/sourcedata/template_subjects.txt
TEMPLATE_RANDOM_SUBJECTS_TXT=$FBA_DIR/sourcedata/random_template_subjects.txt
export SINGULARITYENV_MRTRIX_TMPFILE_DIR=/tmp

container_mrtrix3=mrtrix3-3.0.2      
container_cat12=cat12_standalone

singularity_mrtrix3="singularity exec --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_mrtrix3" 

singularity_cat12="singularity exec --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $WORK/:/home \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_cat12" 

parallel="parallel --ungroup --delay 0.2 -j16 --joblog $CODE_DIR/log/parallel_runtask.log"

# Define subject array
input_subject_array=($@)

# Define environment
#########################
CAT_CODE_DIR=$CODE_DIR/pipelines/cat12/
OUT_DIR=$DATA_DIR/cat12/$1; [ ! -d $OUT_DIR ] && mkdir -p $OUT_DIR
#singularity="singularity exec --cleanenv --no-home --userns -B $PROJ_DIR -B $WORK/:/home -B $TMP_DIR:/tmp_dir"

###############################################################################################################################################################
##### STEP 1: SEGMENTATION & SMOOTHING
###############################################################################################################################################################
# Define inputs
T1=${1}_ses-${SESSION}_T1w.nii.gz
T1_orig=$DATA_DIR/raw_bids/$1/ses-$SESSION/anat/$T1

# Define outputs
GM_SEGMENTS=mri/mwp1T1.nii
LH_THICKNESS=surf/lh.thickness.T1


# Define commands
CMD_CONVERT="mrconvert $T1_orig /tmp_out/T1.nii -force"
CMD_SEGMENT="cat_standalone.sh -b $CAT_CODE_DIR/cat_standalone_segment.txt /tmp_out/T1.nii"
CMD_SMOOTH="cat_standalone.sh -b $CAT_CODE_DIR/cat_standalone_smooth.txt -a1 "[6 6 6]" -a2 "'s6'" /tmp_out/$GM_SEGMENTS"
CMD_RESAMPLE_LH_CONTE="cat_standalone.sh -b $CAT_CODE_DIR/cat_standalone_resample.txt -a1 "12" -a2 "1" /tmp_out/$LH_THICKNESS"
CMD_RESAMPLE_LH_FS="cat_standalone.sh -b $CAT_CODE_DIR/cat_standalone_resample.txt -a1 "12" -a2 "0" /tmp_out/$LH_THICKNESS"

# Execute 
$singularity_mrtrix3 \
/bin/bash -c "$CMD_CONVERT"
$singularity_cat12 \
/bin/bash -c "$CMD_SEGMENT"
$singularity_cat12 \
/bin/bash -c "$CMD_SMOOTH"
$singularity_cat12 \
/bin/bash -c "$CMD_RESAMPLE_LH_CONTE"
$singularity_cat12 \
/bin/bash -c "$CMD_RESAMPLE_LH_FS"

rm -rf $TMP_OUT/T1.nii #$TMP_DIR/$T1
cp -ruvf $TMP_OUT/* $OUT_DIR
###############################################################################################################################################################
