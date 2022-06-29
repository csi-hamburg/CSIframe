#!/bin/bash

###########################################################
# FSL TBSS implementation for parallelized job submission #
#                                                         #
# PART 4 - merging of skeletons and quality assessment    #
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
#       - stats.py                                                            #
#       - report.py                                                           #
#       - csi-miniconda                                                       #  
###############################################################################

# Get verbose outputs
set -x

# Define subject specific temporary directory on $SCRATCH_DIR
export TMP_DIR=$SCRATCH_DIR/$1/tmp/;   [ ! -d $TMP_DIR ] && mkdir -p $TMP_DIR
TMP_IN=$TMP_DIR/input;                 [ ! -d $TMP_IN ] && mkdir -p $TMP_IN
TMP_OUT=$TMP_DIR/output;               [ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT

###############################################################################

# Setup environment
###################

module load singularity

container_fsl=fsl-6.0.3
singularity_fsl="singularity run --cleanenv --no-home --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR \
    -B $TMP_IN \
    -B $TMP_OUT \
    $ENV_DIR/$container_fsl"

container_miniconda=miniconda-csi
singularity_miniconda="singularity run --cleanenv --no-home --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR \
    -B $TMP_IN \
    -B $TMP_OUT \
    $ENV_DIR/$container_miniconda"

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

[ -f $CASELIST ] && rm -rvf $CASELIST

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
    rm -rvf $DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-FWcorrected*
    rm -rvf $DER_DIR/*.html
    rm -rvf $DER_DIR/*.txt
    rm -rvf $DER_DIR/*.pdf
    rm -rvf $DER_DIR/*.csv

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

    if [ $TBSS_MERGE_LIST == "all" ]; then
    
        # If more than 700 skeletons are to be merged, intermediate merges are necessary for RAM reasons
        ################################################################################################

        # Count number of subjects
        ##########################

        subj_batch_array=($(ls $TBSS_DIR/sub-* -d))
        subj_array_length=${#subj_batch_array[@]}
        echo $subj_array_length
        
        if [ $subj_array_length -gt 700 ]; then

            # Define number of subjects to be merged in one intermediate 4D image
            #####################################################################

            subj_per_batch=700
            batch_amount=$(($subj_array_length / $subj_per_batch))
            export START=1

            # If modulo of subject array length and subj_per_batch is not 0 -> add one iteration to make sure all subjects will be processed
            
            [ ! $(( $subj_array_length % $subj_per_batch )) -eq 0 ] && batch_amount=$(($batch_amount + 1))

            # Loop through subject batches
            ##############################

            for batch in $(seq -w $batch_amount); do

                echo ""
                echo "Merging batch $batch ..."
                echo ""

                # Define end of batch
                
                export END=$(($subj_per_batch * $batch))

                # Define output

                MOD_SKEL_MERGED_INTERMEDIATE=$TMP_OUT/batch-${batch}_ses-${SESSION}_space-${SPACE}_desc-skeleton_${MOD}.nii.gz

                # Define commands

                CMD_MERGE_INTERMEDIATE="fslmerge -t $MOD_SKEL_MERGED_INTERMEDIATE $(ls $TBSS_DIR/sub-*/ses-${SESSION}/dwi/*desc-skeleton*${MOD}.nii.gz | sed -n "$START,${END}p")"
                
                # Execute commands for batch

                $singularity_fsl $CMD_MERGE_INTERMEDIATE

                # Increase START by subj_per_batch

                export START=$(($START + $subj_per_batch))

            done

            # Merge batches to final 4D image
            #################################

            # Define output

            MOD_SKEL_MERGED=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_${MOD}.nii.gz

            # Command

            $singularity_fsl fslmerge \
                -t $MOD_SKEL_MERGED \
                $TMP_OUT/batch-*_ses-${SESSION}_space-${SPACE}_desc-skeleton_${MOD}.nii.gz
            
        else

            MOD_SKEL_MERGED=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_${MOD}.nii.gz

            $singularity_fsl fslmerge \
                -t $MOD_SKEL_MERGED \
                $TBSS_DIR/sub-*/ses-${SESSION}/dwi/*desc-skeleton*${MOD}.nii.gz
        
        fi
        
    elif [ $TBSS_MERGE_LIST =! "all" ]; then

        # Define output

        MERGE_LIST_MOD=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_${MOD}_mergelist.txt

        # Create list of paths to skeletons to be merged
        ################################################

        for sub in $(echo $TBSS_DIR/code/merge_${TBSS_MERGE_LIST}.txt); do
            
            MOD_SKEL=$TBSS_DIR/$sub/ses-${SESSION}/dwi/${sub}_ses-${SESSION}_space-${SPACE}_desc-skeleton_${MOD}.nii.gz
            echo $MOD_SKEL >> $MERGE_LIST_MOD
        
        done

        # Count number of subjects
        ##########################

        subj_array_length=$(cat $MERGE_LIST_MOD | wc -l)
        echo $subj_array_length

        if [ $subj_array_length -gt 700 ]; then

            # Define number of subjects to be merged in one intermediate 4D image
            #####################################################################

            subj_per_batch=700
            batch_amount=$(($subj_array_length / $subj_per_batch))
            export START=1

            # If modulo of subject array length and subj_per_batch is not 0 -> add one iteration to make sure all subjects will be processed
            
            [ ! $(( $subj_array_length % $subj_per_batch )) -eq 0 ] && batch_amount=$(($batch_amount + 1))

            # Loop through subject batches
            ##############################

            for batch in $(seq -w $batch_amount); do

                echo ""
                echo "Merging batch $batch ..."
                echo ""

                # Define end of batch
                
                export END=$(($subj_per_batch * $batch))

                # Define output

                MOD_SKEL_MERGED_INTERMEDIATE=$TMP_OUT/batch-${batch}_ses-${SESSION}_space-${SPACE}_desc-skeleton_${MOD}.nii.gz

                # Define commands

                CMD_MERGE_INTERMEDIATE="fslmerge -t $MOD_SKEL_MERGED_INTERMEDIATE $(cat $MERGE_LIST_MOD) | sed -n "$START,${END}p")"
                
                # Execute commands for batch

                $singularity_fsl $CMD_MERGE_INTERMEDIATE

                # Increase START by subj_per_batch

                export START=$(($START + $subj_per_batch))

            done

            # Merge batches to final 4D image
            #################################

            # Define output

            MOD_SKEL_MERGED=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_${MOD}.nii.gz

            # Command

            $singularity_fsl fslmerge \
                -t $MOD_SKEL_MERGED \
                $TMP_OUT/batch-*_ses-${SESSION}_space-${SPACE}_desc-skeleton_${MOD}.nii.gz
            
        else

            $singularity_fsl fslmerge \
                -t $MOD_SKEL_MERGED \
                $(cat $MERGE_LIST_MOD)
        fi

    fi

done

###########################
# Combine individual CSVs #
###########################

# Get random subject to extract columm names from csv
#####################################################

CASELIST_ARRAY=(`sort -R $CASELIST`)
RAND_SUB=`echo ${CASELIST_ARRAY[1]}`

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

elif [ $TBSS_PIPELINE == "fixel" ]; then

    # Input
    #######
    
    MEAN_CSV_RAND=$TBSS_DIR/$RAND_SUB/ses-${SESSION}/dwi/${RAND_SUB}_ses-${SESSION}_space-${SPACE}_desc-skeleton_means.csv
    
    # Output
    ########
    
    MEAN_CSV_MERGED=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_means.csv

    # Create CSV
    ############

    head -n 1 $MEAN_CSV_RAND > $MEAN_CSV_MERGED

    for sub in $(cat $CASELIST); do
    
        MEAN_CSV=$TBSS_DIR/$sub/ses-${SESSION}/dwi/${sub}_ses-${SESSION}_space-${SPACE}_desc-skeleton_means.csv
        tail -n 1 $MEAN_CSV >> $MEAN_CSV_MERGED
    
    done

fi

###############################################################################################
# Make boxplot and histogram of mean across skeleton for each modality and create html report #
###############################################################################################

if [ $TBSS_PIPELINE == "fixel" ]; then

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
        
        # Command 

        $singularity_miniconda python $PIPELINE_DIR/stats.py "" $MOD $CSV $HISTFIG $BOXFIG

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

        $singularity_miniconda python $PIPELINE_DIR/report.py $TBSS_DIR $SESSION $SPACE $MODALITY $HISTFIG $BOXFIG $REPORT

    done

elif [ $TBSS_PIPELINE == "mni" ]; then
    
    MODALITIES="desc-DTINoNeg_FA desc-FWcorrected_FA desc-DTINoNeg_L1 desc-FWcorrected_L1 desc-DTINoNeg_RD \
                desc-FWcorrected_RD desc-DTINoNeg_MD desc-FWcorrected_MD FW"
    CSV=$ROI_CSV_MERGED

    # Create stats figures
    ######################

    for MOD in FA FAt AD ADt RD RDt MD MDt FW; do

        # Stats output

        HISTFIG=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-mean${MOD}_histogram.png
        BOXFIG=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-mean${MOD}_boxplot.png

        # Command

        $singularity_miniconda python $PIPELINE_DIR/stats.py $TBSS_PIPELINE $MOD $CSV $HISTFIG $BOXFIG

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

        # Input: stats figures

        HISTFIG=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-mean${MOD}_histogram.png
        BOXFIG=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-mean${MOD}_boxplot.png

        # Output: HTML report

        REPORT=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_${MODALITY}_report.html

        $singularity_miniconda python $PIPELINE_DIR/report.py $TBSS_DIR $SESSION $SPACE $MODALITY $HISTFIG $BOXFIG $REPORT

    done

fi