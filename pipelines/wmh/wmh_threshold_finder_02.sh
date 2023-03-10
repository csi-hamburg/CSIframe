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
# Singularity container version and command
container_fsl=fsl-6.0.3
singularity_fsl="singularity run --cleanenv --userns -B $PROJ_DIR -B $MAN_SEGMENTATION_DIR -B $(readlink -f $ENV_DIR) -B $TMP_DIR/:/tmp -B $TMP_IN:/tmp_in -B $TMP_OUT:/tmp_out $ENV_DIR/$container_fsl" 

container_freesurfer=freesurfer-7.1.1
singularity_freesurfer="singularity run --cleanenv --userns -B $PROJ_DIR -B $MAN_SEGMENTATION_DIR -B $(readlink -f $ENV_DIR) -B $TMP_DIR/:/tmp -B $TMP_IN:/tmp_in -B $TMP_OUT:/tmp_out $ENV_DIR/$container_freesurfer" 

# $MRTRIX_TMPFILE_DIR should be big and writable
export MRTRIX_TMPFILE_DIR=/tmp

# Pipeline execution
######################################################
# Define outputs
[ $ALGORITHM_COMBI = "multiple" ] && ALGORITHM=${ALGORITHM1}X${ALGORITHM2}

OUT_DIR_der=$DATA_DIR/$PIPELINE/derivatives/$ALGORITHM/thresholds
[ -d $OUT_DIR_der ] && rm -r $OUT_DIR_der
mkdir $OUT_DIR_der

for sub in $(ls $DATA_DIR/$PIPELINE/sub-* -d | xargs -n 1 basename); do   

    OUT_DIR=$DATA_DIR/$PIPELINE/$sub/ses-${SESSION}/anat/
    ALGORITHM_OUT_DIR=$OUT_DIR/$ALGORITHM/thresholds/

    if [ $ALGORITHM_COMBI = "single" ]; then 

        if [ $ALGORITHM == "LOCATE" ]; then

            # Define inputs
            JSON_FILE_dice=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-diceindex_desc-${ALGORITHM}.txt
            JSON_FILE_jaccard=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-jaccard_desc-${ALGORITHM}.txt
            JSON_FILE_falsepositive=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-falsepositive_desc-${ALGORITHM}.txt
            JSON_FILE_falsenegative=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-falsenegative_desc-${ALGORITHM}.txt
            indexfile=$OUT_DIR_der/${ALGORITHM}.csv

            dice_value=$(cat $JSON_FILE_dice | grep '"mean":' | awk '{print $2}')
            jaccard_value=$(cat $JSON_FILE_jaccard | grep '"mean":' | awk '{print $2}')
            falsepositive_value=$(cat $JSON_FILE_falsepositive | awk '{print $2}')
            falsenegative_value=$(cat $JSON_FILE_falsenegative | awk '{print $2}')

            # Execute
            echo "$sub,$dice_value,$jaccard_value,$falsepositive_value,$falsenegative_value" >> $indexfile

        else

            for thresh in 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95; do

                # Define inputs
                JSON_FILE_dice=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-diceindex_desc-${ALGORITHM}${thresh}.txt
                JSON_FILE_jaccard=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-jaccard_desc-${ALGORITHM}${thresh}.txt
                JSON_FILE_falsepositive=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-falsepositive_desc-${ALGORITHM}${thresh}.txt
                JSON_FILE_falsenegative=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-falsenegative_desc-${ALGORITHM}${thresh}.txt
                indexfile=$OUT_DIR_der/${ALGORITHM}${thresh}.csv

                dice_value=$(cat $JSON_FILE_dice | grep '"mean":' | awk '{print $2}')
                jaccard_value=$(cat $JSON_FILE_jaccard | grep '"mean":' | awk '{print $2}')
                falsepositive_value=$(cat $JSON_FILE_falsepositive | awk '{print $2}')
                falsenegative_value=$(cat $JSON_FILE_falsenegative | awk '{print $2}')

                # Execute
                echo "$sub,$dice_value,$jaccard_value,$falsepositive_value,$falsenegative_value" >> $indexfile

            done

        fi

    elif [ $ALGORITHM_COMBI = "multiple" ]; then 

        FIRST_ALGORITHM_DIR=$OUT_DIR/$ALGORITHM1
        FIRST_ALGORITHM_OUT_DIR=$OUT_DIR/$ALGORITHM1/thresholds
        SECOND_ALGORITHM_DIR=$OUT_DIR/$ALGORITHM2
        SECOND_ALGORITHM_OUT_DIR=$OUT_DIR/$ALGORITHM2/thresholds/

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
                JSON_FILE_dice=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-diceindex_desc-${ALGORITHM1}${MASKONE_name}X${ALGORITHM2}${MASKTWO_name}.txt
                JSON_FILE_jaccard=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-jaccard_desc-${ALGORITHM1}${MASKONE_name}X${ALGORITHM2}${MASKTWO_name}.txt
                JSON_FILE_falsepositive=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-falsepositive_desc-${ALGORITHM1}${MASKONE_name}X${ALGORITHM2}${MASKTWO_name}.txt
                JSON_FILE_falsenegative=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-falsenegative_desc-${ALGORITHM1}${MASKONE_name}X${ALGORITHM2}${MASKTWO_name}.txt
                indexfile=$OUT_DIR_der/${ALGORITHM1}${MASKONE_name}X${ALGORITHM2}${MASKTWO_name}.csv

                # Execute
                dice_value=$(cat $JSON_FILE_dice | grep '"mean":' | awk '{print $2}')
                jaccard_value=$(cat $JSON_FILE_jaccard | grep '"mean":' | awk '{print $2}')
                falsepositive_value=$(cat $JSON_FILE_falsepositive | awk '{print $2}')
                falsenegative_value=$(cat $JSON_FILE_falsenegative | awk '{print $2}')

                # Execute
                echo "$sub,$dice_value,$jaccard_value,$falsepositive_value,$falsenegative_value" >> $indexfile

            done

        done

    fi

done

if [[ $ALGORITHM != "LOCATE" ]]; then

    for file in $(ls $OUT_DIR_der/*.csv); do 

        # Define outputs
        OUTPUTFILE=$OUT_DIR_der/${ALGORITHM}.csv

        # Execute
        dice=$(awk -F, '{ total += $2; count++ } END { print total/93 }' $file)
        jaccard=$(awk -F, '{ total += $4; count++ } END { print total/93 }' $file)
        falsepositive=$(awk -F, '{ total += $6; count++ } END { print total/93 }' $file)
        falsenegative=$(awk -F, '{ total += $7; count++ } END { print total/93 }' $file)

        echo $file $dice $jaccard $falsepositive $falsenegative >> $OUTPUTFILE
            
    done

fi
