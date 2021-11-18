#!/usr/bin/env bash

###################################################################################################################
# Bidsification and anonymization with heudiconv (https://github.com/nipy/heudiconv) and pydeface                 #
# (https://github.com/poldracklab/pydeface/                                                                       #
#                                                                                                                 #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - none but make sure that dicoms/ses-XY.tar.gz exists (see dataset_helper.sh)                             #
#   [container]                                                                                                   #
#       - heudiconv-0.9.0.sif                                                                                     #
#       - pydeface-2.0.0.sif                                                                                      #
#       - csi-miniconda.sif                                                                                       #
###################################################################################################################

# Get verbose outputs
set -x

# Define subject specific temporary directory on $SCRATCH_DIR
export TMP_DIR=$SCRATCH_DIR/$1/tmp/;   [ ! -d $TMP_DIR ] && mkdir -p $TMP_DIR
TMP_IN=$TMP_DIR/input;                 [ ! -d $TMP_IN ] && mkdir -p $TMP_IN
TMP_OUT=$TMP_DIR/output;               [ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT

###################################################################################################################

# Define environment
#########################
container_heudiconv=heudiconv-0.9.0  
container_pydeface=pydeface-2.0.0
container_csiminiconda=csi-miniconda

singularity_heudiconv="singularity run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    -B $CODE_DIR:/code \
    -B $BIDS_DIR:/bids \
    -B $DCM_DIR:/dcm \
    $ENV_DIR/$container_heudiconv" 

singularity_pydeface="singularity run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_pydeface" 

singularity_csiminiconda="singularity run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_csiminiconda" 


# Run heudiconv for dcm2nii and bidsification of its outputs
# heudiconv_heuristic.py is dataset specific
echo $SESSION out
if [ "$SESSION" == "all" ];then
   
   # Get available sessions
   export SESSIONS=$(ls $DCM_DIR/$1/ses-* -d | xargs -n 1 basename | cut -d'.' -f 1 | cut -d'-' -f 2)
   
   # Iterate over all sessions
   for SESSION in $SESSIONS;do

      #########################
      # BIDSIFICATION
      #########################

      # Command
      #########################   
      CMD_HEUDICONV="
      heudiconv \
      -d /dcm/{subject}/ses-{session}.tar.gz\
      --subjects $1 \
      --ses $SESSION \
      --bids notop \
      -f /code/pipelines/bidsify/$HEURISTIC\
      -c dcm2niix \
      --minmeta \
      --overwrite\
      --grouping accession_number \
      -o /bids"

      # Execution
      #########################
      $singularity_heudiconv $CMD_HEUDICONV
     
      #singularity run --cleanenv --userns \
      #--home $PWD \
      #-B $CODE_DIR:/code \
      #-B $BIDS_DIR:/bids \
      #-B $DCM_DIR:/dcm \
      #-B $TMP_DIR:/tmp \
      #$ENV_DIR/heudiconv-0.9.0 \
      #$CMD

      # Amend permissions for defacing (-> w)
      [ -d $BIDS_DIR/sub-${1} ] && chmod 770 -R $BIDS_DIR/sub-${1} $BIDS_DIR/.heudiconv


      if [ $MODIFIER==y ];then

         #########################
         # DEFACING
         #########################

         # Input
         #########################   
         T1="$BIDS_DIR/sub-${1}/ses-${SESSION}/anat/sub-${1}_ses-${SESSION}_T1w.nii.gz"
         T2="$BIDS_DIR/sub-${1}/ses-${SESSION}/anat/sub-${1}_ses-${SESSION}_T2w.nii.gz"
         FLAIR="$BIDS_DIR/sub-${1}/ses-${SESSION}/anat/sub-${1}_ses-${SESSION}_FLAIR.nii.gz"

         # Command
         #########################   
         CMD_T1="pydeface $T1 --outfile $T1 --force --verbose"
         CMD_T2="pydeface $T2 --outfile $T2 --force --verbose"
         CMD_FLAIR="pydeface $FLAIR --outfile $FLAIR --force --verbose"

         # Execution
         #########################   
         [ -f $T1 ] && $singularity_pydeface $CMD_T1
         [ -f $T2 ] && $singularity_pydeface $CMD_T2
         [ -f $FLAIR ] && $singularity_pydeface $CMD_FLAIR

      fi
   done

else

   #########################
   # BIDSIFICATION
   #########################

   # Command
   #########################   
   CMD_HEUDICONV="
   heudiconv \
   -d /dcm/{subject}/ses-{session}.tar.gz\
   --subjects $1 \
   --ses $SESSION \
   --bids notop \
   -f /code/pipelines/bidsify/$HEURISTIC\
   -c dcm2niix \
   --minmeta \
   --overwrite\
   --grouping accession_number \
   -o /bids"
   
   # Execution
   #########################
   $singularity_heudiconv $CMD_HEUDICONV
  
   # Amend permissions for defacing (-> w)
   [ -d $BIDS_DIR/sub-${1} ] && chmod 770 -R $BIDS_DIR/sub-${1}
   
   if [ $MODIFIER==y ];then

      #########################
      # DEFACING
      #########################

      # Input
      #########################   
      T1="$BIDS_DIR/sub-${1}/ses-${SESSION}/anat/sub-${1}_ses-${SESSION}_T1w.nii.gz"
      T2="$BIDS_DIR/sub-${1}/ses-${SESSION}/anat/sub-${1}_ses-${SESSION}_T2w.nii.gz"
      FLAIR=$BIDS_DIR/sub-${1}/ses-${SESSION}/anat/sub-${1}_ses-${SESSION}_FLAIR.nii.gz
      
      # Command
      #########################   
      CMD_T1="pydeface $T1 --outfile $T1 --force --verbose"
      CMD_T2="pydeface $T2 --outfile $T2 --force --verbose"
      CMD_FLAIR="pydeface $FLAIR --outfile $FLAIR --force --verbose"
      
      # Execution
      #########################   
      [ -f $T1 ] && $singularity_pydeface $CMD_T1
      [ -f $T2 ] && $singularity_pydeface $CMD_T2
      [ -f $FLAIR ] && $singularity_pydeface $CMD_FLAIR

   fi
fi

# Remove problematic metadata from json sidecars
CMD="python $CODE_DIR/pipelines/$PIPELINE/handle_metadata.py $1"
$CMD

rm -rf $BIDS_DIR/.heudiconv/$1