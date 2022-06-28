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

export SINGULARITYENV_SUBJECTS_DIR=$TMP_OUT

parallel="parallel --ungroup --delay 0.2 -j16 --joblog $CODE_DIR/log/parallel_runtask.log"

[ ! -d $TMP_OUT/ ] && mkdir -p $TMP_OUT

for ses in $(ls $BIDS_DIR/$1);do
   sub_ses_dir=${1}_${ses}
   sessions+=("-tp $sub_ses_dir")
   [ ! -d $TMP_OUT/$sub_ses_dir ] && cp -rf $DATA_DIR/freesurfer_long/$sub_ses_dir $TMP_OUT/
done

CMD_BASE="
   recon-all \
   -base ${1}_base \
   ${sessions[@]} \
   -sd /tmp_out/ \
   -debug \
   -all"
$singularity_freesurfer $CMD_BASE

CMD_LONG="
recon-all \
-long {} ${1}_base \
-sd /tmp_out/ \
-debug \
-all"
$parallel $singularity_freesurfer $CMD_LONG ::: ${sessions[@]}

[ ! -d $DATA_DIR/freesurfer_long ] && mkdir -p $DATA_DIR/freesurfer_long
cp -ruvf $TMP_OUT/* $DATA_DIR/freesurfer_long
