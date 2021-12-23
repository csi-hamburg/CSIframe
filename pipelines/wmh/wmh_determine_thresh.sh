#!/usr/bin/env bash

# Get verbose outputs
set -x
ulimit -c 0

# Define subject specific temporary directory on $SCRATCH_DIR
export TMP_DIR=$SCRATCH_DIR/$1/tmp/;   [ ! -d $TMP_DIR ] && mkdir -p $TMP_DIR
TMP_IN=$TMP_DIR/input;                 [ ! -d $TMP_IN ] && mkdir -p $TMP_IN
TMP_OUT=$TMP_DIR/output;               [ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT

###################################################################################################################
# Pipeline-specific environment
###################################################################################################################
MAN_SEGMENTATION_DIR=$PROJ_DIR/../CSI_WMH_MASKS_HCHS_pseud/HCHS/


# Singularity container version and command
container_fsl=fsl-6.0.3
singularity_fsl="singularity run --cleanenv --userns -B $PROJ_DIR -B $MAN_SEGMENTATION_DIR -B $(readlink -f $ENV_DIR) -B $TMP_DIR/:/tmp -B $TMP_IN:/tmp_in -B $TMP_OUT:/tmp_out $ENV_DIR/$container_fsl" 

container_freesurfer=freesurfer-7.1.1
singularity_freesurfer="singularity run --cleanenv --userns -B $PROJ_DIR -B $MAN_SEGMENTATION_DIR -B $(readlink -f $ENV_DIR) -B $TMP_DIR/:/tmp -B $TMP_IN:/tmp_in -B $TMP_OUT:/tmp_out $ENV_DIR/$container_freesurfer" 

# To make I/O more efficient read/write outputs from/to $SCRATCH
[ -d $TMP_IN ] && cp -rf $BIDS_DIR/$1 $BIDS_DIR/dataset_description.json $TMP_IN 
[ -d $TMP_OUT ] && mkdir -p $TMP_OUT/wmh $TMP_OUT/wmh

# $MRTRIX_TMPFILE_DIR should be big and writable
export MRTRIX_TMPFILE_DIR=/tmp

# Pipeline execution
######################################################
# Set output directories
OUT_DIR=$DATA_DIR/$PIPELINE/$1/ses-${SESSION}/anat/
[ ! -d $OUT_DIR ] && mkdir -p $OUT_DIR
OUT_DIR_json=$DATA_DIR/$PIPELINE/derivatives/test_thresh/
[ ! -d $OUT_DIR_json ] && mkdir -p $OUT_DIR_json

#for ALGORITHM in antsrnet antsrnetbias bianca lpa lga; do
for ALGORITHM in bianca; do

    ALGORITHM_OUT_DIR=$OUT_DIR/${ALGORITHM}/

    if  [ $ALGORITHM == "antsrnet" ] || [ $ALGORITHM == "antsrnetbias" ]; then

        for thresh in 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4; do 

            THRESH_OUT_DIR=$OUT_DIR/$ALGORITHM/test_thresh/
            [ ! -d $THRESH_OUT_DIR ] && mkdir -p $THRESH_OUT_DIR

            if [ $ANALYSIS_LEVEL = "subject" ]; then 

                # Define inputs
                SEGMENTATION_FILTERED=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-maskednothresh_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
                SEGMENTATION_MAN=$MAN_SEGMENTATION_DIR/$1/anat/${1}_DC_FLAIR_label3.nii.gz

                # Define outputs
                SEGMENTATION_THRESH=$THRESH_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}${thresh}_mask.nii.gz
                JSON_FILE_dice=$THRESH_OUT_DIR/${1}_ses-${SESSION}_desc-diceindex_desc-${ALGORITHM}${thresh}.txt
                FALSE_POSITIVE=$THRESH_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-falsepositive_desc-${ALGORITHM}${thresh}_mask.nii.gz
                JSON_FILE_falsepositive=$THRESH_OUT_DIR/${1}_ses-${SESSION}_desc-falsepositive_desc-${ALGORITHM}${thresh}.txt
                FALSE_NEGATIVE=$THRESH_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-falsenegative_desc-${ALGORITHM}${thresh}_mask.nii.gz
                JSON_FILE_falsenegative=$THRESH_OUT_DIR/${1}_ses-${SESSION}_desc-falsenegative_desc-${ALGORITHM}${thresh}.txt
                
                # Define commands
                CMD_THRESH_SEGMENTATION="fslmaths $SEGMENTATION_FILTERED -thr $thresh -bin $SEGMENTATION_THRESH"
                CMD_CALCULATE_DICE="mri_seg_overlap -x $SEGMENTATION_THRESH $SEGMENTATION_MAN -o $JSON_FILE_dice"
                CMD_FALSEPOSITIVE_FILE="fslmaths $SEGMENTATION_THRESH -sub $SEGMENTATION_MAN -thr 0 -bin $FALSE_POSITIVE"
                CMD_FALSENEGATIVE_FILE="fslmaths $SEGMENTATION_MAN -sub $SEGMENTATION_THRESH -thr 0 -bin $FALSE_NEGATIVE"

                # Execute
                $singularity_fsl /bin/bash -c "$CMD_THRESH_SEGMENTATION"
                $singularity_freesurfer /bin/bash -c "$CMD_CALCULATE_DICE"
                $singularity_fsl /bin/bash -c "$CMD_FALSEPOSITIVE_FILE; $CMD_FALSENEGATIVE_FILE"
                $singularity_fsl /bin/bash -c "$(echo fslstats $FALSE_POSITIVE -V) > $JSON_FILE_falsepositive"
                $singularity_fsl /bin/bash -c "$(echo fslstats $FALSE_NEGATIVE -V) > $JSON_FILE_falsenegative"

            elif [ $ANALYSIS_LEVEL == "group" ]; then 

                indexfile=$OUT_DIR_json/subsall_${ALGORITHM}${thresh}.csv
                [ -f $indexfile ] && rm $indexfile


                for sub in $(ls $DATA_DIR/$PIPELINE/sub-* -d | xargs -n 1 basename); do 

                    # Define inputs
                    JSON_FILE_dice=$DATA_DIR/$PIPELINE/$sub/ses-${SESSION}/anat/$ALGORITHM/test_thresh/${sub}_ses-${SESSION}_desc-diceindex_desc-${ALGORITHM}${thresh}.txt
                    JSON_FILE_falsepositive=$DATA_DIR/$PIPELINE/$sub/ses-${SESSION}/anat/$ALGORITHM/test_thresh/${sub}_ses-${SESSION}_desc-falsepositive_desc-${ALGORITHM}${thresh}.txt
                    JSON_FILE_falsenegative=$DATA_DIR/$PIPELINE/$sub/ses-${SESSION}/anat/$ALGORITHM/test_thresh/${sub}_ses-${SESSION}_desc-falsenegative_desc-${ALGORITHM}${thresh}.txt

                    # Define outputs
                    indexfile=$OUT_DIR_json/subsall_${ALGORITHM}${thresh}.csv
                    dice_value=$(cat $JSON_FILE_dice | grep '"mean":' | awk '{print $2}')
                    falsepositive_value=$(cat $JSON_FILE_falsepositive | awk '{print $2}')
                    falsenegative_value=$(cat $JSON_FILE_falsenegative | awk '{print $2}')

                    # Execute
                    echo "$sub,$ALGORITHM,$dice_value,$falsepositive_value,$falsenegative_value" >> $indexfile

                done

            fi

        done 

    elif  [ $ALGORITHM == "bianca" ] || [ $ALGORITHM == "biancabias" ]; then

        for thresh in 0.65 0.7 0.75 0.8 0.85 0.9 0.95; do 

            THRESH_OUT_DIR=$OUT_DIR/$ALGORITHM/test_thresh/
            [ ! -d $THRESH_OUT_DIR ] && mkdir -p $THRESH_OUT_DIR

            if [ $ANALYSIS_LEVEL = "subject" ]; then 

                # Define inputs
                SEGMENTATION_raw=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-${ALGORITHM}_mask_raw.nii.gz
                BRAINWITHOUTRIBBON_MASK_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brainwithoutribbon_mask.nii.gz
                SEGMENTATION_MAN=$MAN_SEGMENTATION_DIR/$1/anat/${1}_DC_FLAIR_label3.nii.gz

                # Define outputs
                SEGMENTATION_sized=$THRESH_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-${ALGORITHM}${thresh}_mask_sized.nii.gz
                SEGMENTATION=$THRESH_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-${ALGORITHM}${thresh}_mask.nii.gz
                SEGMENTATION_FILTERED=$THRESH_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}${thresh}_mask.nii.gz
                JSON_FILE_dice=$THRESH_OUT_DIR/${1}_ses-${SESSION}_desc-diceindex_desc-${ALGORITHM}${thresh}.txt
                FALSE_POSITIVE=$THRESH_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-falsepositive_desc-${ALGORITHM}${thresh}_mask.nii.gz
                JSON_FILE_falsepositive=$THRESH_OUT_DIR/${1}_ses-${SESSION}_desc-falsepositive_desc-${ALGORITHM}${thresh}.txt
                FALSE_NEGATIVE=$THRESH_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-falsenegative_desc-${ALGORITHM}${thresh}_mask.nii.gz
                JSON_FILE_falsenegative=$THRESH_OUT_DIR/${1}_ses-${SESSION}_desc-falsenegative_desc-${ALGORITHM}${thresh}.txt

                # Define commands
                CMD_threshold_segmentation="cluster --in=$SEGMENTATION_raw --thresh=$thresh --osize=$SEGMENTATION_sized"
                CMD_thresholdcluster_segmentation="fslmaths $SEGMENTATION_sized -thr 3 -bin $SEGMENTATION"
                CMD_MASKING_GAME="fslmaths $SEGMENTATION -mul $BRAINWITHOUTRIBBON_MASK_FLAIR $SEGMENTATION_FILTERED"
                CMD_CALCULATE_DICE="mri_seg_overlap -x $SEGMENTATION_FILTERED $SEGMENTATION_MAN -o $JSON_FILE_dice"
                CMD_FALSEPOSITIVE_FILE="fslmaths $SEGMENTATION_FILTERED -sub $SEGMENTATION_MAN -thr 0 -bin $FALSE_POSITIVE"
                CMD_FALSENEGATIVE_FILE="fslmaths $SEGMENTATION_MAN -sub $SEGMENTATION_FILTERED -thr 0 -bin $FALSE_NEGATIVE"

                # Execute 
                $singularity_fsl /bin/bash -c "$CMD_threshold_segmentation; $CMD_thresholdcluster_segmentation; $CMD_MASKING_GAME"
                $singularity_freesurfer /bin/bash -c "$CMD_CALCULATE_DICE"
                $singularity_fsl /bin/bash -c "$CMD_FALSEPOSITIVE_FILE; $CMD_FALSENEGATIVE_FILE"
                $singularity_fsl /bin/bash -c "$(echo fslstats $FALSE_POSITIVE -V) > $JSON_FILE_falsepositive"
                $singularity_fsl /bin/bash -c "$(echo fslstats $FALSE_NEGATIVE -V) > $JSON_FILE_falsenegative"

            elif [ $ANALYSIS_LEVEL == "group" ]; then 

                indexfile=$OUT_DIR_json/subsall_${ALGORITHM}${thresh}.csv
                [ -f $indexfile ] && rm $indexfile

                for sub in $(ls $DATA_DIR/$PIPELINE/sub-* -d | xargs -n 1 basename); do

                    # Define inputs
                    JSON_FILE_dice=$DATA_DIR/$PIPELINE/$sub/ses-${SESSION}/anat/$ALGORITHM/test_thresh/${sub}_ses-${SESSION}_desc-diceindex_desc-${ALGORITHM}${thresh}.txt
                    JSON_FILE_falsepositive=$DATA_DIR/$PIPELINE/$sub/ses-${SESSION}/anat/$ALGORITHM/test_thresh/${sub}_ses-${SESSION}_desc-falsepositive_desc-${ALGORITHM}${thresh}.txt
                    JSON_FILE_falsenegative=$DATA_DIR/$PIPELINE/$sub/ses-${SESSION}/anat/$ALGORITHM/test_thresh/${sub}_ses-${SESSION}_desc-falsenegative_desc-${ALGORITHM}${thresh}.txt

                    # Define outputs
                    indexfile=$OUT_DIR_json/subsall_${ALGORITHM}${thresh}.csv
                    dice_value=$(cat $JSON_FILE_dice | grep '"mean":' | awk '{print $2}')
                    falsepositive_value=$(cat $JSON_FILE_falsepositive | awk '{print $2}')
                    falsenegative_value=$(cat $JSON_FILE_falsenegative | awk '{print $2}')

                    # Execute
                    echo "$sub,$ALGORITHM,$dice_value,$falsepositive_value,$falsenegative_value" >> $indexfile

                done

            fi

        done

    elif  [ $ALGORITHM == "lga" ] || [ $ALGORITHM == "lpa" ]; then

        for thresh in 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95; do 

            THRESH_OUT_DIR=$OUT_DIR/$ALGORITHM/test_thresh/
            [ ! -d $THRESH_OUT_DIR ] && mkdir -p $THRESH_OUT_DIR

            if [ $ANALYSIS_LEVEL = "subject" ]; then 

                # Define inputs
                SEGMENTATION_NOFILT=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-maskednothresh_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
                SEGMENTATION_MAN=$MAN_SEGMENTATION_DIR/$1/anat/${1}_DC_FLAIR_label3.nii.gz

                # Define outputs
                SEGMENTATION_FILTERED=$THRESH_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}${thresh}_mask.nii.gz
                JSON_FILE_dice=$THRESH_OUT_DIR/${1}_ses-${SESSION}_desc-diceindex_desc-${ALGORITHM}${thresh}.txt
                FALSE_POSITIVE=$THRESH_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-falsepositive_desc-${ALGORITHM}${thresh}_mask.nii.gz
                JSON_FILE_falsepositive=$THRESH_OUT_DIR/${1}_ses-${SESSION}_desc-falsepositive_desc-${ALGORITHM}${thresh}.txt
                FALSE_NEGATIVE=$THRESH_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-falsenegative_desc-${ALGORITHM}${thresh}_mask.nii.gz
                JSON_FILE_falsenegative=$THRESH_OUT_DIR/${1}_ses-${SESSION}_desc-falsenegative_desc-${ALGORITHM}${thresh}.txt

                # Define commands
                CMD_THRESH_SEGMENTATION="fslmaths $SEGMENTATION_NOFILT -thr $thresh -bin $SEGMENTATION_FILTERED"
                CMD_CALCULATE_DICE="mri_seg_overlap -x $SEGMENTATION_FILTERED $SEGMENTATION_MAN -o $JSON_FILE_dice"
                CMD_FALSEPOSITIVE_FILE="fslmaths $SEGMENTATION_FILTERED -sub $SEGMENTATION_MAN -thr 0 -bin $FALSE_POSITIVE"
                CMD_FALSENEGATIVE_FILE="fslmaths $SEGMENTATION_MAN -sub $SEGMENTATION_FILTERED -thr 0 -bin $FALSE_NEGATIVE"

                # Execute
                $singularity_fsl /bin/bash -c "$CMD_THRESH_SEGMENTATION"
                $singularity_freesurfer /bin/bash -c "$CMD_CALCULATE_DICE"
                $singularity_fsl /bin/bash -c "$CMD_FALSEPOSITIVE_FILE; $CMD_FALSENEGATIVE_FILE"
                $singularity_fsl /bin/bash -c "$(echo fslstats $FALSE_POSITIVE -V) > $JSON_FILE_falsepositive"
                $singularity_fsl /bin/bash -c "$(echo fslstats $FALSE_NEGATIVE -V) > $JSON_FILE_falsenegative"


            elif [ $ANALYSIS_LEVEL == "group" ]; then 

                indexfile=$OUT_DIR_json/subsall_${ALGORITHM}${thresh}.csv
                [ -f $indexfile ] && rm $indexfile

                for sub in $(ls $DATA_DIR/$PIPELINE/sub-* -d | xargs -n 1 basename); do

                    # Define inputs
                    JSON_FILE_dice=$DATA_DIR/$PIPELINE/$sub/ses-${SESSION}/anat/$ALGORITHM/test_thresh/${sub}_ses-${SESSION}_desc-diceindex_desc-${ALGORITHM}${thresh}.txt
                    JSON_FILE_falsepositive=$DATA_DIR/$PIPELINE/$sub/ses-${SESSION}/anat/$ALGORITHM/test_thresh/${sub}_ses-${SESSION}_desc-falsepositive_desc-${ALGORITHM}${thresh}.txt
                    JSON_FILE_falsenegative=$DATA_DIR/$PIPELINE/$sub/ses-${SESSION}/anat/$ALGORITHM/test_thresh/${sub}_ses-${SESSION}_desc-falsenegative_desc-${ALGORITHM}${thresh}.txt

                    # Define outputs
                    indexfile=$OUT_DIR_json/subsall_${ALGORITHM}${thresh}.csv
                    dice_value=$(cat $JSON_FILE | grep '"mean":' | awk '{print $2}')
                    falsepositive_value=$(cat $JSON_FILE_falsepositive | awk '{print $2}')
                    falsenegative_value=$(cat $JSON_FILE_falsenegative | awk '{print $2}')

                    # Execute
                    echo "$sub,$ALGORITHM,$dice_value,$falsepositive_value,$falsenegative_value" >> $indexfile

                done

            fi

        done

    fi

done






    

        
        

