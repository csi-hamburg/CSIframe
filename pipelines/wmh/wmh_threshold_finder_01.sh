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

# $MRTRIX_TMPFILE_DIR should be big and writable
export MRTRIX_TMPFILE_DIR=/tmp

# Pipeline execution
######################################################
# Define output directories of text files
[ $ALGORITHM_COMBI = "multiple" ] && ALGORITHM=${ALGORITHM1}X${ALGORITHM2}

OUT_DIR_der=$DATA_DIR/$PIPELINE/derivatives
[ -d $OUT_DIR_der/$ALGORITHM/thresholds ] && rm -r $OUT_DIR_der/$ALGORITHM/thresholds
mkdir -p $OUT_DIR_der/$ALGORITHM/thresholds
[ $ALGORITHM_COMBI = "multiple" ] && rm -r $OUT_DIR_der/$ALGORITHM1/thresholds/ && mkdir -p $OUT_DIR_der/$ALGORITHM1/thresholds/
[ $ALGORITHM_COMBI = "multiple" ] && rm -r $OUT_DIR_der/$ALGORITHM2/thresholds/ && mkdir -p $OUT_DIR_der/$ALGORITHM2/thresholds/

# Define output directories
OUT_DIR=$DATA_DIR/$PIPELINE/$1/ses-${SESSION}/anat/
[ ! -d $OUT_DIR ] && mkdir -p $OUT_DIR
ALGORITHM_DIR=$OUT_DIR/$ALGORITHM/
ALGORITHM_OUT_DIR=$OUT_DIR/$ALGORITHM/thresholds/
[ ! -d $ALGORITHM_OUT_DIR ] && mkdir -p $ALGORITHM_OUT_DIR

for sub in $(ls $MAN_SEGMENTATION_DIR/sub-* -d | xargs -n 1 basename); do

    if [ $ALGORITHM_COMBI = "single" ]; then 

        if [ $ALGORITHM == "LOCATE" ]; then 

            # Define inputs
            SEGMENTATION=$ALGORITHM_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz

            # Define outputs
            SEGMENTATION_MAN=$MAN_SEGMENTATION_DIR/${sub}/anat/${sub}_DC_FLAIR_label3.nii.gz
            JSON_FILE_dice=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-diceindex_desc-${ALGORITHM}.txt
            JSON_FILE_jaccard=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-jaccard_desc-${ALGORITHM}.txt
            FALSE_POSITIVE=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-falsepositive_desc-${ALGORITHM}.nii.gz
            JSON_FILE_falsepositive=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-falsepositive_desc-${ALGORITHM}.txt
            FALSE_NEGATIVE=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-falsenegative_desc-${ALGORITHM}.nii.gz
            JSON_FILE_falsenegative=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-falsenegative_desc-${ALGORITHM}.txt

            # Define commands
            CMD_CALCULATE_DICE="mri_seg_overlap -x $SEGMENTATION $SEGMENTATION_MAN -o $JSON_FILE_dice"
            CMD_CALCULATE_JACCARD="mri_seg_overlap -m jaccard -x $SEGMENTATION $SEGMENTATION_MAN -o $JSON_FILE_jaccard"
            CMD_FALSEPOSITIVE_FILE="fslmaths $SEGMENTATION -sub $SEGMENTATION_MAN -thr 0 -bin $FALSE_POSITIVE"
            CMD_FALSENEGATIVE_FILE="fslmaths $SEGMENTATION_MAN -sub $SEGMENTATION -thr 0 -bin $FALSE_NEGATIVE"

            # Execute
            $singularity_freesurfer /bin/bash -c "$CMD_CALCULATE_DICE; $CMD_CALCULATE_JACCARD"
            $singularity_fsl /bin/bash -c "$CMD_FALSEPOSITIVE_FILE; $CMD_FALSENEGATIVE_FILE"
            $singularity_fsl /bin/bash -c "$(echo fslstats $FALSE_POSITIVE -V) > $JSON_FILE_falsepositive"
            $singularity_fsl /bin/bash -c "$(echo fslstats $FALSE_NEGATIVE -V) > $JSON_FILE_falsenegative"


        else

            for thresh in 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95; do 

                if [ $ALGORITHM == "bianca" ]; then 

                    # Define inputs
                    SEGMENTATION_raw=$DATA_DIR/$PIPELINE/sourcedata/BIANCA_training/pseudomized_training_masks/${sub}_bianca_output.nii.gz
                    BRAINWITHOUTRIBBON_MASK_FLAIR=$OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-brainwithoutribbon_mask.nii.gz

                    # Define outputs
                    SEGMENTATION_sized=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-${ALGORITHM}${thresh}_mask_sized.nii.gz
                    SEGMENTATION=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-${ALGORITHM}${thresh}_mask.nii.gz
                    SEGMENTATION_THRESH=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}${thresh}_mask.nii.gz

                    # Define commands
                    CMD_threshold_segmentation="cluster --in=$SEGMENTATION_raw --thresh=$thresh --osize=$SEGMENTATION_sized"
                    CMD_thresholdcluster_segmentation="fslmaths $SEGMENTATION_sized -thr 3 -bin $SEGMENTATION"
                    CMD_MASKING_GAME="fslmaths $SEGMENTATION -mul $BRAINWITHOUTRIBBON_MASK_FLAIR $SEGMENTATION_THRESH"

                    # Execute
                    $singularity_fsl /bin/bash -c "$CMD_threshold_segmentation; $CMD_thresholdcluster_segmentation; $CMD_MASKING_GAME"

                else

                    # Define inputs
                    SEGMENTATION=$ALGORITHM_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-maskednothresh_desc-wmh_desc-${ALGORITHM}_mask.nii.gz

                    # Define outputs
                    SEGMENTATION_THRESH=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}${thresh}_mask.nii.gz

                    # Define commands
                    CMD_THRESH_SEGMENTATION="fslmaths $SEGMENTATION -thr $thresh -bin $SEGMENTATION_THRESH"

                    # Execute
                    $singularity_fsl /bin/bash -c "$CMD_THRESH_SEGMENTATION"
                fi
                
                # Define outputs
                SEGMENTATION_MAN=$MAN_SEGMENTATION_DIR/${sub}/anat/${sub}_DC_FLAIR_label3.nii.gz
                JSON_FILE_dice=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-diceindex_desc-${ALGORITHM}${thresh}.txt
                JSON_FILE_jaccard=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-jaccard_desc-${ALGORITHM}${thresh}.txt
                FALSE_POSITIVE=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-falsepositive_desc-${ALGORITHM}${thresh}.nii.gz
                JSON_FILE_falsepositive=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-falsepositive_desc-${ALGORITHM}${thresh}.txt
                FALSE_NEGATIVE=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-falsenegative_desc-${ALGORITHM}${thresh}.nii.gz
                JSON_FILE_falsenegative=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-falsenegative_desc-${ALGORITHM}${thresh}.txt

                # Define commands
                CMD_CALCULATE_DICE="mri_seg_overlap -x $SEGMENTATION_THRESH $SEGMENTATION_MAN -o $JSON_FILE_dice"
                CMD_CALCULATE_JACCARD="mri_seg_overlap -m jaccard -x $SEGMENTATION_THRESH $SEGMENTATION_MAN -o $JSON_FILE_jaccard"
                CMD_FALSEPOSITIVE_FILE="fslmaths $SEGMENTATION_THRESH -sub $SEGMENTATION_MAN -thr 0 -bin $FALSE_POSITIVE"
                CMD_FALSENEGATIVE_FILE="fslmaths $SEGMENTATION_MAN -sub $SEGMENTATION_THRESH -thr 0 -bin $FALSE_NEGATIVE"

                # Execute
                $singularity_freesurfer /bin/bash -c "$CMD_CALCULATE_DICE; $CMD_CALCULATE_JACCARD"
                $singularity_fsl /bin/bash -c "$CMD_FALSEPOSITIVE_FILE; $CMD_FALSENEGATIVE_FILE"
                $singularity_fsl /bin/bash -c "$(echo fslstats $FALSE_POSITIVE -V) > $JSON_FILE_falsepositive"
                $singularity_fsl /bin/bash -c "$(echo fslstats $FALSE_NEGATIVE -V) > $JSON_FILE_falsenegative"
                
            done

        fi
        
    elif [ $ALGORITHM_COMBI = "multiple" ]; then 

        # Define output directories
        FIRST_ALGORITHM_DIR=$OUT_DIR/$ALGORITHM1
        FIRST_ALGORITHM_OUT_DIR=$OUT_DIR/$ALGORITHM1/thresholds
        [ ! -d $FIRST_ALGORITHM_OUT_DIR ] && mkdir -p $FIRST_ALGORITHM_OUT_DIR
        SECOND_ALGORITHM_DIR=$OUT_DIR/$ALGORITHM2
        SECOND_ALGORITHM_OUT_DIR=$OUT_DIR/$ALGORITHM2/thresholds/
        [ ! -d $SECOND_ALGORITHM_OUT_DIR ] && mkdir -p $SECOND_ALGORITHM_OUT_DIR

        for thresh in 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95; do 

            if [ $ALGORITHM1 == "bianca" ]; then 

                # Define inputs
                SEGMENTATION_raw=$DATA_DIR/$PIPELINE/sourcedata/BIANCA_training/pseudomized_training_masks/${sub}_bianca_output.nii.gz
                BRAINWITHOUTRIBBON_MASK_FLAIR=$OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-brainwithoutribbon_mask.nii.gz
                SEGMENTATION_TWO=$SECOND_ALGORITHM_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-maskednothresh_desc-wmh_desc-${ALGORITHM2}_mask.nii.gz

                # Define outputs
                SEGMENTATION_sized=$FIRST_ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-${ALGORITHM1}${thresh}_mask_sized.nii.gz
                SEGMENTATION=$FIRST_ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-${ALGORITHM1}${thresh}_mask.nii.gz
                SEGMENTATION_FILTERED=$FIRST_ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM1}${thresh}_mask.nii.gz
                SEGMENTATIONTWO_THRESH=$SECOND_ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM2}${thresh}_mask.nii.gz

                # Define commands
                CMD_threshold_segmentation="cluster --in=$SEGMENTATION_raw --thresh=$thresh --osize=$SEGMENTATION_sized"
                CMD_thresholdcluster_segmentation="fslmaths $SEGMENTATION_sized -thr 3 -bin $SEGMENTATION"
                CMD_MASKING_GAME="fslmaths $SEGMENTATION -mul $BRAINWITHOUTRIBBON_MASK_FLAIR $SEGMENTATION_FILTERED"
                CMD_THRESH_SEGMENTATIONTWO="fslmaths $SEGMENTATION_TWO -thr $thresh -bin $SEGMENTATIONTWO_THRESH"

                # Execute
                $singularity_fsl /bin/bash -c "$CMD_threshold_segmentation; $CMD_thresholdcluster_segmentation; $CMD_MASKING_GAME; $CMD_THRESH_SEGMENTATIONTWO"

            elif [ $ALGORITHM1 == "LOCATE" ]; then 

                # Define inputs
                SEGMENTATION_TWO=$SECOND_ALGORITHM_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-maskednothresh_desc-wmh_desc-${ALGORITHM2}_mask.nii.gz

                # Define outputs
                SEGMENTATIONTWO_THRESH=$SECOND_ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM2}${thresh}_mask.nii.gz
                
                # Define commands
                CMD_THRESH_SEGMENTATIONTWO="fslmaths $SEGMENTATION_TWO -thr $thresh -bin $SEGMENTATIONTWO_THRESH"

                # Execute
                $singularity_fsl /bin/bash -c "$CMD_THRESH_SEGMENTATIONTWO"

            elif [ $ALGORITHM2 == "bianca" ]; then 

                # Define inputs
                SEGMENTATION_ONE=$FIRST_ALGORITHM_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-maskednothresh_desc-wmh_desc-${ALGORITHM1}_mask.nii.gz
                SEGMENTATION_raw=$DATA_DIR/$PIPELINE/sourcedata/BIANCA_training/pseudomized_training_masks/${sub}_bianca_output.nii.gz
                BRAINWITHOUTRIBBON_MASK_FLAIR=$OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-brainwithoutribbon_mask.nii.gz

                # Define outputs
                SEGMENTATIONONE_THRESH=$FIRST_ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM1}${thresh}_mask.nii.gz
                SEGMENTATION_sized=$SECOND_ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-${ALGORITHM2}${thresh}_mask_sized.nii.gz
                SEGMENTATION=$SECOND_ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-${ALGORITHM2}${thresh}_mask.nii.gz
                SEGMENTATION_FILTERED=$SECOND_ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM2}${thresh}_mask.nii.gz

                # Define commands
                CMD_threshold_segmentation="cluster --in=$SEGMENTATION_raw --thresh=$thresh --osize=$SEGMENTATION_sized"
                CMD_thresholdcluster_segmentation="fslmaths $SEGMENTATION_sized -thr 3 -bin $SEGMENTATION"
                CMD_MASKING_GAME="fslmaths $SEGMENTATION -mul $BRAINWITHOUTRIBBON_MASK_FLAIR $SEGMENTATION_FILTERED"
                CMD_THRESH_SEGMENTATIONONE="fslmaths $SEGMENTATION_ONE -thr $thresh -bin $SEGMENTATIONONE_THRESH"

                # Execute
                $singularity_fsl /bin/bash -c "$CMD_THRESH_SEGMENTATIONONE; $CMD_threshold_segmentation; $CMD_thresholdcluster_segmentation; $CMD_MASKING_GAME"

            elif [ $ALGORITHM2 == "LOCATE" ]; then 

                # Define inputs
                SEGMENTATION_ONE=$FIRST_ALGORITHM_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-maskednothresh_desc-wmh_desc-${ALGORITHM1}_mask.nii.gz

                # Define outputs
                SEGMENTATIONONE_THRESH=$FIRST_ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM1}${thresh}_mask.nii.gz

                # Define commands
                CMD_THRESH_SEGMENTATIONONE="fslmaths $SEGMENTATION_ONE -thr $thresh -bin $SEGMENTATIONONE_THRESH"
                
                # Execute
                $singularity_fsl /bin/bash -c "$CMD_THRESH_SEGMENTATIONONE"

            else

                # Define inputs
                SEGMENTATION_ONE=$FIRST_ALGORITHM_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-maskednothresh_desc-wmh_desc-${ALGORITHM1}_mask.nii.gz
                SEGMENTATION_TWO=$SECOND_ALGORITHM_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-maskednothresh_desc-wmh_desc-${ALGORITHM2}_mask.nii.gz

                # Define outputs
                SEGMENTATIONONE_THRESH=$FIRST_ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM1}${thresh}_mask.nii.gz
                SEGMENTATIONTWO_THRESH=$SECOND_ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM2}${thresh}_mask.nii.gz

                # Define commands
                CMD_THRESH_SEGMENTATIONONE="fslmaths $SEGMENTATION_ONE -thr $thresh -bin $SEGMENTATIONONE_THRESH"
                CMD_THRESH_SEGMENTATIONTWO="fslmaths $SEGMENTATION_TWO -thr $thresh -bin $SEGMENTATIONTWO_THRESH"

                # Execute
                $singularity_fsl /bin/bash -c "$CMD_THRESH_SEGMENTATIONONE; $CMD_THRESH_SEGMENTATIONTWO"

            fi

        done

        if [ $ALGORITHM1 == "LOCATE" ]; then FIRST_ALGORITHM_DIR_ITER=$FIRST_ALGORITHM_DIR; else FIRST_ALGORITHM_DIR_ITER=$FIRST_ALGORITHM_OUT_DIR; fi

        if [ $ALGORITHM2 == "LOCATE" ]; then SECOND_ALGORITHM_DIR_ITER=$SECOND_ALGORITHM_DIR; else SECOND_ALGORITHM_DIR_ITER=$SECOND_ALGORITHM_OUT_DIR; fi

        for MASKONE in $(ls $FIRST_ALGORITHM_DIR_ITER/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM1}* -d | xargs -n 1 basename); do

            MASKONE_FILE=$FIRST_ALGORITHM_OUT_DIR/$MASKONE
            [ $ALGORITHM1 == "LOCATE" ] && MASKONE_FILE=$FIRST_ALGORITHM_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM1}_mask.nii.gz
            MASKONE_name=$(echo $MASKONE | sed -n "s/.*${ALGORITHM1}//p" | sed -n 's/.nii.gz//p' )
            [ $ALGORITHM1 == "LOCATE" ] && MASKONE_name=""

            for MASKTWO in $(ls $SECOND_ALGORITHM_DIR_ITER/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM2}* -d | xargs -n 1 basename); do

                MASKTWO_FILE=$SECOND_ALGORITHM_OUT_DIR/$MASKTWO
                [ $ALGORITHM2 == "LOCATE" ] && MASKTWO_FILE=$SECOND_ALGORITHM_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM2}_mask.nii.gz
                MASKTWO_name=$(echo $MASKTWO | sed -n "s/.*${ALGORITHM2}//p" | sed -n 's/.nii.gz//p' )
                [ $ALGORITHM2 == "LOCATE" ] && MASKTWO_name=""

                # Define inputs
                SEGMENTATION_MAN=$MAN_SEGMENTATION_DIR/${sub}/anat/${sub}_DC_FLAIR_label3.nii.gz

                # Define outputs
                COMBINATION=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM1}${MASKONE_name}X${ALGORITHM2}${MASKTWO_name}.nii.gz
                JSON_FILE_dice=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-diceindex_desc-${ALGORITHM1}${MASKONE_name}X${ALGORITHM2}${MASKTWO_name}.txt
                JSON_FILE_jaccard=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-jaccard_desc-${ALGORITHM1}${MASKONE_name}X${ALGORITHM2}${MASKTWO_name}.txt
                FALSE_POSITIVE=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-falsepositive_desc-${ALGORITHM1}${MASKONE_name}X${ALGORITHM2}${MASKTWO_name}.nii.gz
                JSON_FILE_falsepositive=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-falsepositive_desc-${ALGORITHM1}${MASKONE_name}X${ALGORITHM2}${MASKTWO_name}.txt
                FALSE_NEGATIVE=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-falsenegative_desc-${ALGORITHM1}${MASKONE_name}X${ALGORITHM2}${MASKTWO_name}.nii.gz
                JSON_FILE_falsenegative=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-falsenegative_desc-${ALGORITHM1}${MASKONE_name}X${ALGORITHM2}${MASKTWO_name}.txt
                indexfile=$OUT_DIR_der/$ALGORITHM/thresholds/${ALGORITHM1}${MASKONE_name}X${ALGORITHM2}${MASKTWO_name}.csv

                # Define commands
                CMD_COMBINE="fslmaths $MASKONE_FILE -add $MASKTWO_FILE -bin $COMBINATION"
                CMD_CALCULATE_DICE="mri_seg_overlap -x $COMBINATION $SEGMENTATION_MAN -o $JSON_FILE_dice"
                CMD_CALCULATE_JACCARD="mri_seg_overlap -x -m jaccard $COMBINATION $SEGMENTATION_MAN -o $JSON_FILE_jaccard"
                CMD_FALSEPOSITIVE_FILE="fslmaths $COMBINATION -sub $SEGMENTATION_MAN -thr 0 -bin $FALSE_POSITIVE"
                CMD_FALSENEGATIVE_FILE="fslmaths $SEGMENTATION_MAN -sub $COMBINATION -thr 0 -bin $FALSE_NEGATIVE"

                # Execute
                $singularity_fsl /bin/bash -c "$CMD_COMBINE"
                $singularity_freesurfer /bin/bash -c "$CMD_CALCULATE_DICE; $CMD_CALCULATE_JACCARD"
                $singularity_fsl /bin/bash -c "$CMD_FALSEPOSITIVE_FILE; $CMD_FALSENEGATIVE_FILE"
                $singularity_fsl /bin/bash -c "$(echo fslstats $FALSE_POSITIVE -V) > $JSON_FILE_falsepositive"
                $singularity_fsl /bin/bash -c "$(echo fslstats $FALSE_NEGATIVE -V) > $JSON_FILE_falsenegative"

            done
        done
    fi

done