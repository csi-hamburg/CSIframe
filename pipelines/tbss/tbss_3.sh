#!/bin/bash

#########################################################################################
# FSL TBSS implementation for parallelized job submission                               #
#                                                                                       #
# PART 3 - projection of diffusion metrics on skeleton overlay creation and ROI readout #
#########################################################################################

###############################################################################
# Pipeline specific dependencies:                                             #
#   [pipelines which need to be run first]                                    #
#       - qsiprep                                                             #
#       - freewater                                                           #
#       - fba (only for fixel branch)                                         #
#       - tbss_1                                                              #
#       - tbss_2                                                              #
#   [container and code]                                                      #
#       - fsl-6.0.3                                                           #
#       - overlay.py                                                          #  
###############################################################################

# Get verbose outputs
set -x

# Turn off creation of core files
ulimit -c 0

# Define subject specific temporary directory on $SCRATCH_DIR
export TMP_DIR=$SCRATCH_DIR/$1/tmp/;   [ ! -d $TMP_DIR ] && mkdir -p $TMP_DIR
TMP_IN=$TMP_DIR/input;                 [ ! -d $TMP_IN ] && mkdir -p $TMP_IN
TMP_OUT=$TMP_DIR/output;               [ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT

###############################################################################

# Setup environment
###################

module load singularity

container_fsl=fsl-6.0.3
singularity_fsl="singularity run --cleanenv --no-home --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR \
    -B $TMP_IN \
    -B $TMP_OUT \
    $ENV_DIR/$container_fsl"

container_miniconda=miniconda-csi
singularity_miniconda="singularity run --cleanenv --no-home --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR \
    -B $TMP_IN \
    -B $TMP_OUT \
    $ENV_DIR/$container_miniconda"

# Set pipeline specific variables

if [ $TBSS_PIPELINE == "fixel" ]; then
    
    SPACE=fodtemplate
    MODALITIES="desc-FWcorrected_FA desc-DTINoNeg_L1 desc-FWcorrected_L1 desc-DTINoNeg_RD \
                desc-FWcorrected_RD desc-DTINoNeg_MD desc-FWcorrected_MD FW desc-voxelmap_fd desc-voxelmap_fdc desc-voxelmap_logfc desc-voxelmap_complexity"

elif [ $TBSS_PIPELINE == "mni" ]; then 

    SPACE=MNI
    MODALITIES="desc-FWcorrected_FA desc-DTINoNeg_L1 desc-FWcorrected_L1 desc-DTINoNeg_RD \
                desc-FWcorrected_RD desc-DTINoNeg_MD desc-FWcorrected_MD FW"

fi

# Input
#######
TBSS_DIR=$DATA_DIR/tbss_${TBSS_PIPELINE}
TBSS_SUBDIR=$TBSS_DIR/$1/ses-${SESSION}/dwi
DER_DIR=$TBSS_DIR/derivatives/sub-all/ses-${SESSION}/dwi

echo "TBSS_DIR = $TBSS_DIR"

FA_ERODED=$TBSS_SUBDIR/${1}_ses-${SESSION}_space-${SPACE}_desc-eroded_desc-DTINoNeg_FA.nii.gz
FA_MASK=$DER_DIR/sub-all_ses-${SESSION}_space-${SPACE}_desc-meanFA_mask.nii.gz
FA_MEAN=$DER_DIR/sub-all_ses-${SESSION}_space-${SPACE}_desc-brain_desc-mean_desc-DTINoNeg_FA.nii.gz
MEAN_FA_SKEL=$DER_DIR/sub-all_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-mean_desc-DTINoNeg_FA.nii.gz
SKEL_DIST=$DER_DIR/sub-all_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-meanFA_desc-mask_distancemap.nii.gz

# Check if TBSS 2 has been run

if [ ! -f $MEAN_FA_SKEL ]; then

    echo ""
    echo "TBSS 2 has not been run yet. Exiting ..."
    echo ""

    exit

fi

# Output
########

FA_MASKED=$TBSS_SUBDIR/${1}_ses-${SESSION}_space-${SPACE}_desc-eroded_desc-brain_desc-DTINoNeg_FA.nii.gz
FA_SKEL=$TBSS_SUBDIR/${1}_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-DTINoNeg_FA.nii.gz

# Remove output of previous runs

if [ -f $FA_MASKED ]; then

    echo ""
    echo "TBSS Part 3 (tbss_3.sh) has already been run on ses-$SESSION of $1. Removing previous output first ..."
    echo ""

    rm -rvf $TBSS_SUBDIR/*_desc-eroded_desc-brain_*
    rm -rvf $TBSS_SUBDIR/*_desc-skeleton_*

fi

#################################################
# Projection of diffusion metrics onto skeleton #
#################################################

thresh=`cat $TBSS_DIR/code/thresh.txt`

echo ""
echo "Projecting diffusion data onto skeleton"
echo ""


# Mask individual preprocessed FA maps with mask of mean FA and project onto FA skeleton
########################################################################################

echo ""
echo "Processing $1 ..."
echo ""

echo ""
echo "Masking individual preprocessed FA maps and projecting onto FA skeleton ..." 
echo ""

CMD_MASK_FA="
    fslmaths \
        $FA_ERODED \
        -mas $FA_MASK \
        $FA_MASKED"
        
CMD_PROJ_FA="
    tbss_skeleton \
    -i $FA_MEAN \
    -p $thresh $SKEL_DIST $ENV_DIR/standard/LowerCingulum_1mm.nii.gz $FA_MASKED $FA_SKEL"

$singularity_fsl $CMD_MASK_FA	
$singularity_fsl $CMD_PROJ_FA

# Mask individual preprocessed diffusion metrics maps with mean_FA_mask and project onto FA skeleton based on FA projection
###########################################################################################################################

echo ""
echo "Masking other modalities and projecting onto FA skeleton."
echo ""

for MOD in $(echo $MODALITIES); do

    echo ""
    echo $MOD
    echo ""
    
    MOD_ERODED=$TBSS_SUBDIR/${1}_ses-${SESSION}_space-${SPACE}_desc-eroded_${MOD}.nii.gz
    MOD_MASKED=$TBSS_SUBDIR/${1}_ses-${SESSION}_space-${SPACE}_desc-eroded_desc-brain_${MOD}.nii.gz
    MOD_SKEL=$TBSS_SUBDIR/${1}_ses-${SESSION}_space-${SPACE}_desc-skeleton_${MOD}.nii.gz

    CMD_MASK="
        fslmaths \
            $MOD_ERODED \
            -mas $FA_MASK \
            $MOD_MASKED"

    CMD_PROJ="
        tbss_skeleton \
            -i $FA_MEAN \
            -p $thresh $SKEL_DIST $ENV_DIR/standard/LowerCingulum_1mm.nii.gz $FA_MASKED $MOD_SKEL \
            -a $MOD_MASKED"
        
    $singularity_fsl $CMD_MASK
    $singularity_fsl $CMD_PROJ

done

#######################################################################################
# Create overlay of skeleton and respective modality for each subject for QC purposes #
#######################################################################################

# Reset MODALITIES (include desc-DTINoNeg_FA)
#############################################

if [ $TBSS_PIPELINE == "mni" ]; then

    MODALITIES="desc-DTINoNeg_FA desc-FWcorrected_FA desc-DTINoNeg_L1 desc-FWcorrected_L1 desc-DTINoNeg_RD \
                desc-FWcorrected_RD desc-DTINoNeg_MD desc-FWcorrected_MD FW"
    
elif [ $TBSS_PIPELINE == "fixel" ]; then

    MODALITIES="desc-DTINoNeg_FA desc-FWcorrected_FA desc-DTINoNeg_L1 desc-FWcorrected_L1 desc-DTINoNeg_RD \
                desc-FWcorrected_RD desc-DTINoNeg_MD desc-FWcorrected_MD FW desc-voxelmap_fd desc-voxelmap_fdc \
                desc-voxelmap_logfc desc-voxelmap_complexity"

fi

# Create overlay
################

for MOD in $(echo $MODALITIES); do

    # Input for overlay creation and ROI analyses
 
    MOD_MASKED=$TBSS_SUBDIR/${1}_ses-${SESSION}_space-${SPACE}_desc-eroded_desc-brain_${MOD}.nii.gz
    MOD_SKEL=$TBSS_SUBDIR/${1}_ses-${SESSION}_space-${SPACE}_desc-skeleton_${MOD}.nii.gz

    # Output

    OVERLAY=$TBSS_SUBDIR/${1}_ses-${SESSION}_space-${SPACE}_desc-skeleton_${MOD}_overlay.png

    $singularity_miniconda python $PIPELINE_DIR/overlay.py $MOD_MASKED $MOD_SKEL $OVERLAY

done

#################
# Read out ROIs #
#################

if [ $TBSS_PIPELINE == "mni" ]; then

    # Reset MODALITIES omitting one modality (FW) for seperate run (necessary for csv file creation)
    ################################################################################################

    MODALITIES="desc-DTINoNeg_FA desc-FWcorrected_FA desc-DTINoNeg_L1 desc-FWcorrected_L1 desc-DTINoNeg_RD \
                desc-FWcorrected_RD desc-DTINoNeg_MD desc-FWcorrected_MD"


    # Create CSV file
    #################

    # CSV for MNI branch
    
    ROI_CSV=$TBSS_SUBDIR/${1}_ses-${SESSION}_space-${SPACE}_desc-skeleton_label-JHU_desc-ROIs_means.csv
    
    echo -n "sub_id," > $ROI_CSV

    # ROIs of JHU ICBM-DTI-81 white-matter labels atlas

    for MOD in FA FAt AD ADt RD RDt MD MDt; do
        
        echo -en "tbssmni_MI-CP_mean_$MOD,tbssmni_P-CT_mean_$MOD,tbssmni_GCC_mean_$MOD,tbssmni_BCC_mean_$MOD,tbssmni_SCC_mean_$MOD,tbssmni_FX_mean_$MOD,\
tbssmni_CST-R_mean_$MOD,tbssmni_CST-L_mean_$MOD,tbssmni_ML-R_mean_$MOD,tbssmni_ML-L_mean_$MOD,tbssmni_ICP-R_mean_$MOD,tbssmni_ICP-L_mean_$MOD,\
tbssmni_SCP-R_mean_$MOD,tbssmni_SCP-L_mean_$MOD,tbssmni_CP-R_mean_$MOD,tbssmni_CP-L_mean_$MOD,tbssmni_ALIC-R_mean_$MOD,tbssmni_ALIC-L_mean_$MOD,\
tbssmni_PLIC-R_mean_$MOD,tbssmni_PLIC-L_mean_$MOD,tbssmni_RLIC-R_mean_$MOD,tbssmni_RLIC-L_mean_$MOD,tbssmni_ACR-R_mean_$MOD,tbssmni_ACR-L_mean_$MOD,\
tbssmni_SCR-R_mean_$MOD,tbssmni_SCR-L_mean_$MOD,tbssmni_PCR-R_mean_$MOD,tbssmni_PCR-L_mean_$MOD,tbssmni_PTR-R_mean_$MOD,tbssmni_PTR-L_mean_$MOD,\
tbssmni_SS-R_mean_$MOD,tbssmni_SS-L_mean_$MOD,tbssmni_EC-R_mean_$MOD,tbssmni_EC-L_mean_$MOD,tbssmni_CGC-R_mean_$MOD,\
tbssmni_CGC-L_mean_$MOD,tbssmni_CGH-R_mean_$MOD,tbssmni_CGH-L_mean_$MOD,tbssmni_FX_ST-R_mean_$MOD,tbssmni_FX_ST-L_mean_$MOD,tbssmni_SLF-R_mean_$MOD,\
tbssmni_SLF-L_mean_$MOD,tbssmni_SFO-R_mean_$MOD,tbssmni_SFO-L_mean_$MOD,tbssmni_UNC-R_mean_$MOD,tbssmni_UNC-L_mean_$MOD,\
tbssmni_TAP-R_mean_$MOD,tbssmni_TAP-L_mean_$MOD,tbssmni_skeleton_mean_$MOD," >> $ROI_CSV
    done

        echo -e "tbssmni_MI-CP_mean_FW,tbssmni_P-CT_mean_FW,tbssmni_GCC_mean_FW,tbssmni_BCC_mean_FW,tbssmni_SCC_mean_FW,tbssmni_FX_mean_FW,tbssmni_CST-R_mean_FW,\
tbssmni_CST-L_mean_FW,tbssmni_ML-R_mean_FW,tbssmni_ML-L_mean_FW,tbssmni_ICP-R_mean_FW,tbssmni_ICP-L_mean_FW,tbssmni_SCP-R_mean_FW,tbssmni_SCP-L_mean_FW,\
tbssmni_CP-R_mean_FW,tbssmni_CP-L_mean_FW,tbssmni_ALIC-R_mean_FW,tbssmni_ALIC-L_mean_FW,tbssmni_PLIC-R_mean_FW,tbssmni_PLIC-L_mean_FW,\
tbssmni_RLIC-R_mean_FW,tbssmni_RLIC-L_mean_FW,tbssmni_ACR-R_mean_FW,tbssmni_ACR-L_mean_FW,tbssmni_SCR-R_mean_FW,tbssmni_SCR-L_mean_FW,\
tbssmni_PCR-R_mean_FW,tbssmni_PCR-L_mean_FW,tbssmni_PTR-R_mean_FW,tbssmni_PTR-L_mean_FW,tbssmni_SS-R_mean_FW,tbssmni_SS-L_mean_FW,tbssmni_EC-R_mean_FW,\
tbssmni_EC-L_mean_FW,tbssmni_CGC-R_mean_FW,tbssmni_CGC-L_mean_FW,tbssmni_CGH-R_mean_FW,tbssmni_CGH-L_mean_FW,tbssmni_FX_ST-R_mean_FW,\
tbssmni_FX_ST-L_mean_FW,tbssmni_SLF-R_mean_FW,tbssmni_SLF-L_mean_FW,tbssmni_SFO-R_mean_FW,tbssmni_SFO-L_mean_FW,tbssmni_UNC-R_mean_FW,\
tbssmni_UNC-L_mean_FW,tbssmni_TAP-R_mean_FW,tbssmni_TAP-L_mean_FW,tbssmni_skeleton_mean_FW" >> $ROI_CSV

    # Iterate across modalities to extract JHU ROIs and mean across entire skeleton
    ###############################################################################

    echo -n "$1," >>  $ROI_CSV

    for MOD in $(echo $MODALITIES); do

        # Calculate mean for each ROI

        for ROI in $(awk '{print $2}' $CODE_DIR/pipelines/tbss/JHU-ICBM-LUT.txt | tail -n +2 ); do

            # Input 
            MOD_SKEL=$TBSS_SUBDIR/${1}_ses-${SESSION}_space-${SPACE}_desc-skeleton_${MOD}.nii.gz
            JHU_ROI=$DER_DIR/JHU/atlas-JHU-ICBM-DTI-81_label-${ROI}.nii.gz

            # Output skeleton (masked by ROI)
            MOD_SKEL_ROI=$TMP_OUT/${1}_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-JHU_label-${ROI}_${MOD}.nii.gz

            CMD_ROI="fslmaths $JHU_ROI -mul $MOD_SKEL $MOD_SKEL_ROI"
            CMD_ROI_MEAN="fslstats $MOD_SKEL_ROI -M"

            $singularity_fsl $CMD_ROI
            mean_roi=`$singularity_fsl $CMD_ROI_MEAN | tail -n 1`
            echo -n "$mean_roi," >> $ROI_CSV
                
        done

        # Calculate mean across entire skeleton

        CMD_MEAN="fslstats $MOD_SKEL -M"
        mean=`$singularity_fsl $CMD_MEAN | tail -n 1`
        echo -n "$mean," >> $ROI_CSV

    done

    # Repeat computations for FW (last echo call without -n option so next subject gets appended to new line) 
        
    MOD="FW"
 
    # Calculate mean for each ROI

    for ROI in $(awk '{print $2}' $CODE_DIR/pipelines/tbss/JHU-ICBM-LUT.txt | tail -n +2 ); do

        # Input 
        MOD_SKEL=$TBSS_SUBDIR/${1}_ses-${SESSION}_space-${SPACE}_desc-skeleton_${MOD}.nii.gz
        JHU_ROI=$DER_DIR/JHU/atlas-JHU-ICBM-DTI-81_label-${ROI}.nii.gz

        # Output skeleton (masked by ROI)
        MOD_SKEL_ROI=$TMP_OUT/${1}_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-JHU_label-${ROI}_${MOD}.nii.gz

        CMD_ROI="fslmaths $JHU_ROI -mul $MOD_SKEL $MOD_SKEL_ROI"
        CMD_ROI_MEAN="fslstats $MOD_SKEL_ROI -M"

        $singularity_fsl $CMD_ROI
        mean_roi=`$singularity_fsl $CMD_ROI_MEAN | tail -n 1`
        echo -n "$mean_roi," >> $ROI_CSV
    
    done


        # Calculate mean across entire skeleton

        CMD_MEAN="fslstats $MOD_SKEL -M"
        mean=`$singularity_fsl $CMD_MEAN | tail -n 1`
        echo "$mean" >> $ROI_CSV

elif [ $TBSS_PIPELINE == "fixel" ]; then

    # Reset MODALITIES omitting one modality (desc-voxelmap_complexity) for seperate run (necessary for csv file creation)
    ######################################################################################################################

    MODALITIES="desc-DTINoNeg_FA desc-FWcorrected_FA desc-DTINoNeg_L1 desc-FWcorrected_L1 desc-DTINoNeg_RD \
                desc-FWcorrected_RD desc-DTINoNeg_MD desc-FWcorrected_MD FW desc-voxelmap_fd desc-voxelmap_fdc \
                desc-voxelmap_logfc"

    # Create CSV file
    #################
    
    # Output CSV for fixel branch
    MEAN_CSV=$TBSS_SUBDIR/${1}_ses-${SESSION}_space-${SPACE}_desc-skeleton_means.csv
    
    echo -e "sub_id,tbss_skeleton_mean_FA,tbss_skeleton_mean_FAt,tbss_skeleton_mean_AD,tbss_skeleton_mean_ADt,tbss_skeleton_mean_RD,\
tbss_skeleton_mean_RDt,tbss_skeleton_mean_MD,tbss_skeleton_mean_MDt,tbss_skeleton_mean_FW,tbss_skeleton_mean_fd,tbss_skeleton_mean_fdc,\
tbss_skeleton_mean_logfc,tbss_skeleton_mean_complexity" > $MEAN_CSV

    # Iterate across modalities to extract mean across entire skeleton
    ##################################################################

    echo -n "$1," >>  $MEAN_CSV

    for MOD in $(echo $MODALITIES); do

        # Input skeleton
        MOD_SKEL=$TBSS_SUBDIR/${1}_ses-${SESSION}_space-${SPACE}_desc-skeleton_${MOD}.nii.gz
            
        CMD_MEAN="fslstats $MOD_SKEL -M"
        mean=`$singularity_fsl $CMD_MEAN | tail -n 1`
        echo -n "$mean," >> $MEAN_CSV
        
    done

    # Repeat computations for desc-voxelmap_complexity (last echo call without -n option so next subject gets appended to new line)

    MOD="desc-voxelmap_complexity"

    # Input skeleton
    MOD_SKEL=$TBSS_SUBDIR/${1}_ses-${SESSION}_space-${SPACE}_desc-skeleton_${MOD}.nii.gz

    CMD_MEAN="fslstats $MOD_SKEL -M"
    mean=`$singularity_fsl $CMD_MEAN | tail -n 1`
    echo "$mean" >> $MEAN_CSV

fi