#!/bin/bash

###########################################################
# FSL TBSS implementation for parallelized job submission #
###########################################################

###############################################################################
# Pipeline specific dependencies:                                             #
#   [pipelines which need to be run first]                                    #
#       - qsiprep                                                             #
#       - freewater                                                           #
#       - fba (only for fixel branch)                                         #
#       - tbss_1                                                              #
#       - tbss_2                                                              #
#   [container]                                                               #
#       - fsl-6.0.3                                                           #  
###############################################################################

########################################################
# PART 3 - projection of diffusion metrics on skeleton #
########################################################

# Setup environment
###################

module load singularity
container_fsl=fsl-6.0.3

singularity_fsl="singularity run --cleanenv --userns \
    -B . \
    -B $PROJ_DIR \
    -B $SCRATCH_DIR:/tmp \
    -B $(readlink -f $ENV_DIR) \
    $ENV_DIR/$container_fsl" 

# Set pipeline specific variables; "" refers to *FW.nii.gz and "_desc-voxelmap" refers to FBA metrics

if [ $TBSS_PIPELINE == "fixel" ]; then
    
    SPACE=fodtemplate
    DTIMETHODS=(_desc-DTINoNeg _desc-FWcorrected "" _desc-voxelmap)

elif [ $TBSS_PIPELINE == "mni" ]; then 

    SPACE=MNI
    DTIMETHODS=(_desc-DTINoNeg _desc-FWcorrected "")

fi

# Input
#######
TBSS_DIR=$DATA_DIR/tbss_${TBSS_PIPELINE}
TBSS_SUBDIR=$TBSS_DIR/$1/ses-${SESSION}/dwi/
DER_DIR=$TBSS_DIR/derivatives/sub-all/ses-${SESSION}/dwi

echo "TBSS_DIR = $TBSS_DIR"

FA_ERODED=$TBSS_SUBDIR/${1}_ses-${SESSION}_space-${SPACE}_desc-eroded_desc-DTINoNeg_FA.nii.gz
MOD_ERODED=$TBSS_SUBDIR/${1}_ses-${SESSION}_space-${SPACE}_desc-eroded${DTIMETHOD}_${MOD}.nii.gz
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
MOD_MASKED=$TBSS_SUBDIR/${1}_ses-${SESSION}_space-${SPACE}_desc-eroded_desc-brain${DTIMETHOD}_${MOD}.nii.gz
FA_SKEL=$TBSS_SUBDIR/${1}_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-DTINoNeg_FA.nii.gz
MOD_SKEL=$TBSS_SUBDIR/${1}_ses-${SESSION}_space-${SPACE}_desc-skeleton${DTIMETHOD}_${MOD}.nii.gz

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
        $FA_MASKED;"
        
CMD_PROJ_FA="
    tbss_skeleton \
    -i $FA_MEAN \
    -p \
        $thresh \
        $SKEL_DIST \
        /opt/$container_fsl/data/standard/data/standard/LowerCingulum_1mm \
        $FA_MASKED \
        $FA_SKEL"

$singularity_fsl "$CMD_MASK_FA"	
$singularity_fsl "$CMD_PROJ_FA"

# Mask individual preprocessed diffusion metrics maps with mean_FA_mask and project onto FA skeleton based on FA projection
###########################################################################################################################

echo ""
echo "Masking other modalities and projecting onto FA skeleton."
echo ""

for DTIMETHOD in "${DTIMETHODS[@]}"; do

    if [ $DTIMETHOD == "_desc-DTINoNeg" ]; then
        MODALITIES="AD RD MD"
    elif [ $DTIMETHOD == "_desc-FWcorrected" ]; then
        MODALITIES="FAt ADt RDt MDt"
    elif [ -z $DTIMETHOD ]; then
        MODALITIES="FW"
    elif [ $DTIMETHOD == "_desc-voxelmap" ];then
        MODALITIES="fd fdc logfc complexity"
    fi

    for MOD in $(echo $MODALITIES); do

        echo ""
        echo $MOD
        echo ""
        
        CMD_MASK="
        fslmaths \
            $MOD_ERODED \
            -mas $FA_MASK \
            $MOD_MASKED;"

        CMD_PROJ="
            tbss_skeleton \
            -i $FA_MEAN \
            -p \
                $thresh \
                $SKEL_DIST \
                /opt/$container_fsl/data/standard/data/standard/LowerCingulum_1mm \
                $FA_MASKED \
                $MOD_SKEL \
            -a $MOD_MASKED"
        
        $singularity_fsl "$CMD_MASK"
        $singularity_fsl "$CMD_PROJ"

    done

done