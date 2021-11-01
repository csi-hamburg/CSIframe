#!/usr/bin/env bash
set -x

###################################################################################################################
# Structural imaging analysis with Computational Anatomy Toolbox 12                                               #
# https://github.com/m-wierzba/cat-container                                                                      #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - LST (for lesion filling)                                                                                #
#   [container]                                                                                                   #
#       - mrtrix-3.0.2.sif (mrconvert for nii.gz-->.nii; cause strange things occur when using gunzip on hummel)  #
#       - cat12_standalone.sif                                                                                    #
###################################################################################################################

# Define subject array
input_subject_array=($@)

# Define environment
#########################
module load zip

MRTRIX_VERSION=mrtrix3-3.0.2
MRTRIX_CONTAINER=$ENV_DIR/$MRTRIX_VERSION
CAT_VERSION=cat12_standalone
CAT_CONTAINER=$ENV_DIR/$CAT_VERSION
CAT_CODE_DIR=$CODE_DIR/pipelines/cat12/
OUT_DIR=$DATA_DIR/cat12/$1; [ ! -d $OUT_DIR ] && mkdir -p $OUT_DIR
#TMP_DIR=$TMP_DIR/cat12; [ ! -d $TMP_DIR ] && mkdir -p $TMP_DIR
singularity="singularity exec --cleanenv --no-home --userns -B $PROJ_DIR -B $WORK/:/home -B $TMP_DIR:/tmp_dir"

###############################################################################################################################################################
##### STEP 1: SEGMENTATION & SMOOTHING
###############################################################################################################################################################
# Define inputs
T1=${1}_ses-${SESSION}_T1w.nii.gz
T1_orig=$DATA_DIR/raw_bids/$1/ses-$SESSION/anat/$T1

# Define outputs
#cp -rf $T1_orig $TMP_DIR
#gzip -dc $TMP_DIR/$T1 > $TMP_DIR/T1.nii
GM_SEGMENTS=mri/mwp1T1.nii

# Define commands
CMD_CONVERT="mrconvert $T1_orig /tmp_dir/T1.nii -force"
CMD_SEGMENT="cat_standalone.sh -b $CAT_CODE_DIR/cat_standalone_segment.txt /tmp_dir/T1.nii"
CMD_SMOOTH="cat_standalone.sh -b $CAT_CODE_DIR/cat_standalone_smooth.txt /tmp_dir/$GM_SEGMENTS"

# Execute 
$singularity $MRTRIX_CONTAINER \
/bin/bash -c "$CMD_CONVERT"
$singularity $CAT_CONTAINER \
/bin/bash -c "$CMD_SEGMENT; $CMD_SMOOTH"

rm -rf $TMP_DIR/T1.nii #$TMP_DIR/$T1
cp -ruvf $TMP_DIR/* $OUT_DIR
###############################################################################################################################################################