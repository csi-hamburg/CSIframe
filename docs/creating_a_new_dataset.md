Invoke dataset_helper.sh and provide the name of the dataset_concerned in the same directory as the dataset_helper.sh

1. Setup new superdataset
    `setup_superdataset` in dataset_helper.sh will create a new superdataset, install hummel_code in ./code from github and ask you where to clone envs from (for now envs is in /work/fatx405/projects/envs)
2. Preparing raw data for processing
    1. `add_dcm_subds`
        - add `dicoms/` subdataset in data/
    2. `import_dcms`
        - Imports dicoms from a directory containing DICOMS
        - ./subjects/session/sequences/DCMs is the assumed structure
        - If session is missing add it with add_ses_dcm in dataset_helper.sh
        - Mind to move dicoms to annex and propagate information to superdataset (from superdataset root -> `datalad save -m "Import dicoms" -d^. -r data/dicoms`)
    3. `add_raw_bids`
        - Adds raw_bids subdataset to data/ and install subject subdatasets to it
        - If no dicoms are available/necessary import of a raw BIDS dataset can be initiated alternatively
        - Mind to check whether raw_bids is clean (everything saved to annex, propagated to superdataset?)
    4. `convert_containers`
        - Convert singularity containers to sandboxes that are used in the pipeline scripts
    5. For prep pipelines: download templateflow data and `datalad get envs/freesurfer_license.txt` 
    5. Ensure that dataset is clean with `datalad status` and `datalad save` 
-> Now bidsification of dicoms should be possible
3. Processing
    - `add_data_subds`
        - Add a derivative-specific subdataset to data/ (e.g. data/fmriprep)
    - `add_subjects_subds`
        - Add subject subdatasets to a data subdataset in data/ (e.g. add data/fmriprep/sub-0001)
    - Before execution of pipeline scripts make sure that all datasets you are reading from and pushing to are in a clean state (content saved to annex and all information propagated to superdataset) with `datalad status data/subds` and `datalad save -d^. -r data/subds`
    - Fix FIXMEs
        - bidsify: heudiconv heuristic and dicom directory structure
        - qsiprep: --recon-spec
        - smriprep: --output-spaces
    - Pipeline testing (optional but recommended)
        - Execute in code before job submission
        1. `salloc`: allocate an interactive node for an hour
        2. `export PIPELINE=<pipeline>`: export PIPELINE variable to specify pipeline
        3. Provide session if applying session-specific analysis (like *bidsify*); e.g. `export SESSION=1`
        4. `srun pipelines_processing.sh <test_subject>`: run pipelines_processing.sh on allocated node
        5. Optional: `srun pipelines_parallelization.sh` to test parallelization interactively 
    - Pipeline execution `bash pipelines_submission.sh <pipeline>`
