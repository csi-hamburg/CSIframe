#!/usr/bin/env bash
set -x

###################################################################################################################
# Extraction of radiomics features based on https://pyradiomics.readthedocs.io/en/latest/index.html               #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - wmh (WMH masks and FLAIR in MNI)                                                                        #
#   [optional]                                                                                                    #
#       - freewater (FA, MD, FW)                                                                                  #
#       - fmriprep & xcpengine (ReHo)                                                                             #
#       - aslprep (CBF, CBV)                                                                                      #
#   [container]                                                                                                   #
#       - pyradiomics_latest.sif                                                                                  #
###################################################################################################################

# Define subject array

input_subject_array=($@)

# Define environment
#########################
module load parallel

PYRADIOMICS_DIR=$DATA_DIR/pyradiomics
container_pyradiomics=pyradiomics_latest

[ ! -d $PYRADIOMICS_DIR ] && mkdir -p $PYRADIOMICS_DIR

singularity_pyradiomics="singularity run --cleanenv --userns \
    -B . \
    -B $PROJ_DIR \
    -B $SCRATCH_DIR:/tmp \
    $ENV_DIR/$container_pyradiomics" 

#########################
# T1w
#########################

# Input
#########################
INPUT=$DATA_DIR/fmriprep/$1/ses-$SESSION/anat/${1}_ses-${session}_space-MNI152NLin6Asym_desc-preproc_T1w.nii.gz
INPUT_WMH_MASK=

# Output
#########################
OUT_WMH_CSV=$PYRADIOMICS_DIR/$1/ses-$SESSION/anat/T1w.csv

# Command
#########################
CMD_PYRADIOMICS="pyradiomics $INPUT $INPUT_WMH_MASK --out $OUT_WMH_CSV -f csv --mode segment --format-path basename --jobs $SLURM_CPUS_PER_TASK" #--out-dir .

# Execution
#########################
[ -f $INPUT ] && $singularity_pyradiomics $CMD_PYRADIOMICS