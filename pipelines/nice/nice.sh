#!/bin/bash

###################################################################################################################
# Script for postprocessing NordicIce perfusion analysis output                                                   #
#       - brain extraction of FLAIR images                                                                        #
#       - registration of lesion segmentations from FLAIR space to DSC space                                      #
#       - creation of perfusion deficit masks (Tmax > 6s)                                                         #
#       - registration of pefusion images to standard spacet                                                      #
###################################################################################################################

###################################################################################################################
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - NordicIce perfusion analysis and bidsification of it's outputs                                          #
#   [containers]                                                                                                  #
#       - fsl-6.0.3                                                                                               #  
###################################################################################################################

# Get verbose outputs and avoid creation of core files
set -x
ulimit -c 0

# Define subject specific temporary directory on $SCRATCH_DIR
export TMP_DIR=$SCRATCH_DIR/$1/tmp/;   [ ! -d $TMP_DIR ] && mkdir -p $TMP_DIR
TMP_IN=$TMP_DIR/input;                 [ ! -d $TMP_IN ] && mkdir -p $TMP_IN
TMP_OUT=$TMP_DIR/output;               [ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT

###################################################################################################################

# Setup environment
###################

[ -z $SLURM_CPUS_PER_TASK ] && SLURM_CPUS_PER_TASK=8

module load singularity
container_fsl=fsl-6.0.3     
container_mrtrix3=mrtrix3-3.0.2
export SINGULARITYENV_MRTRIX_TMPFILE_DIR=$TMP_DIR

singularity_fsl="singularity run --cleanenv --userns \
    -B . \
    -B $PROJ_DIR \
    -B $SCRATCH_DIR:/tmp \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR \
    -B $TMP_IN \
    -B $TMP_OUT \
    $ENV_DIR/$container_fsl"

singularity_mrtrix3="singularity run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR \
    -B $TMP_IN \
    -B $TMP_OUT \
    $ENV_DIR/$container_mrtrix3" 


# Define pipeline output directory 
##################################

NICE_DIR=$DATA_DIR/nice
PERF_DIR=$NICE_DIR/$1/ses-$SESSION/perf
ANAT_DIR=$NICE_DIR/$1/ses-$SESSION/anat
DER_DIR=$NICE_DIR/derivatives/ses-$SESSION/perf

[ ! -d $DER_DIR ] && mkdir -p $DER_DIR
[ ! -d $ANAT_DIR ] && mkdir -p $ANAT_DIR 

###################################################################################################################
#                                           PART I: DSC/PERFUSION SPACE                                           #
###################################################################################################################


##############################################################
# Bias field correction and brain extraction of FLAIR images #
##############################################################

# Define input
##############

FLAIR=$BIDS_DIR/$1/ses-$SESSION/${1}_ses-${SESSION}_FLAIR.nii.gz

# Define output
###############

FLAIR_BIASCORR=$ANAT_DIR/${1}_ses-${SESSION}_desc-preproc_FLAIR.nii.gz
FLAIR_BRAIN=$ANAT_DIR/${1}_ses-${SESSION}_desc-preproc_desc-brain_FLAIR
BRAIN_MASK=$ANAT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brain_mask.nii.gz

# Define commands
#################

CMD_BIASCORR_FLAIR="N4BiasFieldCorrection -d 3 -i $FLAIR -o $FLAIR_BIASCORR --verbose 1"
CMD_BET="bet $FLAIR_BIASCORR $FLAIR_BRAIN -m -v"

# Execute commands
##################

$singularity_mrtrix3 $CMD_BIASCORR_FLAIR
$singularity_fsl $CMD_BET

mv ${FLAIR_BRAIN}_mask.nii.gz $BRAIN_MASK

#######################################
# Tissue segmentation of FLAIR images #
#######################################

# Define input
##############

FLAIR_BRAIN=$ANAT_DIR/${1}_ses-${SESSION}_desc-preproc_desc-brain_FLAIR.nii.gz

# Define output
###############

TISSUES=$ANAT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-fast
GM=$ANAT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-fast_greymatter.nii.gz
WM=$ANAT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-fast_whitematter.nii.gz
CSF=$ANAT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-fast_csf.nii.gz

# Define command
################

CMD_FAST="fast --class 3 --type 2 --segments --nobias --out $TISSUES $FLAIR_BRAIN"

# Execute command
#################

$singularity_fsl $CMD_FAST
mv ${TISSUES}_seg_0.nii.gz $GM
mv ${TISSUES}_seg_1.nii.gz $WM
mv ${TISSUES}_seg_2.nii.gz $CSF

########################################
# Brain extraction of perfusion images #
########################################

# Define input
##############

BASELINE_DSC=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_baselineSI.nii.gz
MTT=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-LeakageCorrected_MTT.nii.gz
RBF=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-LeakageCorrected_rBF.nii.gz
RBV=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-LeakageCorrected_rBV.nii.gz
EF=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_EF.nii.gz
LEAKAGE=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_leakage.nii.gz
TMAX=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_Tmax.nii.gz

# Define output
###############

BASELINE_DSC_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_baselineSI
DSC_BRAIN_MASK=$PERF_DIR/${1}_ses-${SESSION}_space-dsc_desc-brain_mask.nii.gz
MTT_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-LeakageCorrected_MTT.nii.gz
RBF_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-LeakageCorrected_rBF.nii.gz
RBV_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-LeakageCorrected_rBV.nii.gz
EF_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_EF.nii.gz
LEAKAGE_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_leakage.nii.gz
TMAX_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_Tmax.nii.gz

# Define commands
#################

CMD_BET_DSC="bet $BASELINE_DSC $BASELINE_DSC_BRAIN -m -v"
CMD_BET_MTT="fslmaths $MTT -mul $DSC_BRAIN_MASK $MTT_BRAIN"
CMD_BET_RBF="fslmaths $RBF -mul $DSC_BRAIN_MASK $RBF_BRAIN"
CMD_BET_RBV="fslmaths $RBV -mul $DSC_BRAIN_MASK $RBV_BRAIN"
CMD_BET_EF="fslmaths $EF -mul $DSC_BRAIN_MASK $EF_BRAIN"
CMD_BET_LEAKAGE="fslmaths $LEAKAGE -mul $DSC_BRAIN_MASK $LEAKAGE_BRAIN"
CMD_BET_TMAX="fslmaths $TMAX -mul $DSC_BRAIN_MASK $TMAX_BRAIN"

# Execute commands
##################

$singularity_fsl $CMD_BET_DSC
mv ${BASELINE_DSC_BRAIN}_mask.nii.gz $DSC_BRAIN_MASK

$singularity_fsl $CMD_BET_MTT
$singularity_fsl $CMD_BET_RBF
$singularity_fsl $CMD_BET_RBV
$singularity_fsl $CMD_BET_EF
$singularity_fsl $CMD_BET_LEAKAGE
$singularity_fsl $CMD_BET_TMAX

##########################################
# Convert leakage map to absolute values #
##########################################

# Define input
##############

LEAKAGE_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_leakage.nii.gz

# Define output
###############

LEAKAGE_ABS=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_absleakage.nii.gz

# Define command
################

CMD_ABS="fslmaths $LEAKAGE_BRAIN -abs $LEAKAGE_ABS"

# Execute command
#################

$singularity_fsl $CMD_ABS

####################################
# Smoothing of perfusion images ?! #
####################################

#################################################################################
# Registration of lesion and tissue segmentations from FLAIR space to DSC space #
#################################################################################

# Define input
##############

BASELINE_DSC_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_baselineSI.nii.gz
FLAIR_BRAIN=$ANAT_DIR/${1}_ses-${SESSION}_desc-preproc_desc-brain_FLAIR.nii.gz
[ $ORIG_SPACE == "FLAIR" ] && LESION_DIR=$DATA_DIR/$MODIFIER/$1/ses-$SESSION/anat
LESION_MASK=$LESION_DIR/${1}_ses-${SESSION}_space-FLAIR_lesionmask.nii.gz

GM=$ANAT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-fast_greymatter.nii.gz
WM=$ANAT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-fast_whitematter.nii.gz
CSF=$ANAT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-fast_csf.nii.gz

# Define output
###############

DSC_2_FLAIR=$ANAT_DIR/${1}_ses-${SESSION}_from-dsc_to-FLAIR_desc-affine_
AFFINE=${DSC_2_FLAIR}0GenericAffine.mat
LESION_MASK_DSC=$ANAT_DIR/${1}_ses-${SESSION}_space-dsc_desc-lesion_mask.nii.gz

GM_DSC=$ANAT_DIR/${1}_ses-${SESSION}_space-dsc_desc-fast_greymatter.nii.gz
WM_DSC=$ANAT_DIR/${1}_ses-${SESSION}_space-dsc_desc-fast_whitematter.nii.gz
CSF_DSC=$ANAT_DIR/${1}_ses-${SESSION}_space-dsc_desc-fast_csf.nii.gz

# Define commands
#################

# Registration

CMD_DSC2FLAIR="antsRegistrationSyN.sh -d 3 -n $SLURM_CPUS_PER_TASK -m $BASELINE_DSC_BRAIN -f $FLAIR_BRAIN -o $DSC_2_FLAIR -t a"
CMD_APPLY_XFM_LESION="antsApplyTransforms -d 3 -e 0 -i $LESION_MASK -r $BASELINE_DSC_BRAIN -t [ $AFFINE, 1 ] -o $LESION_MASK_DSC"
CMD_APPLY_XFM_GM="antsApplyTransforms -d 3 -e 0 -i $GM -r $BASELINE_DSC_BRAIN -t [ $AFFINE, 1 ] -o $GM_DSC"
CMD_APPLY_XFM_WM="antsApplyTransforms -d 3 -e 0 -i $WM -r $BASELINE_DSC_BRAIN -t [ $AFFINE, 1 ] -o $WM_DSC"
CMD_APPLY_XFM_CSF"antsApplyTransforms -d 3 -e 0 -i $CSF -r $BASELINE_DSC_BRAIN -t [ $AFFINE, 1 ] -o $CSF_DSC"

# Thresholding

CMD_THRESH_LESION="fslmaths $LESION_MASK_DSC -thr 0.9 -bin $LESION_MASK_DSC"
CMD_TRESH_GM="fslmaths $GM_DSC -thr 0.1 -bin $GM_DSC"
CMD_TRESH_WM="fslmaths $WM_DSC -thr 0.1 -bin $WM_DSC"
CMD_TRESH_CSF="fslmaths $CSF_DSC -thr 0.1 -bin $CSF_DSC"

# Execute commands
##################

# Registration

$singularity_mrtrix3 $CMD_DSC2FLAIR
$singularity_mrtrix3 $CMD_APPLY_XFM_LESION
$singularity_fsl $CMD_APPLY_XFM_GM
$singularity_fsl $CMD_APPLY_XFM_WM
$singularity_fsl $CMD_APPLY_XFM_CSF

# Thresholding

$singularity_fsl $CMD_THRESH_LESION
$singularity_fsl $CMD_TRESH_GM
$singularity_fsl $CMD_TRESH_WM
$singularity_fsl $CMD_TRESH_CSF

#######################################################
# Exclude voxels containing CSF from further analysis #
#######################################################

# Define input
##############

MTT_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-LeakageCorrected_MTT.nii.gz
RBF_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-LeakageCorrected_rBF.nii.gz
RBV_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-LeakageCorrected_rBV.nii.gz
EF_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_EF.nii.gz
LEAKAGE_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_leakage.nii.gz
LEAKAGE_ABS_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_absleakage.nii.gz
TMAX_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_Tmax.nii.gz

CSF_DSC=$ANAT_DIR/${1}_ses-${SESSION}_space-dsc_desc-fast_csf.nii.gz

# Define output
###############

MTT_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_MTT.nii.gz
RBF_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_rBF.nii.gz
RBV_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_rBV.nii.gz
EF_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_EF.nii.gz
LEAKAGE_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_leakage.nii.gz
LEAKAGE_ABS_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_absleakage.nii.gz
TMAX_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_Tmax.nii.gz

# Define commands
#################

CMD_MTT_WOCSF="fslmaths $CSF_DSC -add 1 -uthr 1 -mul $MTT_BRAIN $MTT_CLEAN"
CMD_RBF_WOCSF="fslmaths $CSF_DSC -add 1 -uthr 1 -mul $RBF_BRAIN $RBF_CLEAN"
CMD_RBV_WOCSF="fslmaths $CSF_DSC -add 1 -uthr 1 -mul $RBV_BRAIN $RBV_CLEAN"
CMD_EF_WOCSF="fslmaths $CSF_DSC -add 1 -uthr 1 -mul $EF_BRAIN $EF_CLEAN"
CMD_LEAKAGE_WOCSF="fslmaths $CSF_DSC -add 1 -uthr 1 -mul $LEAKAGE_BRAIN $LEAKAGE_CLEAN"
CMD_LEAKAGE_ABS_WOCSF="fslmaths $CSF_DSC -add 1 -uthr 1 -mul $LEAKAGE_ABS_BRAIN $LEAKAGE_ABS_CLEAN"
CMD_TMAX_WOCSF="fslmaths $CSF_DSC -add 1 -uthr 1 -mul $TMAX_BRAIN $TMAX_CLEAN"

# Execute commands
##################

$singularity_fsl $CMD_MTT_WOCSF
$singularity_fsl $CMD_RBF_WOCSF
$singularity_fsl $CMD_RBV_WOCSF
$singularity_fsl $CMD_EF_WOCSF
$singularity_fsl $CMD_LEAKAGE_WOCSF
$singularity_fsl $CMD_LEAKAGE_ABS_WOCSF
$singularity_fsl $CMD_TMAX_WOCSF

###################################################
# Creation of perfusion deficit masks (Tmax > 6s) #
###################################################

# Define input
##############

TMAX_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_Tmax.nii.gz

# Define output
###############

PERF_CLUSTER=$PERF_DIR/${1}_ses-${SESSION}_desc-perfusiondeficit_clusters.nii.gz
PERF_DEFICIT=$PERF_DIR/${1}_ses-${SESSION}_desc-perfusiondeficit_mask.nii.gz

# Calculate cluster threshold based on individual voxel volume
##############################################################

CMD_X="fslval $TMAX_BRAIN pixdim1"
CMD_Y="fslval $TMAX_BRAIN pixdim2"
CMD_Z="fslval $TMAX_BRAIN pixdim3"

X=`$singularity_fsl $CMD_X | tail -n 1`
Y=`$singularity_fsl $CMD_Y | tail -n 1`
Z=`$singularity_fsl $CMD_Z | tail -n 1`

# Minimum volume of cluster is set here to be at least 1 ml

VOX_THRESH=`echo $((1000/$(($X*$Y*$Z)))) | awk '{print int($1+0.5)}'`

# Threshold Tmax image and create perfusion deficit mask 
########################################################

CMD_PERF_CLUSTER="cluster --in=$TMAX_CLEAN --thresh=6 --osize=$PERF_CLUSTER --connectivity=6"
CMD_PERF_DEFICIT="fslmaths $PERF_CLUSTER -thr $VOX_THRESH $PERF_DEFICIT"

$singularity_fsl $CMD_PERF_CLUSTER
$singularity_fsl $CMD_PERF_DEFICIT

#######################################
# Z-tranformation of perfusion images #
#######################################

# Define input
##############

MTT_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_MTT.nii.gz
RBF_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_rBF.nii.gz
RBV_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_rBV.nii.gz
EF_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_EF.nii.gz
LEAKAGE_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_leakage.nii.gz
LEAKAGE_ABS_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_absleakage.nii.gz
TMAX_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_Tmax.nii.gz

# Define output
###############

MTT_Z=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_MTTz.nii.gz
RBF_Z=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_rBFz.nii.gz
RBV_Z=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_rBVz.nii.gz
EF_Z=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_EFz.nii.gz
LEAKAGE_Z=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_leakagez.nii.gz
LEAKAGE_ABS_Z=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_absleakagez.nii.gz
TMAX_Z=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_Tmaxz.nii.gz

# Define z-tranformation function
#################################

ztransform() {

    img=$1
    out=$2

    mean=`$singularity_fsl fslstats $img -M | tail -n 1`
    std=`$singularity_fsl fslstats $img -S | tail -n 1`

    $singularity_fsl fslmaths $img -sub $mean -div $std $out

}

# Execute commands
##################

ztransform $MTT_CLEAN $MTT_Z
ztransform $RBF_CLEAN $RBF_Z
ztransform $RBV_CLEAN $RBV_Z
ztransform $EF_CLEAN $EF_Z
ztransform $LEAKAGE_CLEAN $LEAKAGE_Z
ztransform $LEAKAGE_ABS_CLEAN $LEAKAGE_ABS_Z
ztransform $TMAX_CLEAN $TMAX_Z

###################################################################################################################
#                                           PART II: STANDARD SPACE                                               #
###################################################################################################################

###########################################
# Registration of FLAIR to standard space #
###########################################

# Define input
##############

FLAIR_BRAIN=$ANAT_DIR/${1}_ses-${SESSION}_desc-preproc_desc-brain_FLAIR.nii.gz
TEMPLATE=$ENV_DIR/standard/miplab-flair_asym_brain.nii.gz

# Define output
###############

FLAIR_IN_TEMPLATE=$ANAT_DIR/${1}_ses-${SESSION}_space-miplab_desc-preproc_desc-brain_FLAIR.nii.gz
FLAIR2TEMPLATE_WARP=$ANAT_DIR/${1}_ses-${SESSION}_from-FLAIR_to-miplab_Composite.h5

# Define command
################

CMD_FLAIR2TEMPLATE="
antsRegistration \
    --output [ $ANAT_DIR/${1}_ses-${SESSION}_from-FLAIR_to-miplab_, $FLAIR_IN_TEMPLATE ] \
    --collapse-output-transforms 0 \
    --dimensionality 3 \
    --initial-moving-transform [ $TEMPLATE, $FLAIR_BRAIN, 1 ] \
    --initialize-transforms-per-stage 0 \
    --interpolation LanczosWindowedSinc \
    --transform Rigid[ 0.1 ] \
    --metric MI[ $TEMPLATE, $FLAIR_BRAIN, 1, 32, Regular, 0.25 ] \
    --convergence [ 10000x111110x11110x100, 1e-08, 10 ] \
    --smoothing-sigmas 3.0x2.0x1.0x0.0vox \
    --shrink-factors 8x4x2x1 \
    --use-estimate-learning-rate-once 1 \
    --use-histogram-matching 1 \
    --transform Affine[ 0.1 ] \
    --metric MI[ $TEMPLATE, $FLAIR_BRAIN, 1, 32, Regular, 0.25 ] \
    --convergence [ 10000x111110x11110x100, 1e-08, 10 ] \
    --smoothing-sigmas 3.0x2.0x1.0x0.0vox \
    --shrink-factors 8x4x2x1 \
    --use-estimate-learning-rate-once 1 \
    --use-histogram-matching 1 \
    --transform SyN[ 0.2, 3.0, 0.0 ] \
    --metric CC[ $TEMPALTE, $FLAIR_BRAIN, 1, 4 ] \
    --convergence [ 100x50x30x20, 1e-08, 10 ] \
    --smoothing-sigmas 3.0x2.0x1.0x0.0vox \
    --shrink-factors 8x4x2x1 \
    --use-estimate-learning-rate-once 1 \
    --use-histogram-matching 1 -v \
    --winsorize-image-intensities [ 0.005, 0.995 ] \
    --write-composite-transform 1"

# Execute command
#################

$singularity_mrtrix3 $CMD_FLAIR2TEMPLATE

################################################################
# Registration of perfusion images to standard space via FLAIR #
################################################################

# Define input ### USE brain extracted only perfusion images > exclude csf/ventricles afterwards??
##############

MTT_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_MTT.nii.gz
RBF_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_rBF.nii.gz
RBV_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_rBV.nii.gz
EF_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_EF.nii.gz
LEAKAGE_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_leakage.nii.gz
LEAKAGE_ABS_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_absleakage.nii.gz
TMAX_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_Tmax.nii.gz

DSC2FLAIR_AFFINE=$ANAT_DIR/${1}_ses-${SESSION}_from-dsc_to-FLAIR_desc-affine_0GenericAffine.mat
FLAIR2TEMPLATE_WARP=$ANAT_DIR/${1}_ses-${SESSION}_from-FLAIR_to-miplab_Composite.h5
TEMPLATE=$ENV_DIR/standard/miplab-flair_asym_brain.nii.gz

# Define output
###############

MTT_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_MTT.nii.gz
RBF_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_rBF.nii.gz
RBV_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_rBV.nii.gz
EF_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_EF.nii.gz
LEAKAGE_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_leakage.nii.gz
LEAKAGE_ABS_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_absleakage.nii.gz
TMAX_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_Tmax.nii.gz

# Define commands
#################

CMD_MTT2MNI="antsApplyTransforms -d 3 -e 0 -n LanczosWindowedSinc -i $MTT_CLEAN -r $TEMPLATE -t $FLAIR2TEMPLATE_WARP -t $DSC2FLAIR_AFFINE -o $MTT_TEMP"
CMD_RBF2MNI="antsApplyTransforms -d 3 -e 0 -n LanczosWindowedSinc -i $RBF_CLEAN -r $TEMPLATE -t $FLAIR2TEMPLATE_WARP -t $DSC2FLAIR_AFFINE -o $RBF_TEMP"
CMD_RBV2MNI="antsApplyTransforms -d 3 -e 0 -n LanczosWindowedSinc -i $RBV_CLEAN -r $TEMPLATE -t $FLAIR2TEMPLATE_WARP -t $DSC2FLAIR_AFFINE -o $RBV_TEMP"
CMD_EF2MNI="antsApplyTransforms -d 3 -e 0 -n LanczosWindowedSinc -i $EF_CLEAN -r $TEMPLATE -t $FLAIR2TEMPLATE_WARP -t $DSC2FLAIR_AFFINE -o $EF_TEMP"
CMD_LEAKAGE2MNI="antsApplyTransforms -d 3 -e 0 -n LanczosWindowedSinc -i $LEAKAGE_CLEAN -r $TEMPLATE -t $FLAIR2TEMPLATE_WARP -t $DSC2FLAIR_AFFINE -o $LEAKAGE_TEMP"
CMD_LEAKAGE_ABS2MNI="antsApplyTransforms -d 3 -e 0 -n LanczosWindowedSinc -i $LEAKAGE_ABS_CLEAN -r $TEMPLATE -t $FLAIR2TEMPLATE_WARP -t $DSC2FLAIR_AFFINE -o $LEAKAGE_ABS_TMEP"
CMD_TMAX2MNI="antsApplyTransforms -d 3 -e 0 -n LanczosWindowedSinc -i $TMAX_CLEAN -r $TEMPLATE -t $FLAIR2TEMPLATE_WARP -t $DSC2FLAIR_AFFINE -o $TMAX_TEMP"

# Execute commands
##################

$singularity_mrtrix3 $CMD_MTT2MNI
$singularity_mrtrix3 $CMD_RBF2MNI
$singularity_mrtrix3 $CMD_RBV2MNI
$singularity_mrtrix3 $CMD_EF2MNI
$singularity_mrtrix3 $CMD_LEAKAGE2MNI
$singularity_mrtrix3 $CMD_LEAKAGE_ABS2MNI
$singularity_mrtrix3 $CMD_TMAX2MNI

########################################################################
# Registration of lesion and perfusion deficit masks to standard space #
########################################################################

# Define input
##############

[ $ORIG_SPACE == "FLAIR" ] && LESION_DIR=$DATA_DIR/$MODIFIER/$1/ses-$SESSION/anat
LESION_MASK=$LESION_DIR/${1}_ses-${SESSION}_space-FLAIR_lesionmask.nii.gz
PERF_DEFICIT=$PERF_DIR/${1}_ses-${SESSION}_desc-perfusiondeficit_mask.nii.gz

DSC2FLAIR_AFFINE=$ANAT_DIR/${1}_ses-${SESSION}_from-dsc_to-FLAIR_desc-affine_0GenericAffine.mat
FLAIR2TEMPLATE_WARP=$ANAT_DIR/${1}_ses-${SESSION}_from-FLAIR_to-miplab_Composite.h5
TEMPLATE=$ENV_DIR/standard/miplab-flair_asym_brain.nii.gz

# Define output
###############

LESION_TEMP=$ANAT_DIR/${1}_ses-${SESSION}_space-miplab_desc-lesion_mask.nii.gz
PERF_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-perfusiondeficit_mask.nii.gz

# Define commands
#################

CMD_LESION2TEMP="antsApplyTransforms -d 3 -e 0 -n Linear -i $LESION_MASK -r $TEMPLATE -t $FLAIR2TEMPLATE_WARP -o $LESION_TEMP"
CMD_PERF2TEMP="antsApplyTransforms -d 3 -e 0 -n Linear -i $PERF_DEFICIT -r $TEMPLATE -t $FLAIR2TEMPLATE_WARP -t $DSC2FLAIR_AFFINE -o $PERF_TEMP"
CMD_THRESH_LESION="fslmaths $LESION_TEMP -thr 0.9 $LESION_TEMP"
CMD_THRESH_PERF="fslmaths $PERF_TEMP -thr 0.9 $PERF_TEMP"

# Execute commands
##################

$singularity_mrtrix3 $CMD_LESION2TEMP
$singularity_mrtrix3 $CMD_PERF2TEMP
$singularity_fsl $CMD_THRESH_LESION
$singularity_fsl $CMD_THRESH_PERF

##########################################################
# Z-transformation of perfusion images in standard space #
##########################################################

# Define input
##############

MTT_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_MTT.nii.gz
RBF_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_rBF.nii.gz
RBV_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_rBV.nii.gz
EF_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_EF.nii.gz
LEAKAGE_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_leakage.nii.gz
LEAKAGE_ABS_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_absleakage.nii.gz
TMAX_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_Tmax.nii.gz


# Define output
###############

MTT_Z_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_MTTz.nii.gz
RBF_Z_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_rBFz.nii.gz
RBV_Z_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_rBVz.nii.gz
EF_Z_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_EFz.nii.gz
LEAKAGE_Z_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_leakagez.nii.gz
LEAKAGE_ABS_Z_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_absleakagez.nii.gz
TMAX_Z_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_Tmaxz.nii.gz

# Execute commands
##################

ztransform $MTT_TEMP $MTT_Z_TEMP
ztransform $RBF_TEMP $RBF_Z_TEMP
ztransform $RBV_TEMP $RBV_Z_TEMP
ztransform $EF_TEMP $EF_Z_TEMP
ztransform $LEAKAGE_TEMP $LEAKAGE_Z_TEMP
ztransform $LEAKAGE_ABS_TEMP $LEAKAGE_ABS_Z_TEMP
ztransform $TMAX_TEMP $TMAX_Z_TEMP

###################################################################################################################
#                                  PART III: READ-OUT LESION/PEFUSION DEFICIT MASKS                               #
###################################################################################################################

##############
# Create CSV #
##############

CSV=$PERF_DIR/${1}_ses-${SESSION}_perfusion.csv

echo -e "sub_id,nice_lesion_mean_mtt,nice_lesion_mean_rbf,nice_lesion_mean_rbv,nice_lesion_mean_ef,nice_lesion_mean_leakage,nice_lesion_mean_absleakage,nice_lesion_mean_tmax,\
nice_lesion_z_mtt,nice_lesion_z_rbf,nice_lesion_z_rbv,nice_lesion_z_ef,nice_lesion_z_leakage,nice_lesion_z_absleakage,nice_lesion_z_tmax,\
nicestandard_lesion_mean_mtt,nicestandard_lesion_mean_rbf,nicestandard_lesion_mean_rbv,nicestandard_lesion_mean_ef,nicestandard_lesion_mean_leakage,nicestandard_lesion_mean_absleakage,nicestandard_lesion_mean_tmax,\
nicestandard_lesion_z_mtt,nicestandard_lesion_z_rbf,nicestandard_lesion_z_rbv,nicestandard_lesion_z_ef,nicestandard_lesion_z_leakage,nicestandard_lesion_z_absleakage,nicestandard_lesion_z_tmax,\
nice_perfdef_mean_mtt,nice_perfdef_mean_rbf,nice_perfdef_mean_rbv,nice_perfdef_mean_ef,nice_perfdef_mean_leakage,nice_perfdef_mean_absleakage,nice_perfdef_mean_tmax,\
nice_perfdef_z_mtt,nice_perfdef_z_rbf,nice_perfdef_z_rbv,nice_perfdef_z_ef,nice_perfdef_z_leakage,nice_perfdef_z_absleakage,nice_perfdef_z_tmax,\
nicestandard_perfdef_mean_mtt,nicestandard_perfdef_mean_rbf,nicestandard_perfdef_mean_rbv,nicestandard_perfdef_mean_ef,nicestandard_perfdef_mean_leakage,nicestandard_perfdef_mean_absleakage,nicestandard_perfdef_mean_tmax,\
nicestandard_perfdef_z_mtt,nicestandard_perfdef_z_rbf,nicestandard_perfdef_z_rbv,nicestandard_perfdef_z_ef,nicestandard_perfdef_z_leakage,nicestandard_perfdef_z_absleakage,nicestandard_perfdef_z_tmax" > $CSV

####################
# Read-out of ROIs #
####################

# Define input
##############

# DSC space

MTT_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_MTT.nii.gz
RBF_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_rBF.nii.gz
RBV_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_rBV.nii.gz
EF_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_EF.nii.gz
LEAKAGE_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_leakage.nii.gz
LEAKAGE_ABS_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_absleakage.nii.gz
TMAX_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_Tmax.nii.gz

MTT_Z=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_MTTz.nii.gz
RBF_Z=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_rBFz.nii.gz
RBV_Z=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_rBVz.nii.gz
EF_Z=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_EFz.nii.gz
LEAKAGE_Z=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_leakagez.nii.gz
LEAKAGE_ABS_Z=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_absleakagez.nii.gz
TMAX_Z=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_Tmaxz.nii.gz

PERF_DEFICIT=$PERF_DIR/${1}_ses-${SESSION}_desc-perfusiondeficit_mask.nii.gz
LESION_MASK_DSC=$ANAT_DIR/${1}_ses-${SESSION}_space-dsc_desc-lesion_mask.nii.gz

# Standard space

MTT_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_MTT.nii.gz
RBF_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_rBF.nii.gz
RBV_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_rBV.nii.gz
EF_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_EF.nii.gz
LEAKAGE_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_leakage.nii.gz
LEAKAGE_ABS_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_absleakage.nii.gz
TMAX_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_Tmax.nii.gz

MTT_Z_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_MTTz.nii.gz
RBF_Z_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_rBFz.nii.gz
RBV_Z_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_rBVz.nii.gz
EF_Z_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_EFz.nii.gz
LEAKAGE_Z_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_leakagez.nii.gz
LEAKAGE_ABS_Z_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_absleakagez.nii.gz
TMAX_Z_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-moco_desc-brain_desc-wocsf_Tmaxz.nii.gz

LESION_TEMP=$ANAT_DIR/${1}_ses-${SESSION}_space-miplab_desc-lesion_mask.nii.gz
PERF_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-miplab_desc-perfusiondeficit_mask.nii.gz

# Define function which extracts mean of ROI
############################################

extractmean() {

    img=$1
    roi=$2

    $singularity_fsl fslmaths $img -mul $roi $TMP_OUT/${roi}_mean_tmp
    mean=`$singularity_fsl fslstats $TMP_OUT/${roi}_mean_tmp -M | tail -n 1`

    echo $mean

}

# Extract means
###############

# Lesion

lesion_mtt=`extractmean $MTT_CLEAN $LESION_MASK_DSC`
lesion_rbf=`extractmean $RBF_CLEAN $LESION_MASK_DSC`
lesion_rbv=`extractmean $RBV_CLEAN $LESION_MASK_DSC`
lesion_ef=`extractmean $EF_CLEAN $LESION_MASK_DSC`
lesion_leakage=`extractmean $LEAKAGE_CLEAN $LESION_MASK_DSC`
lesion_absleakage=`extractmean $LEAKAGE_ABS_CLEAN $LESION_MASK_DSC`
lesion_tmax=`extractmean $TMAX_CLEAN $LESION_MASK_DSC`

lesion_z_mtt=`extractmean $MTT_Z $LESION_MASK_DSC`
lesion_z_rbf=`extractmean $RBF_Z $LESION_MASK_DSC`
lesion_z_rbv=`extractmean $RBV_Z $LESION_MASK_DSC`
lesion_z_ef=`extractmean $EF_Z $LESION_MASK_DSC`
lesion_z_leakage=`extractmean $LEAKAGE_Z $LESION_MASK_DSC`
lesion_z_absleakage=`extractmean $LEAKAGE_ABS_Z $LESION_MASK_DSC`
lesion_z_tmax=`extractmean $TMAX_Z $LESION_MASK_DSC`

lesionstandard_mtt=`extractmean $MTT_TEMP $LESION_TEMP`
lesionstandard_rbf=`extractmean $RBF_TEMP $LESION_TEMP`
lesionstandard_rbv=`extractmean $RBV_TEMP $LESION_TEMP`
lesionstandard_ef=`extractmean $EF_TEMP $LESION_TEMP`
lesionstandard_leakage=`extractmean $LEAKAGE_TEMP $LESION_TEMP`
lesionstandard_absleakage=`extractmean $LEAKAGE_ABS_TEMP $LESION_TEMP`
lesionstandard_tmax=`extractmean $TMAX_TEMP $LESION_TEMP`

lesionstandard_z_mtt=`extractmean $MTT_Z_TEMP $LESION_TEMP`
lesionstandard_z_rbf=`extractmean $RBF_Z_TEMP $LESION_TEMP`
lesionstandard_z_rbv=`extractmean $RBV_Z_TEMP $LESION_TEMP`
lesionstandard_z_ef=`extractmean $EF_Z_TEMP $LESION_TEMP`
lesionstandard_z_leakage=`extractmean $LEAKAGE_Z_TEMP $LESION_TEMP`
lesionstandard_z_absleakage=`extractmean $LEAKAGE_ABS_Z_TEMP $LESION_TEMP`
lesionstandard_z_tmax=`extractmean $TMAX_Z_TEMP $LESION_TEMP`


# Perfusion deficit

perfdef_mtt=`extractmean $MTT_CLEAN $PERF_DEFICIT`
perfdef_rbf=`extractmean $RBF_CLEAN $PERF_DEFICIT`
perfdef_rbv=`extractmean $RBV_CLEAN $PERF_DEFICIT`
perfdef_ef=`extractmean $EF_CLEAN $PERF_DEFICIT`
perfdef_leakage=`extractmean $LEAKAGE_CLEAN $PERF_DEFICIT`
perfdef_absleakage=`extractmean $LEAKAGE_ABS_CLEAN $PERF_DEFICIT`
perfdef_tmax=`extractmean $TMAX_CLEAN $PERF_DEFICIT`

perfdef_z_mtt=`extractmean $MTT_Z $PERF_DEFICIT`
perfdef_z_rbf=`extractmean $RBF_Z $PERF_DEFICIT`
perfdef_z_rbv=`extractmean $RBV_Z $PERF_DEFICIT`
perfdef_z_ef=`extractmean $EF_Z $PERF_DEFICIT`
perfdef_z_leakage=`extractmean $LEAKAGE_Z $PERF_DEFICIT`
perfdef_z_absleakage=`extractmean $LEAKAGE_ABS_Z $PERF_DEFICIT`
perfdef_z_tmax=`extractmean $TMAX_Z $PERF_DEFICIT`

perfdefstandard_mtt=`extractmean $MTT_TEMP $PERF_TEMP`
perfdefstandard_rbf=`extractmean $RBF_TEMP $PERF_TEMP`
perfdefstandard_rbv=`extractmean $RBV_TEMP $PERF_TEMP`
perfdefstandard_ef=`extractmean $EF_TEMP $PERF_TEMP`
perfdefstandard_leakage=`extractmean $LEAKAGE_TEMP $PERF_TEMP`
perfdefstandard_absleakage=`extractmean $LEAKAGE_ABS_TEMP $PERF_TEMP`
perfdefstandard_tmax=`extractmean $TMAX_TEMP $PERF_TEMP`

perfdefstandard_z_mtt=`extractmean $MTT_Z_TEMP $PERF_TEMP`
perfdefstandard_z_rbf=`extractmean $RBF_Z_TEMP $PERF_TEMP`
perfdefstandard_z_rbv=`extractmean $RBV_Z_TEMP $PERF_TEMP`
perfdefstandard_z_ef=`extractmean $EF_Z_TEMP $PERF_TEMP`
perfdefstandard_z_leakage=`extractmean $LEAKAGE_Z_TEMP $PERF_TEMP`
perfdefstandard_z_absleakage=`extractmean $LEAKAGE_ABS_Z_TEMP $PERF_TEMP`
perfdefstandard_z_tmax=`extractmean $TMAX_Z_TEMP $PERF_TEMP`


# Append to CSV
###############

echo -e "$1,$lesion_mtt,$lesion_rbf,$lesion_rbv,$lesion_ef,$lesion_leakage,$lesion_absleakage,$lesion_tmax,\
$lesion_z_mtt,$lesion_z_rbf,$lesion_z_rbv,$lesion_z_ef,$lesion_z_leakage,$lesion_z_absleakage,$lesion_z_tmax,\
$lesionstandard_mtt,$lesionstandard_rbf,$lesionstandard_rbv,$lesionstandard_ef,$lesionstandard_leakage,$lesionstandard_absleakage,$lesionstandard_tmax,\
$lesionstandard_z_mtt,$lesionstandard_z_rbf,$lesionstandard_z_rbv,$lesionstandard_z_ef,$lesionstandard_z_leakage,$lesionstandard_z_absleakage,$lesionstandard_z_tmax,\
$perfdef_mtt,$perfdef_rbf,$perfdef_rbv,$perfdef_ef,$perfdef_leakage,$perfdef_absleakage,$perfdef_tmax,\
$perfdef_z_mtt,$perfdef_z_rbf,$perfdef_z_rbv,$perfdef_z_ef,$perfdef_z_leakage,$perfdef_z_absleakage,$perfdef_z_tmax,\
$perfdefstandard_mtt,$perfdefstandard_rbf,$perfdefstandard_rbv,$perfdefstandard_ef,$perfdefstandard_leakage,$perfdefstandard_absleakage,$perfdefstandard_tmax,\
$perfdefstandard_z_mtt,$perfdefstandard_z_rbf,$perfdefstandard_z_rbv,$perfdefstandard_z_ef,$perfdefstandard_z_leakage,$perfdefstandard_z_absleakage,$perfdefstandard_z_tmax" >> $CSV


