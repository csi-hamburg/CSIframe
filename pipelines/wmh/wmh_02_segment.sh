#!/bin/bash

# SET VARIABLES FOR CONTAINER TO BE USED
FSL_VERSION=fsl-6.0.3
FREESURFER_VERSION=freesurfer-7.1.1
MRTRIX_VERSION=mrtrix3-3.0.2
###############################################################################################################################################################
FSL_CONTAINER=$ENV_DIR/$FSL_VERSION
FREESURFER_CONTAINER=$ENV_DIR/$FREESURFER_VERSION
MRTRIX_CONTAINER=$ENV_DIR/$MRTRIX_VERSION
ANTSRNET_CONTAINER=$ENV_DIR/antsrnet
###############################################################################################################################################################
singularity="singularity run --cleanenv --userns -B $(readlink -f $ENV_DIR) -B $PROJ_DIR -B $TMP_DIR/:/tmp"
###############################################################################################################################################################

# Set output directories
OUT_DIR=data/$PIPELINE/$1/ses-${SESSION}/anat/


[ $BIASCORR == y ] && ALGORITHM_OUT_DIR=$OUT_DIR/${ALGORITHM}bias/
[ $BIASCORR == n ] && ALGORITHM_OUT_DIR=$OUT_DIR/${ALGORITHM}/

[ ! -d $ALGORITHM_OUT_DIR ] && mkdir -p $ALGORITHM_OUT_DIR







if [ $ALGORITHM == "antsrnet" ]; then

    # Define inputs
    [ $BIASCORR == n ] && FLAIR=data/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz
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
    CMD_THRESH_SEGMENTATION="fslmaths $SEGMENTATION_FILTERED -thr 0.05 $SEGMENTATION_THRESH"

    # Execute 
    $singularity $ANTSRNET_CONTAINER Rscript -e "flair<-antsImageRead('$FLAIR'); t1<-antsImageRead('$T1_IN_FLAIR'); probabilitymask<-sysuMediaWmhSegmentation(flair, t1); antsImageWrite(probabilitymask, '$SEGMENTATION')"
    $singularity $FSL_CONTAINER /bin/bash -c "$CMD_MASKING_GAME"
    $singularity $FSL_CONTAINER /bin/bash -c "$CMD_THRESH_SEGMENTATION"


elif [ $ALGORITHM == "bianca" ]; then

    # Define inputs 
    [ $BIASCORR == n ] && FLAIR_BRAIN=$OUT_DIR/${1}_ses-${SESSION}_desc-brain_FLAIR.nii.gz
    [ $BIASCORR == y ] && FLAIR_BRAIN=$OUT_DIR/${1}_ses-${SESSION}_desc-biascorr_desc-brain_FLAIR.nii.gz
    T1_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii.gz
    CLASSIFIER=data/wmh/sourcedata/classifierdata
    # the classifier is trained on N=100 HCHS subjects.
    # Input for the training was a brainextracted FLAIR, a T1 in FLAIR space, a mat file with the FLAIR-2-MNI warp and manually segmented WMH masks.
    # Manually segmented WMH masks contain overlap of segmentation of Marvin and Carola.
    # to have full documentation: the following command with the specified flags was executed for the training:
    # bianca --singlefile=masterfile.txt --labelfeaturenum=4 --brainmaskfeaturenum=1 --querysubjectnum=1 --trainingnums=all --featuresubset=1,2 --matfeaturenum=3 \
    # --trainingpts=2000 --nonlespts=10000 --selectpts=noborder -o sub-00012_bianca_output -v --saveclassifierdata=$SCRIPT_DIR/classifierdata
    # we now determined to choose a threshold of 0.9, which seems to be the best fit across subjects and is default on the bianca documentation website
    BRAINWITHOUTRIBBON_MASK_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brainwithoutribbon_mask.nii.gz
    MNI_TEMPLATE=$ENV_DIR/standard/tpl-MNI152NLin2009cAsym_res-01_desc-brain_T1w.nii.gz

    # Define outputs
    [ $BIASCORR == n ] && FLAIR_IN_MNI_FLIRT=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-MNI_desc-brain_FLAIR.nii.gz
    [ $BIASCORR == y ] && FLAIR_IN_MNI_FLIRT=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-MNI_desc-biascorr_desc-brain_FLAIR.nii.gz
    FLAIR_TO_MNI_WARP_FLIRT=$OUT_DIR/${1}_ses-${SESSION}_from-FLAIR_to-MNI_flirtwarp.txt
    [ $BIASCORR == n ] && SEGMENTATION_raw=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-${ALGORITHM}_mask_raw.nii.gz
    [ $BIASCORR == y ] && SEGMENTATION_raw=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-${ALGORITHM}bias_mask_raw.nii.gz
    [ $BIASCORR == n ] && SEGMENTATION_sized=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-${ALGORITHM}_mask_sized.nii.gz
    [ $BIASCORR == y ] && SEGMENTATION_sized=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-${ALGORITHM}bias_mask_sized.nii.gz
    [ $BIASCORR == n ] && SEGMENTATION=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
    [ $BIASCORR == y ] && SEGMENTATION=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-${ALGORITHM}bias_mask.nii.gz
    [ $BIASCORR == n ] && SEGMENTATION_FILTERED=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz
    [ $BIASCORR == y ] && SEGMENTATION_FILTERED=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}bias_mask.nii.gz

    # Write masterfile
    MASTERFILE=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_masterfile.txt
    echo "$FLAIR_BRAIN $T1_IN_FLAIR $FLAIR_TO_MNI_WARP_FLIRT" > $MASTERFILE

    # Define commands
    CMD_FLIRT_FLAIR_TO_MNI="flirt -in $FLAIR_BRAIN -ref $MNI_TEMPLATE -out $FLAIR_IN_MNI_FLIRT -omat $FLAIR_TO_MNI_WARP_FLIRT"
    CMD_BIANCA="bianca --singlefile=$MASTERFILE --brainmaskfeaturenum=1 --querysubjectnum=1 --featuresubset=1,2 --matfeaturenum=3 -o $SEGMENTATION_raw -v --loadclassifierdata=$CLASSIFIER"
    CMD_threshold_segmentation="cluster --in=$SEGMENTATION_raw --thresh=0.9 --osize=$SEGMENTATION_sized"
    CMD_thresholdcluster_segmentation="fslmaths $SEGMENTATION_sized -thr 3 -bin $SEGMENTATION"
    CMD_MASKING_GAME="fslmaths $SEGMENTATION -mul $BRAINWITHOUTRIBBON_MASK_FLAIR $SEGMENTATION_FILTERED"

    # Execute
    $singularity $FSL_CONTAINER /bin/bash -c "$CMD_FLIRT_FLAIR_TO_MNI; $CMD_BIANCA; $CMD_threshold_segmentation; $CMD_thresholdcluster_segmentation; $CMD_MASKING_GAME"

elif [ $ALGORITHM == "lga" ]; then

    module load matlab/2019b 

    # Define inputs 
    T1_IN_FLAIR_nii=/work/fatx405/projects/CSI_DEV/$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii
    FLAIR_nii=/work/fatx405/projects/CSI_DEV/$OUT_DIR/${1}_ses-${SESSION}_FLAIR.nii
    export T1_IN_FLAIR_nii
    export FLAIR_nii
    BRAINWITHOUTRIBBON_MASK_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brainwithoutribbon_mask.nii.gz

    # Define outputs
    SEGMENTATION_nii=$ALGORITHM_OUT_DIR/ples_${ALGORITHM}_0.1_rm${1}_ses-${SESSION}_FLAIR.nii
    SEGMENTATION=$ALGORITHM_OUT_DIR/ples_${ALGORITHM}_0.1_rm${1}_ses-${SESSION}_FLAIR.nii.gz
    SEGMENTATION_FILTERED=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz

    # Define commands
    CMD_CONVERT_SEG="mri_convert $SEGMENTATION_nii $SEGMENTATION"
    CMD_MASKING_GAME="fslmaths $SEGMENTATION -mul $BRAINWITHOUTRIBBON_MASK_FLAIR $SEGMENTATION_FILTERED"

    # Execute 
    matlab -nosplash -nodesktop -nojvm -batch "addpath(genpath('$ENV_DIR/spm12')); ps_LST_lga('$T1_IN_FLAIR_nii', '$FLAIR_nii', 0.1); quit"
    cp -fu $OUT_DIR/ples_${ALGORITHM}_0.1_rm${1}_ses-${SESSION}_FLAIR.nii $ALGORITHM_OUT_DIR/; rm $OUT_DIR/ples_${ALGORITHM}_0.1_rm${1}_ses-${SESSION}_FLAIR.nii
    cp -fur $OUT_DIR/LST_${ALGORITHM}_0.1_rm${1}_ses-${SESSION}_FLAIR $ALGORITHM_OUT_DIR/; rm -r $OUT_DIR/LST_${ALGORITHM}_0.1_rm${1}_ses-${SESSION}_FLAIR
    cp -fu $OUT_DIR/LST_${ALGORITHM}_rm${1}_ses-${SESSION}_FLAIR.mat $ALGORITHM_OUT_DIR/; rm $OUT_DIR/LST_${ALGORITHM}_rm${1}_ses-${SESSION}_FLAIR.mat
    cp -fu $OUT_DIR/report_LST_${ALGORITHM}* $ALGORITHM_OUT_DIR/; rm $OUT_DIR/report_LST_${ALGORITHM}*
    cp -fu $OUT_DIR/rm${1}_ses-${SESSION}_FLAIR.nii $ALGORITHM_OUT_DIR/; rm $OUT_DIR/rm${1}_ses-${SESSION}_FLAIR.nii
    $singularity $FREESURFER_CONTAINER /bin/bash -c "$CMD_CONVERT_SEG"
    $singularity $FSL_CONTAINER /bin/bash -c "$CMD_MASKING_GAME"
        

elif [ $ALGORITHM == "lpa" ]; then

    module load matlab/2019b

    # Define inputs 
    T1_IN_FLAIR_nii=/work/fatx405/projects/CSI_DEV/$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii
    FLAIR_nii=/work/fatx405/projects/CSI_DEV/$OUT_DIR/${1}_ses-${SESSION}_FLAIR.nii
    export T1_IN_FLAIR_nii
    export FLAIR_nii
    BRAINWITHOUTRIBBON_MASK_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brainwithoutribbon_mask.nii.gz

    # Define outputs
    SEGMENTATION_nii=$ALGORITHM_OUT_DIR/ples_${ALGORITHM}_mr${1}_ses-${SESSION}_FLAIR.nii
    SEGMENTATION=$ALGORITHM_OUT_DIR/ples_${ALGORITHM}_mr${1}_ses-${SESSION}_FLAIR.nii.gz
    SEGMENTATION_FILTERED=$ALGORITHM_OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz

    # Define commands
    CMD_CONVERT_SEG="mri_convert $SEGMENTATION_nii $SEGMENTATION"
    CMD_MASKING_GAME="fslmaths $SEGMENTATION -mul $BRAINWITHOUTRIBBON_MASK_FLAIR $SEGMENTATION_FILTERED"

    # Execute 
    matlab -nosplash -nodesktop -nojvm -batch "addpath(genpath('$ENV_DIR/spm12')); ps_LST_lpa('$FLAIR_nii', '$T1_IN_FLAIR_nii'); quit"
    cp -fu $OUT_DIR/ples_${ALGORITHM}_mr${1}_ses-${SESSION}_FLAIR.nii $ALGORITHM_OUT_DIR; rm $OUT_DIR/ples_${ALGORITHM}_mr${1}_ses-${SESSION}_FLAIR.nii
    cp -fur $OUT_DIR/LST_${ALGORITHM}_mr${1}_ses-${SESSION}_FLAIR $ALGORITHM_OUT_DIR/; rm -r $OUT_DIR/LST_${ALGORITHM}_mr${1}_ses-${SESSION}_FLAIR
    cp -fu $OUT_DIR/LST_${ALGORITHM}_mr${1}_ses-${SESSION}_FLAIR.mat $ALGORITHM_OUT_DIR/; rm $OUT_DIR/LST_${ALGORITHM}_mr${1}_ses-${SESSION}_FLAIR.mat
    cp -fu $OUT_DIR/report_LST_${ALGORITHM}* $ALGORITHM_OUT_DIR/; rm $OUT_DIR/report_LST_${ALGORITHM}* 
    cp -fu $OUT_DIR/mr${1}_ses-${SESSION}_FLAIR.nii $ALGORITHM_OUT_DIR/; rm $OUT_DIR/mr${1}_ses-${SESSION}_FLAIR.nii
    $singularity $FREESURFER_CONTAINER /bin/bash -c "$CMD_CONVERT_SEG"
    $singularity $FSL_CONTAINER /bin/bash -c "$CMD_MASKING_GAME"



elif [ $ALGORITHM == "samseg" ]; then

    # Define inputs
    FLAIR=data/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz
    T1_IN_FLAIR=/work/fatx405/projects/CSI_DEV/$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii.gz
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
    $singularity $FREESURFER_CONTAINER /bin/bash -c "$CMD_SAMSEG; $CMD_CONVERT_SEG"
    $singularity $FSL_CONTAINER /bin/bash -c "$CMD_EXTRACT_WMH; $CMD_MASKING_GAME"

fi

