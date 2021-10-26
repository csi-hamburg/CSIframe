#!/usr/bin/env bash
set -x

###################################################################################################################
# FBA based on https://mrtrix.readthedocs.io/en/latest/fixel_based_analysis/st_fibre_density_cross-section.html   #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - qsiprep                                                                                                 #
#   [optional]                                                                                                    #
#       - freewater (to warp freewater results to group template)                                                 #
#   [container]                                                                                                   #
#       - mrtrix3-3.0.2.sif                                                                                       #
#       - mrtrix3tissue-5.2.8.sif                                                                                 #
#       - tractseg-master.sif                                                                                     #
###################################################################################################################

# Define subject array

input_subject_array=($@)

# Define environment
#########################
module load parallel

FBA_DIR=$DATA_DIR/fba
FBA_GROUP_DIR=$DATA_DIR/fba/derivatives
TEMPLATE_SUBJECTS_TXT=$FBA_DIR/sourcedata/template_subjects.txt
container_mrtrix3=mrtrix3-3.0.2      
container_mrtrix3tissue=mrtrix3tissue-5.2.8
export SINGULARITYENV_MRTRIX_TMPFILE_DIR=$TMP_DIR

[ ! -d $FBA_GROUP_DIR ] && mkdir -p $FBA_GROUP_DIR
singularity_mrtrix3="singularity run --cleanenv --userns \
    -B . \
    -B $PROJ_DIR \
    -B $SCRATCH_DIR:/tmp \
    $ENV_DIR/$container_mrtrix3" 

singularity_mrtrix3tissue="singularity run --cleanenv --userns \
    -B . \
    -B $PROJ_DIR \
    -B $SCRATCH_DIR:/tmp \
    $ENV_DIR/$container_mrtrix3tissue" 

foreach_="for_each -nthreads $SLURM_CPUS_PER_TASK ${input_subject_array[@]} :"
parallel="parallel --ungroup --delay 0.2 -j$SUBJS_PER_NODE --joblog $CODE_DIR/log/parallel_runtask.log"

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
DWI_PREPROC_MIF="/tmp/{}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_dwi.mif.gz"
DWI_PREPROC_UPSAMPLED_MIF="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_desc-upsampled_dwi.mif.gz"
DWI_MASK_UPSAMPLED_MIF="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_desc-upsampled_dwi.mif.gz"
RESPONSE_WM="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_space-T1w_desc-responsemean_desc-preproc_desc-wmFODdhollander2019_ss3tcsd.txt"
RESPONSE_GM="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_space-T1w_desc-responsemean_desc-preproc_desc-gmFODdhollander2019_ss3tcsd.txt"
RESPONSE_CSF="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_space-T1w_desc-responsemean_desc-preproc_desc-csfFODdhollander2019_ss3tcsd.txt"

# Command
#########################
CMD_SUBDIR="[ ! -d $FBA_DIR/{}/ses-$SESSION/dwi/ ] && mkdir -p $FBA_DIR/{}/ses-$SESSION/dwi/"
CMD_CONVERT="mrconvert $DWI_PREPROC_NII -grad $DWI_PREPROC_GRAD_TABLE $DWI_PREPROC_MIF -force"
CMD_UPSAMPLE_DWI="mrgrid $DWI_PREPROC_MIF regrid -vox 1.25 $DWI_PREPROC_UPSAMPLED_MIF -force; rm $DWI_PREPROC_MIF; mrgrid $DWI_MASK_NII regrid 1.25 $DWI_MASK_UPSAMPLED"
CMD_DWI2RESPONSE="dwi2response dhollander $DWI_PREPROC_UPSAMPLED_MIF $RESPONSE_WM $RESPONSE_GM $RESPONSE_CSF -mask $DWI_MASK_UPSAMPLED -force"

# Execution
#########################

$parallel "$singularity_mrtrix3tissue $CMD_SUBDIR" ::: ${input_subject_array[@]}
$parallel "$singularity_mrtrix3tissue $CMD_CONVERT" ::: ${input_subject_array[@]}
$parallel "$singularity_mrtrix3tissue $CMD_UPSAMPLE_DWI" ::: ${input_subject_array[@]}
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
    RESPONSE_WM="$DATA_DIR/qsirecon/$sub/ses-${SESSION}/dwi/${sub}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_space-T1w_desc-wmFOD_ss3tcsd.txt"
    RESPONSE_GM="$DATA_DIR/qsirecon/$sub/ses-${SESSION}/dwi/${sub}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_space-T1w_desc-gmFOD_ss3tcsd.txt"
    RESPONSE_CSF="$DATA_DIR/qsirecon/$sub/ses-${SESSION}/dwi/${sub}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_space-T1w_desc-csfFOD_ss3tcsd.txt"
    ln -sr $RESPONSE_WM $RESPONSE_WM_DIR
    ln -sr $RESPONSE_GM $RESPONSE_GM_DIR
    ln -sr $RESPONSE_CSF $RESPONSE_CSF_DIR

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

