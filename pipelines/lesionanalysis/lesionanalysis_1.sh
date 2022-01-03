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
singularity_freesurfer="singularity run --cleanenv --no-home --userns \
    -B .
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR \
    -B $TMP_IN \
    -B $TMP_OUT \
    $ENV_DIR/$container_freesurfer"

# Create output directory
#########################

[ $ORIG_SPACE == "T1w" ] && OUT_DIR=$DATA_DIR/lesionanalysis/$1/ses-${SESSION}/anat
[ $ORIG_SPACE == "FLAIR" ] && OUT_DIR=$DATA_DIR/lesionanalysis/$1/ses-${SESSION}/anat
[ $ORIG_SPACE == "dwi" ] && OUT_DIR=$DATA_DIR/lesionanalysis/$1/ses-${SESSION}/dwi
[ $ORIG_SPACE == "dsc" ] && OUT_DIR=$DATA_DIR/lesionanalysis/$1/ses-${SESSION}/perf
[ $ORIG_SPACE == "asl" ] && OUT_DIR=$DATA_DIR/lesionanalysis/$1/ses-${SESSION}/perf

# Check whether output directory already exists: yes > remove and create new output directory

[ ! -d $OUT_DIR ] && mkdir -p $OUT_DIR
[ -d $OUT_DIR ] && rm -rvf $OUT_DIR && mkdir -p $OUT_DIR


###################################################################################################################
#                                           Run lesion analysis part I                                            #
###################################################################################################################

#################################################
# Create masks based on freesurfer segmentation #
#################################################

# Define inputs
###############

ASEG_MGZ=$DATA_DIR/freesurfer/$1/mri/aseg.mgz
#APARC_ASEG_MGZ=$DATA_DIR/freesurfer/$1/mri/aparc+aseg.mgz
RIBBON_R_MGZ=$DATA_DIR/freesurfer/$1/mri/rh.ribbon.mgz
RIBBON_L_MGZ=$DATA_DIR/freesurfer/$1/mri/lh.ribbon.mgz
T1_FSNATIVE_MGZ=$DATA_DIR/freesurfer/$1/mri/rawavg.mgz
T1_NATIVE=$DATA_DIR/fmriprep/$1/ses-$SESSION/anat/${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz
[ $(ls $DATA_DIR/fmriprep/$1/ses-* -d | wc -l) -gt 1 ] && T1_NATIVE=$DATA_DIR/fmriprep/$1/anat/${1}_desc-preproc_T1w.nii.gz

#FS2T1w=$DATA_DIR/fmriprep/$1/ses-$SESSION/anat/${1}_ses-${SESSION}_from-fsnative_to-T1w_mode-image_xfm.txt

# Define outputs
################

# For white matter mask
ASEG_FSNATIVE=$TMP_OUT/${1}_ses-${SESSION}_space-T1w_aseg.mgz
ASEG_NIFTI=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_aseg.nii.gz
#ASEG_T1w=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_aseg.nii.gz

WM_R=$TMP_OUT/${1}_ses-${SESSION}_space-T1w_hemi-R_desc-wm_mask.nii.gz 
WM_L=$TMP_OUT/${1}_ses-${SESSION}_space-T1w_hemi-L_desc-wm_mask.nii.gz
WMH=$TMP_OUT/${1}_ses-${SESSION}_space-T1w_desc-wmh_mask.nii.gz
WM_ALL=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-wm_mask.nii.gz

# For cortical ribbon which will be excluded from analysis to reduce partial volume effects
RIBBON_R_FSNATIVE=$TMP_OUT/${1}_ses-${SESSION}_space-T1w_hemi-R_desc-ribbon_mask.mgz
RIBBON_R_NIFTI=$TMP_OUT/${1}_ses-${SESSION}_space-T1w_hemi-R_desc-ribbon_mask.nii.gz
#RIBBON_R_T1w=$TMP_OUT/${1}_ses-${SESSION}_space-T1w_hemi-R_desc-ribbon_mask.nii.gz
RIBBON_L_FSNATIVE=$TMP_OUT/${1}_ses-${SESSION}_space-T1w_hemi-L_desc-ribbon_mask.mgz
RIBBON_L_NIFTI=$TMP_OUT/${1}_ses-${SESSION}_space-T1w_hemi-L_desc-ribbon_mask.nii.gz
#RIBBON_L_T1w=$TMP_OUT/${1}_ses-${SESSION}_space-fsnative_hemi-L_desc-ribbon_mask.nii.gz
RIBBON_ALL=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-ribbon_mask.nii.gz
RIBBON_ALL_DIL=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-ribbon_desc-dilated_mask.nii.gz

# For ventricles which will be excluded from analysis
# VENTRICLE_R=$TMP_OUT/${1}_ses-${SESSION}_space-T1w_hemi-R_desc-ventricle_mask.nii.gz
# VENTRICLE_L=$TMP_OUT/${1}_ses-${SESSION}_space-T1w_hemi-L_desc-ventricle_mask.nii.gz
# VENTRICLE_ALL=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-ventricle_mask.nii.gz

# For regions which will be excluded from analysis additionally 
# APARC_ASEG_FSNATIVE=$TMP_OUT/${1}_ses-${SESSION}_space-fsnative_aparc+aseg.mgz
# APARC_ASEG_NIFTI=$OUT_DIR/${1}_ses-${SESSION}_space-fsnative_aparc+aseg.nii.gz
# APARC_ASEG_T1w=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_aparc+aseg.nii.gz

# BRAINSTEM=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-brainstem_mask.nii.gz
# CEREBELLUM_L=$TMP_OUT/${1}_ses-${SESSION}_space-T1w_hemi-L_desc-cerebellum_mask.nii.gz
# CEREBELLUM_R=$TMP_OUT/${1}_ses-${SESSION}_space-T1w_hemi-R_desc-cerebellum_mask.nii.gz
# CEREBELLUM_ALL=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-cerebellum_mask.nii.gz

# Define commands
#################

# White matter mask
CMD_prepare_wmmask="mri_label2vol --seg $ASEG_MGZ --temp $T1_FSNATIVE_MGZ --o $ASEG_FSNATIVE --regheader $ASEG_MGZ"
CMD_convert_wmmask="mri_convert $ASEG_FSNATIVE $ASEG_NIFTI"
# Probably only necessary for longitudinal fmriprep run because images get transformed to T1w-template-space not native T1w-space
#CMD_transform_wmmask="antsApplyTransforms -i $ASEG_NIFTI -r $T1_NATIVE -o $ASEG_T1w -t $FS2T1w -n NearestNeighbor -u uchar"

CMD_create_wm_r="fslmaths $ASEG_NIFTI -thr 41 -uthr 41 -bin $WM_R"
CMD_create_wm_l="fslmaths $ASEG_NIFTI -thr 2 -uthr 2 -bin $WM_L"
CMD_create_wmh="fslmaths $ASEG_NIFTI -thr 77 -uthr 77 -bin $WMH"
CMD_merge_wmmasks="fslmaths $WM_R -add $WM_L -add $WMH -bin $WM_ALL"

# Cortical ribbon
CMD_prepare_ribbon_r="mri_label2vol --seg $RIBBON_R_MGZ --temp $T1_FSNATIVE_MGZ --o $RIBBON_R_FSNATIVE --regheader $RIBBON_R_MGZ"
CMD_convert_ribbon_r="mri_convert $RIBBON_R_FSNATIVE $RIBBON_R_NIFTI"
# Probably only necessary for longitudinal fmriprep run because images get transformed to T1w-template-space not native T1w-space
#CMD_transform_ribbon_r="antsApplyTransforms -i $RIBBON_R_NIFTI -r $T1_NATIVE -o $RIBBON_R_T1w -t $FS2T1w -n NearestNeighbor -u uchar"

CMD_prepare_ribbon_l="mri_label2vol --seg $RIBBON_L_MGZ --temp $T1_FSNATIVE_MGZ --o $RIBBON_L_FSNATIVE --regheader $RIBBON_L_MGZ"
CMD_convert_ribbon_r="mri_convert $RIBBON_L_FSNATIVE $RIBBON_L_NIFTI"
# Probably only necessary for longitudinal fmriprep run because images get transformed to T1w-template-space not native T1w-space
#CMD_transform_ribbon_l="antsApplyTransforms -i $RIBBON_L_NIFTI -r $T1_NATIVE -o $RIBBON_L_T1w -t $FS2T1w -n NearestNeighbor"

CMD_merge_ribbons="fslmaths $RIBBON_R_NIFTI -add $RIBBON_L_NIFTI $RIBBON_ALL"
CMD_dilate_ribbon="fslmaths $RIBBON_ALL -dilM $RIBBON_ALL_DIL"

# # Ventricles
# CMD_create_ventriclemask_right="fslmaths $ASEG_NIFTI -thr 43 -uthr 43 -bin $VENTRICLE_R"
# CMD_create_ventriclemask_left="fslmaths $ASEG_NIFTI -thr 4 -uthr 4 -bin $VENTRICLE_L"
# CMD_merge_ventriclemasks="fslmaths $VENTRICLE_R -add $VENTRICLE_L -bin $VENTRICLE_ALL"

# # Additional regions for mask refinement
# CMD_prepare_aparcaseg="mri_label2vol --seg $APARC_ASEG_MGZ --temp $T1_FSNATIVE_MGZ --o $APARC_ASEG_FSNATIVE --regheader $APARC_ASEG_MGZ"
# CMD_convert_aparcaseg="mri_convert $APARC_ASEG_FSNATIVE $APARC_ASEG_NIFTI"
# # Probably only necessary for longitudinal fmriprep run because images get transformed to T1w-template-space not native T1w-space
# #CMD_transform_wmmask="antsApplyTransforms -i $APARC_ASEG_NIFTI -r $T1_NATIVE -o $APARC_ASEG_T1w -t $FS2T1w -n NearestNeighbor -u int"

# CMD_extract_cerebellum_r="fslmaths $APARC_ASEG_NIFTI -thr 46 -uthr 47 -bin $CEREBELLUM_R"
# CMD_extract_cerebellum_l="fslmaths $APARC_ASEG_NIFTI -thr 7 -uthr 8 -bin $CEREBELLUM_L"
# CMD_merge_cerebellum="fslmaths $CEREBELLUM_R -add $CEREBELLUM_L $CEREBELLUM_ALL"
# CMD_extract_brainstem="fslmaths $APARC_ASEG_NFITI -thr 16 -uthr 16 -bin $BRAINSTEM"

# really necessary?
#( cp -ruvfL $ENV_DIR/freesurfer_license.txt $FREESURFER_CONTAINER/opt/$FREESURFER_VERSION/.license )

# Execute commands
##################

# White matter mask
$singularity_freesurfer $CMD_prepare_wmmask 
$singularity_freesurfer $CMD_convert_wmmask
#$singularity_mrtrix3 $CMD_transform_wmmask
$singularity_fsl $CMD_create_wm_r
$singularity_fsl $CMD_create_wm_l
$singularity_fsl $CMD_create_wmh
$singularity_fsl $CMD_merge_wmmasks

# Cortical ribbon
$singularity_freesurfer $CMD_prepare_ribbon_r 
$singularity_freesurfer $CMD_prepare_ribbon_l 
$singularity_freesurfer $CMD_convert_ribbon_r 
$singularity_freesurfer $CMD_convert_ribbon_l
#$singularity_mrtrix3 $CMD_transform_ribbon_r
#$singularity_mrtrix3 $CMD_transform_ribbon_l
$singularity_mrtrix3 $CMD_merge_ribbons
$singularity_mrtrix3 $CMD_dilate_ribbon

# # Ventricles
# $singularity_fsl $CMD_create_ventriclemask_right
# $singularity_fsl $CMD_create_ventriclemask_left
# $singularity_fsl $CMD_merge_ventriclemasks

# # Additional regions
# $singularity_freesurfer $CMD_prepare_aparcaseg
# $singularity_freesurfer $CMD_convert_aparcaseg
# $singularity_mrtrix3 $CMD_transform_wmmask
# $singularity_fsl $CMD_extract_cerebellum_l
# $singularity_fsl $CMD_extract_cerebellum_r
# $singularity_fsl $CMD_merge_cerebellum
# $singularity_fsl $CMD_extract_brainstem

##########################################################
# Refine white matter mask and register to readout space #
##########################################################

# Define output
###############

WM_REFINED=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-wm_desc-woribbon_mask.nii.gz

# Refine white matter mask
##########################

CMD_REFINE="fslmaths $WM_ALL -sub $RIBBON_ALL_DIL $WM_REFINED"

$singularity_fsl $CMD_REFINE

# Register white matter mask to readout space
#############################################

# If $READOUT_SPACE == "dwi" there is no need for registration because DWI is already registered to T1w space in qsiprep

WM_REFINED_REG=$WM_REFINED

# TO DO: Add other readout spaces

##########################################
# Flip lesion mask to contralateral side #
##########################################

if [ $FLIP == "yes" ]; then

    if [ $ORIG_SPACE == "T1w" ]; then

        # Define input
        ##############

        LESION_T1w=$LESION_DIR/$1/ses-$SESSION/anat/${1}_ses-${SESSION}_space-T1w_desc-lesion_mask.nii.gz
        MNI_TEMPLATE=$ENV_DIR/standard/tpl-MNI152NLin2009cAsym_res-01_desc-brain_T1w.nii.gz
        BRAIN_MASK=$DATA_DIR/fmriprep/$1/ses-$SESSION/anat/${1}_ses-${SESSION}_desc-brain_mask.nii.gz
        [ $(ls $DATA_DIR/fmriprep/$1/ses-* -d | wc -l) -gt 1 ] && BRAIN_MASK=$DATA_DIR/fmriprep/$1/anat/${1}_desc-brain_mask.nii.gz

        # Define output
        ###############

        RIGID=$OUT_DIR/${1}_ses-${SESSION}_from-T1w_to-MNI152NLin2009cAsym_desc-rigid_xfm.txt
        RIGID_INV=$OUT_DIR/${1}_ses-${SESSION}_from-MNI152NLin2009cAsym_to-T1w_desc-rigid_xfm.txt
        T1w_MNI=$OUT_DIR/${1}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-preproc_T1w.nii.gz
        LESION_MNI=$OUT_DIR/${1}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-lesion_mask.nii.gz
        LESION_MNI_FLIP=$OUT_DIR/${1}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-lesion_desc-flipped_mask.nii.gz
        LESION_T1w_FLIP=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-lesion_desc-flipped_mask.nii.gz

        # Affine registration of T1w image to MNI space to obtain transformation matrix
        ###############################################################################

        # Define command
        CMD_T1w2MNI="mrregister -mask1 $BRAIN_MASK -type rigid -rigid $RIGID -transformed $T1w_MNI $T1w_NATIVE $MNI_TEMPLATE"

        # Execute command
        $singularity_mrtrix3 $CMD_T1w2MNI

        # Apply transformation to lesion mask
        #####################################
        
        # Define command
        CMD_APPLY_XFM="mrtransform -linear $RIGID -interp nearest -datatype int32 $LESION_T1w $LESION_MNI"

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
        CMD_APPLY_XFM_INV="mrtransform -linear $RIGID -inverse -interp nearest -datatype int32 $LESION_MNI_FLIP $LESION_T1w_FLIP"

        # Execute command
        $singularity_mrtrix3 $CMD_APPLY_XFM_INV

    fi

fi

# TO DO: add other orig spaces

#################################################
# Registration of lesion masks to readout space #
#################################################

if [ $ORIG_SPACE == "T1w" ] && [ $READOUT_SPACE == "dwi" ]; then

    # Since DWI is registered to T1w-space in qsiprep, there is no need for further registration of lesion masks to DWI space

    # Define output
    ###############

    LESION_READOUT_RESIZED=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-lesion_res-2mm_mask.nii.gz
    LESION_READOUT_FLIP_RESIZED=$OUT_DIR/${1}_ses-${SESSION}_space-T1w_desc-lesion_res-2mm_desc-flipped_mask.nii.gz

    # Resize lesion masks to match voxel size of dwi
    ################################################

    # Define command
    CMD_RESIZE_IPSI="mrgrid -force -voxel 2 -interp nearest -datatype int32 $LESION_T1w regrid $LESION_READOUT_RESIZED"
    CMD_RESIZE_FLIP="mrgrid -force -voxel 2 -interp nearest -datatype int32 $LESION_T1w_FLIP regrid $LESION_READOUT_FLIP_RESIZED"
    
    # Execute command
    $singularity_mrtrix3 $CMD_RESIZE_IPSI
    [ $FLIP == "yes" ] && $singularity_mrtrix3 $CMD_RESIZE_FLIP

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
    
    if [ $FLIP == "yes" ]; then

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
    
    if [ $FLIP == "yes" ]; then

        # Create contralateral shells - include only white matter
        
        CMD_SHELL_FLIP="fslmaths ${LESION_FLIP_DIL_i}1_mask.nii.gz -sub $LESION_READOUT_FLIP_RESIZED -mul $WM_REFINED_REG ${LESION_FLIP_DIL_i}1_shell.nii.gz"
        $singularity_fsl $CMD_SHELL_FLIP

        for i in {2..8}; do
            
            CMD_SHELL_FLIP="fslmaths ${LESION_FLIP_DIL_i}${i}_mask.nii.gz -sub ${LESION_FLIP_DIL_i}$(($i-1))_mask.nii.gz -mul $WM_REFINED_REG ${LESION_FLIP_DIL_i}${i}_shell.nii.gz"
            $singularity_fsl $CMD_SHELL_FLIP
        
        done

        # Substract ipsi- and contralateral shells from each other to avoid overlap
        
        for i in {1..8}; do
            
            CMD_UNIQ_IPSI="fslmaths ${LESION_DIL_i}${i}_shell.nii.gz -sub ${LESION_FLIP_DIL_i}${i}_shell.nii.gz ${LESION_DIL_i}${i}_shell.nii.gz"
            CMD_UNIQ_FLIP="fslmaths ${LESION_FLIP_DIL_i}${i}_shell.nii.gz -sub ${LESION_DIL_i}${i}_shell.nii.gz ${LESION_FLIP_DIL_i}${i}_shell.nii.gz"
            $singularity_fsl $CMD_UNIQ_IPSI
            $singularity_fsl $CMD_UNIQ_FLIP
        
        done

    fi

fi

# TO DO: Add other readout spaces
