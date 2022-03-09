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
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_fsl" 

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


    # create a list with subjects which are part of the classifier / training
    MAN_SEGMENTATION_DIR=$PROJ_DIR/../CSI_WMH_MASKS_HCHS_pseud/HCHS/
    LIST_TRAINING=$DATA_DIR/$PIPELINE/derivatives/sublist_segmentation_training.csv
    [ -f $LIST_TRAINING ] && rm $LIST_TRAINING
    for sub in $(ls $MAN_SEGMENTATION_DIR/sub-* -d | xargs -n 1 basename); do echo $sub >> $LIST_TRAINING; done
    [[ -n "${LISTTRAINING[$1]}" ]] && SUB_GROUP=training || SUB_GROUP=testing


    if [ $SUB_GROUP == training ]; then
        # the actual training with the creation of the classifier is already run

        # as determined with wmh_determine_thresh.sh
        threshold=0.8

        # Define inputs
        BRAINWITHOUTRIBBON_MASK_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brainwithoutribbon_mask.nii.gz

        # Define outputs
        SEGMENTATION_raw=$DATA_DIR/$PIPELINE/sourcedata/BIANCA_training/pseudomized_training_masks/${1}_bianca_output.nii.gz
        SEGMENTATION_sized=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-${ALGORITHM}_mask_sized.nii.gz
        SEGMENTATION=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
        SEGMENTATION_FILTERED=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz

        # Define commands
        CMD_threshold_segmentation="cluster --in=$SEGMENTATION_raw --thresh=$threshold --osize=$SEGMENTATION_sized"
        CMD_thresholdcluster_segmentation="fslmaths $SEGMENTATION_sized -thr 3 -bin $SEGMENTATION"
        CMD_MASKING_GAME="fslmaths $SEGMENTATION -mul $BRAINWITHOUTRIBBON_MASK_FLAIR $SEGMENTATION_FILTERED"

        # Execute
        $singularity_fsl /bin/bash -c "$CMD_threshold_segmentation; $CMD_thresholdcluster_segmentation; $CMD_MASKING_GAME"


    elif [ $SUB_GROUP == testing ]; then

        # as determined with wmh_determine_thresh.sh
        threshold=0.8

        # Define inputs 
        FLAIR_BRAIN=$OUT_DIR/${1}_ses-${SESSION}_desc-brain_FLAIR.nii.gz
        T1_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii.gz
        CLASSIFIER=$DATA_DIR/$PIPELINE/sourcedata/classifierdata
        # the classifier is trained on N=100 HCHS subjects.
        # Input for the training was a brainextracted FLAIR, a T1 in FLAIR space, a mat file with the FLAIR-2-MNI warp and manually segmented WMH masks.
        # Manually segmented WMH masks contain overlap of segmentation of Marvin and Carola.
        # to have full documentation: the following command with the specified flags was executed for the training:
        # bianca --singlefile=masterfile.txt --labelfeaturenum=4 --brainmaskfeaturenum=1 --querysubjectnum=1 --trainingnums=all --featuresubset=1,2 --matfeaturenum=3 \
        # --trainingpts=2000 --nonlespts=10000 --selectpts=noborder -o sub-00012_bianca_output -v --saveclassifierdata=$SCRIPT_DIR/classifierdata
        # the input for the bianca segmentation is from the training data in case the subject was part of the training dataset
        BRAINWITHOUTRIBBON_MASK_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brainwithoutribbon_mask.nii.gz
        MNI_TEMPLATE=$ENV_DIR/standard/tpl-MNI152NLin2009cAsym_res-01_desc-brain_T1w.nii.gz

        # Define outputs
        FLAIR_IN_MNI_FLIRT=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-MNI_desc-brain_FLAIR.nii.gz
        FLAIR_TO_MNI_WARP_FLIRT=$OUT_DIR/${1}_ses-${SESSION}_from-FLAIR_to-MNI_flirtwarp.txt
        SEGMENTATION_raw=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-${ALGORITHM}_mask_raw.nii.gz
        SEGMENTATION_sized=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-${ALGORITHM}_mask_sized.nii.gz
        SEGMENTATION=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
        SEGMENTATION_FILTERED=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz


        # Write masterfile
        MASTERFILE=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_masterfile.txt
        echo "$FLAIR_BRAIN $T1_IN_FLAIR $FLAIR_TO_MNI_WARP_FLIRT" > $MASTERFILE
        
        # Define commands    
        CMD_FLIRT_FLAIR_TO_MNI="flirt -in $FLAIR_BRAIN -ref $MNI_TEMPLATE -out $FLAIR_IN_MNI_FLIRT -omat $FLAIR_TO_MNI_WARP_FLIRT"
        CMD_BIANCA="bianca --singlefile=$MASTERFILE --brainmaskfeaturenum=1 --querysubjectnum=1 --featuresubset=1,2 --matfeaturenum=3 -o $SEGMENTATION_raw -v --loadclassifierdata=$CLASSIFIER"
        CMD_threshold_segmentation="cluster --in=$SEGMENTATION_raw --thresh=$threshold --osize=$SEGMENTATION_sized"
        CMD_thresholdcluster_segmentation="fslmaths $SEGMENTATION_sized -thr 3 -bin $SEGMENTATION"
        CMD_MASKING_GAME="fslmaths $SEGMENTATION -mul $BRAINWITHOUTRIBBON_MASK_FLAIR $SEGMENTATION_FILTERED"
        
        # Execute
        $singularity_fsl /bin/bash -c "$CMD_FLIRT_FLAIR_TO_MNI; $CMD_BIANCA; $CMD_threshold_segmentation; $CMD_thresholdcluster_segmentation; $CMD_MASKING_GAME"


    fi

    
elif [ $ALGORITHM == "LOCATE" ]; then

    # it is best to run this locally. It takes more than maximum batch time to run
    source /work/bax0929/set_envs/fsl
    module load matlab

    LOCATE_installation=$ENV_DIR/LOCATE-BIANCA

    LOCATE_working_dir=$DATA_DIR/$PIPELINE/MyLOCATE
    [ ! -d $LOCATE_working_dir ] && mkdir -p $LOCATE_working_dir
    LOCATE_training_dir=$LOCATE_working_dir/LOO_training_imgs
    [ ! -d $LOCATE_training_dir ] && mkdir -p $LOCATE_training_dir
    export $LOCATE_training_dir
    LOCATE_testing_dir=$LOCATE_working_dir/LOO_testing_imgs
    [ ! -d $LOCATE_testing_dir ] && mkdir -p $LOCATE_testing_dir
    export $LOCATE_testing_dir

    LIST_TRAINING=$DATA_DIR/$PIPELINE/derivatives/sublist_segmentation_training.csv
    [ -f $LIST_TRAINING ] && rm $LIST_TRAINING
    for sub in $(ls $MAN_SEGMENTATION_DIR/sub-* -d | xargs -n 1 basename); do echo $sub >> $LIST_TRAINING; done
    [[ -n "${LISTTRAINING[$1]}" ]] && SUB_GROUP=training || SUB_GROUP=testing

    if [ $SUB_GROUP == training ] ; then

        for sub in $(ls $DATA_DIR/$PIPELINE/sub-* -d | xargs -n 1 basename); do

            OUT_DIR=$DATA_DIR/$PIPELINE/$sub/ses-${SESSION}/anat/

            # Define inputs
            MAN_SEGMENTATION_DIR=$PROJ_DIR/../CSI_WMH_MASKS_HCHS_pseud/HCHS/
            FLAIR_BRAIN=$OUT_DIR/${sub}_ses-${SESSION}_desc-brain_FLAIR.nii.gz
            FLAIR_LOCATE=$LOCATE_training_dir/${sub}_feature_FLAIR.nii.gz 
            T1_IN_FLAIR=$OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii.gz
            T1_LOCATE=$LOCATE_training_dir/${sub}_feature_T1.nii.gz
            SEGMENTATION_MAN=$MAN_SEGMENTATION_DIR/$sub/anat/${sub}_DC_FLAIR_label3.nii.gz
            MANUAL_MASK_LOCATE=$LOCATE_training_dir/${sub}_manualmask.nii.gz
            DISTANCEMAP=$OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_distancemap.nii.gz
            DISTANCEMAP_LOCATE=$LOCATE_training_dir/${sub}_ventdistmap.nii.gz
            SEGMENTATION_raw=$DATA_DIR/$PIPELINE/sourcedata/BIANCA_training/pseudomized_training_masks/${sub}_bianca_output.nii.gz
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

        done

    if [ $SUB_GROUP == testing ] && [ $LOCATE_LEVEL == testing ]; then

        for sub in $(ls $DATA_DIR/$PIPELINE/sub-* -d | xargs -n 1 basename); do

            OUT_DIR=$DATA_DIR/$PIPELINE/$sub/ses-${SESSION}/anat/

            # Define inputs
            FLAIR_BRAIN=$OUT_DIR/${sub}_ses-${SESSION}_desc-brain_FLAIR.nii.gz
            FLAIR_LOCATE=$LOCATE_testing_dir/${sub}_feature_FLAIR.nii.gz 
            T1_IN_FLAIR=$OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii.gz
            T1_LOCATE=$LOCATE_testing_dir/${sub}_feature_T1.nii.gz
            DISTANCEMAP=$OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_distancemap.nii.gz
            DISTANCEMAP_LOCATE=$LOCATE_testing_dir/${sub}_ventdistmap.nii.gz
            SEGMENTATION_raw=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-${ALGORITHM}_mask_raw.nii.gz
            SEGMENTATION_raw_LOCATE=$LOCATE_testing_dir/${sub}_BIANCA_LPM.nii.gz
            T1_MASK_IN_FLAIR=$OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-brain_mask.nii.gz
            BRAINMASK_LOCATE=$LOCATE_testing_dir/${sub}_brainmask.nii.gz
            BIANCAMASK_LOCATE=$LOCATE_testing_dir/${sub}_biancamask.nii.gz

            if [ -f $FLAIR_BRAIN ] && [ -f $T1_IN_FLAIR ] && [ -f $DISTANCEMAP ] && [ -f $SEGMENTATION_raw ] && [ -f $T1_MASK_IN_FLAIR ]; then
            
                cp $FLAIR_BRAIN $FLAIR_LOCATE
                cp $T1_IN_FLAIR $T1_LOCATE
                cp $DISTANCEMAP $DISTANCEMAP_LOCATE
                cp $SEGMENTATION_raw $SEGMENTATION_raw_LOCATE
                cp $T1_MASK_IN_FLAIR $BRAINMASK_LOCATE
                cp $T1_MASK_IN_FLAIR $BIANCAMASK_LOCATE

            # else we will not copy any of the files into the LOCATE directory because LOCATE cannot handle incomplete data of subjects, throws an error and stops

            fi

        done

    fi


    # LOCATE can run in 3 ways:
        # 1) train and test the LOCATE model on data with manual mask available (with leave one out validation). Then work with LOO directory
        # 2) train the LOCATE model on data with manual mask available. Then work with training directory
        # 3) test the LOCATE model on data without manual mask, then work with apply directory

    # For 1)
    [ $LOCATE_LEVEL == validate ] && matlab -nosplash -nodesktop -nojvm -batch "addpath(genpath('$ENV_DIR/LOCATE-BIANCA')); LOCATE_LOO_testing('$LOCATE_training_dir'); quit"
    SEGMENTATION=$ALGORITHM_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz

    # For 2)
    [ $LOCATE_LEVEL == training ] && matlab -nosplash -nodesktop -nojvm -batch "addpath(genpath('$ENV_DIR/LOCATE-BIANCA')); LOCATE_training('$LOCATE_training_dir'); quit"

    # For 3)
    [ $LOCATE_LEVEL == testing ] && matlab -nosplash -nodesktop -nojvm -batch "addpath(genpath('$ENV_DIR/LOCATE-BIANCA')); LOCATE_testing('$LOCATE_testing_dir', '$LOCATE_training_dir'); quit"


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

