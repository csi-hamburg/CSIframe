#!/bin/bash

############################################################
# FSL TBSS implementation for parallelized job submission  #
#                                                          #
# PART 1 - registration, eroding and zeroing of end slices #
############################################################

###############################################################################
# Pipeline specific dependencies:                                             #
#   [pipelines which need to be run first]                                    #
#       - qsiprep                                                             #
#       - freewater                                                           #
#       - fba (only for fixel branch)                                         #
#   [containers]                                                              #
#       - fsl-6.0.3                                                           #  
#       - mrtrix3-3.0.2 (only for fixel branch)                               #
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
export SINGULARITYENV_MRTRIX_TMPFILE_DIR=$TMP_DIR

singularity_mrtrix3="singularity run --cleanenv --no-home --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_mrtrix3" 

singularity_fsl="singularity run --cleanenv --no-home --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_fsl" 

# Define input/output directories
#################################

# Input

FW_DIR=$DATA_DIR/freewater/$1/ses-$SESSION/dwi
FBA_DIR=$DATA_DIR/fba/$1/ses-$SESSION/dwi

# Output

TBSS_DIR=$DATA_DIR/tbss_${TBSS_PIPELINE}
TBSS_SUBDIR=$TBSS_DIR/$1/ses-${SESSION}/dwi/

echo "TBSS_DIR = $TBSS_DIR"

# Remove previous run

if [ -d $TBSS_SUBDIR ]; then
    
    echo "TBSS $TBSS_PIPELINE has been run for ses-$SESSION of $1. Removing $TBSS_SUBDIR first ..."
    rm -rf $TBSS_SUBDIR

fi

mkdir -p $TBSS_DIR/sourcedata
mkdir -p $TBSS_DIR/derivatives
mkdir -p $TBSS_DIR/code

###############################
# Definition of TBSS pipeline #
###############################

if [ $TBSS_PIPELINE == "mni" ]; then 

    ############
    # MNI TBSS #
    ############

    echo "Running MNI TBSS pipeline ..."

    # Set pipeline specific variables
    
    MODALITIES="desc-DTINoNeg_FA desc-FWcorrected_FA desc-DTINoNeg_L1 desc-FWcorrected_L1 desc-DTINoNeg_RD \
                desc-FWcorrected_RD desc-DTINoNeg_MD desc-FWcorrected_MD FW"
    
    # Check for necessary freewater pipeline output 
    ###############################################
    
    echo ""
    echo "Processing $1"
    echo ""

    if [ -f $FW_DIR/${1}_ses-${SESSION}_space-${SPACE}_desc-DTINoNeg_FA.nii.gz ]; then 

        mkdir -p $TBSS_SUBDIR
        
    else

        echo ""
        echo "$1 does not have necessary freewater output. Please run freewater pipeline first. Exiting ..."
        echo ""

        exit
    
    fi


    # Check whether registration has already been performed 
    #######################################################

    if [ -f $FW_DIR/${1}_ses-${SESSION}_space-MNI_desc-DTINoNeg_FA.nii.gz ]; then

        echo ""
        echo "Registration has already been performed. Starting to erode and zero end sices of $1 ..."
        echo ""

        INPUT_DIR=$FW_DIR
        SPACE=MNI

    elif [ -f $FW_DIR/${1}_ses-${SESSION}_space-T1w_desc-DTINoNeg_FA.nii.gz ] && [ ! -f $FW_DIR/${1}_ses-${SESSION}_space-MNI_desc-DTINoNeg_FA.nii.gz ]; then
        
        # Perform registration to MNI space with ANTS
        #############################################
        
        echo ""
        echo "Registration has not been performed perviously. Starting registration of $1 to MNI space ..."
        echo ""
    
        # Input for registration
        
        FA_MNI_TARGET=$ENV_DIR/standard/FSL_HCP1065_FA_1mm.nii.gz
        FA=$FW_DIR/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-T1w_desc-DTINoNeg_FA.nii.gz
        FAt=$FW_DIR/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-T1w_desc-FWcorrected_FA.nii.gz
        AD=$FW_DIR/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-T1w_desc-DTINoNeg_L1.nii.gz
        ADt=$FW_DIR/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-T1w_desc-FWcorrected_L1.nii.gz
        RD=$FW_DIR/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-T1w_desc-DTINoNeg_RD.nii.gz
        RDt=$FW_DIR/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-T1w_desc-FWcorrected_RD.nii.gz
        MD=$FW_DIR/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-T1w_desc-DTINoNeg_MD.nii.gz
        MDt=$FW_DIR/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-T1w_desc-FWcorrected_MD.nii.gz
        FW=$FW_DIR/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-T1w_FW.nii.gz
        
        # Output of registration / input for TBSS
        
        INPUT_DIR=$TBSS_SUBDIR
        SPACE=MNI
        
        FA2MNI_WARP="$TBSS_SUBDIR/${1}_ses-${SESSION}_desc-dwi_from-T1w_to-MNI_Composite.h5" 

        FA_IMAGE=$INPUT_DIR/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-${SPACE}_desc-DTINoNeg_FA.nii.gz
        FAt_IMAGE=$INPUT_DIR/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-${SPACE}_desc-FWcorrected_FA.nii.gz
        AD_IMAGE=$INPUT_DIR/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-${SPACE}_desc-DTINoNeg_L1.nii.gz
        ADt_IMAGE=$INPUT_DIR/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-${SPACE}_desc-FWcorrected_L1.nii.gz
        RD_IMAGE=$INPUT_DIR/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-${SPACE}_desc-DTINoNeg_RD.nii.gz
        RDt_IMAGE=$INPUT_DIR/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-${SPACE}_desc-FWcorrected_RD.nii.gz
        MD_IMAGE=$INPUT_DIR/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-${SPACE}_desc-DTINoNeg_MD.nii.gz
        MDt_IMAGE=$INPUT_DIR/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-${SPACE}_desc-FWcorrected_MD.nii.gz
        FW_IMAGE=$INPUT_DIR/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-${SPACE}_FW.nii.gz

        # Commands
        
        CMD_FA2MNI="
        antsRegistration \
            --output [ $TBSS_SUBDIR/${1}_ses-${SESSION}_desc-dwi_from-T1w_to-MNI_, $FA_IMAGE ] \
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
            --write-composite-transform 1
        "

        CMD_FAt2MNI="
        antsApplyTransforms -d 3 -e 3 -n Linear \
                    -i $FAt \
                    -r $FA_MNI \
                    -o $FAt_IMAGE \
                    -t $FA2MNI_WARP
        "

        CMD_AD2MNI="
        antsApplyTransforms -d 3 -e 3 -n Linear \
                    -i $AD \
                    -r $FA_MNI_TARGET \
                    -o $AD_IMAGE \
                    -t $FA2MNI_WARP
        "

        CMD_ADt2MNI="
        antsApplyTransforms -d 3 -e 3 -n Linear \
                    -i $ADt \
                    -r $FA_MNI_TARGET \
                    -o $ADt_IMAGE \
                    -t $FA2MNI_WARP
        "

        CMD_RD2MNI="
        antsApplyTransforms -d 3 -e 3 -n Linear \
                    -i $RD \
                    -r $FA_MNI_TARGET \
                    -o $RD_IMAGE \
                    -t $FA2MNI_WARP
        "

        CMD_RDt2MNI="
        antsApplyTransforms -d 3 -e 3 -n Linear \
                    -i $RDt \
                    -r $FA_MNI_TARGET \
                    -o $RDt_IMAGE \
                    -t $FA2MNI_WARP
        "

        CMD_MD2MNI="
        antsApplyTransforms -d 3 -e 3 -n Linear \
                    -i $MD \
                    -r $FA_MNI_TARGET \
                    -o $MD_IMAGE \
                    -t $FA2MNI_WARP
        "

        CMD_MDt2MNI="
        antsApplyTransforms -d 3 -e 3 -n Linear \
                    -i $MDt \
                    -r $FA_MNI_TARGET \
                    -o $MDt_IMAGE \
                    -t $FA2MNI_WARP
        "

        CMD_FW2MNI="
        antsApplyTransforms -d 3 -e 3 -n Linear \
                    -i $FW \
                    -r $FA_MNI_TARGET \
                    -o $FW_IMAGE \
                    -t $FA2MNI_WARP
        "

        # Execution
    
        $singularity_mrtrix3 $CMD_FA2MNI
        $singularity_mrtrix3 $CMD_FAt2MNI
        $singularity_mrtrix3 $CMD_AD2MNI
        $singularity_mrtrix3 $CMD_ADt2MNI
        $singularity_mrtrix3 $CMD_RD2MNI
        $singularity_mrtrix3 $CMD_RDt2MNI
        $singularity_mrtrix3 $CMD_MD2MNI
        $singularity_mrtrix3 $CMD_MDt2MNI
        $singularity_mrtrix3 $CMD_FW2MNI

        # Erode and zero end slices
        ###########################

        echo ""
        echo "Registration of $1 to MNI space completed. Starting to erode and zero end slices of $1 ..."
        echo ""

    else
        
        echo ""
        echo "$1 does not have input DTI data."
        echo ""

        exit

    fi

elif [ $TBSS_PIPELINE == "fixel" ]; then

    ##############
    # Fixel TBSS #
    ##############

    echo "Running fixel TBSS pipeline ..."
    
    # Set pipeline specific variables
    #################################

    INPUT_DIR=$TBSS_SUBDIR
    SPACE=fodtemplate
    MODALITIES="desc-DTINoNeg_FA desc-FWcorrected_FA desc-DTINoNeg_L1 desc-FWcorrected_L1 desc-DTINoNeg_RD \
                desc-FWcorrected_RD desc-DTINoNeg_MD desc-FWcorrected_MD FW desc-voxelmap_fd desc-voxelmap_fdc desc-voxelmap_logfc desc-voxelmap_complexity"

    # Check for necessary FBA pipeline output 
    #########################################
    
    echo ""
    echo "Processing $1"
    echo ""

    if [ -f $FBA_DIR/${1}_ses-${SESSION}_space-${SPACE}_desc-DTINoNeg_FA.nii.gz ]; then 

        echo ""
        echo "Registration of $1 to FOD template has been performed already. Starting to erode and zero end slices of $1 ..."
        echo ""
        
        mkdir -p $TBSS_SUBDIR

        # Mask FBA output to avoid non-zero values outside of brain
        ###########################################################

        for MOD in $(echo $MODALITIES); do

            # Define input

            DMRI_MOD=$FBA_DIR/${1}_ses-${SESSION}_space-${SPACE}_${MOD}
            BRAIN_MASK=$FBA_DIR/${1}_ses-${SESSION}_space-${SPACE}_desc-brain_mask

            # Define output

            DMRI_MASKED=$TBSS_SUBDIR/${1}_ses-${SESSION}_space-${SPACE}_${MOD}

            # Define command
            
            CMD_MASK="fslmaths $DMRI_MOD -mas $BRAIN_MASK $DMRI_MASKED"

            #Execute command

            $singularity_fsl $CMD_MASK

        done
        
    else

        echo ""
        echo "$1 does not have necessary FBA output. Please run FBA pipeline first. Exiting ..."
        echo ""

        exit
    
    fi

fi

#####################################
# Eroding and zeroing of end slices #
#####################################

for MOD in $(echo $MODALITIES); do

    X=`$singularity_fsl fslval $INPUT_DIR/${1}_ses-${SESSION}_space-${SPACE}_${MOD} dim1 | tail -n 1`; let X="$X-2"
    Y=`$singularity_fsl fslval $INPUT_DIR/${1}_ses-${SESSION}_space-${SPACE}_${MOD} dim2 | tail -n 1`; let Y="$Y-2"
    Z=`$singularity_fsl fslval $INPUT_DIR/${1}_ses-${SESSION}_space-${SPACE}_${MOD} dim3 | tail -n 1`; let Z="$Z-2"
        
    $singularity_fsl fslmaths \
        $INPUT_DIR/${1}_ses-${SESSION}_space-${SPACE}_${MOD} \
        -min 1 -ero -roi 1 $X 1 $Y 1 $Z 0 1 \
        $TBSS_SUBDIR/${1}_ses-${SESSION}_space-${SPACE}_desc-eroded_${MOD}
        
done
        

