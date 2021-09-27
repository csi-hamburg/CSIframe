#!/bin/bash

#SBATCH --nodes=1
#SBATCH --export=INTERACTIVE,PIPELINE,SESSION,SUBJS_PER_NODE,MODIFIER,FBA_LEVEL

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

[ ! -d $FBA_GROUP_DIR ] && mkdir -p $FBA_GROUP_DIR
singularity_mrtrix3="singularity run --cleanenv --userns \
    -B . \
    -B $PROJ_DIR \
    -B $SCRATCH_DIR:/tmp \
    $ENV_DIR/$container_mrtrix3" 

singularity_mrtrix3tissue="singularity run --cleanenv --userns \
    -B . \
    -B $PROJ_DIR \
    -B $SCRATCH_DIR:/tmp \
    $ENV_DIR/$container_mrtrix3tissue" 

singularity_tractseg="singularity run --cleanenv --userns \
    -B . \
    -B $PROJ_DIR \
    -B $SCRATCH_DIR:/tmp \
    $ENV_DIR/$container_tractseg" 

foreach_="for_each -nthreads $SLURM_CPUS_PER_TASK ${input_subject_array[@]} :"
parallel="parallel --ungroup --delay 0.2 -j$SUBJS_PER_NODE --joblog $CODE_DIR/log/parallel_runtask.log"


#########################
# POPULATION_TEMPLATE
#########################

# Input
#########################

# Prepare group directories with symlinks of FODs and masks for population_template input 
if [ -f $TEMPLATE_SUBJECTS_TXT ];then
    readarray template_subject_array < $TEMPLATE_SUBJECTS_TXT
else
    template_subject_array=($(echo ${input_subject_array[@]} | sort -R | tail -40))
fi

FOD_GROUP_DIR=$FBA_GROUP_DIR/template/fod_input
MASK_GROUP_DIR=$FBA_GROUP_DIR/template/mask_input

[ ! -d  ] && mkdir -p $FOD_GROUP_DIR $MASK_GROUP_DIR

for sub in ${template_subject_array[@]};do

    DWI_MASK_UPSAMPLED_="$DATA_DIR/qsiprep/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_acq-AP_space-T1w_desc-brain_mask.nii.gz"
    FOD_WM_="$FBA_DIR/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_acq-AP_space-T1w_desc-responsemean_desc-preproc_desc-wmFODmtnormed_ss3tcsd.mif.gz"
    ln -sr $FOD_WM_ $FOD_GROUP_DIR
    ln -sr $DWI_MASK_UPSAMPLED_ $MASK_GROUP_DIR

done

# Output
#########################
FOD_TEMPLATE="$FBA_GROUP_DIR/template/wmfod_template.mif"

# Command
#########################
CMD_POPTEMP="population_template $FOD_GROUP_DIR -mask_dir $MASK_GROUP_DIR $FOD_TEMPLATE -voxel_size 1.3"

# Execution
#########################
$singularity_mrtrix3 $CMD_POPTEMP


#########################
# MRREGISTER & MRTRANSFORM
#########################

# Input
#########################
FOD_WM="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_space-T1w_desc-responsemean_desc-preproc_desc-wmFODmtnormed_ss3tcsd.mif.gz"
DWI_MASK_UPSAMPLED="$DATA_DIR/qsiprep/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_space-T1w_desc-brain_mask.nii.gz"
FOD_TEMPLATE="$FBA_GROUP_DIR/template/wmfod_template.mif"

# Output
#########################
SUB2TEMP_WARP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_from-subject_to-fodtemplate_warp.mif"
TEMP2SUB_WARP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_from-fodtemplate_to-subject_warp.mif"
DWI_MASK_TEMPLATE="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-brain_mask.nii.gz"

# Command
#########################
CMD_MRREGISTER="mrregister $FOD_WM -mask1 $DWI_MASK_UPSAMPLED $FOD_TEMPLATE -nl_warp $SUB2TEMP_WARP $TEMP2SUB_WARP"
CMD_MRTRANSFORM="mrtransform $DWI_MASK_UPSAMPLED $SUB2TEMP_WARP -interp nearest -datatype bit $DWI_MASK_TEMPLATE"

# Execution
#########################
$parallel "$singularity_mrtrix3tissue $CMD_MRREGISTER" ::: ${input_subject_array[@]}
$parallel "$singularity_mrtrix3tissue $CMD_MRTRANSFORM" ::: ${input_subject_array[@]}


#########################
# MASK & TRACTOGRAPHY
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
CMD_TEMPLATEMASK="mrmask $FBA_DIR/*/ses-$SESSION/dwi/*_ses-${SESSION}_space-fodtemplate_desc-brain_mask.nii.gz min $TEMPLATE_MASK"
CMD_TCKGEN="tckgen -angle 22.5 maxlen 250 -minlen 10 -power 1.0 $FOD_TEMPLATE -seed_image $TEMPLATE_MASK -mask $TEMPLATE_MASK -select 20000000 -cutoff $TRACTOGRAM"
CMD_TCKSIFT="tcksift $TRACTOGRAM $FOD_TEMPLATE $TRACTOGRAM_SIFT -term_number 2000000"

# Execution
#########################
$singularity_mrtrix3 \
/bin/bash -c "$CMD_TEMPLATE_MASK; $CMD_TCKGEN; $CMD_TCKSIFT"


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
#EXCLUSION_MASK="$FBA_GROUP_DIR/fixelmask/exclusion_mask_inv.mif"

# Output
#########################
FIXELMASK_CROSSFB="$FBA_GROUP_DIR/fixelmask/01_fixelmask_crossingfibers"
FIXELMASK_FALSEPOS="$FBA_GROUP_DIR/fixelmask/02_fixelmask_falsepos"
FIXELMASK_CROP="$FBA_GROUP_DIR/fixelmask/03_fixelmask_crop"
VOXELMASK_FALSEPOS="$FBA_GROUP_DIR/fixelmask/voxelmask_falsepos.mif"
FIXELMASK_FINAL="$FBA_GROUP_DIR/fixelmask/04_fixelmask_final"
TRACTOGRAM="$FBA_GROUP_DIR/template/template_tractogram_20_million.tck"
TRACTOGRAM_SIFT="$FBA_GROUP_DIR/template/template_tractogram_20_million_sift.tck"

# Command
#########################
CMD_FIXMASKCROSSINGFB="fod2fixel -mask $TEMPLATE_MASK -fmls_peak_value $thr4crossingfibres $FOD_TEMPLATE $FIXELMASK_CROSSFB -force"
CMD_FIXMASKFALSEPOS="fod2fixel -mask $TEMPLATE_MASK -fmls_peak_value $thr4fpcontrol $FOD_TEMPLATE $FIXELMASK_FALSEPOS -force"
CMD_VOXMASKFALSEPOS="fixel2voxel $FIXELMASK_FALSEPOS/directions.mif count - | mrthreshold - -abs 0.9 $VOXELMASK_FALSEPOS.mif -force"
CMD_CROPMASK="voxel2fixel $VOXELMASK_FALSEPOS $FIXELMASK_CROSSFB $FIXELMASK_CROP fixelmask_crop.mif -force"
CMD_CROP="fixelcrop $FIXELMASK_CROSSFB $FIXELMASK_CROP/fixelmask_crop.mif $FIXELMASK_FINAL -force"

# Execution
#########################
$singularity_mrtrix3 \
/bin/bash -c "$CMD_FIXMASKCROSSINGFB; $CMD_FIXMASKFALSEPOS; $CMD_VOXMASKFALSEPOS; $CMD_CROPMASK; $CMD_CROP"


#########################
# TRACTSEG
#########################

TRACTSEG_DIR=$FBA_GROUP_DIR/tractseg
[ ! -d  $TRACTSEG_DIR ] && mkdir $TRACTSEG_DIR/ 
pushd $TRACTSEG_DIR/ 

# Input
#########################
FOD_TEMPLATE="$FBA_GROUP_DIR/template/wmfod_template.mif"
TRACTOGRAM_SIFT="$FBA_GROUP_DIR/template/template_tractogram_20_million_sift.tck"

# Output
#########################
TEMPLATE_SHPEAKS="$TRACTSEG_DIR/wmfod_template_peaks.nii"
SEGBUNDLE_TRACTOGRAM="$TRACTSEG_DIR/segmentation_bundle_tractogram.tck"
SEGBUNDLE_FIXELMASK="$TRACTSEG_DIR/segmentation_bundle_fixelmask"

# Command
#########################
CMD_TEMPLATEMASK="shpeaks $FOD_TEMPLATE $TEMPLATE_SHPEAKS"
CMD_TRACTSEG="TractSeg -i $TEMPLATE_SHPEAKS --output_type tract_segmentation"
CMD_TRACTENDINGS="TractSeg -i $TEMPLATE_SHPEAKS --output_type endings_segmentation"
CMD_TOM="TractSeg -i $TEMPLATE_SHPEAKS --output_type TOM"
CMD_TRACTOGRAMS="TractSeg -i $TEMPLATE_SHPEAKS --tracking_format tck"
CMD_TRACTEXTRACTION="for_each $(ls $TRACTSEG_DIR/bundles_tdi | xargs -n 1 basename) : tckedit $TRACTOGRAM_SIFT 
    -include $TRACTSEG_DIR/endings_segmentations/NAME_b.nii.gz 
    -include $TRACTSEG_DIR/endings_segmentations/NAME_e.nii.gz 
    -mask $TRACTSEG_DIR/bundle_segmentations/NAME.nii.gz $TRACTSEG_DIR/bundles_tck/NAME.tck"
CMD_BUNDLETRACTOGRAM="tckedit $TRACTSEG_DIR/bundles_tck/* $SEGBUNDLE_TRACTOGRAM"
CMD_BUNDLETDI="tck2fixel $BUNDLE_FIXELMASK $FIXELMASK_FINAL $SEGBUNDLE_FIXELMASK segmentation_bundle_tdi.mif"
CMD_BUNDLEFIXELMASK="mrthreshold -abs 1 $SEGBUNDLE_FIXELMASK/segmentation_bundle_tdi.mif $SEGBUNDLE_FIXELMASK/segmentation_bundle_fixelmask.mif"

# Execution
#########################
$singularity_tractseg \
/bin/bash -c "$CMD_TEMPLATE_MASK; $CMD_TRACTSEG; $CMD_TRACTENDINGS; $CMD_TOM; $CMD_TRACTOGRAMS"
$singularity_mrtrix3 \
/bin/bash -c "$CMD_TRACTEXTRACTION; $CMD_BUNDLETRACTOGRAM; $CMD_BUNDLETDI; $CMD_BUNDLEFIXELMASK"

popd


#########################
# FIXELMETRICS
#########################

# Input
#########################
FOD_WM="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_space-T1w_desc-responsemean_desc-preproc_desc-wmFODmtnormed_ss3tcsd.mif.gz"
SUB2TEMP_WARP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_from-subject_to-fodgrouptemplate_warp.mif"
TEMPLATE_MASK="$FBA_GROUP_DIR/template/wmfod_template_mask.mif"
FIXELMASK_FINAL="$FBA_GROUP_DIR/fixelmask/04_fixelmask_final"

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
[ ! -d $FD_DIR] && mkdir -p $FD_DIR $FC_DIR $LOG_FC_DIR $FDC_DIR

# Command
#########################
CMD_FOD2TEMPLATE="mrtransform $FOD_WM -warp $SUBJ2TEMP_WARP -noreorientation $FOD_WM_TEMP_NOREORIENT -force"
CMD_SUBJECTFOD2FIXEL="fod2fixel -mask $TEMPLATE_MASK $FOD_WM_TEMP_NOREORIENT $FIXELMASK_NOREORIENT -afd fd.mif -force"
CMD_REORIENTFIXELS="fixelreorient $FIXELMASK_NOREORIENT $SUB2TEMP_WARP $FIXELMASK_REORIENT -force"
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
FIXELMASK_FINAL="$FBA_GROUP_DIR/fixelmask/04_fixelmask_final"
SEGBUNDLE_TRACTOGRAM="$TRACTSEG_DIR/segmentation_bundle_tractogram.tck"

FD_DIR=$FBA_GROUP_DIR/fd
LOG_FC_DIR=$FBA_GROUP_DIR/log_fc
FDC_DIR=$FBA_GROUP_DIR/fdc

# Output
#########################
FIXELCONNECTIVITY_MAT=$FBA_GROUP_DIR/matrix
[ ! -d $FIXELCONNECTIVITY_MAT ] && mkdir $FIXELCONNECTIVITY_MAT

FD_SMOOTH_DIR=$FBA_GROUP_DIR/fd
LOG_FC_SMOOTH_DIR=$FBA_GROUP_DIR/log_fc
FDC_SMOOTH_DIR=$FBA_GROUP_DIR/fdc
[ ! -d $FD_SMOOTH_DIR] && mkdir -p $FD_SMOOTH_DIR $LOG_FC_SMOOTH_DIR $FDC_SMOOTH_DIR

# Command
#########################
CMD_FIXELCONNECTIVITY="fixelconnectivity $FIXELMASK_FINAL $BUNDLE_TRACTOGRAM $FIXELCONNECTIVITY_MAT"
CMD_FILTER_FD="fixelfilter $FD_DIR smooth $FD_SMOOTH_DIR -matrix $FIXELCONNECTIVITY_MAT"
CMD_FILTER_LOG_FC="fixelfilter $LOG_FC_DIR smooth $LOG_FC_SMOOTH_DIR -matrix $FIXELCONNECTIVITY_MAT"
CMD_FILTER_FDC="fixelfilter $FDC_DIR smooth $FDC_SMOOTH_DIR -matrix $FIXELCONNECTIVITY_MAT"

# Execution
#########################
$singularity_mrtrix3 \
/bin/bash -c "$CMD_FIXELCONNECTIVITY; $CMD_FILTER_FD; $CMD_FILTER_LOG_FC; $CMD_FILTER_FDC"