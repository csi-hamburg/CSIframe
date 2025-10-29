% Batch file for getting quality measures for SPM12/CAT12 standalone installation
%
%_______________________________________________________________________
% $Id$

% Read file list from text file
fileID = fopen('file_list.txt', 'r');
dataPaths = textscan(fileID, '%s');
fclose(fileID);

% data field, that will be dynamically replaced by cat_standalone.sh
matlabbatch{1}.spm.tools.cat.tools.quality_measures.data = dataPaths{1};

% Entry for csv output filename
% Remove comments and edit entry if you would like to change the parameter.
% Otherwise the default value from cat_defaults.m is used.
% Or use 1st parameter field, that will be dynamically replaced by cat_standalone.sh
matlabbatch{1}.spm.tools.cat.tools.quality_measures.csv_name = 'quality_measures_surfaces.csv';

% Entry for enabling global scaling with TIV
% Remove comments and edit entry if you would like to change the parameter.
% Otherwise the default value from cat_defaults.m is used.
% Or use 2nd parameter field, that will be dynamically replaced by cat_standalone.sh
% matlabbatch{1}.spm.tools.cat.tools.quality_measures.globals = '<UNDEFINED>';
