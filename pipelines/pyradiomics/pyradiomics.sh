#!/usr/bin/env bash
set -x

###################################################################################################################
# Extraction of radiomics features based on https://pyradiomics.readthedocs.io/en/latest/index.html               #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - fmriprep (anat)
#       - wmh (WMH masks and FLAIR in MNI)                                                                        #
#   [optional]                                                                                                    #
#       - freewater                                                                                               #
#       - fmriprep & xcpengine                                                                                    #
#       - aslprep                                                                                                 #
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
T1w_MNI=sub-002144a4_ses-1_space-MNI152NLin6Asym_desc-preproc_T1w.nii.gz
FLAIR_MNI

# Output
#########################

# Command
#########################

# Execution
#########################


foreach_="for_each -nthreads $SLURM_CPUS_PER_TASK ${input_subject_array[@]} :"
parallel="parallel --ungroup --delay 0.2 -j$SUBJS_PER_NODE --joblog $CODE_DIR/log/parallel_runtask.log"