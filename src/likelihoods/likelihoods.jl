#This file contains a list of the currently implemented likelihood function

import Base.show

@compat abstract type Likelihood end

function show(io::IO, lik::Likelihood, depth::Int = 0)
    pad = repeat(" ", 2*depth)
    print(io, "$(pad)Type: $(typeof(lik)), Params: ")
    show(io, get_params(lik))
    print(io, "\n")
end

include("bernoulli.jl")
include("exponential.jl")
include("gaussian.jl")
include("studentT.jl")
include("poisson.jl")
include("binomial.jl")

##########
# Priors #
##########
function set_priors!(lik::Likelihood, priors::Array)
    length(priors) == num_params(lik) || throw(ArgumentError("$(typeof(lik)) has exactly $(num_params(lik)) parameters"))
    lik.priors = priors
end

function prior_logpdf(lik::Likelihood)
    if num_params(lik)==0
        return 0.0
    elseif lik.priors==[]
        return 0.0
    else
        return sum(logpdf(prior,param) for (prior, param) in zip(lik.priors,get_params(lik)))
    end    
end

function prior_gradlogpdf(lik::Likelihood)
    if num_params(lik)==0
        return zeros(num_params(lik))
    elseif lik.priors==[]
        return zeros(num_params(lik))
    else
        return [gradlogpdf(prior,param) for (prior, param) in zip(lik.priors,get_params(lik))]
    end    
end

#————————————————————————————————————————————
#Predict observations at test locations

""" Computes the predictive mean and variance given a Gaussian distribution for f using quadrature."""
function predict_obs(lik::Likelihood, fmean::Vector{Float64}, fvar::Vector{Float64}) 
    n_gaussHermite = 20
    nodes, weights = gausshermite(n_gaussHermite)
    weights /= sqrt(pi)
    f = fmean .+ sqrt.(2.0*fvar)*nodes'
    
    mLik = Array{Float64}(size(f)); vLik = Array{Float64}(size(f));
    for i in 1:n_gaussHermite
        mLik[:,i] = mean_lik(lik, f[:,i]) 
        vLik[:,i] = var_lik(lik, f[:,i])
    end    
    μ = mLik*weights
    σ² = (vLik + mLik.^2)*weights - μ.^2
    return μ, σ²
end


#————————————————————————————————————————————
#Variational expectation

""" Compute the integral of the log-density of the observation model over a Gaussian approximation to the function values, i.e. ∫log p(y|f)q(f)df."""
function var_exp(lik::Likelihood, fmean::Vector{Float64}, fvar::Vector{Float64})
    n_gaussHermite = 20
    nodes, weights = gausshermite(n_gaussHermite)
    weights /= sqrt(pi)
    f = fmean .+ sqrt.(2.0*fvar)*nodes'
    logp = log_dens(lik,f,gp.y)
    return logp*weights


#————————————————————————————————————————————
#Kullkback-Leibler divergence

""" Compute the KL divergence between q(x) = N(qμ, qΣ²) and p(x) = N(0,K) """    
function kl(qμ::Vector{Float64}, qΣ::Vector{Float64})
    alpha = qμ
    Lq = qΣ
    mah = sum(alpha.^2)                             # Mahalanobis distance
    logdet_qcov = sum(log(tf.square(diag(Lq)).^2))  # Log-determinant of the covariance of q(x):
    trace = sum(Lq.^2)                              # Trace term: tr(Σp⁻¹ Σq)
    twoKL = mah - logdet_qcov + trace    
    return 0.5 * twoKL
