"""
## module Potentials

### Summary

This module implements some basic interatomic potentials in pure Julia, as well
as provides building blocks and prototypes for further implementations
The implementation is done in such a way that they can be used either in "raw"
form or withinabstractframeworks.

### Types

### `evaluate`, `evaluate_d`, `evaluate_dd`, `grad`

### The `@D`, `@DD`, `@GRAD` macros

TODO: write documentation

"""
module Potentials



using JuLIP: Atoms, AbstractAtoms, AbstractCalculator,
      JVec, mat, vec, JMat, SVec, vecs, SMat,
      positions, set_positions!, fltype_intersect

using JuLIP.Chemistry: atomic_number

using StaticArrays: @SMatrix, SVector

using NeighbourLists

using LinearAlgebra: norm

using SparseArrays: sparse

using .Threads

import JuLIP: energy, forces, cutoff, virial, hessian_pos, hessian,
              site_energies, r_sum,
              site_energy, site_energy_d,
              energy!, forces!, virial!,
              alloc_temp, alloc_temp_d, alloc_temp_dd,
              read_dict, write_dict, fltype, rfltype,
              evaluate, evaluate_d, evaluate_dd, evaluate_ed,
              evaluate!, evaluate_d!, evaluate_dd!, evaluate_ed!,
              precon!

export PairPotential, SitePotential, ZeroSitePotential




include("potentials_base.jl")
# * @pot, @D, @DD
# *


"""
`SitePotential`:abstractsupertype for generic site potentials
"""
abstract type SitePotential <: AbstractCalculator end

"""
`SimpleSitePotential`:abstractsupertype for generic site potentials,
ignoring species
"""
abstract type SimpleSitePotential <: SitePotential end


"""
`PairPotential`:abstractsupertype for pair potentials
"""
abstract type PairPotential <: SitePotential end

"""
`SimplePairPotential`:abstractsupertype for pair potentials,
ignoring species
"""
abstract type SimplePairPotential <: PairPotential end

abstract type ExplicitPairPotential <: SimplePairPotential end



# ---- redirect with some convenience functions ----

# redirect allocating -> non-allocating calls

evaluate(V::SitePotential, R, args...) =
      evaluate!(alloc_temp(V, length(R)), V, R, args...)

evaluate_d(V::SitePotential, R::AbstractVector{JVec{T}}, args...) where {T} =
      evaluate_d!(zeros(JVec{fltype_intersect(V, T)}, length(R)),
                  alloc_temp_d(V, length(R)),
                  V, R, args...)

evaluate_dd(V::SitePotential, R::AbstractVector{JVec{T}}, args...) where {T} =
      evaluate_dd!(zeros(JMat{fltype_intersect(V, T)}, length(R), length(R)),
                   alloc_temp_dd(V, length(R)),
                   V, R, args...)


# ----- interface for SimpleSitePotential

evaluate!(tmp, V::SimpleSitePotential, R, Z, z0) =
      evaluate!(tmp, V, R)
evaluate_d!(dEs, tmp, V::SimpleSitePotential, R, Z, z0) =
      evaluate_d!(dEs, tmp, V, R)
evaluate_dd!(hEs, tmp, V::SimpleSitePotential, R, Z, z0) =
      evaluate_dd!(hEs, tmp, V, R)
precon!(hEs, tmp, V::SimpleSitePotential, R, Z, z0, innerstab) =
      precon!(hEs, tmp, V, R, innerstab)

# ------- Neighbourlist related business -------------------

NeighbourLists.sites(at::AbstractAtoms, rcut::AbstractFloat) =
      sites(neighbourlist(at, rcut))

NeighbourLists.pairs(at::AbstractAtoms, rcut::AbstractFloat) =
      pairs(neighbourlist(at, rcut))

"""
`neigsz!(tmp, nlist::PairList, at::Atoms, i::Integer) -> j, R Z`

requires a temporary storage array `tmp` with fields
`tmp.R, tmp.Z`.
"""
function neigsz!(tmp, nlist::PairList, at::Atoms, i::Integer)
   j, R = neigs!(tmp.R, nlist, i)
   Z = tmp.Z
   for n = 1:length(j)
      Z[n] = at.Z[j[n]]
   end
   return j, R, (@view Z[1:length(j)])
end

function neigsz(nlist::PairList, at::Atoms, i::Integer)
   j, R = NeighbourLists.neigs(nlist, i)
   return j, R, at.Z[j]
end

# ------------------------------------------------------

"a site potential that just returns zero"
mutable struct ZeroSitePotential <: SitePotential
end

@pot ZeroSitePotential

cutoff(::ZeroSitePotential) = Bool(0)
energy(V::ZeroSitePotential, at::AbstractAtoms{T}; kwargs...) where T = zero(T)
energy_t(V::ZeroSitePotential, at::AbstractAtoms{T}; kwargs...) where T = zero(T)
forces(V::ZeroSitePotential, at::AbstractAtoms{T}; kwargs...) where T = zeros(JVec{T}, length(at))
evaluate!(tmp, p::ZeroSitePotential, args...) = Bool(0)
evaluate_d!(dEs, tmp, V::ZeroSitePotential, args...) = fill!(dEs, zero(eltype(dEs)))
evaluate_dd!(hEs, tmp, V::ZeroSitePotential, args...) = fill!(hEs, zero(eltype(hEs)))



# Implementation of a generic site potential
# ================================================

alloc_temp_site(N::Integer, T=Float64) =
      ( R = zeros(JVec{T}, N),
        Z = zeros(AtomicNumber, N), )

alloc_temp(V::SitePotential, at::AbstractAtoms) =
      alloc_temp(V, maxneigs(neighbourlist(at, cutoff(V))))

alloc_temp(V::SitePotential, N::Integer) =
      ( R = zeros(JVecF, N),
        Z = zeros(AtomicNumber, N), )

alloc_temp_d(V::SitePotential, at::AbstractAtoms) =
      alloc_temp_d(V, maxneigs(neighbourlist(at, cutoff(V))))

alloc_temp_d(V::SitePotential, N::Integer) =
      (dV = zeros(JVec{fltype(V)}, N),
        R = zeros(JVecF, N),
        Z = zeros(AtomicNumber, N), )

alloc_temp_dd(V::SitePotential, args...) = nothing


# -------------- Implementations of energy, forces, virials
#                for a generic site potential


energy(V::SitePotential, at::AbstractAtoms; kwargs...) =
      energy!(alloc_temp(V, at), V, at; kwargs...)

virial(V::SitePotential, at::AbstractAtoms; kwargs...) =
      virial!(alloc_temp_d(V, at), V, at; kwargs...)

forces(V::SitePotential, at::AbstractAtoms; kwargs...) =
      forces!(zeros(JVec{fltype_intersect(V, at)}, length(at)),
              alloc_temp_d(V, at), V, at; kwargs...)

energy_t(V::SitePotential, at::AbstractAtoms; kwargs...) =
      energy_t!(alloc_temp(V, at), V, at; kwargs...)

virial_t(V::SitePotential, at::AbstractAtoms; kwargs...) =
      virial_t!(alloc_temp_d(V, at), V, at; kwargs...)

forces_t(V::SitePotential, at::AbstractAtoms; kwargs...) =
      forces_t!(zeros(JVec{fltype_intersect(V, at)}, length(at)),
      alloc_temp_d(V, at), V, at; kwargs...)


function energy!(tmp, calc::SitePotential, at::Atoms;
                 domain=1:length(at))
   TFL = fltype_intersect(calc, at)
   E = zero(TFL)
   nlist = neighbourlist(at, cutoff(calc))
   for i in domain
      j, R, Z = neigsz!(tmp, nlist, at, i)
      E += evaluate!(tmp, calc, R, Z, at.Z[i])
   end
   return E
end

function energy_t!(tmp, calc::SitePotential, at::Atoms;
                   domain=1:length(at))
   nthreads = nthreads()
   TFL = fltype_intersect(calc, at)
   E = zeros(TFL, nthreads())
   nlist = neighbourlist(at, cutoff(calc))
   @threads for i in domain
      j, R, Z = neigsz!(tmp, nlist, at, i)
      @inbounds E[threadid()] += evaluate!(tmp, calc, R, Z, at.Z[i])
   end
   Etot = zero(TFL)
   for i in eachindex(E)
      @inbounds Etot += E[i]
   end
   return Etot
end

function forces!(frc, tmp, calc::SitePotential, at::Atoms;
                 domain=1:length(at), reset=true)
   TFL = fltype_intersect(calc, at)
   if reset; fill!(frc, zero(eltype(frc))); end
   nlist = neighbourlist(at, cutoff(calc))
   for i in domain
      j, R, Z = neigsz!(tmp, nlist, at, i)
      if length(j) > 0
         evaluate_d!(tmp.dV, tmp, calc, R, Z, at.Z[i])
         for a = 1:length(j)
            frc[j[a]] -= tmp.dV[a]
            frc[i]    += tmp.dV[a]
         end
      end
   end
   return frc
end


site_virial(dV::AbstractVector{JVec{T1}}, R::AbstractVector{JVec{T2}}
            ) where {T1, T2} =  (
      length(R) > 0 ? (- sum( dVi * Ri' for (dVi, Ri) in zip(dV, R) ))
                    : zero(JMat{fltype_intersect(T1, T2)})
      )

function virial!(tmp, calc::SitePotential, at::Atoms; domain=1:length(at))
   TFL = fltype_intersect(calc, at)
   nlist = neighbourlist(at, cutoff(calc))
   vir = zero(JMat{TFL})
   for i in domain
      j, R, Z = neigsz!(tmp, nlist, at, i)
      if length(j) > 0
         evaluate_d!(tmp.dV, tmp, calc, R, Z, at.Z[i])
         vir += site_virial(tmp.dV, R)
      end
   end
   return vir
end


function site_energies(V::SitePotential, at::AbstractAtoms; kwargs...)
   TFL = fltype_intersect(V, at)
   return site_energies!(zeros(TFL, length(at)),
                         alloc_temp(V, at), V, at; kwargs...)
end

function site_energies!(Es, tmp, V::SitePotential, at::AbstractAtoms;
                        domain = 1:length(at))
   nlist = neighbourlist(at, cutoff(V))
   for i in domain
      _j, R, Z = neigsz!(tmp, nlist, at, i)
      Es[i] = evaluate!(tmp, V, R, Z, at.Z[i])
   end
   return Es
end

site_energy(V::SitePotential, at::AbstractAtoms, i0::Integer) =
      energy(V, at; domain = (i0,))

site_energy_d(V::SitePotential, at::AbstractAtoms, i0::Integer) =
      rmul!(forces(V, at; domain = (i0,)), -one(fltype(at)))


# ------------------------------------------------
#  specialisation for Pair potentials

include("analyticpotential.jl")

include("cutoffs.jl")

include("pairpotentials.jl")


include("adsite.jl")

include("stillingerweber.jl")

include("splines.jl")
include("eam.jl")

include("onebody.jl")

include("hessians.jl")

include("emt.jl")

end
