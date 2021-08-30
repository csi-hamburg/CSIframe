#!/bin/bash

# Set specific environment for pipeline
export MRTRIX_TMPFILE_DIR=$TMP_DIR

if [ -z $RECON ];then
	echo "Do you want to perform connectome reconstruction after preprocessing; i.e. qsiprep incl. qsirecon (y/n)"
	read RECON; export RECON
	if [ $RECON == y ];then
		echo "Choose reconstruction pipeline you want to apply (mrtrix_singleshell_ss3t, mrtrix_multishell_msmt)"
		read RECON_PIPELINE; export RECON_PIPELINE
	fi
fi

CMD="
   singularity run --cleanenv --userns -B $PROJ_DIR -B $TMP_DIR/:/tmp \
   $ENV_DIR/qsiprep-0.14.2 \
   data/raw_bids data participant \
   -w /tmp \
   --participant-label $1 \
   --nthreads $SLURM_CPUS_PER_TASK \
   --skip-bids-validation \
   --use-syn-sdc \
   --force-syn \
   --output-space T1w \
   --nthreads $SLURM_CPUS_PER_TASK \
   --omp-nthreads $OMP_NTHREADS \
   --mem_mb $MEM_MB \
   --denoise-method dwidenoise \
   --unringing-method mrdegibbs \
   --skull-strip-template OASIS \
   --stop-on-first-crash \
   --output-resolution 1.3 \
   --stop-on-first-crash \
   --fs-license-file envs/freesurfer_license.txt"
[ $RECON == y ] && CMD="${CMD} --recon_input data/qsiprep/$1 --recon_spec $RECON_PIPELINE"
$CMD