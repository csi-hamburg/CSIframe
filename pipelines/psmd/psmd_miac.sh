#!/usr/bin/env bash

##################################################################################################
# Submission script for PSMD (https://github.com/miac-research/psmd)                             #
# Please check here for license and usage notes                                                  #
#                                                                                                #
# Citation for the PSMD pipeline:                                                                #
# Baykara E. et al. A novel imaging marker for small vessel disease based on skeletonization of  #
# white matter tracts and diffusion histograms. Annals of Neurology 2016. DOI: 10.1002/ana.24758 #
#                                                                                                #
# Pipeline specific dependencies:                                                                #
#   [pipelines which need to be run first]                                                       #
#       - qsiprep                                                                                #
#       - freewater                                                                              #
#   [container]                                                                                  #
#       - psmd-1.8.2                                                                             #
##################################################################################################

# Get verbose outputs
set -x

# Define subject specific temporary directory on $SCRATCH_DIR
export TMP_DIR=$SCRATCH_DIR/$1/tmp/;   [ ! -d $TMP_DIR ] && mkdir -p $TMP_DIR
TMP_IN=$TMP_DIR/input;                 [ ! -d $TMP_IN ] && mkdir -p $TMP_IN
TMP_OUT=$TMP_DIR/output;               [ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT

###################################################################################################################

# Define environment
####################

container_mrtrix3=mrtrix3-3.0.2      
container_psmd=psmd-1.8.2

singularity_mrtrix3="singularity run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR \
    -B $TMP_IN \
    -B $TMP_OUT \
    $ENV_DIR/$container_mrtrix3" 

singularity_psmd="singularity run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR \
    -B $TMP_IN \
    -B $TMP_OUT \
    $ENV_DIR/$container_psmd" 

# Define PSMD output directory
##############################

PSMD_DIR=$DATA_DIR/psmd${PIPELINE_SUFFIX}_${MODIFIER}

#############################################
# PSMD calculation - subject level analysis #
#############################################

if [ $ANALYSIS_LEVEL == "subject" ]; then

    # Create output directory
    #########################

    if [ -d $PSMD_DIR/$1/ses-${SESSION} ]; then
        
        rm -rf $PSMD_DIR/$1/ses-${SESSION}
        mkdir -p $PSMD_DIR/$1/ses-${SESSION}/dwi

    else
        
        mkdir -p $PSMD_DIR/$1/ses-${SESSION}/dwi

    fi

    pushd $TMP_DIR

    if [ $MODIFIER == "preprocessed" ]; then
    
        # Run PSMD based on preprocessed DWI data (qsiprep output)
        ##########################################################

        # Define input data

        INPUT_DWI=$DATA_DIR/qsiprep/$1/ses-${SESSION}/dwi/${1}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_dwi.nii.gz
        INPUT_DWI_MIF=$TMP_OUT/${1}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_dwi.mif
        INPUT_MASK=$DATA_DIR/qsiprep/$1/ses-${SESSION}/dwi/${1}_ses-${SESSION}_acq-AP_space-T1w_desc-brain_mask.nii.gz
        INPUT_BVEC_BVAL=$DATA_DIR/qsiprep/$1/ses-${SESSION}/dwi/${1}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_dwi.b
        INPUT_BVEC=$TMP_OUT/${1}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_dwi_desc-mrconvert.bvec
        INPUT_BVAL=$TMP_OUT/${1}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_dwi_desc-mrconvert.bval
        SKELETON_MASK=$PIPELINE_DIR/skeleton_mask_2019.nii.gz

        # Convert bvals and bvecs from .b (mrtrix format) to .bval and .bvec (fsl format)

        CMD_CONVERT="mrconvert \
        -force \
        -grad $INPUT_BVEC_BVAL \
        -export_grad_fsl $INPUT_BVEC $INPUT_BVAL \
        $INPUT_DWI $INPUT_DWI_MIF"

        $singularity_mrtrix3 $CMD_CONVERT

        # Define PSMD command

        CMD_PSMD_GLOBAL="psmd.sh -p $INPUT_DWI -b $INPUT_BVAL -r $INPUT_BVEC -s $SKELETON_MASK -c -t"
        CMD_PSMD_HEMI="psmd.sh -p $INPUT_DWI -b $INPUT_BVAL -r $INPUT_BVEC -s $SKELETON_MASK -g -c -t"

    elif [ $MODIFIER == "fitted" ]; then

        # Run PSMD based on already fitted DWI data (freewater output)
        ##############################################################
    
        # Define input data

        FA_IMAGE=$DATA_DIR/freewater/$1/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-T1w_desc-DTINoNeg_FA.nii.gz
        MD_IMAGE=$DATA_DIR/freewater/$1/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-T1w_desc-DTINoNeg_MD.nii.gz
        SKELETON_MASK=$PIPELINE_DIR/skeleton_mask_2019.nii.gz

        # Define PSMD command
        
        CMD_PSMD_GLOBAL="psmd.sh -f $FA_IMAGE -m $MD_IMAGE -s $SKELETON_MASK -c -t"
        CMD_PSMD_HEMI="psmd.sh -f $FA_IMAGE -m $MD_IMAGE -s $SKELETON_MASK -g -c -t"
    
    fi

    # Execute PSMD commands and obtain CSV file
    ###########################################

    PSMD_OUTPUT_GLOBAL=`$singularity_psmd $CMD_PSMD_GLOBAL`
    PSMD_RESULT_GLOBAL=`echo $PSMD_OUTPUT_GLOBAL | grep "PSMD is" | grep -Eo "[0-9]+\.[0-9][0-9]+"`

    PSMD_OUTPUT_HEMI=`$singularity_psmd $CMD_PSMD_HEMI`
    PSMD_RESULT_HEMI=`echo $PSMD_OUTPUT_HEMI | grep "PSMD is" | grep -Eo "[0-9]+\.[0-9]+\,[0-9]+\.[0-9]+"`

    # Create csv file with results

    echo "sub_id,psmd_global,psmd_left,psmd_right" > $PSMD_DIR/$1/ses-${SESSION}/dwi/${1}_ses-${SESSION}_psmd.csv
    echo $1,$PSMD_RESULT_GLOBAL,$PSMD_RESULT_HEMI >> $PSMD_DIR/$1/ses-${SESSION}/dwi/${1}_ses-${SESSION}_psmd.csv

    popd

    # Copy psmdtemp folder to /work
    ##############################

    cp -ruvf $TMP_DIR/psmdtemp $PSMD_DIR/$1/ses-${SESSION}/dwi/
    
#######################################
# Combine CSVs - group level analysis #
#######################################

elif [ $ANALYSIS_LEVEL == "group" ]; then

    [ -d $PSMD_DIR/derivatives/ses-${SESSION}/dwi ] || mkdir -p $PSMD_DIR/derivatives/ses-${SESSION}/dwi

    pushd $PSMD_DIR
    echo "sub_id,psmd_global,psmd_left,psmd_right" > $PSMD_DIR/derivatives/ses-${SESSION}/dwi/group_ses-${SESSION}_psmd.csv
    
        for sub in $(ls -d sub-*); do

            tail -n 1 $PSMD_DIR/$sub/ses-${SESSION}/dwi/${sub}_ses-${SESSION}_psmd.csv >> \
            $PSMD_DIR/derivatives/ses-${SESSION}/dwi/group_ses-${SESSION}_psmd.csv
        
        done

    popd

fi
