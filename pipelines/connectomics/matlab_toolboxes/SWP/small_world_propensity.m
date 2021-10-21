function [SWP,delta_C,delta_L] = small_world_propensity(A, varargin)

% a function for calculating the small world propensity of
% a given network - assumes that matrix is undirected (symmeteric) and if
% not, creates a symmetric matrix which is used for the calculations

%NOTE:  This code requires the Bioinformatics Toolbox to be installed
%        (uses graphallshortestpaths.m)

%Inputs:
%   A           the connectivity matrix, weighted or binary
%   varargin    a string corresponding to the method of clustering
%               to be used, where 'O' is Onnela, 'Z' is Zhang, 
%               'B' is Barrat, 'bin' is binary (default is Onnela).
%               If the user specifies binary analysis, a 
%               weighted matrix will be converted to a binary matrix 
%               before proceeding.
%        

%Outputs:
%   SWP         the small world propensity of the matrix
%   delta_C     the fractional deviation from the expected culstering coefficient of a
%                   random network
%   delta_L     the fractional deviation from the expected path length of a
%                   random network

%written by Eric Bridgeford

% Reference: Muldoon, Bridgeford, and Bassett (2015) "Small-World Propensity in Weighted, 
%               Real-World Networks" http://arxiv.org/abs/1505.02194

if isempty(varargin)
    varargin{1} = 'O';
end

if sum(sum(A)) > 0
    
bin_matrix = 0;
if strcmp(varargin{1},'bin') == 1
   bin_matrix = 1;
   A = A > 0;
end

%check to see if matrix is symmeteric
symcheck=abs(A-A');
if sum(sum(symcheck)) > 0
    % adjust the input matrix to symmeterize
    disp('Input matrix is not symmetric. Symmetrizing.')
    W = symm_matrix(A, bin_matrix);
else
    W=A;
end

%calculate the number of nodes
n = length(W);  
%compute the weighted density of the network
dens_net = sum(sum(W))/(max(max(W))*n*(n-1));

%compute the average degree of the unweighted network, to give
%the approximate radius
numb_connections = length(find(W>0));
avg_deg_unw = numb_connections/n;
avg_rad_unw = avg_deg_unw/2;
avg_rad_eff = ceil(avg_rad_unw);


%compute the regular and random matrix for the network W
W_reg = regular_matrix_generator(W, avg_rad_eff);
W_rand = randomize_matrix(W);

%compute all path length calculations for the network
reg_path = avg_path_matrix(1./W_reg);      %path of the regular network
rand_path = avg_path_matrix(1./W_rand);    %path of the random netowork
net_path = avg_path_matrix(1./W);          %path of the network

A = (net_path - rand_path);
if A < 0
    A = 0;
end
diff_path =  A/ (reg_path - rand_path);
if net_path == Inf || rand_path == Inf || reg_path == Inf
    diff_path = 1;
end
if diff_path > 1
    diff_path = 1;
end


%compute all clustering calculations for the network
reg_clus = avg_clus_matrix(W_reg,varargin{1});
rand_clus = avg_clus_matrix(W_rand,varargin{1});
net_clus = avg_clus_matrix(W,varargin{1});

B = (reg_clus - net_clus);
if B < 0
    B = 0;
end
    
diff_clus = B / (reg_clus - rand_clus);
if isnan(reg_clus) || isnan(rand_clus) || isnan(net_clus)
    diff_clus = 1;
end
if diff_clus > 1
    diff_clus = 1;
end

%calculate small world value, the root sum of the squares of
%diff path and diff clus
SWP = 1 - (sqrt(diff_clus^2 + diff_path^2)/sqrt(2));
delta_C=diff_clus;
delta_L=diff_path;
end


