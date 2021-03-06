using Gridap
using LaTeXStrings
import CairoMakie
using Test
import Gridap: ∇

function run_CP(; n=10, generate_vtk::Bool=false, dirname::String, test::Bool=false)
    L = 2π
    h = L / n
    γ = 5
    α = 1

    u(x) = cos(x[1])*cos(x[2])

    order = 2
    domain2D = (0, L, 0, L)
    partition2D = (n,n)
    model = CartesianDiscreteModel(domain2D,partition2D)

    # Spaces
    V = TestFESpace(model, ReferenceFE(lagrangian,Float64,order), conformity=:H1)
    U = TrialFESpace(V)
    Ω = Triangulation(model)
    Λ = SkeletonTriangulation(model)
    Γ = BoundaryTriangulation(model)

    degree = 2*order
    dΩ = Measure(Ω,degree)
    dΓ = Measure(Γ,degree)
    dΛ = Measure(Λ,degree)

    n_Λ = get_normal_vector(Λ)
    n_Γ = get_normal_vector(Γ)

    # manufactured solution
    # g(x) = ( ∇( Δ(u))⊙n_Γ)(x) #this does not compile since u is a ordinary function inner product with normal field vector
    # f(x) = Δ(Δ(u))(x)+ α*u(x)
    f(x) = ( 4 + α )*u(x)
    g(x) = 0

    function mean_nn(u,n)
        return 0.5*( n.plus⋅ ∇∇(u).plus⋅ n.plus + n.minus ⋅ ∇∇(u).minus ⋅ n.minus )
    end

    ⋅
    # Inner facets
    a(u,v) =( ∫( ∇∇(v)⊙∇∇(u) + α⋅(v⊙u) )dΩ
             + ∫(-mean_nn(v,n_Λ)⊙jump(∇(u)⋅n_Λ) - mean_nn(u,n_Λ)⊙jump(∇(v)⋅n_Λ))dΛ
             + ∫((γ/h)⋅jump(∇(u)⋅n_Λ)⊙jump(∇(v)⋅n_Λ))dΛ
             + ∫(-( n_Γ ⋅ ∇∇(v)⋅ n_Γ )⊙∇(u)⋅n_Γ - ( n_Γ ⋅ ∇∇(u)⋅ n_Γ )⊙∇(v)⋅n_Γ)dΓ
             + ∫((γ/h)⋅ ∇(u)⊙n_Γ⋅∇(v)⊙n_Γ )dΓ
             )

    l(v) = ∫( v ⋅ f )dΩ + ∫(- (g⋅v))dΓ

    op = AffineFEOperator(a, l, U, V)
    uh = solve(op)

    e = u - uh
    el2 = sqrt(sum( ∫(e*e)dΩ ))
    eh = sqrt(sum( ∫( ∇∇(e)⊙∇∇(e) )*dΩ
                    + ( γ/h ) * ∫(jump(∇(e)⋅n_Λ) ⊙ jump(∇(e)⋅n_Λ))dΛ
                    + ( h/γ ) * ∫(mean_nn(e,n_Λ) ⊙ mean_nn(e,n_Λ))dΛ
                    + ( γ/h ) * ∫((∇(e)⋅n_Γ) ⊙ (∇(e)⋅n_Γ))dΓ
                    + ( h/γ ) * ∫(( n_Γ ⋅ ∇∇(e)⋅ n_Γ ) ⊙ ( n_Γ ⋅ ∇∇(e)⋅ n_Γ ))dΓ
                   ))


    if !generate_vtk
        return el2, eh
    end

    writevtk(model, dirname*"/model")
    writevtk(Λ,dirname*"/skeleton")
    writevtk(Λ,dirname*"/jumps",cellfields=["jump_u"=>jump(uh)])
    writevtk(Ω,dirname*"/omega",cellfields=["uh"=>uh])
    writevtk(Ω,dirname*"/error",cellfields=["e"=>e])
    writevtk(Ω,dirname*"/manufatured",cellfields=["u"=>u])

    if test==true
        @test el2 < 10^-5
    end
    return el2, eh1
end



function conv_test(;dirname)
    ns = [8,16,32,64]

    el2s = Float64[]
    ehs = Float64[]
    hs = Float64[]

    println("Run convergence tests")
    for n in ns

        el2, eh = run_CP(n=n, dirname=dirname)
        println("Simulation with n:", n, ", Errors:  L2: ", el2, " h:", eh)

        h = ( 1/n )*2*π
        push!(el2s,el2)
        push!(ehs,eh)
        push!(hs,h)
    end

    fig = CairoMakie.Figure()
    ax = CairoMakie.Axis(fig[1, 1], yscale = log10, xscale= log2,
                         yminorticksvisible = true, yminorgridvisible = true, yminorticks = CairoMakie.IntervalsBetween(8),
                         xlabel = "h", ylabel = "error norms")

    CairoMakie.lines!(hs, el2s, label= L"L2 norm,  ", linewidth=2)
    CairoMakie.lines!(hs, ehs, label= L"h norm ", linewidth=2)
    CairoMakie.scatter!(hs, el2s)
    CairoMakie.scatter!(hs, ehs)
    file = dirname*"/convergence.png"
    CairoMakie.Legend(fig[1,2], ax, framevisible = true)
    CairoMakie.save(file,fig)
end


function main()
    dirname = "minimal_example"

    if (isdir(dirname))
        rm(dirname, recursive=true)
    end
    mkdir(dirname)

    # run_CP(n=10, generate_vtk=true, dirname=dirname, test=false)
    conv_test(dirname=dirname)
end

main()
