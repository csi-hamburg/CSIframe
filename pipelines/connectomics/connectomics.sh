#!/usr/bin/env bash

###################################################################################################################
# Connectome analysis based on                                                                                    #
#  Brain Connectivity Toolbox (Rubinov & Sporns, 2010, https://sites.google.com/site/bctnet/)                     #
#  Small World Propensity (Muldoon et al., 2016, https://complexsystemsupenn.com/s/SWP1.zip)                      #
#  Controllability (Gu et al., 2015, https://complexsystemsupenn.com/s/controllability_code-smb8.zip)             #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - qsiprep & qsirecon for structural connectomics                                                          #
#       - fmriprep & xcpengine for functional connectomics                                                        #                                                                                 #
###################################################################################################################

# Get verbose outputs
set -x

# Define subject specific temporary directory on $SCRATCH_DIR
export TMP_DIR=$SCRATCH_DIR/$1/tmp/;   [ ! -d $TMP_DIR ] && mkdir -p $TMP_DIR
TMP_IN=$TMP_DIR/input;                 [ ! -d $TMP_IN ] && mkdir -p $TMP_IN
TMP_OUT=$TMP_DIR/output;               [ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT

###################################################################################################################

# Define subject array
input_subject_array=($@)

# Define environment
#########################

CONN_DIR=$DATA_DIR/connectomics
[ ! -d $CONN_DIR/derivatives ] && mkdir -p $CONN_DIR/derivatives

# Max threads for hpc matlab set to 16 by admins
parpool_threads=16
#parpool_threads=$SLURM_CPUS_PER_TASK
#[ $parpool_threads -ge 16 ] && parpool_threads=16

for sub in ${input_subject_array[@]};do

    if [ $MODIFIER == sc ];then

        INPUT_DIR=$DATA_DIR/qsirecon

        # Execute 
        for atlas in schaefer100x7 schaefer200x7 schaefer400x7 schaefer100x17 schaefer200x17 schaefer400x17; do
            matlab -nosplash -nodesktop -batch \
            "addpath(genpath('$ENV_DIR/matlab_toolboxes')); addpath(genpath('$CODE_DIR/pipelines/connectomics'));connectomics('$sub','$INPUT_DIR', '$CONN_DIR', 'ses-$SESSION', $parpool_threads, '$atlas', 'sc', 'sift', '$TMP_DIR', '$ENV_DIR/standard/'); quit"
        done


    elif [ $MODIFIER == fc ];then
        

        INPUT_DIR=$DATA_DIR/xcpengine

        # Execute 
        for atlas in schaefer100x7 schaefer200x7 schaefer400x7 schaefer100x17 schaefer200x17 schaefer400x17; do
            matlab -nosplash -nodesktop -batch \
            "addpath(genpath('$ENV_DIR/matlab_toolboxes')); addpath(genpath('$CODE_DIR/pipelines/connectomics')); connectomics('$sub','$INPUT_DIR', '$CONN_DIR', 'ses-$SESSION', $parpool_threads, '$atlas', 'fc', '36pspkreg', '$TMP_DIR', '$ENV_DIR/standard/'); quit"
        done

    fi

done
