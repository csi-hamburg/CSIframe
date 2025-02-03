% Patient folder
OutputFolder='/beegfs/g/thomalla/bao4990/CSI_FRAME/data/pvs';

% Dataset folder
dataset_path='/beegfs/g/thomalla/bao4990/CSI_FRAME/data/fmriprep';

% Reference Image (Brain Segmentation Reference) choose higher resolved
options.SegmentationReferenceImage='T1w';

% Image for PVS analysis (PVS Segmentation) 
options.PVSReferenceImage='T1w';

% Not needed as we exclude artefactual PVS segmentation when postprocessing
%options.artefact.template=[library_path,'/Artefact_Templates/template_55y/template_55y.nii.gz'];
%options.artefact.mask=[library_path,'/Artefact_Templates/template_55y/template_55y_artefactual_PVSROI.nii.gz'];

% % Vessel-shape likelihood Parameters: choose between FRANGI and RORPO
options.VSLParameters.Filter='FRANGI'; % default FRANGI
%options.VSLParameters.Filter='RORPO'; % default FRANGI

% Frangi parameters
options.VSLParameters.FrangiAlpha=0.5; ...
options.VSLParameters.FrangiBeta=0.5;
options.VSLParameters.FrangiC=500; 
options.VSLParameters.verbose=false;

% Set Frangi scale range
options.VSLParameters.FrangiScaleRange= [0.4 0.8]; %In mm internally it convert the parameters to the voxels

% RORPO parameters
% options.VSLParameters.normalize=0; % Normalize image (0 or 1)
% options.VSLParameters.type='uint8'; % Provide for the input truncation (Faster) 
% options.VSLParameters.core=7; % Number of cores to be used (0-7)
% options.VSLParameters.dilation=1; % Dilation size (1<)
% options.VSLParameters.scaleMin=1; % Minimum pvs size (1<)
% options.VSLParameters.nbScalesPV/usr/local/freesurfer/bin/freesurfer/usr/local/freesurfer/bin/freesurfer=9; % Max number of scales (1<)
% options.VSLParameters.factor=1.7; % Scale increase factor (1<)
%options.VSLParameters.RORPO_path='/home/rduarte/RORPO/bin/';

if strcmp(options.PVSReferenceImage,'T1w')
    options.VSLParameters.BlackWhite=true;
else
    options.VSLParameters.BlackWhite=false;
end

% These parameters need to be defined empirically
% Input ROIs Parameters
% Define threshold for the vessel-shape likelihood
options.ROIs.LeftBG.VSLThresh=2.4;
options.ROIs.RightBG.VSLThresh=2.4;
options.ROIs.LeftCSO.VSLThresh=1.0;
options.ROIs.RightCSO.VSLThresh=1.0;
options.ROIs.Midbrain.VSLThresh=1.7;

% % Define threshold for the vessel-shape likelihood for WMH
options.ROIs.LeftBG.VSLThreshWMH=5;
options.ROIs.RightBG.VSLThreshWMH=5;
options.ROIs.LeftCSO.VSLThreshWMH=5;
options.ROIs.RightCSO.VSLThreshWMH=5;
options.ROIs.Midbrain.VSLThreshWMH=5;

% Define the number of connections for connected-component analysis
options.ROIs.LeftBG.nConect=18;
options.ROIs.RightBG.nConect=18;
options.ROIs.LeftCSO.nConect=18;
options.ROIs.RightCSO.nConect=18;
options.ROIs.Midbrain.nConect=18;

% Define the minimum expected number of voxels for each PVS 
options.ROIs.LeftBG.minVolume=3;
options.ROIs.RightBG.minVolume=3;
options.ROIs.LeftCSO.minVolume=3;
options.ROIs.RightCSO.minVolume=3;
options.ROIs.Midbrain.minVolume=3;

% Define the maximum expected number of voxels for each PVS 
options.ROIs.LeftBG.maxVolume=3000;
options.ROIs.RightBG.maxVolume=3000;
options.ROIs.LeftCSO.maxVolume=3000;
options.ROIs.RightCSO.maxVolume=3000;
options.ROIs.Midbrain.maxVolume=3000;

% Multispectral clustering - Uncomment if ROIs are not correct
%options.MSC=1;

%Overwrite existing files (1=Yes, 0=No)
options.overwrite.NIFTI=0;
options.overwrite.Registration=0;
options.overwrite.FS=0;
options.overwrite.FAST=0;
options.overwrite.MSC=0;
options.overwrite.WMH=0;
options.overwrite.Artefact=0;
options.overwrite.ROI=0;
options.overwrite.VSL=1;
options.overwrite.PVS=1;

% Create Output Folder if it does not exists
if ~exist(OutputFolder, 'dir')
    mkdir(OutputFolder);
end

% Define input images used for PVS segmentation
% Note: subjectID and sessionID are defined when executing the pvs_seg container
% Uncomment the images that are not used
ImageFiles.T1w = [dataset_path, filesep, subjectID, filesep, 'ses-', sessionID, filesep, 'anat', filesep, subjectID,  '_ses-', sessionID, '_desc-preproc_T1w.nii.gz'];
%ImageFiles.T2w=[dataset_path, filesep, subjectID, filesep, 'ses-', sessionID, filesep, 'anat', filesep, subjectID,  '_ses-', sessionID, '_ses-01_T2w.nii.gz'];
%ImageFiles.FLAIR=[dataset_path, filesep, subjectID, filesep, 'ses-', sessionID, filesep, 'anat', filesep, subjectID,  '_ses-', sessionID, '_ses-01_FLAIR.nii.gz'];

% Define Output folders for each patient if it does not exists
%PFolder.NIFTI=[OutputFolder, filesep, subjectID, filesep, 'ses-', sessionID, filesep, 'anat'];
PFolder.Registration=[OutputFolder, filesep, subjectID, filesep, 'ses-', sessionID, filesep, 'anat', filesep, 'registration'];
PFolder.Segmentation=[OutputFolder, filesep, subjectID, filesep, 'ses-', sessionID, filesep, 'anat', filesep, 'segmentation'];
PFolder.PVS=[OutputFolder, filesep, subjectID, filesep, 'ses-', sessionID, filesep, 'anat', filesep, 'pvs'];
PFolder.VQC=[OutputFolder, filesep, subjectID, filesep, 'ses-', sessionID, filesep, 'visual_qc'];
PFolder.FreeSurfer=[dataset_path, filesep, '..', filesep, 'freesurfer', filesep, subjectID];

% Define Folder for measurement files
PFolder.Measurements=[OutputFolder, filesep, subjectID, filesep, 'ses-', sessionID, filesep, 'anat', filesep, 'pvs'];