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

input_subject_array=($@)

# Define environment
#########################
module load parallel

FW_DIR=$DATA_DIR/freewater
FBA_DIR=$DATA_DIR/fba
FBA_GROUP_DIR=$DATA_DIR/fba/derivatives
TEMPLATE_SUBJECTS_TXT=$FBA_DIR/sourcedata/template_subjects.txt
container_mrtrix3=mrtrix3-3.0.2      
container_mrtrix3tissue=mrtrix3tissue-5.2.8
container_tractseg=tractseg-master
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

singularity_tractseg="singularity run --cleanenv --userns \
    -B . \
    -B $PROJ_DIR \
    -B $SCRATCH_DIR:/tmp \
    $ENV_DIR/$container_tractseg" 

foreach_="for_each -nthreads $SLURM_CPUS_PER_TASK ${input_subject_array[@]} :"
parallel="parallel --ungroup --delay 0.2 -j$SUBJS_PER_NODE --joblog $CODE_DIR/log/parallel_runtask.log"


#########################
# FA TO TEMPLATE + AVG
#########################

FA_TEMP_DIR=$FBA_DIR/derivatives/fa_template_dir
[ ! -d $FA_TEMP_DIR ] && mkdir $FA_TEMP_DIR

# Input
#########################
FA="$FW_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-T1w_desc-FWcorrected_FA.nii.gz"
SUB2TEMP_WARP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_from-subject_to-fodtemplate_warp.mif"

# Output
#########################
FA_TEMP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-FWcorrected_FA.nii.gz"

# Command
#########################
CMD_MRTRANSFORM="mrtransform $FA -warp $SUB2TEMP_WARP -interp nearest -datatype bit $FA_TEMP -force"
CMD_AVG="mrmath $FA_TEMP_DIR/* mean $FBA_DIR/derivatives/FA_averaged.nii.gz"

# Execution
#########################
$parallel "$singularity_mrtrix3 $CMD_MRTRANSFORM" ::: ${input_subject_array[@]}
$parallel ln -sr $FA_TEMP $FA_TEMP_DIR ::: ${input_subject_array[@]}
$singularity_mrtrix3 $CMD_AVG
