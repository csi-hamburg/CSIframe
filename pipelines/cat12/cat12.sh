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
#       - cat12_standalone.sif                                                                                    #
###################################################################################################################

# Define subject array
input_subject_array=($@)

# Define environment
#########################
module load zip

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
T1=${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz
T1_orig=data/fmriprep/$1/ses-$SESSION/anat/$T1

# Define outputs
T1_unzipped=${1}_ses-${SESSION}_desc-preproc_T1w.nii
cp -rf $T1_orig $TMP_DIR
gzip -dc $TMP_DIR/$T1 > $TMP_DIR/T1.nii
GM_SEGMENTS=mri/mwp1T1.nii

# Define commands
CMD_SEGMENT="cat_standalone.sh -b $CAT_CODE_DIR/cat_standalone_segment.txt /tmp_dir/T1.nii"
CMD_SMOOTH="cat_standalone.sh -b $CAT_CODE_DIR/cat_standalone_smooth.txt /tmp_dir/$GM_SEGMENTS"

# Execute 
$singularity $CAT_CONTAINER \
/bin/bash -c "$CMD_SEGMENT; $CMD_SMOOTH"

rm -rf $TMP_DIR/$T1_unzipped $TMP_DIR/$T1
cp -ruvf $TMP_DIR/* $OUT_DIR
###############################################################################################################################################################