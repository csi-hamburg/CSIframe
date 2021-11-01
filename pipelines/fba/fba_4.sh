#!/usr/bin/env bash
set -x

###################################################################################################################
# FBA based on https://mrtrix.readthedocs.io/en/latest/fixel_based_analysis/st_fibre_density_cross-section.html   #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - qsiprep & qsirecon                                                                                      #
#   [optional]                                                                                                    #
#       - freewater (to warp freewater results to group template)                                                 #
#   [container]                                                                                                   #
#       - mrtrix3-3.0.2.sif                                                                                       #
#       - mrtrix3tissue-5.2.8.sif                                                                                 #
#       - tractseg-master.sif                                                                                     #
###################################################################################################################

# Define subject array

input_subject_array=($@)

# Define environment
#########################
module load parallel

FBA_DIR=$DATA_DIR/fba
FBA_GROUP_DIR=$DATA_DIR/fba/derivatives
TEMPLATE_SUBJECTS_TXT=$FBA_DIR/sourcedata/template_subjects.txt
container_mrtrix3=mrtrix3-3.0.2      
container_mrtrix3tissue=mrtrix3tissue-5.2.8
container_tractseg=tractseg-master
export SINGULARITYENV_MRTRIX_TMPFILE_DIR=$TMP_DIR

[ ! -d $FBA_GROUP_DIR ] && mkdir -p $FBA_GROUP_DIR
singularity_mrtrix3="singularity run --cleanenv --userns \
    -B $(readlink -f $ENV_DIR) \
    -B $PROJ_DIR \
    -B $SCRATCH_DIR:/tmp \
    $ENV_DIR/$container_mrtrix3" 

singularity_mrtrix3tissue="singularity run --cleanenv --userns \
    -B $(readlink -f $ENV_DIR) \
    -B $PROJ_DIR \
    -B $SCRATCH_DIR:/tmp \
    $ENV_DIR/$container_mrtrix3tissue" 

singularity_tractseg="singularity run --cleanenv --userns \
    -B $(readlink -f $ENV_DIR) \
    -B $PROJ_DIR \
    -B $SCRATCH_DIR:/tmp \
    $ENV_DIR/$container_tractseg" 

foreach_="for_each -nthreads $SLURM_CPUS_PER_TASK ${input_subject_array[@]} :"
parallel="parallel --ungroup --delay 0.2 -j$SUBJS_PER_NODE --joblog $CODE_DIR/log/parallel_runtask.log"


#########################
# MRREGISTER & MRTRANSFORM
#########################

# Input
#########################
FOD_WM="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_space-T1w_desc-responsemean_desc-preproc_desc-wmFODmtnormed_ss3tcsd.mif.gz"
DWI_MASK_UPSAMPLED="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_space-T1w_desc-upsampled_desc-brain_mask.mif.gz"
FOD_TEMPLATE="$FBA_GROUP_DIR/template/wmfod_template.mif"

# Output
#########################
SUB2TEMP_WARP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_from-subject_to-fodtemplate_warp.mif"
TEMP2SUB_WARP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_from-fodtemplate_to-subject_warp.mif"
DWI_MASK_TEMPLATE="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-brain_mask.nii.gz"

# Command
#########################
CMD_MRREGISTER="mrregister $FOD_WM -mask1 $DWI_MASK_UPSAMPLED $FOD_TEMPLATE -nl_warp $SUB2TEMP_WARP $TEMP2SUB_WARP -force"
CMD_MRTRANSFORM="mrtransform $DWI_MASK_UPSAMPLED -warp $SUB2TEMP_WARP -interp nearest -datatype bit $DWI_MASK_TEMPLATE -force"

# Execution
#########################
$parallel "$singularity_mrtrix3tissue $CMD_MRREGISTER" ::: ${input_subject_array[@]}
$parallel "$singularity_mrtrix3tissue $CMD_MRTRANSFORM" ::: ${input_subject_array[@]}


#########################
# TEMPLATEMASK
#########################

# Input
#########################
FOD_TEMPLATE="$FBA_GROUP_DIR/template/wmfod_template.mif"

# Output
#########################
TEMPLATE_MASK="$FBA_GROUP_DIR/template/wmfod_template_mask.mif"
TRACTOGRAM="$FBA_GROUP_DIR/template/template_tractogram_20_million.tck"
TRACTOGRAM_SIFT="$FBA_GROUP_DIR/template/template_tractogram_20_million_sift.tck"

# Command
#########################
CMD_TEMPLATEMASK="mrmath $FBA_DIR/*/ses-$SESSION/dwi/*_ses-${SESSION}_space-fodtemplate_desc-brain_mask.nii.gz min $TEMPLATE_MASK -datatype bit -force"

# Execution
#########################
$singularity_mrtrix3 \
/bin/bash -c "$CMD_TEMPLATEMASK"


#########################
# FIXELMASK
#########################

# Lower threshold for keeping crossing fibres
# And upper threshold to prevent too many false positives
# Empirically derived from previous HCHS FBA
thr4crossingfibres=0.06
thr4fpcontrol=0.2

[ ! -d $FBA_GROUP_DIR/fixelmask ] && mkdir $FBA_GROUP_DIR/fixelmask

# Input
#########################
FOD_TEMPLATE="$FBA_GROUP_DIR/template/wmfod_template.mif"
TEMPLATE_MASK="$FBA_GROUP_DIR/template/wmfod_template_mask.mif"
EXCLUSION_MASK="$FBA_GROUP_DIR/fixelmask/exclusion_mask_inv.mif"

# Output
#########################
FIXELMASK_CROSSFB="$FBA_GROUP_DIR/fixelmask/01_fixelmask_crossingfibers"
FIXELMASK_FALSEPOS="$FBA_GROUP_DIR/fixelmask/02_fixelmask_falsepos"
FIXELMASK_CROP="$FBA_GROUP_DIR/fixelmask/03_fixelmask_crop"
FIXELMASK_CROSSFB_CROPPED="$FBA_GROUP_DIR/fixelmask/04_fixelmask_crossingfibers_cropped"
VOXELMASK_FALSEPOS="$FBA_GROUP_DIR/fixelmask/voxelmask_falsepos.mif"
FIXELMASK_EXCLUSIONMASK="$FBA_GROUP_DIR/fixelmask/05_fixelmask_exclusion"
FIXELMASK_FINAL="$FBA_GROUP_DIR/fixelmask/06_fixelmask_final"

# Command
#########################

CMD_FIXMASKCROSSINGFB="[ -d $FIXELMASK_CROSSFB ] && rm -rf $FIXELMASK_CROSSFB/*; fod2fixel -force -mask $TEMPLATE_MASK -fmls_peak_value $thr4crossingfibres $FOD_TEMPLATE $FIXELMASK_CROSSFB"
CMD_FIXMASKFALSEPOS="[ -d $FIXELMASK_FALSEPOS ] && rm -rf $FIXELMASK_FALSEPOS/*; fod2fixel -force -mask $TEMPLATE_MASK -fmls_peak_value $thr4fpcontrol $FOD_TEMPLATE $FIXELMASK_FALSEPOS"
CMD_VOXMASKFALSEPOS="fixel2voxel $FIXELMASK_FALSEPOS/directions.mif count - | mrthreshold - -abs 0.9 $VOXELMASK_FALSEPOS -force"
CMD_CROPMASK="[ -d $FIXELMASK_CROP ] && rm -rf $FIXELMASK_CROP/*; voxel2fixel $VOXELMASK_FALSEPOS $FIXELMASK_CROSSFB $FIXELMASK_CROP fixelmask_crop.mif -force"
CMD_CROP_CROSSFB="fixelcrop $FIXELMASK_CROSSFB $FIXELMASK_CROP/fixelmask_crop.mif $FIXELMASK_CROSSFB_CROPPED -force"
if [ -f $EXCLUSION_MASK ];then
    CMD_EXCLUSIONFIXELMASK="voxel2fixel $EXCLUSION_MASK $FIXELMASK_CROP $FIXELMASK_EXCLUSIONMASK fixelmask_exclusion.mif -force"
    CMD_CROP_FINAL="fixelcrop $FIXELMASK_CROSSFB_CROPPED $FIXELMASK_EXCLUSIONMASK/fixelmask_exclusionmask.mif $FIXELMASK_FINAL -force"
else
    CMD_EXCLUSIONFIXELMASK="echo 'No manual exclusion mask!'"
    CMD_CROP_FINAL="cp -rf $FIXELMASK_CROSSFB_CROPPED $FIXELMASK_FINAL"
fi

# Execution
#########################
$singularity_mrtrix3 \
/bin/bash -c "$CMD_FIXMASKCROSSINGFB; $CMD_FIXMASKFALSEPOS; $CMD_VOXMASKFALSEPOS; $CMD_CROPMASK; $CMD_EXCLUSIONFIXELMASK; $CMD_CROP_CROSSFB; $CMD_CROP_FINAL"


#########################
# TRACTOGRAPHY
#########################

# Input
#########################
FOD_TEMPLATE="$FBA_GROUP_DIR/template/wmfod_template.mif"
TEMPLATE_MASK="$FBA_GROUP_DIR/template/wmfod_template_mask.mif"

# Output
#########################
TRACTOGRAM="$FBA_GROUP_DIR/template/template_tractogram_20_million.tck"
TRACTOGRAM_SIFT="$FBA_GROUP_DIR/template/template_tractogram_20_million_sift.tck"

# Command
#########################
CMD_TCKGEN="tckgen -angle 22.5 -maxlen 250 -minlen 10 -power 1.0 $FOD_TEMPLATE -seed_image $TEMPLATE_MASK -mask $TEMPLATE_MASK -select 20000000 -cutoff 0.06 $TRACTOGRAM -force"
CMD_TCKSIFT="tcksift $TRACTOGRAM $FOD_TEMPLATE $TRACTOGRAM_SIFT -term_number 2000000 -force"

# Execution
#########################
# $singularity_mrtrix3 \
# /bin/bash -c "$CMD_TCKGEN; $CMD_TCKSIFT"


#########################
# TRACTSEG
#########################

TRACTSEG_DIR=$FBA_GROUP_DIR/tractseg/
TRACTSEG_OUT_DIR=$TRACTSEG_DIR/tractseg_output/

# Input
#########################
FOD_TEMPLATE="$FBA_GROUP_DIR/template/wmfod_template.mif"
TRACTOGRAM_SIFT="$FBA_GROUP_DIR/template/template_tractogram_20_million_sift.tck"

# Output
#########################
TEMPLATE_SHPEAKS="$TRACTSEG_DIR/wmfod_template_peaks.nii"
BUNDLE_TRACTOGRAM="$TRACTSEG_DIR/bundles_tractogram_sift.tck"
BUNDLE_FIXELMASK="$TRACTSEG_DIR/bundles_fixelmask"

[ ! -d  $TRACTSEG_DIR ] && mkdir $TRACTSEG_DIR/ $TRACTSEG_DIR/bundles_sift_tck $BUNDLE_FIXELMASK
pushd $TRACTSEG_DIR/ 

# Command
#########################
CMD_TEMPLATEMASK="sh2peaks $FOD_TEMPLATE $TEMPLATE_SHPEAKS -force"
CMD_TRACTSEG="TractSeg -i $TEMPLATE_SHPEAKS --output_type tract_segmentation"
CMD_TRACTENDINGS="TractSeg -i $TEMPLATE_SHPEAKS --output_type endings_segmentation"
CMD_TOM="TractSeg -i $TEMPLATE_SHPEAKS --output_type TOM"
CMD_TRACTOGRAMS="Tracking -i $TEMPLATE_SHPEAKS --tracking_format tck"
CMD_TRACTEXTRACTION="tckedit $TRACTOGRAM_SIFT -include $TRACTSEG_OUT_DIR/endings_segmentations/{}_b.nii.gz -include $TRACTSEG_OUT_DIR/endings_segmentations/{}_e.nii.gz -mask $TRACTSEG_OUT_DIR/bundle_segmentations/{}.nii.gz $TRACTSEG_DIR/bundles_sift_tck/{}.tck -force"
CMD_BUNDLETRACTOGRAM="tckedit $TRACTSEG_DIR/bundles_sift_tck/* $BUNDLE_TRACTOGRAM -force"
CMD_BUNDLETDI="tck2fixel $BUNDLE_TRACTOGRAM $FIXELMASK_FINAL $BUNDLE_FIXELMASK segmentation_bundle_tdi.mif -force"
CMD_BUNDLEFIXELMASK="mrthreshold -abs 1 $BUNDLE_FIXELMASK/segmentation_bundle_tdi.mif $BUNDLE_FIXELMASK/segmentation_bundle_fixelmask.mif -force"

# Execution
#########################
# $singularity_tractseg \
# /bin/bash -c "$CMD_TEMPLATEMASK; $CMD_TRACTSEG; $CMD_TRACTENDINGS; $CMD_TOM; $CMD_TRACTOGRAMS"
# $parallel "$singularity_mrtrix3 $CMD_TRACTEXTRACTION" ::: $(ls $TRACTSEG_OUT_DIR/bundle_segmentations | xargs -n 1 basename | cut -d "." -f 1)
# $singularity_mrtrix3 \
# /bin/bash -c "$CMD_BUNDLETRACTOGRAM; $CMD_BUNDLETDI; $CMD_BUNDLEFIXELMASK"

popd


#########################
# FIXELMETRICS
#########################

# Input
#########################
FOD_WM="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_space-T1w_desc-responsemean_desc-preproc_desc-wmFODmtnormed_ss3tcsd.mif.gz"
SUB2TEMP_WARP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_from-subject_to-fodtemplate_warp.mif"
TEMPLATE_MASK="$FBA_GROUP_DIR/template/wmfod_template_mask.mif"
FIXELMASK_FINAL="$FBA_GROUP_DIR/fixelmask/06_fixelmask_final"

# Output
#########################
FOD_WM_TEMP_NOREORIENT="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_space-fodtemplate_desc-wmFODmtnormed_ss3tcsd.mif.gz"
FIXELMASK_NOREORIENT="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_space-fodtemplate_desc-noreorient_fixelmask"
FIXELMASK_REORIENT="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_space-fodtemplate_desc-reorient_fixelmask"
TEMP2SUB_WARP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_from-fodtemplate_to-subject_warp.mif"
DWI_MASK_TEMPLATE="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-brain_mask.nii.gz"

FD_DIR=$FBA_GROUP_DIR/fd
FC_DIR=$FBA_GROUP_DIR/fc
LOG_FC_DIR=$FBA_GROUP_DIR/log_fc
FDC_DIR=$FBA_GROUP_DIR/fdc
[ ! -d $FD_DIR ] && mkdir -p $FD_DIR $FC_DIR $LOG_FC_DIR $FDC_DIR

# Command
#########################
CMD_FOD2TEMPLATE="mrtransform $FOD_WM -warp $SUB2TEMP_WARP -reorient_fod no $FOD_WM_TEMP_NOREORIENT -force"
CMD_SUBJECTFOD2FIXEL="[ -d $FIXELMASK_NOREORIENT ] && rm -rf $FIXELMASK_NOREORIENT/*; fod2fixel -mask $TEMPLATE_MASK $FOD_WM_TEMP_NOREORIENT $FIXELMASK_NOREORIENT -afd fd.mif -force"
CMD_REORIENTFIXELS="[ -d $FIXELMASK_REORIENT ] && rm -rf $FIXELMASK_REORIENT/*; fixelreorient $FIXELMASK_NOREORIENT $SUB2TEMP_WARP $FIXELMASK_REORIENT -force"
CMD_FD="fixelcorrespondence -force $FIXELMASK_REORIENT/fd.mif $FIXELMASK_FINAL $FD_DIR {}.mif -force"
CMD_FC="warp2metric $SUB2TEMP_WARP -fc $FIXELMASK_FINAL $FC_DIR {}.mif -force"
CMD_LOG_FC="mrcalc $FC_DIR/{}.mif -log $LOG_FC_DIR/{}.mif -force"
CMD_FDC="mrcalc $FD_DIR/{}.mif $FC_DIR/{}.mif -mult $FDC_DIR/{}.mif -force"

# Execution
#########################
$parallel "$singularity_mrtrix3 $CMD_FOD2TEMPLATE" ::: ${input_subject_array[@]}
$parallel "$singularity_mrtrix3 $CMD_SUBJECTFOD2FIXEL" ::: ${input_subject_array[@]}
$parallel "$singularity_mrtrix3 $CMD_REORIENTFIXELS" ::: ${input_subject_array[@]}
$parallel "$singularity_mrtrix3 $CMD_FD" ::: ${input_subject_array[@]}
$parallel "$singularity_mrtrix3 $CMD_FC" ::: ${input_subject_array[@]}
cp $FC_DIR/index.mif $FC_DIR/directions.mif $LOG_FC_DIR
cp $FC_DIR/index.mif $FC_DIR/directions.mif $FDC_DIR
$parallel "$singularity_mrtrix3 $CMD_LOG_FC" ::: ${input_subject_array[@]}
$parallel "$singularity_mrtrix3 $CMD_FDC" ::: ${input_subject_array[@]}


#########################
# CONNECTIVITY & FILTER
#########################

# Input
#########################
FIXELMASK_FINAL="$FBA_GROUP_DIR/fixelmask/06_fixelmask_final"
BUNDLE_TRACTOGRAM="$TRACTSEG_DIR/bundle_tractogram_sift.tck"

FD_DIR=$FBA_GROUP_DIR/fd
LOG_FC_DIR=$FBA_GROUP_DIR/log_fc
FDC_DIR=$FBA_GROUP_DIR/fdc

# Output
#########################
FIXELCONNECTIVITY_MAT=$FBA_GROUP_DIR/matrix
[ ! -d $FIXELCONNECTIVITY_MAT ] && mkdir $FIXELCONNECTIVITY_MAT

FD_SMOOTH_DIR=$FBA_GROUP_DIR/fd_smooth
LOG_FC_SMOOTH_DIR=$FBA_GROUP_DIR/log_fc_smooth
FDC_SMOOTH_DIR=$FBA_GROUP_DIR/fdc_smooth
[ ! -d $FD_SMOOTH_DIR ] && mkdir -p $FD_SMOOTH_DIR $LOG_FC_SMOOTH_DIR $FDC_SMOOTH_DIR

# Command
#########################
CMD_FIXELCONNECTIVITY="fixelconnectivity $FIXELMASK_FINAL $TRACTOGRAM_SIFT $FIXELCONNECTIVITY_MAT -force"
CMD_FILTER_FD="fixelfilter $FD_DIR smooth $FD_SMOOTH_DIR -matrix $FIXELCONNECTIVITY_MAT -force"
CMD_FILTER_LOG_FC="fixelfilter $LOG_FC_DIR smooth $LOG_FC_SMOOTH_DIR -matrix $FIXELCONNECTIVITY_MAT -force"
CMD_FILTER_FDC="fixelfilter $FDC_DIR smooth $FDC_SMOOTH_DIR -matrix $FIXELCONNECTIVITY_MAT -force"

# Execution
#########################
$singularity_mrtrix3 \
/bin/bash -c "$CMD_FIXELCONNECTIVITY; $CMD_FILTER_FD; $CMD_FILTER_LOG_FC; $CMD_FILTER_FDC"