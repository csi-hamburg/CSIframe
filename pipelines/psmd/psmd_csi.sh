#!/usr/bin/env bash

##################################################################################################
# Submission script for PSMD calculation (https://github.com/miac-research/psmd) with adapted    #
# registration step (ANTS instead of FNIRT)                                                      #
#                                                                                                #
# Citation for the PSMD pipeline:                                                                #
# Baykara E. et al. A novel imaging marker for small vessel disease based on skeletonization of  #
# white matter tracts and diffusion histograms. Annals of Neurology 2016. DOI: 10.1002/ana.24758 #
#                                                                                                #
# Pipeline specific dependencies:                                                                #
#   [pipelines which need to be run first]                                                       #
#       - qsiprep                                                                                #
#   [container]                                                                                  #
#       - fsl-6.0.3                                                                              #
#       - mrtrix3-3.0.2                                                                          #
##################################################################################################

# Get verbose outputs
set -x

# Define subject specific temporary directory on $SCRATCH_DIR
export TMP_DIR=$SCRATCH_DIR/$1/tmp;   [ ! -d $TMP_DIR ] && mkdir -p $TMP_DIR
TMP_IN=$TMP_DIR/input;                 [ ! -d $TMP_IN ] && mkdir -p $TMP_IN
TMP_OUT=$TMP_DIR/output;               [ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT

###################################################################################################################

# Define environment
####################

container_mrtrix3=mrtrix3-3.0.2      

singularity_mrtrix3="singularity run --cleanenv --userns \
    -B .
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR \
    -B $TMP_IN \
    -B $TMP_OUT \
    $ENV_DIR/$container_mrtrix3" 

container_fsl=fsl-6.0.3
singularity_fsl="singularity run --cleanenv --no-home --userns \
    -B .
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR \
    -B $TMP_IN \
    -B $TMP_OUT \
    $ENV_DIR/$container_fsl" 

# Define PSMD output directory
##############################

PSMD_DIR=$DATA_DIR/psmd${PIPELINE_SUFFIX}

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

    # Define input data
    ###################

    INPUT_DWI=$DATA_DIR/qsiprep/$1/ses-${SESSION}/dwi/${1}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_dwi.nii.gz
    INPUT_DWI_MIF=$TMP_OUT/${1}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_dwi.mif
    INPUT_MASK=$DATA_DIR/qsiprep/$1/ses-${SESSION}/dwi/${1}_ses-${SESSION}_acq-AP_space-T1w_desc-brain_mask.nii.gz
    INPUT_BVEC_BVAL=$DATA_DIR/qsiprep/$1/ses-${SESSION}/dwi/${1}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_dwi.b
    INPUT_BVEC=$TMP_OUT/${1}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_dwi_desc-mrconvert.bvec
    INPUT_BVAL=$TMP_OUT/${1}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_dwi_desc-mrconvert.bval
    
    # Convert bvals and bvecs from .b (mrtrix format) to .bval and .bvec (fsl format)
    #################################################################################

    CMD_CONVERT="mrconvert \
        -force \
        -grad $INPUT_BVEC_BVAL \
        -export_grad_fsl $INPUT_BVEC $INPUT_BVAL \
        $INPUT_DWI $INPUT_DWI_MIF"

    $singularity_mrtrix3 $CMD_CONVERT

    # Fit DTI model
    ###############

    CMD_FIT="dtifit -k $INPUT_DWI -o $TMP_OUT/temp-DTI -m $INPUT_MASK -r $INPUT_BVEC -b $INPUT_BVAL"

    $singularity_fsl $CMD_FIT

    # Run TBSS 1 preproc
    ####################

    FA_IMAGE=$TMP_OUT/temp-DTI_FA.nii.gz
    MD_IMAGE=$TMP_OUT/temp-DTI_MD.nii.gz

    mkdir $TMP_OUT/tbss
    cp -v $FA_IMAGE $TMP_OUT/tbss
     
    pushd $TMP_OUT/tbss
    tbssfile=$(ls)

    $singularity_fsl tbss_1_preproc $tbssfile

    # Run TBSS 2 reg / ANTs registration
    ####################################

    # Input

    FA_MNI_TARGET="$ENV_DIR/standard/FMRIB58_FA_1mm.nii.gz"
    FA="$TMP_OUT/tbss/FA/temp-DTI_FA_FA.nii.gz"
    MD="$TMP_OUT/temp-DTI_MD.nii.gz"

    # Output

    FA2MNI_WARP="$TMP_OUT/tbss/FA/${1}_ses-${SESSION}_desc-dwi_from-T1w_to-MNI_Composite.h5"
    FA_MNI="$TMP_OUT/tbss/FA/${1}_ses-${SESSION}_space-MNI_FA.nii.gz"
    MD_MNI="$TMP_OUT/tbss/MD/${1}_ses-${SESSION}_space-MNI_MD.nii.gz"

    mkdir $TMP_OUT/tbss/MD

    # Define commands
    
    CMD_FA2MNI="
    antsRegistration \
        --output [ $TMP_OUT/tbss/FA/${1}_ses-${SESSION}_desc-dwi_from-T1w_to-MNI_, $FA_MNI ] \
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
        --write-composite-transform 1"

    CMD_MD2MNI="
    antsApplyTransforms -d 3 -e 3 -n Linear \
        -i $MD \
        -r $FA_MNI_TARGET \
        -o $MD_MNI \
        -t $FA2MNI_WARP"

    # Execute commands

    $singularity_mrtrix3 $CMD_FA2MNI
    $singularity_mrtrix3 $CMD_MD2MNI

    # Run TBSS 3 postreg
    ####################

    mkdir $TMP_OUT/tbss/stats
    cp $FA_MNI $TMP_OUT/tbss/stats/all_FA.nii.gz

    pushd $TMP_OUT/tbss/stats

    echo "creating valid mask and mean FA"
    $singularity_fsl fslmaths all_FA -max 0 -Tmin -bin mean_FA_mask -odt char
    $singularity_fsl fslmaths all_FA -mas mean_FA_mask all_FA
    $singularity_fsl fslmaths all_FA -Tmean mean_FA

    echo "creating skeleton"
    $singularity_fsl fslmaths $ENV_DIR/standard/FMRIB58_FA_1mm -mas mean_FA_mask mean_FA
    $singularity_fsl fslmaths mean_FA -bin mean_FA_mask
    $singularity_fsl fslmaths all_FA -mas mean_FA_mask all_FA
    $singularity_fsl imcp $ENV_DIR/standard/FMRIB58_FA-skeleton_1mm mean_FA_skeleton

    popd

    # Run TBSS 4 prestats
    #####################

    $singularity_fsl tbss_4_prestats 0.2

    # Run TBSS NonFA
    ################

    cp $TMP_OUT/tbss/MD/${1}_ses-${SESSION}_space-MNI_MD.nii.gz $TMP_OUT/tbss/stats/all_MD.nii.gz

    pushd $TMP_OUT/tbss/stats

    echo "masking MD and projecting onto FA skeleton"
 
    CMD_MASK="
        fslmaths \
            all_MD \
            -mas mean_FA_mask \
            all_MD"

    CMD_PROJ="
        tbss_skeleton \
            -i mean_FA \
            -p 0.2 mean_FA_skeleton_mask_dst $ENV_DIR/standard/LowerCingulum_1mm all_FA all_MD_skeletonised \
            -a all_MD"

    $singularity_fsl $CMD_MASK
    $singularity_fsl $CMD_PROJ

    # Histogram analysis
    ####################
    
    SKELETON_MASK=$PIPELINE_DIR/skeleton_mask_2019.nii.gz
    
    $singularity_fsl fslmaths all_MD_skeletonised.nii.gz -mas $SKELETON_MASK -mul 1000000 MD_skeletonised_masked.nii.gz
    mdskel=MD_skeletonised_masked.nii.gz

    # Whole brain metrics
      
    a=`$singularity_fsl fslstats $mdskel -P 95 | tail -n 1`
    b=`$singularity_fsl fslstats $mdskel -P 5 | tail -n 1`
    psmd_global=`echo - | awk "{print ( ${a} - ${b} ) / 1000000 }" | sed 's/,/./'`

    # Left and right hemisphere metrics

    $singularity_fsl fslmaths $mdskel -roi  0 90 0 -1 0 -1 0 -1 MD_skeletonised_masked_R.nii.gz
    $singularity_fsl fslmaths $mdskel -roi 91 90 0 -1 0 -1 0 -1 MD_skeletonised_masked_L.nii.gz

    mdskel=MD_skeletonised_masked_L.nii.gz
    a=`$singularity_fsl fslstats $mdskel -P 95 | tail -n 1`
    b=`$singularity_fsl fslstats $mdskel -P 5 | tail -n 1`
    psmdL=`echo - | awk "{print ( ${a} - ${b} ) / 1000000 }" | sed 's/,/./'`

    mdskel=MD_skeletonised_masked_R.nii.gz
    a=`$singularity_fsl fslstats $mdskel -P 95 | tail -n 1`
    b=`$singularity_fsl fslstats $mdskel -P 5 | tail -n 1`
    psmdR=`echo - | awk "{print ( ${a} - ${b} ) / 1000000 }" | sed 's/,/./'`

    popd

    # Create CSV file
    #################

    echo "sub_id,psmd_global,psmd_left,psmd_right" > $PSMD_DIR/$1/ses-${SESSION}/dwi/${1}_ses-${SESSION}_psmd.csv
    echo $1,$psmd_global,$psmdL,$psmdR >> $PSMD_DIR/$1/ses-${SESSION}/dwi/${1}_ses-${SESSION}_psmd.csv

    popd

    # Copy data to /work
    ####################

    cp -ruvf $TMP_OUT/tbss $PSMD_DIR/$1/ses-${SESSION}/dwi/


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