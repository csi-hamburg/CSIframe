#!/bin/bash

# Set up environment

module load singularity

container_miniconda=miniconda-csi
singularity_miniconda="singularity run --cleanenv --userns \
    -B . \
    -B $PROJ_DIR \
    -B $SCRATCH_DIR:/tmp \
    -B $(readlink -f $ENV_DIR) \
    -B /usw \
    /usw/fatx405/csi_envs/$container_miniconda"

##############################################################
# Run heudiconv for dcm2nii and bidsification of its outputs #
# CAVE: dataset specific files                               #
#           - heudiconv_<heuristic>.py                       #
#           - metadataextra_<study>.py                       #
#           - handle_scantsvfile.py                          #
##############################################################

# for testing purposes
BIDS_DIR=$DATA_DIR/raw_bids

echo $SESSION out

if [ "$SESSION" == "all" ]; then

     export SESSIONS=$(ls $DCM_DIR/$1/ses-* -d | xargs -n 1 basename | cut -d'.' -f 1 | cut -d'-' -f 2)
   
      for SESSION in $SESSIONS; do
      
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
            -B $(readlink -f $ENV_DIR) \
            $ENV_DIR/heudiconv-0.9.0 \
            $CMD

            # Merge images using FSL
            
            CMD_merge="
            fslmerge \
            -a $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_asl.nii.gz \
            $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_desc-control_asl.nii.gz \
            $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_desc-label_asl.nii.gz"
            
            singularity run --cleanenv --userns \
            --home $PWD \
            -B $TMP_DIR:/tmp \
            -B $(readlink -f $ENV_DIR) \
            $ENV_DIR/fsl-6.0.3 \
            $CMD_merge

            # Delete unnecessary data
            
            mv -v $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_desc-label_asl.json $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_asl.json
            rm -v $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_desc-control_asl.json
            rm -v $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_desc-control_asl.nii.gz
            rm -v $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_desc-label_asl.nii.gz

            # Add extra metadata to json-files necessary for ASL-Preparation
            
            [ -d $BIDS_DIR/sub-${1}/ses-${SESSION}/perf ] && chmod 770 -Rv $BIDS_DIR/sub-${1}/ses-${SESSION}/perf
            
            $singularity_miniconda python $PIPELINE_DIR/edit_aslbids_hchs.py -s sub-${1} -t ses-${SESSION} -b $BIDS_DIR -j $PIPELINE_DIR/metadataextra_hchs.json
            
            # Edit scans.tsv file to reflect available asl data and eliminate problematic metadata

            $singularity_miniconda python $PIPELINE_DIR/handle_scantsvfile.py $1 $SESSION $BIDS_DIR

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
      -B $(readlink -f $ENV_DIR) \
      $ENV_DIR/heudiconv-0.9.0 \
      $CMD

      # Merge images using FSL
      
      CMD_merge="
      fslmerge \
      -a $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_asl.nii.gz \
      $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_desc-control_asl.nii.gz \
      $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_desc-label_asl.nii.gz"
      
      singularity run --cleanenv --userns \
      --home $PWD \
      -B $TMP_DIR:/tmp \
      -B $(readlink -f $ENV_DIR) \
      $ENV_DIR/fsl-6.0.3 \
      $CMD_merge

      # Delete unnecessary data
      
      mv -v $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_desc-label_asl.json $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_asl.json
      rm -v $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_desc-control_asl.json
      rm -v $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_desc-control_asl.nii.gz
      rm -v $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_desc-label_asl.nii.gz

      # Add extra metadata to json-files necessary for ASL-Preparation
      
      [ -d $BIDS_DIR/sub-${1}/ses-${SESSION}/perf ] && chmod 770 -Rv $BIDS_DIR/sub-${1}/ses-${SESSION}/perf
      
      $singularity_miniconda python $PIPELINE_DIR/edit_aslbids_hchs.py -s sub-${1} -t ses-${SESSION} -b $BIDS_DIR -j $PIPELINE_DIR/metadataextra_hchs.json
      
      # Edit scans.tsv file to reflect available asl data and eliminate problematic metadata

      $singularity_miniconda python $PIPELINE_DIR/handle_scantsvfile.py $1 $SESSION $BIDS_DIR

fi

# Remove problematic metadata from json sidecars

CMD="python $PIPELINE_DIR/handle_metadata.py $1"
$singularity_miniconda $CMD

rm -rf $BIDS_DIR/.heudiconv/$1
