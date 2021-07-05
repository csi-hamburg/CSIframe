#!/bin/bash

#| # heudiconv first pass

#| Import cluster modules
source /sw/batch/init.sh
module switch singularity singularity/3.5.2-overlayfix

#| export project env variables
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source $SCRIPT_DIR/.projectrc

#| rename DCM subjects if no sub prefix
#for dir in $(ls $DCM_DIR); do
#	if [[ "$dir" != "sub-"* ]]; then
#	mv $DCM_DIR/$dir $DCM_DIR/sub-${dir}
#	fi
#done 
#ls ${DCM_DIR} | sort -R | tail -3

#| Define singularity command and srun flags
CMD="singularity run --cleanenv --userns -B $BIDS_DIR:/bids -B $DCM_DIR:/dcm $ENV_DIR/heudiconv-0.9.0 -d /dcm/{subject}/ses-1/*/* -s $(ls ${DCM_DIR} | sort -R | tail -3) -f convertall -c none -o /bids"

#| execute command
$CMD
