#!/usr/bin/env bash

###################################################################################################################
# Preprocessing of FLAIR and T1 and creation of input files for WMH segmentation 
#                                                                                                                 
# Pipeline specific dependencies:                                                                                 
#   [pipelines which need to be run first]                                                                        
#       - wmh_01_prep in wmh
#       - fmriprep  
#       - freesurfer                                                                                                  
#   [container]                                                                                                   
#       - fsl-6.0.3.sif
#       - freesurfer-7.1.1.sif     
#       - mrtrix3-3.0.2    
#       - antsrnet
#                                                                           
###################################################################################################################

# Get verbose outputs
set -x
ulimit -c 0

# Define subject specific temporary directory on $SCRATCH_DIR
export TMP_DIR=$SCRATCH_DIR/$1/tmp/;   [ ! -d $TMP_DIR ] && mkdir -p $TMP_DIR
TMP_IN=$TMP_DIR/input;                 [ ! -d $TMP_IN ] && mkdir -p $TMP_IN
TMP_OUT=$TMP_DIR/output;               [ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT

###################################################################################################################

# Pipeline-specific environment
##################################

# Singularity container version and command
container_freesurfer=freesurfer-7.1.1
singularity_freesurfer="singularity run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_freesurfer" 

container_fsl=fsl-6.0.3
singularity_fsl="singularity run --cleanenv --userns \
    -B $PROJ_DIR/../ \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_fsl" 

FSLDIR=/work/fatx129/software/fsl-6.0.5
export FSLDIR
PATH=${FSLDIR}/bin:${PATH}
export FSLDIR PATH

container_mrtrix=mrtrix3-3.0.2
singularity_mrtrix="singularity run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_mrtrix" 

container_antsrnet=antsrnet
singularity_antsrnet="singularity run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_antsrnet" 

# Set output directories
OUT_DIR=$DATA_DIR/$PIPELINE/$1/ses-${SESSION}/anat/
[ ! -d $OUT_DIR ] && mkdir -p $OUT_DIR
[ $BIASCORR == y ] && ALGORITHM_OUT_DIR=$OUT_DIR/${ALGORITHM}bias/
[ $BIASCORR == n ] && ALGORITHM_OUT_DIR=$OUT_DIR/${ALGORITHM}/
[ ! -d $ALGORITHM_OUT_DIR ] && mkdir -p $ALGORITHM_OUT_DIR
DERIVATIVE_dir=$DATA_DIR/$PIPELINE/derivatives
[ ! -d $DERIVATIVE_dir ] && mkdir -p $DERIVATIVE_dir

# To make I/O more efficient read/write outputs from/to $SCRATCH
[ -d $TMP_IN ] && cp -rf $BIDS_DIR/$1 $BIDS_DIR/dataset_description.json $TMP_IN 
[ -d $TMP_OUT ] && mkdir -p $TMP_OUT/wmh $TMP_OUT/wmh

# $MRTRIX_TMPFILE_DIR should be big and writable
export MRTRIX_TMPFILE_DIR=/tmp

# Pipeline execution
##################################

if [ $ALGORITHM == "antsrnet" ]; then

    # as determined with wmh_determine_thresh.sh
    [ $BIASCORR == n ] && threshold=0.3
    [ $BIASCORR == y ] && threshold=0.15

    # Define inputs
    [ $BIASCORR == n ] && FLAIR=$DATA_DIR/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz
    [ $BIASCORR == y ] && FLAIR=$OUT_DIR/${1}_ses-${SESSION}_desc-biascorr_FLAIR.nii.gz
    T1_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii.gz
    BRAINWITHOUTRIBBON_MASK_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brainwithoutribbon_mask.nii.gz

    # Define outputs
    [ $BIASCORR == n ] && SEGMENTATION=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
    [ $BIASCORR == y ] && SEGMENTATION=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-${ALGORITHM}bias_mask.nii.gz
    export SEGMENTATION
    [ $BIASCORR == n ] && SEGMENTATION_FILTERED=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-maskednothresh_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
    [ $BIASCORR == y ] && SEGMENTATION_FILTERED=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-maskednothresh_desc-wmh_desc-${ALGORITHM}bias_mask.nii.gz
    [ $BIASCORR == n ] && SEGMENTATION_THRESH=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
    [ $BIASCORR == y ] && SEGMENTATION_THRESH=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}bias_mask.nii.gz

    # Define commands
    CMD_MASKING_GAME="fslmaths $SEGMENTATION -mul $BRAINWITHOUTRIBBON_MASK_FLAIR $SEGMENTATION_FILTERED"
    CMD_THRESH_SEGMENTATION="fslmaths $SEGMENTATION_FILTERED -thr $threshold -bin $SEGMENTATION_THRESH"

    # Execute 
    #$singularity_antsrnet Rscript -e "flair<-antsImageRead('$FLAIR'); t1<-antsImageRead('$T1_IN_FLAIR'); probabilitymask<-sysuMediaWmhSegmentation(flair, t1); antsImageWrite(probabilitymask, '$SEGMENTATION')"
    $singularity_antsrnet Rscript -e "flair<-antsImageRead('$FLAIR'); probabilitymask<-sysuMediaWmhSegmentation(flair); antsImageWrite(probabilitymask, '$SEGMENTATION')"
    $singularity_fsl /bin/bash -c "$CMD_MASKING_GAME"
    $singularity_fsl /bin/bash -c "$CMD_THRESH_SEGMENTATION"



elif [ $ALGORITHM == "bianca" ]; then

    MAN_SEGMENTATION_DIR=$PROJ_DIR/../CSI_WMH_MASKS_HCHS_pseud/HCHS/
    
    if [ $BIANCA_LEVEL == "training" ]; then

        TRAINING_DIR=$DATA_DIR/$PIPELINE/sourcedata/BIANCA_training
        [ ! -d $TRAINING_DIR ] && mkdir -p $TRAINING_DIR
        MASTERFILE=$TRAINING_DIR/masterfile.txt
        [ -f $MASTERFILE ] && rm $MASTERFILE

        for sub in $(ls $DATA_DIR/$PIPELINE/sub-* -d | xargs -n 1 basename); do

            OUT_DIR=$DATA_DIR/$PIPELINE/$sub/ses-${SESSION}/anat/
            [ $BIASCORR == y ] && ALGORITHM_OUT_DIR=$OUT_DIR/${ALGORITHM}bias/
            [ $BIASCORR == n ] && ALGORITHM_OUT_DIR=$OUT_DIR/${ALGORITHM}/
            [ ! -d $ALGORITHM_OUT_DIR ] && mkdir $ALGORITHM_OUT_DIR

            [[ $(ls -A $MAN_SEGMENTATION_DIR/${sub}) ]] && SUB_GROUP=training || SUB_GROUP=testing

            if [ $SUB_GROUP == "training" ]; then

                # as determined with wmh_determine_thresh.sh
                threshold=0.8

                # Define inputs
                BRAINWITHOUTRIBBON_MASK_FLAIR=$OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-brainwithoutribbon_mask.nii.gz
                MNI_TEMPLATE=$ENV_DIR/standard/tpl-MNI152NLin2009cAsym_res-01_desc-brain_T1w.nii.gz
                FLAIR_BRAIN=$OUT_DIR/${sub}_ses-${SESSION}_desc-brain_FLAIR.nii.gz
                T1_IN_FLAIR=$OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii.gz
                SEGMENTATION_MAN=$MAN_SEGMENTATION_DIR/$sub/anat/${sub}_DC_FLAIR_label4.nii.gz

                # Define outputs
                MASTERFILE=$TRAINING_DIR/masterfile.txt
                SEGMENTATION_raw=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-${ALGORITHM}_mask_raw.nii.gz
                FLAIR_IN_MNI_FLIRT=/tmp/${sub}_ses-${SESSION}_space-MNI_desc-brain_FLAIR.nii.gz
                FLAIR_TO_MNI_WARP_FLIRT=$OUT_DIR/${sub}_ses-${SESSION}_from-FLAIR_to-MNI_flirtwarp.txt
                CLASSIFIER=$TRAINING_DIR/classifierdata
                SEGMENTATION_sized=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-${ALGORITHM}_mask_sized.nii.gz
                SEGMENTATION=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
                SEGMENTATION_FILTERED=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
                
                # Define commands
                CMD_FLIRT_FLAIR_TO_MNI="flirt -in $FLAIR_BRAIN -ref $MNI_TEMPLATE -out $FLAIR_IN_MNI_FLIRT -omat $FLAIR_TO_MNI_WARP_FLIRT"
                CMD_BIANCA="bianca --singlefile=$MASTERFILE --brainmaskfeaturenum=1 --querysubjectnum=1 --trainingnums=all --featuresubset=1,2 --matfeaturenum=3 --labelfeaturenum=4 --trainingpts=2000 --nonlespts=10000 --selectpts=noborder -v --saveclassifierdata=$CLASSIFIER --patch3D --patchsizes=3,3,3"

                # Execute
                $singularity_fsl /bin/bash -c "$CMD_FLIRT_FLAIR_TO_MNI"
                if [ -f $FLAIR_BRAIN ] && [ -f $T1_IN_FLAIR ] && [ -f $FLAIR_TO_MNI_WARP_FLIRT ] && [ -f $SEGMENTATION_MAN ] ; then   
                    echo "$FLAIR_BRAIN $T1_IN_FLAIR $FLAIR_TO_MNI_WARP_FLIRT $SEGMENTATION_MAN" >> $MASTERFILE
                fi

            fi

        done

        # Execute bianca
        $singularity_fsl /bin/bash -c "$CMD_BIANCA"
    
    elif [ $BIANCA_LEVEL == "validation" ]; then

        [[ $(ls -A $MAN_SEGMENTATION_DIR/${1}) ]] && SUB_GROUP=training || SUB_GROUP=testing

        if [ $SUB_GROUP == "training" ]; then  

            threshold=0.8

            # Define inputs
            TRAINING_DIR=$DATA_DIR/$PIPELINE/sourcedata/BIANCA_training
            [ ! -d $TRAINING_DIR ] && mkdir -p $TRAINING_DIR
            OUT_DIR=$DATA_DIR/$PIPELINE/$1/ses-${SESSION}/anat/
            [ $BIASCORR == y ] && ALGORITHM_OUT_DIR=$OUT_DIR/${ALGORITHM}bias/
            [ $BIASCORR == n ] && ALGORITHM_OUT_DIR=$OUT_DIR/${ALGORITHM}/
            [ ! -d $ALGORITHM_OUT_DIR ] && mkdir $ALGORITHM_OUT_DIR

            BRAINWITHOUTRIBBON_MASK_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brainwithoutribbon_mask.nii.gz
            FLAIR_BRAIN=$OUT_DIR/${1}_ses-${SESSION}_desc-brain_FLAIR.nii.gz
            T1_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii.gz
            SEGMENTATION_MAN=$MAN_SEGMENTATION_DIR/$1/anat/${1}_DC_FLAIR_label4.nii.gz
            FLAIR_TO_MNI_WARP_FLIRT=$OUT_DIR/${1}_ses-${SESSION}_from-FLAIR_to-MNI_flirtwarp.txt
            MASTERFILE=$TRAINING_DIR/masterfile.txt
            CLASSIFIER=$TRAINING_DIR/classifierdata
            subjectline=$(cat $MASTERFILE | grep -n $1 | awk -F: '{print $1}')

            # Define output
            SEGMENTATION_raw=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-${ALGORITHM}_mask_raw.nii.gz
            SEGMENTATION_masked=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-maskednothresh_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
            SEGMENTATION_sized=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-maskednothresh_desc-wmh_desc-${ALGORITHM}_mask_sized.nii.gz
            SEGMENTATION=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-${ALGORITHM}_mask.nii.gz

            # Define commands
            CMD_BIANCA_leaveoneout="bianca --singlefile=$MASTERFILE --brainmaskfeaturenum=1 --querysubjectnum=$subjectline --featuresubset=1,2 --matfeaturenum=3 --trainingpts=2000 --nonlespts=10000 --selectpts=noborder -o $SEGMENTATION_raw -v --loadclassifierdata=$CLASSIFIER --patch3D --patchsizes=3,3,3"
            CMD_MASKING_GAME="fslmaths $SEGMENTATION_raw -mul $BRAINWITHOUTRIBBON_MASK_FLAIR $SEGMENTATION_masked"
            CMD_threshold_segmentation="cluster --in=$SEGMENTATION_masked --thresh=0.1 --connectivity=6 --osize=$SEGMENTATION_sized"
            CMD_thresholdcluster_segmentation="fslmaths $SEGMENTATION_sized -thr 5 -bin $SEGMENTATION"
            

            if [ -f $FLAIR_BRAIN ] && [ -f $T1_IN_FLAIR ] && [ -f $FLAIR_TO_MNI_WARP_FLIRT ] && [ -f $SEGMENTATION_MAN ] ; then  

                # Execute
                $singularity_fsl /bin/bash -c "$CMD_BIANCA_leaveoneout; $CMD_MASKING_GAME; $CMD_threshold_segmentation; $CMD_thresholdcluster_segmentation"

            fi

        fi
    
    elif [ $BIANCA_LEVEL == "testing" ]; then

        [[ $(ls -A $MAN_SEGMENTATION_DIR/${1}) ]] && SUB_GROUP=training || SUB_GROUP=testing

        if [ $SUB_GROUP == "testing" ]; then

            TRAINING_DIR=$DATA_DIR/$PIPELINE/sourcedata/BIANCA_training

            # as determined with wmh_determine_thresh.sh
            threshold=0.8

            # Define inputs 
            FLAIR_BRAIN=$OUT_DIR/${1}_ses-${SESSION}_desc-brain_FLAIR.nii.gz
            T1_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii.gz
            CLASSIFIER=$TRAINING_DIR/classifierdata
            BRAINWITHOUTRIBBON_MASK_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brainwithoutribbon_mask.nii.gz
            MNI_TEMPLATE=$ENV_DIR/standard/tpl-MNI152NLin2009cAsym_res-01_desc-brain_T1w.nii.gz


            # Define outputs
            FLAIR_IN_MNI_FLIRT=/tmp/${sub}_ses-${SESSION}_space-MNI_desc-brain_FLAIR.nii.gz
            FLAIR_TO_MNI_WARP_FLIRT=$OUT_DIR/${1}_ses-${SESSION}_from-FLAIR_to-MNI_flirtwarp.txt
            MASTERFILE=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_masterfile.txt
            SEGMENTATION_raw=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-${ALGORITHM}_mask_raw.nii.gz
            SEGMENTATION_masked=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-maskednothresh_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
            SEGMENTATION_sized=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-maskednothresh_desc-wmh_desc-${ALGORITHM}_mask_sized.nii.gz
            SEGMENTATION=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
            

            # Define commands
            CMD_FLIRT_FLAIR_TO_MNI="flirt -in $FLAIR_BRAIN -ref $MNI_TEMPLATE -out $FLAIR_IN_MNI_FLIRT -omat $FLAIR_TO_MNI_WARP_FLIRT"
            CMD_BIANCA="bianca --singlefile=$MASTERFILE --brainmaskfeaturenum=1 --querysubjectnum=1 --featuresubset=1,2 --matfeaturenum=3 -o $SEGMENTATION_raw -v --loadclassifierdata=$CLASSIFIER --patch3D --patchsizes=3,3,3"
            #CMD_MASKING_GAME="fslmaths $SEGMENTATION -mul $BRAINWITHOUTRIBBON_MASK_FLAIR $SEGMENTATION_masked"
            #CMD_threshold_segmentation="cluster --in=$SEGMENTATION_masked --thresh=$threshold --connectivity=6 --osize=$SEGMENTATION_sized"
            #CMD_thresholdcluster_segmentation="fslmaths $SEGMENTATION_sized -thr 5 -bin $SEGMENTATION"
            
            
            # Execute
            $singularity_fsl /bin/bash -c "$CMD_FLIRT_FLAIR_TO_MNI" 
            if [ -f $FLAIR_BRAIN ] && [ -f $T1_IN_FLAIR ] && [ -f $FLAIR_TO_MNI_WARP_FLIRT ] ; then   
                echo "$FLAIR_BRAIN $T1_IN_FLAIR $FLAIR_TO_MNI_WARP_FLIRT" > $MASTERFILE 
            fi
            $singularity_fsl /bin/bash -c "$CMD_BIANCA" 
            # $CMD_MASKING_GAME; $CMD_threshold_segmentation; $CMD_thresholdcluster_segmentation"

        fi

    fi

    
elif [ $ALGORITHM == "LOCATE" ]; then

    # it is best to run this locally. It takes more than maximum batch time to run

    source $FSLDIR
    module load matlab

    LOCATE_installation=$ENV_DIR/LOCATE-BIANCA
    export LOCATE_installation

    LOCATE_working_dir=$DATA_DIR/$PIPELINE/MyLOCATE
    [ ! -d $LOCATE_working_dir ] && mkdir -p $LOCATE_working_dir
    LOCATE_training_dir=$LOCATE_working_dir/LOO_training_imgs
    [ ! -d $LOCATE_training_dir ] && mkdir -p $LOCATE_training_dir
    export LOCATE_training_dir

    MAN_SEGMENTATION_DIR=$PROJ_DIR/../CSI_WMH_MASKS_HCHS_pseud/HCHS/
    
    if [ $LOCATE_LEVEL == "training" ]; then

        for sub in $(ls $DATA_DIR/$PIPELINE/sub-* -d | xargs -n 1 basename); do

            [[ $(ls -A $MAN_SEGMENTATION_DIR/$sub) ]] && SUB_GROUP=training || SUB_GROUP=testing

            if [ $SUB_GROUP == "training" ]; then

                OUT_DIR=$DATA_DIR/$PIPELINE/$sub/ses-${SESSION}/anat/
                [ $BIASCORR == y ] && ALGORITHM_OUT_DIR=$OUT_DIR/${ALGORITHM}bias/
                [ $BIASCORR == n ] && ALGORITHM_OUT_DIR=$OUT_DIR/${ALGORITHM}/
                [ ! -d $ALGORITHM_OUT_DIR ] && mkdir $ALGORITHM_OUT_DIR

                # Define inputs
                FLAIR_BRAIN=$OUT_DIR/${sub}_ses-${SESSION}_desc-brain_FLAIR.nii.gz
                FLAIR_LOCATE=$LOCATE_training_dir/${sub}_feature_FLAIR.nii.gz 
                T1_IN_FLAIR=$OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii.gz
                T1_LOCATE=$LOCATE_training_dir/${sub}_feature_T1.nii.gz
                SEGMENTATION_MAN=$MAN_SEGMENTATION_DIR/$sub/anat/${sub}_DC_FLAIR_label4.nii.gz
                MANUAL_MASK_LOCATE=$LOCATE_training_dir/${sub}_manualmask.nii.gz
                DISTANCEMAP=$OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_distancemap.nii.gz
                DISTANCEMAP_LOCATE=$LOCATE_training_dir/${sub}_ventdistmap.nii.gz
                SEGMENTATION_raw=$OUT_DIR/bianca/${sub}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-bianca_mask_raw.nii.gz
                SEGMENTATION_raw_LOCATE=$LOCATE_training_dir/${sub}_BIANCA_LPM.nii.gz
                T1_MASK_IN_FLAIR=$OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-brain_mask.nii.gz
                BRAINMASK_LOCATE=$LOCATE_training_dir/${sub}_brainmask.nii.gz
                BIANCAMASK_LOCATE=$LOCATE_training_dir/${sub}_biancamask.nii.gz

                if [ -f $FLAIR_BRAIN ] && [ -f $T1_IN_FLAIR ] && [ -f $SEGMENTATION_MAN ] && [ -f $DISTANCEMAP ] && [ -f $SEGMENTATION_raw ] && [ -f $T1_MASK_IN_FLAIR ]; then
                
                    cp $FLAIR_BRAIN $FLAIR_LOCATE
                    cp $T1_IN_FLAIR $T1_LOCATE
                    cp $SEGMENTATION_MAN $MANUAL_MASK_LOCATE
                    cp $DISTANCEMAP $DISTANCEMAP_LOCATE
                    cp $SEGMENTATION_raw $SEGMENTATION_raw_LOCATE
                    cp $T1_MASK_IN_FLAIR $BRAINMASK_LOCATE
                    cp $T1_MASK_IN_FLAIR $BIANCAMASK_LOCATE

                # else we will not copy any of the files into the LOCATE directory because LOCATE cannot handle incomplete data of subjects, throws an error and stops

                fi

            fi
            
        done

        matlab -nosplash -nodesktop -nojvm -batch "addpath(genpath('$LOCATE_installation')); LOCATE_training('$LOCATE_training_dir'); quit"            

    elif [ $LOCATE_LEVEL == "validation" ]; then

        #matlab -nosplash -nodesktop -nojvm -batch "addpath(genpath('$LOCATE_installation')); LOCATE_LOO_testing('$LOCATE_training_dir'); quit"

        # output are all files in $LOCATE_training_dir/LOCATE_LOO_results_directory

        for sub in $(ls $DATA_DIR/$PIPELINE/sub-* -d | xargs -n 1 basename); do

            [[ $(ls -A $MAN_SEGMENTATION_DIR/$sub) ]] && SUB_GROUP=training || SUB_GROUP=testing

            if [ $SUB_GROUP == "training" ]; then

                OUT_DIR=$DATA_DIR/$PIPELINE/$sub/ses-${SESSION}/anat/
                [ $BIASCORR == y ] && ALGORITHM_OUT_DIR=$OUT_DIR/${ALGORITHM}bias/
                [ $BIASCORR == n ] && ALGORITHM_OUT_DIR=$OUT_DIR/${ALGORITHM}/
                [ ! -d $ALGORITHM_OUT_DIR ] && mkdir $ALGORITHM_OUT_DIR

                # Define outputs
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
                WMH_VOLUME_FILE=$DERIVATIVE_dir/${sub}_ses-1_${ALGORITHM}_wmhvolume.csv

                # Define commands
                CMD_MASKING_GAME="fslmaths $SEGMENTATION_NOTHRESH -mul $BRAINWITHOUTRIBBON_MASK_FLAIR $SEGMENTATION_masked"
                CMD_threshold_segmentation="cluster --in=$SEGMENTATION_masked --thresh=0.1 --connectivity=6 --osize=$SEGMENTATION_sized"
                CMD_thresholdcluster_segmentation="fslmaths $SEGMENTATION_sized -thr 5 -bin $SEGMENTATION"
                
                # Execute
                cp $SEGMENTATION_LOCATE $SEGMENTATION_NOTHRESH
                cp $INDEXMAP_LOCATE $INDEXMAP
                cp $THRESHOLDSMAP_LOCATE $THRESHOLDSMAP
                $singularity_fsl /bin/bash -c "$CMD_MASKING_GAME; $CMD_threshold_segmentation; $CMD_thresholdcluster_segmentation"
                $singularity_fsl /bin/bash -c "$(echo fslstats $SEGMENTATION -V) > $WMH_VOLUME_FILE"
                [ ! -f $SEGMENTATION ] && echo "na na" > $WMH_VOLUME_FILE

            fi

        done
        
    elif [ $LOCATE_LEVEL == "testing" ]; then  

        [[ $(ls -A $MAN_SEGMENTATION_DIR/$1) ]] && SUB_GROUP=training || SUB_GROUP=testing

        if [ $SUB_GROUP == "testing" ]; then

            LOCATE_upper_testing_dir=$LOCATE_working_dir/LOO_testing_imgs
            [ ! -d $LOCATE_upper_testing_dir ] && mkdir -p $LOCATE_upper_testing_dir

            LOCATE_testing_dir=$LOCATE_working_dir/LOO_testing_imgs/$1
            [ ! -d $LOCATE_testing_dir ] && mkdir -p $LOCATE_testing_dir
            export LOCATE_testing_dir
            [ ! -d $LOCATE_testing_dir/LOCATE_results_directory ] && mkdir $LOCATE_testing_dir/LOCATE_results_directory

            # Define inputs
            FLAIR_BRAIN=$OUT_DIR/${1}_ses-${SESSION}_desc-brain_FLAIR.nii.gz
            FLAIR_LOCATE=$LOCATE_testing_dir/${1}_feature_FLAIR.nii.gz 
            T1_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii.gz
            T1_LOCATE=$LOCATE_testing_dir/${1}_feature_T1.nii.gz
            DISTANCEMAP=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_distancemap.nii.gz
            DISTANCEMAP_LOCATE=$LOCATE_testing_dir/${1}_ventdistmap.nii.gz
            SEGMENTATION_raw=$OUT_DIR/bianca/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-bianca_mask_raw.nii.gz
            SEGMENTATION_raw_LOCATE=$LOCATE_testing_dir/${1}_BIANCA_LPM.nii.gz
            T1_MASK_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brain_mask.nii.gz
            BRAINMASK_LOCATE=$LOCATE_testing_dir/${1}_brainmask.nii.gz
            BIANCAMASK_LOCATE=$LOCATE_testing_dir/${1}_biancamask.nii.gz
            BRAINWITHOUTRIBBON_MASK_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brainwithoutribbon_mask.nii.gz

            # Define output
            SEGMENTATION_LOCATE=$LOCATE_testing_dir/LOCATE_results_directory/${1}_BIANCA_LOCATE_binarylesionmap.nii.gz
            SEGMENTATION_NOTHRESH=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-unmaskednothresh_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
            INDEXMAP_LOCATE=$LOCATE_testing_dir/LOCATE_results_directory/${1}_indexmap.nii.gz
            INDEXMAP=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_indexmap.nii.gz
            THRESHOLDSMAP_LOCATE=$LOCATE_testing_dir/LOCATE_results_directory/${1}_thresholdsmap.nii.gz
            THRESHOLDSMAP=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_thresholdsmap.nii.gz
            SEGMENTATION_masked=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-maskednothresh_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
            SEGMENTATION_sized=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-maskednothresh_desc-wmh_desc-${ALGORITHM}_mask_sized.nii.gz
            SEGMENTATION=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
            WMH_VOLUME_FILE=$DERIVATIVE_dir/${1}_ses-1_${ALGORITHM}_wmhvolume.csv

            # Define commands
            CMD_MASKING_GAME="fslmaths $SEGMENTATION_NOTHRESH -mul $BRAINWITHOUTRIBBON_MASK_FLAIR $SEGMENTATION_masked"
            CMD_threshold_segmentation="cluster --in=$SEGMENTATION_masked --thresh=0.1 --connectivity=6 --osize=$SEGMENTATION_sized"
            CMD_thresholdcluster_segmentation="fslmaths $SEGMENTATION_sized -thr 5 -bin $SEGMENTATION"            
            

            # Execute
            if [ ! -f $SEGMENTATION_LOCATE ] && [ -f $FLAIR_BRAIN ] && [ -f $T1_IN_FLAIR ] && [ -f $DISTANCEMAP ] && [ -f $SEGMENTATION_raw ] && [ -f $T1_MASK_IN_FLAIR ]; then
                
                cp $FLAIR_BRAIN $FLAIR_LOCATE
                cp $T1_IN_FLAIR $T1_LOCATE
                cp $DISTANCEMAP $DISTANCEMAP_LOCATE
                cp $SEGMENTATION_raw $SEGMENTATION_raw_LOCATE
                cp $T1_MASK_IN_FLAIR $BRAINMASK_LOCATE
                cp $T1_MASK_IN_FLAIR $BIANCAMASK_LOCATE

                # else we will not copy any of the files into the LOCATE directory because LOCATE cannot handle incomplete data of subjects, throws an error and stops

            fi

            [ ! -f $SEGMENTATION_LOCATE ] && matlab -nosplash -nodesktop -nojvm -batch "addpath(genpath('$LOCATE_installation')); addpath(genpath('$LOCATE_installation/MATLAB')); setenv( 'FSLDIR', '$FSLDIR' ); setenv('PATH', [getenv('PATH'),':$FSLDIR/bin']); LOCATE_testing('$LOCATE_testing_dir', '$LOCATE_training_dir'); quit"
            cp $SEGMENTATION_LOCATE $SEGMENTATION_NOTHRESH
            cp $INDEXMAP_LOCATE $INDEXMAP
            cp $THRESHOLDSMAP_LOCATE $THRESHOLDSMAP
            $singularity_fsl /bin/bash -c "$CMD_MASKING_GAME; $CMD_threshold_segmentation; $CMD_thresholdcluster_segmentation"
            $singularity_fsl /bin/bash -c "$(echo fslstats $SEGMENTATION -V) > $WMH_VOLUME_FILE"
            [ ! -f $SEGMENTATION ] && echo "na na" > $WMH_VOLUME_FILE

        fi

    fi

elif [ $ALGORITHM == "lga" ]; then

    module load matlab/2019b 
    # as determined with wmh_determine_thresh.sh
    threshold=0.7
    kappa=0.1
    export kappa 

    # Define inputs 
    T1_IN_FLAIR_nii=/work/fatx405/projects/CSI_WMH_EVAL/$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii
    FLAIR_nii=/work/fatx405/projects/CSI_WMH_EVAL/$OUT_DIR/${1}_ses-${SESSION}_FLAIR.nii
    export T1_IN_FLAIR_nii
    export FLAIR_nii
    BRAINWITHOUTRIBBON_MASK_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brainwithoutribbon_mask.nii.gz

    # Define outputs
    SEGMENTATION_nii=$ALGORITHM_OUT_DIR/ples_${ALGORITHM}_${kappa}_rm${1}_ses-${SESSION}_FLAIR.nii
    SEGMENTATION=$ALGORITHM_OUT_DIR/ples_${ALGORITHM}_${kappa}_rm${1}_ses-${SESSION}_FLAIR.nii.gz
    SEGMENTATION_NOFILT=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-maskednothresh_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
    SEGMENTATION_FILTERED=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz

    # Define commands
    CMD_CONVERT_SEG="mri_convert $SEGMENTATION_nii $SEGMENTATION"
    CMD_MASKING_GAME="fslmaths $SEGMENTATION -mul $BRAINWITHOUTRIBBON_MASK_FLAIR $SEGMENTATION_NOFILT"
    CMD_THRESH_SEGMENTATION="fslmaths $SEGMENTATION_NOFILT -thr $threshold -bin $SEGMENTATION_FILTERED"

    # Execute 
    matlab -nosplash -nodesktop -nojvm -batch "addpath(genpath('$ENV_DIR/spm12')); ps_LST_lga('$T1_IN_FLAIR_nii', '$FLAIR_nii', '$kappa'); quit"
    cp -fu $OUT_DIR/ples_${ALGORITHM}_${kappa}_rm${1}_ses-${SESSION}_FLAIR.nii $ALGORITHM_OUT_DIR/ ; rm $OUT_DIR/ples_${ALGORITHM}_${kappa}_rm${1}_ses-${SESSION}_FLAIR.nii
    cp -fur $OUT_DIR/LST_${ALGORITHM}_${kappa}_rm${1}_ses-${SESSION}_FLAIR $ALGORITHM_OUT_DIR/ ; rm -r $OUT_DIR/LST_${ALGORITHM}_${kappa}_rm${1}_ses-${SESSION}_FLAIR
    cp -fu $OUT_DIR/LST_${ALGORITHM}_rm${1}_ses-${SESSION}_FLAIR.mat $ALGORITHM_OUT_DIR/ ; rm $OUT_DIR/LST_${ALGORITHM}_rm${1}_ses-${SESSION}_FLAIR.mat
    cp -fu $OUT_DIR/report_LST_${ALGORITHM}* $ALGORITHM_OUT_DIR/ ; rm $OUT_DIR/report_LST_${ALGORITHM}*
    cp -fu $OUT_DIR/rm${1}_ses-${SESSION}_FLAIR.nii $ALGORITHM_OUT_DIR/ ; rm $OUT_DIR/rm${1}_ses-${SESSION}_FLAIR.nii
    rm -r $OUT_DIR/LST_tmp_*
    $singularity_freesurfer /bin/bash -c "$CMD_CONVERT_SEG"
    rm $SEGMENTATION_nii
    $singularity_fsl /bin/bash -c "$CMD_MASKING_GAME; $CMD_THRESH_SEGMENTATION"
    

elif [ $ALGORITHM == "lpa" ]; then

    module load matlab/2019b

    # as determined with wmh_determine_thresh.sh
    threshold=0.15

    # Define inputs 
    T1_IN_FLAIR_nii=/work/fatx405/projects/CSI_WMH_EVAL/$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii
    FLAIR_nii=/work/fatx405/projects/CSI_WMH_EVAL/$OUT_DIR/${1}_ses-${SESSION}_FLAIR.nii
    export T1_IN_FLAIR_nii
    export FLAIR_nii
    BRAINWITHOUTRIBBON_MASK_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brainwithoutribbon_mask.nii.gz

    # Define outputs
    #SEGMENTATION_nii=$ALGORITHM_OUT_DIR/ples_${ALGORITHM}_mr${1}_ses-${SESSION}_FLAIR.nii
    #SEGMENTATION=$ALGORITHM_OUT_DIR/ples_${ALGORITHM}_mr${1}_ses-${SESSION}_FLAIR.nii.gz
    #SEGMENTATION_NOFILT=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-maskednothresh_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
    #SEGMENTATION_FILTERED=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
    SEGMENTATION_nii=$ALGORITHM_OUT_DIR/ples_${ALGORITHM}_m${1}_ses-${SESSION}_FLAIR.nii
    SEGMENTATION=$ALGORITHM_OUT_DIR/ples_${ALGORITHM}_m${1}_ses-${SESSION}_FLAIR.nii.gz
    SEGMENTATION_NOFILT=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-maskednothresh_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
    SEGMENTATION_FILTERED=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz

    # Define commands
    CMD_CONVERT_SEG="mri_convert $SEGMENTATION_nii $SEGMENTATION"
    CMD_MASKING_GAME="fslmaths $SEGMENTATION -mul $BRAINWITHOUTRIBBON_MASK_FLAIR $SEGMENTATION_NOFILT"
    CMD_THRESH_SEGMENTATION="fslmaths $SEGMENTATION_NOFILT -thr $threshold -bin $SEGMENTATION_FILTERED"

    # Execute 
    #matlab -nosplash -nodesktop -nojvm -batch "addpath(genpath('$ENV_DIR/spm12')); ps_LST_lpa('$FLAIR_nii', '$T1_IN_FLAIR_nii'); quit"
    #cp -fu $OUT_DIR/ples_${ALGORITHM}_mr${1}_ses-${SESSION}_FLAIR.nii $ALGORITHM_OUT_DIR ; rm $OUT_DIR/ples_${ALGORITHM}_mr${1}_ses-${SESSION}_FLAIR.nii
    #cp -fur $OUT_DIR/LST_${ALGORITHM}_mr${1}_ses-${SESSION}_FLAIR $ALGORITHM_OUT_DIR/ ; rm -r $OUT_DIR/LST_${ALGORITHM}_mr${1}_ses-${SESSION}_FLAIR
    #cp -fu $OUT_DIR/LST_${ALGORITHM}_mr${1}_ses-${SESSION}_FLAIR.mat $ALGORITHM_OUT_DIR/ ; rm $OUT_DIR/LST_${ALGORITHM}_mr${1}_ses-${SESSION}_FLAIR.mat
    #cp -fu $OUT_DIR/report_LST_${ALGORITHM}* $ALGORITHM_OUT_DIR/ ; rm $OUT_DIR/report_LST_${ALGORITHM}* 
    #cp -fu $OUT_DIR/mr${1}_ses-${SESSION}_FLAIR.nii $ALGORITHM_OUT_DIR/ ; rm $OUT_DIR/mr${1}_ses-${SESSION}_FLAIR.nii
    #rm -r $OUT_DIR/LST_tmp_*

    #matlab -nosplash -nodesktop -nojvm -batch "addpath(genpath('$ENV_DIR/spm12')); ps_LST_lpa('$FLAIR_nii'); quit"
    cp -fu $OUT_DIR/ples_${ALGORITHM}_m${1}_ses-${SESSION}_FLAIR.nii $ALGORITHM_OUT_DIR ; rm $OUT_DIR/ples_${ALGORITHM}_m${1}_ses-${SESSION}_FLAIR.nii
    cp -fur $OUT_DIR/LST_${ALGORITHM}_m${1}_ses-${SESSION}_FLAIR $ALGORITHM_OUT_DIR/ ; rm -r $OUT_DIR/LST_${ALGORITHM}_m${1}_ses-${SESSION}_FLAIR
    cp -fu $OUT_DIR/LST_${ALGORITHM}_m${1}_ses-${SESSION}_FLAIR.mat $ALGORITHM_OUT_DIR/ ; rm $OUT_DIR/LST_${ALGORITHM}_m${1}_ses-${SESSION}_FLAIR.mat
    cp -fu $OUT_DIR/report_LST_${ALGORITHM}* $ALGORITHM_OUT_DIR/ ; rm $OUT_DIR/report_LST_${ALGORITHM}* 
    cp -fu $OUT_DIR/m${1}_ses-${SESSION}_FLAIR.nii $ALGORITHM_OUT_DIR/ ; rm $OUT_DIR/m${1}_ses-${SESSION}_FLAIR.nii
    rm -r $OUT_DIR/LST_tmp_*
    $singularity_freesurfer /bin/bash -c "$CMD_CONVERT_SEG"
    rm $SEGMENTATION_nii
    $singularity_fsl /bin/bash -c "$CMD_MASKING_GAME; $CMD_THRESH_SEGMENTATION"


elif [ $ALGORITHM == "samseg" ]; then

    # Define inputs
    FLAIR=$DATA_DIR/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz
    T1_IN_FLAIR=/work/fatx405/projects/CSI_WMH_EVAL/$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii.gz
    BRAINWITHOUTRIBBON_MASK_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brainwithoutribbon_mask.nii.gz

    # Define outputs 
    SEGMENTED_BRAIN=$ALGORITHM_OUT_DIR/seg.mgz
    SEGMENTED_BRAIN_NIIGZ=$ALGORITHM_OUT_DIR/seg.nii.gz
    SEGMENTATION=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_mask.nii.gz
    SEGMENTATION_FILTERED=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz

    # Define commands
    CMD_SAMSEG="run_samseg --input $FLAIR $T1_IN_FLAIR --output $ALGORITHM_OUT_DIR"
    CMD_CONVERT_SEG="mri_convert $SEGMENTED_BRAIN $SEGMENTED_BRAIN_NIIGZ"
    CMD_EXTRACT_WMH="fslmaths $SEGMENTED_BRAIN_NIIGZ -uthr 77 -thr 77 -bin $SEGMENTATION"
    CMD_MASKING_GAME="fslmaths $SEGMENTATION -mul $BRAINWITHOUTRIBBON_MASK_FLAIR $SEGMENTATION_FILTERED"

    # Execute
    $singularity_freesurfer /bin/bash -c "$CMD_SAMSEG; $CMD_CONVERT_SEG"
    $singularity_fsl /bin/bash -c "$CMD_EXTRACT_WMH; $CMD_MASKING_GAME"

fi