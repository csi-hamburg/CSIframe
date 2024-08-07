#!/usr/bin/env bash

###################################################################################################################
# Registration pipeline that allows for flexible registration between volumes                                     #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - nothing mandatory, but the input files should be computed                                               #
#   [container]                                                                                                   #
#       - mrtrix-3.0.2.sif                                                                                      #
###################################################################################################################

# Get verbose outputs
set -x

# Define subject specific temporary directory on $SCRATCH_DIR
export TMP_DIR=$SCRATCH_DIR/$1/tmp;   [ ! -d $TMP_DIR ] && mkdir -p $TMP_DIR
TMP_IN=$TMP_DIR/input;                 [ ! -d $TMP_IN ] && mkdir -p $TMP_IN/moving $TMP_IN/target $TMP_IN/transform $TMP_IN/mask $TMP_IN/mask_inv
TMP_OUT=$TMP_DIR/output;               [ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT

###################################################################################################################

# Pipeline-specific environment
##################################

# Singularity container version and command
container_mrtrix=mrtrix3-3.0.2
singularity_mrtrix3="singularity run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_mrtrix"

MOVING_DIR=$DATA_DIR/registration/$REGISTRATION_TASK/moving
TARGET_DIR=$DATA_DIR/registration/$REGISTRATION_TASK/target
TRANSFORM_DIR=$DATA_DIR/registration/$REGISTRATION_TASK/transform
MASK_DIR=$DATA_DIR/registration/$REGISTRATION_TASK/mask

# To make I/O more efficient read/write outputs from/to $SCRATCH
[ -d $MOVING_DIR ] && cp -rfL $MOVING_DIR/${1}* $TMP_IN/moving || echo "No moving images found"

if [ $(ls $MOVING_DIR | wc -l) == 1 ]; then
    echo "Assuming template image as target"
    cp -rfL $MOVING_DIR/* $TMP_IN/moving
elif [ $(ls $MOVING_DIR | wc -l) > 1  ]; then
    cp -rfL $MOVING_DIR/${1}* $TMP_IN/moving
else
    echo "No moving images found"
fi


if [ $(ls $TARGET_DIR | wc -l) == 1 ]; then
    echo "Assuming template image as target"
    cp -rfL $TARGET_DIR/* $TMP_IN/target
elif [ $(ls $TARGET_DIR | wc -l) > 1  ]; then
    cp -rfL $TARGET_DIR/${1}* $TMP_IN/target
else
    echo "No target images found"
fi





# Pipeline execution
##################################

# Define command

MOVING=$(find $TMP_IN/moving -name *${1}* -type f)
TARGET=$(find $TMP_IN/target -name *${1}* -type f)


if [ $TEMPLATE_WARP == moving ]; then
    pushd $TMP_IN/moving
    MOVING=$(find $TMP_IN/moving -name * -type f)
    popd
elif [ $TEMPLATE_WARP == target ]; then
    pushd $TMP_IN/target
    TARGET=$(find $TMP_IN/target -name * -type f)
    popd
fi

MOVING_IN_CONTAINER=$(sed "s|$TMP_IN|/tmp_in|g" <<< $MOVING)
TARGET_IN_CONTAINER=$(sed "s|$TMP_IN|/tmp_in|g" <<< $TARGET)

if [ $REGISTRATION_METHOD == ants_apply_transform ]; then
    [ -d $TRANSFORM_DIR ] && cp -rfL $TRANSFORM_DIR/${1}* $TMP_IN/transform || echo "No transform images found"
    TRANSFORM=$(find $TMP_IN/transform -name *${1}* -type f)
    TRANSFORM_IN_CONTAINER=$(sed "s|$TMP_IN|/tmp_in|g" <<< $TRANSFORM)
fi

if [ $MASKING == y ]; then
    [ -d $MASK_DIR ] && cp -rfL $MASK_DIR/${1}* $TMP_IN/mask || echo "No mask images found"
    MASK=$(find $TMP_IN/mask -name *${1}* -type f)
    MASK_IN_CONTAINER=$(sed "s|$TMP_IN|/tmp_in|g" <<< $MASK)
    MASK_FLAG="-x NULL,$MASK_IN_CONTAINER"

    if [ $LESION_MASKING == y ]; then
        [ ! -d $TMP_IN/mask_inv ] && mkdir -p $TMP_IN/mask_inv
        $singularity_mrtrix3 mrcalc $MASK_IN_CONTAINER -neg 1 -add /tmp_in/mask_inv/${1}.nii.gz -force
        MASK_INV=$(find $TMP_IN/mask_inv -name *${1}* -type f)
        MASK_INV_IN_CONTAINER=$(sed "s|$TMP_IN|/tmp_in|g" <<< $MASK_INV)
        MASK_FLAG="-x NULL,$MASK_INV_IN_CONTAINER"
    fi
fi



# Define command

if [ $REGISTRATION_METHOD == ants_rigid ]; then
    CMD="
        $singularity_mrtrix3 antsRegistrationSyN.sh \
        -d 3 \
        -f $TARGET_IN_CONTAINER \
        -m $MOVING_IN_CONTAINER \
        -o /tmp_out/${1} \
        -t r \
        -n $OMP_NTHREADS \
        $MASK_FLAG

    "
elif [ $REGISTRATION_METHOD == ants_affine ]; then
    CMD="
        $singularity_mrtrix3 antsRegistrationSyN.sh \
        -d 3 \
        -f $TARGET_IN_CONTAINER \
        -m $MOVING_IN_CONTAINER \
        -o /tmp_out/${1} \
        -t a \
        -n $OMP_NTHREADS \
        $MASK_FLAG
    "
elif [ $REGISTRATION_METHOD == ants_syn ]; then
    CMD="
        $singularity_mrtrix3 antsRegistrationSyN.sh \
        -d 3 \
        -f $TARGET_IN_CONTAINER \
        -m $MOVING_IN_CONTAINER \
        -o /tmp_out/${1} \
        -t s \
        -n $OMP_NTHREADS \
        $MASK_FLAG
    "
elif [[ $REGISTRATION_METHOD == ants_apply_transform ]]; then

    CMD="
        $singularity_mrtrix3 antsApplyTransforms \
        -d 3 -i $MOVING_IN_CONTAINER \
        -r $TARGET_IN_CONTAINER \
        -o /tmp_out/${1}.nii.gz \
        -n $INTERPOLATION \
        -t $TRANSFORM_IN_CONTAINER \
        -v
    "

else

    echo "ERROR: registration method '${REGISTRATION_METHOD}' not available"
    exit 1

fi

# Execute command
eval $CMD

# Copy outputs to $DATA_DIR
[ $LESION_MASKING == y ] && REGISTRATION_METHOD=${REGISTRATION_METHOD}_lesion_masked
OUTPUT_DIR=$DATA_DIR/registration/$REGISTRATION_TASK/output/$REGISTRATION_METHOD/$1
[ ! -d  $OUTPUT_DIR ] && mkdir -p $OUTPUT_DIR
cp -ruvf $TMP_OUT/* $OUTPUT_DIR
