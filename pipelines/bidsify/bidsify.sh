#!/usr/bin/env bash

###################################################################################################################
# Bidsification and anonymization with heudiconv (https://github.com/nipy/heudiconv) and pydeface                 #
# (https://github.com/poldracklab/pydeface/                                                                       #
#                                                                                                                 #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - none but make sure that dicoms/sub-XY/ses-XY.tar.gz exists (see dataset_helper.sh)                      #
#   [containers]                                                                                                  #
#       - heudiconv-0.9.0.sif                                                                                     #
#       - pydeface-2.0.0.sif                                                                                      #
#       - csi-miniconda.sif                                                                                       #         
#       - fsl-6.0.3.sif                                                                                           #
#                                                                                                                 #
########                                                                                                          #
# MIND #                                                                                                          #
########                                                                                                          #
#                                                                                                                 #
# The following files are dataset specific and must be present in $ENV_DIR/bidsify/                               #
#  - heudiconv_*.py                                                                                               #
#  - metadataextra_*.py                                                                                           #
#                                                                                                                 #
# In case of different acquisitions define subjects corresponding to heuristic/metadataextra during submission    #
###################################################################################################################

# Get verbose outputs
set -x

# Define subject specific temporary directory on $SCRATCH_DIR
export TMP_DIR=$SCRATCH_DIR/$1/tmp/;   [ ! -d $TMP_DIR ] && mkdir -p $TMP_DIR
TMP_IN=$TMP_DIR/input;                 [ ! -d $TMP_IN ] && mkdir -p $TMP_IN
TMP_OUT=$TMP_DIR/output;               [ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT

###################################################################################################################

# Define environment
####################
ENV_DIR=$PROJ_DIR/envs
container_heudiconv=heudiconv-1.1.6 
container_pydeface=pydeface-2.0.0
container_csiminiconda=miniconda-csi
container_fsl=fsl-6.0.3

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

singularity_fsl="singularity run --cleanenv --userns \
   -B $PROJ_DIR \
   -B $(readlink -f $ENV_DIR) \
   -B $TMP_DIR/:/tmp \
   -B $TMP_IN:/tmp_in \
   -B $TMP_OUT:/tmp_out \
   $ENV_DIR/$container_fsl"

# Define sessions to process
############################

echo $SESSION out

if [ $SESSION == "all" ];then
   
   # Get available sessions
   export SESSIONS=$(ls $DCM_DIR/$1/ses-* -d | xargs -n 1 basename | cut -d'.' -f 1 | cut -d'-' -f 2)

else

   export SESSIONS=$SESSION

fi

#################
# BIDSIFICATION #
#################

for SESSION in $SESSIONS; do

   if [ $BIDS_PIPE == "heudiconv" ]; then
      
      # Command
      #########################

      # CMD_HEUDICONV="
      # heudiconv \
      # --dicom_dir_template /dcm/{subject}/ses-{session}.tar.gz\
      # --subjects $1 \
      # --ses $SESSION \
      # --bids notop \
      # --heuristic /code/pipelines/bidsify/$HEURISTIC\
      # --converter dcm2niix \
      # --minmeta \
      # --overwrite\
      # --grouping all \
      # --outdir /bids"

      CMD_HEUDICONV="
      --dicom_dir_template /dcm/{subject}/ses-{session}.tar.gz\
      --subjects $1 \
      --ses $SESSION \
      --bids notop \
      --heuristic /code/pipelines/bidsify/$HEURISTIC\
      --converter dcm2niix \
      --minmeta \
      --overwrite\
      --grouping all \
      --outdir /bids"

      # Execution
      #########################

      $singularity_heudiconv $CMD_HEUDICONV

      # Amend permissions for defacing (-> w)
      [ -d $BIDS_DIR/sub-${1} ] && chmod 770 -R $BIDS_DIR/sub-${1} $BIDS_DIR/.heudiconv


      if [ $MODIFIER == y ];then

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

   elif [ $BIDS_PIPE == "asl" ]; then

      #####################################################################
      # Modify ASL output to comply with BIDS standard / aslprep pipeline #
      #####################################################################

      # Merge images using FSL
      ########################
      
      #####################################################################################################################################################
      # MIND # Make sure that ASL heudiconv output is numbered according to the order of acquisition (run-01, run-02 .. etc.) > defined in heuristic file #
      ######## This will reflect the (alphabetical) order in which fsl merges the files and must therefore reflect the order of volumes in the            #
      #        aslcontext.tsv file which is defined in the metadataextra.json file.                                                                       #                             #
      #####################################################################################################################################################
      
      # Commands
      ##########

      CMD_MERGE_ASL="fslmerge \
         -a $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_asl.nii.gz \
         $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_run-*_asl.nii.gz"
      
      CMD_MERGE_M0="fslmerge \
         -a $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_m0scan.nii.gz \
         $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_run-*_m0scan.nii.gz"

      # Execution (only if ASL and M0 scans are acquired in seperate runs)
      ####################################################################

      if [ ! -z $(ls $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_run-*_asl.nii.gz | head -n 1) ]; then
         
         $singularity_fsl $CMD_MERGE_ASL
         
         # Remove unnecessary files

         ASL_JSON=`ls $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_run-*_asl.json | head -n 1`   
         mv -v $ASL_JSON $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_asl.json
         rm -v $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_run*_asl*

      fi

      if [ ! -z $(ls $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_run-*_m0scan.nii.gz | head -n 1) ]; then
         
         $singularity_fsl $CMD_MERGE_M0

         # Remove unnecessary files

         M0_JSON=`ls $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_run-*_m0scan.json | head -n 1`   
         mv -v $M0_JSON $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_m0scan.json
         rm -v $BIDS_DIR/sub-${1}/ses-${SESSION}/perf/sub-${1}_ses-${SESSION}_run*_m0scan*

      fi

      # Add extra metadata to json-files necessary for ASLprep/BIDS standard
      ######################################################################

      [ -d $BIDS_DIR/sub-${1}/ses-${SESSION}/perf ] && chmod 770 -Rv $BIDS_DIR/sub-${1}/ses-${SESSION}/perf
      
      $singularity_csiminiconda python $PIPELINE_DIR/edit_aslbids.py -s sub-${1} -t ses-${SESSION} -b $BIDS_DIR -j $ENV_DIR/bidsify/$METADATA_EXTRA
      
      # Edit scans.tsv file to reflect available asl data 
      ###################################################

      $singularity_csiminiconda python $PIPELINE_DIR/handle_scanstsvfile.py $1 $SESSION $BIDS_DIR

   fi

done

##################################################
# Remove problematic metadata from json sidecars #
##################################################

CMD="python $CODE_DIR/pipelines/$PIPELINE/handle_metadata.py $1"
$singularity_csiminiconda $CMD

# Clean up
##########
rm -rf $BIDS_DIR/.heudiconv/$1