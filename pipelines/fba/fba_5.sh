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
###################################################################################################################

# Define subject array

input_subject_array=($@)

# Define environment
#########################
module load parallel

FW_DIR=$DATA_DIR/freewater
FBA_DIR=$DATA_DIR/fba
FBA_GROUP_DIR=$DATA_DIR/fba/derivatives
TEMPLATE_SUBJECTS_TXT=$FBA_DIR/sourcedata/template_subjects.txt
container_mrtrix3=mrtrix3-3.0.2      
container_mrtrix3tissue=mrtrix3tissue-5.2.8
container_tractseg=tractseg-master
export SINGULARITYENV_MRTRIX_TMPFILE_DIR=$TMP_DIR

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
# FA TO TEMPLATE + AVG
#########################

FA_TEMP_DIR=$FBA_DIR/derivatives/fa_template
TEMP2MNI_DIR=$FBA_DIR/derivatives/temp2mni
[ ! -d $FA_TEMP_DIR ] && mkdir -p $FA_TEMP_DIR/fa
[ ! -d $TEMP2MNI_DIR ] && mkdir $TEMP2MNI_DIR

# Input
#########################
FA="$FW_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-T1w_desc-DTINoNeg_FA.nii.gz"
SUB2TEMP_WARP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_from-subject_to-fodtemplate_warp.mif"
FA_MNI_TARGET="$ENV_DIR/standard/FSL_HCP1065_FA_1mm.nii.gz"
SCHAEFER200_MNI="$ENV_DIR/standard/Schaefer2018_200Parcels_17Networks_order_FSLMNI152_1mm.nii.gz"

# Output
#########################
FA_TEMP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-DTINoNeg_FA.nii.gz"
FA_AVG_TEMP="$FA_TEMP_DIR/FA_averaged.nii.gz"

# Command
#########################
CMD_MRTRANSFORM="mrtransform $FA -warp $SUB2TEMP_WARP -interp nearest -datatype bit $FA_TEMP -force"
CMD_AVG="mrmath $(ls -d -1 $FA_TEMP_DIR/fa/sub-*) mean $FA_AVG_TEMP --force"

# Execution
#########################
#$parallel "$singularity_mrtrix3 $CMD_MRTRANSFORM" ::: ${input_subject_array[@]}
#$parallel "[ -f $FA_TEMP ] && ln -srf $FA_TEMP $FA_TEMP_DIR/fa" ::: ${input_subject_array[@]}
#$singularity_mrtrix3 $CMD_AVG

#########################
# FA_TEMP 2 MNI + ATLAS 2 TEMP
#########################

# Input
#########################
FA_MNI_TARGET="envs/standard/FSL_HCP1065_FA_1mm.nii.gz"
ATLAS_MNI="envs/standard/Schaefer2018_{}Parcels_17Networks_order_FSLMNI152_1mm.nii.gz"
FA_AVG_TEMP="$FA_TEMP_DIR/FA_averaged.nii.gz"

# Output
#########################
FA_MNI="$FA_TEMP_DIR/FA_averaged_in_mni.nii.gz"
TEMP2MNI_WARP="$TEMP2MNI_DIR/FA_averaged_in_mni_InverseComposite.h5"
FA_TEMP="$FBA_DIR/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-FWcorrected_FA.nii.gz"
ATLAS_TEMP="$TEMP2MNI_DIR/Schaefer2018_{}Parcels_17Networks_order_FSLMNI152_space-fodtemplate_1mm.nii.gz"

CMD_TEMP2MNI="
antsRegistration \
    --output [ $TEMP2MNI_DIR/FA2MNI, $FA_TEMP_DIR/FA_averaged_in_mni.nii.gz ] \
    --collapse-output-transforms 0 \
    --dimensionality 3 \
    --initial-moving-transform [ $FA_MNI_TARGET, $FA_AVG_TEMP, 1 ] \
    --initialize-transforms-per-stage 0 \
    --interpolation Linear \
    --transform Rigid[ 0.1 ] \
    --metric MI[ $FA_MNI_TARGET, $FA_AVG_TEMP, 1, 32, Regular, 0.25 ] \
    --convergence [ 10000x111110x11110x100, 1e-08, 10 ] \
    --smoothing-sigmas 3.0x2.0x1.0x0.0vox \
    --shrink-factors 8x4x2x1 \
    --use-estimate-learning-rate-once 1 \
    --use-histogram-matching 1 \
    --transform Affine[ 0.1 ] \
    --metric MI[ $FA_MNI_TARGET, $FA_AVG_TEMP, 1, 32, Regular, 0.25 ] \
    --convergence [ 10000x111110x11110x100, 1e-08, 10 ] \
    --smoothing-sigmas 3.0x2.0x1.0x0.0vox \
    --shrink-factors 8x4x2x1 \
    --use-estimate-learning-rate-once 1 \
    --use-histogram-matching 1 \
    --transform SyN[ 0.2, 3.0, 0.0 ] \
    --metric CC[ $FA_MNI_TARGET, $FA_AVG_TEMP, 1, 4 ] \
    --convergence [ 100x50x30x20, 1e-08, 10 ] \
    --smoothing-sigmas 3.0x2.0x1.0x0.0vox \
    --shrink-factors 8x4x2x1 \
    --use-estimate-learning-rate-once 1 \
    --use-histogram-matching 1 -v \
    --winsorize-image-intensities [ 0.005, 0.995 ] \
    --write-composite-transform 1
"

CMD_ATLAS2TEMP="
antsApplyTransforms -d 3 -e 3 -n Linear \
            -i $ATLAS_MNI \
            -r $FA_AVG_TEMP \
            -o $ATLAS_TEMP \
            -t $TEMP2MNI_WARP
"

#$singularity_mrtrix3 $CMD_TEMP2MNI
$parallel $singularity_mrtrix3 $CMD_ATLAS2TEMP ::: 100 200 400 600