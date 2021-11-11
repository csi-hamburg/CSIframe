#!/usr/bin/env bash
set -x

###################################################################################################################
# FBA based on https://mrtrix.readthedocs.io/en/latest/fixel_based_analysis/st_fibre_density_cross-section.html   #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - qsiprep & qsirecon                                                                                      #
#       - freewater (to warp freewater results to group template)                                                 #
#   [container]                                                                                                   #
#       - mrtrix3-3.0.2.sif                                                                                       #
###################################################################################################################

# Define subject array

input_subject_array=($@)

# Define environment
#########################
module load parallel

FW_DIR=$DATA_DIR/freewater
FBA_DIR=$DATA_DIR/fba
FBA_GROUP_DIR=$DATA_DIR/fba/derivatives
TEMPLATE_SUBJECTS_TXT=$FBA_DIR/sourcedata/template_subjects.txt
container_mrtrix3=mrtrix3-3.0.2      
container_mrtrix3tissue=mrtrix3tissue-5.2.8
container_tractseg=tractseg-master
export SINGULARITYENV_MRTRIX_TMPFILE_DIR=$TMP_DIR

[ ! -d $FBA_GROUP_DIR ] && mkdir -p $FBA_GROUP_DIR
singularity_mrtrix3="singularity run --cleanenv --userns \
    -B $(readlink -f $ENV_DIR) \
    -B $PROJ_DIR \
    -B $SCRATCH_DIR:/tmp \
    $ENV_DIR/$container_mrtrix3" 

singularity_mrtrix3tissue="singularity run --cleanenv --userns \
    -B $(readlink -f $ENV_DIR) \
    -B $PROJ_DIR \
    -B $SCRATCH_DIR:/tmp \
    $ENV_DIR/$container_mrtrix3tissue" 

singularity_tractseg="singularity run --cleanenv --userns \
    -B $(readlink -f $ENV_DIR) \
    -B $PROJ_DIR \
    -B $SCRATCH_DIR:/tmp \
    $ENV_DIR/$container_tractseg" 

foreach_="for_each -nthreads $SLURM_CPUS_PER_TASK ${input_subject_array[@]} :"
parallel="parallel --ungroup --delay 0.2 -j$SUBJS_PER_NODE --joblog $CODE_DIR/log/parallel_runtask.log"

#########################
# FIXEL METRICS 2 VOXEL
#########################

# Input
#########################
FD_DIR=$FBA_GROUP_DIR/fd/
LOG_FC_DIR=$FBA_GROUP_DIR/log_fc
FDC_DIR=$FBA_GROUP_DIR/fdc

# Output
#########################
FD_VOXEL=$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-voxelmap_fd.nii.gz
LOG_FC_VOXEL=$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-voxelmap_logfc.nii.gz
FDC_VOXEL=$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-voxelmap_fdc.nii.gz
COMPLEXITY_VOXEL=$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-voxelmap_complexity.nii.gz

# Command
#########################
CMD_FIX2VOX_FD="fixel2voxel $FD_DIR/{}.mif mean $FD_VOXEL -force"
CMD_FIX2VOX_LOG_FC="fixel2voxel $LOG_FC_DIR/{}.mif mean $LOG_FC_VOXEL -force"
CMD_FIX2VOX_FDC="fixel2voxel $FDC_DIR/{}.mif mean $FDC_VOXEL -force"
CMD_FIX2VOX_COMPLEXITY="fixel2voxel $FD_DIR/{}.mif complexity $COMPLEXITY_VOXEL -force"

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
FA="$FW_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-T1w_desc-DTINoNeg_FA.nii.gz"
SUB2TEMP_WARP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_from-subject_to-fodtemplate_warp.mif"
FA_MNI_TARGET="$ENV_DIR/standard/FSL_HCP1065_FA_1mm.nii.gz"
SCHAEFER200_MNI="$ENV_DIR/standard/Schaefer2018_200Parcels_17Networks_order_FSLMNI152_1mm.nii.gz"

# Output
#########################
FA_TEMP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-DTINoNeg_FA.nii.gz"
FA_AVG_TEMP="$FA_TEMP_DIR/FA_averaged.nii.gz"

# Command
#########################
CMD_MRTRANSFORM="mrtransform $FA -warp $SUB2TEMP_WARP -interp nearest -datatype bit $FA_TEMP -force"
CMD_AVG="mrmath $(ls -d -1 $FA_TEMP_DIR/fa/sub-*) mean $FA_AVG_TEMP --force"

# Execution
#########################
#$parallel "$singularity_mrtrix3 $CMD_MRTRANSFORM" ::: ${input_subject_array[@]}
#$parallel "[ -f $FA_TEMP ] && ln -srf $FA_TEMP $FA_TEMP_DIR/fa" ::: ${input_subject_array[@]}
#$singularity_mrtrix3 $CMD_AVG

#########################
# FA_AVG_TEMP 2 MNI + ATLAS 2 TEMP
#########################

# Input
#########################
FA_MNI_TARGET="envs/standard/FSL_HCP1065_FA_1mm.nii.gz"
ATLAS_MNI="envs/standard/Schaefer2018_{}Parcels_17Networks_order_FSLMNI152_1mm.nii.gz"
FA_AVG_TEMP="$FA_TEMP_DIR/FA_averaged.nii.gz"

# Output
#########################
FA_MNI="$FA_TEMP_DIR/FA_averaged_in_mni.nii.gz"
TEMP2MNI_WARP="$TEMP2MNI_DIR/FA_averaged_in_mni_InverseComposite.h5"
FA_TEMP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-FWcorrected_FA.nii.gz"
ATLAS_TEMP="$TEMP2MNI_DIR/Schaefer2018_{}Parcels_17Networks_order_FSLMNI152_space-fodtemplate_1mm.nii.gz"

# Command
#########################
CMD_TEMP2MNI="
antsRegistration \
    --output [ $TEMP2MNI_DIR/FA2MNI, $FA_TEMP_DIR/FA_averaged_in_mni.nii.gz ] \
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
            -t $TEMP2MNI_WARP
"

# Execution
#########################
#$singularity_mrtrix3 $CMD_TEMP2MNI
#$parallel $singularity_mrtrix3 $CMD_ATLAS2TEMP ::: 100 200 400 600


#########################
# VOXELMAPS 2 MNI
#########################

# Input
#########################
FD_VOXEL=$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-voxelmask_fd.nii.gz
LOG_FC_VOXEL=$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-voxelmask_logfc.nii.gz
FDC_VOXEL=$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-voxelmask_fdc.nii.gz
COMPLEXITY_VOXEL=$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-voxelmask_complexity.nii.gz



# Output
#########################
FD_VOXEL_MNI=$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-MNI_desc-voxelmask_fd.nii.gz
LOG_FC_VOXEL_MNI=$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-MNI_desc-voxelmask_logfc.nii.gz
FDC_VOXEL_MNI=$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-MNI_desc-voxelmask_fdc.nii.gz
COMPLEXITY_VOXEL_MNI=$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-MNI_desc-voxelmask_complexity.nii.gz

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
$parallel "$singularity_mrtrix3 $CMD_FD2MNI" ::: ${input_subject_array[@]}
$parallel "$singularity_mrtrix3 $CMD_LOGFC2MNI" ::: ${input_subject_array[@]}
$parallel "$singularity_mrtrix3 $CMD_FDC2MNI" ::: ${input_subject_array[@]}
$parallel "$singularity_mrtrix3 $CMD_COMPLEXITY2MNI" ::: ${input_subject_array[@]}


#########################
# FREEWATER 2 TEMPLATE
#########################

FW_DIR=$DATA_DIR/freewater/$1/ses-$SESSION/dwi/
[ ! -d $FW_DIR ] && echo Please run freewater core pipeline first

# Input
#########################
FA="$FW_DIR/{}_ses-${SESSION}_space-T1w_desc-DTINoNeg_FA.nii.gz"
FAt="$FW_DIR/{}_ses-${SESSION}_space-T1w_desc-FWcorrected_FA.nii.gz"
MD="$FW_DIR/{}_ses-${SESSION}_space-T1w_desc-DTINoNeg_MD.nii.gz"
MDt="$FW_DIR/{}_ses-${SESSION}_space-T1w_desc-FWcorrected_MD.nii.gz"
AD="$FW_DIR/{}_ses-${SESSION}_space-T1w_desc-DTINoNeg_L1.nii.gz"
ADt="$FW_DIR/{}_ses-${SESSION}_space-T1w_desc-FWcorrected_L1.nii.gz"
RD="$FW_DIR/{}_ses-${SESSION}_space-T1w_desc-DTINoNeg_RD.nii.gz"
RDt="$FW_DIR/{}_ses-${SESSION}_space-T1w_desc-FWcorrected_RD.nii.gz"
FW="$FW_DIR/{}_ses-${SESSION}_space-T1w_FW.nii.gz"
SUB2TEMP_WARP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_from-subject_to-fodtemplate_warp.mif"
FA_AVG_TEMP="$FA_TEMP_DIR/FA_averaged.nii.gz"

# Output
#########################
FA_TEMP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-DTINoNeg_FA.nii.gz"
FAt_TEMP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-FWcorrected_FA.nii.gz"
MD_TEMP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-DTINoNeg_MD.nii.gz"
MDt_TEMP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-FWcorrected_MD.nii.gz"
AD_TEMP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-DTINoNeg_L1.nii.gz"
ADt_TEMP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-FWcorrected_L1.nii.gz"
RD_TEMP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-DTINoNeg_RD.nii.gz"
RDt_TEMP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-FWcorrected_RD.nii.gz"
FW_TEMP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_FW.nii.gz"


# Command
#########################
CMD_FAt2TEMP="mrtransform $FAt -warp $SUB2TEMP_WARP -interp nearest -datatype bit $FAt_TEMP -force"
CMD_MD2TEMP="mrtransform $MD -warp $SUB2TEMP_WARP -interp nearest -datatype bit $MD_TEMP -force"
CMD_MDt2TEMP="mrtransform $MDt -warp $SUB2TEMP_WARP -interp nearest -datatype bit $MDt_TEMP -force"
CMD_AD2TEMP="mrtransform $AD -warp $SUB2TEMP_WARP -interp nearest -datatype bit $AD_TEMP -force"
CMD_ADt2TEMP="mrtransform $ADt -warp $SUB2TEMP_WARP -interp nearest -datatype bit $ADt_TEMP -force"
CMD_RD2TEMP="mrtransform $RD -warp $SUB2TEMP_WARP -interp nearest -datatype bit $RD_TEMP -force"
CMD_RDt2TEMP="mrtransform $RDt -warp $SUB2TEMP_WARP -interp nearest -datatype bit $RDt_TEMP -force"
CMD_FW2TEMP="mrtransform $FW -warp $SUB2TEMP_WARP -interp nearest -datatype bit $FW_TEMP -force"

# Execution
#########################
$parallel "$singularity_mrtrix3 $CMD_FAt2TEMP" ::: ${input_subject_array[@]}
$parallel "$singularity_mrtrix3 $CMD_MD2TEMP" ::: ${input_subject_array[@]}
$parallel "$singularity_mrtrix3 $CMD_MDt2TEMP" ::: ${input_subject_array[@]}
$parallel "$singularity_mrtrix3 $CMD_AD2TEMP" ::: ${input_subject_array[@]}
$parallel "$singularity_mrtrix3 $CMD_ADt2TEMP" ::: ${input_subject_array[@]}
$parallel "$singularity_mrtrix3 $CMD_RD2TEMP" ::: ${input_subject_array[@]}
$parallel "$singularity_mrtrix3 $CMD_RDt2TEMP" ::: ${input_subject_array[@]}
$parallel "$singularity_mrtrix3 $CMD_FW2TEMP" ::: ${input_subject_array[@]}
