#!/usr/bin/env bash

#SBATCH --nodes=1
#SBATCH --export=SCRIPT_DIR,PIPELINE,PIPELINE_SUFFIX,SESSION,SUBJS_PER_NODE,SLURM_CPUS_PER_TASK,ITER,ANALYSIS_LEVEL,OUTPUT_SPACES,BIDS_PIPE,HEURISTIC,METADATA_EXTRA,RECON,OUTPUT_RESOLUTION,TBSS_PIPELINE,TBSS_MERGE_LIST,MODIFIER,ALGORITHM,DESIGN,BIASCORR,ALGORITHM_MIX,ALGORITHM1,ALGORITHM2,BIASCORR1,BIASCORR2,ORIG_SPACE,TEMP_SPACE,LESION_DIR,READOUT_SPACE,ANAT_PREPROC,LOCATE_LEVEL,BIANCA_LEVEL,sublist,REGISTRATION_METHOD,REGISTRATION_TASK,TEMPLATE_WARP,MASKING,INTERPOLATION,INPUT_T1_HIPPUNFOLD,HIPPUNFOLD_OUTPUT_DENSITY

###################################################################################################################
# Batch script to prepare and parallelize pipeline execution
###################################################################################################################

source /sw/batch/init.sh
start=$(date +%s)

# Load HPC environment modules
module load apptainer
module load parallel

# -x to get verbose logfiles
set -x

# Change default permissions for new files >>> This should probably be set individually for each project
#umask u=rwx g=rwx

# Do not dump core files
ulimit -c 0

# Source project environment
set -o allexport
source $SCRIPT_DIR/environment.conf
set +o allexport

# Set further environment
export TEMPLATEFLOW_HOME=$BIDS_DIR/code/templateflow; 			[ ! -d $TEMPLATEFLOW_HOME ] && mkdir -p $TEMPLATEFLOW_HOME
export APPTAINERENV_TEMPLATEFLOW_HOME=$TEMPLATEFLOW_HOME;		[ ! -d $APPTAINERENV_TEMPLATEFLOW_HOME ] && mkdir -p $APPTAINERENV_TEMPLATEFLOW_HOME
export APPTAINER_CACHEDIR=$SCRATCH_DIR/apptainer_cache; 	[ ! -d $APPTAINER_CACHEDIR ] && mkdir -p $APPTAINER_CACHEDIR
export APPTAINER_TMPDIR=$SCRATCH_DIR/apptainer_tmp; 		[ ! -d $APPTAINER_TMPDIR ] && mkdir -p $APPTAINER_TMPDIR
export APPTAINERENV_FS_LICENSE=$ENV_DIR/freesurfer_license.txt

if [ -z $ANALYSIS_LEVEL ];then
	echo "Specify analysis level. (subject/group)"
	read ANALYSIS_LEVEL; export ANALYSIS_LEVEL
fi

# Define subarray of subjects to process
subj_batch_array=($@)

# Provide feedback to user
echo starting processing with $PIPELINE from index: $ITER ...
echo for n=$SUBJS_PER_NODE subjects
echo subjects to process: ${subj_batch_array[@]}
echo submission script directory: $SCRIPT_DIR
echo ITERator: $ITER

# Define hardware configuration for the batch job
# SLURM_CPUS_PER_TASK is set in 01_pipelines_submission.sh and used here to define the number of threads per subject ("GNU_CPUS_PER_TASK")

HPC_VIRTUAL_NODES=$(awk "BEGIN {print int($SLURM_CPUS_PER_TASK / 8); exit}")

if [ "$ANALYSIS_LEVEL" == "subject" ];then

    export GNU_CPUS_PER_TASK=$(awk "BEGIN {print int($SLURM_CPUS_PER_TASK * 2 / $SUBJS_PER_NODE); exit}")
	export MEM_MB=$(awk "BEGIN {print int($HPC_MEM * $HPC_VIRTUAL_NODES / $SUBJS_PER_NODE); exit}")

elif [ "$ANALYSIS_LEVEL" == "group" ];then

    export GNU_CPUS_PER_TASK=$SLURM_CPUS_PER_TASK
	export MEM_MB=$(awk "BEGIN {print int($HPC_MEM * $HPC_VIRTUAL_NODES); exit}")

fi

export OMP_NTHREADS=$(($GNU_CPUS_PER_TASK - 1 )) # Variable for prep-pipelines like qsiprep
export MEM_GB=$(awk "BEGIN {print int($MEM_MB/1000); exit}")

# Additional variables recommended by cluster admins 
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK  # essential
export OMP_PROC_BIND=spread                  # recommended
export OMP_PLACES=cores                      # recommended
export OMP_SCHEDULE=static                   # recommended
export OMP_DISPLAY_ENV=verbose               # good to know

# All relative paths relate to project_dir
cd $PROJ_DIR

# Run pipeline
PROC_SCRIPT=$PIPELINE_DIR/${PIPELINE}${PIPELINE_SUFFIX}.sh

if [ $ANALYSIS_LEVEL == subject ];then

	parallel="parallel --ungroup --delay 0.2 -j$SUBJS_PER_NODE --joblog $CODE_DIR/log/parallel_runtask.log"
	echo -e "running:\n $parallel $proc_script {} ::: ${subj_batch_array[@]}"
	$parallel $PROC_SCRIPT ::: ${subj_batch_array[@]}

elif [ $ANALYSIS_LEVEL == group ];then

	source $PROC_SCRIPT "${subj_batch_array[@]}"
	
fi

# Monitor usage of $SCRATCH_DIR (intermediate files)
df -h $SCRATCH_DIR

# Output script runtime
runtime_s=$(expr $(expr $(date +%s) - $start))
echo "script runtime: $(date -d@$runtime_s -u +%H:%M:%S) hours"
