#!/usr/bin/env bash
set -x

###################################################################################################################
# Threshold-free cluster enhancement based statistics                                                             #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [manual preparation]                                                                                          #
#       - hypothesis directory in data/statistics with design_matrix.txt, contrast_matrix and files.txt           #
#   [pipelines which need to be run first]                                                                        #
#       - fba levels 1-4                                                                                          #
#   [container]                                                                                                   #
#       - mrtrix3-3.0.2.sif                                                                                       #
###################################################################################################################

# Define subject array

input_subject_array=($@)

# Define environment
#########################
module load parallel

container_mrtrix3=mrtrix3-3.0.2      
export SINGULARITYENV_MRTRIX_TMPFILE_DIR=$TMP_DIR

singularity_mrtrix3="singularity run --cleanenv --userns \
    -B . \
    -B $PROJ_DIR \
    -B $SCRATCH_DIR:/tmp \
    $ENV_DIR/$container_mrtrix3" 

#########################
# TFCE
#########################

STATISTICS_DIR=$DATA_DIR/statistics/${MODIFIER}
[ ! -d $STATISTICS_DIR ] && mkdir -p $STATISTICS_DIR && echo "Please setup $STATISTICS_DIR with 'design_matrix.txt' and 'files.txt'" && exit 0

# Input
#########################

# Desgin / contrast matrix for voxel metrics
DESIGN_MATRIX_VOXEL=$STATISTICS_DIR/design_tbss.txt
CONTRAST_MATRIX_VOXEL=$STATISTICS_DIR/contrast_tbss.txt

# Design /contrast matrix for fixel metrics
DESIGN_MATRIX_FIXEL=$STATISTICS_DIR/design_tbss_fba.txt
CONTRAST_MATRIX_FIXEL=$STATISTICS_DIR/contrast_tbss_fba.txt

# Text files with paths to skeletons relative to $STATISTICS_DIR
FILES_FD=$STATISTICS_DIR/files_fd.txt
FILES_LOG_FC=$STATISTICS_DIR/files_logfc.txt
FILES_FDC=$STATISTICS_DIR/files_fdc.txt
FILES_FA=$STATISTICS_DIR/files_fa.txt
FILES_AD=$STATISTICS_DIR/files_ad.txt
FILES_MD=$STATISTICS_DIR/files_md.txt
FILES_RD=$STATISTICS_DIR/files_rd.txt
FILES_FAt=$STATISTICS_DIR/files_fat.txt
FILES_ADt=$STATISTICS_DIR/files_adt.txt
FILES_MDt=$STATISTICS_DIR/files_mdt.txt
FILES_RDt=$STATISTICS_DIR/files_rdt.txt
FILES_COMP=$STATISTICS_DIR/files_complexity.txt
FILES_FW=$STATISTICS_DIR/files_fw.txt

# Skeleton mask
MASK=$DATA_DIR/tbss_mni/derivatives/sub-all/ses-1/dwi/sub-all_ses-1_space-MNI_desc-skeleton_desc-meanFA_mask.nii.gz
[ -f $DESIGN_MATRIX_FIXEL ] && MASK=$DATA_DIR/tbss_fixel/derivatives/sub-all/ses-1/dwi/sub-all_ses-1_space-fodtemplate_desc-skeleton_desc-meanFA_mask.nii.gz

# Commands
#########################

# Fixel metrics
CMD_TFCE_FD="mrclusterstats $FILES_FD $DESIGN_MATRIX_FIXEL $CONTRAST_MATRIX_FIXEL $MASK stats_fd -force"
CMD_TFCE_FC="mrclusterstats $FILES_LOG_FC $DESIGN_MATRIX_FIXEL $CONTRAST_MATRIX_FIXEL $MASK stats_log_fc -force"
CMD_TFCE_FDC="mrclusterstats $FILES_FDC $DESIGN_MATRIX_FIXEL $CONTRAST_MATRIX_FIXEL $MASK stats_fdc -force"


# Voxel metrics
CMD_TFCE_FA="mrclusterstats $FILES_FA $DESIGN_MATRIX_VOXEL $CONTRAST_MATRIX_VOXEL $MASK stats_fa -force"
CMD_TFCE_AD="mrclusterstats $FILES_AD $DESIGN_MATRIX_VOXEL $CONTRAST_MATRIX_VOXEL $MASK stats_ad -force"
CMD_TFCE_MD="mrclusterstats $FILES_MD $DESIGN_MATRIX_VOXEL $CONTRAST_MATRIX_VOXEL $MASK stats_md -force"
CMD_TFCE_RD="mrclusterstats $FILES_RD $DESIGN_MATRIX_VOXEL $CONTRAST_MATRIX_VOXEL $MASK stats_rd -force"
CMD_TFCE_FAt="mrclusterstats $FILES_FAt $DESIGN_MATRIX_VOXEL $CONTRAST_MATRIX_VOXEL $MASK stats_fat -force"
CMD_TFCE_ADt="mrclusterstats $FILES_ADt $DESIGN_MATRIX_VOXEL $CONTRAST_MATRIX_VOXEL $MASK stats_adt -force"
CMD_TFCE_MDt="mrclusterstats $FILES_MDt $DESIGN_MATRIX_VOXEL $CONTRAST_MATRIX_VOXEL $MASK stats_mdt -force"
CMD_TFCE_RDt="mrclusterstats $FILES_RDt $DESIGN_MATRIX_VOXEL $CONTRAST_MATRIX_VOXEL $MASK stats_rdt -force"
CMD_TFCE_FW="mrclusterstats $FILES_FW $DESIGN_MATRIX_VOXEL $CONTRAST_MATRIX_VOXEL $MASK stats_fw -force"
CMD_TFCE_COMP="mrclusterstats $FILES_COMP $DESIGN_MATRIX_VOXEL $CONTRAST_MATRIX_VOXEL $MASK stats_complexity -force"

# Execution
#########################

pushd $STATISTICS_DIR

$singularity_mrtrix3 $CMD_TFCE_FA
$singularity_mrtrix3 $CMD_TFCE_AD
$singularity_mrtrix3 $CMD_TFCE_MD
$singularity_mrtrix3 $CMD_TFCE_RD
$singularity_mrtrix3 $CMD_TFCE_FAt
$singularity_mrtrix3 $CMD_TFCE_ADt
$singularity_mrtrix3 $CMD_TFCE_MDt
$singularity_mrtrix3 $CMD_TFCE_RDt
$singularity_mrtrix3 $CMD_TFCE_FW

if [ -f $DESIGN_MATRIX_FIXEL ]; then

    $singularity_mrtrix3 $CMD_TFCE_FD
    $singularity_mrtrix3 $CMD_TFCE_LOG_FC
    $singularity_mrtrix3 $CMD_TFCE_FDC
    $singularity_mrtrix3 $CMD_TFCE_COMP

fi

popd