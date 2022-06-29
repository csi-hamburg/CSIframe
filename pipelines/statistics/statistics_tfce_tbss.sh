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


container_fsl=fsl-6.0.3     

singularity_fsl="singularity run --cleanenv --userns \
    -B . \
    -B $PROJ_DIR \
    -B $SCRATCH_DIR:/tmp \
    -B $(readlink -f $ENV_DIR) \
    $ENV_DIR/$container_fsl"

#########################
# TFCE
#########################

STATISTICS_DIR=$DATA_DIR/statistics/${MODIFIER}
[ ! -d $STATISTICS_DIR ] && mkdir -p $STATISTICS_DIR && echo "Please setup $STATISTICS_DIR with 'design_matrix.txt' and 'files.txt'" && exit 0

# Input
#########################

# Design / contrast matrix for DTI metrics
DESIGN_MATRIX_DTI=$STATISTICS_DIR/design_tbss.txt
CONTRAST_MATRIX_DTI=$STATISTICS_DIR/contrast_tbss.txt

# Design / contrast matrix for FBA metrics not sensitive to brain volume
DESIGN_MATRIX_FBA=$STATISTICS_DIR/design_tbss_fba.txt
CONTRAST_MATRIX_FBA=$STATISTICS_DIR/contrast_tbss_fba.txt

# Design /contrast matrix for brain volume sensitive metrics
DESIGN_MATRIX_FBA_TIV=$STATISTICS_DIR/design_tbss_fba_tiv.txt
CONTRAST_MATRIX_FBA_TIV=$STATISTICS_DIR/contrast_tbss_fba_tiv.txt

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
[ -f $DESIGN_MATRIX_FBA ] && MASK=$DATA_DIR/tbss_fixel/derivatives/sub-all/ses-1/dwi/sub-all_ses-1_space-fodtemplate_desc-skeleton_desc-meanFA_mask.nii.gz

# # Create output directories
# ###########################

# if [ -f $DESIGN_MATRIX_DTI ]; then

#     mkdir $STATISTICS_DIR/fa_stats
#     mkdir $STATISTICS_DIR/fat_stats
#     mkdir $STATISTICS_DIR/ad_stats
#     mkdir $STATISTICS_DIR/adt_stats
#     mkdir $STATISTICS_DIR/rd_stats
#     mkdir $STATISTICS_DIR/rdt_stats
#     mkdir $STATISTICS_DIR/md_stats
#     mkdir $STATISTICS_DIR/mdt_stats
#     mkdir $STATISTICS_DIR/fw_stats

# fi

# if [ -f $DESIGN_MATRIX_FBA ]; then

#     mkdir $STATISTICS_DIR/fd_stats
#     mkdir $STATISTICS_DIR/complexity_stats

# fi

# if [ -f $DESIGN_MATRIX_FBA_TIV ]; then

#     mkdir $STATISTICS_DIR/logfc_stats
#     mkdir $STATISTICS_DIR/fdc_stats
# fi

# Commands
#########################

# FBA TIV
CMD_TFCE_LOG_FC="mrclusterstats -strong $FILES_LOG_FC $DESIGN_MATRIX_FBA_TIV $CONTRAST_MATRIX_FBA_TIV $MASK logfc_stats/logfc_ -force"
CMD_TFCE_FDC="mrclusterstats -strong $FILES_FDC $DESIGN_MATRIX_FBA_TIV $CONTRAST_MATRIX_FBA_TIV $MASK fdc_stats/fdc_ -force"

# FBA
CMD_TFCE_FD="mrclusterstats -strong $FILES_FD $DESIGN_MATRIX_FBA $CONTRAST_MATRIX_FBA $MASK fd_stats/fd_ -force"
CMD_TFCE_COMP="mrclusterstats -strong $FILES_COMP $DESIGN_MATRIX_FBA $CONTRAST_MATRIX_FBA $MASK complexity_stats/complexity_ -force"

# DTI
CMD_TFCE_FA="mrclusterstats -strong $FILES_FA $DESIGN_MATRIX_DTI $CONTRAST_MATRIX_DTI $MASK fa_stats/fa_ -force"
CMD_TFCE_AD="mrclusterstats -strong $FILES_AD $DESIGN_MATRIX_DTI $CONTRAST_MATRIX_DTI $MASK ad_stats/ad_ -force"
CMD_TFCE_MD="mrclusterstats -strong $FILES_MD $DESIGN_MATRIX_DTI $CONTRAST_MATRIX_DTI $MASK md_stats/md_ -force"
CMD_TFCE_RD="mrclusterstats -strong $FILES_RD $DESIGN_MATRIX_DTI $CONTRAST_MATRIX_DTI $MASK rd_stats/rd_ -force"
CMD_TFCE_FAt="mrclusterstats -strong $FILES_FAt $DESIGN_MATRIX_DTI $CONTRAST_MATRIX_DTI $MASK fat_stats/fat_ -force"
CMD_TFCE_ADt="mrclusterstats -strong $FILES_ADt $DESIGN_MATRIX_DTI $CONTRAST_MATRIX_DTI $MASK adt_stats/adt_ -force"
CMD_TFCE_MDt="mrclusterstats -strong $FILES_MDt $DESIGN_MATRIX_DTI $CONTRAST_MATRIX_DTI $MASK mdt_stats/mdt_ -force"
CMD_TFCE_RDt="mrclusterstats -strong $FILES_RDt $DESIGN_MATRIX_DTI $CONTRAST_MATRIX_DTI $MASK rdt_stats/rdt_ -force"
CMD_TFCE_FW="mrclusterstats -strong $FILES_FW $DESIGN_MATRIX_DTI $CONTRAST_MATRIX_DTI $MASK fw_stats/fw_ -force"

# # Execution
# #########################

# pushd $STATISTICS_DIR

# if [ -f $DESIGN_MATRIX_DTI ]; then

#     $singularity_mrtrix3 $CMD_TFCE_FA
#     $singularity_mrtrix3 $CMD_TFCE_AD
#     $singularity_mrtrix3 $CMD_TFCE_MD
#     $singularity_mrtrix3 $CMD_TFCE_RD
#     $singularity_mrtrix3 $CMD_TFCE_FAt
#     $singularity_mrtrix3 $CMD_TFCE_ADt
#     $singularity_mrtrix3 $CMD_TFCE_MDt
#     $singularity_mrtrix3 $CMD_TFCE_RDt
#     $singularity_mrtrix3 $CMD_TFCE_FW

# fi

# if [ -f $DESIGN_MATRIX_FBA ]; then

#     $singularity_mrtrix3 $CMD_TFCE_FD
#     $singularity_mrtrix3 $CMD_TFCE_COMP

# fi

# if [ -f $DESIGN_MATRIX_FBA_TIV ]; then

#     $singularity_mrtrix3 $CMD_TFCE_LOG_FC
#     $singularity_mrtrix3 $CMD_TFCE_FDC
# fi

# popd

############################################################ 
# Visualize and calculate percentage of significant voxels #
############################################################

pushd $STATISTICS_DIR

# Mean FA
MEAN_FA=$DATA_DIR/tbss_mni/derivatives/sub-all/ses-1/dwi/sub-all_ses-1_space-MNI_desc-brain_desc-mean_desc-DTINoNeg_FA.nii.gz
[ -f $DESIGN_MATRIX_FBA ] && MEAN_FA=$DATA_DIR/tbss_fixel/derivatives/sub-all/ses-1/dwi/sub-all_ses-1_space-fodtemplate_desc-brain_desc-mean_desc-DTINoNeg_FA.nii.gz

# Create CSV
CSV=$STATISTICS_DIR/percentages.csv
echo "test,no_skeleton_voxels,no_sig_voxels,percentage" > $CSV
NUM_VOXEL_TOTAL=`$singularity_fsl fslstats $MASK -V | tail -n 1 | cut -d " " -f 1`


for mod in $(ls *stats -d | cut -d "_" -f 1); do 

    chmod 770 -R ${mod}_stats

    for img in $(ls ${mod}_stats/${mod}*1mpvalue* | cut -d "." -f -1); do

        # Convert to nifti
        $singularity_mrtrix3 mrconvert ${img}.mif ${img}.nii.gz -force
        chmod 770 ${img}.nii.gz

        # Fill significant voxels
        $singularity_fsl tbss_fill ${img}.nii.gz 0.95 $MEAN_FA ${img}_p05_fill.nii.gz

        # Calculate percentage of significant voxels
        $singularity_fsl fslmaths ${img}.nii.gz -thr 0.95 -bin ${img}_p05.nii.gz

        NUM_VOXEL_TEST=`$singularity_fsl fslstats ${img}_p05.nii.gz -V | tail -n 1 | cut -d " " -f 1`
        PERCENTAGE=`printf %.3f "$((10**4 * ${NUM_VOXEL_TEST} / ${NUM_VOXEL_TOTAL}))e-4"`

        echo "$img,$NUM_VOXEL_TOTAL,$NUM_VOXEL_TEST,$PERCENTAGE" >> $CSV

    done

done

popd

