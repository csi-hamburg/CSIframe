#!/bin/bash
set -e

#####################################################################################
# Submission script for free-water elimination based on implementation in Matlab    #
# by Ofer Pasternak and Fan Zhang (see below) and estimation of diffusion measures  #
# based on free-water corrected and negative eigenvalue corrected tensors.          #
#                                                                                   #
# 'FreeWater_OneCase.m' was adjusted to comply with BIDS naming convention          #
# (https://bids.neuroimaging.io/)                                                   #
# 'load_nifti.m' was adjusted to gunzip to ./                                       #
#####################################################################################

##########################################################################################
# The free-water imaging implementation is based on the following paper. Please refer    #
# to the paper for method details, and cite the paper if you use this code in your work. #
#                                                                                        #  
#    Pasternak, O., Sochen, N., Gur, Y., Intrator, N. and Assaf, Y., 2009.               #  
#    Free water elimination and mapping from diffusion MRI.                              #
#    Magnetic Resonance in Medicine, 62(3), pp.717-730.                                  #
#                                                                                        #
# Date: October, 2018                                                                    #
# Authors: Fan Zhang (fzhang@bwh.harvard.edu) and Ofer Pasternak (ofer@bwh.harvard.edu)  #
##########################################################################################

#########################################
# Load modules and set up datalad clone #
#########################################

# Load matlab module
module load matlab/2019b

# Get input and output dataset directory trees
datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/qsiprep
datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/qsiprep/${1}
datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/freewater
datalad get -n -J $SLURM_CPUS_PER_TASK $CLONE_DATA_DIR/freewater/${1}

# Checkout unique branches (names derived from jobIDs) of result subdatasets

########################################################################
# Enables pushing the results without interference from other jobs.    #
# In a setup with no subdatasets, "-C <subds-name>" would be stripped, #
# and a new branch would be checked out in the superdataset instead.   #
########################################################################

git -C $CLONE_DATA_DIR/freewater checkout -b "$PIPE_ID"
git -C $CLONE_DATA_DIR/freewater/$1 checkout -b "$PIPE_ID"

# Remove job outputs in dataset clone to prevent issues when rerunning
# $1/* matches all content in subject subdataset but dotfiles (.git, .datalad, .gitattributes)
(cd $CLONE_DATA_DIR/freewater && rm -rf $1/*)

##############################
# Run free-water elimination #
##############################

##############################################################################################
# The following output images will be generated:                                             #
#  *_FW.nii.gz                      - The free-water map                                     #
#  *_desc-FWCorrected_tensor.nii.gz - The tensor map after correcting for free-water         #
#  *_NegativeEigMap.nii.gz          - The map (mask) of voxels with negative DTI eigenvalues #
#  *_desc-DTINoNeg_tensor.nii.gz    - The tensor map after correcting for negative DTI       #
#                                     eigenvalues but before correcting for free-water       # 
##############################################################################################

# Define inputs and output
datalad get $CLONE_DATA_DIR/freewater/code/Free-Water-master
FW_CODE_DIR=$CLONE_DATA_DIR/freewater/code/Free-Water-master

INPUT_DWI=$CLONE_DATA_DIR/qsiprep/$1/ses-${SESSION}/dwi/${1}_ses-${SESSION}_dir-AP_space-T1w_desc-preproc_dwi.nii.gz
INPUT_BVAL=$CLONE_DATA_DIR/qsiprep/$1/ses-${SESSION}/dwi/${1}_ses-${SESSION}_dir-AP_space-T1w_desc-preproc_dwi.bval
INPUT_BVEC=$CLONE_DATA_DIR/qsiprep/$1/ses-${SESSION}/dwi/${1}_ses-${SESSION}_dir-AP_space-T1w_desc-preproc_dwi.bvec
INPUT_MASK=$CLONE_DATA_DIR/qsiprep/$1/ses-${SESSION}/dwi/${1}_ses-${SESSION}_dir-AP_space-T1w_desc-brain_mask.nii.gz

mkdir -p $CLONE_DATA_DIR/freewater/$1/ses-${SESSION}/dwi
FW_OUTPUT_DIR=$CLONE_DATA_DIR/freewater/$1/ses-${SESSION}/dwi

# execute command with datalad run
datalad run -m "${PIPE_ID} freewater" \
   --explicit \
   --input $CLONE_DATA_DIR/qsiprep/$1 \
   --output $CLONE_DATA_DIR/freewater/$1 \
   matlab \
      -nosplash \
      -nodesktop \
      -nojvm \
      -batch \
      "cd('$FW_CODE_DIR'); FreeWater_OneCase('$1', 'ses-${SESSION}', '$INPUT_DWI', '$INPUT_BVAL', '$INPUT_BVEC', '$INPUT_MASK', '$FW_OUTPUT_DIR'); cd('$CLONE'); quit"

######################################################################################
# Estimate free-water corrected and negative eigenvalue corrected diffusion measures #
######################################################################################

# Define inputs and outputs
INPUT_TENSOR_CORRECTED=$FW_OUTPUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-FWCorrected_tensor.nii.gz
INPUT_TENSOR_NONEG=$FW_OUTPUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-DTINoNeg_tensor.nii.gz
OUTPUT_FWC_DIFF=$FW_OUTPUT_DIR/${1}_ses-${SESSION}_desc-FWcorrected
OUTPUT_NONEG_DIFF=$FW_OUTPUT_DIR/${1}_ses-${SESSION}_desc-DTINoNeg

# Calculate free-water corrected diffusion measures (note, L1 = AD)
###################################################################

# Define command
CMD_FWC="
   fslmaths \
      $INPUT_TENSOR_CORRECTED \
      -mas $INPUT_MASK \
      -tensor_decomp \
      $OUTPUT_FWC_DIFF; \
   fslmaths \
      ${OUTPUT_FWC_DIFF}_L2.nii.gz \
      -add ${OUTPUT_FWC_DIFF}_L3.nii.gz \
      -div 2 \
      ${OUTPUT_FWC_DIFF}_RD.nii.gz"

# Execute command with datalad run
datalad run -m "${PIPE_ID} calculate free-water corrected diffusion measures" \
   --explicit \
   --input $INPUT_TENSOR_CORRECTED -i $INPUT_MASK \
   --output $FW_OUTPUT_DIR \
      singularity run --cleanenv --userns \
      -B .\
      -B $PROJ_DIR \
      -B $SCRATCH_DIR:/tmp \
      $ENV_DIR/fsl-6.0.3 /bin/bash -c "$CMD_FWC"

# Calculate negative eigenvalue corrected diffusion measures (note, L1 = AD)
############################################################################

# Define command
CMD_NONEG="
   fslmaths \
      $INPUT_TENSOR_NONEG \
      -mas $INPUT_MASK \
      -tensor_decomp \
      $OUTPUT_NONEG_DIFF; \
   fslmaths \
      ${OUTPUT_NONEG_DIFF}_L2.nii.gz \
      -add ${OUTPUT_NONEG_DIFF}_L3.nii.gz \
      -div 2 \
      ${OUTPUT_NONEG_DIFF}_RD.nii.gz"

# Execute command with datalad run
datalad run -m "${PIPE_ID} calculate negative eigenvalue corrected diffusion measures" \
   --explicit \
   --input $INPUT_TENSOR_NONEG -i $INPUT_MASK \
   --output $FW_OUTPUT_DIR \
      singularity run --cleanenv --userns \
      -B . \
      -B $PROJ_DIR \
      -B $SCRATCH_DIR:/tmp \
      $ENV_DIR/fsl-6.0.3 /bin/bash -c "$CMD_NONEG"

###############################################
# Push results from clone to original dataset #
###############################################

flock $DSLOCKFILE datalad push -d $CLONE_DATA_DIR/freewater --to origin
flock $DSLOCKFILE datalad push -d $CLONE_DATA_DIR/freewater/${1} --to origin