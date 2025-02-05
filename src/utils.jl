## Update set of active sets 
function update_ASs(ASs::BitMatrix, AS::BitVector)
    (m,n) = size(ASs);
    n==0 && return AS[:,:]
    AS_found = 0;
    for j in 1:n
        AS_found = 1;
        for i in 1:m
            if (AS[i] != ASs[i,j])
                AS_found=0;
                break
            end
        end
        AS_found == 1 && break
    end

    return AS_found == 0 ? [ASs AS] : ASs
end

function get_unique_ASs(part::Vector{Region})
    N = length(part)
    N==0 && return
    ASs_unique = part[1].ASs[:,end:end];
    for i = 2:N
        ASs_unique = update_ASs(ASs_unique,part[i].ASs[:,end])
    end
    return ASs_unique
end

## Check containment in partition 
function pointlocation(th::Vector{Float64}, partition::Vector{Region};eps_gap=0.0,terminate_early=false)
    inds = Int[]
    for (i,r) in enumerate(partition)
        if contains(r.Ath,r.bth,th;tol=eps_gap)
            push!(inds,i)
            terminate_early && break
        end
    end
    return inds 
end

## Parametric forward/backward substitution 
function forward_L_para!(L,b)
    # Solve L x = b
    n = size(b,2);
    for i in 1:n
        for j in 1:(i-1)
            @inbounds b[:,i] -= L[i,j]*view(b,:,j);
        end
    end
end

# Row instead of column vector
function backward_L_para!(L,x)
    # Solve L'x = b
    n = size(x,2);
    for i = n:-1:1
        for j = i+1:n
            @inbounds x[:,i] -= L[j,i]*view(x,:,j);
        end
    end
end

## Generate random mpQP
function generate_mpQP(n,m,nth;double_sided=true)
    M = randn(n,n)
    H = M*M'
    f = randn(n,1)
    f_theta = randn(n,nth)
    A = randn(m,n)
    b = [rand(m,1);rand(m,1)]
    F0 = randn(n,nth); # The point F0*th will be primal feasible
    if(double_sided)
        W =[A;-A]*(-F0);
        bounds_table = [collect(m+1:2m);collect(1:m)]
        senses = zeros(Cint,2m)
        mpQP = MPQP(H,f,f_theta,zeros(0,0),
                    [A;-A],b,W,bounds_table,senses)
    else
        W =A*(-F0);
        bounds_table = collect(1:m)
        senses = zeros(Cint,m)
        mpQP = MPQP(H,f,f_theta,zeros(0,0),
                    A,b[1:m,:],W,bounds_table,senses)
    end

    P_theta = (A = zeros(nth,0), b=zeros(0), ub=ones(nth),lb=-ones(nth),F0=F0) 

    return mpQP,P_theta
end
## Merged certify (LP) 
function merged_certify(prob::DualLPCertProblem,P_theta,AS0,opts)
    opts.storage_level=0
    opts.store_ASs=true
    part,max_iter,~,ASs,~,ASs_state = certify(prob,P_theta,AS0,opts);
    nth = length(P_theta.ub);

    exp_sol = []
    inds_constr = collect(1:size(ASs,1))
    # Compute regions
    for j = 1:size(ASs,2)
        AS = ASs[:,j]
        x = prob.d[:,AS]/(prob.M[AS,:]')
        μ=prob.d[:,.!AS]-x*(prob.M[.!AS,:])'
        Ath = [P_theta.A I(nth) -I(nth) -μ[1:end-1,:]];
        bth = [P_theta.b;P_theta.ub;P_theta.lb; μ[end,:].+opts.eps_primal];
        AS_int = inds_constr[AS];
        push!(exp_sol,(x=x,Ath=Ath,bth=bth, state=ASs_state[j]))
    end
    return exp_sol
end

