#!/bin/bash


# To make I/O more efficient read/write outputs from/to scratch #
TMP_IN=$TMP_DIR/input
TMP_OUT=$TMP_DIR/output
[ ! -d $TMP_IN ] && mkdir -p $TMP_IN && cp -rf $BIDS_DIR/$1 $BIDS_DIR/dataset_description.json $TMP_IN 
[ ! -d $TMP_OUT/ ] && mkdir -p $TMP_OUT
#[ ! -f $DATA_DIR/freesurfer/$1/stats/aseg.stats ] && rm -rf $DATA_DIR/freesurfer/$1 || cp -rf $DATA_DIR/freesurfer/$1 $TMP_OUT/freesurfer
export SINGULARITYENV_SUBJECTS_DIR=$TMP_OUT/freesurfer

parallel="parallel --ungroup --delay 0.2 -j16 --joblog $CODE_DIR/log/parallel_runtask.log"

if [ $SESSION == all ];then

      [ ! -d $TMP_OUT/$1/$ses_dir ]; mkdir -p $TMP_OUT/$1/$ses_dir

      CMD="
         singularity run --cleanenv --userns -B $PROJ_DIR -B $(readlink -f $ENV_DIR) -B $TMP_DIR:/tmp -B $TMP_IN:/tmp_in -B $TMP_OUT:/tmp_out \
         $ENV_DIR/freesurfer-7.1.1 \
         recon-all \
         -sd /tmp_out/$1/$ses_dir \
         -subjid $1 \
         -i /tmp_in/$1/{}/anat/${1}_{}_*T1w.nii.gz \
         -debug \
         -all"
         [ ! -z $MODIFIER ] && CMD="${CMD} ${MODIFIER}"
      $parallel $CMD ::: $(ls $BIDS_DIR/$1)

else

   CMD="
      singularity run --cleanenv --userns -B $PROJ_DIR -B $(readlink -f $ENV_DIR) -B $TMP_DIR:/tmp -B $TMP_IN:/tmp_in -B $TMP_OUT:/tmp_out \
      $ENV_DIR/freesurfer-7.1.1 \
      recon-all \
      -sd /tmp_out \
      -subjid $1 \
      -i /tmp_in/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_*T1w.nii.gz \
      -debug \
      -all"
   [ ! -z $MODIFIER ] && CMD="${CMD} ${MODIFIER}"
   $CMD

fi



cp -ruvf $TMP_OUT/* $DATA_DIR/freesurfer