#!/usr/bin/env bash

###################################################################################################################
# Structural imaging analysis with Computational Anatomy Toolbox 12                                               #
# https://github.com/jhuguetn/cat12-docker                                                                        #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - none (optional 'wmh' for lesion filling -> change paths accordingly)                                    #
#   [container]                                                                                                   #
#       - mrtrix3-3.0.4.sif (mrconvert for nii.gz-->.nii; unexpected things occur when using hpc gunzip on nii.gz)#
#       - cat12-12.9                                                                                              #
#                                                                                                                 #
# Note: configuration files for batch jobs are located in $CODE_DIR/pipelines/cat12. These need to be adapted     #
#       to your needs                                                                                             #
###################################################################################################################

# Get verbose outputs
set -x

# Define subject specific temporary directory on $SCRATCH_DIR
export TMP_DIR=$SCRATCH_DIR/$1/tmp/;   [ ! -d $TMP_DIR ] && mkdir -p $TMP_DIR
TMP_IN=$TMP_DIR/input;                 [ ! -d $TMP_IN ] && mkdir -p $TMP_IN
TMP_OUT=$TMP_DIR/output;               [ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT

###################################################################################################################

# Define containers
#########################

container_mrtrix3=mrtrix3-3.0.4.sif      
container_cat12=cat12-12.9 # only sandbox works here

apptainer_mrtrix3="apptainer run --cleanenv\
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_mrtrix3" 

apptainer_cat12="apptainer run --cleanenv --userns --no-home \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $BEEGFS:/home \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_cat12" 

CAT_CODE_DIR=$CODE_DIR/pipelines/cat12/

###################################################################################################################

if [ $ANALYSIS_LEVEL == "subject" ]; then

    pushd $TMP_OUT
    
    ###################################################################################################################
    ##### STEP 1: Segmentation
    ###################################################################################################################

    # Define inputs
    ###############

    T1_orig=$DATA_DIR/raw_bids/$1/ses-$SESSION/anat/${1}_ses-${SESSION}_T1w.nii.gz
    T1_NII=${1}_ses-${SESSION}.nii

    # Define commands
    #################

    CMD_CONVERT="mrconvert $T1_orig /tmp_out/$T1_NII"
    CMD_SEGMENT="-b $CAT_CODE_DIR/cat_standalone_segment.m /tmp_out/$T1_NII"

    # Execute commands
    ##################
    
    $apptainer_mrtrix3 $CMD_CONVERT
    $apptainer_cat12 $CMD_SEGMENT

    ###################################################################################################################
    ##### STEP 2: Smoothing
    ###################################################################################################################

    # Define inputs
    ###############

    GM_SEGMENTS=mri/mwp1${1}_ses-${SESSION}.nii

    # Define command
    #################

    CMD_SMOOTH="-b $CAT_CODE_DIR/cat_standalone_smooth.m /tmp_out/$GM_SEGMENTS"

    # Execute command
    #################

    $apptainer_cat12 $CMD_SMOOTH

    ###################################################################################################################
    ##### STEP 3: Resample and smooth surface data
    ###################################################################################################################

    # Define input
    ##############
    LH_THICKNESS=surf/lh.thickness.${1}_ses-${SESSION}

    # Define commands
    #################

    CMD_RESAMPLE_LH_CONTE="-b $CAT_CODE_DIR/cat_standalone_resample.m -a1 "12" -a2 "1" /tmp_out/$LH_THICKNESS"
    CMD_RESAMPLE_LH_FS="-b $CAT_CODE_DIR/cat_standalone_resample.m -a1 "12" -a2 "0" /tmp_out/$LH_THICKNESS"

    # Execute commands
    ##################

    $apptainer_cat12 $CMD_RESAMPLE_LH_CONTE
    $apptainer_cat12 $CMD_RESAMPLE_LH_FS

    ###################################################################################################################
    ##### STEP 4: Get image quality rating and total intracranial volume
    ###################################################################################################################

    # Define input
    ##############

    REPORT=report/cat_${1}_ses-${SESSION}.xml
    
    # Define commands
    #################

    CMD_QA_IQR="-b $CAT_CODE_DIR/cat_standalone_get_IQR.m /tmp_out/$REPORT"
    CMD_TIV="-b $CAT_CODE_DIR/cat_standalone_get_TIV.m /tmp_out/$REPORT"

    # Execute commands
    ##################

    $apptainer_cat12 $CMD_QA_IQR
    $apptainer_cat12 $CMD_TIV

    ###################################################################################################################
    ##### STEP 5: Save data to subject level output directory
    ###################################################################################################################

    OUT_DIR=$DATA_DIR/cat12/$1/ses-$SESSION/anat; [ ! -d $OUT_DIR ] && mkdir -p $OUT_DIR
    rm -rf $TMP_OUT/*.nii  
    cp -ruvf $TMP_OUT/* $OUT_DIR
    mv $OUT_DIR/segmentation_volumes.tsv $OUT_DIR/report/${1}_ses-${SESSION}_segmentation_volumes.tsv
    mv $OUT_DIR/IQR.txt $OUT_DIR/report/${1}_ses-${SESSION}_IQR.txt

    popd

elif [ $ANALYSIS_LEVEL == "group" ]; then

    pushd $TMP_OUT

    ###################################################################################################################
    ##### STEP 6: Quality assessment
    ###################################################################################################################

    # Define output
    ###############
    
    DER_DIR=$DATA_DIR/cat12/derivatives/ses-$SESSION/anat; [ ! -d $DER_DIR ] && mkdir -p $DER_DIR
    TSV_IQR=$DER_DIR/group_IQR.tsv
    TSV_TIV=$DER_DIR/group_segmentation_volumes.tsv
    find $DATA_DIR/cat12/sub*/ses-$SESSION/anat/surf/ -name "s12.mesh.thickness.resampled_32k.*" > file_list.txt

    # Define commands
    #################
    
    CMD_QA_VOLUME="-b $CAT_CODE_DIR/cat_standalone_get_quality_volumes.m $DATA_DIR/cat12/sub*/ses-$SESSION/anat/mri/mwp1*.nii"
    CMD_QA_SURFACE="-b $CAT_CODE_DIR/cat_standalone_get_quality_surfaces.m"

    # Execute commands
    ##################

    $apptainer_cat12 $CMD_QA_VOLUME
    $apptainer_cat12 $CMD_QA_SURFACE

    echo -e "sub_id\tIQR" > $TSV_IQR
    echo -e "sub_id\ttotal\tgm\twm\tcsf\twmh" > $TSV_TIV
    sublist=${subj_batch_array[@]}
    
    for sub in $sublist; do
        iqr=`cat $DATA_DIR/cat12/$sub/ses-$SESSION/anat/report/${sub}_ses-${SESSION}_IQR.txt`
        echo "${sub}\t${iqr}" >> $TSV_IQR
        cat $DATA_DIR/cat12/$sub/ses-$SESSION/anat/report/${sub}_ses-${SESSION}_segmentation_volumes.tsv >> $TSV_TIV

    done 

    ###################################################################################################################
    ##### STEP 7: Estimate mean volumes and mean surface values per ROI
    ###################################################################################################################

    # Define commands
    #################

    CMD_ROI="-b $CAT_CODE_DIR/cat_standalone_get_ROI_values.m $DATA_DIR/cat12/sub*/ses-$SESSION/anat/label/catROI*.xml -a1 "'ROI'""

    # Execute commands
    ##################

    $apptainer_cat12 $CMD_ROI

    ###################################################################################################################
    ##### STEP 8 Save data to derivatives directory
    ###################################################################################################################
    
    cp -ruvf $TMP_OUT/* $DER_DIR

    popd
    
fi