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
FA_TEMP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-DTINoNeg_FA.nii.gz"
FA_AVG_TEMP="$FA_TEMP_DIR/FA_averaged.nii.gz"

# Command
#########################
CMD_MRTRANSFORM="mrtransform $FA -warp $SUB2TEMP_WARP $FA_TEMP -force"
CMD_AVG="mrmath $(ls -d -1 $FA_TEMP_DIR/fa/sub-*) mean $FA_AVG_TEMP --force"

# Execution
#########################
$parallel "$singularity_mrtrix3 $CMD_MRTRANSFORM" ::: ${input_subject_array[@]}
$parallel "[ -f $FA_TEMP ] && ln -srf $FA_TEMP $FA_TEMP_DIR/fa" ::: ${input_subject_array[@]}
$singularity_mrtrix3 $CMD_AVG

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
FA_TEMP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-FWcorrected_FA.nii.gz"
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
[ ! -d $FW_DIR ] && echo Please run freewater core pipeline first && exit 1

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
CMD_FAt2TEMP="mrtransform $FAt -warp $SUB2TEMP_WARP $FAt_TEMP -force"
CMD_MD2TEMP="mrtransform $MD -warp $SUB2TEMP_WARP $MD_TEMP -force"
CMD_MDt2TEMP="mrtransform $MDt -warp $SUB2TEMP_WARP $MDt_TEMP -force"
CMD_AD2TEMP="mrtransform $AD -warp $SUB2TEMP_WARP $AD_TEMP -force"
CMD_ADt2TEMP="mrtransform $ADt -warp $SUB2TEMP_WARP $ADt_TEMP -force"
CMD_RD2TEMP="mrtransform $RD -warp $SUB2TEMP_WARP $RD_TEMP -force"
CMD_RDt2TEMP="mrtransform $RDt -warp $SUB2TEMP_WARP $RDt_TEMP -force"
CMD_FW2TEMP="mrtransform $FW -warp $SUB2TEMP_WARP $FW_TEMP -force"

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

###################################
# Read out ROIs in template space #
###################################

# Get tracktseg ROIs
####################

FIXEL_ROIS=(`ls $FBA_GROUP_DIR/tractseg/tractseg_output/bundle_segmentations/*nii.gz | rev | cut -d "/" -f 1 | rev | cut -d "." -f 1`)

# Create CSV
############

for sub in $(echo ${input_subject_array[@]}); do

    if [ -f $FD_SMOOTH_DIR/$sub.mif ]; then

        ROI_CSV=$FBA_DIR/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_space-fodtemplate_desc-tractseg_desc-roi_means.csv
        echo -n "sub_id," > $ROI_CSV

        # Tractseg ROIs

        for MOD in fd logfc fdc complexity FA FAt AD ADt RD RDt MD MDt; do
        
            echo -en "fba_AF_left_mean_$MOD,fba_AF_right_mean_$MOD,fba_ATR_left_mean_$MOD,fba_ATR_right_mean_$MOD,\
            fba_CA_mean_$MOD,fba_CC_1_mean_$MOD,fba_CC_2_mean_$MOD,fba_CC_3_mean_$MOD,fba_CC_4_mean_$MOD,fba_CC_5_mean_$MOD,fba_CC_6_mean_$MOD,\
            fba_CC_7_mean_$MOD,fba_CC_mean_$MOD,fba_CG_left_mean_$MOD,fba_CG_right_mean_$MOD,fba_CST_left_mean_$MOD,fba_CST_right_mean_$MOD,fba_FPT_left_mean_$MOD,\
            fba_FPT_right_mean_$MOD,fba_FX_left_mean_$MOD,fba_FX_right_mean_$MOD,fba_ICP_left_mean_$MOD,fba_ICP_right_mean_$MOD,fba_IFO_left_mean_$MOD,\
            fba_IFO_right_mean_$MOD,fba_ILF_left_mean_$MOD,fba_ILF_right_mean_$MOD,fba_MCP_mean_$MOD,fba_MLF_left_mean_$MOD,fba_MLF_right_mean_$MOD,\
            fba_OR_left_mean_$MOD,fba_OR_right_mean_$MOD,fba_POPT_left_mean_$MOD,fba_POPT_right_mean_$MOD,fba_SCP_left_mean_$MOD,fba_SCP_right_mean_$MOD,fba_SLF_III_left_mean_$MOD,\
            fba_SLF_III_right_mean_$MOD,fba_SLF_II_left_mean_$MOD,fba_SLF_II_right_mean_$MOD,fba_SLF_I_left_mean_$MOD,fba_SLF_I_right_mean_$MOD,\
            fba_ST_FO_left_mean_$MOD,fba_ST_FO_right_mean_$MOD,fba_ST_OCC_left_mean_$MOD,fba_ST_OCC_right_mean_$MOD,fba_ST_PAR_left_mean_$MOD,\
            fba_ST_PAR_right_mean_$MOD,fba_ST_POSTC_left_mean_$MOD,fba_ST_POSTC_right_mean_$MOD,fba_ST_PREC_left_mean_$MOD,fba_PREC_right_mean_$MOD,\
            fba_ST_PREF_left_mean_$MOD,fba_ST_PREF_right_mean_$MOD,fba_ST_PREM_left_mean_$MOD,fba_ST_PREM_right_mean_$MOD,fba_STR_left_mean_$MOD,fba_STR_right_mean_$MOD,\
            fba_T_OCC_left_mean_$MOD,fba_T_OCC_right_mean_$MOD,fba_T_PAR_left_mean_$MOD,fba_T_PAR_right_mean_$MOD,fba_T_POSTC_left_mean_$MOD,fba_T_POSTC_right_mean_$MOD,\
            fba_T_PREC_left_mean_$MOD,fba_T_PREC_right_mean_$MOD,fba_T_PREF_left_mean_$MOD,fba_T_PREF_right_mean_$MOD,fba_T_PREM_left_mean_$MOD,fba_T_PREM_right_mean_$MOD,\
            fba_UF_left_mean_$MOD,fba_UF_right_mean_$MOD" >> $ROI_CSV

        done

        echo -e "fba_AF_left_mean_FW,fba_AF_right_mean_FW,fba_ATR_left_mean_FW,fba_ATR_right_mean_FW,\
        fba_CA_mean_FW,fba_CC_1_mean_FW,fba_CC_2_mean_FW,fba_CC_3_mean_FW,fba_CC_4_mean_FW,fba_CC_5_mean_FW,fba_CC_6_mean_FW,\
        fba_CC_7_mean_FW,fba_CC_mean_FW,fba_CG_left_mean_FW,fba_CG_right_mean_FW,fba_CST_left_mean_FW,fba_CST_right_mean_FW,fba_FPT_left_mean_FW,\
        fba_FPT_right_mean_FW,fba_FX_left_mean_FW,fba_FX_right_mean_FW,fba_ICP_left_mean_FW,fba_ICP_right_mean_FW,fba_IFO_left_mean_FW,\
        fba_IFO_right_mean_FW,fba_ILF_left_mean_FW,fba_ILF_right_mean_FW,fba_MCP_mean_FW,fba_MLF_left_mean_FW,fba_MLF_right_mean_FW,\
        fba_OR_left_mean_FW,fba_OR_right_mean_FW,fba_POPT_left_mean_FW,fba_POPT_right_mean_FW,fba_SCP_left_mean_FW,fba_SCP_right_mean_FW,fba_SLF_III_left_mean_FW,\
        fba_SLF_III_right_mean_FW,fba_SLF_II_left_mean_FW,fba_SLF_II_right_mean_FW,fba_SLF_I_left_mean_FW,fba_SLF_I_right_mean_FW,\
        fba_ST_FO_left_mean_FW,fba_ST_FO_right_mean_FW,fba_ST_OCC_left_mean_FW,fba_ST_OCC_right_mean_FW,fba_ST_PAR_left_mean_FW,\
        fba_ST_PAR_right_mean_FW,fba_ST_POSTC_left_mean_FW,fba_ST_POSTC_right_mean_FW,fba_ST_PREC_left_mean_FW,fba_PREC_right_mean_FW,\
        fba_ST_PREF_left_mean_FW,fba_ST_PREF_right_mean_FW,fba_ST_PREM_left_mean_FW,fba_ST_PREM_right_mean_FW,fba_STR_left_mean_FW,fba_STR_right_mean_FW,\
        fba_T_OCC_left_mean_FW,fba_T_OCC_right_mean_FW,fba_T_PAR_left_mean_FW,fba_T_PAR_right_mean_FW,fba_T_POSTC_left_mean_FW,fba_T_POSTC_right_mean_FW,\
        fba_T_PREC_left_mean_FW,fba_T_PREC_right_mean_FW,fba_T_PREF_left_mean_FW,fba_T_PREF_right_mean_FW,fba_T_PREM_left_mean_FW,fba_T_PREM_right_mean_FW,\
        fba_UF_left_mean_FW,fba_UF_right_mean_FW" >> $ROI_CSV
    fi

done

# Extract ROIs
##############

for ROI in $(echo ${FIXEL_ROIS[@]}); do

    FIXEL_MASK=$FBA_GROUP_DIR/tractseg/bundles_fixelmask/${ROI}_fixelmask.mif
    VOXEL_MASK=$FBA_GROUP_DIR/tractseg/tractseg_output/bundle_segmentations/${ROI}.nii.gz

    # Fixel metrics
    CMD_ROI_FD="mrstats -output mean -mask $FIXEL_MASK $FD_SMOOTH_DIR/{}.mif | tail -n 1 > $TMP_OUT/{}_fba_${ROI}_mean_fd.txt"
    CMD_ROI_LOG_FC="mrstats -output mean -mask $FIXEL_MASK $LOG_FC_SMOOTH_DIR/{}.mif | tail -n 1 > $TMP_OUT/{}_fba_${ROI}_mean_logfc.txt"
    CMD_ROI_FDC="mrstats -output mean -mask $FIXEL_MASK $FDC_SMOOTH_DIR/{}.mif | tail -n 1 > $TMP_OUT/{}_fba_${ROI}_mean_fdc.txt"

    # Voxel metrics
    CMD_ROI_COMPLEXITY="mrstats -output mean -mask $VOXEL_MASK $COMPLEXITY_VOXEL | tail -n 1 > $TMP_OUT/{}_fba_${ROI}_mean_complexity.txt"
    CMD_ROI_FA="mrstats -output mean -mask $VOXEL_MASK $FA_TEMP | tail -n 1 > $TMP_OUT/{}_fba_${ROI}_mean_FA.txt"
    CMD_ROI_FAt="mrstats -output mean -mask $VOXEL_MASK $FAt_TEMP | tail -n 1 > $TMP_OUT/{}_fba_${ROI}_mean_FAt.txt"
    CMD_ROI_AD="mrstats -output mean -mask $VOXEL_MASK $AD_TEMP | tail -n 1 > $TMP_OUT/{}_fba_${ROI}_mean_AD.txt"
    CMD_ROI_ADt="mrstats -output mean -mask $VOXEL_MASK $ADt_TEMP | tail -n 1 > $TMP_OUT/{}_fba_${ROI}_mean_ADt.txt"
    CMD_ROI_RD="mrstats -output mean -mask $VOXEL_MASK $RD_TEMP | tail -n 1 > $TMP_OUT/{}_fba_${ROI}_mean_RD.txt"
    CMD_ROI_RDt="mrstats -output mean -mask $VOXEL_MASK $RDt_TEMP | tail -n 1 > $TMP_OUT/{}_fba_${ROI}_mean_RDt.txt"
    CMD_ROI_MD="mrstats -output mean -mask $VOXEL_MASK $MD_TEMP | tail -n 1 > $TMP_OUT/{}_fba_${ROI}_mean_MD.txt"
    CMD_ROI_MDt="mrstats -output mean -mask $VOXEL_MASK $MDt_TEMP | tail -n 1 > $TMP_OUT/{}_fba_${ROI}_mean_MDt.txt"
    CMD_ROI_FW="mrstats -output mean -mask $VOXEL_MASK $FW_TEMP | tail -n 1 > $TMP_OUT/{}_fba_${ROI}_mean_FW.txt"

    # Run commands in parallel
    $parallel $singularity_mrtrix3 $CMD_ROI_FD ::: ${input_subject_array[@]}
    $parallel $singularity_mrtrix3 $CMD_ROI_LOG_FC ::: ${input_subject_array[@]}
    $parallel $singularity_mrtrix3 $CMD_ROI_FDC ::: ${input_subject_array[@]}
    $parallel $singularity_mrtrix3 $CMD_ROI_COMPLEXITY ::: ${input_subject_array[@]}
    $parallel $singularity_mrtrix3 $CMD_ROI_FA ::: ${input_subject_array[@]}
    $parallel $singularity_mrtrix3 $CMD_ROI_FAt ::: ${input_subject_array[@]}
    $parallel $singularity_mrtrix3 $CMD_ROI_AD ::: ${input_subject_array[@]}
    $parallel $singularity_mrtrix3 $CMD_ROI_ADt ::: ${input_subject_array[@]}
    $parallel $singularity_mrtrix3 $CMD_ROI_RD ::: ${input_subject_array[@]}
    $parallel $singularity_mrtrix3 $CMD_ROI_RDt ::: ${input_subject_array[@]}
    $parallel $singularity_mrtrix3 $CMD_ROI_MD ::: ${input_subject_array[@]}
    $parallel $singularity_mrtrix3 $CMD_ROI_MDt ::: ${input_subject_array[@]}
    $parallel $singularity_mrtrix3 $CMD_ROI_FW ::: ${input_subject_array[@]}

done

# Ammend outputs to CSV on subject level
########################################

for sub in $(echo ${input_subject_array[@]}); do

    if [ -f $FD_SMOOTH_DIR/$sub.mif ]; then

        ROI_CSV=$FBA_DIR/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_space-fodtemplate_desc-tractseg_desc-roi_means.csv
        echo -n "$sub," >> $ROI_CSV

        for MOD in fd logfc fdc complexity FA FAt AD ADt RD RDt MD MDt; do
        
            for ROI in $(echo ${FIXEL_ROIS[@]}); do

            MEAN=`cat $TMP_OUT/${sub}_fba_${ROI}_mean_$MOD.txt`
            echo -n "$MEAN," >> $ROI_CSV

            done
        
        done

        MOD="FW"
        
        for ROI in $(echo ${FIXEL_ROIS[@]:0:72}); do
        
            MEAN=`cat $TMP_OUT/${sub}_fba_${ROI}_mean_$MOD.txt`
            echo -n "$MEAN," >> $ROI_CSV

        done

        ROI="UF_right"
        MEAN=`cat $TMP_OUT/${sub}_fba_${ROI}_mean_$MOD.txt`
        echo "$MEAN" >> $ROI_CSV
    fi
done

###############################
# Combine CSVs on group level #
###############################

# Get subject to extract columm names from csv
##############################################

for sub in $(echo ${input_subject_array[@]}); do

    ROI_CSV=$FBA_DIR/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_space-fodtemplate_desc-tractseg_desc-roi_means.csv
    RAND_SUB=$sub
    
    [ -f $ROI_CSV ] && break

done

ROI_CSV_RAND=$FBA_DIR/$RAND_SUB/ses-$SESSION/dwi/${RAND_SUB}_ses-${SESSION}_space-fodtemplate_desc-tractseg_desc-roi_means.csv

# Output
########

[ ! -d $FBA_GROUP_DIR/ses-$SESSION ] && mkdir -p $FBA_GROUP_DIR/ses-$SESSION/dwi

ROI_CSV_COMBINED=$FBA_GROUP_DIR/ses-$SESSION/dwi/ses-${SESSION}_space-fodtemplate_desc-tractseg_desc-roi_means.csv

# Create CSV
############

head -n 1 $ROI_CSV_RAND > $ROI_CSV_COMBINED

for sub in $(echo ${input_subject_array[@]}); do
    
    ROI_CSV=$FBA_DIR/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_space-fodtemplate_desc-tractseg_desc-roi_means.csv
    
    [ -f $ROI_CSV ] && tail -n 1 $ROI_CSV >> $ROI_CSV_COMBINED

done