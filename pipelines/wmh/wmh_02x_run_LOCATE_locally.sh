PIPELINE=wmh

export SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"  # Script localization
export CODE_DIR=$SCRIPT_DIR/../..                                                         # Code directory
export PROJ_DIR=$(realpath $SCRIPT_DIR/../../..)                                          # Project root; should be 1 level above $SCRIPT_DIR
export ENV_DIR=$PROJ_DIR/envs                                                       # Software environments directory
export PIPELINE_DIR=$CODE_DIR/pipelines/$PIPELINE                                   # Pipeline-specific subdirectory in $CODE_DIR 
export DATA_DIR=$PROJ_DIR/data                                                      # Data directory inputs come from and outputs go to; should 

SESSION=1
ALGORITHM=LOCATE

LOCATE_installation=$ENV_DIR/LOCATE-BIANCA
export LOCATE_installation

LOCATE_working_dir=$DATA_DIR/$PIPELINE/MyLOCATE
[ ! -d $LOCATE_working_dir ] && mkdir -p $LOCATE_working_dir
LOCATE_training_dir=$LOCATE_working_dir/LOO_training_imgs
[ ! -d $LOCATE_training_dir ] && mkdir -p $LOCATE_training_dir
export LOCATE_training_dir

MAN_SEGMENTATION_DIR=$PROJ_DIR/../CSI_WMH_MASKS_HCHS_pseud/HCHS/

for sub in $(ls $DATA_DIR/$PIPELINE/sub-* -d | xargs -n 1 basename); do

    [[ $(ls -A $MAN_SEGMENTATION_DIR/$sub) ]] && SUB_GROUP=training || SUB_GROUP=testing

    if [ $SUB_GROUP == "training" ]; then

        OUT_DIR=$DATA_DIR/$PIPELINE/$sub/ses-${SESSION}/anat/
        ALGORITHM_OUT_DIR=$OUT_DIR/${ALGORITHM}/

        # Define inputs
        MAN_SEGMENTATION_DIR=$PROJ_DIR/../CSI_WMH_MASKS_HCHS_pseud/HCHS/
        FLAIR_BRAIN=$OUT_DIR/${sub}_ses-${SESSION}_desc-brain_FLAIR.nii.gz
        FLAIR_LOCATE=$LOCATE_training_dir/${sub}_feature_FLAIR.nii.gz 
        T1_IN_FLAIR=$OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii.gz
        T1_LOCATE=$LOCATE_training_dir/${sub}_feature_T1.nii.gz
        SEGMENTATION_MAN=$MAN_SEGMENTATION_DIR/$sub/anat/${sub}_DC_FLAIR_label3.nii.gz
        MANUAL_MASK_LOCATE=$LOCATE_training_dir/${sub}_manualmask.nii.gz
        DISTANCEMAP=$OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_distancemap.nii.gz
        DISTANCEMAP_LOCATE=$LOCATE_training_dir/${sub}_ventdistmap.nii.gz
        SEGMENTATION_raw=$OUT_DIR/bianca/${sub}_ses-${SESSION}_space-FLAIR_desc-wmh_desc-bianca_mask_raw.nii.gz
        SEGMENTATION_raw_LOCATE=$LOCATE_training_dir/${sub}_BIANCA_LPM.nii.gz
        T1_MASK_IN_FLAIR=$OUT_DIR/${sub}_ses-${SESSION}_space-FLAIR_desc-brain_mask.nii.gz
        BRAINMASK_LOCATE=$LOCATE_training_dir/${sub}_brainmask.nii.gz
        BIANCAMASK_LOCATE=$LOCATE_training_dir/${sub}_biancamask.nii.gz

        if [ -f $FLAIR_BRAIN ] && [ -f $T1_IN_FLAIR ] && [ -f $SEGMENTATION_MAN ] && [ -f $DISTANCEMAP ] && [ -f $SEGMENTATION_raw ] && [ -f $T1_MASK_IN_FLAIR ]; then
        
            cp $FLAIR_BRAIN $FLAIR_LOCATE
            cp $T1_IN_FLAIR $T1_LOCATE
            cp $SEGMENTATION_MAN $MANUAL_MASK_LOCATE
            cp $DISTANCEMAP $DISTANCEMAP_LOCATE
            cp $SEGMENTATION_raw $SEGMENTATION_raw_LOCATE
            cp $T1_MASK_IN_FLAIR $BRAINMASK_LOCATE
            cp $T1_MASK_IN_FLAIR $BIANCAMASK_LOCATE

        # else we will not copy any of the files into the LOCATE directory because LOCATE cannot handle incomplete data of subjects, throws an error and stops
        fi
    
    fi

done

# training
#matlab -nosplash -nodesktop -nojvm -batch "addpath(genpath('$LOCATE_installation')); LOCATE_training('$LOCATE_training_dir'); quit"

# validation
matlab -nosplash -nodesktop -nojvm -batch "addpath(genpath('$LOCATE_installation')); LOCATE_LOO_testing('$LOCATE_training_dir'); quit"