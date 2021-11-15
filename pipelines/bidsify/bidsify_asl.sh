#!/bin/bash

module load python/3.8.10
pip install pydicom
pip install nibabel
pip install pandas
pip install bids

# Run heudiconv for dcm2nii and bidsification of its outputs
# heudiconv_heuristic.py is dataset specific
echo $SESSION out
if [ "$SESSION" == "all" ];then
   export SESSIONS=$(ls $DCM_DIR/$1/ses-* -d | xargs -n 1 basename | cut -d'.' -f 1 | cut -d'-' -f 2)
   for SESSION in $SESSIONS;do
      CMD="
      heudiconv \
      --dicom_dir_template /dcm/{subject}/ses-{session}.tar.gz \
      --subjects $1 \
      --ses $SESSION \
      --bids notop \
      --heuristic /code/pipelines/bidsify/$HEURISTIC \
      --converter dcm2niix \
      --minmeta \
      --overwrite \
      --grouping all \
      --outdir /bids"
      singularity run --cleanenv --userns \
      --home $PWD \
      -B $CODE_DIR:/code \
      -B $BIDS_DIR:/bids \
      -B $DCM_DIR:/dcm \
      -B $TMP_DIR:/tmp \
      $ENV_DIR/heudiconv-0.9.0 \
      $CMD

      # Merge images using FSL
      CMD_merge="
      fslmerge \
      -a $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_asl.nii.gz \
      $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_desc_control_asl.nii.gz \
      $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_desc_label_asl.nii.gz"
      
      singularity run --cleanenv --userns \
      --home $PWD \
      -B $TMP_DIR:/tmp \
      $ENV_DIR/fsl-6.0.3 \
      $CMD_merge

      # delete unnecessary data
      cp $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_desc_label_asl.json $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_asl.json

      # Add extra metadata to json-files necessary for ASL-Preparation
      [ -d $BIDS_DIR/sub-${1}/ses-${SESSION}/perf ] && chmod 770 -Rv $BIDS_DIR/sub-${1}/ses-${SESSION}/perf
      
      python $PIPELINE_DIR/edit_aslbids_hchs.py -s sub-${1} -t ses-${SESSION} -b $BIDS_DIR -j $PIPELINE_DIR/metadataextra_hchs.json
    
    done

else

      CMD="
      heudiconv \
      --dicom_dir_template /dcm/{subject}/ses-{session}.tar.gz \
      --subjects $1 \
      --ses $SESSION \
      --bids notop \
      --heuristic /code/pipelines/bidsify/$HEURISTIC \
      --converter dcm2niix \
      --minmeta \
      --overwrite \
      --grouping all \
      --outdir /bids"
      singularity run --cleanenv --userns \
      --home $PWD \
      -B $CODE_DIR:/code \
      -B $BIDS_DIR:/bids \
      -B $DCM_DIR:/dcm \
      -B $TMP_DIR:/tmp \
      $ENV_DIR/heudiconv-0.9.0 \
      $CMD

      # Merge images using FSL
      CMD_merge="
      fslmerge \
      -a $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_asl.nii.gz \
      $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_desc_control_asl.nii.gz \
      $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_desc_label_asl.nii.gz"
      
      singularity run --cleanenv --userns \
      --home $PWD \
      -B $TMP_DIR:/tmp \
      $ENV_DIR/fsl-6.0.3 \
      $CMD_merge

      # delete unnecessary data
      cp $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_desc_label_asl.json $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_asl.json

      # Add extra metadata to json-files necessary for ASL-Preparation
      [ -d $BIDS_DIR/sub-${1}/ses-${SESSION}/perf ] && chmod 770 -Rv $BIDS_DIR/sub-${1}/ses-${SESSION}/perf
      
      python $PIPELINE_DIR/edit_aslbids_hchs.py -s sub-${1} -t ses-${SESSION} -b $BIDS_DIR -j $PIPELINE_DIR/metadataextra_hchs.json

fi

# Remove problematic metadata from json sidecars
CMD="python $PIPELINE_DIR/handle_metadata.py $1"
$CMD

rm -rf $BIDS_DIR/.heudiconv/$1