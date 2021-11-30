#!/usr/bin/env bash

###################################################################################################################
# FBA based on https://mrtrix.readthedocs.io/en/latest/fixel_based_analysis/st_fibre_density_cross-section.html   #
#                                                                                                                 #
# Step 3: Population template creation                                                                            #
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
export SINGULARITYENV_MRTRIX_TMPFILE_DIR=/tmp


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

    DWI_MASK_UPSAMPLED_="$DATA_DIR/fba/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_acq-AP_space-T1w_desc-upsampled_desc-brain_mask.nii.gz"
    FOD_WM_="$FBA_DIR/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_acq-AP_space-T1w_desc-responsemean_desc-preproc_desc-wmFODmtnormed_ss3tcsd.mif.gz"
    [ -f $DWI_MASK_UPSAMPLED_ ] && ln -srf $FOD_WM_ $FOD_GROUP_DIR
    [ -f $FOD_WM_ ] && ln -srf $DWI_MASK_UPSAMPLED_ $MASK_GROUP_DIR

done

# Output
#########################
FOD_TEMPLATE="$FBA_GROUP_DIR/template/wmfod_template.mif"

# Command
#########################
CMD_POPTEMP="population_template $FOD_GROUP_DIR -mask_dir $MASK_GROUP_DIR $FOD_TEMPLATE -scratch /tmp -voxel_size 1.25 -force"

# Execution
#########################
$singularity_mrtrix3 $CMD_POPTEMP
