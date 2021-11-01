#!/bin/bash


# To make I/O more efficient read/write outputs from/to scratch #
TMP_IN=$TMP_DIR/input
TMP_OUT=$TMP_DIR/output
[ ! -d $TMP_IN ] && mkdir -p $TMP_IN && cp -rf $BIDS_DIR/$1 $BIDS_DIR/dataset_description.json $TMP_IN 
[ ! -d $TMP_OUT/ ] && mkdir -p $TMP_OUT
#[ ! -f $DATA_DIR/freesurfer/$1/stats/aseg.stats ] && rm -rf $DATA_DIR/freesurfer/$1 || cp -rf $DATA_DIR/freesurfer/$1 $TMP_OUT/freesurfer
export SINGULARITYENV_SUBJECTS_DIR=$TMP_OUT/freesurfer

CMD="
   singularity run --cleanenv --userns -B $PROJ_DIR -B $(readlink -f $ENV_DIR) -B $TMP_DIR:/tmp -B $TMP_IN:/tmp_in -B $TMP_OUT:/tmp_out \
   $ENV_DIR/freesurfer-7.1.1 \
   recon-all \
   -sd /tmp_out \
   -subjid $1 \
   -i /tmp_in/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_T1w.nii.gz \
   -debug \
   -all"
[ ! -z $MODIFIER ] && CMD="${CMD} ${MODIFIER}"
$CMD

cp -ruvf $TMP_OUT/* $DATA_DIR/freesurfer