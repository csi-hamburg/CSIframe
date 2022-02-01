#!/usr/bin/env bash

##################################################################################################
# Submission script for white matter lesion analysis                                             #
#                                                                                                #
# Part II: extract means for each shell, normalize and combine in csv                            #
##################################################################################################

##################################################################################################
# Pipeline specific dependencies:                                                                #
#   [pipelines which need to be run first]                                                       #
#       - freesurfer reconstruction (e.g. as part of qsiprep or fmriprep)                        #
#       - lesion segmentation of some sort                                                       #
#       - lesionanalysis_1.sh                                                                    #
#   [container]                                                                                  #
#       - fsl-6.0.3                                                                              #
##################################################################################################

# Get verbose outputs
set -x

# Define subject specific temporary directory on $SCRATCH_DIR
export TMP_DIR=$SCRATCH_DIR/$1/tmp;   [ ! -d $TMP_DIR ] && mkdir -p $TMP_DIR
TMP_IN=$TMP_DIR/input;                 [ ! -d $TMP_IN ] && mkdir -p $TMP_IN
TMP_OUT=$TMP_DIR/output;               [ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT

###################################################################################################################

# Define environment
####################

parallel="parallel --ungroup --delay 0.2 -j16 --joblog $CODE_DIR/log/parallel_runtask.log"

container_fsl=fsl-6.0.3
singularity_fsl="singularity run --cleanenv --no-home --userns \
    -B .
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR \
    -B $TMP_IN \
    -B $TMP_OUT \
    $ENV_DIR/$container_fsl"

# Input directory
#################

LA_DIR=$DATA_DIR/lesionanalysis

# Create output directory
#########################

[ $READOUT_SPACE == "T1w" ] && DER_DIR=$LA_DIR/derivatives/ses-${SESSION}/anat
[ $READOUT_SPACE == "FLAIR" ] && DER_DIR=$LA_DIR/derivatives/ses-${SESSION}/anat
[ $READOUT_SPACE == "dwi" ] && DER_DIR=$LA_DIR/derivatives/ses-${SESSION}/dwi
[ $READOUT_SPACE == "dsc" ] && DER_DIR=$LA_DIR/derivatives/ses-${SESSION}/perf
[ $READOUT_SPACE == "asl" ] && DER_DIR=$LA_DIR/derivatives/ses-${SESSION}/perf

# Check whether output directory already exists: yes > remove and create new output directory

[ ! -d $DER_DIR ] && mkdir -p $DER_DIR
[ -d $DER_DIR ] && rm -rvf $DER_DIR && mkdir -p $DER_DIR


###################################################################################################################
#                                           Run lesion analysis part II                                           #
###################################################################################################################

###########################################
# Read out lesion shells on subject level #
###########################################

if [ $ANALYSIS_LEVEL == "subject" ]; then

    if [ $ORIG_SPACE == "T1w" ] && [ $READOUT_SPACE == "dwi" ]; then

        ###################
        # Create CSV file #
        ################### 

        CSV=$LA_DIR/$1/ses-${SESSION}/dwi/${1}_ses-${SESSION}_mod-${READOUT_SPACE}_space-T1w_lesionanalysis.csv

        if [ $MODIFIER == "yes" ]; then

            echo -en "sub_id,ses_id,\
    lesionanalysis_lesion_mean_FW,lesionanalysis_fliplesion_mean_FW,\
    lesionanalysis_lesion_mean_FAt,lesionanalysis_fliplesion_mean_FAt,\
    lesionanalysis_lesion_mean_MD,lesionanalysis_fliplesion_mean_MD,\
    lesionanalysis_shell1_mean_FW,lesionanalysis_flipshell1_mean_FW,\
    lesionanalysis_shell1_mean_FAt,lesionanalysis_flipshell1_mean_FAt,\
    lesionanalysis_shell1_mean_MD,lesionanalysis_flipshell1_mean_MD,\
    lesionanalysis_shell2_mean_FW,lesionanalysis_flipshell2_mean_FW,\
    lesionanalysis_shell2_mean_FAt,lesionanalysis_flipshell2_mean_FAt,\
    lesionanalysis_shell2_mean_MD,lesionanalysis_flipshell2_mean_MD,\
    lesionanalysis_shell3_mean_FW,lesionanalysis_flipshell3_mean_FW,\
    lesionanalysis_shell3_mean_FAt,lesionanalysis_flipshell3_mean_FAt,\
    lesionanalysis_shell3_mean_MD,lesionanalysis_flipshell3_mean_MD,\
    lesionanalysis_shell4_mean_FW,lesionanalysis_flipshell4_mean_FW,\
    lesionanalysis_shell4_mean_FAt,lesionanalysis_flipshell4_mean_FAt,\
    lesionanalysis_shell4_mean_MD,lesionanalysis_flipshell4_mean_MD,\
    lesionanalysis_shell5_mean_FW,lesionanalysis_flipshell5_mean_FW,\
    lesionanalysis_shell5_mean_FAt,lesionanalysis_flipshell5_mean_FAt,\
    lesionanalysis_shell5_mean_MD,lesionanalysis_flipshell5_mean_MD,\
    lesionanalysis_shell6_mean_FW,lesionanalysis_flipshell6_mean_FW,\
    lesionanalysis_shell6_mean_FAt,lesionanalysis_flipshell6_mean_FAt,\
    lesionanalysis_shell6_mean_MD,lesionanalysis_flipshell6_mean_MD,\
    lesionanalysis_shell7_mean_FW,lesionanalysis_flipshell7_mean_FW,\
    lesionanalysis_shell7_mean_FAt,lesionanalysis_flipshell7_mean_FAt,\
    lesionanalysis_shell7_mean_MD,lesionanalysis_flipshell7_mean_MD,\
    lesionanalysis_shell8_mean_FW,lesionanalysis_flipshell8_mean_FW,\
    lesionanalysis_shell8_mean_FAt,lesionanalysis_flipshell8_mean_FAt,\
    lesionanalysis_shell8_mean_MD,lesionanalysis_flipshell8_mean_MD" > $CSV

        elif [ $MODIFIER == "no" ]; then

            echo -en "sub_id,ses_id,\
    lesionanalysis_lesion_mean_FW,lesionanalysis_lesion_mean_FAt,lesionanalysis_lesion_mean_MD,\
    lesionanalysis_shell1_mean_FW,lesionanalysis_shell1_mean_FAt,lesionanalysis_shell1_mean_MD,\
    lesionanalysis_shell2_mean_FW,lesionanalysis_shell2_mean_FAt,lesionanalysis_shell2_mean_MD,\
    lesionanalysis_shell3_mean_FW,lesionanalysis_shell3_mean_FAt,lesionanalysis_shell3_mean_MD,\
    lesionanalysis_shell4_mean_FW,lesionanalysis_shell4_mean_FAt,lesionanalysis_shell4_mean_MD,\
    lesionanalysis_shell5_mean_FW,lesionanalysis_shell5_mean_FAt,lesionanalysis_shell5_mean_MD,\
    lesionanalysis_shell6_mean_FW,lesionanalysis_shell6_mean_FAt,lesionanalysis_shell6_mean_MD,\
    lesionanalysis_shell7_mean_FW,lesionanalysis_shell7_mean_FAt,lesionanalysis_shell7_mean_MD,\
    lesionanalysis_shell8_mean_FW,lesionanalysis_shell8_mean_FAt,lesionanalysis_shell8_mean_MD" > $CSV

        fi

        #######################################
        # Extract means of lesions and shells #
        #######################################
        
        # Define image modalities from which to extract means 
        #####################################################

        FW_IMAGE=$DATA_DIR/freewater/$1/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-T1w_FW.nii.gz
        FAt_IMAGE=$DATA_DIR/freewater/$1/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-T1w_desc-FWcorrected_FA.nii.gz
        MD_IMAGE=$DATA_DIR/freewater/$1/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-T1w_desc-DTINoNeg_MD.nii.gz

        ######################
        # Ipsilateral lesion #
        ######################

        # Define input
        ##############

        LESION=$LA_DIR/${1}/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-T1w_desc-lesion_res-2mm_mask.nii.gz

        # Define output
        ###############

        FW_LESION=$TMP_OUT/${1}_ses-${SESSION}_space-T1w_desc-lesion_FW.nii.gz
        FAt_LESION=$TMP_OUT/${1}_ses-${SESSION}_space-T1w_desc-FWcorrected_desc-lesion_FAt.nii.gz
        MD_LESION=$TMP_OUT/${1}_ses-${SESSION}_space-T1w_desc-DTINoNeg_desc-lesion_MD.nii.gz

        # Define commands
        #################

        CMD_LESION_FW="fslmaths $FW_IMAGE -mul $LESION $FW_LESION"
        CMD_LESION_MEAN_FW="fslstats $FW_LESION -M"
        CMD_LESION_FAt="fslmaths $FAt_IMAGE -mul $LESION $FAt_LESION"
        CMD_LESION_MEAN_FAt="fslstats $FAt_LESION -M"
        CMD_LESION_MD="fslmaths $MD_IMAGE -mul $LESION $MD_LESION"
        CMD_LESION_MEAN_MD="fslstats $MD_LESION -M"

        # Execute commands
        ##################

        $singularity_fsl /bin/bash -c "$CMD_LESION_FW;$CMD_LESION_FAt;$CMD_LESION_MD"
        mean_lesion_fw=`$singularity_fsl $CMD_LESION_MEAN_FW | tail -n 1`
        mean_lesion_fat=`$singularity_fsl $CMD_LESION_MEAN_FAt | tail -n 1`
        mean_lesion_md=`$singularity_fsl $CMD_LESION_MEAN_MD | tail -n 1`

        ########################
        # Contralateral lesion #
        ########################

        if [ $MODIFIER = "yes" ]; then

            # Define input
            ##############

            LESION_FLIP=$LA_DIR/${1}/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-T1w_desc-lesion_desc-flipped_res-2mm_mask.nii.gz

            # Define output
            ###############

            FW_LESION_FLIP=$TMP_OUT/${1}_ses-${SESSION}_space-T1w_desc-lesion_desc-flipped_FW.nii.gz
            FAt_LESION_FLIP=$TMP_OUT/${1}_ses-${SESSION}_space-T1w_desc-FWcorrected_desc-lesion_desc-flipped_FAt.nii.gz
            MD_LESION_FLIP=$TMP_OUT/${1}_ses-${SESSION}_space-T1w_desc-DTINoNeg_desc-lesion_desc-flipped_MD.nii.gz

            # Define commands
            #################

            CMD_LESION_FLIP_FW="fslmaths $FW_IMAGE -mul $LESION_FLIP $FW_LESION_FLIP"
            CMD_LESION_FLIP_MEAN_FW="fslstats $FW_LESION_FLIP -M"
            CMD_LESION_FLIP_FAt="fslmaths $FAt_IMAGE -mul $LESION_FLIP $FAt_LESION_FLIP"
            CMD_LESION_FLIP_MEAN_FAt="fslstats $FAt_LESION_FLIP -M"
            CMD_LESION_FLIP_MD="fslmaths $MD_IMAGE -mul $LESION_FLIP $MD_LESION_FLIP"
            CMD_LESION_FLIP_MEAN_MD="fslstats $MD_LESION_FLIP -M"

            # Execute commands
            ##################

            $singularity_fsl /bin/bash -c "$CMD_LESION_FLIP_FW; $CMD_LESION_FLIP_FAt; $CMD_LESION_FLIP_MD"
            mean_lesion_flip_fw=`$singularity_fsl $CMD_LESION_FLIP_MEAN_FW | tail -n 1`
            mean_lesion_flip_fat=`$singularity_fsl $CMD_LESION_FLIP_MEAN_FAt | tail -n 1`
            mean_lesion_flip_md=`$singularity_fsl $CMD_LESION_FLIP_MEAN_MD | tail -n 1`

        fi
        
        ##############################
        # Append lesion means to CSV #
        ##############################

        if [ $MODIFIER == "yes" ]; then

            echo -en "\n$1,$SESSION,$mean_lesion_fw,$mean_lesion_flip_fw,$mean_lesion_fat,$mean_lesion_flip_fat,$mean_lesion_md,$mean_lesion_flip_md," >> $CSV
        
        elif [ $MODIFIER == "no" ]; then

            echo -en "\n$1,$SESSION,$mean_lesion_fw,$mean_lesion_fat,$mean_lesion_md," >> $CSV

        fi

        ######################
        # Ipsilateral shells #
        ######################

        for i in {1..8}; do

            # Define input
            ##############

            LESION_SHELL=$LA_DIR/${1}/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-T1w_desc-lesion_res-2mm_desc-dil${i}_shell.nii.gz
            
            # Define output
            ###############

            FW_SHELL=$TMP_OUT/${1}_ses-${SESSION}_space-T1w_desc-shell${i}_FW.nii.gz
            FAt_SHELL=$TMP_OUT/${1}_ses-${SESSION}_space-T1w_desc-FWcorrected_desc-shell${i}_FA.nii.gz
            MD_SHELL=$TMP_OUT/${1}_ses-${SESSION}_space-T1w_desc-DTINoNeg_desc-shell${i}_MD.nii.gz

            # Define commands
            #################

            CMD_SHELL_FW="fslmaths $FW_IMAGE -mul $LESION_SHELL $FW_SHELL"
            CMD_SHELL_MEAN_FW="fslstats $FW_SHELL -M"
            CMD_SHELL_FAt="fslmaths $FAt_IMAGE -mul $LESION_SHELL $FAt_SHELL"
            CMD_SHELL_MEAN_FAt="fslstats $FAt_SHELL -M"
            CMD_SHELL_MD="fslmaths $MD_IMAGE -mul $LESION_SHELL $MD_SHELL"
            CMD_SHELL_MEAN_MD="fslstats $MD_SHELL -M"

            # Execute commands
            ##################

            $singularity_fsl /bin/bash -c "$CMD_SHELL_FW;$CMD_SHELL_FAt;$CMD_SHELL_MD"
            mean_shell_fw=`$singularity_fsl $CMD_SHELL_MEAN_FW | tail -n 1`
            mean_shell_fat=`$singularity_fsl $CMD_SHELL_MEAN_FAt | tail -n 1`
            mean_shell_md=`$singularity_fsl $CMD_SHELL_MEAN_MD | tail -n 1`
    
        ########################
        # Contralateral shells #
        ########################
        
            if [ $MODIFIER = yes ]; then
        
                # Define input
                ##############

                LESION_FLIP_SHELL=$LA_DIR/${1}/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-T1w_desc-lesion_desc-flipped_res-2mm_desc-dil${i}_shell.nii.gz
                
                # Define output
                ###############

                FW_SHELL_FLIP=$TMP_OUT/${1}_ses-${SESSION}_space-T1w_desc-shell${i}_desc-flipped_FW.nii.gz
                FAt_SHELL_FLIP=$TMP_OUT/${1}_ses-${SESSION}_space-T1w_desc-FWcorrected_desc-shell${i}_desc-flipped_FA.nii.gz
                MD_SHELL_FLIP=$TMP_OUT/${1}_ses-${SESSION}_space-T1w_desc-DTINoNeg_desc-shell${i}_desc-flipped_MD.nii.gz

                # Define commands
                #################

                CMD_SHELL_FLIP_FW="fslmaths $FW_IMAGE -mul $LESION_FLIP_SHELL $FW_SHELL_FLIP"
                CMD_SHELL_FLIP_MEAN_FW="fslstats $FW_SHELL_FLIP -M"
                CMD_SHELL_FLIP_FAt="fslmaths $FAt_IMAGE -mul $LESION_FLIP_SHELL $FAt_SHELL_FLIP"
                CMD_SHELL_FLIP_MEAN_FAt="fslstats $FAt_SHELL_FLIP -M"
                CMD_SHELL_FLIP_MD="fslmaths $MD_IMAGE -mul $LESION_FLIP_SHELL $MD_SHELL_FLIP"
                CMD_SHELL_FLIP_MEAN_MD="fslstats $MD_SHELL_FLIP -M"

                # Execute commands
                ##################

                $singularity_fsl /bin/bash -c "$CMD_SHELL_FLIP_FW;$CMD_SHELL_FLIP_FAt;$CMD_SHELL_FLIP_MD"
                mean_shell_flip_fw=`$singularity_fsl $CMD_SHELL_FLIP_MEAN_FW | tail -n 1`
                mean_shell_flip_fat=`$singularity_fsl $CMD_SHELL_FLIP_MEAN_FAt | tail -n 1`
                mean_shell_flip_md=`$singularity_fsl $CMD_SHELL_FLIP_MEAN_MD | tail -n 1`
            
            fi
        
        #############################
        # Append shell means to CSV #
        #############################

            if [ $MODIFIER == "yes" ]; then

                echo -n "$mean_shell_fw,$mean_shell_flip_fw,$mean_shell_fat,$mean_shell_flip_fat,$mean_shell_md,$mean_shell_flip_md," >> $CSV
            
            elif [ $MODIFIER == "no" ]; then

                echo -n "$mean_shell_fw,$mean_shell_fat,$mean_shell_md," >> $CSV

            fi
        
        done
    
    fi

###############################
# Combine CSVs on group level #
###############################

elif [ $ANALYSIS_LEVEL == "group" ]; then

    # Get subject to extract columm names from csv
    ##############################################

    pushd $LA_DIR 
    sub_array=($(ls sub* -d))
    popd

    for sub in $(echo ${sub_array[@]}); do

        CSV=$LA_DIR/$sub/ses-${SESSION}/$READOUT_SPACE/${sub}_ses-${SESSION}_mod-${READOUT_SPACE}_space-${ORIG_SPACE}_lesionanalysis.csv
        RAND_SUB=$sub
        
        [ -f $CSV ] && break

    done

    CSV_RAND=$LA_DIR/$RAND_SUB/ses-${SESSION}/$READOUT_SPACE/${RAND_SUB}_ses-${SESSION}_mod-${READOUT_SPACE}_space-${ORIG_SPACE}_lesionanalysis.csv

    # Define output
    ###############

    CSV_COMBINED=$DER_DIR/ses-${SESSION}_mod-${READOUT_SPACE}_space-${ORIG_SPACE}_lesionanalysis.csv

    # Create CSV
    ############

    head -n 1 $CSV_RAND > $CSV_COMBINED

    for sub in $(echo ${sub_array[@]}); do
        
        CSV=$LA_DIR/$sub/ses-${SESSION}/$READOUT_SPACE/${sub}_ses-${SESSION}_mod-${READOUT_SPACE}_space-${ORIG_SPACE}_lesionanalysis.csv
        
        [ -f $CSV ] && csv=`tail -n 1 $CSV` && echo -e "\n$csv" >> $CSV_COMBINED

    done

fi

