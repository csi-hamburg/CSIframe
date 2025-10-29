#######################################################################################################################
#                               Pipeline under construction. Please check back later.                                 #
#######################################################################################################################

# Get verbose outputs
set -x
ulimit -c 0

for sub in $sublist; do  

    # Define subject specific temporary directory on $SCRATCH_DIR
    export TMP_DIR=$SCRATCH_DIR/$sub/tmp/;   [ ! -d $TMP_DIR ] && mkdir -p $TMP_DIR
    TMP_IN=$TMP_DIR/input;                 [ ! -d $TMP_IN ] && mkdir -p $TMP_IN
    TMP_OUT=$TMP_DIR/output;               [ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT

    ###################################################################################################################
    # Pipeline-specific environment
    ##################################

    # Singularity container version and command
    container_freesurfer=freesurfer-7.4.1.sif
    singularity_freesurfer="singularity run --cleanenv --userns \
        -B $PROJ_DIR \
        -B $(readlink -f $ENV_DIR) \
        -B $TMP_DIR/:/tmp \
        -B $TMP_IN:/tmp_in \
        -B $TMP_OUT:/tmp_out \
        $ENV_DIR/$container_freesurfer" 

    container_fsl=fsl-6.0.7.13.sif
    singularity_fsl="singularity run --cleanenv --userns \
        -B $PROJ_DIR \
        -B $(readlink -f $ENV_DIR) \
        -B $TMP_DIR/:/tmp \
        -B $TMP_IN:/tmp_in \
        -B $TMP_OUT:/tmp_out \
        $ENV_DIR/$container_fsl" 

    container_ants=ants-2.5.4.sif
    apptainer_ants="apptainer run --cleanenv --userns \
        -B $PROJ_DIR \
        -B $(readlink -f $ENV_DIR) \
        -B $TMP_DIR/:/tmp \
        -B $TMP_IN \
        -B $TMP_OUT \
        $ENV_DIR/$container_ants"

    # Set output directories
    OUT_DIR=$DATA_DIR/$PIPELINE/$sub/ses-${SESSION}/anat/
    [ ! -d $OUT_DIR ] && mkdir -p $OUT_DIR
    ALGORITHM_OUT_DIR=$OUT_DIR/$ALGORITHM/
    DERIVATIVE_dir=$DATA_DIR/$PIPELINE/derivatives
    [ ! -d $DERIVATIVE_dir ] && mkdir -p $DERIVATIVE_dir

    # To make I/O more efficient read/write outputs from/to $SCRATCH
    [ -d $TMP_IN ] && cp -rf $BIDS_DIR/$sub $BIDS_DIR/dataset_description.json $TMP_IN 
    [ -d $TMP_OUT ] && mkdir -p $TMP_OUT/wmh $TMP_OUT/wmh
    
    ###############################################################################################################################################################
    # Register segmentation into T1-acpc-MNI space (the space in which the connectome is, created by qsiprep)
    ###############################################################################################################################################################
    
    # Define inputs
    T1acpc=$DATA_DIR/qsiprep/$sub/anat/${sub}_desc-preproc_T1w.nii.gz
    T1_IN_MNI=$DATA_DIR/fmriprep/$sub/ses-${SESSION}/anat/${sub}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-preproc_T1w.nii.gz
    SEGMENTATION_MNI=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz

    # Define outputs
    FROM_T1acpc_2_MNI_warp_pre=$OUT_DIR/${sub}_ses-${SESSION}_from-T1acpc_to-MNI_
    FROM_T1acpc_2_MNI_warp=$OUT_DIR/${sub}_ses-${SESSION}_from-T1acpc_to-MNI_Composite.h5
    FROM_MNI_2_T1acpc_warp=$OUT_DIR/${sub}_ses-${SESSION}_from-T1acpc_to-MNI_InverseComposite.h5
    T1acpc_in_MNI=$OUT_DIR/${sub}_space-MNI152NLin2009cAsym_desc-acpc_desc-preproc_T1w.nii.gz
    SEGMENTATION_ACPC=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-T1acpc_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz

    # Define commands
    CMD_REGISTER_T1acpc2MNI="antsRegistration \
        --collapse-output-transforms 1 \
        --dimensionality 3 \
        --float 1 \
        --initial-moving-transform [ $T1_IN_MNI, $T1acpc, 1 ] \
        --initialize-transforms-per-stage 0 \
        --interpolation LanczosWindowedSinc \
        --output [ $FROM_T1acpc_2_MNI_warp_pre, $T1acpc_in_MNI ] \
        --transform Rigid[ 0.05 ] \
        --metric Mattes[ $T1_IN_MNI, $T1acpc, 1, 56, Regular, 0.25 ] \
        --convergence [ 100x100, 1e-06, 20 ] \
        --smoothing-sigmas 2.0x1.0vox \
        --shrink-factors 2x1 \
        --use-estimate-learning-rate-once 1 \
        --use-histogram-matching 1 \
        --transform Affine[ 0.08 ] \
        --metric Mattes[ $T1_IN_MNI, $T1acpc, 1, 56, Regular, 0.25 ] \
        --convergence [ 100x100, 1e-06, 20 ] \
        --smoothing-sigmas 1.0x0.0vox \
        --shrink-factors 2x1 \
        --use-estimate-learning-rate-once 1 \
        --use-histogram-matching 1 \
        --transform SyN[ 0.1, 3.0, 0.0 ] \
        --metric CC[ $T1_IN_MNI, $T1acpc, 1, 4, None, 1 ] \
        --convergence [ 100x70x50x20, 1e-06, 10 ] \
        --smoothing-sigmas 3.0x2.0x1.0x0.0vox \
        --shrink-factors 8x4x2x1 \
        --use-estimate-learning-rate-once 1 \
        --use-histogram-matching 1 \
        --winsorize-image-intensities [ 0.005, 0.995 ] \
        --write-composite-transform 1
        "
    CMD_REGISTER_WMH_2_ACPC="antsApplyTransforms -d 3 -i $SEGMENTATION_MNI -r $T1acpc -o $SEGMENTATION_ACPC -t $FROM_MNI_2_T1acpc_warp"

    # Execute
    [ ! -f $T1acpc_in_MNI ] && $singularity_mrtrix $CMD_REGISTER_T1acpc2MNI
    $singularity_mrtrix $CMD_REGISTER_WMH_2_ACPC

    ###############################################################################################################################################################
    # Create disconnectome
    ###############################################################################################################################################################
    module load aws-cli
    
    # Define inputs
    TRACKING_FILE=${sub}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_space-T1w_desc-tracks_ifod2.tck
    FODS=${sub}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_space-T1w_desc-siftweights_ifod2.csv
    SCHAEFER_PARC_1=${sub}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_space-T1w_desc-schaefer100x7_atlas.mif.gz
    SCHAEFER_PARC_2=${sub}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_space-T1w_desc-schaefer200x7_atlas.mif.gz
    SCHAEFER_PARC_3=${sub}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_space-T1w_desc-schaefer400x7_atlas.mif.gz
    SEGMENTATION_ACPC=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_space-T1acpc_desc-masked_desc-wmh_desc-${ALGORITHM}_mask.nii.gz

    # Define outputs
    TRACKING_FILE_T1=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_acq-AP_space-T1w_desc-preproc_space-T1w_desc-WMHconnectome_ifod2.tck
    OUTPUT_CSV_1_sift=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-schaefer100x7_desc-WMH_desc-sift_connectome.csv
    ASSIGNMENTS_1_sift=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-schaefer100x7_desc-WMH_desc-sift_assignments.csv
    OUTPUT_CSV_2_sift=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-schaefer200x7_desc-WMH_desc-sift_connectome.csv
    ASSIGNMENTS_2_sift=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-schaefer200x7_desc-WMH_desc-sift_assignments.csv
    OUTPUT_CSV_3_sift=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-schaefer400x7_desc-WMH_desc-sift_connectome.csv
    ASSIGNMENTS_3_sift=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-schaefer400x7_desc-WMH_desc-sift_assignments.csv
    OUTPUT_CSV_1=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-schaefer100x7_desc-WMH_connectome.csv
    ASSIGNMENTS_1=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-schaefer100x7_desc-WMH_assignments.csv
    OUTPUT_CSV_2=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-schaefer200x7_desc-WMH_connectome.csv
    ASSIGNMENTS_2=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-schaefer200x7_desc-WMH_assignments.csv
    OUTPUT_CSV_3=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-schaefer400x7_desc-WMH_connectome.csv
    ASSIGNMENTS_3=$ALGORITHM_OUT_DIR/${sub}_ses-${SESSION}_desc-schaefer400x7_desc-WMH_assignments.csv

    # Define commands
    CMD_TCKEDIT="tckedit $OUT_DIR/$TRACKING_FILE $TRACKING_FILE_T1 -exclude $SEGMENTATION_ACPC -inverse -force"
    CMD_CONNECTOME_1_sift="tck2connectome $TRACKING_FILE_T1 $OUT_DIR/$SCHAEFER_PARC_1 $OUTPUT_CSV_1_sift -tck_weights_in $OUT_DIR/$FODS -out_assignments $ASSIGNMENTS_1_sift -force"
    CMD_CONNECTOME_2_sift="tck2connectome $TRACKING_FILE_T1 $OUT_DIR/$SCHAEFER_PARC_2 $OUTPUT_CSV_2_sift -tck_weights_in $OUT_DIR/$FODS -out_assignments $ASSIGNMENTS_2_sift -force"
    CMD_CONNECTOME_3_sift="tck2connectome $TRACKING_FILE_T1 $OUT_DIR/$SCHAEFER_PARC_3 $OUTPUT_CSV_3_sift -tck_weights_in $OUT_DIR/$FODS -out_assignments $ASSIGNMENTS_3_sift -force"
    CMD_CONNECTOME_1="tck2connectome $TRACKING_FILE_T1 $OUT_DIR/$SCHAEFER_PARC_1 $OUTPUT_CSV_1 -out_assignments $ASSIGNMENTS_1 -force"
    CMD_CONNECTOME_2="tck2connectome $TRACKING_FILE_T1 $OUT_DIR/$SCHAEFER_PARC_2 $OUTPUT_CSV_2 -out_assignments $ASSIGNMENTS_2 -force"
    CMD_CONNECTOME_3="tck2connectome $TRACKING_FILE_T1 $OUT_DIR/$SCHAEFER_PARC_3 $OUTPUT_CSV_3 -out_assignments $ASSIGNMENTS_3 -force"

    # Execute
    aws s3 cp --endpoint-url https://s3-uhh.lzs.uni-hamburg.de s3://uke-csi-hchs/qsirecon/${sub}/ses-${SESSION}/dwi/$TRACKING_FILE $OUT_DIR/
    aws s3 cp --endpoint-url https://s3-uhh.lzs.uni-hamburg.de s3://uke-csi-hchs/qsirecon/${sub}/ses-${SESSION}/dwi/$FODS $OUT_DIR/
    aws s3 cp --endpoint-url https://s3-uhh.lzs.uni-hamburg.de s3://uke-csi-hchs/qsirecon/${sub}/ses-${SESSION}/dwi/$SCHAEFER_PARC_1 $OUT_DIR/
    aws s3 cp --endpoint-url https://s3-uhh.lzs.uni-hamburg.de s3://uke-csi-hchs/qsirecon/${sub}/ses-${SESSION}/dwi/$SCHAEFER_PARC_2 $OUT_DIR/
    aws s3 cp --endpoint-url https://s3-uhh.lzs.uni-hamburg.de s3://uke-csi-hchs/qsirecon/${sub}/ses-${SESSION}/dwi/$SCHAEFER_PARC_3 $OUT_DIR/

    [ ! -f $ASSIGNMENTS_3_sift ] && $singularity_mrtrix /bin/bash -c "$CMD_TCKEDIT; $CMD_CONNECTOME_1_sift; $CMD_CONNECTOME_2_sift; $CMD_CONNECTOME_3_sift; $CMD_CONNECTOME_1; $CMD_CONNECTOME_2; $CMD_CONNECTOME_3"

    rm $OUT_DIR/$TRACKING_FILE
    rm $OUT_DIR/$FODS
    rm $OUT_DIR/$SCHAEFER_PARC_1
    rm $OUT_DIR/$SCHAEFER_PARC_2
    rm $OUT_DIR/$SCHAEFER_PARC_3

done