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

# Input for overlay creation and ROI analyses

#MOD_ERODED=$TBSS_DIR/$sub/ses-${SESSION}/dwi/${sub}_ses-${SESSION}_space-${SPACE}_desc-eroded_${MOD}.nii.gz
#MOD_SKEL=$TBSS_DIR/$sub/ses-${SESSION}/dwi/${sub}_ses-${SESSION}_space-${SPACE}_desc-skeleton_${MOD}.nii.gz

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

# Output
########

# Merging outputs

#MERGE_LIST_MOD=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_${MOD}_mergelist.txt
FA_SKEL_MERGED=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-DTINoNeg_FA.nii.gz
#MOD_SKEL_MERGED=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_${MOD}.nii.gz

# Overlay

#OVERLAY=$TBSS_DIR/$sub/ses-${SESSION}/dwi/${sub}_ses-${SESSION}_space-${SPACE}_desc-skeleton_${MOD}_overlay.png

# CSV for MNI branch

#MOD_SKEL_ROI=$TBSS_DIR/${sub}_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-JHU_label-${ROI}_${MOD}.nii.gz
#ROI_CSV=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_label-JHU_ROI.csv

# CSV for fixel branch

#MEAN_CSV=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_means.csv

# Stats 

#HISTFIG=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-mean${MOD}_histogram.png
#BOXFIG=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-mean${MOD}_boxplot.png
#ZSCORE=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_label-JHU_${MOD}_zscores.csv

# HTML report

#REPORT=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_${MODALITY}_report.html

# Remove output of previous runs

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

#######################################################################################
# Create overlay of skeleton and respective modality for each subject for QC purposes #
#######################################################################################

# for sub in $(cat $CASELIST); do
    
#     for MOD in $(echo $MODALITIES); do

#         # Input for overlay creation and ROI analyses

#         MOD_ERODED=$TBSS_DIR/$sub/ses-${SESSION}/dwi/${sub}_ses-${SESSION}_space-${SPACE}_desc-eroded_${MOD}.nii.gz
#         MOD_SKEL=$TBSS_DIR/$sub/ses-${SESSION}/dwi/${sub}_ses-${SESSION}_space-${SPACE}_desc-skeleton_${MOD}.nii.gz

#         # Output

#         OVERLAY=$TBSS_DIR/$sub/ses-${SESSION}/dwi/${sub}_ses-${SESSION}_space-${SPACE}_desc-skeleton_${MOD}_overlay.png

#         $singularity_miniconda python $PIPELINE_DIR/overlay.py $MOD_ERODED $MOD_SKEL $OVERLAY

#     done

# done
    
#################
# Read out ROIs #
#################

if [ $TBSS_PIPELINE == "mni" ]; then

    # Reset MODALITIES omitting one modality (FW) for seperate run (necessary for csv file creation)
    ################################################################################################

    MODALITIES="desc-DTINoNeg_FA desc-FWcorrected_FA desc-DTINoNeg_L1 desc-FWcorrected_L1 desc-DTINoNeg_RD \
                desc-FWcorrected_RD desc-DTINoNeg_MD desc-FWcorrected_MD"


    # Create CSV file
    #################

    # CSV for MNI branch

    ROI_CSV=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_label-JHU_ROI.csv
    
    echo -n "sub_id," >> $ROI_CSV

    # ROIs of JHU ICBM-DTI-81 white-matter labels atlas

    for MOD in FA FAt AD ADt RD RDt MD MDt; do
        
        echo -n "MI-CP_$MOD,P-CT_$MOD,GCC_$MOD,BCC_$MOD,SCC_$MOD,FX_$MOD,CST-R_$MOD,CST-L_$MOD,ML-R_$MOD,ML-L_$MOD,ICP-R_$MOD,ICP-L_$MOD,\
        SCP-R_$MOD,SCP-L_$MOD,CP-R_$MOD,CP-L_$MOD,ALIC-R_$MOD,ALIC-L_$MOD,PLIC-R_$MOD,PLIC-L_$MOD,RLIC-R_${MOD},RLIC-L_${MOD},ACR-R_$MOD,\
        ACR-L_$MOD,SCR-R_$MOD,SCR-L_$MOD,PCR-R_$MOD,PCR-L_$MOD,PTR-R_$MOD,PTR-L_$MOD,SS-R_$MOD,SS-L_$MOD,EC-R_$MOD,EC-L_$MOD,CGC-R_$MOD,\
        CGC-L_$MOD,CGH-R_$MOD,CGH-L_$MOD,FX_ST-R_$MOD,FX_ST-L_$MOD,SLF-R_$MOD,SLF-L_$MOD,SFO-R_$MOD,SFO-L_$MOD,UNC-R_$MOD,UNC-L_$MOD,\
        TAP-R_$MOD,TAP-L_$MOD,mean_$MOD" >> $ROI_CSV
    done

        echo "MI-CP_FW,P-CT_FW,GCC_FW,BCC_FW,SCC_FW,FX_FW,CST-R_FW,CST-L_FW,ML-R_FW,ML-L_FW,ICP-R_FW,ICP-L_FW,\
        SCP-R_FW,SCP-L_FW,CP-R_FW,CP-L_FW,ALIC-R_FW,ALIC-L_FW,PLIC-R_FW,PLIC-L_FW,RLIC-R_FW,RLIC-L_FW,\
        ACR-R_FW,ACR-L_FW,SCR-R_FW,SCR-L_FW,PCR-R_FW,PCR-L_FW,PTR-R_FW,PTR-L_FW,SS-R_FW,SS-L_FW,EC-R_FW,EC-L_FW,\
        CGC-R_FW,CGC-L_FW,CGH-R_FW,CGH-L_FW,FX_ST-R_FW,FX_ST-L_FW,SLF-R_FW,SLF-L_FW,SFO-R_FW,SFO-L_FW,UNC-R_FW,\
        UNC-L_FW,TAP-R_FW,TAP-L_FW,mean_FW" >> $ROI_CSV

    # Iterate across subjects and modalities to extract JHU ROIs and mean across entire skeleton
    ############################################################################################

    for sub in $(cat $CASELIST); do

        echo -n "$sub," >>  $ROI_CSV

        for MOD in $(echo $MODALITIES); do

            # Calculate mean for each ROI

            for i in $(seq 1 48); do

                let index=$i+1
                ROI=`sed -n ${index}p $CODE_DIR/pipelines/tbss/JHU-ICBM-LUT.txt | awk '{print $2}'`

                # Input skeleton
                MOD_SKEL=$TBSS_DIR/$sub/ses-${SESSION}/dwi/${sub}_ses-${SESSION}_space-${SPACE}_desc-skeleton_${MOD}.nii.gz

                # Output skeleton (masked by ROI)
                MOD_SKEL_ROI=$TBSS_DIR/$sub/ses-${SESSION}/dwi/${sub}_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-JHU_label-${ROI}_${MOD}.nii.gz

                CMD_ROI="fslmaths \
                            /opt/$container_fsl/data/atlases/JHU/JHU-ICBM-labels-1mm.nii.gz \
                            -thr $i \
                            -uthr $i \
                            -bin \
                            -mul $MOD_SKEL $MOD_SKEL_ROI"
                    
                CMD_ROI_MEAN="fslstats $MOD_SKEL_ROI -M"

                $singularity_fsl $CMD_ROI
                mean_roi=`$singularity_fsl $CMD_ROI_MEAN | tail -n 1`
                echo -n "$mean_roi," >> $ROI_CSV
            
            done

            # Calculate mean across entire skeleton

            CMD_MEAN="fslstats $MOD_SKEL -M"
            mean=`$singularity_fsl $CMD_MEAN | tail -n 1`
            echo -n "$mean," >> $ROI_CSV

        done

        # Repeat computations for FW (last echo call without -n option so next subject gets appended to new line) 
        
        MOD="FW"

        for i in $(seq 1 48); do

            let index=$i+1
            ROI=`sed -n ${index}p $CODE_DIR/pipelines/tbss/JHU-ICBM-LUT.txt | awk '{print $2}'`
            
            # Input skeleton
            MOD_SKEL=$TBSS_DIR/$sub/ses-${SESSION}/dwi/${sub}_ses-${SESSION}_space-${SPACE}_desc-skeleton_${MOD}.nii.gz
            
            # Output skeleton (masked by ROI)
            MOD_SKEL_ROI=$TBSS_DIR/$sub/ses-${SESSION}/dwi/${sub}_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-JHU_label-${ROI}_${MOD}.nii.gz

            CMD_ROI="fslmaths \
                        /opt/$container_fsl/data/atlases/JHU/JHU-ICBM-labels-1mm.nii.gz \
                        -thr $i \
                        -uthr $i \
                        -bin \
                        -mul $MOD_SKEL $MOD_SKEL_ROI"
                    
            CMD_ROI_MEAN="fslstats $MOD_SKEL_ROI -M"

            $singularity_fsl $CMD_ROI
            mean_roi=`$singularity_fsl $CMD_ROI_MEAN | tail -n 1`
            echo -n "$mean_roi," >> $ROI_CSV

        done

        # Calculate mean across entire skeleton

        CMD_MEAN="fslstats $MOD_SKEL -M"
        mean=`$singularity_fsl $CMD_MEAN | tail -n 1`
        echo "$mean" >> $ROI_CSV

    done

elif [ $TBSS_PIPELINE == "fixel" ]; then

    # Reset MODALITIES omitting one modality (desc-voxelmap_complexity) for seperate run (necessary for csv file creation)
    ######################################################################################################################

    MODALITIES="desc-DTINoNeg_FA desc-FWcorrected_FA desc-DTINoNeg_L1 desc-FWcorrected_L1 desc-DTINoNeg_RD \
                desc-FWcorrected_RD desc-DTINoNeg_MD desc-FWcorrected_MD FW desc-voxelmap_fd desc-voxelmap_fdc \
                desc-voxelmap_logfc"

    # Create CSV file
    #################
    
    # Output CSV for fixel branch

    MEAN_CSV=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_means.csv
    
    echo "sub_id,mean_FA,mean_FAt,mean_AD,mean_ADt,mean_RD,mean_RDt,mean_MD,mean_MDt,mean_FW,mean_fd,mean_fdc,mean_logfc,mean_complexity" \
    >> $MEAN_CSV

    # Iterate across subjects and modalities to extract mean across entire skeleton
    ###############################################################################

    for sub in $(cat $CASELIST); do

        echo -n "$sub," >>  $MEAN_CSV

        for MOD in $(echo $MODALITIES); do

            # Input skeleton
            MOD_SKEL=$TBSS_DIR/$sub/ses-${SESSION}/dwi/${sub}_ses-${SESSION}_space-${SPACE}_desc-skeleton_${MOD}.nii.gz
            
            CMD_MEAN="fslstats $MOD_SKEL -M"
            mean=`$singularity_fsl $CMD_MEAN | tail -n 1`
            echo -n "$mean," >> $MEAN_CSV
        
        done

        # Repeat computations for desc-voxelmap_complexity (last echo call without -n option so next subject gets appended to new line)

        MOD="desc-voxelmap_complexity"

        # Input skeleton
        MOD_SKEL=$TBSS_DIR/$sub/ses-${SESSION}/dwi/${sub}_ses-${SESSION}_space-${SPACE}_desc-skeleton_${MOD}.nii.gz

        CMD_MEAN="fslstats $MOD_SKEL -M"
            mean=`$singularity_fsl $CMD_MEAN | tail -n 1`
            echo "$mean" >> $MEAN_CSV
    
    done

fi

###############################################################################################
# Make boxplot and histogram of mean across skeleton for each modality and create html report #
###############################################################################################

if [ $TBSS_PIPELINE == "fixel"]; then

    MODALITIES="desc-DTINoNeg_FA desc-FWcorrected_FA desc-DTINoNeg_L1 desc-FWcorrected_L1 desc-DTINoNeg_RD \
                desc-FWcorrected_RD desc-DTINoNeg_MD desc-FWcorrected_MD FW desc-voxelmap_fd desc-voxelmap_fdc \
                desc-voxelmap_logfc desc-voxelmap_complexity"
    CSV=$MEAN_CSV

    # Create stats figures
    ######################

    for MOD in FA FAt AD ADt RD RDt MD MDt FW fd fdc logfc complexity; do

        # Stats output

        HISTFIG=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-mean${MOD}_histogram.png
        BOXFIG=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-mean${MOD}_boxplot.png
        ZSCORE=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-mean_zscores.csv
        
        # Command 

        $singularity_miniconda python stats.py $MOD $CSV $HISTFIG $BOXFIG $ZSCORE

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
    CSV=$ROI_CSV

    # Create stats figures
    ######################

    for MOD in FA FAt AD ADt RD RDt MD MDt FW; do

        # Stats output

        HISTFIG=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-mean${MOD}_histogram.png
        BOXFIG=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_desc-mean${MOD}_boxplot.png
        ZSCORE=$DER_DIR/sub-${TBSS_MERGE_LIST}_ses-${SESSION}_space-${SPACE}_desc-skeleton_label-JHU_desc-mean_zscores.csv

        # Command

        $singularity_miniconda python stats.py $MOD $CSV $HISTFIG $BOXFIG $ZSCORE

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