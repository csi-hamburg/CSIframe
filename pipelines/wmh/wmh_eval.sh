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
OUT_DIR=data/$PIPELINE/$1/ses-${SESSION}/anat/
ALGORITHM_OUT_DIR=$OUT_DIR/$ALGORITHM/
MAN_SEGMENTATION_DIR=$PROJ_DIR/../CSI_WMH_MASKS_pseud/HCHS/

# Define inputs
SEGMENTATION=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
SEGMENTATION_MAN=$MAN_SEGMENTATION_DIR/$1/anat/${1}_DC_FLAIR_label3.nii.gz
    
# Define outputs
JSON_FILE=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_desc-diceindex_desc-${ALGORITHM}.txt

# Define commands
CMD_CALCULATE_DICE="mri_seg_overlap $SEGMENTATION $SEGMENTATION_MAN -o $JSON_FILE"

# Execute
$singularity $FREESURFER_CONTAINER /bin/bash -c "$CMD_CALCULATE_DICE"

