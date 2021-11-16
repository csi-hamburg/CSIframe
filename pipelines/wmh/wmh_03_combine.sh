#!/bin/bash

# SET VARIABLES FOR CONTAINER TO BE USED
FSL_VERSION=fsl-6.0.3
FREESURFER_VERSION=freesurfer-7.1.1
MRTRIX_VERSION=mrtrix3-3.0.2
###############################################################################################################################################################
FSL_CONTAINER=$ENV_DIR/$FSL_VERSION
FREESURFER_CONTAINER=$ENV_DIR/$FREESURFER_VERSION
MRTRIX_CONTAINER=$ENV_DIR/$MRTRIX_VERSION
ANTSRNET_CONTAINER=$ENV_DIR/antsrnet
###############################################################################################################################################################
singularity="singularity run --cleanenv --userns -B $(readlink -f $ENV_DIR) -B $PROJ_DIR -B $TMP_DIR/:/tmp"
###############################################################################################################################################################

# Set output directories
ALGORITHM=${ALGORITHM1}X${ALGORITHM2}
OUT_DIR=data/$PIPELINE/$1/ses-${SESSION}/anat/
ALGORITHM_OUT_DIR=$OUT_DIR/$ALGORITHM/

[ ! -d $ALGORITHM_OUT_DIR ] && mkdir -p $ALGORITHM_OUT_DIR

# Define inputs
SEGMENTATION1=$OUT_DIR/$ALGORITHM1/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM1}_mask.nii.gz
SEGMENTATION2=$OUT_DIR/$ALGORITHM2/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM2}_mask.nii.gz

# Define outputs
SEGMENTATION_COMBI=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz

# Define commands
CMD_COMBINE_SEGS="fslmaths $SEGMENTATION1 -add $SEGMENTATION2 $SEGMENTATION_COMBI"

# Execute
$singularity $FSL_CONTAINER /bin/bash -c "$CMD_COMBINE_SEGS"

