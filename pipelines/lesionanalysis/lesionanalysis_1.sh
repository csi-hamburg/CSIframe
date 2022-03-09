#!/usr/bin/env bash

##################################################################################################
# Submission script for white matter lesion analysis                                             #
#                                                                                                #
# Part I: creation of lesion shells and flipping of lesions/shells to contralateral hemisphere   #
# for normalization of later derived means                                                       #
##################################################################################################

##################################################################################################
# Pipeline specific dependencies:                                                                #
#   [pipelines which need to be run first]                                                       #
#       - freesurfer reconstruction (e.g. as part of qsiprep or fmriprep)                        #
#       - lesion segmentation of some sort                                                       #
#   [containers]                                                                                 #
#       - fsl-6.0.3                                                                              #
#       - mrtrix3-3.0.2                                                                          #
#       - freesurfer-7.1.1                                                                       #
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

container_freesurfer=freesurfer-7.1.1
singularity_freesurfer="singularity run --cleanenv --userns \
    -B .
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR \
    -B $TMP_IN \
    -B $TMP_OUT \
    $ENV_DIR/$container_freesurfer"

# Create output directory
#########################

[ $READOUT_SPACE == "T1w" ] && OUT_DIR=$DATA_DIR/lesionanalysis/$1/ses-${SESSION}/anat
[ $READOUT_SPACE == "FLAIR" ] && OUT_DIR=$DATA_DIR/lesionanalysis/$1/ses-${SESSION}/anat
[ $READOUT_SPACE == "dwi" ] && OUT_DIR=$DATA_DIR/lesionanalysis/$1/ses-${SESSION}/dwi
[ $READOUT_SPACE == "dsc" ] && OUT_DIR=$DATA_DIR/lesionanalysis/$1/ses-${SESSION}/perf
[ $READOUT_SPACE == "asl" ] && OUT_DIR=$DATA_DIR/lesionanalysis/$1/ses-${SESSION}/perf

# Check whether output directory already exists: yes > remove and create new output directory

[ ! -d $OUT_DIR ] && mkdir -p $OUT_DIR
[ -d $OUT_DIR ] && rm -rvf $OUT_DIR && mkdir -p $OUT_DIR


###################################################################################################################
#                                           Run lesion analysis part I                                            #
###################################################################################################################

#############################################################
# Create white matter mask based on freesurfer segmentation #
#############################################################

# Define inputs
###############

ASEG_MGZ=$DATA_DIR/freesurfer/$1/mri/aseg.mgz
T1_FSNATIVE_MGZ=$DATA_DIR/freesurfer/$1/mri/rawavg.mgz

# Define outputs
################

# For white matter mask
ASEG_FSNATIVE=$TMP_OUT/${1}_ses-${SESSION}_space-T1w_aseg.mgz
ASEG_NIFTI=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_aseg.nii.gz

WM_R=$TMP_OUT/${1}_ses-${SESSION}_space-T1w_hemi-R_desc-wm_mask.nii.gz 
WM_L=$TMP_OUT/${1}_ses-${SESSION}_space-T1w_hemi-L_desc-wm_mask.nii.gz
WMH=$TMP_OUT/${1}_ses-${SESSION}_space-T1w_desc-wmh_mask.nii.gz
WM_ALL=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-wm_mask.nii.gz

# For ventricle mask
VENTRICLES_R=$TMP_OUT/${1}_ses-${SESSION}_space-T1w_hemi-R_desc-ventricle_mask.nii.gz
VENTRICLES_L=$TMP_OUT/${1}_ses-${SESSION}_space-T1w_hemi-L_desc-ventricle_mask.nii.gz
VENTRICLES_ALL=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-ventricles_mask.nii.gz

# Define commands
#################

CMD_prepare_wmmask="mri_label2vol --seg $ASEG_MGZ --temp $T1_FSNATIVE_MGZ --o $ASEG_FSNATIVE --regheader $ASEG_MGZ"
CMD_convert_wmmask="mri_convert $ASEG_FSNATIVE $ASEG_NIFTI"

CMD_create_wm_r="fslmaths $ASEG_NIFTI -thr 41 -uthr 41 -bin $WM_R"
CMD_create_wm_l="fslmaths $ASEG_NIFTI -thr 2 -uthr 2 -bin $WM_L"
CMD_create_wmh="fslmaths $ASEG_NIFTI -thr 77 -uthr 77 -bin $WMH"
CMD_merge_wmmasks="fslmaths $WM_R -add $WM_L -add $WMH -bin $WM_ALL"

CMD_create_ventricles_r="fslmaths $ASEG_NIFTI -thr 43 -uthr 43 -bin $VENTRICLES_R"
CMD_create_ventricles_l="fslmaths $ASEG_NIFTI -thr 4 -uthr 4 -bin $VENTRICLES_L"
CMD_merge_ventricles="fslmaths $VENTRICLES_R -add $VENTRICLES_L -bin $VENTRICLES_ALL"


# Execute commands
##################

$singularity_freesurfer $CMD_prepare_wmmask 
$singularity_freesurfer $CMD_convert_wmmask
$singularity_fsl $CMD_create_wm_r
$singularity_fsl $CMD_create_wm_l
$singularity_fsl $CMD_create_wmh
$singularity_fsl $CMD_merge_wmmasks

$singularity_fsl $CMD_create_ventricles_r
$singularity_fsl $CMD_create_ventricles_l
$singularity_fsl $CMD_merge_ventricles

############################################################################
# Erode white matter mask in order to avoid partial voluming effects later # 
############################################################################

# Define output
###############

WM_REFINED=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-wm_desc-eroded_mask.nii.gz

# Define command
################

CMD_REFINE="maskfilter -npass 2 $WM_ALL erode $WM_REFINED"

# Execute command
#################

$singularity_mrtrix3 $CMD_REFINE

##############################################################
# Register white matter and ventricles mask to readout space #
##############################################################

# If $READOUT_SPACE == "dwi" only regridding is necessary because DWI is already registered to T1w space in qsiprep

if [ $READOUT_SPACE == "dwi" ]; then

    # Define input
    ##############

    DWI=$DATA_DIR/qsiprep/$1/ses-${SESSION}/dwi/${1}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_dwi.nii.gz

    # Define output
    ###############

    WM_REFINED_REG=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-wm_desc-eroded_res-2mm_mask.nii.gz
    VENTRICLES_ALL_REG=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-ventricles_res-2mm_mask.nii.gz

    # Define command
    ################

    CMD_REGRID_WM="mrgrid -force -template $DWI -interp nearest -datatype int32 $WM_REFINED regrid $WM_REFINED_REG"
    CMD_REGRID_VENTRICLES="mrgrid -force -template $DWI -interp nearest -datatype int32 $VENTRICLES_ALL regrid $VENTRICLES_ALL_REG"

    # Execute command
    #################

    $singularity_mrtrix3 $CMD_REGRID_WM
    $singularity_mrtrix3 $CMD_REGRID_VENTRICLES

fi

# TO DO: Add other readout spaces

##########################################
# Flip lesion mask to contralateral side #
##########################################

if [ $MODIFIER == "yes" ]; then

    if [ $ORIG_SPACE == "T1w" ]; then

        # Define input
        ##############

        LESION_T1w=$LESION_DIR/$1/ses-$SESSION/anat/${1}_ses-${SESSION}_space-T1w_desc-lesion_mask.nii.gz
        MNI_TEMPLATE=$ENV_DIR/standard/tpl-MNI152NLin2009cAsym_res-01_desc-brain_T1w.nii.gz
        
        if [ $ANAT_PREPROC == "qsiprep" ]; then

            BRAIN_MASK=$DATA_DIR/$ANAT_PREPROC/$1/anat/${1}_desc-brain_mask.nii.gz
            T1_NATIVE=$DATA_DIR/$ANAT_PREPROC/$1/anat/${1}_desc-preproc_T1w.nii.gz
        
        elif [ $ANAT_PREPROC == "fmriprep" ]; then

            BRAIN_MASK=$DATA_DIR/$ANAT_PREPROC/$1/ses-$SESSION/anat/${1}_ses-${SESSION}_desc-brain_mask.nii.gz
            [ $(ls $DATA_DIR/$ANAT_PREPROC/$1/ses-* -d | wc -l) -gt 1 ] && BRAIN_MASK=$DATA_DIR/$ANAT_PREPROC/$1/anat/${1}_desc-brain_mask.nii.gz
            T1_NATIVE=$DATA_DIR/$ANAT_PREPROC/$1/ses-$SESSION/anat/${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz
            [ $(ls $DATA_DIR/$ANAT_PREPROC/$1/ses-* -d | wc -l) -gt 1 ] && T1_NATIVE=$DATA_DIR/$ANAT_PREPROC/$1/anat/${1}_desc-preproc_T1w.nii.gz
        
        fi
        
        # Define output
        ###############
        
        T1_BRAIN=$OUT_DIR/${1}_ses-${SESSION}_desc-preproc_desc-brain_T1w.nii.gz
        T1w_MNI_OUT=$OUT_DIR/${1}_ses-${SESSION}_from-T1w_to-MNI152NLin2009cAsym_desc-rigid_
        RIGID=${T1w_MNI_OUT}0GenericAffine.mat
        
        LESION_MNI=$OUT_DIR/${1}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-lesion_mask.nii.gz
        LESION_MNI_FLIP=$OUT_DIR/${1}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-lesion_desc-flipped_mask.nii.gz
        LESION_T1w_FLIP=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-lesion_desc-flipped_mask.nii.gz
        
        # Mask brain prior to registration
        ##################################
        
        # Define command
        CMD_MASK_BRAIN="fslmaths $T1_NATIVE -mul $BRAIN_MASK $T1_BRAIN"

        # Execute command
        $singularity_fsl $CMD_MASK_BRAIN

        # Rigid registration of T1w image to MNI space to obtain transformation matrix
        ###############################################################################

        # Define command
        [ -z $SLURM_CPUS_PER_TASK ] && SLURM_CPUS_PER_TASK=16
        CMD_T1w2MNI="antsRegistrationSyN.sh -d 3 -n $SLURM_CPUS_PER_TASK -m $T1_BRAIN -f $MNI_TEMPLATE -o $T1w_MNI_OUT -t r"

        # Execute command
        $singularity_mrtrix3 $CMD_T1w2MNI

        # Apply transformation to lesion mask
        #####################################
        
        # Define command
        CMD_APPLY_XFM="antsApplyTransforms -d 3 -e 0 -i $LESION_T1w -r $MNI_TEMPLATE -t $RIGID -o $LESION_MNI"

        # Execute command
        $singularity_mrtrix3 $CMD_APPLY_XFM

        # Flip lesion mask to contralateral hemisphere in MNI space
        ###########################################################
        
        # Define command
        CMD_SWAP="fslswapdim $LESION_MNI -x y z $LESION_MNI_FLIP"

        # Execute command
        $singularity_fsl $CMD_SWAP

        # Apply inverse transformation to flipped lesion mask
        #####################################################

        # Define command
        CMD_APPLY_XFM_INV="antsApplyTransforms -d 3 -e 0 -i $LESION_MNI_FLIP -r $T1_BRAIN -t [ $RIGID, 1 ] -o $LESION_T1w_FLIP"

        # Execute command
        $singularity_mrtrix3 $CMD_APPLY_XFM_INV

        # Threshold flipped lesion mask in T1w space
        ############################################

        # Define command
        FLIP_THRESH="fslmaths $LESION_T1w_FLIP -thr 0.9 -bin $LESION_T1w_FLIP"

        # Execute command
        $singularity_fsl $FLIP_THRESH

    fi

fi

# TO DO: add other orig spaces

###############################################################################################
# Registration of lesion masks to readout space and filter flipped mask to exclude ventricles #
###############################################################################################

if [ $ORIG_SPACE == "T1w" ] && [ $READOUT_SPACE == "dwi" ]; then

    # Since DWI is registered to T1w-space in qsiprep, only regridding of lesion masks is necessary

    # Define output
    ###############

    LESION_READOUT_RESIZED=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-lesion_res-2mm_mask.nii.gz
    LESION_READOUT_FLIP_RESIZED=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-lesion_desc-flipped_res-2mm_mask.nii.gz

    # Define commands
    #################

    CMD_RESIZE_IPSI="mrgrid -force -template $DWI -interp nearest -datatype uint32 $LESION_T1w regrid $LESION_READOUT_RESIZED"
    CMD_RESIZE_FLIP="mrgrid -force -template $DWI -interp nearest -datatype uint32 $LESION_T1w_FLIP regrid $LESION_READOUT_FLIP_RESIZED"
    CMD_FILTER_FLIP="fslmaths $LESION_READOUT_FLIP_RESIZED -sub $VENTRICLES_ALL_REG -thr 1 -bin $LESION_READOUT_FLIP_RESIZED"

    # Execute command
    #################

    $singularity_mrtrix3 $CMD_RESIZE_IPSI
    
    [ $MODIFIER == "yes" ] && $singularity_mrtrix3 $CMD_RESIZE_FLIP && $singularity_fsl $CMD_FILTER_FLIP

fi

# TODO: add other combinations

##############################
# Create perilesional shells #
##############################

if [ $READOUT_SPACE == "dwi" ]; then

    # Define output
    ###############
    
    LESION_DIL_i=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-lesion_res-2mm_desc-dil
    LESION_FLIP_DIL_i=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-lesion_desc-flipped_res-2mm_desc-dil

    # Dilate lesion masks
    #####################

    # ipsilateral

    for i in {1..8}; do
        
        CMD_DIL="maskfilter -npass $i $LESION_READOUT_RESIZED dilate ${LESION_DIL_i}${i}_mask.nii.gz"
        $singularity_mrtrix3 $CMD_DIL
    
    done
    
    # flipped
    
    if [ $MODIFIER == "yes" ]; then

        for i in {1..8}; do
            
            CMD_DIL_FLIP="maskfilter -npass $i $LESION_READOUT_FLIP_RESIZED dilate ${LESION_FLIP_DIL_i}${i}_mask.nii.gz"
            $singularity_mrtrix3 $CMD_DIL_FLIP
        
        done
    fi
    
    # Create and filter shells
    ##########################
    
    # Create ipsilateral shells - include only white matter
    
    CMD_SHELL="fslmaths ${LESION_DIL_i}1_mask.nii.gz -sub $LESION_READOUT_RESIZED -mul $WM_REFINED_REG ${LESION_DIL_i}1_shell.nii.gz"
    $singularity_fsl $CMD_SHELL

    for i in {2..8}; do
        
        CMD_SHELL="fslmaths ${LESION_DIL_i}${i}_mask.nii.gz -sub ${LESION_DIL_i}$(($i-1))_mask.nii.gz -mul $WM_REFINED_REG ${LESION_DIL_i}${i}_shell.nii.gz"
        $singularity_fsl $CMD_SHELL
    
    done
    
    if [ $MODIFIER == "yes" ]; then

        # Create contralateral shells - include only white matter
        
        CMD_SHELL_FLIP="fslmaths ${LESION_FLIP_DIL_i}1_mask.nii.gz -sub $LESION_READOUT_FLIP_RESIZED -mul $WM_REFINED_REG ${LESION_FLIP_DIL_i}1_shell.nii.gz"
        $singularity_fsl $CMD_SHELL_FLIP

        for i in {2..8}; do
            
            CMD_SHELL_FLIP="fslmaths ${LESION_FLIP_DIL_i}${i}_mask.nii.gz -sub ${LESION_FLIP_DIL_i}$(($i-1))_mask.nii.gz -mul $WM_REFINED_REG ${LESION_FLIP_DIL_i}${i}_shell.nii.gz"
            $singularity_fsl $CMD_SHELL_FLIP
        
        done

        # Substract ipsi- and contralateral shells from each other to avoid overlap
        
        for i in {1..8}; do
            
            CMD_UNIQ_IPSI="fslmaths ${LESION_DIL_i}${i}_shell.nii.gz -sub ${LESION_FLIP_DIL_i}${i}_shell.nii.gz -thr 1 -bin ${LESION_DIL_i}${i}_shell.nii.gz"
            CMD_UNIQ_FLIP="fslmaths ${LESION_FLIP_DIL_i}${i}_shell.nii.gz -sub ${LESION_DIL_i}${i}_shell.nii.gz -thr 1 -bin ${LESION_FLIP_DIL_i}${i}_shell.nii.gz"
            $singularity_fsl $CMD_UNIQ_IPSI
            $singularity_fsl $CMD_UNIQ_FLIP
        
        done

    fi

    # Remove dilated masks
    ######################

    rm -rvf $OUT_DIR/*_desc-lesion_*_desc-dil*_mask.nii.gz

fi

# TO DO: Add other readout spaces
