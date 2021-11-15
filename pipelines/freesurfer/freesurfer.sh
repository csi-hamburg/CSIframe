#!/usr/bin/env bash

###################################################################################################################
# FreeSurfer recon-all (https://surfer.nmr.mgh.harvard.edu/)                                                      #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - none                                                                                                    #
#   [container]                                                                                                   #
#       - freesurfer-7.1.1                                                                                        #
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
container_freesurfer=freesurfer-7.1.1
singularity_freesurfer="singularity run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_freesurfer" 


# To make I/O more efficient read/write outputs from/to scratch 
[ -d $TMP_IN ] && cp -rf $BIDS_DIR/$1 $TMP_IN 
[ ! -d $TMP_OUT/ ] && mkdir -p $TMP_OUT


export SINGULARITYENV_SUBJECTS_DIR=$TMP_OUT/freesurfer

parallel="parallel --ungroup --delay 0.2 -j16 --joblog $CODE_DIR/log/parallel_runtask.log"

if [ $SESSION == all ];then

      for ses_dir in $(ls $DATA_DIR/raw_bids/$1);do
         [ ! -d $TMP_OUT/$1/$ses_dir ]; mkdir -p $TMP_OUT/$1/$ses_dir
      done

      CMD="
         $singularity_freesurfer \
         recon-all \
         -sd /tmp_out/$1/{} \
         -subjid $1 \
         -i /tmp_in/$1/{}/anat/${1}_{}_T1w.nii.gz \
         -debug \
         -all"
      $parallel $CMD ::: $(ls $TMP_IN/$1)

else

   CMD="
      $singularity_freesurfer \
      recon-all \
      -sd /tmp_out \
      -subjid $1 \
      -i /tmp_in/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_T1w.nii.gz \
      -debug \
      -all"
   $CMD

fi


cp -ruvf $TMP_OUT/* $DATA_DIR/freesurfer