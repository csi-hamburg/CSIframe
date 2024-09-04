#!/bin/bash

###################################################################################################################
# Script for postprocessing NordicIce perfusion analysis output                                                   #
#       - brain extraction and bias correction of FLAIR images                                                    #
#       - registration of lesion segmentations from FLAIR space to DSC space                                      #
#       - registration of pefusion images to standard space                                                       #
#       - extraction of perfusion and blood brain barrier estimates                                               #
###################################################################################################################

###################################################################################################################
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - NordicIce perfusion analysis and bidsification of it's outputs                                          #
#       - RapidAI perfusion analysis for perfusion deficit masks and registration to NordicIce space              #
#   [containers]                                                                                                  #
#       - fsl-6.0.3                                                                                               #
#       - mrtrix3-3.0.2                                                                                           #
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
ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=4

module load singularity
container_fsl=fsl-6.0.3     
container_mrtrix3=mrtrix3-3.0.2
container_freesurfer=freesurfer-7.4.1    

singularity_mrtrix3="singularity run --cleanenv --no-home --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR \
    -B $TMP_IN \
    -B $TMP_OUT \
    $ENV_DIR/$container_mrtrix3" 

singularity_fsl="singularity run --cleanenv --userns \
    -B . \
    -B $PROJ_DIR \
    -B $SCRATCH_DIR:/tmp \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR \
    -B $TMP_IN \
    -B $TMP_OUT \
    $ENV_DIR/$container_fsl"

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

FLAIR=$BIDS_DIR/$1/ses-$SESSION/anat/${1}_ses-${SESSION}_FLAIR.nii.gz
FLAIR_2=$BIDS_DIR/$1/ses-2/anat/${1}_ses-2_FLAIR.nii.gz

# Define output
###############

FLAIR_BIASCORR=$ANAT_DIR/${1}_ses-${SESSION}_desc-preproc_FLAIR.nii.gz
FLAIR_BRAIN=$ANAT_DIR/${1}_ses-${SESSION}_desc-preproc_desc-brain_FLAIR
BRAIN_MASK=$ANAT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brain_mask.nii.gz

FLAIR_2_BIASCORR=$ANAT_DIR/${1}_ses-2_desc-preproc_FLAIR.nii.gz
FLAIR_2_BRAIN=$ANAT_DIR/${1}_ses-2_desc-preproc_desc-brain_FLAIR
BRAIN_2_MASK=$ANAT_DIR/${1}_ses-2_space-FLAIR_desc-brain_mask.nii.gz

# Define commands
#################

CMD_BIASCORR_FLAIR="N4BiasFieldCorrection -d 3 -i $FLAIR -o $FLAIR_BIASCORR --verbose 1"
CMD_BET="bet $FLAIR_BIASCORR $FLAIR_BRAIN -m -v"

CMD_BIASCORR_FLAIR_2="N4BiasFieldCorrection -d 3 -i $FLAIR_2 -o $FLAIR_2_BIASCORR --verbose 1"
CMD_BET_2="bet $FLAIR_2_BIASCORR $FLAIR_2_BRAIN -m -v"

# Execute commands
##################

$singularity_mrtrix3 $CMD_BIASCORR_FLAIR
$singularity_fsl $CMD_BET
mv ${FLAIR_BRAIN}_mask.nii.gz $BRAIN_MASK

if [[ $MODIFIER == "yes" && $SESSION == "1" ]]; then

    $singularity_mrtrix3 $CMD_BIASCORR_FLAIR_2
    $singularity_fsl $CMD_BET_2
    mv ${FLAIR_2_BRAIN}_mask.nii.gz $BRAIN_2_MASK

fi

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

CMD_FAST="fast -n 3 -t 2 -g -N -v -o $TISSUES $FLAIR_BRAIN"
CMD_FILL_CSF="fslmaths $CSF -fillh $CSF"

# Execute command
#################

$singularity_fsl $CMD_FAST
mv ${TISSUES}_seg_0.nii.gz $GM
mv ${TISSUES}_seg_1.nii.gz $WM
mv ${TISSUES}_seg_2.nii.gz $CSF
$singularity_fsl $CMD_FILL_CSF

#####################################################
# Reorient perfusion images to standard orientation #
#####################################################

# This needs to be done to accomodate NordicIce orientation bug

# Define input/output
#####################

BASELINE_DSC=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_baselineSI.nii.gz
MTT=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-LeakageCorrected_MTT.nii.gz
RBF=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-LeakageCorrected_rBF.nii.gz
RBV=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-LeakageCorrected_rBV.nii.gz
EF=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_EF.nii.gz
LEAKAGE=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_leakage.nii.gz
TMAX=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_Tmax.nii.gz

# Define commands
#################

CMD_BASELINE_RO="fslreorient2std $BASELINE_DSC $BASELINE_DSC"
CMD_MTT_RO="fslreorient2std $MTT $MTT"
CMD_RBF_RO="fslreorient2std $RBF $RBF"
CMD_RBV_RO="fslreorient2std $RBV $RBV"
CMD_EF_RO="fslreorient2std $EF $EF"
CMD_LEAKAGE_RO="fslreorient2std $LEAKAGE $LEAKAGE"
CMD_TMAX_RO="fslreorient2std $TMAX $TMAX"

# Execute commands
##################

$singularity_fsl $CMD_BASELINE_RO
$singularity_fsl $CMD_MTT_RO
$singularity_fsl $CMD_RBF_RO
$singularity_fsl $CMD_RBV_RO
$singularity_fsl $CMD_EF_RO
$singularity_fsl $CMD_LEAKAGE_RO
$singularity_fsl $CMD_TMAX_RO

########################################
# Brain extraction of perfusion images #
########################################

# Define input
##############

BASELINE_DSC=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_baselineSI.nii.gz

# Define output
###############

BASELINE_DSC_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_baselineSI
DSC_BRAIN_MASK=$PERF_DIR/${1}_ses-${SESSION}_space-dsc_desc-brain_mask.nii.gz

# Define commands
#################

CMD_BET_DSC="bet $BASELINE_DSC $BASELINE_DSC_BRAIN -m -v"

# Execute commands
##################

$singularity_fsl $CMD_BET_DSC
mv ${BASELINE_DSC_BRAIN}_mask.nii.gz $DSC_BRAIN_MASK


#################################################################################
# Registration of lesion and tissue segmentations from FLAIR space to DSC space #
#################################################################################

# Define input
##############

BASELINE_DSC_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_baselineSI.nii.gz

FLAIR_BRAIN=$ANAT_DIR/${1}_ses-${SESSION}_desc-preproc_desc-brain_FLAIR.nii.gz
[ $ORIG_SPACE == "FLAIR" ] && LESION_DIR=$DATA_DIR/$LESION_DIR/$1/ses-$SESSION/anat
LESION_MASK=$LESION_DIR/${1}_ses-${SESSION}_space-FLAIR_lesionmask.nii.gz

FLAIR_2_BRAIN=$ANAT_DIR/${1}_ses-2_desc-preproc_desc-brain_FLAIR.nii.gz
[ $ORIG_SPACE == "FLAIR" ] && LESION_DIR_2=$DATA_DIR/$LESION_DIR/$1/ses-2/anat
LESION_MASK_2=$LESION_DIR_2/${1}_ses-2_space-FLAIR_lesionmask.nii.gz

GM=$ANAT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-fast_greymatter.nii.gz
WM=$ANAT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-fast_whitematter.nii.gz
CSF=$ANAT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-fast_csf.nii.gz

# Define output
###############

DSC_IN_FLAIR=$PERF_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-moco_desc-brain_baselineSI.nii.gz
DSC_2_FLAIR_FSL=$PERF_DIR/${1}_ses-${SESSION}_from-dsc_to-FLAIR_desc-affine.mat
FLAIR_2_DSC=$ANAT_DIR/${1}_ses-${SESSION}_from-FLAIR_to-dsc_desc-affine.mat

LESION_MASK_DSC_PROB=$ANAT_DIR/${1}_ses-${SESSION}_space-dsc_desc-prob_desc-lesion_mask.nii.gz
LESION_MASK_DSC=$ANAT_DIR/${1}_ses-${SESSION}_space-dsc_desc-lesion_mask.nii.gz
LESION_MASK_DSC_INV=$ANAT_DIR/${1}_ses-${SESSION}_space-dsc_desc-lesion_desc-inverted_mask.nii.gz

GM_DSC_PROB=$ANAT_DIR/${1}_ses-${SESSION}_space-dsc_desc-fast_desc-prob_greymatter.nii.gz
WM_DSC_PROB=$ANAT_DIR/${1}_ses-${SESSION}_space-dsc_desc-fast_desc-prob_whitematter.nii.gz
CSF_DSC_PROB=$ANAT_DIR/${1}_ses-${SESSION}_space-dsc_desc-fast_desc-prob_csf.nii.gz

GM_DSC=$ANAT_DIR/${1}_ses-${SESSION}_space-dsc_desc-fast_greymatter.nii.gz
WM_DSC=$ANAT_DIR/${1}_ses-${SESSION}_space-dsc_desc-fast_whitematter.nii.gz
CSF_DSC=$ANAT_DIR/${1}_ses-${SESSION}_space-dsc_desc-fast_csf.nii.gz

DSC_IN_FLAIR2=$PERF_DIR/${1}_ses-${SESSION}_space-FLAIR2_desc-moco_desc-brain_baselineSI.nii.gz
DSC_2_FLAIR2_FSL=$PERF_DIR/${1}_ses-${SESSION}_from-dsc_to-FLAIR2_desc-affine.mat
FLAIR2_2_DSC=$ANAT_DIR/${1}_ses-${SESSION}_from-FLAIR2_to-dsc_desc-affine.mat

LESION_MASK_2_DSC_PROB=$ANAT_DIR/${1}_ses-2_space-dsc_desc-prob_desc-lesion_mask.nii.gz
LESION_MASK_2_DSC=$ANAT_DIR/${1}_ses-2_space-dsc_desc-lesion_mask.nii.gz

# Define commands
#################

CMD_DSC2FLAIR="flirt -in $BASELINE_DSC_BRAIN -ref $FLAIR_BRAIN -out $DSC_IN_FLAIR -omat $DSC_2_FLAIR_FSL"
CMD_FLAIR2DSC="convert_xfm -omat $FLAIR_2_DSC -inverse $DSC_2_FLAIR_FSL"

CMD_APPLY_XFM_LESION="flirt -in $LESION_MASK -ref $BASELINE_DSC_BRAIN -applyxfm -init $FLAIR_2_DSC -out $LESION_MASK_DSC_PROB"
CMD_APPLY_XFM_GM="flirt -in $GM -ref $BASELINE_DSC_BRAIN -applyxfm -init $FLAIR_2_DSC -out $GM_DSC_PROB"
CMD_APPLY_XFM_WM="flirt -in $WM -ref $BASELINE_DSC_BRAIN -applyxfm -init $FLAIR_2_DSC -out $WM_DSC_PROB"
CMD_APPLY_XFM_CSF="flirt -in $CSF -ref $BASELINE_DSC_BRAIN -applyxfm -init $FLAIR_2_DSC -out $CSF_DSC_PROB"

CMD_DSC2FLAIR2="flirt -in $BASELINE_DSC_BRAIN -ref $FLAIR_2_BRAIN -out $DSC_IN_FLAIR2 -omat $DSC_2_FLAIR2_FSL"
CMD_FLAIR22DSC="convert_xfm -omat $FLAIR2_2_DSC -inverse $DSC_2_FLAIR2_FSL"
CMD_APPLY_XFM_LESION2="flirt -in $LESION_MASK_2 -ref $BASELINE_DSC_BRAIN -applyxfm -init $FLAIR2_2_DSC -out $LESION_MASK_2_DSC_PROB"

# Thresholding
CMD_THRESH_LESION="fslmaths $LESION_MASK_DSC_PROB -thr 0.1 -bin $LESION_MASK_DSC"
CMD_THRESH_LESION2="fslmaths $LESION_MASK_2_DSC_PROB -thr 0.1 -bin $LESION_MASK_2_DSC"
CMD_TRESH_GM="fslmaths $GM_DSC_PROB -thr 0.6 -bin $GM_DSC"
CMD_TRESH_WM="fslmaths $WM_DSC_PROB -thr 0.6 -bin $WM_DSC"
CMD_TRESH_CSF="fslmaths $CSF_DSC_PROB -thr 0.6 -bin $CSF_DSC"

# Inversion
CMD_LESION_INV="fslmaths $LESION_MASK_DSC -binv $LESION_MASK_DSC_INV"

# Execute commands
##################

# Registration
$singularity_fsl $CMD_DSC2FLAIR
$singularity_fsl $CMD_FLAIR2DSC
$singularity_fsl $CMD_APPLY_XFM_LESION
$singularity_fsl $CMD_APPLY_XFM_GM
$singularity_fsl $CMD_APPLY_XFM_WM
$singularity_fsl $CMD_APPLY_XFM_CSF
$singularity_fsl $CMD_DSC2FLAIR2
$singularity_fsl $CMD_FLAIR22DSC
$singularity_fsl $CMD_APPLY_XFM_LESION2

# Thresholding
$singularity_fsl $CMD_THRESH_LESION
$singularity_fsl $CMD_THRESH_LESION2
$singularity_fsl $CMD_TRESH_GM
$singularity_fsl $CMD_TRESH_WM
$singularity_fsl $CMD_TRESH_CSF

# Inversion
$singularity_fsl $CMD_LESION_INV

#######################################################
# Exclude voxels containing CSF from further analysis #
#######################################################

# Define input
##############

MTT=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-LeakageCorrected_MTT.nii.gz
RBF=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-LeakageCorrected_rBF.nii.gz
RBV=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-LeakageCorrected_rBV.nii.gz
EF=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_EF.nii.gz
LEAKAGE=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_leakage.nii.gz
TMAX=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_Tmax.nii.gz
TMAX_RAPID=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-RAPID_Tmax.nii.gz

DSC_BRAIN_MASK=$PERF_DIR/${1}_ses-${SESSION}_space-dsc_desc-brain_mask.nii.gz
CSF_DSC=$ANAT_DIR/${1}_ses-${SESSION}_space-dsc_desc-fast_csf.nii.gz

# Define output
###############

CSF_DSC_DIL=$ANAT_DIR/${1}_ses-${SESSION}_space-dsc_desc-fast_desc-dilated_csf.nii.gz
DSC_BRAIN_MASK_ERO=$PERF_DIR/${1}_ses-${SESSION}_space-dsc_desc-brain_desc-eroded_mask.nii.gz
FILTER_MASK=$PERF_DIR/${1}_ses-${SESSION}_space-dsc_desc-filter_mask.nii.gz

MTT_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_MTT.nii.gz
RBF_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_rBF.nii.gz
RBV_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_rBV.nii.gz
EF_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_EF.nii.gz
LEAKAGE_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_leakage.nii.gz
TMAX_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_Tmax.nii.gz
TMAX_RAPID_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_desc-RAPID_Tmax.nii.gz

# Define commands
#################

CMD_FILTER_MASK="fslmaths $DSC_BRAIN_MASK -sub $CSF_DSC -thr 1 $FILTER_MASK"

CMD_MTT_WOCSF="fslmaths $FILTER_MASK -mul $MTT $MTT_CLEAN"
CMD_RBF_WOCSF="fslmaths $FILTER_MASK -mul $RBF $RBF_CLEAN"
CMD_RBV_WOCSF="fslmaths $FILTER_MASK -mul $RBV $RBV_CLEAN"
CMD_EF_WOCSF="fslmaths $FILTER_MASK -mul $EF $EF_CLEAN"
CMD_LEAKAGE_WOCSF="fslmaths $FILTER_MASK -mul $LEAKAGE $LEAKAGE_CLEAN"
CMD_TMAX_WOCSF="fslmaths $FILTER_MASK -mul $TMAX $TMAX_CLEAN"
CMD_TMAX_RAPID_WOCSF="fslmaths $FILTER_MASK -mul $TMAX_RAPID $TMAX_RAPID_CLEAN"

# Execute commands
##################

$singularity_fsl $CMD_FILTER_MASK

$singularity_fsl $CMD_MTT_WOCSF
$singularity_fsl $CMD_RBF_WOCSF
$singularity_fsl $CMD_RBV_WOCSF
$singularity_fsl $CMD_EF_WOCSF
$singularity_fsl $CMD_LEAKAGE_WOCSF
$singularity_fsl $CMD_TMAX_WOCSF
$singularity_fsl $CMD_TMAX_RAPID_WOCSF

########################################################################################################
#                                   Process RAPID perfusion deficit mask                               #
########################################################################################################

# Create prefusion deficit mask excluding DWI lesion voxels in DSC space
########################################################################

# Define input
##############

PERF_DEFICIT=$PERF_DIR/${1}_ses-${SESSION}_desc-RAPID_desc-perfusiondeficit_mask.nii.gz
PERF_DEFICIT_2=$PERF_DIR/${1}_ses-2_desc-RAPID_desc-perfusiondeficit_mask.nii.gz
LESION_MASK_DSC=$ANAT_DIR/${1}_ses-${SESSION}_space-dsc_desc-lesion_mask.nii.gz
LESION_MASK_2_DSC=$ANAT_DIR/${1}_ses-2_space-dsc_desc-lesion_mask.nii.gz

# Define output
###############

PERF_DEFICIT_INV=$PERF_DIR/${1}_ses-${SESSION}_desc-RAPID_desc-perfusiondeficit_desc-inverted_mask.nii.gz
PENUMBRA=$PERF_DIR/${1}_ses-${SESSION}_desc-RAPID_desc-penumbra_mask.nii.gz
PENUMBRA_NOINFARCT=$PERF_DIR/${1}_ses-${SESSION}_desc-RAPID_desc-penumbra_desc-noinfarct_mask.nii.gz
PENUMBRA_INFARCT=$PERF_DIR/${1}_ses-${SESSION}_desc-RAPID_desc-penumbra_desc-infarct_mask.nii.gz
PENUMBRA_NOREFLOW=$PERF_DIR/${1}_ses-${SESSION}_desc-RAPID_desc-penumbra_desc-noreflow_mask.nii.gz
PENUMBRA_REFLOW=$PERF_DIR/${1}_ses-${SESSION}_desc-RAPID_desc-penumbra_desc-reflow_mask.nii.gz

# Define command
################

CMD_PERF_DEFICIT_INV="fslmaths $PERF_DEFICIT -binv $PERF_DEFICIT_INV"
CMD_PENUMBRA="fslmaths $PERF_DEFICIT -sub $LESION_MASK_DSC -thr 1 $PENUMBRA"
CMD_PENUMBRA_NOINFARCT="fslmaths $PENUMBRA -sub $LESION_MASK_2_DSC -thr 1 $PENUMBRA_NOINFARCT"
CMD_PENUMBRA_INFARCT="fslmaths $PENUMBRA -mul $LESION_MASK_2_DSC $PENUMBRA_INFARCT"
CMD_PENUMBRA_NOREFLOW="fslmaths $PENUMBRA_NOINFARCT -mul $PERF_DEFICIT_2 $PENUMBRA_NOREFLOW"
CMD_PENUMBRA_REFLOW="fslmaths $PENUMBRA_NOINFARCT -sub $PERF_DEFICIT_2 -thr 1 $PENUMBRA_REFLOW"

# Execute command
#################

$singularity_fsl $CMD_PERF_DEFICIT_INV
$singularity_fsl $CMD_PENUMBRA

if [[ $MODIFIER == "yes" && $SESSION == "1" ]]; then

    $singularity_fsl $CMD_PENUMBRA_NOINFARCT
    $singularity_fsl $CMD_PENUMBRA_INFARCT
    $singularity_fsl $CMD_PENUMBRA_NOREFLOW
    $singularity_fsl $CMD_PENUMBRA_REFLOW

fi

#######################################
# Z-tranformation of perfusion images #
#######################################

# Define input
##############

FILTER_MASK=$PERF_DIR/${1}_ses-${SESSION}_space-dsc_desc-filter_mask.nii.gz

MTT_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_MTT.nii.gz
RBF_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_rBF.nii.gz
RBV_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_rBV.nii.gz
EF_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_EF.nii.gz
LEAKAGE_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_leakage.nii.gz
TMAX_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_Tmax.nii.gz
TMAX_RAPID_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_desc-RAPID_Tmax.nii.gz

# Define output
###############

MTT_Z=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_MTTz.nii.gz
RBF_Z=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_rBFz.nii.gz
RBV_Z=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_rBVz.nii.gz
EF_Z=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_EFz.nii.gz
LEAKAGE_Z=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_leakagez.nii.gz
TMAX_Z=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_Tmaxz.nii.gz
TMAX_RAPID_Z=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_desc-RAPID_Tmaxz.nii.gz


# Define z-tranformation function
#################################

ztransform() {

    img=$1
    mask=$2
    out=$3

    mean=`$singularity_fsl fslstats $img -M | tail -n 1`
    std=`$singularity_fsl fslstats $img -S | tail -n 1`

    $singularity_fsl fslmaths $img -sub $mean -div $std -mul $mask $out

}

# Execute commands
##################

ztransform $MTT_CLEAN $FILTER_MASK $MTT_Z
ztransform $RBF_CLEAN $FILTER_MASK $RBF_Z
ztransform $RBV_CLEAN $FILTER_MASK $RBV_Z
ztransform $EF_CLEAN $FILTER_MASK $EF_Z
ztransform $LEAKAGE_CLEAN $FILTER_MASK $LEAKAGE_Z
ztransform $TMAX_CLEAN $FILTER_MASK $TMAX_Z
ztransform $TMAX_RAPID_CLEAN $FILTER_MASK $TMAX_RAPID_Z

###################################################################################################################
#                                           PART II: STANDARD SPACE                                               #
###################################################################################################################

###########################################
# Registration of FLAIR to standard space #
###########################################

# Define input
##############

FLAIR_BRAIN=$ANAT_DIR/${1}_ses-${SESSION}_desc-preproc_desc-brain_FLAIR.nii.gz

if [ $TEMP_SPACE == "miplab" ];then
    
    TEMPLATE=$ENV_DIR/standard/miplab-flair_asym_brain.nii.gz
    

elif [ $TEMP_SPACE == "brainder" ];then
    
    TEMPLATE=$ENV_DIR/standard/GG-853-FLAIR-1.0mm_brain.nii.gz

fi

# Define output
###############

FLAIR_IN_TEMPLATE=$ANAT_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-preproc_desc-brain_FLAIR.nii.gz
FLAIR2TEMPLATE_WARP=$ANAT_DIR/${1}_ses-${SESSION}_from-FLAIR_to-${TEMP_SPACE}_Composite.h5

# Define command
################

CMD_FLAIR2TEMPLATE="antsRegistration \
    --output [ $ANAT_DIR/${1}_ses-${SESSION}_from-FLAIR_to-${TEMP_SPACE}_, $FLAIR_IN_TEMPLATE ] \
    --collapse-output-transforms 0 \
    --dimensionality 3 \
    --initial-moving-transform [ $TEMPLATE, $FLAIR_BRAIN, 1 ] \
    --initialize-transforms-per-stage 0 \
    --interpolation Linear \
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
    --metric CC[ $TEMPLATE, $FLAIR_BRAIN, 1, 4 ] \
    --convergence [ 100x50x30x20, 1e-08, 10 ] \
    --smoothing-sigmas 3.0x2.0x1.0x0.0vox \
    --shrink-factors 8x4x2x1 \
    --use-estimate-learning-rate-once 1 \
    --use-histogram-matching 1 -v \
    --winsorize-image-intensities [ 0.005, 0.995 ] \
    --write-composite-transform 1"

# Execute command
#################

if [ ! -f $FLAIR2TEMPLATE_WARP ]; then

    $singularity_mrtrix3 $CMD_FLAIR2TEMPLATE

fi

################################################################
# Registration of perfusion images to standard space via FLAIR #
################################################################

# Define input
##############

MTT_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_MTT.nii.gz
RBF_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_rBF.nii.gz
RBV_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_rBV.nii.gz
EF_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_EF.nii.gz
LEAKAGE_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_leakage.nii.gz
TMAX_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_Tmax.nii.gz
TMAX_RAPID_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_desc-RAPID_Tmax.nii.gz

FLAIR_BRAIN=$ANAT_DIR/${1}_ses-${SESSION}_desc-preproc_desc-brain_FLAIR.nii.gz
DSC_2_FLAIR_FSL=$PERF_DIR/${1}_ses-${SESSION}_from-dsc_to-FLAIR_desc-affine.mat
DSC_IN_FLAIR=$PERF_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-moco_desc-brain_baselineSI.nii.gz
FLAIR2TEMPLATE_WARP=$ANAT_DIR/${1}_ses-${SESSION}_from-FLAIR_to-${TEMP_SPACE}_Composite.h5
# TEMPLATE: Defined above

# Define output
###############
MTT_FLAIR=$PERF_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-moco_desc-brain_desc-wocsf_MTT.nii.gz
RBF_FLAIR=$PERF_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-moco_desc-brain_desc-wocsf_rBF.nii.gz
RBV_FLAIR=$PERF_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-moco_desc-brain_desc-wocsf_rBV.nii.gz
EF_FLAIR=$PERF_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-moco_desc-brain_desc-wocsf_EF.nii.gz
LEAKAGE_FLAIR=$PERF_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-moco_desc-brain_desc-wocsf_leakage.nii.gz
TMAX_FLAIR=$PERF_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-moco_desc-brain_desc-wocsf_Tmax.nii.gz
TMAX_RAPID_FLAIR=$PERF_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-moco_desc-brain_desc-wocsf_desc-RAPID_Tmax.nii.gz

BASELINE_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-moco_desc-brain_baselineSI.nii.gz
MTT_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-moco_desc-brain_desc-wocsf_MTT.nii.gz
RBF_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-moco_desc-brain_desc-wocsf_rBF.nii.gz
RBV_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-moco_desc-brain_desc-wocsf_rBV.nii.gz
EF_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-moco_desc-brain_desc-wocsf_EF.nii.gz
LEAKAGE_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-moco_desc-brain_desc-wocsf_leakage.nii.gz
TMAX_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-moco_desc-brain_desc-wocsf_Tmax.nii.gz
TMAX_RAPID_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-moco_desc-brain_desc-wocsf_desc-RAPID_Tmax.nii.gz

# Define commands
#################

CMD_MTT2FLAIR="flirt -in $MTT_CLEAN -ref $FLAIR_BRAIN -applyxfm -init $DSC_2_FLAIR_FSL -out $MTT_FLAIR"
CMD_RBF2FLAIR="flirt -in $RBF_CLEAN -ref $FLAIR_BRAIN -applyxfm -init $DSC_2_FLAIR_FSL -out $RBF_FLAIR"
CMD_RBV2FLAIR="flirt -in $RBV_CLEAN -ref $FLAIR_BRAIN -applyxfm -init $DSC_2_FLAIR_FSL -out $RBV_FLAIR"
CMD_EF2FLAIR="flirt -in $EF_CLEAN -ref $FLAIR_BRAIN -applyxfm -init $DSC_2_FLAIR_FSL -out $EF_FLAIR"
CMD_LEAKAGE2FLAIR="flirt -in $LEAKAGE_CLEAN -ref $FLAIR_BRAIN -applyxfm -init $DSC_2_FLAIR_FSL -out $LEAKAGE_FLAIR"
CMD_TMAX2FLAIR="flirt -in $TMAX_CLEAN -ref $FLAIR_BRAIN -applyxfm -init $DSC_2_FLAIR_FSL -out $TMAX_FLAIR"
CMD_TMAXRAPID2FLAIR="flirt -in $TMAX_RAPID_CLEAN -ref $FLAIR_BRAIN -applyxfm -init $DSC_2_FLAIR_FSL -out $TMAX_RAPID_FLAIR"

CMD_BASELINE2MNI="antsApplyTransforms -d 3 -e 0 -n Linear -i $DSC_IN_FLAIR -r $TEMPLATE -t $FLAIR2TEMPLATE_WARP -o $BASELINE_TEMP"
CMD_MTT2MNI="antsApplyTransforms -d 3 -e 0 -n Linear -i $MTT_FLAIR -r $TEMPLATE -t $FLAIR2TEMPLATE_WARP -o $MTT_TEMP"
CMD_RBF2MNI="antsApplyTransforms -d 3 -e 0 -n Linear -i $RBF_FLAIR -r $TEMPLATE -t $FLAIR2TEMPLATE_WARP -o $RBF_TEMP"
CMD_RBV2MNI="antsApplyTransforms -d 3 -e 0 -n Linear -i $RBV_FLAIR -r $TEMPLATE -t $FLAIR2TEMPLATE_WARP -o $RBV_TEMP"
CMD_EF2MNI="antsApplyTransforms -d 3 -e 0 -n Linear -i $EF_FLAIR -r $TEMPLATE -t $FLAIR2TEMPLATE_WARP -o $EF_TEMP"
CMD_LEAKAGE2MNI="antsApplyTransforms -d 3 -e 0 -n Linear -i $LEAKAGE_FLAIR -r $TEMPLATE -t $FLAIR2TEMPLATE_WARP -o $LEAKAGE_TEMP"
CMD_TMAX2MNI="antsApplyTransforms -d 3 -e 0 -n Linear -i $TMAX_FLAIR -r $TEMPLATE -t $FLAIR2TEMPLATE_WARP -o $TMAX_TEMP"
CMD_TMAXRAPID2MNI="antsApplyTransforms -d 3 -e 0 -n Linear -i $TMAX_RAPID_FLAIR -r $TEMPLATE -t $FLAIR2TEMPLATE_WARP -o $TMAX_RAPID_TEMP"

# Execute commands
##################

$singularity_fsl $CMD_MTT2FLAIR
$singularity_fsl $CMD_RBF2FLAIR
$singularity_fsl $CMD_RBV2FLAIR
$singularity_fsl $CMD_EF2FLAIR
$singularity_fsl $CMD_LEAKAGE2FLAIR
$singularity_fsl $CMD_TMAX2FLAIR
$singularity_fsl $CMD_TMAXRAPID2FLAIR

$singularity_mrtrix3 $CMD_BASELINE2MNI
$singularity_mrtrix3 $CMD_MTT2MNI
$singularity_mrtrix3 $CMD_RBF2MNI
$singularity_mrtrix3 $CMD_RBV2MNI
$singularity_mrtrix3 $CMD_EF2MNI
$singularity_mrtrix3 $CMD_LEAKAGE2MNI
$singularity_mrtrix3 $CMD_TMAX2MNI
$singularity_mrtrix3 $CMD_TMAXRAPID2MNI

###############################################################################
# Registration of brain, lesion and perfusion deficit masks to standard space #
###############################################################################

# Define input
##############

LESION_MASK=$LESION_DIR/${1}_ses-${SESSION}_space-FLAIR_lesionmask.nii.gz
PERF_DEFICIT=$PERF_DIR/${1}_ses-${SESSION}_desc-RAPID_desc-perfusiondeficit_mask.nii.gz
BRAIN_MASK=$ANAT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brain_mask.nii.gz

DSC_2_FLAIR_ITK=$PERF_DIR/${1}_ses-${SESSION}_from-dsc_to-FLAIR_desc-affine.txt
FLAIR_BRAIN=$ANAT_DIR/${1}_ses-${SESSION}_desc-preproc_desc-brain_FLAIR.nii.gz
DSC_2_FLAIR_FSL=$PERF_DIR/${1}_ses-${SESSION}_from-dsc_to-FLAIR_desc-affine.mat
FLAIR2TEMPLATE_WARP=$ANAT_DIR/${1}_ses-${SESSION}_from-FLAIR_to-${TEMP_SPACE}_Composite.h5
# TEMPLATE: Defined above

# Define output
###############

LESION_TEMP_PROB=$ANAT_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-prob_desc-lesion_mask.nii.gz
LESION_TEMP=$ANAT_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-lesion_mask.nii.gz
LESION_TEMP_INV=$ANAT_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-lesion_desc-inverted_mask.nii.gz
PERF_FLAIR=$PERF_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-RAPID_desc-perfusiondeficit_mask.nii.gz
PERF_TEMP_PROB=$PERF_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-RAPID_desc-prob_desc-perfusiondeficit_mask.nii.gz
PERF_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-RAPID_desc-perfusiondeficit_mask.nii.gz
PERF_TEMP_INV=$PERF_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-RAPID_desc-perfusiondeficit_desc-inverted_mask.nii.gz
BRAIN_TEMP_PROB=$ANAT_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-prob_desc-brain_mask.nii.gz
BRAIN_TEMP=$ANAT_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-brain_mask.nii.gz

# Define commands
#################

CMD_LESION2TEMP="antsApplyTransforms -d 3 -e 0 -n Linear -i $LESION_MASK -r $TEMPLATE -t $FLAIR2TEMPLATE_WARP -o $LESION_TEMP_PROB"
CMD_THRESH_LESION="fslmaths $LESION_TEMP_PROB -thr 0.80 -bin $LESION_TEMP"
CMD_LESION_TEMP_INV="fslmaths $LESION_TEMP -binv $LESION_TEMP_INV"

CMD_BRAIN2TEMP="antsApplyTransforms -d 3 -e 0 -n Linear -i $BRAIN_MASK -r $TEMPLATE -t $FLAIR2TEMPLATE_WARP -o $BRAIN_TEMP_PROB"
CMD_THRESH_BRAIN="fslmaths $BRAIN_TEMP_PROB -thr 0.90 -bin $BRAIN_TEMP"

CMD_PERF2FLAIR="flirt -in $PERF_DEFICIT -ref $FLAIR_BRAIN -applyxfm -init $DSC_2_FLAIR_FSL -out $PERF_FLAIR"
CMD_PERF2TEMP="antsApplyTransforms -d 3 -e 0 -n Linear -i $PERF_FLAIR -r $TEMPLATE -t $FLAIR2TEMPLATE_WARP -o $PERF_TEMP_PROB"
CMD_THRESH_PERF="fslmaths $PERF_TEMP_PROB -thr 0.6 -bin $PERF_TEMP"
CMD_PERF_TEMP_INV="fslmaths $PERF_TEMP -binv $PERF_TEMP_INV"

# Execute commands
##################

$singularity_mrtrix3 $CMD_LESION2TEMP
$singularity_fsl $CMD_THRESH_LESION
$singularity_fsl $CMD_LESION_TEMP_INV

$singularity_mrtrix3 $CMD_BRAIN2TEMP
$singularity_fsl $CMD_THRESH_BRAIN

$singularity_fsl $CMD_PERF2FLAIR
$singularity_mrtrix3 $CMD_PERF2TEMP
$singularity_fsl $CMD_THRESH_PERF
$singularity_fsl $CMD_PERF_TEMP_INV


##########################################
# Create penumbra mask in standard space #
##########################################

# Define input
##############

PERF_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-RAPID_desc-perfusiondeficit_mask.nii.gz
LESION_TEMP=$ANAT_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-lesion_mask.nii.gz

# Define output
###############

PENUMBRA_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-RAPID_desc-penumbra_mask.nii.gz


# Define command
################

CMD_PENUMBRA_TEMP="fslmaths $PERF_TEMP -sub $LESION_TEMP -thr 1 $PENUMBRA_TEMP"

# Execute command
#################

$singularity_fsl $CMD_PENUMBRA_TEMP

##########################################################
# Z-transformation of perfusion images in standard space #
##########################################################

# Define input
##############

MTT_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-moco_desc-brain_desc-wocsf_MTT.nii.gz
RBF_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-moco_desc-brain_desc-wocsf_rBF.nii.gz
RBV_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-moco_desc-brain_desc-wocsf_rBV.nii.gz
EF_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-moco_desc-brain_desc-wocsf_EF.nii.gz
LEAKAGE_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-moco_desc-brain_desc-wocsf_leakage.nii.gz
TMAX_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-moco_desc-brain_desc-wocsf_Tmax.nii.gz
TMAX_RAPID_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-moco_desc-brain_desc-wocsf_Tmax.nii.gz

BRAIN_TEMP=$ANAT_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-brain_mask.nii.gz

# Define output
###############

MTT_Z_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-moco_desc-brain_desc-wocsf_MTTz.nii.gz
RBF_Z_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-moco_desc-brain_desc-wocsf_rBFz.nii.gz
RBV_Z_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-moco_desc-brain_desc-wocsf_rBVz.nii.gz
EF_Z_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-moco_desc-brain_desc-wocsf_EFz.nii.gz
LEAKAGE_Z_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-moco_desc-brain_desc-wocsf_leakagez.nii.gz
TMAX_Z_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-moco_desc-brain_desc-wocsf_Tmaxz.nii.gz
TMAX_RAPID_Z_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-moco_desc-brain_desc-wocsf_desc-RAPID_Tmaxz.nii.gz

# Execute commands
##################

ztransform $MTT_TEMP $BRAIN_TEMP $MTT_Z_TEMP
ztransform $RBF_TEMP $BRAIN_TEMP $RBF_Z_TEMP
ztransform $RBV_TEMP $BRAIN_TEMP $RBV_Z_TEMP
ztransform $EF_TEMP $BRAIN_TEMP $EF_Z_TEMP
ztransform $LEAKAGE_TEMP $BRAIN_TEMP $LEAKAGE_Z_TEMP
ztransform $TMAX_TEMP $BRAIN_TEMP $TMAX_Z_TEMP
ztransform $TMAX_RAPID_TEMP $BRAIN_TEMP $TMAX_RAPID_Z_TEMP


###################################################################################################################
#                                  PART III/A: READ-OUT LESION/PEFUSION DEFICIT MASKS                               #
###################################################################################################################

if [ $TEMP_SPACE == "miplab" ];then

    ##############
    # Create CSV #
    ##############

    CSV=$PERF_DIR/${1}_ses-${SESSION}_perfusion.csv

    echo -e "sub_id,nice_lesion_mean_mtt,nice_lesion_mean_rbf,nice_lesion_mean_rbv,nice_lesion_mean_ef,nice_lesion_mean_leakage,nice_lesion_mean_tmax,nice_lesion_mean_tmax_rapid,\
    nice_lesion_z_mtt,nice_lesion_z_rbf,nice_lesion_z_rbv,nice_lesion_z_ef,nice_lesion_z_leakage,nice_lesion_z_tmax,nice_lesion_z_tmax_rapid,\
    nice_penumbra_mean_mtt,nice_penumbra_mean_rbf,nice_penumbra_mean_rbv,nice_penumbra_mean_ef,nice_penumbra_mean_leakage,nice_penumbra_mean_tmax,nice_penumbra_mean_tmax_rapid,\
    nice_penumbra_z_mtt,nice_penumbra_z_rbf,nice_penumbra_z_rbv,nice_penumbra_z_ef,nice_penumbra_z_leakage,nice_penumbra_z_tmax,nice_penumbra_z_tmax_rapid,\
    nice_penumbra_infarct_mean_mtt,nice_penumbra_infarct_mean_rbf,nice_penumbra_infarct_mean_rbv,nice_penumbra_infarct_mean_ef,nice_penumbra_infarct_mean_leakage,nice_penumbra_infarct_mean_tmax,nice_penumbra_infarct_mean_tmax_rapid,\
    nice_penumbra_infarct_z_mtt,nice_penumbra_infarct_z_rbf,nice_penumbra_infarct_z_rbv,nice_penumbra_infarct_z_ef,nice_penumbra_infarct_z_leakage,nice_penumbra_infarct_z_tmax,nice_penumbra_infarct_z_tmax_rapid,\
    nice_penumbra_noinfarct_mean_mtt,nice_penumbra_noinfarct_mean_rbf,nice_penumbra_noinfarct_mean_rbv,nice_penumbra_noinfarct_mean_ef,nice_penumbra_noinfarct_mean_leakage,nice_penumbra_noinfarct_mean_tmax,nice_penumbra_noinfarct_mean_tmax_rapid,\
    nice_penumbra_noinfarct_z_mtt,nice_penumbra_noinfarct_z_rbf,nice_penumbra_noinfarct_z_rbv,nice_penumbra_noinfarct_z_ef,nice_penumbra_noinfarct_z_leakage,nice_penumbra_noinfarct_z_tmax,nice_penumbra_noinfarct_z_tmax_rapid,\
    nice_penumbra_noreflow_mean_mtt,nice_penumbra_noreflow_mean_rbf,nice_penumbra_noreflow_mean_rbv,nice_penumbra_noreflow_mean_ef,nice_penumbra_noreflow_mean_leakage,nice_penumbra_noreflow_mean_tmax,nice_penumbra_noreflow_mean_tmax_rapid,\
    nice_penumbra_noreflow_z_mtt,nice_penumbra_noreflow_z_rbf,nice_penumbra_noreflow_z_rbv,nice_penumbra_noreflow_z_ef,nice_penumbra_noreflow_z_leakage,nice_penumbra_noreflow_z_tmax,nice_penumbra_noreflow_z_tmax_rapid,\
    nice_penumbra_reflow_mean_mtt,nice_penumbra_reflow_mean_rbf,nice_penumbra_reflow_mean_rbv,nice_penumbra_reflow_mean_ef,nice_penumbra_reflow_mean_leakage,nice_penumbra_reflow_mean_tmax,nice_penumbra_reflow_mean_tmax_rapid,\
    nice_penumbra_reflow_z_mtt,nice_penumbra_reflow_z_rbf,nice_penumbra_reflow_z_rbv,nice_penumbra_reflow_z_ef,nice_penumbra_reflow_z_leakage,nice_penumbra_reflow_z_tmax,nice_penumbra_reflow_z_tmax_rapid,\
    nice_tmax6_mean_ef,nice_tmax6_z_ef,nice_tmax8_mean_ef,nice_tmax8_z_ef,nice_tmax10_mean_ef,nice_tmax10_z_ef,\
    nice_normal_mean_mtt,nice_normal_mean_rbf,nice_normal_mean_rbv,nice_normal_mean_ef,nice_normal_mean_leakage,nice_normal_mean_tmax,nice_normal_mean_tmax_rapid,\
    nice_normal_z_mtt,nice_normal_z_rbf,nice_normal_z_rbv,nice_normal_z_ef,nice_normal_z_leakage,nice_normal_z_tmax,nice_normal_z_tmax_rapid,\
    nice_focal_normal_ef,nice_focal_normal_z_ef,\
    nice_focal_lesion_ef,nice_focal_lesion_z_ef,\
    nice_focal_penumbra_ef,nice_focal_penumbra_z_ef,\
    nice_focal_penumbra_infarct_ef,nice_focal_penumbra_infarct_z_ef,\
    nice_focal_penumbra_noinfarct_ef,nice_focal_penumbra_noinfarct_z_ef,\
    nice_focal_penumbra_noreflow_ef,nice_focal_penumbra_noreflow_z_ef,\
    nice_focal_penumbra_reflow_ef,nice_focal_penumbra_reflow_z_ef,\
    nice_focal_tmax6_ef,nice_focal_tmax6_z_ef,\
    nice_focal_tmax8_ef,nice_focal_tmax8_z_ef,\
    nice_focal_tmax10_ef,nice_focal_tmax10_z_ef" > $CSV

    ####################
    # Read-out of ROIs #
    ####################

    # Define input
    ##############

    MTT_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_MTT.nii.gz
    RBF_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_rBF.nii.gz
    RBV_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_rBV.nii.gz
    EF_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_EF.nii.gz
    LEAKAGE_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_leakage.nii.gz
    TMAX_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_Tmax.nii.gz
    TMAX_RAPID_CLEAN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_desc-RAPID_Tmax.nii.gz

    MTT_Z=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_MTTz.nii.gz
    RBF_Z=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_rBFz.nii.gz
    RBV_Z=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_rBVz.nii.gz
    EF_Z=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_EFz.nii.gz
    LEAKAGE_Z=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_leakagez.nii.gz
    TMAX_Z=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_Tmaxz.nii.gz
    TMAX_RAPID_Z=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-wocsf_desc-RAPID_Tmaxz.nii.gz

    PERF_DEFICIT_INV=$PERF_DIR/${1}_ses-${SESSION}_desc-RAPID_desc-perfusiondeficit_desc-inverted_mask.nii.gz
    PENUMBRA=$PERF_DIR/${1}_ses-${SESSION}_desc-RAPID_desc-penumbra_mask.nii.gz
    PENUMBRA_NOINFARCT=$PERF_DIR/${1}_ses-${SESSION}_desc-RAPID_desc-penumbra_desc-noinfarct_mask.nii.gz
    PENUMBRA_INFARCT=$PERF_DIR/${1}_ses-${SESSION}_desc-RAPID_desc-penumbra_desc-infarct_mask.nii.gz
    
    PENUMBRA_NOREFLOW=$PERF_DIR/${1}_ses-${SESSION}_desc-RAPID_desc-penumbra_desc-noreflow_mask.nii.gz
    PENUMBRA_REFLOW=$PERF_DIR/${1}_ses-${SESSION}_desc-RAPID_desc-penumbra_desc-reflow_mask.nii.gz

    PERF_DEFICIT_6=$PERF_DIR/${1}_ses-${SESSION}_desc-RAPID_desc-Tmax6_mask.nii.gz
    PERF_DEFICIT_8=$PERF_DIR/${1}_ses-${SESSION}_desc-RAPID_desc-Tmax8_mask.nii.gz
    PERF_DEFICIT_10=$PERF_DIR/${1}_ses-${SESSION}_desc-RAPID_desc-Tmax10_mask.nii.gz
    LESION_MASK_DSC=$ANAT_DIR/${1}_ses-${SESSION}_space-dsc_desc-lesion_mask.nii.gz
    LESION_MASK_DSC_INV=$ANAT_DIR/${1}_ses-${SESSION}_space-dsc_desc-lesion_desc-inverted_mask.nii.gz


    # Define function which extracts mean of ROI
    ############################################

    extractmean() {

        img=$1
        roi=$2
        mod=$3

        test=`$singularity_fsl fslstats $roi -M | tail -n 1`

        if [ $test != "0.000000" ]; then

            $singularity_fsl fslmaths $img -mul $roi $TMP_OUT/${mod}_mean_tmp > /dev/null 2>&1
            mean=`$singularity_fsl fslstats $TMP_OUT/${mod}_mean_tmp -M | tail -n 1`
        
        else

            mean="NaN"
        
        fi
        
        echo $mean

    }


    # Define function which extracts mean after exluding areas of lesion and perfusion deficit
    ##########################################################################################

    extractmean_normal() {

        img=$1
        lesion_inv=$2
        perfdef_inv=$3
        mod=$4

        $singularity_fsl fslmaths $img -mul $lesion_inv -mul $perfdef_inv $TMP_OUT/${mod}_mean_tmp > /dev/null 2>&1
        mean=`$singularity_fsl fslstats $TMP_OUT/${mod}_mean_tmp -M | tail -n 1`
        
        echo $mean

    }

    # Define function which extracts "focal" permeability derangement as the 95th percentile of voxels 
    # within the ROI 
    ##################################################################################################

    extract_focal() {

        img=$1
        lesion_inv=$2
        perfdef_inv=$3
        mod=$4
        lesion=$5
        penumbra=$6

        $singularity_fsl fslmaths $img -mul $lesion_inv -mul $perfdef_inv $TMP_OUT/${mod}_normal_tmp > /dev/null 2>&1

        focal_normal=`$singularity_fsl fslstats $TMP_OUT/${mod}_normal_tmp -P 95 | tail -n 1`
        focal_lesion=`$singularity_fsl fslstats $img -k $lesion -P 95 | tail -n 1`
        focal_penumbra=`$singularity_fsl fslstats $img -k $penumbra -P 95 | tail -n 1`

        
        echo $focal_normal
        echo $focal_lesion

        test=`$singularity_fsl fslstats $penumbra -M | tail -n 1`

        if [ $test != "0.000000" ]; then
         
            focal_penumbra=$focal_penumbra;
        
        else 
            
            focal_penumbra="NaN"
        
        fi

        echo $focal_penumbra
    }

    # Extract means
    ###############

    # Lesion
    lesion_mtt=`extractmean $MTT_CLEAN $LESION_MASK_DSC mtt_lesion`
    lesion_rbf=`extractmean $RBF_CLEAN $LESION_MASK_DSC rbf_lesion`
    lesion_rbv=`extractmean $RBV_CLEAN $LESION_MASK_DSC rbv_lesion`
    lesion_ef=`extractmean $EF_CLEAN $LESION_MASK_DSC ef_lesion`
    lesion_leakage=`extractmean $LEAKAGE_CLEAN $LESION_MASK_DSC leakage_lesion`
    lesion_tmax=`extractmean $TMAX_CLEAN $LESION_MASK_DSC tmax_lesion`
    lesion_tmax_rapid=`extractmean $TMAX_RAPID_CLEAN $LESION_MASK_DSC tmax_rapid_lesion`

    lesion_z_mtt=`extractmean $MTT_Z $LESION_MASK_DSC mttz_lesion`
    lesion_z_rbf=`extractmean $RBF_Z $LESION_MASK_DSC rbfz_lesion`
    lesion_z_rbv=`extractmean $RBV_Z $LESION_MASK_DSC rbvz_lesion`
    lesion_z_ef=`extractmean $EF_Z $LESION_MASK_DSC efz_lesion`
    lesion_z_leakage=`extractmean $LEAKAGE_Z $LESION_MASK_DSC leakagez_lesion`
    lesion_z_tmax=`extractmean $TMAX_Z $LESION_MASK_DSC tmaxz_lesion`
    lesion_z_tmax_rapid=`extractmean $TMAX_RAPID_Z $LESION_MASK_DSC tmaxz_rapid_lesion`

    # Penumbra
    penumbra_mtt=`extractmean $MTT_CLEAN $PENUMBRA mtt_penumbra`
    penumbra_rbf=`extractmean $RBF_CLEAN $PENUMBRA rbf_penumbra`
    penumbra_rbv=`extractmean $RBV_CLEAN $PENUMBRA rbv_penumbra`
    penumbra_ef=`extractmean $EF_CLEAN $PENUMBRA ef_penumbra`
    penumbra_leakage=`extractmean $LEAKAGE_CLEAN $PENUMBRA leakage_penumbra`
    penumbra_tmax=`extractmean $TMAX_CLEAN $PENUMBRA tmax_penumbra`
    penumbra_tmax_rapid=`extractmean $TMAX_RAPID_CLEAN $PENUMBRA tmax_rapid_penumbra`

    penumbra_z_mtt=`extractmean $MTT_Z $PENUMBRA mttz_penumbra`
    penumbra_z_rbf=`extractmean $RBF_Z $PENUMBRA rbfz_penumbra`
    penumbra_z_rbv=`extractmean $RBV_Z $PENUMBRA rbvz_penumbra`
    penumbra_z_ef=`extractmean $EF_Z $PENUMBRA efz_penumbra`
    penumbra_z_leakage=`extractmean $LEAKAGE_Z $PENUMBRA leakagez_penumbra`
    penumbra_z_tmax=`extractmean $TMAX_Z $PENUMBRA tmaxz_penumbra`
    penumbra_z_tmax_rapid=`extractmean $TMAX_RAPID_Z $PENUMBRA tmaxz_rapid_penumbra`

    if [[ $MODIFIER == "yes" && $SESSION == "1" ]]; then

        # Penumbra - infarct
        penumbra_infarct_mtt=`extractmean $MTT_CLEAN $PENUMBRA_INFARCT mtt_penumbra_infarct`
        penumbra_infarct_rbf=`extractmean $RBF_CLEAN $PENUMBRA_INFARCT rbf_penumbra_infarct`
        penumbra_infarct_rbv=`extractmean $RBV_CLEAN $PENUMBRA_INFARCT rbv_penumbra_infarct`
        penumbra_infarct_ef=`extractmean $EF_CLEAN $PENUMBRA_INFARCT ef_penumbra_infarct`
        penumbra_infarct_leakage=`extractmean $LEAKAGE_CLEAN $PENUMBRA_INFARCT leakage_penumbra_infarct`
        penumbra_infarct_tmax=`extractmean $TMAX_CLEAN $PENUMBRA_INFARCT tmax_penumbra_infarct`
        penumbra_infarct_tmax_rapid=`extractmean $TMAX_RAPID_CLEAN $PENUMBRA_INFARCT tmax_rapid_penumbra_infarct`

        penumbra_infarct_z_mtt=`extractmean $MTT_Z $PENUMBRA_INFARCT mttz_penumbra_infarct`
        penumbra_infarct_z_rbf=`extractmean $RBF_Z $PENUMBRA_INFARCT rbfz_penumbra_infarct`
        penumbra_infarct_z_rbv=`extractmean $RBV_Z $PENUMBRA_INFARCT rbvz_penumbra_infarct`
        penumbra_infarct_z_ef=`extractmean $EF_Z $PENUMBRA_INFARCT efz_penumbra_infarct`
        penumbra_infarct_z_leakage=`extractmean $LEAKAGE_Z $PENUMBRA_INFARCT leakagez_penumbra_infarct`
        penumbra_infarct_z_tmax=`extractmean $TMAX_Z $PENUMBRA_INFARCT tmaxz_penumbra_infarct`
        penumbra_infarct_z_tmax_rapid=`extractmean $TMAX_RAPID_Z $PENUMBRA_INFARCT tmaxz_rapid_penumbra_infarct`

        # Penumbra - no infarct
        penumbra_noinfarct_mtt=`extractmean $MTT_CLEAN $PENUMBRA_NOINFARCT mtt_penumbra_noinfarct`
        penumbra_noinfarct_rbf=`extractmean $RBF_CLEAN $PENUMBRA_NOINFARCT rbf_penumbra_noinfarct`
        penumbra_noinfarct_rbv=`extractmean $RBV_CLEAN $PENUMBRA_NOINFARCT rbv_penumbra_noinfarct`
        penumbra_noinfarct_ef=`extractmean $EF_CLEAN $PENUMBRA_NOINFARCT ef_penumbra_noinfarct`
        penumbra_noinfarct_leakage=`extractmean $LEAKAGE_CLEAN $PENUMBRA_NOINFARCT leakage_penumbra_noinfarct`
        penumbra_noinfarct_tmax=`extractmean $TMAX_CLEAN $PENUMBRA_NOINFARCT tmax_penumbra_noinfarct`
        penumbra_noinfarct_tmax_rapid=`extractmean $TMAX_RAPID_CLEAN $PENUMBRA_NOINFARCT tmax_rapid_penumbra_noinfarct`

        penumbra_noinfarct_z_mtt=`extractmean $MTT_Z $PENUMBRA_NOINFARCT mttz_penumbra_noinfarct`
        penumbra_noinfarct_z_rbf=`extractmean $RBF_Z $PENUMBRA_NOINFARCT rbfz_penumbra_noinfarct`
        penumbra_noinfarct_z_rbv=`extractmean $RBV_Z $PENUMBRA_NOINFARCT rbvz_penumbra_noinfarct`
        penumbra_noinfarct_z_ef=`extractmean $EF_Z $PENUMBRA_NOINFARCT efz_penumbra_noinfarct`
        penumbra_noinfarct_z_leakage=`extractmean $LEAKAGE_Z $PENUMBRA_NOINFARCT leakagez_penumbra_noinfarct`
        penumbra_noinfarct_z_tmax=`extractmean $TMAX_Z $PENUMBRA_NOINFARCT tmaxz_penumbra_noinfarct`
        penumbra_noinfarct_z_tmax_rapid=`extractmean $TMAX_RAPID_Z $PENUMBRA_NOINFARCT tmaxz_rapid_penumbra_noinfarct`

        # Penumbra - no reflow
        penumbra_noreflow_mtt=`extractmean $MTT_CLEAN $PENUMBRA_NOREFLOW mtt_penumbra_noreflow`
        penumbra_noreflow_rbf=`extractmean $RBF_CLEAN $PENUMBRA_NOREFLOW rbf_penumbra_noreflow`
        penumbra_noreflow_rbv=`extractmean $RBV_CLEAN $PENUMBRA_NOREFLOW rbv_penumbra_noreflow`
        penumbra_noreflow_ef=`extractmean $EF_CLEAN $PENUMBRA_NOREFLOW ef_penumbra_noreflow`
        penumbra_noreflow_leakage=`extractmean $LEAKAGE_CLEAN $PENUMBRA_NOREFLOW leakage_penumbra_noreflow`
        penumbra_noreflow_tmax=`extractmean $TMAX_CLEAN $PENUMBRA_NOREFLOW tmax_penumbra_noreflow`
        penumbra_noreflow_tmax_rapid=`extractmean $TMAX_RAPID_CLEAN $PENUMBRA_NOREFLOW tmax_rapid_penumbra_noreflow`

        penumbra_noreflow_z_mtt=`extractmean $MTT_Z $PENUMBRA_NOREFLOW mttz_penumbra_noreflow`
        penumbra_noreflow_z_rbf=`extractmean $RBF_Z $PENUMBRA_NOREFLOW rbfz_penumbra_noreflow`
        penumbra_noreflow_z_rbv=`extractmean $RBV_Z $PENUMBRA_NOREFLOW rbvz_penumbra_noreflow`
        penumbra_noreflow_z_ef=`extractmean $EF_Z $PENUMBRA_NOREFLOW efz_penumbra_noreflow`
        penumbra_noreflow_z_leakage=`extractmean $LEAKAGE_Z $PENUMBRA_NOREFLOW leakagez_penumbra_noreflow`
        penumbra_noreflow_z_tmax=`extractmean $TMAX_Z $PENUMBRA_NOREFLOW tmaxz_penumbra_noreflow`
        penumbra_noreflow_z_tmax_rapid=`extractmean $TMAX_RAPID_Z $PENUMBRA_NOREFLOW tmaxz_rapid_penumbra_noreflow`
        
        # Penumbra - reflow
        penumbra_reflow_mtt=`extractmean $MTT_CLEAN $PENUMBRA_REFLOW mtt_penumbra_reflow`
        penumbra_reflow_rbf=`extractmean $RBF_CLEAN $PENUMBRA_REFLOW rbf_penumbra_reflow`
        penumbra_reflow_rbv=`extractmean $RBV_CLEAN $PENUMBRA_REFLOW rbv_penumbra_reflow`
        penumbra_reflow_ef=`extractmean $EF_CLEAN $PENUMBRA_REFLOW ef_penumbra_reflow`
        penumbra_reflow_leakage=`extractmean $LEAKAGE_CLEAN $PENUMBRA_REFLOW leakage_penumbra_reflow`
        penumbra_reflow_tmax=`extractmean $TMAX_CLEAN $PENUMBRA_REFLOW tmax_penumbra_reflow`
        penumbra_reflow_tmax_rapid=`extractmean $TMAX_RAPID_CLEAN $PENUMBRA_REFLOW tmax_rapid_penumbra_reflow`

        penumbra_reflow_z_mtt=`extractmean $MTT_Z $PENUMBRA_REFLOW mttz_penumbra_reflow`
        penumbra_reflow_z_rbf=`extractmean $RBF_Z $PENUMBRA_REFLOW rbfz_penumbra_reflow`
        penumbra_reflow_z_rbv=`extractmean $RBV_Z $PENUMBRA_REFLOW rbvz_penumbra_reflow`
        penumbra_reflow_z_ef=`extractmean $EF_Z $PENUMBRA_REFLOW efz_penumbra_reflow`
        penumbra_reflow_z_leakage=`extractmean $LEAKAGE_Z $PENUMBRA_REFLOW leakagez_penumbra_reflow`
        penumbra_reflow_z_tmax=`extractmean $TMAX_Z $PENUMBRA_REFLOW tmaxz_penumbra_reflow`
        penumbra_reflow_z_tmax_rapid=`extractmean $TMAX_RAPID_Z $PENUMBRA_REFLOW tmaxz_rapid_penumbra_reflow`
    
    fi
    
    # EF for Tmax 6, 8, 10 s areas
    tmax6_ef=`extractmean $EF_CLEAN $PERF_DEFICIT_6 ef_6`
    tmax8_ef=`extractmean $EF_CLEAN $PERF_DEFICIT_8 ef_8`
    tmax10_ef=`extractmean $EF_CLEAN $PERF_DEFICIT_10 ef_10`

    tmax6_z_ef=`extractmean $EF_Z $PERF_DEFICIT_6 efz_6`
    tmax8_z_ef=`extractmean $EF_Z $PERF_DEFICIT_8 efz_8`
    tmax10_z_ef=`extractmean $EF_Z $PERF_DEFICIT_10 efz_10`

    # Normal areas (excluding lesion and perfusion deficit)
    normal_mtt=`extractmean_normal $MTT_CLEAN $LESION_MASK_DSC_INV $PERF_DEFICIT_INV mtt_normal`
    normal_rbf=`extractmean_normal $RBF_CLEAN $LESION_MASK_DSC_INV $PERF_DEFICIT_INV rbf_normal`
    normal_rbv=`extractmean_normal $RBV_CLEAN $LESION_MASK_DSC_INV $PERF_DEFICIT_INV rbv_normal`
    normal_ef=`extractmean_normal $EF_CLEAN $LESION_MASK_DSC_INV $PERF_DEFICIT_INV ef_normal`
    normal_leakage=`extractmean_normal $LEAKAGE_CLEAN $LESION_MASK_DSC_INV $PERF_DEFICIT_INV leakage_normal`
    normal_tmax=`extractmean_normal $TMAX_CLEAN $LESION_MASK_DSC_INV $PERF_DEFICIT_INV tmax_normal`
    normal_tmax_rapid=`extractmean_normal $TMAX_RAPID_CLEAN $LESION_MASK_DSC_INV $PERF_DEFICIT_INV tmax_rapid_normal`

    normal_z_mtt=`extractmean_normal $MTT_Z $LESION_MASK_DSC_INV $PERF_DEFICIT_INV mttz_normal`
    normal_z_rbf=`extractmean_normal $RBF_Z $LESION_MASK_DSC_INV $PERF_DEFICIT_INV rbfz_normal`
    normal_z_rbv=`extractmean_normal $RBV_Z $LESION_MASK_DSC_INV $PERF_DEFICIT_INV rbvz_normal`
    normal_z_ef=`extractmean_normal $EF_Z $LESION_MASK_DSC_INV $PERF_DEFICIT_INV efz_normal`
    normal_z_leakage=`extractmean_normal $LEAKAGE_Z $LESION_MASK_DSC_INV $PERF_DEFICIT_INV leakagez_normal`
    normal_z_tmax=`extractmean_normal $TMAX_Z $LESION_MASK_DSC_INV $PERF_DEFICIT_INV tmaxz_normal`
    normal_z_tmax_rapid=`extractmean_normal $TMAX_RAPID_Z $LESION_MASK_DSC_INV $PERF_DEFICIT_INV tmaxz_rapid_normal`

    # Extract focal blood-brain barrier leakage values
    ##################################################

    # Normal areas (excluding lesion and perfusion deficit)
    normal_focal_ef=`extract_focal $EF_CLEAN $LESION_MASK_DSC_INV $PERF_DEFICIT_INV ef_normal $LESION_MASK_DSC $PENUMBRA | tail -n 3 | head -n 1`
    normal_focal_z_ef=`extract_focal $EF_Z $LESION_MASK_DSC_INV $PERF_DEFICIT_INV efz_normal $LESION_MASK_DSC $PENUMBRA | tail -n 3 | head -n 1`

    # Lesion 
    lesion_focal_ef=`extract_focal $EF_CLEAN $LESION_MASK_DSC_INV $PERF_DEFICIT_INV ef_normal $LESION_MASK_DSC $PENUMBRA | tail -n 2 | head -n 1`
    lesion_focal_z_ef=`extract_focal $EF_Z $LESION_MASK_DSC_INV $PERF_DEFICIT_INV efz_normal $LESION_MASK_DSC $PENUMBRA | tail -n 2 | head -n 1`

    # Penumbra  
    penumbra_focal_ef=`extract_focal $EF_CLEAN $LESION_MASK_DSC_INV $PERF_DEFICIT_INV ef_normal $LESION_MASK_DSC $PENUMBRA | tail -n 1`
    penumbra_focal_z_ef=`extract_focal $EF_Z $LESION_MASK_DSC_INV $PERF_DEFICIT_INV efz_normal $LESION_MASK_DSC $PENUMBRA | tail -n 1`

    if [[ $MODIFIER == "yes" && $SESSION == "1" ]]; then

        # Penumbra - infarct
        penumbra_infarct_focal_ef=`extract_focal $EF_CLEAN $LESION_MASK_DSC_INV $PERF_DEFICIT_INV ef_normal $LESION_MASK_DSC $PENUMBRA_INFARCT | tail -n 1`
        penumbra_infarct_focal_z_ef=`extract_focal $EF_Z $LESION_MASK_DSC_INV $PERF_DEFICIT_INV efz_normal $LESION_MASK_DSC $PENUMBRA_INFARCT | tail -n 1`

        # Penumbra - no infarct
        penumbra_noinfarct_focal_ef=`extract_focal $EF_CLEAN $LESION_MASK_DSC_INV $PERF_DEFICIT_INV ef_normal $LESION_MASK_DSC $PENUMBRA_NOINFARCT | tail -n 1`
        penumbra_noinfarct_focal_z_ef=`extract_focal $EF_Z $LESION_MASK_DSC_INV $PERF_DEFICIT_INV efz_normal $LESION_MASK_DSC $PENUMBRA_NOINFARCT | tail -n 1`

        # Penumbra - noreflow
        penumbra_noreflow_focal_ef=`extract_focal $EF_CLEAN $LESION_MASK_DSC_INV $PERF_DEFICIT_INV ef_normal $LESION_MASK_DSC $PENUMBRA_NOREFLOW | tail -n 1`
        penumbra_noreflow_focal_z_ef=`extract_focal $EF_Z $LESION_MASK_DSC_INV $PERF_DEFICIT_INV efz_normal $LESION_MASK_DSC $PENUMBRA_NOREFLOW | tail -n 1`

        # Penumbra - reflow
        penumbra_reflow_focal_ef=`extract_focal $EF_CLEAN $LESION_MASK_DSC_INV $PERF_DEFICIT_INV ef_normal $LESION_MASK_DSC $PENUMBRA_REFLOW | tail -n 1`
        penumbra_reflow_focal_z_ef=`extract_focal $EF_Z $LESION_MASK_DSC_INV $PERF_DEFICIT_INV efz_normal $LESION_MASK_DSC $PENUMBRA_REFLOW | tail -n 1`

    fi

    # Perfusion deficit 6-8 s 
    tmax6_focal_ef=`extract_focal $EF_CLEAN $LESION_MASK_DSC_INV $PERF_DEFICIT_INV ef_normal $LESION_MASK_DSC $PERF_DEFICIT_6 | tail -n 1`
    tmax6_focal_z_ef=`extract_focal $EF_Z $LESION_MASK_DSC_INV $PERF_DEFICIT_INV efz_normal $LESION_MASK_DSC $PERF_DEFICIT_6 | tail -n 1`

    # Perfusion deficit 8-10 s  
    tmax8_focal_ef=`extract_focal $EF_CLEAN $LESION_MASK_DSC_INV $PERF_DEFICIT_INV ef_normal $LESION_MASK_DSC $PERF_DEFICIT_8 | tail -n 1`
    tmax8_focal_z_ef=`extract_focal $EF_Z $LESION_MASK_DSC_INV $PERF_DEFICIT_INV efz_normal $LESION_MASK_DSC $PERF_DEFICIT_8 | tail -n 1`

    # Perfusion deficit >10s
    tmax10_focal_ef=`extract_focal $EF_CLEAN $LESION_MASK_DSC_INV $PERF_DEFICIT_INV ef_normal $LESION_MASK_DSC $PERF_DEFICIT_10 | tail -n 1`
    tmax10_focal_z_ef=`extract_focal $EF_Z $LESION_MASK_DSC_INV $PERF_DEFICIT_INV efz_normal $LESION_MASK_DSC $PERF_DEFICIT_10 | tail -n 1`

    # Append to CSV
    ###############

    echo -e "$1,$lesion_mtt,$lesion_rbf,$lesion_rbv,$lesion_ef,$lesion_leakage,$lesion_tmax,$lesion_tmax_rapid,\
    $lesion_z_mtt,$lesion_z_rbf,$lesion_z_rbv,$lesion_z_ef,$lesion_z_leakage,$lesion_z_tmax,$lesion_z_tmax_rapid,\
    $penumbra_mtt,$penumbra_rbf,$penumbra_rbv,$penumbra_ef,$penumbra_leakage,$penumbra_tmax,$penumbra_tmax_rapid,\
    $penumbra_z_mtt,$penumbra_z_rbf,$penumbra_z_rbv,$penumbra_z_ef,$penumbra_z_leakage,$penumbra_z_tmax,$penumbra_z_tmax_rapid,\
    $penumbra_infarct_mtt,$penumbra_infarct_rbf,$penumbra_infarct_rbv,$penumbra_infarct_ef,$penumbra_infarct_leakage,$penumbra_infarct_tmax,$penumbra_infarct_tmax_rapid,\
    $penumbra_infarct_z_mtt,$penumbra_infarct_z_rbf,$penumbra_infarct_z_rbv,$penumbra_infarct_z_ef,$penumbra_infarct_z_leakage,$penumbra_infarct_z_tmax,$penumbra_infarct_z_tmax_rapid,\
    $penumbra_noinfarct_mtt,$penumbra_noinfarct_rbf,$penumbra_noinfarct_rbv,$penumbra_noinfarct_ef,$penumbra_noinfarct_leakage,$penumbra_noinfarct_tmax,$penumbra_noinfarct_tmax_rapid,\
    $penumbra_noinfarct_z_mtt,$penumbra_noinfarct_z_rbf,$penumbra_noinfarct_z_rbv,$penumbra_noinfarct_z_ef,$penumbra_noinfarct_z_leakage,$penumbra_noinfarct_z_tmax,$penumbra_noinfarct_z_tmax_rapid,\
    $penumbra_noreflow_mtt,$penumbra_noreflow_rbf,$penumbra_noreflow_rbv,$penumbra_noreflow_ef,$penumbra_noreflow_leakage,$penumbra_noreflow_tmax,$penumbra_noreflow_tmax_rapid,\
    $penumbra_noreflow_z_mtt,$penumbra_noreflow_z_rbf,$penumbra_noreflow_z_rbv,$penumbra_noreflow_z_ef,$penumbra_noreflow_z_leakage,$penumbra_noreflow_z_tmax,$penumbra_noreflow_z_tmax_rapid,\
    $penumbra_reflow_mtt,$penumbra_reflow_rbf,$penumbra_reflow_rbv,$penumbra_reflow_ef,$penumbra_reflow_leakage,$penumbra_reflow_tmax,$penumbra_reflow_tmax_rapid,\
    $penumbra_reflow_z_mtt,$penumbra_reflow_z_rbf,$penumbra_reflow_z_rbv,$penumbra_reflow_z_ef,$penumbra_reflow_z_leakage,$penumbra_reflow_z_tmax,$penumbra_reflow_z_tmax_rapid,\
    $tmax6_ef,$tmax6_z_ef,\
    $tmax8_ef,$tmax8_z_ef,\
    $tmax10_ef,$tmax10_z_ef,\
    $normal_mtt,$normal_rbf,$normal_rbv,$normal_ef,$normal_leakage,$normal_tmax,$normal_tmax_rapid,\
    $normal_z_mtt,$normal_z_rbf,$normal_z_rbv,$normal_z_ef,$normal_z_leakage,$normal_z_tmax,$normal_z_tmax_rapid,\
    $normal_focal_ef,$normal_focal_z_ef,\
    $lesion_focal_ef,$lesion_focal_z_ef,\
    $penumbra_focal_ef,$penumbra_focal_z_ef,\
    $penumbra_infarct_focal_ef,$penumbra_infarct_focal_z_ef,\
    $penumbra_noinfarct_focal_ef,$penumbra_noinfarct_focal_z_ef,\
    $penumbra_noreflow_focal_ef,$penumbra_noreflow_focal_z_ef,\
    $penumbra_reflow_focal_ef,$penumbra_reflow_focal_z_ef,\
    $tmax6_focal_ef,$tmax6_focal_z_ef,\
    $tmax8_focal_ef,$tmax8_focal_z_ef,\
    $tmax10_focal_ef,$tmax10_focal_z_ef" >> $CSV

fi

###################################################################################################################
#                                  PART IV: READ-OUT VASCULAR TERRITORIES                                         #
###################################################################################################################

if [ $TEMP_SPACE == "brainder" ];then

    ##############
    # Create CSV #
    ##############

    # Define input
    ##############

    CSV=$PERF_DIR/${1}_ses-${SESSION}_perfusion_territories.csv
    LABEL_MAP=$ENV_DIR/standard/Atlas_MNI152/ArterialAtlas_level2_desc-regrid_desc-round.nii.gz

    echo -n "sub_id," > $CSV

    for MOD in mtt rbf rbv ef; do

        echo -en "nicestandard_ACAL_z_${MOD},nicestandard_ACAR_z_${MOD},nicestandard_MCAL_z_${MOD},nicestandard_MCAR_z_${MOD},nicestandard_PCAL_z_${MOD},nicestandard_PCAR_z_${MOD},nicestandard_VBL_z_${MOD},nicestandard_VBR_z_${MOD}," >> $CSV

    done

    echo -e "nicestandard_ACAL_z_tmax,nicestandard_ACAR_z_tmax,nicestandard_MCAL_z_tmax,nicestandard_MCAR_z_tmax,nicestandard_PCAL_z_tmax,nicestandard_PCAR_z_tmax,nicestandard_VBL_z_tmax,nicestandard_VBR_z_tmax" >> $CSV

    echo -n "$1" >>  $CSV

    # Iterate across modalities to extract mean values for each vascular territory
    ##############################################################################

    for MOD in MTTz rBFz rBVz EFz desc-RAPID_Tmaxz; do

        # Calculate mean for each ROI

        for N in {1..8}; do

            # Define input 
            MOD_PERF=$PERF_DIR/${1}_ses-${SESSION}_space-${TEMP_SPACE}_desc-moco_desc-brain_desc-wocsf_${MOD}.nii.gz

            # Define command
            CMD_ROI="mrcalc $LABEL_MAP $N -eq $TMP_OUT/${MOD}_ROI_${N}.mif -quiet"  
            CMD_MEAN="mrstats $MOD_PERF -mask $TMP_OUT/${MOD}_ROI_${N}.mif -output mean -ignorezero -quiet"

            # Execute command
            $singularity_mrtrix3 $CMD_ROI
            mean_roi=`$singularity_mrtrix3 $CMD_MEAN | tail -n 1`

            # Append to CSV
            echo -n ",$mean_roi" >> $CSV
                    
        done
    
    done
    
fi