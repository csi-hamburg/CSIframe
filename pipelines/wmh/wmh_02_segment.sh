#!/usr/bin/env bash

###################################################################################################################
# Segmentation of White Matter Hyperintensities using BIANCA and LOCATE algorithms                                #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - fmriprep                                                                                                #
#       - freesurfer (if not run in fmriprep)                                                                     #
#       - wmh_01_prep in wmh                                                                                      #
#   [container]                                                                                                   #
#       - fsl-6.0.7.13.sif                                                                                        #      
#       - locate.sif                                                                                              #
#                                                                                                                 #
###################################################################################################################

# Get verbose outputs
set -x
ulimit -c 0

# Define subject specific temporary directory on $SCRATCH_DIR
export TMP_DIR=$SCRATCH_DIR/$1/tmp;           [ ! -d $TMP_DIR ] && mkdir -p $TMP_DIR
TMP_IN=$TMP_DIR/input;                 [ ! -d $TMP_IN ] && mkdir -p $TMP_IN
TMP_OUT=$TMP_DIR/output;               [ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT

###################################################################################################################

# Pipeline-specific environment
##################################

# Apptainer container version and command
container_fsl=fsl-6.0.7.13.sif
apptainer_fsl="apptainer run --cleanenv --userns \
    -B $PROJ_DIR/../ \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_fsl"

container_locate=locate.sif
apptainer_locate="apptainer run --cleanenv --userns \
    -B $PROJ_DIR/../ \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_locate"

###################################################################################################################
#                                               Pipeline execution                                                #                              
###################################################################################################################

if [ $ALGORITHM == "BIANCA" ]; then

    ##################
    # Part A: BIANCA #
    ##################

    # Define directory which contains manual segmentations for training
    ###################################################################

    MAN_SEGMENTATION_DIR=$DATA_DIR/$PIPELINE/sourcedata/manual_segmentations/
    
    if [ $BIANCA_LEVEL == "training" ]; then

        TRAINING_DIR=$DATA_DIR/$PIPELINE/sourcedata/bianca_training
        [ ! -d $TRAINING_DIR ] && mkdir -p $TRAINING_DIR
        MASTERFILE=$TRAINING_DIR/masterfile.txt
        [ -f $MASTERFILE ] && rm $MASTERFILE

        for sub in $(ls $DATA_DIR/$PIPELINE/sub-* -d | xargs -n 1 basename); do

            # Set up output directories
            ###########################

            OUT_DIR=$DATA_DIR/$PIPELINE/$sub/ses-${SESSION}/anat/
            [ ! -d $OUT_DIR ] && echo "Necessary input data are not available. Note: 01_prep needs to be run first. Exiting ..." && exit 1
            ALGORITHM_OUT_DIR=$OUT_DIR/${ALGORITHM}/
            [ ! -d $ALGORITHM_OUT_DIR ] && mkdir -p $ALGORITHM_OUT_DIR

            [[ $(ls -A $MAN_SEGMENTATION_DIR/${sub}) ]] && SUB_GROUP=training || SUB_GROUP=testing

            if [ $SUB_GROUP == "training" ]; then

                # Define inputs
                ###############

                MNI_TEMPLATE=$ENV_DIR/standard/tpl-MNI152NLin2009cAsym_res-01_desc-brain_T1w.nii.gz
                FLAIR_BRAIN=$OUT_DIR/${sub}_ses-${SESSION}_desc-brain_FLAIR.nii.gz
                T1_IN_FLAIR=$OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii.gz
                SEGMENTATION_MAN=$MAN_SEGMENTATION_DIR/$sub/anat/${sub}_DC_FLAIR_label4.nii.gz

                # Define outputs
                ################

                MASTERFILE=$TRAINING_DIR/masterfile.txt
                FLAIR_IN_MNI_FLIRT=/tmp/${sub}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-brain_FLAIR.nii.gz
                FLAIR_TO_MNI_WARP_FLIRT=$OUT_DIR/${sub}_ses-${SESSION}_from-FLAIR_to-MNI152NLin2009cAsym_flirtwarp.txt
                CLASSIFIER=$TRAINING_DIR/classifierdata
                
                # Define commands
                #################

                CMD_FLIRT_FLAIR_TO_MNI="flirt -in $FLAIR_BRAIN -ref $MNI_TEMPLATE -out $FLAIR_IN_MNI_FLIRT -omat $FLAIR_TO_MNI_WARP_FLIRT"

                # Execute commands
                ##################

                $apptainer_fsl /bin/bash -c "$CMD_FLIRT_FLAIR_TO_MNI"
                if [ -f $FLAIR_BRAIN ] && [ -f $T1_IN_FLAIR ] && [ -f $FLAIR_TO_MNI_WARP_FLIRT ] && [ -f $SEGMENTATION_MAN ] ; then   
                    echo "$FLAIR_BRAIN $T1_IN_FLAIR $FLAIR_TO_MNI_WARP_FLIRT $SEGMENTATION_MAN" >> $MASTERFILE
                fi

            fi

        done

        # Execute bianca
        ################

        CMD_BIANCA="bianca --singlefile=$MASTERFILE --brainmaskfeaturenum=1 --querysubjectnum=1 --trainingnums=all --featuresubset=1,2 --matfeaturenum=3 --labelfeaturenum=4 --trainingpts=2000 --nonlespts=10000 --selectpts=noborder -v --saveclassifierdata=$CLASSIFIER --patch3D --patchsizes=3,3,3"
        $apptainer_fsl /bin/bash -c "$CMD_BIANCA"
    
    elif [ $BIANCA_LEVEL == "validation" ]; then

        [[ $(ls -A $MAN_SEGMENTATION_DIR/${1}) ]] && SUB_GROUP=training || SUB_GROUP=testing

        if [ $SUB_GROUP == "training" ]; then  
            
            # Check if training data is available
            #####################################
            
            TRAINING_DIR=$DATA_DIR/$PIPELINE/sourcedata/bianca_training
            [ ! -d $TRAINING_DIR ] && echo "No training data found. Please run bianca training first." && exit 1

            # Set output directories
            #########################

            OUT_DIR=$DATA_DIR/$PIPELINE/$1/ses-${SESSION}/anat/
            [ ! -d $OUT_DIR ] && echo "Necessary input data are not available. Note: 01_prep needs to be run first. Exiting ..." && exit 1

            ALGORITHM_OUT_DIR=$OUT_DIR/${ALGORITHM}/
            [ ! -d $ALGORITHM_OUT_DIR ] && mkdir -p $ALGORITHM_OUT_DIR

            # Define inputs
            ###############

            BRAINWITHOUTRIBBON_MASK_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brainwithoutribbon_mask.nii.gz
            FLAIR_BRAIN=$OUT_DIR/${1}_ses-${SESSION}_desc-brain_FLAIR.nii.gz
            T1_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii.gz
            SEGMENTATION_MAN=$MAN_SEGMENTATION_DIR/$1/anat/${1}_DC_FLAIR_label4.nii.gz
            FLAIR_TO_MNI_WARP_FLIRT=$OUT_DIR/${1}_ses-${SESSION}_from-FLAIR_to-MNI152NLin2009cAsym_flirtwarp.txt
            MASTERFILE=$TRAINING_DIR/masterfile.txt
            CLASSIFIER=$TRAINING_DIR/classifierdata
            subjectline=$(cat $MASTERFILE | grep -n $1 | awk -F: '{print $1}')

            # Define output
            ###############

            SEGMENTATION_raw=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-${ALGORITHM}_mask_raw.nii.gz

            # Define command
            ################

            CMD_BIANCA_leaveoneout="bianca --singlefile=$MASTERFILE --brainmaskfeaturenum=1 --querysubjectnum=$subjectline --featuresubset=1,2 --matfeaturenum=3 --trainingpts=2000 --nonlespts=10000 --selectpts=noborder -o $SEGMENTATION_raw -v --loadclassifierdata=$CLASSIFIER --patch3D --patchsizes=3,3,3"

            if [ -f $FLAIR_BRAIN ] && [ -f $T1_IN_FLAIR ] && [ -f $FLAIR_TO_MNI_WARP_FLIRT ] && [ -f $SEGMENTATION_MAN ] ; then  

                # Execute command
                #################

                $apptainer_fsl /bin/bash -c "$CMD_BIANCA_leaveoneout"

            fi

        fi
    
    elif [ $BIANCA_LEVEL == "testing" ]; then

        [[ $(ls -A $MAN_SEGMENTATION_DIR/${1}) ]] && SUB_GROUP=training || SUB_GROUP=testing

        if [ $SUB_GROUP == "testing" ]; then

            # Check if training data is available
            #####################################

            TRAINING_DIR=$DATA_DIR/$PIPELINE/sourcedata/bianca_training
            [ ! -d $TRAINING_DIR ] && echo "No training data found. Please run bianca training first." && exit 1

            # Set output directories
            #########################
            
            OUT_DIR=$DATA_DIR/$PIPELINE/$1/ses-${SESSION}/anat/
            [ ! -d $OUT_DIR ] && echo "Necessary input data are not available. Note: 01_prep needs to be run first. Exiting ..." && exit 1

            ALGORITHM_OUT_DIR=$OUT_DIR/${ALGORITHM}/
            [ ! -d $ALGORITHM_OUT_DIR ] && mkdir -p $ALGORITHM_OUT_DIR
          
            # Define inputs
            ###############

            FLAIR_BRAIN=$OUT_DIR/${1}_ses-${SESSION}_desc-brain_FLAIR.nii.gz
            T1_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii.gz
            CLASSIFIER=$TRAINING_DIR/classifierdata
            BRAINWITHOUTRIBBON_MASK_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brainwithoutribbon_mask.nii.gz
            MNI_TEMPLATE=$ENV_DIR/standard/tpl-MNI152NLin2009cAsym_res-01_desc-brain_T1w.nii.gz


            # Define outputs
            ################

            FLAIR_IN_MNI_FLIRT=/tmp/${1}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-brain_FLAIR.nii.gz
            FLAIR_TO_MNI_WARP_FLIRT=$OUT_DIR/${1}_ses-${SESSION}_from-FLAIR_to-MNI152NLin2009cAsym_flirtwarp.txt
            MASTERFILE=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_masterfile.txt
            SEGMENTATION_raw=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-${ALGORITHM}_mask_raw.nii.gz           

            # Define commands
            #################

            CMD_FLIRT_FLAIR_TO_MNI="flirt -in $FLAIR_BRAIN -ref $MNI_TEMPLATE -out $FLAIR_IN_MNI_FLIRT -omat $FLAIR_TO_MNI_WARP_FLIRT"
            CMD_BIANCA="bianca --singlefile=$MASTERFILE --brainmaskfeaturenum=1 --querysubjectnum=1 --featuresubset=1,2 --matfeaturenum=3 -o $SEGMENTATION_raw -v --loadclassifierdata=$CLASSIFIER --patch3D --patchsizes=3,3,3"

            # Execute commands
            ##################

            $apptainer_fsl /bin/bash -c "$CMD_FLIRT_FLAIR_TO_MNI" 
            if [ -f $FLAIR_BRAIN ] && [ -f $T1_IN_FLAIR ] && [ -f $FLAIR_TO_MNI_WARP_FLIRT ] ; then   
                echo "$FLAIR_BRAIN $T1_IN_FLAIR $FLAIR_TO_MNI_WARP_FLIRT" > $MASTERFILE 
            fi
            $apptainer_fsl /bin/bash -c "$CMD_BIANCA" 

        fi

    fi
    
elif [ $ALGORITHM == "LOCATE" ]; then

    ##################
    # Part B: LOCATE #
    ##################

    # Note: You may need to run training locally, as run time can be very long.

    # Set up environment
    ####################
    
    TRAINING_DIR=$DATA_DIR/$PIPELINE/sourcedata/bianca_training
    MAN_SEGMENTATION_DIR=$DATA_DIR/$PIPELINE/sourcedata/manual_segmentations/

    LOCATE_working_dir=$DATA_DIR/$PIPELINE/sourcedata/MyLOCATE
    [ ! -d $LOCATE_working_dir ] && mkdir -p $LOCATE_working_dir
    LOCATE_training_dir=$LOCATE_working_dir/LOO_training_imgs
    [ ! -d $LOCATE_training_dir ] && mkdir -p $LOCATE_training_dir
    export LOCATE_training_dir

    
    if [ $LOCATE_LEVEL == "training" ]; then

        for sub in $(ls $DATA_DIR/$PIPELINE/sub-* -d | xargs -n 1 basename); do

            # Set up output directories
            ###########################

            OUT_DIR=$DATA_DIR/$PIPELINE/$sub/ses-${SESSION}/anat/
            ALGORITHM_OUT_DIR=$OUT_DIR/${ALGORITHM}/
            [ ! -d $ALGORITHM_OUT_DIR ] && mkdir $ALGORITHM_OUT_DIR

            [[ $(ls -A $MAN_SEGMENTATION_DIR/$sub) ]] && SUB_GROUP=training || SUB_GROUP=testing

            if [ $SUB_GROUP == "training" ]; then

                # Define inputs
                ###############

                FLAIR_BRAIN=$OUT_DIR/${sub}_ses-${SESSION}_desc-brain_FLAIR.nii.gz
                FLAIR_LOCATE=$LOCATE_training_dir/${sub}_feature_FLAIR.nii.gz 
                T1_IN_FLAIR=$OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii.gz
                T1_LOCATE=$LOCATE_training_dir/${sub}_feature_T1.nii.gz
                SEGMENTATION_MAN=$MAN_SEGMENTATION_DIR/$sub/anat/${sub}_DC_FLAIR_label4.nii.gz
                MANUAL_MASK_LOCATE=$LOCATE_training_dir/${sub}_manualmask.nii.gz
                DISTANCEMAP=$OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_distancemap.nii.gz
                DISTANCEMAP_LOCATE=$LOCATE_training_dir/${sub}_ventdistmap.nii.gz
                SEGMENTATION_raw=$OUT_DIR/BIANCA/${sub}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-BIANCA_mask_raw.nii.gz
                SEGMENTATION_raw_LOCATE=$LOCATE_training_dir/${sub}_BIANCA_LPM.nii.gz
                T1_MASK_IN_FLAIR=$OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-brain_mask.nii.gz
                BRAINMASK_LOCATE=$LOCATE_training_dir/${sub}_brainmask.nii.gz
                BIANCAMASK_LOCATE=$LOCATE_training_dir/${sub}_biancamask.nii.gz

                if [ -f $FLAIR_BRAIN ] && [ -f $T1_IN_FLAIR ] && [ -f $SEGMENTATION_MAN ] && [ -f $DISTANCEMAP ] && [ -f $SEGMENTATION_raw ] && [ -f $T1_MASK_IN_FLAIR ]; then
                
                    cp -ruvf $FLAIR_BRAIN $FLAIR_LOCATE
                    cp -ruvf $T1_IN_FLAIR $T1_LOCATE
                    cp -ruvf $SEGMENTATION_MAN $MANUAL_MASK_LOCATE
                    cp -ruvf $DISTANCEMAP $DISTANCEMAP_LOCATE
                    cp -ruvf $SEGMENTATION_raw $SEGMENTATION_raw_LOCATE
                    cp -ruvf $T1_MASK_IN_FLAIR $BRAINMASK_LOCATE
                    cp -ruvf $T1_MASK_IN_FLAIR $BIANCAMASK_LOCATE

                # else we will not copy any of the files into the LOCATE directory because LOCATE cannot handle incomplete data of subjects, throws an error and stops

                fi

            fi
            
        done

        # Define and execute locate command
        ###################################

        # locate.sif contains compiled LOCATE-BIANCA matlab code and an FSL installation
        # Running the container invokes this matlab function: locate(mode, training_dir, testing_dir)
        # mode: 'train'  / 'validate' / 'test'
        # training_dir: directory containing training data
        # testing_dir: directory containing testing data
        # USAGE
        ## when 'train' is selected, LOCATE will train with data contained in 'training_dir'.
        ## when 'validate' is selected, LOCATE will perform leave-one-out validation on the training data in 'training_dir'.
        ## when 'test' is selected, LOCATE will perform testing on the testing data in 'testing_dir'.
        ### requires definition of 'testing_dir' and 'training_dir'

        $apptainer_locate train $LOCATE_training_dir 

    elif [ $LOCATE_LEVEL == "validation" ]; then

        # Define and execute locate command
        ###################################
        
        $apptainer_locate validate $LOCATE_training_dir 

        # output are all files in $LOCATE_training_dir/LOCATE_LOO_results_directory

        for sub in $(ls $DATA_DIR/$PIPELINE/sub-* -d | xargs -n 1 basename); do

            [[ $(ls -A $MAN_SEGMENTATION_DIR/$sub) ]] && SUB_GROUP=training || SUB_GROUP=testing

            if [ $SUB_GROUP == "training" ]; then

                # Set up output directories
                ###########################

                OUT_DIR=$DATA_DIR/$PIPELINE/$sub/ses-${SESSION}/anat/
                ALGORITHM_OUT_DIR=$OUT_DIR/${ALGORITHM}/
                [ ! -d $ALGORITHM_OUT_DIR ] && mkdir $ALGORITHM_OUT_DIR

                # Define outputs
                ################

                SEGMENTATION_LOCATE=$LOCATE_training_dir/LOCATE_LOO_results_directory/${sub}_BIANCA_LOCATE_binarylesionmap.nii.gz
                SEGMENTATION_NOTHRESH=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-unmaskednothresh_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
                INDEXMAP_LOCATE==$LOCATE_training_dir/LOCATE_LOO_results_directory/${sub}_indexmap.nii.gz
                INDEXMAP=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_indexmap.nii.gz
                THRESHOLDSMAP_LOCATE=$LOCATE_training_dir/LOCATE_LOO_results_directory/${sub}_thresholdsmap.nii.gz
                THRESHOLDSMAP=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_thresholdsmap.nii.gz
                SEGMENTATION_masked=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-maskednothresh_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
                SEGMENTATION_sized=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-maskednothresh_desc-wmh_desc-${ALGORITHM}_mask_sized.nii.gz
                SEGMENTATION=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
                BRAINWITHOUTRIBBON_MASK_FLAIR=$OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-brainwithoutribbon_mask.nii.gz

                # Define commands
                #################

                CMD_MASKING_GAME="fslmaths $SEGMENTATION_NOTHRESH -mul $BRAINWITHOUTRIBBON_MASK_FLAIR $SEGMENTATION_masked"
                CMD_threshold_segmentation="fsl-cluster --in=$SEGMENTATION_masked --thresh=0.1 --connectivity=6 --osize=$SEGMENTATION_sized"
                CMD_thresholdcluster_segmentation="fslmaths $SEGMENTATION_sized -thr 5 -bin $SEGMENTATION"
                
                # Execute commands
                ##################

                cp $SEGMENTATION_LOCATE $SEGMENTATION_NOTHRESH
                cp $INDEXMAP_LOCATE $INDEXMAP
                cp $THRESHOLDSMAP_LOCATE $THRESHOLDSMAP
                $apptainer_fsl /bin/bash -c "$CMD_MASKING_GAME; $CMD_threshold_segmentation; $CMD_thresholdcluster_segmentation"

                # Clean up
                ##########
                
                if [ $MODIFIER == "clean" ]; then

                    rm $LOCATE_training_dir/LOCATE_LOO_results_directory/*
                    rm $SEGMENTATION_NOTHRESH $SEGMENTATION_masked $SEGMENTATION_sized 
                fi

            fi

        done
        
    elif [ $LOCATE_LEVEL == "testing" ]; then  

        [[ $(ls -A $MAN_SEGMENTATION_DIR/$1) ]] && SUB_GROUP=training || SUB_GROUP=testing

        if [ $SUB_GROUP == "testing" ]; then
            
            # Set up output directories
            ###########################
            OUT_DIR=$DATA_DIR/$PIPELINE/$1/ses-${SESSION}/anat/
            ALGORITHM_OUT_DIR=$OUT_DIR/${ALGORITHM}/
            [ ! -d $ALGORITHM_OUT_DIR ] && mkdir $ALGORITHM_OUT_DIR

            LOCATE_testing_dir=$LOCATE_working_dir/LOO_testing_imgs/$1
            [ ! -d $LOCATE_testing_dir ] && mkdir -p $LOCATE_testing_dir
            export LOCATE_testing_dir
            [ ! -d $LOCATE_testing_dir/LOCATE_results_directory ] && mkdir $LOCATE_testing_dir/LOCATE_results_directory
                        
            # Define inputs
            ###############

            FLAIR_BRAIN=$OUT_DIR/${1}_ses-${SESSION}_desc-brain_FLAIR.nii.gz
            FLAIR_LOCATE=$LOCATE_testing_dir/${1}_feature_FLAIR.nii.gz 
            T1_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii.gz
            T1_LOCATE=$LOCATE_testing_dir/${1}_feature_T1.nii.gz
            DISTANCEMAP=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_distancemap.nii.gz
            DISTANCEMAP_LOCATE=$LOCATE_testing_dir/${1}_ventdistmap.nii.gz
            SEGMENTATION_raw=$OUT_DIR/BIANCA/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-BIANCA_mask_raw.nii.gz
            SEGMENTATION_raw_LOCATE=$LOCATE_testing_dir/${1}_BIANCA_LPM.nii.gz
            T1_MASK_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brain_mask.nii.gz
            BRAINMASK_LOCATE=$LOCATE_testing_dir/${1}_brainmask.nii.gz
            BIANCAMASK_LOCATE=$LOCATE_testing_dir/${1}_biancamask.nii.gz
            BRAINWITHOUTRIBBON_MASK_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brainwithoutribbon_mask.nii.gz

            # Define output
            ###############

            SEGMENTATION_LOCATE=$LOCATE_testing_dir/LOCATE_results_directory/${1}_BIANCA_LOCATE_binarylesionmap.nii.gz
            SEGMENTATION_NOTHRESH=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-unmaskednothresh_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
            INDEXMAP_LOCATE=$LOCATE_testing_dir/LOCATE_results_directory/${1}_indexmap.nii.gz
            INDEXMAP=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_indexmap.nii.gz
            THRESHOLDSMAP_LOCATE=$LOCATE_testing_dir/LOCATE_results_directory/${1}_thresholdsmap.nii.gz
            THRESHOLDSMAP=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_thresholdsmap.nii.gz
            SEGMENTATION_masked=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-maskednothresh_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
            SEGMENTATION_sized=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-maskednothresh_desc-wmh_desc-${ALGORITHM}_mask_sized.nii.gz
            SEGMENTATION=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz

            # Define commands
            #################

            CMD_MASKING_GAME="fslmaths $SEGMENTATION_NOTHRESH -mul $BRAINWITHOUTRIBBON_MASK_FLAIR $SEGMENTATION_masked"
            CMD_threshold_segmentation="fsl-cluster --in=$SEGMENTATION_masked --thresh=0.1 --connectivity=6 --osize=$SEGMENTATION_sized"
            CMD_thresholdcluster_segmentation="fslmaths $SEGMENTATION_sized -thr 5 -bin $SEGMENTATION"            
            
            # Execute commands
            ##################
            
            if [ ! -f $SEGMENTATION_LOCATE ] && [ -f $FLAIR_BRAIN ] && [ -f $T1_IN_FLAIR ] && [ -f $DISTANCEMAP ] && [ -f $SEGMENTATION_raw ] && [ -f $T1_MASK_IN_FLAIR ]; then
                
                cp -ruvf $FLAIR_BRAIN $FLAIR_LOCATE
                cp -ruvf $T1_IN_FLAIR $T1_LOCATE
                cp -ruvf $DISTANCEMAP $DISTANCEMAP_LOCATE
                cp -ruvf $SEGMENTATION_raw $SEGMENTATION_raw_LOCATE
                cp -ruvf $T1_MASK_IN_FLAIR $BRAINMASK_LOCATE
                cp -ruvf $T1_MASK_IN_FLAIR $BIANCAMASK_LOCATE

                # else we will not copy any of the files into the LOCATE directory because LOCATE cannot handle incomplete data of subjects, throws an error and stops

            fi

            [ ! -f $SEGMENTATION_LOCATE ] && $apptainer_locate test $LOCATE_training_dir $LOCATE_testing_dir
            cp $SEGMENTATION_LOCATE $SEGMENTATION_NOTHRESH
            cp $INDEXMAP_LOCATE $INDEXMAP
            cp $THRESHOLDSMAP_LOCATE $THRESHOLDSMAP
            $apptainer_fsl /bin/bash -c "$CMD_MASKING_GAME; $CMD_threshold_segmentation; $CMD_thresholdcluster_segmentation"

            if [ $MODIFIER == "clean" ]; then

                rm -rvf $LOCATE_testing_dir/*
                rm -rvf $SEGMENTATION_NOTHRESH $SEGMENTATION_masked $SEGMENTATION_sized 
            fi

        fi

    fi

fi