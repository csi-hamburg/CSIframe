#!/usr/bin/env bash

###################################################################################################################
# FBA based on https://mrtrix.readthedocs.io/en/latest/fixel_based_analysis/st_fibre_density_cross-section.html   #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - qsiprep                                                                                                 #
#       - previous fba steps
#   [container]                                                                                                   #
#       - mrtrix3-3.0.2.sif                                                                                       #
#       - mrtrix3tissue-5.2.8.sif                                                                                 #
#       - tractseg-master.sif                                                                                     #
###################################################################################################################

# Get verbose outputs
set -x

# Define subject specific temporary directory on $SCRATCH_DIR
export TMP_DIR=$SCRATCH_DIR/$1/tmp/;   [ ! -d $TMP_DIR ] && mkdir -p $TMP_DIR
TMP_IN=$TMP_DIR/input;                 [ ! -d $TMP_IN ] && mkdir -p $TMP_IN
TMP_OUT=$TMP_DIR/output;               [ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT

###################################################################################################################

# Define environment
#########################
module load parallel

FBA_DIR=$DATA_DIR/fba
FBA_GROUP_DIR=$FBA_DIR/derivatives; [ ! -d $FBA_GROUP_DIR ] && mkdir -p $FBA_GROUP_DIR
TEMPLATE_SUBJECTS_TXT=$FBA_DIR/sourcedata/template_subjects.txt
TEMPLATE_RANDOM_SUBJECTS_TXT=$FBA_DIR/sourcedata/random_template_subjects.txt
export SINGULARITYENV_MRTRIX_TMPFILE_DIR=$TMP_DIR


container_mrtrix3=mrtrix3-3.0.2      
container_mrtrix3tissue=mrtrix3tissue-5.2.8
container_tractseg=tractseg-master

singularity_mrtrix3="singularity run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_mrtrix3" 

singularity_mrtrix3tissue="singularity run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_mrtrix3tissue" 

singularity_tractseg="singularity run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_tractseg" 

parallel="parallel --ungroup --delay 0.2 -j16 --joblog $CODE_DIR/log/parallel_runtask.log"

# Define subject array
input_subject_array=($@)



#########################
# DWI2RESPONSE
#########################

# Input
#########################
DWI_PREPROC_NII="$DATA_DIR/qsiprep/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_dwi.nii.gz"
DWI_PREPROC_GRAD_TABLE="$DATA_DIR/qsiprep/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_dwi.b"
DWI_MASK_NII="$DATA_DIR/qsiprep/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_space-T1w_desc-brain_mask.nii.gz"

# Output
#########################
DWI_PREPROC_MIF="/tmp/{}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_dwi.mif"
DWI_PREPROC_UPSAMPLED="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_desc-upsampled_dwi.mif.gz"
DWI_MASK_UPSAMPLED="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_space-T1w_desc-upsampled_desc-brain_mask.nii.gz"
RESPONSE_WM="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_space-T1w_desc-responsemean_desc-preproc_desc-wmFODdhollander2019_ss3tcsd.txt"
RESPONSE_GM="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_space-T1w_desc-responsemean_desc-preproc_desc-gmFODdhollander2019_ss3tcsd.txt"
RESPONSE_CSF="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_space-T1w_desc-responsemean_desc-preproc_desc-csfFODdhollander2019_ss3tcsd.txt"

# Command
#########################
CMD_SUBDIR="[ ! -d $FBA_DIR/{}/ses-$SESSION/dwi/ ] && mkdir -p $FBA_DIR/{}/ses-$SESSION/dwi/"
CMD_CONVERT="mrconvert $DWI_PREPROC_NII -grad $DWI_PREPROC_GRAD_TABLE $DWI_PREPROC_MIF -force"
CMD_UPSAMPLE_DWI="mrgrid $DWI_PREPROC_MIF regrid -vox 1.25 $DWI_PREPROC_UPSAMPLED -force"
CMD_UPSAMPLE_MASK="mrgrid $DWI_MASK_NII regrid -vox 1.25 $DWI_MASK_UPSAMPLED -force"
CMD_DWI2RESPONSE="dwi2response dhollander -nthreads 16 $DWI_PREPROC_UPSAMPLED $RESPONSE_WM $RESPONSE_GM $RESPONSE_CSF -mask $DWI_MASK_UPSAMPLED -force"

# Execution
#########################

$parallel "$singularity_mrtrix3tissue $CMD_SUBDIR" ::: ${input_subject_array[@]}
$parallel "$singularity_mrtrix3tissue $CMD_CONVERT" ::: ${input_subject_array[@]}
$parallel "$singularity_mrtrix3tissue $CMD_UPSAMPLE_DWI" ::: ${input_subject_array[@]}
$parallel "$singularity_mrtrix3tissue $CMD_UPSAMPLE_MASK" ::: ${input_subject_array[@]}
$parallel "$singularity_mrtrix3tissue $CMD_DWI2RESPONSE" ::: ${input_subject_array[@]}

#########################
# RESPONSEMEAN
#########################

# Input
#########################
RESPONSE_WM_DIR="$FBA_GROUP_DIR/responsemean/response_wm"
RESPONSE_GM_DIR="$FBA_GROUP_DIR/responsemean/response_gm"
RESPONSE_CSF_DIR="$FBA_GROUP_DIR/responsemean/response_csf"

# Collect in group dir
#########################
[ ! -d $RESPONSE_WM_DIR ] && mkdir -p $RESPONSE_WM_DIR $RESPONSE_GM_DIR $RESPONSE_CSF_DIR
for sub in ${input_subject_array[@]};do

    [ ! -d $FBA_DIR/$sub/ses-${SESSION}/dwi ] && mkdir -p $FBA_DIR/$sub/ses-${SESSION}/dwi
    #RESPONSE_WM="$FBA_DIR/$sub/ses-${SESSION}/dwi/${sub}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_space-T1w_desc-wmFOD_ss3tcsd.txt"
    #RESPONSE_GM="$DATA_DIR/qsirecon/$sub/ses-${SESSION}/dwi/${sub}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_space-T1w_desc-gmFOD_ss3tcsd.txt"
    #RESPONSE_CSF="$DATA_DIR/qsirecon/$sub/ses-${SESSION}/dwi/${sub}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_space-T1w_desc-csfFOD_ss3tcsd.txt"

    RESPONSE_WM="$FBA_DIR/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_acq-AP_space-T1w_desc-responsemean_desc-preproc_desc-wmFODdhollander2019_ss3tcsd.txt"
    RESPONSE_GM="$FBA_DIR/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_acq-AP_space-T1w_desc-responsemean_desc-preproc_desc-gmFODdhollander2019_ss3tcsd.txt"
    RESPONSE_CSF="$FBA_DIR/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_acq-AP_space-T1w_desc-responsemean_desc-preproc_desc-csfFODdhollander2019_ss3tcsd.txt"

    [ -f $RESPONSE_WM ] && ln -srf $RESPONSE_WM $RESPONSE_WM_DIR
    [ -f $RESPONSE_WM ] && ln -srf $RESPONSE_GM $RESPONSE_GM_DIR
    [ -f $RESPONSE_WM ] && ln -srf $RESPONSE_CSF $RESPONSE_CSF_DIR

done

# Output
#########################
GROUP_RESPONSE_WM="$FBA_GROUP_DIR/responsemean/group_average_response_wmFOD_ss3tcsd.txt"
GROUP_RESPONSE_GM="$FBA_GROUP_DIR/responsemean/group_average_response_gmFOD_ss3tcsd.txt"
GROUP_RESPONSE_CSF="$FBA_GROUP_DIR/responsemean/group_average_response_csfFOD_ss3tcsd.txt"

# Command
#########################
CMD_RESPONSEMEAN_WM="responsemean -f $RESPONSE_WM_DIR/* $GROUP_RESPONSE_WM -force"
CMD_RESPONSEMEAN_GM="responsemean -f $RESPONSE_GM_DIR/* $GROUP_RESPONSE_GM -force"
CMD_RESPONSEMEAN_CSF="responsemean -f $RESPONSE_CSF_DIR/* $GROUP_RESPONSE_CSF -force"

# Execution
#########################
$singularity_mrtrix3tissue \
/bin/bash -c "$CMD_RESPONSEMEAN_WM; $CMD_RESPONSEMEAN_GM; $CMD_RESPONSEMEAN_CSF"

