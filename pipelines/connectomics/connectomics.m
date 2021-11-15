function connectomics(subject, input_path, output_path, session, threads, atlas, connectivity_type, connectivity_method, tmp_dir, env_dir)
% FUNCTION:
%         Computes multiple structural connectomics metrics given a adjacency matrix
%
% DEPENDENCIES (ensure installation):
%         Brain Connectivity Toolbox (Rubinov & Sporns, 2010, https://sites.google.com/site/bctnet/)
%         Small World Propensity (Muldoon et al., 2016, https://complexsystemsupenn.com/s/SWP1.zip)
%         Controllability (Gu et al., 2015, https://complexsystemsupenn.com/s/controllability_code-smb8.zip)
%         Parallel Computing Toolbox
% 
%
% INPUT:
%         input_path: connectome as output by qsiprep or xcpengine
%         output_path: output.csv being created before function call
%         threads: how many threads to use
%         atlas: which atlas to operate on
%           structural (qsiprep): schaefer100x17, schaefer200x17,
%           schaefer400x17, aicha384, power264, aal116, brainnetome246,
%           gordon333
%           functional (xcpengine): schaefer100x17, schaefer200x17,
%           schaefer400x17
%         connectivity_type: structural or functional connectivity (sc, fc)
%           Please mind that not every computed metric is sensible in the
%           realms of both connectivites (efficiency for fc, controllability for sc)
%         connectivity_method: which connectome flavor to operate on
%           structural (qsiprep): count, sift, invnode_sift, mean_length
%           functional (xcpengine): simply provide preprocessing short (e.g. 36pspkreg)
%
% OUTPUT:
%         CSV files containing metrics at output_path
%
% Clinical Stroke Imaging Lab, University Medical Center Hamburg-Eppendorf, 2021. 

% Set up parallel computing to occur in $TMP_DIR
S = parallel.Settings;
profiles = S.findProfile;
index=1;
sc = profiles(index).getSchedulerComponent
set(sc, 'JobStorageLocation', tmp_dir)     
parpool(threads)

A_all=[]

subject=convertCharsToStrings(subject)
session=convertCharsToStrings(session)

% Input and preparation
if connectivity_type == "sc"

    % Define bids output dir
    bids_dir="dwi"
    
    % Input path
    mat_path=fullfile(input_path,subject,session,bids_dir,strcat(subject,"_",session,"_acq-AP_space-T1w_desc-preproc_space-T1w_dhollanderconnectome.mat"))

    % Define which connectome to pick from mat
    if connectivity_method == "count"
        connectivity_str = "_radius2_count_connectivity"
    elseif connectivity_method == "sift"
        connectivity_str = "_sift_radius2_count_connectivity"
    elseif connectivity_method == "invnode_sift"
        connectivity_str = "_sift_invnodevol_radius2_count_connectivity"
    elseif connectivity_method == "mean_length"
        connectivity_str = "_mean_length_connectivity"
    else
        print("No connectivity type provided")
    end

    % Import matfile and extract connectome and region labels
    A = importdata(mat_path)
    mat = A.(strcat(atlas,connectivity_str))
    region_ids = A.(strcat(atlas,"_region_ids"))
    region_labels_char = A.(strcat(atlas,"_region_labels"))
    region_labels=[]
    for region_idx=region_ids
        region_labels=[region_labels,strtrim(convertCharsToStrings(region_labels_char(region_idx,:)))]
    end

  

elseif connectivity_type == 'fc'
    
    % Define bids output dir
    bids_dir="func"

    % Input path
    mat_path=fullfile(input_path,subject,"fcon",atlas,strcat(subject,"_",atlas,"_network.txt"))

    % Extract parcel length from atlas name
    parcel_length=regexp(atlas,['\d+\.?\d*'],'match')
    parcel_length=str2num(cell2mat(parcel_length(1)))
    
    % Import connectome + region_labels, convert it to symmetric adjacency matrix
    A = importdata(mat_path)
    
    ones_upper=triu(ones(parcel_length)) - diag(diag(ones(parcel_length)))
    ones_upper(ones_upper==1) = A
    mat = ones_upper + ones_upper'
    mat(mat<0) = 0
    region_labels=importdata(strcat(env_dir,atlas,"_labels.mat"))

end

% Yeo networks
yeo_networks=["Default", "Cont", "Limbic", "VentAttn", "DorsAttn", "SomMot", "Vis"]

% Fix self connections and normalize
mat = weight_conversion(mat,'autofix')
mat = weight_conversion(mat,'normalize')

% Lower triangle and diagonal = NaN
mat_null = tril(mat)
mat_nan = mat_null
mat_nan(mat_null==0) = NaN

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Degree
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

weighted_degree_labels = strcat(atlas, "_", connectivity_type, "_weighted_degree_", region_labels)

weighted_degree = strengths_und(mat)
median_weighted_degree = median(weighted_degree)

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Connectivity, segregation & modularity
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Comput global (sum) and mean connectivity 
connectivity = sum(reshape(mat_nan,1,[]), "omitnan")
mean_connectivity = mean(reshape(mat_nan,1,[]), "omitnan")

% Save labels and results in vectors 
network_connectivity_labels = [strcat(atlas, "_" , connectivity_type, "_", char('summed_connectivity', 'mean_connectivity'))]'
network_connectivity = [connectivity(:), mean_connectivity(:)]

network_segregation_labels = []
network_segregation = []

modQ_vector = []

for net_idx = 1:numel(yeo_networks)
    
    % Define label vector containing variable names for dataframe
    network_label=lower(strcat(atlas, "_", connectivity_type,  "_yeo_", yeo_networks(net_idx), "_", "within_connectivity"))
    feeder_label=lower(strcat(atlas, "_", connectivity_type, "_yeo_", yeo_networks(net_idx), "_", "feeder_connectivity"))
    periph_label=lower(strcat(atlas, "_", connectivity_type, "_yeo_", yeo_networks(net_idx), "_", "periph_connectivity"))
    network_label_mean=lower(strcat(atlas, "_", connectivity_type, "_yeo_", yeo_networks(net_idx), "_", "within_connectivity_mean"))
    feeder_label_mean=lower(strcat(atlas, "_", connectivity_type, "_yeo_", yeo_networks(net_idx), "_", "feeder_connectivity_mean"))
    periph_label_mean=lower(strcat(atlas, "_", connectivity_type, "_yeo_", yeo_networks(net_idx), "_", "periph_connectivity_mean"))
    network_connectivity_labels = [network_connectivity_labels, network_label, feeder_label, periph_label ...
        network_label_mean, feeder_label_mean, periph_label_mean]
    
    subnetwork_segregation_label=lower(strcat(atlas, "_yeo_", yeo_networks(net_idx), "_", "segregation"))
    network_segregation_labels = [network_segregation_labels, subnetwork_segregation_label]
    
    % Find indices that correspond with yeo network
    pos=strfind(region_labels, yeo_networks(net_idx))
    matches = find(~cellfun(@isempty,pos))
    network_labels=region_labels(matches)
    
    % Loop through vector of nonzero edge weights (row/column are provided by find)
    network_connectivity_vector=[]
    feeder_connectivity_vector=[]
    periph_connectivity_vector=[]
    modQ_vector=[]
    [row,col,v]=find(mat_null)
    
    parfor i = 1:numel(v)
        
        % compute modularity Q vector entry
        modQ_vector = [modQ_vector, (v(i) - weighted_degree(row(i)) * weighted_degree(col(i)) / (2 * connectivity)) * (ismember(row(i),matches) && (ismember(col(i),matches)))]

        % If row and column correspond with network nodes -> network edge
        if (ismember(row(i),matches)) && (ismember(col(i),matches))
            network_connectivity_vector=[network_connectivity_vector,mat_null(row(i),col(i))]
        % If column or row doesn't correspond to network node -> feeder edge
        elseif (not(ismember(row(i),matches))) && (ismember(col(i),matches)) && (mat_null(row(i),col(i)) ~= 0)
            feeder_connectivity_vector=[feeder_connectivity_vector,mat_null(row(i),col(i))]
        elseif (ismember(row(i),matches)) && (not(ismember(col(i),matches))) && (mat_null(row(i),col(i)) ~= 0)
            feeder_connectivity_vector=[feeder_connectivity_vector,mat_null(row(i),col(i))]
            
        % If row and column do not correspond with network nodes -> peripheral edge
        elseif (not(ismember(row(i),matches))) && (not(ismember(col(i),matches))) && (mat_null(row(i),col(i)) ~= 0)
            periph_connectivity_vector=[periph_connectivity_vector,mat_null(row(i),col(i))]
        end
    end
    
    % Define mean network, feeder and peripheral connectivity
    mean_network_connectivity = mean(network_connectivity_vector)
    mean_feeder_connectivity = mean(feeder_connectivity_vector)
    mean_periph_connectivity = mean(periph_connectivity_vector)
    network_connectivity = [network_connectivity, sum(network_connectivity_vector),...
    sum(feeder_connectivity_vector), sum(periph_connectivity_vector), mean_network_connectivity,...
    mean_feeder_connectivity, mean_periph_connectivity]

    % segregation
    subnetwork_segregation = mean_network_connectivity - mean_feeder_connectivity / mean_network_connectivity 
    network_segregation = [network_segregation, subnetwork_segregation]

end    

% Compute global segregation and modQ
global_network_segregation = mean(network_segregation)
global_network_segregation_label =lower(strcat(atlas, "_", connectivity_type, "_yeo_mean_segregation"))

modQ_label=lower(strcat(atlas, "_", connectivity_type,  "_yeo_modularityQ"))
modQ = 1 / (2 * connectivity) * sum(modQ_vector)

% Save labels and results in vectors 
glob_graph_labels = [global_network_segregation_label, modQ_label]
glob_graph_param = [global_network_segregation, modQ]

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Efficiency, clustering, SWP, density
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

glo_eff = efficiency_wei(mat)
clust_coeff = clustering_coef_wu_sign(mat)
mean_clust_coeff = mean(clust_coeff)
swp = small_world_propensity(mat)
density = density_und(mat)

array_glo_eff_null = []
array_lo_eff_null = []
array_cc_null = []

% Permute null models for normalization
parfor idx = 1:100
    mat_null = null_model_und_sign(mat)
    glo_eff_null = efficiency_wei(mat_null)
    cc_null = mean(clustering_coef_wu_sign(mat_null))
    array_glo_eff_null = [array_glo_eff_null glo_eff_null]
    array_cc_null = [array_cc_null cc_null]
end

% Normalization of efficiency and cc
glo_eff_norm = glo_eff / mean(array_glo_eff_null)
cc_norm = mean_clust_coeff / mean(array_cc_null)

% Save labels and results in vectors 
glob_graph_labels = [glob_graph_labels, strcat(atlas, "_" , connectivity_type, "_", char('global_eff_norm', 'global_clust_coeff_norm',...
    'small_world_propensity', 'density', 'median_weighted_degree'))']
glob_graph_param = [glob_graph_param, glo_eff_norm, cc_norm, swp, density, median_weighted_degree]

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Network controllability
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Compute average and modal controllability
avg_ctrl = ave_control(mat)'
median_avg_ctrl = median(avg_ctrl)
modal_ctrl = modal_control(mat)'
median_modal_ctrl = median(modal_ctrl)

% Save labels and results in vectors
glob_graph_labels = [glob_graph_labels, strcat(atlas, "_" , connectivity_type, "_", char('median_avg_ctrl', 'median_modal_ctrl'))']
glob_graph_param = [glob_graph_param, median_avg_ctrl(:), median_modal_ctrl(:)]
avg_control_labels = strcat(atlas, "_", connectivity_type, "_avg_control_", region_labels)
modal_control_labels = strcat(atlas, "_", connectivity_type, "_mod_control_", region_labels)

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Prepare output structure array
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Concatenate label vectors and values vectors
name_vector = ["sub_id", network_connectivity_labels, network_segregation_labels, glob_graph_labels,...
    weighted_degree_labels, avg_control_labels, modal_control_labels]
sub_vector = [subject, network_connectivity, network_segregation, glob_graph_param, ...
    weighted_degree, avg_ctrl, modal_ctrl]

% Merge vectors to table
T_sub = array2table(sub_vector)
T_sub.Properties.VariableNames = name_vector
A_all = [A_all, sub_vector]

% Write table to output
sub_out_dir=fullfile(output_path,subject,session,bids_dir) 
sub_out_file=strcat(sub_out_dir,"/",subject,"_",session,"_",atlas,"_",connectivity_type,"_",connectivity_method,"_connectomics.csv")
mkdir(sub_out_dir)
system(strcat('touch', {' '}, sub_out_file))
writetable(T_sub,sub_out_file)
