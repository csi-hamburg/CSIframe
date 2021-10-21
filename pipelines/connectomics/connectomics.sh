#!/usr/bin/env bash
set -x

###################################################################################################################
# Graph theoretical metric derivation                                                                             #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - qsiprep & qsirecon for structural connectomics                                                          #
#       - fmriprep & xcpengine for functional connectomics                                                        #
###################################################################################################################

# Define subject array

input_subject_array=($@)

# Define environment
#########################
module load matlab/2019b

CONN_DIR=$DATA_DIR/connectomics
[ ! -d $CONN_DIR/derivatives ] && mkdir -p $CONN_DIR/derivatives

for sub in ${input_subject_array[@]};do

    if [ $MODIFIER == sc ];then

        INPUT_DIR=$DATA_DIR/qsirecon

        # Execute 
        for atlas in schaefer100x17 schaefer200x17 schaefer400x17; do
            matlab -nosplash -nodesktop -batch \
            "addpath(genpath('$CODE_DIR/pipelines/connectomics/matlab_toolboxes')); connectomics('$sub','$INPUT_DIR', '$CONN_DIR', 'ses-$SESSION', $SLURM_CPUS_PER_TASK, '$atlas', 'sc', 'sift', '$TMP_DIR', '$ENV_DIR/standard/'); quit"
        done


    elif [ $MODIFIER == fc ];then
        

        INPUT_DIR=$DATA_DIR/xcpengine

        # Execute 
        for atlas in schaefer100x17 schaefer200x17 schaefer400x17; do
            matlab -nosplash -nodesktop -batch \
            "addpath(genpath('$CODE_DIR/pipelines/connectomics/matlab_toolboxes')); connectomics('$sub','$INPUT_DIR', '$CONN_DIR', 'ses-$SESSION', $SLURM_CPUS_PER_TASK, '$atlas', 'fc', '36pspkreg', '$TMP_DIR', '$ENV_DIR/standard/'); quit"
        done

    fi

done
