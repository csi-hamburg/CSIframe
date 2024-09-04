#!/bin/bash

###################################################################################################################
# Script for postprocessing NordicIce perfusion analysis output for the ARCTIC study                              #
#       - brain extraction and bias correction of FLAIR images                                                    #
#       - registration of pefusion images to standard space                                                       #
###################################################################################################################

###################################################################################################################
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - NordicIce perfusion analysis and bidsification of it's outputs                                          #
#       - ASLprep (for T1w preprocessing)                                                                         #
#   [containers]                                                                                                  #
#       - fsl-6.0.3                                                                                               #
#       - mrtrix3-3.0.2                                                                                           #
#       - freesurfer-7.4.1                                                                                        #
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

ENV_DIR="/usw/fatx129/envs/"

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

singularity_freesurfer="singularity run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR \
    -B $TMP_IN \
    -B $TMP_OUT \
    $ENV_DIR/$container_freesurfer" 

# Define pipeline output directory 
##################################

NICE_DIR=$DATA_DIR/nice
ASL_DIR=$DATA_DIR/aslprep/$1/anat
BASIL_DIR=$DATA_DIR/aslprep/$1/perf
PERF_DIR=$NICE_DIR/$1/ses-$SESSION/perf
ANAT_DIR=$NICE_DIR/$1/ses-$SESSION/anat
DER_DIR=$NICE_DIR/derivatives/ses-$SESSION/perf

[ ! -d $DER_DIR ] && mkdir -p $DER_DIR
[ ! -d $ANAT_DIR ] && mkdir -p $ANAT_DIR 

###################################################################################################################
#                                           PART I: DSC/PERFUSION SPACE                                           #
###################################################################################################################

##################################
# Brain extraction of T1w images #
##################################

# Define input
##############

T1W=$ASL_DIR/${1}_desc-preproc_T1w.nii.gz
T1W_MASK=$ASL_DIR/${1}_desc-brain_mask.nii.gz


# Define output
###############

T1W_BRAIN=$ANAT_DIR/${1}_desc-preproc_desc-brain_T1w.nii.gz

# Define commands
#################

CMD_BET="fslmaths $T1W -mas $T1W_MASK $T1W_BRAIN"

# Execute commands
##################

$singularity_fsl $CMD_BET

#####################################
# Tissue segmentation of T1w images #
#####################################

# Define input
##############

T1W_BRAIN=$ANAT_DIR/${1}_desc-preproc_desc-brain_T1w.nii.gz

# Define output
###############

T1W_SEG=$ANAT_DIR/${1}_mod-T1w_SynthSeg.nii.gz
T1W_SEG_STATS=$ANAT_DIR/${1}_mod-T1w_desc-SynthSeg_stats.csv
T1W_SEG_QC=$ANAT_DIR/${1}_mod-T1w_desc-SynthSeg_qc.csv

LEFT_WM=$ANAT_DIR/${1}_mod-T1w_label-lwm_SynthSeg.nii.gz # supratentorial white matter w/o subcortical gray matter
LEFT_GM=$ANAT_DIR/${1}_mod-T1w_label-lgm_SynthSeg.nii.gz # cortical gray matter
RIGHT_WM=$ANAT_DIR/${1}_mod-T1w_label-rwm_SynthSeg.nii.gz
RIGHT_GM=$ANAT_DIR/${1}_mod-T1w_label-rgm_SynthSeg.nii.gz

WM=$ANAT_DIR/${1}_mod-T1w_label-wm_SynthSeg.nii.gz
GM=$ANAT_DIR/${1}_mod-T1w_label-gm_SynthSeg.nii.gz

WM_REGRID=$ANAT_DIR/${1}_space-T1w_label-wm_SynthSeg.nii.gz
GM_REGRID=$ANAT_DIR/${1}_space-T1w_label-gm_SynthSeg.nii.gz

# Define commands
#################

# SynthSeg
CMD_SEG="mri_synthseg \
    --i $T1W_BRAIN \
    --o $T1W_SEG \
    --vol $T1W_SEG_STATS \
    --qc $T1W_SEG_QC \
    --robust \
    --threads 4" 

# Extract white and gray matter labels
CMD_LEFT_WM="fslmaths $T1W_SEG -thr 2 -uthr 2 -bin $LEFT_WM"
CMD_LEFT_GM="fslmaths $T1W_SEG -thr 3 -uthr 3 -bin $LEFT_GM"
CMD_RIGHT_WM="fslmaths $T1W_SEG -thr 41 -uthr 41 -bin $RIGHT_WM"
CMD_RIGHT_GM="fslmaths $T1W_SEG -thr 42 -uthr 42 -bin $RIGHT_GM"

CMD_WM="fslmaths $LEFT_WM -add $RIGHT_WM $WM"
CMD_GM="fslmaths $LEFT_GM -add $RIGHT_GM $GM"

# Regrid to T1w voxel size and binarize
CMD_REGRID_WM="mrgrid $WM regrid -template $T1W_BRAIN $WM_REGRID -force"
CMD_BIN_WM="fslmaths $WM_REGRID -thr 0.9 -bin $WM_REGRID"
CMD_REGRID_GM="mrgrid $GM regrid -template $T1W_BRAIN $GM_REGRID -force"
CMD_BIN_GM="fslmaths $GM_REGRID -thr 0.9 -bin $GM_REGRID"

# Execute commands
##################

$singularity_freesurfer $CMD_SEG

$singularity_fsl $CMD_LEFT_WM
$singularity_fsl $CMD_LEFT_GM
$singularity_fsl $CMD_RIGHT_WM
$singularity_fsl $CMD_RIGHT_GM

$singularity_fsl $CMD_WM
$singularity_fsl $CMD_GM

$singularity_mrtrix3 $CMD_REGRID_WM
$singularity_fsl $CMD_BIN_WM
$singularity_mrtrix3 $CMD_REGRID_GM
$singularity_fsl $CMD_BIN_GM

#####################################################
# Reorient perfusion images to standard orientation #
#####################################################

# This needs to be done to accomodate NordicIce orientation bug

# Define input/output
#####################

BASELINE_DSC=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_baselineSI.nii.gz
MTT=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-LeakageCorrected_MTT.nii.gz
RBF=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-LeakageCorrected_rBF.nii.gz
RBV=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-LeakageCorrected_rCBV.nii.gz
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
MTT=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-LeakageCorrected_MTT.nii.gz
RBF=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-LeakageCorrected_rBF.nii.gz
RBV=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-LeakageCorrected_rCBV.nii.gz
EF=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_EF.nii.gz
LEAKAGE=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_leakage.nii.gz
TMAX=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_Tmax.nii.gz

# Define output
###############

BASELINE_DSC_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_baselineSI
DSC_BRAIN_MASK=$PERF_DIR/${1}_ses-${SESSION}_space-dsc_desc-brain_mask.nii.gz
MTT_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-LeakageCorrected_MTT.nii.gz
RBF_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-LeakageCorrected_rBF.nii.gz
RBV_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-LeakageCorrected_rCBV.nii.gz
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


####################################################################
# Registration of tissue segmentations from T1w space to DSC space #
####################################################################

# Define input
##############

BASELINE_DSC_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_baselineSI.nii.gz
T1W_BRAIN=$ANAT_DIR/${1}_desc-preproc_desc-brain_T1w.nii.gz
WM_REGRID=$ANAT_DIR/${1}_space-T1w_label-wm_SynthSeg.nii.gz
GM_REGRID=$ANAT_DIR/${1}_space-T1w_label-gm_SynthSeg.nii.gz

# Define output
###############

DSC_IN_T1W=$PERF_DIR/${1}_ses-${SESSION}_space-T1w_desc-moco_desc-brain_baselineSI.nii.gz
DSC_2_T1W_FSL=$PERF_DIR/${1}_ses-${SESSION}_from-dsc_to-T1w_desc-affine.mat
T1W_2_DSC=$ANAT_DIR/${1}_ses-${SESSION}_from-T1w_to-dsc_desc-affine.mat

GM_DSC_PROB=$ANAT_DIR/${1}_space-dsc_label-gm_desc-prob_SynthSeg.nii.gz
WM_DSC_PROB=$ANAT_DIR/${1}_space-dsc_label-wm_desc-prob_SynthSeg.nii.gz

GM_DSC=$ANAT_DIR/${1}_space-dsc_label-gm_SynthSeg.nii.gz
WM_DSC=$ANAT_DIR/${1}_space-dsc_label-wm_SynthSeg.nii.gz

# Define commands
#################

CMD_DSC2T1W="flirt -in $BASELINE_DSC_BRAIN -ref $T1W_BRAIN -out $DSC_IN_T1W -omat $DSC_2_T1W_FSL -cost mutualinfo -searchcost mutualinfo -dof 6"
CMD_T1W2DSC="convert_xfm -omat $T1W_2_DSC -inverse $DSC_2_T1W_FSL"

CMD_APPLY_XFM_GM="flirt -in $GM_REGRID -ref $BASELINE_DSC_BRAIN -applyxfm -init $T1W_2_DSC -out $GM_DSC_PROB"
CMD_APPLY_XFM_WM="flirt -in $WM_REGRID -ref $BASELINE_DSC_BRAIN -applyxfm -init $T1W_2_DSC -out $WM_DSC_PROB"

# Thresholding

CMD_TRESH_GM="fslmaths $GM_DSC_PROB -thr 0.6 -bin $GM_DSC"
CMD_TRESH_WM="fslmaths $WM_DSC_PROB -thr 0.6 -bin $WM_DSC"

# Execute commands
##################

# Registration

$singularity_fsl $CMD_DSC2T1W
$singularity_fsl $CMD_T1W2DSC
$singularity_fsl $CMD_APPLY_XFM_GM
$singularity_fsl $CMD_APPLY_XFM_WM

# Thresholding

$singularity_fsl $CMD_TRESH_GM
$singularity_fsl $CMD_TRESH_WM

###################################################################################################################
#                                           PART II: STANDARD SPACE                                               #
###################################################################################################################

################################################################
# Registration of perfusion images to standard space via T1w #
################################################################

# Define input
##############
BASELINE_DSC_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_baselineSI.nii.gz
T1W_BRAIN=$ANAT_DIR/${1}_desc-preproc_desc-brain_T1w.nii.gz

MTT_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-LeakageCorrected_MTT.nii.gz
RBF_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-LeakageCorrected_rBF.nii.gz
RBV_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-LeakageCorrected_rCBV.nii.gz
EF_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_EF.nii.gz
LEAKAGE_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_leakage.nii.gz
TMAX_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_Tmax.nii.gz

DSC_IN_T1W=$PERF_DIR/${1}_ses-${SESSION}_space-T1w_desc-moco_desc-brain_baselineSI.nii.gz
DSC_2_T1W_FSL=$PERF_DIR/${1}_ses-${SESSION}_from-dsc_to-T1w_desc-affine.mat
T1W_2_DSC=$ANAT_DIR/${1}_ses-${SESSION}_from-T1w_to-dsc_desc-affine.mat
T1W2TEMPLATE_WARP=$ASL_DIR/${1}_from-T1w_to-MNI152NLin2009cAsym_mode-image_xfm.h5
T1W_IN_MNI=$ASL_DIR/${1}_space-MNI152NLin2009cAsym_desc-preproc_T1w.nii.gz

# Define output
###############

MTT_T1W=$PERF_DIR/${1}_ses-${SESSION}_space-T1w_desc-moco_desc-brain_MTT.nii.gz
RBF_T1W=$PERF_DIR/${1}_ses-${SESSION}_space-T1w_desc-moco_desc-brain_rBF.nii.gz
RBV_T1W=$PERF_DIR/${1}_ses-${SESSION}_space-T1w_desc-moco_desc-brain_rCBV.nii.gz
EF_T1W=$PERF_DIR/${1}_ses-${SESSION}_space-T1w_desc-moco_desc-brain_EF.nii.gz
LEAKAGE_T1W=$PERF_DIR/${1}_ses-${SESSION}_space-T1w_desc-moco_desc-brain_leakage.nii.gz
TMAX_T1W=$PERF_DIR/${1}_ses-${SESSION}_space-T1w_desc-moco_desc-brain_Tmax.nii.gz

BASELINE_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-moco_desc-brain_baselineSI.nii.gz
MTT_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-moco_desc-brain_MTT.nii.gz
RBF_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-moco_desc-brain_rBF.nii.gz
RBV_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-moco_desc-brain_rCBV.nii.gz
EF_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-moco_desc-brain_EF.nii.gz
LEAKAGE_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-moco_desc-brain_leakage.nii.gz
TMAX_TEMP=$PERF_DIR/${1}_ses-${SESSION}_space-MNI152NLin2009cAsym_desc-moco_desc-brain_Tmax.nii.gz

# Define commands
#################

CMD_MTT2T1W="flirt -in $MTT_BRAIN -ref $T1W_BRAIN -applyxfm -init $DSC_2_T1W_FSL -out $MTT_T1W"
CMD_RBF2T1W="flirt -in $RBF_BRAIN -ref $T1W_BRAIN -applyxfm -init $DSC_2_T1W_FSL -out $RBF_T1W"
CMD_RBV2T1W="flirt -in $RBV_BRAIN -ref $T1W_BRAIN -applyxfm -init $DSC_2_T1W_FSL -out $RBV_T1W"
CMD_EF2T1W="flirt -in $EF_BRAIN -ref $T1W_BRAIN -applyxfm -init $DSC_2_T1W_FSL -out $EF_T1W"
CMD_LEAKAGE2T1W="flirt -in $LEAKAGE_BRAIN -ref $T1W_BRAIN -applyxfm -init $DSC_2_T1W_FSL -out $LEAKAGE_T1W"
CMD_TMAX2T1W="flirt -in $TMAX_BRAIN -ref $T1W_BRAIN -applyxfm -init $DSC_2_T1W_FSL -out $TMAX_T1W"

CMD_BASELINE2MNI="antsApplyTransforms -d 3 -e 0 -n Linear -i $DSC_IN_T1W -r $T1W_IN_MNI -t $T1W2TEMPLATE_WARP -o $BASELINE_TEMP"
CMD_MTT2MNI="antsApplyTransforms -d 3 -e 0 -n Linear -i $MTT_T1W -r $T1W_IN_MNI -t $T1W2TEMPLATE_WARP -o $MTT_TEMP"
CMD_RBF2MNI="antsApplyTransforms -d 3 -e 0 -n Linear -i $RBF_T1W -r $T1W_IN_MNI -t $T1W2TEMPLATE_WARP -o $RBF_TEMP"
CMD_RBV2MNI="antsApplyTransforms -d 3 -e 0 -n Linear -i $RBV_T1W -r $T1W_IN_MNI -t $T1W2TEMPLATE_WARP -o $RBV_TEMP"
CMD_EF2MNI="antsApplyTransforms -d 3 -e 0 -n Linear -i $EF_T1W -r $T1W_IN_MNI -t $T1W2TEMPLATE_WARP -o $EF_TEMP"
CMD_LEAKAGE2MNI="antsApplyTransforms -d 3 -e 0 -n Linear -i $LEAKAGE_T1W -r $T1W_IN_MNI -t $T1W2TEMPLATE_WARP -o $LEAKAGE_TEMP"
CMD_TMAX2MNI="antsApplyTransforms -d 3 -e 0 -n Linear -i $TMAX_T1W -r $T1W_IN_MNI -t $T1W2TEMPLATE_WARP -o $TMAX_TEMP"

# Execute commands
##################

$singularity_fsl $CMD_MTT2T1W
$singularity_fsl $CMD_RBF2T1W
$singularity_fsl $CMD_RBV2T1W
$singularity_fsl $CMD_EF2T1W
$singularity_fsl $CMD_LEAKAGE2T1W
$singularity_fsl $CMD_TMAX2T1W

$singularity_mrtrix3 $CMD_BASELINE2MNI
$singularity_mrtrix3 $CMD_MTT2MNI
$singularity_mrtrix3 $CMD_RBF2MNI
$singularity_mrtrix3 $CMD_RBV2MNI
$singularity_mrtrix3 $CMD_EF2MNI
$singularity_mrtrix3 $CMD_LEAKAGE2MNI
$singularity_mrtrix3 $CMD_TMAX2MNI


############################################################################################
#                                  PART III/A: READ-OUT ROIs                               #
############################################################################################

##############
# Create CSV #
##############

CSV=$PERF_DIR/${1}_ses-${SESSION}_perfusion.csv

echo -e "sub_id,ses_id,mtt_wm,mtt_gm,cbf_wm,cbf_gm,cbv_wm,cbv_gm,ef_wm,ef_gm,leakage_wm,leakage_gm,tmax_wm,tmax_gm,basil_rbf_wm,basil_rbf_gm" > $CSV

####################
# Read-out of ROIs #
####################

# Define input
##############

MTT_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-LeakageCorrected_MTT.nii.gz
RBF_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-LeakageCorrected_rBF.nii.gz
RBV_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_desc-LeakageCorrected_rCBV.nii.gz
EF_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_EF.nii.gz
LEAKAGE_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_leakage.nii.gz
TMAX_BRAIN=$PERF_DIR/${1}_ses-${SESSION}_desc-moco_desc-brain_Tmax.nii.gz

GM_DSC=$ANAT_DIR/${1}_space-dsc_label-gm_SynthSeg.nii.gz
WM_DSC=$ANAT_DIR/${1}_space-dsc_label-wm_SynthSeg.nii.gz

WM_REGRID=$ANAT_DIR/${1}_space-T1w_label-wm_SynthSeg.nii.gz
GM_REGRID=$ANAT_DIR/${1}_space-T1w_label-gm_SynthSeg.nii.gz
BASIL_RBF=$BASIL_DIR/${1}_ses-${SESSION}_space-T1w_desc-basil_cbf.nii.gz

# Define function which extracts mean of ROI
############################################

extractmean() {

    img=$1
    roi=$2

    test=`$singularity_fsl fslstats $roi -M | tail -n 1`

    if [ $test != "0.000000" ]; then

        mean=`$singularity_fsl fslstats $img -k $roi -M | tail -n 1`
    
    else

        mean=""
    
    fi
    
    echo $mean

}


# Extract means
###############

mtt_wm=`extractmean $MTT_BRAIN $WM_DSC`
rbf_wm=`extractmean $RBF_BRAIN $WM_DSC`
rbv_wm=`extractmean $RBV_BRAIN $WM_DSC`
ef_wm=`extractmean $EF_BRAIN $WM_DSC`
leakage_wm=`extractmean $LEAKAGE_BRAIN $WM_DSC`
tmax_wm=`extractmean $TMAX_BRAIN $WM_DSC`

mtt_gm=`extractmean $MTT_BRAIN $GM_DSC`
rbf_gm=`extractmean $RBF_BRAIN $GM_DSC`
rbv_gm=`extractmean $RBV_BRAIN $GM_DSC`
ef_gm=`extractmean $EF_BRAIN $GM_DSC`
leakage_gm=`extractmean $LEAKAGE_BRAIN $GM_DSC`
tmax_gm=`extractmean $TMAX_BRAIN $GM_DSC`

basil_rbf_wm=`extractmean $BASIL_RBF $WM_REGRID`
basil_rbf_gm=`extractmean $BASIL_RBF $GM_REGRID`

# Append to CSV
###############

echo -e "$1,$SESSION,$mtt_wm,$mtt_gm,$rbf_wm,$rbf_gm,$rbv_wm,$rbv_gm,$ef_wm,$ef_gm,$leakage_wm,$leakage_gm,$tmax_wm,$tmax_gm,$basil_rbf_wm,$basil_rbf_gm" >> $CSV