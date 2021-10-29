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

FBA_DIR=$DATA_DIR/fba
FBA_GROUP_DIR=$DATA_DIR/fba/derivatives
TEMPLATE_SUBJECTS_TXT=$FBA_DIR/sourcedata/template_subjects.txt
TEMPLATE_RANDOM_SUBJECTS_TXT=$FBA_DIR/sourcedata/random_template_subjects.txt
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
# POPULATION_TEMPLATE
#########################

# Input
#########################

# Prepare group directories with symlinks of FODs and masks for population_template input 
if [ -f $TEMPLATE_SUBJECTS_TXT ];then
    readarray template_subject_array < $TEMPLATE_SUBJECTS_TXT
elif [ -f $TEMPLATE_RANDOM_SUBJECTS_TXT ];then
    readarray template_subject_array < $TEMPLATE_RANDOM_SUBJECTS_TXT
else
    template_subject_array=($(echo ${input_subject_array[@]} | sort -R | tail -40))
    echo ${template_subject_array[@]} >> $TEMPLATE_RANDOM_SUBJECTS_TXT
fi

FOD_GROUP_DIR=$FBA_GROUP_DIR/template/fod_input
MASK_GROUP_DIR=$FBA_GROUP_DIR/template/mask_input

[ ! -d $FOD_GROUP_DIR ] && mkdir -p $FOD_GROUP_DIR $MASK_GROUP_DIR || rm -rf $FOD_GROUP_DIR/* $MASK_GROUP_DIR/*

for sub in ${template_subject_array[@]};do

    DWI_MASK_UPSAMPLED_="$DATA_DIR/qsiprep/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_acq-AP_space-T1w_desc-brain_mask.nii.gz"
    FOD_WM_="$FBA_DIR/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_acq-AP_space-T1w_desc-responsemean_desc-preproc_desc-wmFODmtnormed_ss3tcsd.mif.gz"
    [ -f $DWI_MASK_UPSAMPLED_ ] && ln -sr $FOD_WM_ $FOD_GROUP_DIR
    [ -f $FOD_WM_ ] && ln -sr $DWI_MASK_UPSAMPLED_ $MASK_GROUP_DIR

done

# Output
#########################
FOD_TEMPLATE="$FBA_GROUP_DIR/template/wmfod_template.mif"

# Command
#########################
CMD_POPTEMP="population_template $FOD_GROUP_DIR -mask_dir $MASK_GROUP_DIR $FOD_TEMPLATE -voxel_size 1.3 -force"

# Execution
#########################
$singularity_mrtrix3 $CMD_POPTEMP