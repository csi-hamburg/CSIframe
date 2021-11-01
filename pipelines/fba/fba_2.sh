#!/usr/bin/env bash
set -x

###################################################################################################################
# FBA based on https://mrtrix.readthedocs.io/en/latest/fixel_based_analysis/st_fibre_density_cross-section.html   #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - qsiprep & qsirecon                                                                                      #
#   [optional]                                                                                                    #
#       - freewater (to warp freewater results to group template)                                                 #
#   [container]                                                                                                   #
#       - mrtrix3-3.0.2.sif                                                                                       #
#       - mrtrix3tissue-5.2.8.sif                                                                                 #
#       - tractseg-master.sif                                                                                     #
###################################################################################################################


# Define subject array
#########################
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
    -B $(readlink -f $ENV_DIR) \
    -B $PROJ_DIR \
    -B $SCRATCH_DIR:/tmp \
    $ENV_DIR/$container_mrtrix3" 

singularity_mrtrix3tissue="singularity run --cleanenv --userns \
    -B $(readlink -f $ENV_DIR) \
    -B $PROJ_DIR \
    -B $SCRATCH_DIR:/tmp \
    $ENV_DIR/$container_mrtrix3tissue" 

foreach_="for_each -nthreads $SLURM_CPUS_PER_TASK ${input_subject_array[@]} :"
parallel="parallel --ungroup --delay 0.2 -j$SUBJS_PER_NODE --joblog $CODE_DIR/log/parallel_runtask.log"


#########################
# DWI2FOD & MTNORMALISE
#########################

# Input
#########################
DWI_PREPROC_UPSAMPLED_MIF="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_dwi.mif.gz"
DWI_MASK_UPSAMPLED="$DATA_DIR/qsiprep/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_space-T1w_desc-brain_mask.nii.gz"
GROUP_RESPONSE_WM="$FBA_GROUP_DIR/responsemean/group_average_response_wmFOD_ss3tcsd.txt"
GROUP_RESPONSE_GM="$FBA_GROUP_DIR/responsemean/group_average_response_gmFOD_ss3tcsd.txt"
GROUP_RESPONSE_CSF="$FBA_GROUP_DIR/responsemean/group_average_response_csfFOD_ss3tcsd.txt"

# Output
#########################
FOD_WM="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_space-T1w_desc-responsemean_desc-preproc_desc-wmFODmtnormed_ss3tcsd.mif.gz"
FOD_GM="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_space-T1w_desc-responsemean_desc-preproc_desc-gmFODmtnormed_ss3tcsd.mif.gz"
FOD_CSF="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_space-T1w_desc-responsemean_desc-preproc_desc-csfFODmtnormed_ss3tcsd.mif.gz"

# Command
#########################
CMD_DWI2FOD="ss3t_csd_beta1 -nthreads $SLURM_CPUS_PER_TASK $DWI_PREPROC_UPSAMPLED_MIF $GROUP_RESPONSE_WM $FOD_WM $GROUP_RESPONSE_GM $FOD_GM $GROUP_RESPONSE_CSF $FOD_CSF -mask $DWI_MASK_UPSAMPLED -force"
CMD_MTNORMALISE="mtnormalise $FOD_WM $FOD_WM $FOD_GM $FOD_GM $FOD_CSF $FOD_CSF -mask $DWI_MASK_UPSAMPLED -force"

# Execution
#########################
$parallel "$singularity_mrtrix3tissue $CMD_DWI2FOD" ::: ${input_subject_array[@]}
$parallel "$singularity_mrtrix3tissue $CMD_MTNORMALISE" ::: ${input_subject_array[@]}

