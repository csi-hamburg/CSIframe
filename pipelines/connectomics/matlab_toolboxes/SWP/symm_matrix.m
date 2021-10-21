function [W] = symm_matrix(A, bin_key)

% a function to symmetrize an input matrix. The procedure
% by which items are symmetrized such that:
%   in the binary case:
%       if a(i,j) || a(j,i) == 1 for i,j in A
%           w(i,j) && w(j,i) == 1
%   in  the weighted case:
%       if (a(i,j) || a(j,i) > 0 for i,j in A
%           w(i,j) && w(j,i) == (a(i,j) + a(j,i) )/ 2

% Inputs:
%   A:          The binary or weighted input matrix
%   bin_key:    the key to indicate whether weighted or binary analysis
%               will take place
%               1 indicates binarized, 0 indicates weighted

% Outputs
%   W:          The symmeterized matrix

% if binary analysis is specified, let binary symmeterization take place 

% written by Eric W. Bridgeford

W = zeros(length(A));

if bin_key == 1
    A = A > 0; % verify that the input matrix is binary
    for i = 1:length(A)
        for j = i:length(A)
            if A(i,j) || A(j,i)
                W(i,j) = 1;
                W(j,i) = 1;
            end
        end
    end
else
    for i = 1:length(A)
        for j = i:length(A)
            if A(i,j) || A(j,i)
                val = (A(i,j) + A(j,i)) / 2;
                W(i,j) = val;
                W(j,i) = val;
            end
        end
    end
end

    

