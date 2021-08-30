Invoke dataset_helper.sh and provide the name of the dataset_concerned in the same directory as the dataset_helper.sh

1. Setup new superdataset
    `setup_superdataset` in dataset_helper.sh will create a new superdataset, install hummel_processing in ./code from github and ask you where to clone envs from (default is S3 bucket)
2. Preparing raw data for processing
    1. `add_data_subds`
        - add `dicoms/ raw_bids` (and derivative subdatasets) in data/
    2. `import_dcms`
        - Imports dicoms from a directory containing DICOMS
        - ./subjects/session/sequences/DCMs is the assumed structure
        - If session is missing add it with `add_ses_dcm` in dataset_helper.sh
    4. `convert_containers`
        - Convert singularity containers to sandboxes that are used in the pipeline scripts
    5. Pipeline specific precautions
        -  For prep pipelines: download templateflow data (can only be downloaded on login node with internet connection) and `datalad get envs/freesurfer_license.txt`
        - Bianca: containers (mrtrix, freesurfer, fsl), freesurfer license, classifier in sourcedata
-> Now bidsification of dicoms should be possible with `bidsify`
3. Processing
    - `add_data_subds`
        - Add a derivative-specific subdataset to data/ (e.g. data/fmriprep)
    - Fix FIXMEs
        - smriprep: --output-spaces
    - Pipeline testing (optional but recommended)
        - Execute in code before job submission
        1. `salloc`: allocate an interactive node for an hour
        2. `export PIPELINE=<pipeline>`: export PIPELINE variable to specify pipeline
        3. Provide session if applying session-specific analysis (like *bidsify*); e.g. `export SESSION=1`
        4. `srun pipelines_processing.sh <test_subject>`: run pipelines_processing.sh on allocated node
        5. Optional: `srun pipelines_parallelization.sh` to test parallelization interactively 
    - Pipeline execution `bash pipelines_submission.sh <pipeline>`
