function [Clus] = avg_clus_matrix(W, met)
%a function to compute the average clusteirng coefficient for a 
%input matrix M

%Inputs:
%   W     a matrix, weighted or unweighted
%   met   a string, to represent the method to be used for computing
%         the clustering coefficient
%         possible strings: 'O' (Onnela), 'Z' (Zhang), 'B' (Barrat),
%         'bin' (binary)
%         default if none is chosen is Onnela

%Outputs:
%   Clus  the average clustering coefficient

%written by Eric Bridgeford

n = length(W);
[C] = clustering_coef_matrix(W, met);
Clus = mean(C, 'omitnan');
end
