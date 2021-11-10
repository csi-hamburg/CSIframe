#!/bin/bash
set -e

#####################################################################################
# Warp of freewater pipeline results to standard space                              #
#                                                                                   #
# Pipeline specific dependencies:                                                   #
#   [pipelines which need to be run first]                                          #
#       - freewater <- qsiprep                                                      #                                         
#   [container/code]                                                                #                                                          #    
#       - mrtrix3-3.0.2                                                             # 
#####################################################################################

# Define environment
#########################
module load parallel

FW_DIR=$DATA_DIR/freewater/$1/ses-$SESSION/dwi/
[ ! -d $FW_DIR ] && mkdir -p $FW_DIR
container_mrtrix3=mrtrix3-3.0.2      
export SINGULARITYENV_MRTRIX_TMPFILE_DIR=$TMP_DIR


singularity_mrtrix3="singularity run --cleanenv --userns \
    -B . \
    -B $PROJ_DIR \
    -B $SCRATCH_DIR:/tmp \
    -B $(readlink -f $ENV_DIR) \
    $ENV_DIR/$container_mrtrix3" 

parallel="parallel --ungroup --delay 0.2 --joblog $CODE_DIR/log/parallel_runtask.log"


#########################
# FW OUTPUTS 2 MNI
#########################

# Input
#########################
FA_MNI_TARGET="$ENV_DIR/standard/FSL_HCP1065_FA_1mm.nii.gz"
FA="$FW_DIR/${1}_ses-${SESSION}_space-T1w_desc-DTINoNeg_FA.nii.gz"
FAt="$FW_DIR/${1}_ses-${SESSION}_space-T1w_desc-FWcorrected_FA.nii.gz"
AD="$FW_DIR/${1}_ses-${SESSION}_space-T1w_desc-DTINoNeg_AD.nii.gz"
ADt="$FW_DIR/${1}_ses-${SESSION}_space-T1w_desc-FWcorrected_AD.nii.gz"
RD="$FW_DIR/${1}_ses-${SESSION}_space-T1w_desc-DTINoNeg_RD.nii.gz"
RDt="$FW_DIR/${1}_ses-${SESSION}_space-T1w_desc-FWcorrected_RD.nii.gz"
MD="$FW_DIR/${1}_ses-${SESSION}_space-T1w_desc-DTINoNeg_MD.nii.gz"
MDt="$FW_DIR/${1}_ses-${SESSION}_space-T1w_desc-FWcorrected_MD.nii.gz"
FW="$FW_DIR/${1}_ses-${SESSION}_space-T1w_FW.nii.gz"


# Output
#########################
FA2MNI_WARP="$FW_DIR/${1}_ses-${SESSION}_desc-dwi_from-T1w_to-MNI_Composite.h5"
FA_MNI="$FW_DIR/${1}_ses-${SESSION}_space-MNI_desc-DTINoNeg_FA.nii.gz"
FAt_MNI="$FW_DIR/${1}_ses-${SESSION}_space-MNI_desc-FWcorrected_FA.nii.gz"
AD_MNI="$FW_DIR/${1}_ses-${SESSION}_space-MNI_desc-DTINoNeg_FA.nii.gz"
ADt_MNI="$FW_DIR/${1}_ses-${SESSION}_space-MNI_desc-FWcorrected_FA.nii.gz"
RD_MNI="$FW_DIR/${1}_ses-${SESSION}_space-MNI_desc-DTINoNeg_FA.nii.gz"
RDt_MNI="$FW_DIR/${1}_ses-${SESSION}_space-MNI_desc-FWcorrected_FA.nii.gz"
MD_MNI="$FW_DIR/${1}_ses-${SESSION}_space-MNI_desc-DTINoNeg_MD.nii.gz"
MDt_MNI="$FW_DIR/${1}_ses-${SESSION}_space-MNI_desc-FWcorrected_MD.nii.gz"
FW_MNI="$FW_DIR/${1}_ses-${SESSION}_space-MNI_FW.nii.gz"

# Command
#########################
CMD_TEMP2MNI="
antsRegistration \
    --output [ $FW_DIR/${1}_ses-${SESSION}_desc-dwi_from-T1w_to-MNI_, $FA_MNI ] \
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

# Execution
#########################
$singularity_mrtrix3 $CMD_TEMP2MNI
$singularity_mrtrix3 $CMD_FAt2MNI
$singularity_mrtrix3 $CMD_AD2MNI
$singularity_mrtrix3 $CMD_ADt2MNI
$singularity_mrtrix3 $CMD_RD2MNI
$singularity_mrtrix3 $CMD_RDt2MNI
$singularity_mrtrix3 $CMD_MD2MNI
$singularity_mrtrix3 $CMD_MDt2MNI
$singularity_mrtrix3 $CMD_FW2MNI
