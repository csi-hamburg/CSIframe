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

container_fsl=fsl-6.0.3
singularity_fsl="singularity run --cleanenv --no-home --userns \
    -B .
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR \
    -B $TMP_IN \
    -B $TMP_OUT \
    $ENV_DIR/$container_fsl"

# Input subjects
################

pushd $LA_DIR 
sub_array=($(ls sub* -d))
popd

# Create output directory
#########################

LA_DIR=$DATA_DIR/lesionanalysis

[ $ORIG_SPACE == "T1w" ] && OUT_DIR=$LA_DIR/derivatives/ses-${SESSION}/anat
[ $ORIG_SPACE == "FLAIR" ] && OUT_DIR=$LA_DIR/derivatives/ses-${SESSION}/anat
[ $ORIG_SPACE == "dwi" ] && OUT_DIR=$LA_DIR/derivatives/ses-${SESSION}/dwi
[ $ORIG_SPACE == "dsc" ] && OUT_DIR=$LA_DIR/derivatives/ses-${SESSION}/perf
[ $ORIG_SPACE == "asl" ] && OUT_DIR=$LA_DIR/derivatives/ses-${SESSION}/perf

# Check whether output directory already exists: yes > remove and create new output directory

[ ! -d $OUT_DIR ] && mkdir -p $OUT_DIR
[ -d $OUT_DIR ] && rm -rvf $OUT_DIR && mkdir -p $OUT_DIR


###################################################################################################################
#                                           Run lesion analysis part II                                           #
###################################################################################################################


if [ $ORIG_SPACE == "T1w" ] && [ $READOUT_SPACE == "dwi" ]; then

    ###################
    # Create CSV file #
    ################### 

    CSV=$OUT_DIR/${READOUT_SPACE}_ses-${SESSION}_space-T1w_lesionanalysis.csv

    if [ $FLIP == "yes" ]; then

        echo -en "sub_id,\
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

    elif [ $FLIP == "no" ]; then

        echo -en "sub_id,\
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

    for sub in ${sub_array[@]}; do

        #######################################################
        # Define image modalities from which to extract means #
        #######################################################

        FW_IMAGE=$DATA_DIR/freewater/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_space-T1w_FW.nii.gz
        FAt_IMAGE=$DATA_DIR/freewater/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_space-T1w_desc-FWcorrected_FA.nii.gz
        MD_IMAGE=$DATA_DIR/freewater/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_space-T1w_desc-DTINoNeg_MD.nii.gz

        ######################
        # Ipsilateral lesion #
        ######################

        # Define input
        ##############

        LESION=$LA_DIR/${sub}/ses-$SESSION/anat/${1}_ses-${SESSION}_space-T1w_desc-lesion_res-2mm_mask.nii.gz

        # Define output
        ###############

        FW_LESION=$TMP_OUT/${sub}_ses-${SESSION}_space-T1w_desc-lesion_FW.nii.gz
        FAt_LESION=$TMP_OUT/${sub}_ses-${SESSION}_space-T1w_desc-FWcorrected_desc-lesion_FAt.nii.gz
        MD_LESION=$TMP_OUT/${sub}_ses-${SESSION}_space-T1w_desc-DTINoNeg_desc-lesion_MD.nii.gz

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

        $singularity_fsl /bin/bash -c "$CMD_LESION_FW; $CMD_LESION_FAt; $CMD_LESION_MD"
        mean_lesion_fw=`$CMD_LESION_MEAN_FW | tail -n 1`
        mean_lesion_fat=`$CMD_LESION_MEAN_FAt | tail -n 1`
        mean_lesion_md=`$CMD_LESION_MEAN_MD | tail -n 1`

        ########################
        # Contralateral lesion #
        ########################

        [ if $FLIP = "yes" ]; then

            # Define input
            ##############

            LESION_FLIP=$LA_DIR/${sub}/ses-$SESSION/anat/${1}_ses-${SESSION}_space-T1w_desc-lesion_res-2mm_desc-flipped_mask.nii.gz

            # Define output
            ###############

            FW_LESION_FLIP=$TMP_OUT/${sub}_ses-${SESSION}_space-T1w_desc-lesion_desc-flipped_FW.nii.gz
            FAt_LESION_FLIP=$TMP_OUT/${sub}_ses-${SESSION}_space-T1w_desc-FWcorrected_desc-lesion_desc-flipped_FAt.nii.gz
            MD_LESION_FLIP=$TMP_OUT/${sub}_ses-${SESSION}_space-T1w_desc-DTINoNeg_desc-lesion_desc-flipped_MD.nii.gz

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
            mean_lesion_flip_fw=`$CMD_LESION_FLIP_MEAN_FW | tail -n 1`
            mean_lesion_flip_fat=`$CMD_LESION_FLIP_MEAN_FAt | tail -n 1`
            mean_lesion_flip_md=`$CMD_LESION_FLIP_MEAN_MD | tail -n 1`

        fi
        
        ##############################
        # Append lesion means to CSV #
        ##############################

        if [ $FLIP == "yes" ]; then

            echo -en "\n$sub,$mean_lesion_fw,$mean_lesion_flip_fw,$mean_lesion_fat,$mean_lesion_flip_fat,$mean_lesion_md,$mean_lesion_flip_md" >> $CSV
        
        elif [ $FLIP == "no" ]; then

            echo -en "\n$sub,$mean_lesion_fw,$mean_lesion_fat,$mean_lesion_md," >> $CSV

        fi

        ######################
        # Ipsilateral shells #
        ######################

        for i in {1..8}; do

            # Define input
            ##############

            LESION_SHELL=$LA_DIR/${sub}/ses-$SESSION/anat/${sub}_ses-${SESSION}_space-T1w_desc-lesion_res-2mm_desc-dil${i}_shell.nii.gz
            
            # Define output
            ###############

            FW_SHELL=$TMP_OUT/${sub}_ses-${SESSION}_space-T1w_desc-shell${i}_FW.nii.gz
            FAt_SHELL=$TMP_OUT/${sub}_ses-${SESSION}_space-T1w_desc-FWcorrected_desc-shell${i}_FA.nii.gz
            MD_SHELL=$TMP_OUT/${sub}_ses-${SESSION}_space-T1w_desc-DTINoNeg_desc-shell${i}_MD.nii.gz

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

            $singularity_fsl /bin/bash -c "$CMD_LESION_FW; $CMD_LESION_FAt; $CMD_LESION_MD"
            mean_shell_fw=`$CMD_SHELL_MEAN_FW | tail -n 1`
            mean_shell_fat=`$CMD_SHELL_MEAN_FAt | tail -n 1`
            mean_shell_md=`$CMD_LESION_MEAN_MD | tail -n 1`
       
        ########################
        # Contralateral shells #
        ########################
        
            if [ $FLIP = yes]; then
           
                # Define input
                ##############

                LESION_FLIP_SHELL=$LA_DIR/${sub}/ses-$SESSION/anat/${sub}_ses-${SESSION}_space-T1w_desc-lesion_desc-flipped_res-2mm_desc-dil${i}_shell.nii.gz
                
                # Define output
                ###############

                FW_SHELL_FLIP=$TMP_OUT/${sub}_ses-${SESSION}_space-T1w_desc-shell${i}_desc-flipped_FW.nii.gz
                FAt_SHELL_FLIP=$TMP_OUT/${sub}_ses-${SESSION}_space-T1w_desc-FWcorrected_desc-shell${i}_desc-flipped_FA.nii.gz
                MD_SHELL_FLIP=$TMP_OUT/${sub}_ses-${SESSION}_space-T1w_desc-DTINoNeg_desc-shell${i}_desc-flipped_MD.nii.gz

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

                $singularity_fsl /bin/bash -c "$CMD_SHELL_FLIP_FW; $CMD_SHELL_FLIP_FAt; $CMD_SHELL_FLIP_MD"
                mean_shell_flip_fw=`$CMD_SHELL_FLIP_MEAN_FW | tail -n 1`
                mean_shell_flip_fat=`$CMD_SHELL_FLIP_MEAN_FAt | tail -n 1`
                mean_shell_flip_md=`$CMD_SHELL_FLIP_MEAN_MD | tail -n 1`
            
            fi
        
        #############################
        # Append shell means to CSV #
        #############################

            if [ $FLIP == "yes" ]; then

                echo -n "$mean_shell_fw,$mean_shell_flip_fw,$mean_shell_fat,$mean_shell_flip_fat,$mean_shell_md,$mean_shell_flip_md" >> $CSV
            
            elif [ $FLIP == "no" ]; then

                echo -n "$mean_lesion_fw,$mean_lesion_fat,$mean_lesion_md" >> $CSV

            fi
        
        done
    
    done

fi

