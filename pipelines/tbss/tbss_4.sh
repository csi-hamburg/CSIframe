#!/bin/bash

###########################################################
# FSL TBSS implementation for parallelized job submission #
###########################################################

###############################################################################
# Pipeline specific dependencies:                                             #
#   [pipelines which need to be run first]                                    #
#       - qsiprep                                                             #
#       - freewater                                                           #
#       - fba (only for fixel branch)                                         #
#       - tbss_1                                                              #
#       - tbss_2                                                              #
#       - tbss_3                                                              #
#   [containers and code]                                                     #
#       - fsl-6.0.3                                                           #
#       - overlay.py                                                          #
#       - stats.py                                                            #
#       - report.py                                                           #  
###############################################################################

########################################################
# PART 4 - merging of skeletons and quality assessment #
########################################################

# Setup environment
###################

module load singularity

container_fsl=fsl-6.0.3
singularity_fsl="singularity run --cleanenv --userns \
    -B . \
    -B $PROJ_DIR \
    -B $SCRATCH_DIR:/tmp \
    -B $(readlink -f $ENV_DIR) \
    $ENV_DIR/$container_fsl" 

container_miniconda=miniconda-csi
singularity_miniconda=" singularity run --cleanenv --userns \
    -B . \
    -B $PROJ_DIR \
    -B $SCRATCH_DIR:/tmp \
    -B $(readlink -f $ENV_DIR) \
    -B /usw
    /usw/fatx405/csi_envs/$container_miniconda"

# Set pipeline specific variables

if [ $TBSS_PIPELINE == "mni" ]; then

    SPACE=MNI
    MODALITIES="desc-DTINoNeg_FA desc-FWcorrected_FA desc-DTINoNeg_L1 desc-FWcorrected_L1 desc-DTINoNeg_RD \
                desc-FWcorrected_RD desc-DTINoNeg_MD desc-FWcorrected_MD FW"
    
elif [ $TBSS_PIPELINE == "fixel" ]; then

    SPACE=fodtemplate
    MODALITIES="desc-DTINoNeg_FA desc-FWcorrected_FA desc-DTINoNeg_L1 desc-FWcorrected_L1 desc-DTINoNeg_RD \
                desc-FWcorrected_RD desc-DTINoNeg_MD desc-FWcorrected_MD FW desc-voxelmap_fd desc-voxelmap_fdc \
                desc-voxelmap_logfc desc-voxelmap_complexity"

fi

# Input
#######

TBSS_DIR=$DATA_DIR/tbss_${TBSS_PIPELINE}
DER_DIR=$TBSS_DIR/derivatives/sub-${TBSS_MERGE_LIST}/ses-${SESSION}/dwi
CASELIST=$TBSS_DIR/sourcedata/caselist.txt

echo "TBSS_DIR = $TBSS_DIR"
echo "DER_DIR = $DER_DIR"
echo "TBSS_MERGE_LIST = $TBSS_MERGE_LIST"

# Check if TBSS 3 has already been run and create list of subjects with TBSS 3 output

echo "sub_id,source" > $TBSS_DIR/sourcedata/sourcedata.csv

files_complete=y

for sub in $(ls $TBSS_DIR/sub*/ses-$SESSION/dwi/*_ses-${SESSION}_space-${SPACE}_desc-eroded_desc-DTINoNeg_FA.nii.gz | rev | cut -d "/" -f 1 | rev | cut -d "_" -f 1); do

    img=`ls $TBSS_DIR/$sub/ses-$SESSION/dwi/*desc-skeleton*FA.nii.gz | head -n 1`
    
    if [ -f $img ]; then
        
        echo "$sub,$PROJ_DIR/data/freewater/$sub/$SESSION/dwi" >> $TBSS_DIR/sourcedata/sourcedata.csv
        echo "$sub" >> $TBSS_DIR/sourcedata/caselist.txt

    else

        files_complete=n

    fi

done

if [ $files_complete == "n" ]; then
    
    echo "TBSS 3 has not been run for all subjects in $TBSS_DIR yet. Exiting ..."

    exit
fi

# Remove output of previous runs
################################

FA_SKEL_MERGED=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-DTINoNeg_FA.nii.gz

if [ -f $FA_SKEL_MERGED ]; then
    
    echo ""
    echo "TBSS Part 4 (tbss_4.sh) has already been run for merge list "$TBSS_MERGE_LIST". Removing output of previous run first ..."
    echo ""

    rm -rvf $DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-DTINoNeg*
    rm -rvf $DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-FWCorrected*
    rm -rvf $TBSS_DIR/sub-*/ses-${SESSION}/dwi/*_overlay.png
    rm -rvf $DER_DIR/*.png
    rm -rvf $DER_DIR/*.csv
    rm -rvf $DER_DIR/*.html
    rm -rvf $DER_DIR/*.txt

    if [ $TBSS_PIPELINE == "fixel" ]; then

    rm -rvf $DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-voxelmap*

    fi

fi

#######################################
# Merging skeletons for each modality #
#######################################

for MOD in $(echo $MODALITIES); do

    echo ""
    echo $MOD
    echo ""

    # Merging outputs

    MERGE_LIST_MOD=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_${MOD}_mergelist.txt
    MOD_SKEL_MERGED=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_${MOD}.nii.gz

    if [ $TBSS_MERGE_LIST == "all" ]; then
    
        $singularity_fsl fslmerge \
            -t $MOD_SKEL_MERGED \
            $TBSS_DIR/sub-*/ses-${SESSION}/dwi/*desc-skeleton*${MOD}.nii.gz
        

    else

        for sub in $(echo $TBSS_DIR/code/merge_${TBSS_MERGE_LIST}.txt); do

            echo $MOD_SKEL >> $MERGE_LIST_MOD
        
        done

        $singularity_fsl fslmerge \
            -t $MOD_SKEL_MERGED \
            $(cat $MERGE_LIST_MOD)
    fi

done

###########################
# Combine individual CSVs #
###########################

# Get random subject to extract columm names from csv
#####################################################

CASELIST_ARRAY=(`sort - R $CASELIST`)
RAND_SUB=`echo $CASLIST_ARRAY[1]`

if [ $TBSS_PIPELINE == "mni" ]; then

    # Input
    #######

    ROI_CSV_RAND=$TBSS_DIR/$RAND_SUB/ses-${SESSION}/dwi/${RAND_SUB}_ses-${SESSION}_space-${SPACE}_desc-skeleton_label-JHU_desc-ROIs_means.csv
    
    # Output
    ########
    
    ROI_CSV_MERGED=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_label-JHU_desc-ROIs_means.csv

    # Create CSV
    ############

    head -n 1 $ROI_CSV_RAND > $ROI_CSV_MERGED

    for sub in $(cat $CASELIST); do

        ROI_CSV=$TBSS_DIR/$sub/ses-${SESSION}/dwi/${sub}_ses-${SESSION}_space-${SPACE}_desc-skeleton_label-JHU_desc-ROIs_means.csv
        tail -n 1 $ROI_CSV >> $ROI_CSV_MERGED
    
    done

if [ $TBSS_PIPELINE == "fixel" ]; then

    # Input
    #######
    
    MEAN_CSV_RAND=$TBSS_DIR/$RAND_SUB/ses-${SESSION}/dwi/${RAND_SUB}_ses-${SESSION}_space-${SPACE}_desc-skeleton_means.csv
    
    # Output
    ########
    
    MEAN_CSV_MERGED=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_means.csv

    # Create CSV
    ############

    head -n 1 $MEAN_CSV_RAND > $ROI_CSV_MERGED

    for sub in $(cat $CASELIST); do
    
        MEAN_CSV=$TBSS_DIR/$sub/ses-${SESSION}/dwi/${sub}_ses-${SESSION}_space-${SPACE}_desc-skeleton_means.csv
        tail -n 1 $MEAN_CSV >> $ROI_CSV_MERGED
    
    done

###############################################################################################
# Make boxplot and histogram of mean across skeleton for each modality and create html report #
###############################################################################################

if [ $TBSS_PIPELINE == "fixel"]; then

    MODALITIES="desc-DTINoNeg_FA desc-FWcorrected_FA desc-DTINoNeg_L1 desc-FWcorrected_L1 desc-DTINoNeg_RD \
                desc-FWcorrected_RD desc-DTINoNeg_MD desc-FWcorrected_MD FW desc-voxelmap_fd desc-voxelmap_fdc \
                desc-voxelmap_logfc desc-voxelmap_complexity"
    CSV=$MEAN_CSV_MERGED

    # Create stats figures
    ######################

    for MOD in FA FAt AD ADt RD RDt MD MDt FW fd fdc logfc complexity; do

        # Stats output

        HISTFIG=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-mean${MOD}_histogram.png
        BOXFIG=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-mean${MOD}_boxplot.png
        ZSCORE=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-mean_zscores.csv
        
        # Command 

        $singularity_miniconda python stats.py $TBSS_PIPELINE $MOD $CSV $HISTFIG $BOXFIG $ZSCORE

    done

    # Create HTML report
    ####################

    for MODALITY in $(echo $MODALITIES); do

        [ $MODALITY == "desc-DTINoNeg_FA" ] && MOD="FA"
        [ $MODALITY == "desc-FWcorrected_FA" ] && MOD="FAt"
        [ $MODALITY == "desc-DTINoNeg_L1" ] && MOD="AD"
        [ $MODALITY == "desc-FWcorrected_L1" ] && MOD="ADt"
        [ $MODALITY == "desc-DTINoNeg_RD" ] && MOD="RD"
        [ $MODALITY == "desc-FWcorrected_RD" ] && MOD="RDt"
        [ $MODALITY == "desc-DTINoNeg_MD" ] && MOD="MD"
        [ $MODALITY == "desc-FWcorrected_MD" ] && MOD="MDt"
        [ $MODALITY == "FW" ] && MOD="FW"
        [ $MODALITY == "desc-voxelmap_fd" ] && MOD="fd"
        [ $MODALITY == "desc-voxelmap_fdc" ] && MOD="fdc"
        [ $MODALITY == "desc-voxelmap_logfc" ] && MOD="logfc"
        [ $MODALITY == "desc-voxelmap_complexity" ] && MOD="complexity"

        # Input: stats figures

        HISTFIG=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-mean${MOD}_histogram.png
        BOXFIG=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-mean${MOD}_boxplot.png

        # Output: HTML report

        REPORT=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_${MODALITY}_report.html

        $singularity_miniconda python report.py \
            $TBSS_DIR \
            $SESSSION \
            $SPACE \
            $MODALITY \
            $HISTFIG \
            $BOXFIG \
            $REPORT
    done

elif [ $TBSS_PIPELINE == "mni"]; then
    
    MODALITIES="desc-DTINoNeg_FA desc-FWcorrected_FA desc-DTINoNeg_L1 desc-FWcorrected_L1 desc-DTINoNeg_RD \
                desc-FWcorrected_RD desc-DTINoNeg_MD desc-FWcorrected_MD FW"
    CSV=$ROI_CSV_MERGED

    # Create stats figures
    ######################

    for MOD in FA FAt AD ADt RD RDt MD MDt FW; do

        # Stats output

        HISTFIG=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-mean${MOD}_histogram.png
        BOXFIG=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-mean${MOD}_boxplot.png
        ZSCORE=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_label-JHU_desc-mean_zscores.csv

        # Command

        $singularity_miniconda python stats.py $TBSS_PIPELINE $MOD $CSV $HISTFIG $BOXFIG $ZSCORE

    done

    # Create HTML report
    ####################

    for MODALITY in $(echo $MODALITIES); do

        [ $MODALITY == "desc-DTINoNeg_FA" ] && MOD="FA"
        [ $MODALITY == "desc-FWcorrected_FA" ] && MOD="FAt"
        [ $MODALITY == "desc-DTINoNeg_L1" ] && MOD="AD"
        [ $MODALITY == "desc-FWcorrected_L1" ] && MOD="ADt"
        [ $MODALITY == "desc-DTINoNeg_RD" ] && MOD="RD"
        [ $MODALITY == "desc-FWcorrected_RD" ] && MOD="RDt"
        [ $MODALITY == "desc-DTINoNeg_MD" ] && MOD="MD"
        [ $MODALITY == "desc-FWcorrected_MD" ] && MOD="MDt"
        [ $MODALITY == "FW" ] && MOD="FW"

        $singularity_miniconda python report.py \
            $TBSS_DIR \
            $SESSSION \
            $SPACE \
            $MODALITY \
            $HISTFIG \
            $BOXFIG \
            $REPORT
    done

fi