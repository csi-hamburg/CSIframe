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
container_mrtrix3=mrtrix3-3.0.2

singularity_fsl="singularity run --cleanenv --userns \
    -B . \
    -B $PROJ_DIR \
    -B $SCRATCH_DIR:/tmp \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR \
    -B $TMP_IN \
    -B $TMP_OUT \
    $ENV_DIR/$container_fsl"

singularity_mrtrix3="singularity run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR \
    -B $TMP_IN \
    -B $TMP_OUT \
    $ENV_DIR/$container_mrtrix3" 

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

# Count number of subjects
##########################

subj_batch_array=($(ls $TBSS_DIR/sub-* -d))
subj_array_length=${#subj_batch_array[@]}
echo $subj_array_length

# 700 is derived empirically: fslmerge worked for CSI_POSTCOVID without the "workaround" below

if [ $subj_array_length > 700 ]; then

    # Define number of subjects to be merged in one intermediate 4D image
    #####################################################################

    subj_per_batch=700
    batch_amount=$(($subj_array_length / $subj_per_batch))
    export START=1
    export subject_count=0

    # If modulo of subject array length and subj_per_batch is not 0 -> add one iteration to make sure all subjects will be processed
    
    [ ! $(( $subj_array_length % $subj_per_batch )) -eq 0 ] && batch_amount=$(($batch_amount + 1))

    # Loop through subject batches
    ##############################

    for batch in $(seq -w $batch_amount); do

        echo ""
        echo "Merging batch $batch and creating mask containing only non-zero voxels in all subjects of this batch"
        echo ""

        # Define end of batch
        
        export END=$(($subj_per_batch * $batch))

        # Define output

        FA_MERGED_INTERMEDIATE=$DER_DIR/batch-${batch}_ses-${SESSION}_space-${SPACE}_desc-DTINoNeg_FA.nii.gz
        FA_MAX0_INTERMEDIATE=$DER_DIR/batch-${batch}_ses-${SESSION}_space-${SPACE}_desc-allFA_max0
        FA_MAX0_MIN_INTERMEDIATE=$DER_DIR/batch-${batch}_ses-${SESSION}_space-${SPACE}_desc-allFA_max0_min
        FA_MASK_INTERMEDIATE=$DER_DIR/batch-${batch}_ses-${SESSION}_space-${SPACE}_desc-FA_mask
        FA_SUM_INTERMEDIATE=$DER_DIR/batch-${batch}_ses-${SESSION}_space-${SPACE}_desc-sum_desc-DTINoNeg_FA.nii.gz

        # Define commands

        CMD_MERGE_INTERMEDIATE="fslmerge -t $FA_MERGED_INTERMEDIATE $(ls $TBSS_DIR/sub-*/ses-${SESSION}/dwi/*_desc-eroded_desc-DTINoNeg_FA.nii.gz | sed -n "$START,${END}p")"
        CMD_MAX0_INTERMEDIATE="fslmaths $FA_MERGED_INTERMEDIATE -max 0 $FA_MAX0_INTERMEDIATE"
        CMD_MAX0_MIN_INTERMEDIATE="fslmaths $FA_MAX0_INTERMEDIATE -Tmin $FA_MAX0_MIN_INTERMEDIATE"
        CMD_BIN_INTERMEDIATE="fslmaths $FA_MAX0_MIN_INTERMEDIATE -bin $FA_MASK_INTERMEDIATE -odt char"
        CMD_SUM="mrmath $(ls $TBSS_DIR/sub-*/ses-${SESSION}/dwi/*_desc-eroded_desc-DTINoNeg_FA.nii.gz | sed -n "$START,${END}p") sum $FA_SUM_INTERMEDIATE"
        CMD_NUM="fslval $FA_MERGED_INTERMEDIATE dim4"
        
        # Execute commands for batch

        $singularity_fsl $CMD_MERGE_INTERMEDIATE
        $singularity_fsl $CMD_MAX0_INTERMEDIATE
        $singularity_fsl $CMD_MAX0_MIN_INTERMEDIATE
        $singularity_fsl $CMD_BIN_INTERMEDIATE
        $singularity_mrtrix3 $CMD_SUM

        # Increase START by subj_per_batch

        export START=$(($START + $subj_per_batch))

        # Add number of subjects to subject count

        subject_count_batch=`$singularity_fsl $CMD_NUM | tail -n 1`
        export subject_count=$(($subject_count + $subject_count_batch))

    done

    # Create final mask and mean FA
    ###############################
    
    echo ""
    echo "Merging intermediate masks into 4D image to create mask that is valid for all subjects, calculate mean FA and mask..."
    echo ""

    # Verify number of subjects for calculation of mean

    echo ""
    echo $subject_count
    echo ""

    # Define output

    FA_MASK_MERGED=$TMP_OUT/sub-all_ses-${SESSION}_space-${SPACE}_desc-FA_desc-merged_mask
    FA_MASK=$TMP_OUT/sub-all_ses-${SESSION}_space-${SPACE}_desc-meanFA_mask
    FA_SUM=$TMP_OUT/sub-all_ses-${SESSION}_space-${SPACE}_desc-sum_desc-DTINoNeg_FA.nii.gz
    FA_MEAN=$TMP_OUT/sub-all_ses-${SESSION}_space-${SPACE}_desc-brain_desc-mean_desc-DTINoNeg_FA
    
    # Define commands

    CMD_MERGE_MASK="fslmerge -t $FA_MASK_MERGED $(ls $TMP_OUT/batch-*_ses-${SESSION}_space-${SPACE}_desc-FA_mask.nii.gz)"
    CMD_Tmin_MASK="fslmaths $FA_MASK_MERGED -Tmin $FA_MASK"
    CMD_FA_SUM="mrmath $(ls $TMP_OUT/batch-*_ses-${SESSION}_space-${SPACE}_desc-sum_desc-DTINoNeg_FA.nii.gz) sum $FA_SUM"
    CMD_MEAN_FA="fslmaths $FA_SUM -div $subject_count -mas $FA_MASK $FA_MEAN"

    # Execute command

    $singularity_fsl $CMD_MERGE_MASK
    $singularity_fsl $CMD_Tmin_MASK
    $singularity_mrtrix3 $CMD_FA_SUM
    $singularity_fsl $CMD_MEAN_FA

   rm -rvf $TMP_OUT/batch*

else

    # Merge all individual FA images directly into final 4D image
    #############################################################

    echo ""
    echo "Merging all registered FA images into a single 4D image ..."
    echo ""

    FA_MERGED=$TMP_DIR/sub-all_ses-${SESSION}_space-${SPACE}_desc-DTINoNeg_FA

    $singularity_fsl fslmerge -t $FA_MERGED $TBSS_DIR/sub-*/ses-${SESSION}/dwi/*_desc-eroded_desc-DTINoNeg_FA.nii.gz

    echo ""
    echo "Creating valid mask and mean FA ..."
    echo ""

    # Define input/output

    FA_MASK=$TMP_DIR/sub-all_ses-${SESSION}_space-${SPACE}_desc-meanFA_mask
    FA_MASKED=$TMP_DIR/sub-all_ses-${SESSION}_space-${SPACE}_desc-brain_desc-DTINoNeg_FA
    FA_MEAN=$TMP_DIR/sub-all_ses-${SESSION}_space-${SPACE}_desc-brain_desc-mean_desc-DTINoNeg_FA

    # Define command

    CMD_MEAN="
        fslmaths $FA_MERGED -max 0 -Tmin -bin $FA_MASK -odt char; \
        fslmaths $FA_MERGED -mas $FA_MASK $FA_MASKED; \
        fslmaths $FA_MASKED -Tmean $FA_MEAN"

    # Execute command

    $singularity_fsl /bin/bash -c "$CMD_MEAN"

fi

echo ""
echo "Skeletonizing mean FA ..."
echo ""

MEAN_FA_SKEL=$TMP_OUT/sub-all_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-mean_desc-DTINoNeg_FA

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

SKELETON_MASK=$TMP_OUT/sub-all_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-meanFA_mask

$singularity_fsl fslmaths $MEAN_FA_SKEL -thr $thresh -bin $SKELETON_MASK

echo ""
echo "Creating skeleton distancemap ..."
echo ""

SKEL_DIST=$TMP_OUT/sub-all_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-meanFA_desc-mask_distancemap

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

echo ""
echo "Copying output from scratch to work directory ..."
echo ""

cp -ruvf $TMP_OUT/* $DER_DIR

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