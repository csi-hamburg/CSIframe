#!/usr/bin/env bash

###################################################################################################################
# Submission script for free-water elimination based on implementation in Matlab                                  #
# by Ofer Pasternak and Fan Zhang (see below) and estimation of diffusion measures                                #
# based on free-water corrected and negative eigenvalue corrected tensors.                                        #
#                                                                                                                 #
# 'FreeWater_OneCase.m' was adjusted to comply with BIDS naming convention                                        #
# (https://bids.neuroimaging.io/)                                                                                 #
# 'load_nifti.m' was adjusted to gunzip to ./                                                                     #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - qsiprep                                                                                                 #                                         
#   [containers/code]                                                                                             # 
#       - Free-Water-master                                                                                       #                              
#       - fsl-6.0.3                                                                                               #      
#       - mrtrix3-3.0.2                                                                                           #
#                                                                                                                 #
# The following output images will be generated:                                                                  #
#  *_FW.nii.gz                      - The free-water map                                                          #
#  *_desc-FWCorrected_tensor.nii.gz - The tensor map after correcting for free-water                              #
#  *_NegativeEigMap.nii.gz          - The map (mask) of voxels with negative DTI eigenvalues                      #
#  *_desc-DTINoNeg_tensor.nii.gz    - The tensor map after correcting for negative DTI                            #
#                                     eigenvalues but before correcting for free-water                            #
#                                                                                                                 # 
###################################################################################################################

###################################################################################################################
# The free-water imaging implementation is based on the following paper. Please refer                             #
# to the paper for method details, and cite the paper if you use this code in your work.                          #
#                                                                                                                 #  
#    Pasternak, O., Sochen, N., Gur, Y., Intrator, N. and Assaf, Y., 2009.                                        #  
#    Free water elimination and mapping from diffusion MRI.                                                       #
#    Magnetic Resonance in Medicine, 62(3), pp.717-730.                                                           #
#                                                                                                                 #
###################################################################################################################

# Get verbose outputs
#####################

set -x

# Define subject specific temporary directory on $SCRATCH_DIR
#############################################################

export TMP_DIR=$SCRATCH_DIR/$1/tmp/;   [ ! -d $TMP_DIR ] && mkdir -p $TMP_DIR
TMP_IN=$TMP_DIR/input;                 [ ! -d $TMP_IN ] && mkdir -p $TMP_IN
TMP_OUT=$TMP_DIR/output;               [ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT

###################################################################################################################

# Define environment
####################

module load matlab/2019b
module load singularity

export SINGULARITYENV_MRTRIX_TMPFILE_DIR=/tmp
container_mrtrix3=mrtrix3-3.0.2      
singularity_mrtrix3="singularity run --cleanenv --no-home --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_mrtrix3" 

container_fsl=fsl-6.0.3
singularity_fsl="singularity run --cleanenv --no-home --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_fsl" 

# Define input and output
##########################

FW_CODE_DIR=$ENV_DIR/freewater/
FW_OUTPUT_DIR=$DATA_DIR/freewater/$1/ses-${SESSION}/dwi

# Check whether output directory already exists: yes > remove and create new output directory

if [ ! -d $FW_OUTPUT_DIR ]; then

   mkdir -p $FW_OUTPUT_DIR

else 
   
   rm -rf $FW_OUTPUT_DIR
   mkdir -p $FW_OUTPUT_DIR

fi

INPUT_DWI=$DATA_DIR/qsiprep/$1/ses-${SESSION}/dwi/${1}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_dwi.nii.gz
INPUT_DWI_MIF=$FW_OUTPUT_DIR/${1}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_dwi.mif
INPUT_MASK=$DATA_DIR/qsiprep/$1/ses-${SESSION}/dwi/${1}_ses-${SESSION}_acq-AP_space-T1w_desc-brain_mask.nii.gz
INPUT_BVEC_BVAL=$DATA_DIR/qsiprep/$1/ses-${SESSION}/dwi/${1}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_dwi.b
INPUT_BVEC=$FW_OUTPUT_DIR/${1}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_dwi_desc-mrconvert.bvec
INPUT_BVAL=$FW_OUTPUT_DIR/${1}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_dwi_desc-mrconvert.bval

###################################################################################################################
#                                   Run free-water  pipeline                                                      #
###################################################################################################################

###################################################################################
# Convert bvals and bvecs from .b (mrtrix format) to .bval and .bvec (fsl format) #
###################################################################################

# Define command
################

CMD_CONVERT="mrconvert \
   -force \
   -grad $INPUT_BVEC_BVAL \
   -export_grad_fsl $INPUT_BVEC $INPUT_BVAL \
   $INPUT_DWI $INPUT_DWI_MIF"

# Execute command
#################

$singularity_mrtrix3 $CMD_CONVERT

##############################
# Run free-water elimination #
############################## 

pushd $FW_CODE_DIR

matlab \
   -nosplash \
   -nodesktop \
   -nojvm \
   -batch \
   "FreeWater_OneCase('$1', 'ses-${SESSION}', '$INPUT_DWI', '$INPUT_BVAL', '$INPUT_BVEC', '$INPUT_MASK', '$FW_OUTPUT_DIR'); quit"

popd

######################################################################################
# Estimate free-water corrected and negative eigenvalue corrected diffusion measures #
######################################################################################

# Define inputs and outputs
###########################

INPUT_TENSOR_CORRECTED=$FW_OUTPUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-FWCorrected_tensor.nii.gz
INPUT_TENSOR_NONEG=$FW_OUTPUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-DTINoNeg_tensor.nii.gz
OUTPUT_FWC_DIFF=$FW_OUTPUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-FWcorrected
OUTPUT_NONEG_DIFF=$FW_OUTPUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-DTINoNeg

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

# Execute command

$singularity_fsl /bin/bash -c "$CMD_FWC"

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

# Execute command

$singularity_fsl /bin/bash -c "$CMD_NONEG"

###########################################
# Register free-water output to MNI space #
###########################################

# Define input
##############

FA_MNI_TARGET="$ENV_DIR/standard/FSL_HCP1065_FA_1mm.nii.gz"
FA="$FW_OUTPUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-DTINoNeg_FA.nii.gz"
FAt="$FW_OUTPUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-FWcorrected_FA.nii.gz"
AD="$FW_OUTPUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-DTINoNeg_L1.nii.gz"
ADt="$FW_OUTPUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-FWcorrected_L1.nii.gz"
RD="$FW_OUTPUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-DTINoNeg_RD.nii.gz"
RDt="$FW_OUTPUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-FWcorrected_RD.nii.gz"
MD="$FW_OUTPUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-DTINoNeg_MD.nii.gz"
MDt="$FW_OUTPUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-FWcorrected_MD.nii.gz"
FW="$FW_OUTPUT_DIR/${1}_ses-${SESSION}_space-T1w_FW.nii.gz"


# Define output
###############

FA2MNI_WARP="$FW_OUTPUT_DIR/${1}_ses-${SESSION}_desc-dwi_from-T1w_to-MNI_Composite.h5"
FA_MNI="$FW_OUTPUT_DIR/${1}_ses-${SESSION}_space-MNI_desc-DTINoNeg_FA.nii.gz"
FAt_MNI="$FW_OUTPUT_DIR/${1}_ses-${SESSION}_space-MNI_desc-FWcorrected_FA.nii.gz"
AD_MNI="$FW_OUTPUT_DIR/${1}_ses-${SESSION}_space-MNI_desc-DTINoNeg_L1.nii.gz"
ADt_MNI="$FW_OUTPUT_DIR/${1}_ses-${SESSION}_space-MNI_desc-FWcorrected_L1.nii.gz"
RD_MNI="$FW_OUTPUT_DIR/${1}_ses-${SESSION}_space-MNI_desc-DTINoNeg_RD.nii.gz"
RDt_MNI="$FW_OUTPUT_DIR/${1}_ses-${SESSION}_space-MNI_desc-FWcorrected_RD.nii.gz"
MD_MNI="$FW_OUTPUT_DIR/${1}_ses-${SESSION}_space-MNI_desc-DTINoNeg_MD.nii.gz"
MDt_MNI="$FW_OUTPUT_DIR/${1}_ses-${SESSION}_space-MNI_desc-FWcorrected_MD.nii.gz"
FW_MNI="$FW_OUTPUT_DIR/${1}_ses-${SESSION}_space-MNI_FW.nii.gz"

# Define commands
#################

CMD_TEMP2MNI="
antsRegistration \
    --output [ $FW_OUTPUT_DIR/${1}_ses-${SESSION}_desc-dwi_from-T1w_to-MNI_, $FA_MNI ] \
    --collapse-output-transforms 0 \
    --dimensionality 3 \
    --initial-moving-transform [ $FA_MNI_TARGET, $FA, 1 ] \
    --initialize-transforms-per-stage 0 \
    --interpolation Linear \
    --transform Rigid[ 0.1 ] \
    --metric MI[ $FA_MNI_TARGET, $FA, 1, 32, Regular, 0.25 ] \
    --convergence [ 10000x111110x11110x100, 1e-08, 10 ] \
    --smoothing-sigmas 3.0x2.0x1.0x0.0vox \
    --shrink-factors 8x4x2x1 \
    --use-estimate-learning-rate-once 1 \
    --use-histogram-matching 1 \
    --transform Affine[ 0.1 ] \
    --metric MI[ $FA_MNI_TARGET, $FA, 1, 32, Regular, 0.25 ] \
    --convergence [ 10000x111110x11110x100, 1e-08, 10 ] \
    --smoothing-sigmas 3.0x2.0x1.0x0.0vox \
    --shrink-factors 8x4x2x1 \
    --use-estimate-learning-rate-once 1 \
    --use-histogram-matching 1 \
    --transform SyN[ 0.2, 3.0, 0.0 ] \
    --metric CC[ $FA_MNI_TARGET, $FA, 1, 4 ] \
    --convergence [ 100x50x30x20, 1e-08, 10 ] \
    --smoothing-sigmas 3.0x2.0x1.0x0.0vox \
    --shrink-factors 8x4x2x1 \
    --use-estimate-learning-rate-once 1 \
    --use-histogram-matching 1 -v \
    --winsorize-image-intensities [ 0.005, 0.995 ] \
    --write-composite-transform 1
"

CMD_FAt2MNI="
antsApplyTransforms -d 3 -e 3 -n Linear \
            -i $FAt \
            -r $FA_MNI \
            -o $FAt_MNI \
            -t $FA2MNI_WARP
"
CMD_AD2MNI="
antsApplyTransforms -d 3 -e 3 -n Linear \
            -i $AD \
            -r $FA_MNI \
            -o $AD_MNI \
            -t $FA2MNI_WARP
"
CMD_ADt2MNI="
antsApplyTransforms -d 3 -e 3 -n Linear \
            -i $ADt \
            -r $FA_MNI \
            -o $ADt_MNI \
            -t $FA2MNI_WARP
"
CMD_RD2MNI="
antsApplyTransforms -d 3 -e 3 -n Linear \
            -i $RD \
            -r $FA_MNI \
            -o $RD_MNI \
            -t $FA2MNI_WARP
"
CMD_RDt2MNI="
antsApplyTransforms -d 3 -e 3 -n Linear \
            -i $RDt \
            -r $FA_MNI \
            -o $RDt_MNI \
            -t $FA2MNI_WARP
"

CMD_MD2MNI="
antsApplyTransforms -d 3 -e 3 -n Linear \
            -i $MD \
            -r $FA_MNI_TARGET \
            -o $MD_MNI \
            -t $FA2MNI_WARP
"

CMD_MDt2MNI="
antsApplyTransforms -d 3 -e 3 -n Linear \
            -i $MDt \
            -r $FA_MNI_TARGET \
            -o $MDt_MNI \
            -t $FA2MNI_WARP
"

CMD_FW2MNI="
antsApplyTransforms -d 3 -e 3 -n Linear \
            -i $FW \
            -r $FA_MNI_TARGET \
            -o $FW_MNI \
            -t $FA2MNI_WARP
"

# Execute commands
##################

$singularity_mrtrix3 $CMD_TEMP2MNI
$singularity_mrtrix3 $CMD_FAt2MNI
$singularity_mrtrix3 $CMD_AD2MNI
$singularity_mrtrix3 $CMD_ADt2MNI
$singularity_mrtrix3 $CMD_RD2MNI
$singularity_mrtrix3 $CMD_RDt2MNI
$singularity_mrtrix3 $CMD_MD2MNI
$singularity_mrtrix3 $CMD_MDt2MNI
$singularity_mrtrix3 $CMD_FW2MNI
