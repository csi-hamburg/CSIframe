#!/bin/bash

# Set specific environment for pipeline
export MRTRIX_TMPFILE_DIR=$TMP_DIR

if [ $MODIFIED == y ];then
   # qsiprep only preprocessing
   recon=""
else
   # qsiprep + qsirecon
   recon="--recon_input data/qsiprep/$1 --recon_spec mrtrix_singleshell_ss3t"
fi

CMD="
   singularity run --cleanenv --userns -B $PROJ_DIR -B $TMP_DIR/:/tmp \
   $ENV_DIR/qsiprep-0.14.2 \
   data/raw_bids data participant \
   -w $TMP_DIR $recon \
   --participant-label $1 \
   --nthreads $SLURM_CPUS_PER_TASK \
   --skip-bids-validation \
   --use-syn-sdc \
   --force-syn \
   --output-space T1w \
   --nthreads $SLURM_CPUS_PER_TASK \
   --omp-nthreads $OMP_NTHREADS \
   --mem_mb $MEM_PER_SUB_MB \
   --denoise-method dwidenoise \
   --unringing-method mrdegibbs \
   --skull-strip-template OASIS \
   --stop-on-first-crash \
   --output-resolution 1.3 \
   --stop-on-first-crash \
   --fs-license-file envs/freesurfer_license.txt"
$CMD

# Move subject specific directories and files to qsiprep/$1 and qsirecon/$1, respectively
mv $CLONE_DATA_DIR/qsiprep/dwiqc.json $CLONE_DATA_DIR/qsiprep/$1
mv $CLONE_DATA_DIR/qsirecon/dwiqc.json $CLONE_DATA_DIR/qsirecon/$1