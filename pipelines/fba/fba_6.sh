#!/usr/bin/env bash

###################################################################################################################
# FBA based on https://mrtrix.readthedocs.io/en/latest/fixel_based_analysis/st_fibre_density_cross-section.html   #
#                                                                                                                 #
# Step 6:                                                                                                         #
#       - Read out ROIs in template space                                                                         #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - qsiprep                                                                                                 #
#       - previous fba steps                                                                                      #
#       - freewater                                                                                               #
#   [containers]                                                                                                  #
#       - mrtrix3-3.0.2.sif                                                                                       #
###################################################################################################################

# Get verbose outputs
set -x

# Define subject specific temporary directory on $SCRATCH_DIR
export TMP_DIR=$SCRATCH_DIR/$1/tmp/;   [ ! -d $TMP_DIR ] && mkdir -p $TMP_DIR
TMP_IN=$TMP_DIR/input;                 [ ! -d $TMP_IN ] && mkdir -p $TMP_IN
TMP_OUT=$TMP_DIR/output;               [ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT

###################################################################################################################

# Define environment
####################

module load parallel

FBA_DIR=$DATA_DIR/fba
FBA_GROUP_DIR=$FBA_DIR/derivatives; [ ! -d $FBA_GROUP_DIR ] && mkdir -p $FBA_GROUP_DIR
TEMPLATE_SUBJECTS_TXT=$FBA_DIR/sourcedata/template_subjects.txt
TEMPLATE_RANDOM_SUBJECTS_TXT=$FBA_DIR/sourcedata/random_template_subjects.txt
export SINGULARITYENV_MRTRIX_TMPFILE_DIR=/tmp


container_mrtrix3=mrtrix3-3.0.2      

singularity_mrtrix3="singularity run --cleanenv --no-home --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_mrtrix3" 

parallel="parallel --ungroup --delay 0.2 -j16 --joblog $CODE_DIR/log/parallel_runtask.log"


# Define input data
###################

input_subject_array=($@)

FD_SMOOTH_DIR=$FBA_GROUP_DIR/fd_smooth
LOG_FC_SMOOTH_DIR=$FBA_GROUP_DIR/log_fc_smooth
FDC_SMOOTH_DIR=$FBA_GROUP_DIR/fdc_smooth
COMPLEXITY_VOXEL=$FBA_DIR/$1/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-fodtemplate_desc-voxelmap_complexity.nii.gz

FA_TEMP="$FBA_DIR/${1}/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-fodtemplate_desc-DTINoNeg_FA.nii.gz"
FAt_TEMP="$FBA_DIR/${1}/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-fodtemplate_desc-FWcorrected_FA.nii.gz"
AD_TEMP="$FBA_DIR/${1}/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-fodtemplate_desc-DTINoNeg_L1.nii.gz"
ADt_TEMP="$FBA_DIR/${1}/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-fodtemplate_desc-FWcorrected_L1.nii.gz"
RD_TEMP="$FBA_DIR/${1}/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-fodtemplate_desc-DTINoNeg_RD.nii.gz"
RDt_TEMP="$FBA_DIR/${1}/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-fodtemplate_desc-FWcorrected_RD.nii.gz"
MD_TEMP="$FBA_DIR/${1}/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-fodtemplate_desc-DTINoNeg_MD.nii.gz"
MDt_TEMP="$FBA_DIR/${1}/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-fodtemplate_desc-FWcorrected_MD.nii.gz"
FW_TEMP="$FBA_DIR/${1}/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-fodtemplate_FW.nii.gz"

###################################
# Read out ROIs in template space #
###################################

if [ $ANALYSIS_LEVEL == "subject" ]; then

    [ ! -f $FD_SMOOTH_DIR/$1.mif ] && echo "$1 does not have necessary FBA output. Exiting ..." && exit 0

    # Get tracktseg ROIs
    ####################

    FIXEL_ROIS=(`ls $FBA_GROUP_DIR/tractseg/tractseg_output/bundle_segmentations/*nii.gz | rev | cut -d "/" -f 1 | rev | cut -d "." -f 1`)

    # Create CSV
    ############

    ROI_CSV=$FBA_DIR/$1/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-fodtemplate_desc-tractseg_desc-roi_means.csv
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

    # Extract ROIs
    ##############

    for ROI in $(echo ${FIXEL_ROIS[@]}); do

        FIXEL_MASK=$FBA_GROUP_DIR/tractseg/bundles_fixelmask/${ROI}_fixelmask.mif
        VOXEL_MASK=$FBA_GROUP_DIR/tractseg/tractseg_output/bundle_segmentations/${ROI}.nii.gz
        
        # Define commands for fixel metrics
        CMD_ROI_FD="mrstats -output mean -mask $FIXEL_MASK $FD_SMOOTH_DIR/${1}.mif"
        CMD_ROI_LOG_FC="mrstats -output mean -mask $FIXEL_MASK $LOG_FC_SMOOTH_DIR/${1}.mif"
        CMD_ROI_FDC="mrstats -output mean -mask $FIXEL_MASK $FDC_SMOOTH_DIR/${1}.mif"

        # Define commands for voxel metrics
        CMD_ROI_COMPLEXITY="mrstats -output mean -mask $VOXEL_MASK $COMPLEXITY_VOXEL"
        CMD_ROI_FA="mrstats -output mean -mask $VOXEL_MASK $FA_TEMP"
        CMD_ROI_FAt="mrstats -output mean -mask $VOXEL_MASK $FAt_TEMP"
        CMD_ROI_AD="mrstats -output mean -mask $VOXEL_MASK $AD_TEMP"
        CMD_ROI_ADt="mrstats -output mean -mask $VOXEL_MASK $ADt_TEMP"
        CMD_ROI_RD="mrstats -output mean -mask $VOXEL_MASK $RD_TEMP"
        CMD_ROI_RDt="mrstats -output mean -mask $VOXEL_MASK $RDt_TEMP"
        CMD_ROI_MD="mrstats -output mean -mask $VOXEL_MASK $MD_TEMP"
        CMD_ROI_MDt="mrstats -output mean -mask $VOXEL_MASK $MDt_TEMP"
        CMD_ROI_FW="mrstats -output mean -mask $VOXEL_MASK $FW_TEMP"

        # Run commands
        $singularity_mrtrix3 $CMD_ROI_FD | tail -n 1 > $TMP_OUT/${1}_fba_${ROI}_mean_fd.txt
        $singularity_mrtrix3 $CMD_ROI_LOG_FC | tail -n 1 > $TMP_OUT/${1}_fba_${ROI}_mean_logfc.txt
        $singularity_mrtrix3 $CMD_ROI_FDC | tail -n 1 > $TMP_OUT/${1}_fba_${ROI}_mean_fdc.txt
        $singularity_mrtrix3 $CMD_ROI_COMPLEXITY | tail -n 1 > $TMP_OUT/${1}_fba_${ROI}_mean_complexity.txt
        $singularity_mrtrix3 $CMD_ROI_FA | tail -n 1 > $TMP_OUT/${1}_fba_${ROI}_mean_FA.txt
        $singularity_mrtrix3 $CMD_ROI_FAt | tail -n 1 > $TMP_OUT/${1}_fba_${ROI}_mean_FAt.txt
        $singularity_mrtrix3 $CMD_ROI_AD | tail -n 1 > $TMP_OUT/${1}_fba_${ROI}_mean_AD.txt
        $singularity_mrtrix3 $CMD_ROI_ADt | tail -n 1 > $TMP_OUT/${1}_fba_${ROI}_mean_ADt.txt
        $singularity_mrtrix3 $CMD_ROI_RD | tail -n 1 > $TMP_OUT/${1}_fba_${ROI}_mean_RD.txt
        $singularity_mrtrix3 $CMD_ROI_RDt | tail -n 1 > $TMP_OUT/${1}_fba_${ROI}_mean_RDt.txt
        $singularity_mrtrix3 $CMD_ROI_MD | tail -n 1 > $TMP_OUT/${1}_fba_${ROI}_mean_MD.txt
        $singularity_mrtrix3 $CMD_ROI_MDt | tail -n 1 > $TMP_OUT/${1}_fba_${ROI}_mean_MDt.txt
        $singularity_mrtrix3 $CMD_ROI_FW | tail -n 1 > $TMP_OUT/${1}_fba_${ROI}_mean_FW.txt

    done

    # Ammend outputs to CSV on subject level
    ########################################

    ROI_CSV=$FBA_DIR/$1/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-fodtemplate_desc-tractseg_desc-roi_means.csv
    echo -n "$1," >> $ROI_CSV

    for MOD in fd logfc fdc complexity FA FAt AD ADt RD RDt MD MDt; do
            
        for ROI in $(echo ${FIXEL_ROIS[@]}); do

            MEAN=`cat $TMP_OUT/${1}_fba_${ROI}_mean_$MOD.txt`
            echo -n "$MEAN," >> $ROI_CSV

        done
            
    done

    MOD="FW"
            
    for ROI in $(echo ${FIXEL_ROIS[@]:0:71}); do
            
        MEAN=`cat $TMP_OUT/${1}_fba_${ROI}_mean_$MOD.txt`
        echo -n "$MEAN," >> $ROI_CSV

    done

    ROI="UF_right"
    MEAN=`cat $TMP_OUT/${1}_fba_${ROI}_mean_$MOD.txt`
    echo "$MEAN" >> $ROI_CSV

###############################
# Combine CSVs on group level #
###############################

elif [ $ANALYSIS_LEVEL == "group" ]; then

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

    [ ! -d $FBA_GROUP_DIR/ses-$SESSION/dwi ] && mkdir -p $FBA_GROUP_DIR/ses-$SESSION/dwi

    ROI_CSV_COMBINED=$FBA_GROUP_DIR/ses-$SESSION/dwi/ses-${SESSION}_space-fodtemplate_desc-tractseg_desc-roi_means.csv

    # Create CSV
    ############

    head -n 1 $ROI_CSV_RAND > $ROI_CSV_COMBINED

    for sub in $(echo ${input_subject_array[@]}); do
        
        ROI_CSV=$FBA_DIR/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_space-fodtemplate_desc-tractseg_desc-roi_means.csv
        
        [ -f $ROI_CSV ] && tail -n 1 $ROI_CSV >> $ROI_CSV_COMBINED

    done

fi