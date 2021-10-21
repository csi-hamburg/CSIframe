function M = regular_matrix_generator(G,r)
%generates a regular matrix, with weights obtained form the 
%original adjacency matrix representation of the network

% note that all inputs should be symmeterized prior to forming a regular
% matrix, since otherwise half of the connnections will be trashed. This
% can be accomplished with the built in symm_matrix function, however,
% the function is not performed here so that users can use their own 
% symmeterization procedure.

%Inputs:
%   G    the adjacency matrix for the given network; must be symmmeterized
%   r    the approximate radius of the regular network 

%Outputs:
%   M    the regular matrix for the given network, where all 
%        weights are sorted such that the inner radius has the
%        highest weights randomly distributed across the nodes, 
%        and so on

%written by Eric W. Bridgeford 

n = length(G);
G = triu(G);
%reshape the matrix G into an array, B
B = reshape(G,[length(G)^2,1]);
%sorts the array in descending order
B = sort(B,'descend');
%computes the number of connections and adds zeros if 
%numel(G) < 2*n*r
num_els =ceil(numel(G)/(2*n));
num_zeros = 2*n*num_els - numel(G);
%adds zeros to the remaineder of the list, so length(B) = 2*n*r
B = cat(1,B,zeros(num_zeros,1));
%reshapes B into a matrix, where the values descend top to
%bottom, as well as left to right. The greatest value in each 
%column is less than the smallest value of the column to its left.
B = reshape(B,[n],[]);

M = zeros(length(G));

%distributes the connections into a regular network, M, where
%the innermost radius represents the highest values
for i = 1:length(G)
    for z = 1:r
        a = randi([1,n]);

        %random integer chosen to take a value from B
        while (B(a,z) == 0 && z ~= r) || (B(a,z) == 0 && z == r && ~isempty(find(B(:,r),1)))
            a = randi([1,n]);
        end
        %finds the two nodes a distance of z from the origin node
        %and places the entries from the matrix B
        y_coor_1 = mod(i+z-1,length(G))+1;
        %y_coor_2 = mod(i-z-1,length(G))+1;
        M(i,y_coor_1) = B(a,z);
        M(y_coor_1,i) = B(a,z);
        %removes the weights from the matrix B so they cannot be
        %reused
        B(a,z) = 0;      
        
    end
end
end
