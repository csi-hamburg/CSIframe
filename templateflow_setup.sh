#!/bin/bash

set -x

SCRIPT_DIR=${SLURM_SUBMIT_DIR-"$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"}
PROJ_DIR=$SCRIPT_DIR/../.
CODE_DIR=$SCRIPT_DIR


export TEMPLATEFLOW_HOME=$CODE_DIR/templateflow
mkdir -p $TEMPLATEFLOW_HOME

python -c "from templateflow.api import get; get(['MNI152NLin2009cAsym', 'MNI152NLin6Asym', 'OASIS30ANTs'])"


