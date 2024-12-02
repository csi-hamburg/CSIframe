#!/usr/bin/env bash

###################################################################################################################
# Diffusion prepocessing and structural connectome reconstruction (https://qsiprep.readthedocs.io/en/latest/)     #
#                                                                                                                 #
# Internal documentation:                                                                                         #
#   https://github.com/csi-hamburg/hummel_processing/wiki/Diffusion-MRI-Preprocessing                             #
#   https://github.com/csi-hamburg/hummel_processing/wiki/Structural-Connectome-Reconstruction                    #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - qsiprep                                                                                                 #
#       - a pipeline providing freesurfer output                                                                  #
#   [container]                                                                                                   #
#       - qsiprep-0.22.0.sif                                                                                      #
#                                                                                                                 #
# Author: Marvin Petersen (m-petersen), Felix Nägele (felenae)                                                    #
###################################################################################################################

# Get verbose outputs
set -x

# Define subject specific temporary directory on $SCRATCH_DIR
export TMP_DIR=$SCRATCH_DIR/$1/tmp/;   [ ! -d $TMP_DIR ] && mkdir -p $TMP_DIR
TMP_IN=$TMP_DIR/input;                 [ ! -d $TMP_IN ] && mkdir -p $TMP_IN
TMP_OUT=$TMP_DIR/output;               [ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT

###################################################################################################################

#################################
# Pipeline-specific environment #
#################################

# apptainer container version and command
container_qsiprep=qsiprep-0.22.0.sif
apptainer_qsiprep="apptainer run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_qsiprep" 

# To make I/O more efficient read/write outputs from/to $SCRATCH
[ -d $TMP_IN ] && cp -rvf $BIDS_DIR/$1 $BIDS_DIR/dataset_description.json $TMP_IN 
[ -d $TMP_OUT ] && mkdir -p $TMP_OUT/qsiprep $TMP_OUT/qsirecon $TMP_OUT/freesurfer
[ -f $DATA_DIR/freesurfer/$1/stats/aseg.stats ] && cp -rvf $DATA_DIR/freesurfer/$1 $TMP_OUT/freesurfer
[ -d $DATA_DIR/qsiprep/$1 ] && cp -rvf $DATA_DIR/qsiprep/$1 $TMP_OUT/qsiprep/$1

# $MRTRIX_TMPFILE_DIR should be big and writable
export MRTRIX_TMPFILE_DIR=/tmp

######################
# Pipeline execution #
######################

# Part 1: Run reorient to FSL pipeline
######################################

# Reorients the preprocessed DWI and bval/bvec to the standard FSL orientation. 
# This can be useful if FSL tools will be applied outside of qsiprep

# Define command
CMD="
$apptainer_qsiprep \
/tmp_in /tmp_out participant \
-w /tmp \
--participant-label $1 \
--skip-bids-validation \
--nthreads $GNU_CPUS_PER_TASK \
--omp-nthreads $OMP_NTHREADS \
--mem_mb $MEM_MB \
--stop-on-first-crash \
--recon-only \
--recon_input /tmp_out/qsiprep/ \
--recon_spec reorient_fslstd \
--output-resolution $OUTPUT_RESOLUTION \
--freesurfer-input /tmp_out/freesurfer \
--fs-license-file envs/freesurfer_license.txt"

if [ $MODIFIER == "y" ]; then

    # Execute command
    eval $CMD

fi

# Part 2: Run recon pipeline
############################

# Define command
CMD="
   $apptainer_qsiprep \
   /tmp_in /tmp_out participant \
   -w /tmp \
   --participant-label $1 \
   --skip-bids-validation \
   --nthreads $SLURM_CPUS_PER_TASK \
   --omp-nthreads $OMP_NTHREADS \
   --mem_mb $MEM_MB \
   --stop-on-first-crash \
   --recon-only \
   --recon_input /tmp_out/qsiprep/ \
   --recon_spec $RECON \
   --output-resolution $OUTPUT_RESOLUTION \
   --freesurfer-input /tmp_out/freesurfer \
   --fs-license-file envs/freesurfer_license.txt"

# Execute command
if [ ! -z $RECON ]; then
    
    eval $CMD

else

    echo "No recon pipeline specified"

fi

# Part 3: Save outputs
#######################

# Copy outputs to $DATA_DIR
cp -ruvf $TMP_OUT/* $DATA_DIR