#!/usr/bin/env bash

###################################################################################################################
# FBA based on https://mrtrix.readthedocs.io/en/latest/fixel_based_analysis/st_fibre_density_cross-section.html   #
#                                                                                                                 #
# Step 4:                                                                                                         #
#       - Fixel metrics 2 voxel maps                                                                              #
#       - FA to template and averaging                                                                            #
#       - FA AVG 2 MNI and atlas 2 template                                                                       #
#       - Voxel maps 2 MNI                                                                                        #
#       - Freewater 2 template                                                                                    #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - qsiprep                                                                                                 #
#       - previous fba steps                                                                                      #
#       - freewater                                                                                               #
#   [container]                                                                                                   #
#       - mrtrix3-3.0.2.sif                                                                                       #
#       - mrtrix3tissue-5.2.8.sif                                                                                 #
#       - tractseg-master.sif                                                                                     #
#       - fsl-6.0.3                                                                                               #
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
container_mrtrix3tissue=mrtrix3tissue-5.2.8
container_tractseg=tractseg-master
container_fsl=fsl-6.0.3

singularity_mrtrix3="singularity run --cleanenv --no-home --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_mrtrix3" 

singularity_mrtrix3tissue="singularity run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_mrtrix3tissue" 

singularity_tractseg="singularity run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_tractseg" 

singularity_fsl="singularity run --cleanenv --no-home --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_fsl"

parallel="parallel --ungroup --delay 0.2 -j16 --joblog $CODE_DIR/log/parallel_runtask.log"

# Define subject array
input_subject_array=($@)

#########################
# FIXEL METRICS 2 VOXEL
#########################

# Input
#########################
FD_SMOOTH_DIR=$FBA_GROUP_DIR/fd_smooth
LOG_FC_SMOOTH_DIR=$FBA_GROUP_DIR/log_fc_smooth
FDC_SMOOTH_DIR=$FBA_GROUP_DIR/fdc_smooth

# Output
#########################
FD_VOXEL=$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-voxelmap_fd.nii.gz
LOG_FC_VOXEL=$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-voxelmap_logfc.nii.gz
FDC_VOXEL=$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-voxelmap_fdc.nii.gz
COMPLEXITY_VOXEL=$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-voxelmap_complexity.nii.gz

# Command
#########################
CMD_FIX2VOX_FD="fixel2voxel $FD_SMOOTH_DIR/{}.mif mean $FD_VOXEL -force"
CMD_FIX2VOX_LOG_FC="fixel2voxel $LOG_FC_SMOOTH_DIR/{}.mif mean $LOG_FC_VOXEL -force"
CMD_FIX2VOX_FDC="fixel2voxel $FDC_SMOOTH_DIR/{}.mif mean $FDC_VOXEL -force"
CMD_FIX2VOX_COMPLEXITY="fixel2voxel $FD_SMOOTH_DIR/{}.mif complexity $COMPLEXITY_VOXEL -force"

# Execution
#########################
$parallel "$singularity_mrtrix3 $CMD_FIX2VOX_FD" ::: ${input_subject_array[@]}
$parallel "$singularity_mrtrix3 $CMD_FIX2VOX_LOG_FC" ::: ${input_subject_array[@]}
$parallel "$singularity_mrtrix3 $CMD_FIX2VOX_FDC" ::: ${input_subject_array[@]}
$parallel "$singularity_mrtrix3 $CMD_FIX2VOX_COMPLEXITY" ::: ${input_subject_array[@]}


#########################
# FA TO TEMPLATE + AVG
#########################

FA_TEMP_DIR=$FBA_DIR/derivatives/fa_template
TEMP2MNI_DIR=$FBA_DIR/derivatives/temp2mni
[ ! -d $FA_TEMP_DIR ] && mkdir -p $FA_TEMP_DIR/fa
[ ! -d $TEMP2MNI_DIR ] && mkdir $TEMP2MNI_DIR

# Input
#########################
FA="$DATA_DIR/freewater/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-T1w_desc-DTINoNeg_FA.nii.gz"
SUB2TEMP_WARP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_from-subject_to-fodtemplate_warp.mif"
FA_MNI_TARGET="$ENV_DIR/standard/FSL_HCP1065_FA_1mm.nii.gz"

# Output
#########################
FA_TEMP="$FA_TEMP_DIR/fa/{}_ses-${SESSION}_space-fodtemplate_desc-DTINoNeg_FA.nii.gz"
FA_AVG_TEMP="$FA_TEMP_DIR/FA_averaged.nii.gz"

# Command
#########################
CMD_MRTRANSFORM="mrtransform $FA -warp $SUB2TEMP_WARP $FA_TEMP -force"
CMD_AVG="mrmath $(find $FA_TEMP_DIR -name "sub-*") mean $FA_AVG_TEMP -force"
CMD_THRESH="fslmaths $FA_AVG_TEMP -thr 0 $FA_AVG_TEMP"

# Execution
#########################
$parallel "$singularity_mrtrix3 $CMD_MRTRANSFORM" ::: ${input_subject_array[@]}
$singularity_mrtrix3 $CMD_AVG
$singularity_fsl $CMD_THRESH

#########################
# Individual FA maps (T1w space) to FA_averaged (fodtemplate space)
#########################

# Input
#########################
FA="$DATA_DIR/freewater/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-T1w_desc-DTINoNeg_FA.nii.gz"
FA_AVG_TEMP="$FA_TEMP_DIR/FA_averaged.nii.gz"

# Output
#########################
FA2TEMP_WARP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_desc-dwi_from-T1w_to-fodtemplate_Composite.h5"
FA_TEMPLATE_SPACE="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-DTINoNeg_FA.nii.gz"

# Command
#########################
CMD_FA2TEMP="antsRegistration \
    --output [ $FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_desc-dwi_from-T1w_to-fodtemplate_, $FA_TEMPLATE_SPACE ] \
    --collapse-output-transforms 0 \
    --dimensionality 3 \
    --initial-moving-transform [ $FA_AVG_TEMP, $FA, 1 ] \
    --initialize-transforms-per-stage 0 \
    --interpolation Linear \
    --transform Rigid[ 0.1 ] \
    --metric MI[ $FA_AVG_TEMP, $FA, 1, 32, Regular, 0.25 ] \
    --convergence [ 10000x111110x11110x100, 1e-08, 10 ] \
    --smoothing-sigmas 3.0x2.0x1.0x0.0vox \
    --shrink-factors 8x4x2x1 \
    --use-estimate-learning-rate-once 1 \
    --use-histogram-matching 1 \
    --transform Affine[ 0.1 ] \
    --metric MI[ $FA_AVG_TEMP, $FA, 1, 32, Regular, 0.25 ] \
    --convergence [ 10000x111110x11110x100, 1e-08, 10 ] \
    --smoothing-sigmas 3.0x2.0x1.0x0.0vox \
    --shrink-factors 8x4x2x1 \
    --use-estimate-learning-rate-once 1 \
    --use-histogram-matching 1 \
    --transform SyN[ 0.2, 3.0, 0.0 ] \
    --metric CC[ $FA_AVG_TEMP, $FA, 1, 4 ] \
    --convergence [ 100x50x30x20, 1e-08, 10 ] \
    --smoothing-sigmas 3.0x2.0x1.0x0.0vox \
    --shrink-factors 8x4x2x1 \
    --use-estimate-learning-rate-once 1 \
    --use-histogram-matching 1 -v \
    --winsorize-image-intensities [ 0.005, 0.995 ] \
    --write-composite-transform 1"

# Execution
#########################
$parallel "$singularity_mrtrix3 $CMD_FA2TEMP" ::: ${input_subject_array[@]}

#########################
# FA_AVG_TEMP 2 MNI + ATLAS 2 TEMP
#########################

# Input
#########################
FA_MNI_TARGET="envs/standard/FSL_HCP1065_FA_1mm.nii.gz"
ATLAS_MNI="envs/standard/schaefer/Schaefer2018_{1}Parcels_{2}Networks_order_FSLMNI152_1mm.nii.gz"
FA_AVG_TEMP="$FA_TEMP_DIR/FA_averaged.nii.gz"

# Output
#########################
FA_MNI="$FA_TEMP_DIR/FA_averaged_in_mni.nii.gz"
MNI2TEMP_WARP="$TEMP2MNI_DIR/TEMP2MNI_InverseComposite.h5"
#FA_TEMP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-FWcorrected_FA.nii.gz"
ATLAS_TEMP="$TEMP2MNI_DIR/Schaefer2018_{1}Parcels_{2}Networks_order_FSLMNI152_space-fodtemplate_1mm.nii.gz"

# Command
#########################
CMD_TEMP2MNI="
antsRegistration \
    --output [ $TEMP2MNI_DIR/TEMP2MNI_, $FA_TEMP_DIR/FA_averaged_in_mni.nii.gz ] \
    --collapse-output-transforms 0 \
    --dimensionality 3 \
    --initial-moving-transform [ $FA_MNI_TARGET, $FA_AVG_TEMP, 1 ] \
    --initialize-transforms-per-stage 0 \
    --interpolation Linear \
    --transform Rigid[ 0.1 ] \
    --metric MI[ $FA_MNI_TARGET, $FA_AVG_TEMP, 1, 32, Regular, 0.25 ] \
    --convergence [ 10000x111110x11110x100, 1e-08, 10 ] \
    --smoothing-sigmas 3.0x2.0x1.0x0.0vox \
    --shrink-factors 8x4x2x1 \
    --use-estimate-learning-rate-once 1 \
    --use-histogram-matching 1 \
    --transform Affine[ 0.1 ] \
    --metric MI[ $FA_MNI_TARGET, $FA_AVG_TEMP, 1, 32, Regular, 0.25 ] \
    --convergence [ 10000x111110x11110x100, 1e-08, 10 ] \
    --smoothing-sigmas 3.0x2.0x1.0x0.0vox \
    --shrink-factors 8x4x2x1 \
    --use-estimate-learning-rate-once 1 \
    --use-histogram-matching 1 \
    --transform SyN[ 0.2, 3.0, 0.0 ] \
    --metric CC[ $FA_MNI_TARGET, $FA_AVG_TEMP, 1, 4 ] \
    --convergence [ 100x50x30x20, 1e-08, 10 ] \
    --smoothing-sigmas 3.0x2.0x1.0x0.0vox \
    --shrink-factors 8x4x2x1 \
    --use-estimate-learning-rate-once 1 \
    --use-histogram-matching 1 -v \
    --winsorize-image-intensities [ 0.005, 0.995 ] \
    --write-composite-transform 1
"

CMD_ATLAS2TEMP="
antsApplyTransforms -d 3 -e 3 -n Linear \
            -i $ATLAS_MNI \
            -r $FA_AVG_TEMP \
            -o $ATLAS_TEMP \
            -t $MNI2TEMP_WARP
"

# Execution
#########################
$singularity_mrtrix3 $CMD_TEMP2MNI
$parallel $singularity_mrtrix3 $CMD_ATLAS2TEMP ::: 100 200 400 600 ::: 7 17


#########################
# VOXELMAPS 2 MNI
#########################

# Input
#########################
TEMP2MNI_WARP="$TEMP2MNI_DIR/TEMP2MNI_Composite.h5"
FD_VOXEL=$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-voxelmap_fd.nii.gz
LOG_FC_VOXEL=$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-voxelmap_logfc.nii.gz
FDC_VOXEL=$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-voxelmap_fdc.nii.gz
COMPLEXITY_VOXEL=$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-voxelmap_complexity.nii.gz



# Output
#########################
FD_VOXEL_MNI=$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-MNI_desc-voxelmap_fd.nii.gz
LOG_FC_VOXEL_MNI=$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-MNI_desc-voxelmap_logfc.nii.gz
FDC_VOXEL_MNI=$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-MNI_desc-voxelmap_fdc.nii.gz
COMPLEXITY_VOXEL_MNI=$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-MNI_desc-voxelmap_complexity.nii.gz

# Command
#########################
CMD_FD2MNI="
antsApplyTransforms -d 3 -e 3 -n Linear \
            -i $FD_VOXEL \
            -r $FA_MNI \
            -o $FD_VOXEL_MNI \
            -t $TEMP2MNI_WARP
"

CMD_LOGFC2MNI="
antsApplyTransforms -d 3 -e 3 -n Linear \
            -i $LOG_FC_VOXEL \
            -r $FA_MNI \
            -o $LOG_FC_VOXEL_MNI \
            -t $TEMP2MNI_WARP
"

CMD_FDC2MNI="
antsApplyTransforms -d 3 -e 3 -n Linear \
            -i $FDC_VOXEL \
            -r $FA_MNI \
            -o $FDC_VOXEL_MNI \
            -t $TEMP2MNI_WARP
"

CMD_COMPLEXITY2MNI="
antsApplyTransforms -d 3 -e 3 -n Linear \
            -i $COMPLEXITY_VOXEL \
            -r $FA_MNI \
            -o $COMPLEXITY_VOXEL_MNI \
            -t $TEMP2MNI_WARP
"

# Execution
#########################
$parallel $singularity_mrtrix3 $CMD_FD2MNI ::: ${input_subject_array[@]}
$parallel $singularity_mrtrix3 $CMD_LOGFC2MNI ::: ${input_subject_array[@]}
$parallel $singularity_mrtrix3 $CMD_FDC2MNI ::: ${input_subject_array[@]}
$parallel $singularity_mrtrix3 $CMD_COMPLEXITY2MNI ::: ${input_subject_array[@]}


#########################
# DTI 2 TEMPLATE
#########################

FW_DIR="$DATA_DIR/freewater/{}/ses-$SESSION/dwi/"

# Input
#########################
#FA="$FW_DIR/{}_ses-${SESSION}_space-T1w_desc-DTINoNeg_FA.nii.gz"
FA_TEMP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-DTINoNeg_FA.nii.gz"
FA2TEMP_WARP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_desc-dwi_from-T1w_to-fodtemplate_Composite.h5"
FAt="$FW_DIR/{}_ses-${SESSION}_space-T1w_desc-FWcorrected_FA.nii.gz"
MD="$FW_DIR/{}_ses-${SESSION}_space-T1w_desc-DTINoNeg_MD.nii.gz"
MDt="$FW_DIR/{}_ses-${SESSION}_space-T1w_desc-FWcorrected_MD.nii.gz"
AD="$FW_DIR/{}_ses-${SESSION}_space-T1w_desc-DTINoNeg_L1.nii.gz"
ADt="$FW_DIR/{}_ses-${SESSION}_space-T1w_desc-FWcorrected_L1.nii.gz"
RD="$FW_DIR/{}_ses-${SESSION}_space-T1w_desc-DTINoNeg_RD.nii.gz"
RDt="$FW_DIR/{}_ses-${SESSION}_space-T1w_desc-FWcorrected_RD.nii.gz"
FW="$FW_DIR/{}_ses-${SESSION}_space-T1w_FW.nii.gz"

# Output
#########################
FAt_TEMP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-FWcorrected_FA.nii.gz"
MD_TEMP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-DTINoNeg_MD.nii.gz"
MDt_TEMP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-FWcorrected_MD.nii.gz"
AD_TEMP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-DTINoNeg_L1.nii.gz"
ADt_TEMP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-FWcorrected_L1.nii.gz"
RD_TEMP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-DTINoNeg_RD.nii.gz"
RDt_TEMP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-FWcorrected_RD.nii.gz"
FW_TEMP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_FW.nii.gz"

CMD_FAt2TEMP="
antsApplyTransforms -d 3 -e 3 -n Linear \
            -i $FAt \
            -r $FA_TEMP \
            -o $FAt_TEMP \
            -t $FA2TEMP_WARP
"
CMD_AD2TEMP="
antsApplyTransforms -d 3 -e 3 -n Linear \
            -i $AD \
            -r $FA_TEMP \
            -o $AD_TEMP \
            -t $FA2TEMP_WARP
"
CMD_ADt2TEMP="
antsApplyTransforms -d 3 -e 3 -n Linear \
            -i $ADt \
            -r $FA_TEMP \
            -o $ADt_TEMP \
            -t $FA2TEMP_WARP
"
CMD_RD2TEMP="
antsApplyTransforms -d 3 -e 3 -n Linear \
            -i $RD \
            -r $FA_TEMP \
            -o $RD_TEMP \
            -t $FA2TEMP_WARP
"
CMD_RDt2TEMP="
antsApplyTransforms -d 3 -e 3 -n Linear \
            -i $RDt \
            -r $FA_TEMP \
            -o $RDt_TEMP \
            -t $FA2TEMP_WARP
"

CMD_MD2TEMP="
antsApplyTransforms -d 3 -e 3 -n Linear \
            -i $MD \
            -r $FA_TEMP \
            -o $MD_TEMP \
            -t $FA2TEMP_WARP
"

CMD_MDt2TEMP="
antsApplyTransforms -d 3 -e 3 -n Linear \
            -i $MDt \
            -r $FA_TEMP \
            -o $MDt_TEMP \
            -t $FA2TEMP_WARP
"

CMD_FW2TEMP="
antsApplyTransforms -d 3 -e 3 -n Linear \
            -i $FW \
            -r $FA_TEMP \
            -o $FW_TEMP \
            -t $FA2TEMP_WARP
"

# Execution
#########################
$parallel $singularity_mrtrix3 $CMD_FAt2TEMP ::: ${input_subject_array[@]}
$parallel $singularity_mrtrix3 $CMD_MD2TEMP ::: ${input_subject_array[@]}
$parallel $singularity_mrtrix3 $CMD_MDt2TEMP ::: ${input_subject_array[@]}
$parallel $singularity_mrtrix3 $CMD_AD2TEMP ::: ${input_subject_array[@]}
$parallel $singularity_mrtrix3 $CMD_ADt2TEMP ::: ${input_subject_array[@]}
$parallel $singularity_mrtrix3 $CMD_RD2TEMP ::: ${input_subject_array[@]}
$parallel $singularity_mrtrix3 $CMD_RDt2TEMP ::: ${input_subject_array[@]}
$parallel $singularity_mrtrix3 $CMD_FW2TEMP ::: ${input_subject_array[@]}
