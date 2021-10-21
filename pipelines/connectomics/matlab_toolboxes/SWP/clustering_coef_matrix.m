function [C] = clustering_coef_matrix(W, met)

%a modification of the clustering coefficient function provided
%in the brain connectivity toolbox

%improved definition of Onnela Clustering Coefficient, as well as
%implementation of function for Zhang and Barrat clustering values

%Reference: 
%   Onnela et al., Phys. Rev. E71, 065103(R)(2005)
%   B.Zhang and S. Horvath, Stat. App. Genet. Mol. Biol.4, 17(2005)
%   Barrat et al., Proc. Natl. Acad. Sci. U.S.A.101, 3747(2004)
%   Watts and Strogatz (1998) Nature 393:440-442

%Inputs:
%   W    the weighted or unweighted connectivity matrix
%   met   a string, to represent the method to be used for computing
%         the clustering coefficient
%         possible strings: 'O' (Onnela), 'Z' (Zhang), 'B' (Barrat), 'bin'
%         (binary)
%         default if none is chosen is Onnela


%code originally written by Mika Rubinov, UNSW, 2007-2010
%modified/written by Eric Bridgeford

if met == 'O'
    K=sum(W~=0,2);
    W = double(W);
    W2 = W/max(max(W));
    cyc3=diag(W2.^(1/3)^3);
    K(cyc3==0)=inf;             %if no 3-cycles exist, make C=0 (via K=inf)
    C=cyc3./(K.*(K-1));
end
if met == 'bin'
    G = double(W>0);
    n=length(G);
    C=zeros(n,1);
    for u=1:n
        V=find(G(u,:));
        k=length(V);
        if k>=2;                %degree must be at least 2
            S=G(V,V);
            C(u)=sum(S(:))/(k^2-k);
        end
    end
end

if met == 'Z'
    K=sum(W~=0,2);
    W = double(W);
    W2 = W/max(max((W)));
    cyc3=diag((W2)^3);
    denom = zeros(length(W),1);
    for i = 1:length(W)
        denom(i) = (sum(W2(i,:))^2-sum(W2(i,:).^2));
    end
    C = cyc3./denom;
end

if met == 'B'
    A = double(W>0);
    C = zeros(length(W),1);
    for i = 1:length(W)
        sum1 = 0;
        for j = 1:length(W)
            for k = 1:length(W)
                sum1 = ((W(i,j)+W(i,k))/2)*A(i,j)*A(j,k)*A(i,k)+sum1;
            end
        end
        C(i) = 1/(sum(W(i,:))*(sum(A(i,:))-1))*sum1;
    end
end


end

