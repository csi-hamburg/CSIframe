#!/bin/bash

###########################################################
# FSL TBSS implementation for parallelized job submission #
#                                                         #
# PART 2 - creation of mean FA and skeletonization        #
###########################################################

###############################################################################
# Pipeline specific dependencies:                                             #
#   [pipelines which need to be run first]                                    #
#       - qsiprep                                                             #
#       - freewater                                                           #
#       - fba (only for fixel branch)                                         #
#       - tbss_1                                                              #
#   [container]                                                               #
#       - fsl-6.0.3                                                           #  
###############################################################################

# Get verbose outputs
set -x

# Define subject specific temporary directory on $SCRATCH_DIR
export TMP_DIR=$SCRATCH_DIR/$1/tmp/;   [ ! -d $TMP_DIR ] && mkdir -p $TMP_DIR
TMP_IN=$TMP_DIR/input;                 [ ! -d $TMP_IN ] && mkdir -p $TMP_IN
TMP_OUT=$TMP_DIR/output;               [ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT

###################################################################################################################

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

# Set pipeline specific variables

if [ $TBSS_PIPELINE == "fixel" ]; then
    
    SPACE=fodtemplate

elif [ $TBSS_PIPELINE == "mni" ]; then 

    SPACE=MNI
    
fi

# Checking input
################

TBSS_DIR=$DATA_DIR/tbss_${TBSS_PIPELINE}
echo "TBSS_DIR = $TBSS_DIR"

# Check if TBSS 1 has already been run for all subjects with freewater output

files_complete=y

for sub in $(ls $DATA_DIR/freewater/sub*/ses-1/dwi/*T1w*DTINoNeg_FA.nii.gz | rev | cut -d "/" -f 1 | rev | cut -d "_" -f 1); do
    
    TBSS_SUBDIR=$TBSS_DIR/$sub/ses-${SESSION}/dwi/

    img=`ls $TBSS_SUBDIR/*desc-eroded*FA.nii.gz | head -n 1`
    [ -f $img ] || files_complete=n

done

if [ $files_complete == "n" ]; then
    
    echo ""
    echo "TBSS 1 has not been run for all subjects with freewater output yet. Exiting ..."
    echo ""

    exit 

fi

# Creating derivatives directory
################################

DER_DIR=$TBSS_DIR/derivatives/sub-all/ses-${SESSION}/dwi

if [ -d $DER_DIR ]; then
    
    echo ""
    echo "TBSS Part 2 (tbss_2.sh) has already been run. Removing output of previous run first ..."
    echo ""

    rm -rvf $DER_DIR/*

fi

mkdir -p $DER_DIR

##############################################
# Calculation of mean FA and skeletonization #
##############################################

echo ""
echo "Merging all registered FA images into a single 4D image ..."
echo ""

FA_MERGED=$DER_DIR/sub-all_ses-${SESSION}_space-${SPACE}_desc-DTINoNeg_FA

$singularity_fsl fslmerge -t $FA_MERGED $TBSS_DIR/sub-*/ses-${SESSION}/dwi/*_desc-eroded_desc-DTINoNeg_FA.nii.gz

echo ""
echo "Creating valid mask and mean FA ..."
echo ""

if [ $TBSS_PIPELINE == "mni" ]; then

    # Define input/output

    FA_MASK=$DER_DIR/sub-all_ses-${SESSION}_space-${SPACE}_desc-meanFA_mask
    FA_MASKED=$DER_DIR/sub-all_ses-${SESSION}_space-${SPACE}_desc-brain_desc-DTINoNeg_FA
    FA_MEAN=$DER_DIR/sub-all_ses-${SESSION}_space-${SPACE}_desc-brain_desc-mean_desc-DTINoNeg_FA

    # Define command

    CMD_MEAN="
        fslmaths $FA_MERGED -max 0 -Tmin -bin $FA_MASK -odt char; \
        fslmaths $FA_MERGED -mas $FA_MASK $FA_MASKED; \
        fslmaths $FA_MASKED -Tmean $FA_MEAN"

elif [ $TBSS_PIPELINE == "fixel" ]; then
    
    # Define input/output

    FA_FBA_TEMPLATE=$DATA_DIR/fba/derivatives/fa_template/FA_averaged
    BET_MASK=$DER_DIR/sub-all_ses-${SESSION}_space-${SPACE}_desc-FAaveraged_desc-brain
    FA_MASK=$DER_DIR/sub-all_ses-${SESSION}_space-${SPACE}_desc-FAaveraged_desc-brain_mask
    FA_MASKED=$DER_DIR/sub-all_ses-${SESSION}_space-${SPACE}_desc-brain_desc-DTINoNeg_FA
    FA_MEAN=$DER_DIR/sub-all_ses-${SESSION}_space-${SPACE}_desc-brain_desc-mean_desc-DTINoNeg_FA

    # Define command

    CMD_MEAN="
        bet $FA_FBA_TEMPLATE $BET_MASK -m; \
        fslmaths $FA_MERGED -mas $FA_MASK $FA_MASKED; \
        fslmaths $FA_MASKED -Tmean $FA_MEAN"
    
fi

# Execute command

$singularity_fsl /bin/bash -c "$CMD_MEAN"


echo ""
echo "Skeletonizing mean FA ..."
echo ""

MEAN_FA_SKEL=$DER_DIR/sub-all_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-mean_desc-DTINoNeg_FA

$singularity_fsl tbss_skeleton -i $FA_MEAN -o $MEAN_FA_SKEL

echo "###################################################################################################"
echo "# Consider viewing mean_FA_skeleton to check whether the default or set threshold needs changing! #"
echo "###################################################################################################"

if [ -f $TBSS_DIR/code/thresh.txt ]; then

    thresh=`cat $TBSS_DIR/code/thresh.txt`

else 

    thresh=0.2
    echo $thresh > $TBSS_DIR/code/thresh.txt
	
fi

echo ""
echo "Creating skeleton mask using threshold of $thresh ..."
echo ""

SKELETON_MASK=$DER_DIR/sub-all_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-meanFA_mask

$singularity_fsl fslmaths $MEAN_FA_SKEL -thr $thresh -bin $SKELETON_MASK

echo ""
echo "Creating skeleton distancemap ..."
echo ""

SKEL_DIST=$DER_DIR/sub-all_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-meanFA_desc-mask_distancemap

CMD_DIST="
    fslmaths \
        $FA_MASK \
        -mul -1 \
        -add 1 \
        -add $SKELETON_MASK \
        $SKEL_DIST; \
    distancemap \
        -i $SKEL_DIST \
        -o $SKEL_DIST"

$singularity_fsl /bin/bash -c "$CMD_DIST"

########################################################################################
# Create ROI masks of JHU ICBM-DTI-81 white-matter labels atlas for MNI branch of TBSS #
########################################################################################

if [ $TBSS_PIPELINE == "mni" ]; then

    mkdir $DER_DIR/JHU

    for i in $(seq 1 48); do

        let index=$i+1
        ROI=`sed -n ${index}p $CODE_DIR/pipelines/tbss/JHU-ICBM-LUT.txt | awk '{print $2}'`

        # Input atlas
        ATLAS=/opt/$container_fsl/data/atlases/JHU/JHU-ICBM-labels-1mm.nii.gz

        # Output ROI mask
        JHU_ROI=$DER_DIR/JHU/atlas-JHU-ICBM-DTI-81_label-${ROI}.nii.gz
        
        CMD_ROI="fslmaths \
            $ATLAS \
            -thr $i \
            -uthr $i \
            -bin \
            $JHU_ROI"

        $singularity_fsl $CMD_ROI

    done

fi