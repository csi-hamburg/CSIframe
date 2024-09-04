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
#       - none                                                                                                    #
#   [container]                                                                                                   #
#       - qsiprep-0.18.1.sif                                                                                      #
#                                                                                                                 #
# Author: Marvin Petersen (m-petersen)                                                                            #
###################################################################################################################

# Get verbose outputs
set -x

# Define subject specific temporary directory on $SCRATCH_DIR
export TMP_DIR=$SCRATCH_DIR/$1/tmp/;   [ ! -d $TMP_DIR ] && mkdir -p $TMP_DIR
TMP_IN=$TMP_DIR/input;                 [ ! -d $TMP_IN ] && mkdir -p $TMP_IN
TMP_OUT=$TMP_DIR/output;               [ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT

###################################################################################################################

# Pipeline-specific environment
##################################

# Singularity container version and command
container_qsiprep=qsiprep-0.18.1
singularity_qsiprep="singularity run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_qsiprep" 

# To make I/O more efficient read/write outputs from/to $SCRATCH
[ -d $TMP_IN ] && cp -rf $BIDS_DIR/$1 $BIDS_DIR/dataset_description.json $TMP_IN 
[ -d $TMP_OUT ] && mkdir -p $TMP_OUT/qsiprep $TMP_OUT/qsirecon $TMP_OUT/freesurfer
[ -d data/qsiprep/$1 ] && cp -rf data/qsiprep/$1 $TMP_OUT/qsiprep/$1
[ -f $DATA_DIR/freesurfer/$1/stats/aseg.stats ] && cp -rf $DATA_DIR/freesurfer/$1 $TMP_OUT/freesurfer


# $MRTRIX_TMPFILE_DIR should be big and writable
export MRTRIX_TMPFILE_DIR=/tmp

# Pipeline execution
##################################

# Define command
CMD="
   $singularity_qsiprep \
   /tmp_in /tmp_out participant \
   -w /tmp \
   --participant-label $1 \
   --skip-bids-validation \
   --nthreads $SLURM_CPUS_PER_TASK \
   --omp-nthreads $OMP_NTHREADS \
   --mem_mb $MEM_MB \
   --denoise-method dwidenoise \
   --unringing-method mrdegibbs \
   --skull-strip-template OASIS \
   --stop-on-first-crash \
   --freesurfer-input /tmp_out/freesurfer \
   --output-resolution $OUTPUT_RESOLUTION \
   --fs-license-file envs/freesurfer_license.txt"

# --output-space T1w \

[ ! -z $RECON ] && CMD="${CMD} --recon_input /tmp_out/qsiprep/$1 --recon_spec $RECON"
[ ! -z $MODIFIER ] && CMD="${CMD} $MODIFIER"

# Execute command
eval $CMD

if [ ! -z $APPLY_NODDI  ]; then
CMD="
   $singularity_qsiprep \
   /tmp_in /tmp_out participant \
   -w /tmp \
   --participant-label $1 \
   --skip-bids-validation \
   --nthreads $SLURM_CPUS_PER_TASK \
   --omp-nthreads $OMP_NTHREADS \
   --mem_mb $MEM_MB \
   --stop-on-first-crash \
   --freesurfer-input /tmp_out/freesurfer \
   --output-resolution $OUTPUT_RESOLUTION \
   --fs-license-file envs/freesurfer_license.txt
   --recon_input /tmp_out/qsiprep/$1 --recon_spec amico_noddi --recon-only"

echo "##### Applying NODDI ######"

# Execute command
eval $CMD

fi

if [ ! -z $APPLY_PYAFQ  ]; then
CMD="
   $singularity_qsiprep \
   /tmp_in /tmp_out participant \
   -w /tmp \
   --participant-label $1 \
   --skip-bids-validation \
   --nthreads $SLURM_CPUS_PER_TASK \
   --omp-nthreads $OMP_NTHREADS \
   --mem_mb $MEM_MB \
   --stop-on-first-crash \
   --freesurfer-input /tmp_out/freesurfer \
   --output-resolution $OUTPUT_RESOLUTION \
   --fs-license-file envs/freesurfer_license.txt
   --recon_input /tmp_out/qsiprep/$1 --recon_spec $APPLY_PYAFQ --recon-only"

echo "##### Applying PyAFQ ######"

# Execute command
eval $CMD

fi

# Execute command
eval $CMD
# Copy outputs to $DATA_DIR
cp -ruvf $TMP_OUT/qsiprep $DATA_DIR
cp -ruvf $TMP_OUT/qsirecon $DATA_DIR
#cp -ruvf $TMP_OUT/* $DATA_DIR/qsirecon/$1
