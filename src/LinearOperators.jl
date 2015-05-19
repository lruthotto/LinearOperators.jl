# Linear Operators for Julia
module LinearOperators

using Compat  # for Nullable types.

# Setup for documentation
if VERSION < v"0.4.0-dev"
  using Docile
  eval(:(@docstrings(manual = ["../doc/manual.md"])))  # Macro nonsense.
end

export LinearOperator, opEye, opOnes, opZeros, opDiagonal,
       opInverse, opCholesky, opHouseholder, opHermitian,
       check_ctranspose, check_hermitian, check_positive_definite,
       shape, hermitian, symmetric

KindOfMatrix = Union(Array, SparseMatrixCSC)


@doc """Abstract object to represent a linear operator.
The usual arithmetic operations may be applied to operators
to combine or otherwise alter them. They can be combined with
other operators, with matrices and with scalars. Operators may
be transposed and conjugate-transposed using the usual Julia syntax.
""" ->
type LinearOperator
  nrow   :: Int
  ncol   :: Int
  dtype   :: DataType
  symmetric :: Bool
  hermitian :: Bool
  prod   :: Function           # apply the operator to a vector
  tprod  :: Nullable{Function} # apply the transpose operator to a vector
  ctprod :: Nullable{Function} # apply the transpose conjugate operator to a vector
end


import Base.size

@doc "Return the size of a linear operator as a tuple" ->
size(op :: LinearOperator) = (op.nrow, op.ncol)

@doc "Return the size of a linear operator along dimension `d`" ->
function size(op :: LinearOperator, d :: Int)
  if d == 1
    return op.nrow;
  end
  if d == 2
    return op.ncol;
  end
  error("Linear operators only have 2 dimensions for now");
end

@doc "An alias for size" ->
shape(op :: LinearOperator) = size(op)

@doc "Determine whether the operator is Hermitian" ->
hermitian(op :: LinearOperator) = op.hermitian

@doc "Determine whether the operator is symmetric" ->
symmetric(op :: LinearOperator) = op.symmetric


import Base.show

@doc "Display basic information about a linear operator" ->
function show(io :: IO, op :: LinearOperator)
  s  = "Linear operator\n"
  s *= @sprintf("  nrow: %s\n", op.nrow)
  s *= @sprintf("  ncol: %d\n", op.ncol)
  s *= @sprintf("  dtype: %s\n", op.dtype)
  s *= @sprintf("  symmetric: %s\n", op.symmetric)
  s *= @sprintf("  hermitian: %s\n", op.hermitian)
  s *= @sprintf("  prod:   %s\n", string(op.prod))
  s *= @sprintf("  tprod:  %s\n", string(op.tprod))
  s *= @sprintf("  ctprod: %s", string(op.ctprod))
  s *= "\n"
  print(io, s)
end


# Constructors.
@doc """Construct a linear operator from a dense or sparse matrix.
Use the optional keyword arguments to indicate whether the operator
is symmetric and/or hermitian.""" ->
LinearOperator(M :: KindOfMatrix; symmetric=false, hermitian=false) =
  LinearOperator(size(M,1), size(M,2), typeof(M[1,1]), symmetric, hermitian,
                 v -> M * v,
                 Nullable{Function}(u -> M.' * u),
                 Nullable{Function}(w -> M' * w))

@doc "Construct a linear operator from functions." ->
LinearOperator(nrow :: Int, ncol :: Int, dtype :: DataType,
               symmetric :: Bool, hermitian :: Bool,
               prod :: Function, tprod :: Function, ctprod :: Function) =
  LinearOperator(nrow, ncol, dtype, symmetric, hermitian,
                 prod, Nullable{Function}(tprod), Nullable{Function}(ctprod))

@doc "Construct a real symmetric linear operator from a function." ->
LinearOperator(nrow :: Int, dtype :: DataType, prod :: Function) =
  LinearOperator(nrow, nrow, dtype, true, true,
                 prod,
                 Nullable{Function}(prod),
                 Nullable{Function}(prod))

@doc "Construct a linear operator from a single function." ->
LinearOperator(nrow :: Int, ncol :: Int, dtype :: DataType,
               symmetric :: Bool, hermitian :: Bool,
               prod :: Function) =
  LinearOperator(nrow, ncol, dtype, symmetric, hermitian,
                 prod, Nullable{Function}(), Nullable{Function}())


# Apply an operator to a vector.
function (*)(op :: LinearOperator, v :: Vector)
  (m, n) = size(op)
  if size(v,1) != n
    error("Shape mismatch")
  end
  return op.prod(v)
end

import Base.full

@doc "Materialize an operator as a dense array using `op.ncol` products" ->
function full(op :: LinearOperator)
  (m, n) = size(op)
  A = zeros(op.dtype, m, n)  # Must be of same dtype as operator.
  ei = zeros(op.dtype, n)
  for i = 1 : n
    ei[i] = 1;
    A[:,i] = op * ei;
    ei[i] = 0;
  end
  return A
end


# Unary operations.
(+)(op :: LinearOperator) = op
(-)(op :: LinearOperator) = LinearOperator(op.nrow, op.ncol, op.dtype,
                                           op.symmetric, op.hermitian,
                                           v -> -op.prod(v),
                                           Nullable{Function}(u -> -get(op.tprod)(u)),
                                           Nullable{Function}(w -> -get(op.ctprod)(w)))

function transpose(op :: LinearOperator)
  if op.symmetric
    return op
  end
  if !isnull(op.tprod)
    return LinearOperator(op.ncol, op.nrow, op.dtype, op.symmetric, op.hermitian,
                          get(op.tprod),
                          Nullable{Function}(op.prod),
                          Nullable{Function}(v -> conj(get(op.tprod)(v))))
  end
  if isnull(op.ctprod)
    if op.hermitian
      ctprod = op.prod;
    else
      error("Unable to infer transpose operator")
    end
  else
    ctprod = get(op.ctprod);
  end

  return LinearOperator(op.ncol, op.nrow, op.dtype, op.symmetric, op.hermitian,
                        v -> conj(ctprod(conj(v))),                # A.'v = conj(A' conj(v))
                        Nullable{Function}(op.prod),               # (A.').' = A
                        Nullable{Function}(w -> conj(op.prod(w)))) # (A.')' = conj(A)
end

function ctranspose(op :: LinearOperator)
  if op.hermitian
    return op
  end
  if !isnull(op.ctprod)
    return LinearOperator(op.ncol, op.nrow, op.dtype, op.symmetric, op.hermitian,
                          get(op.ctprod),
                          Nullable{Function}(u -> conj(op.prod(u))),
                          Nullable{Function}(op.prod))
  end
  if isnull(op.tprod)
    if op.symmetric
      tprod = op.prod;
    else
      error("Unable to infer conjugate transpose operator")
    end
  else
    tprod = get(op.tprod);
  end

  return LinearOperator(op.ncol, op.nrow, op.dtype, op.symmetric, op.hermitian,
                        v -> conj(tprod(v)),
                        Nullable{Function}(u -> conj(op.prod(u))),
                        Nullable{Function}(op.prod))
end

import Base.conj
function conj(op :: LinearOperator)
  return LinearOperator(op.nrow, op.ncol, op.dtype, op.symmetric, op.hermitian,
                        v -> conj(op.prod(conj(v))),
                        op.ctprod,
                        op.tprod)
end

# Binary operations.

## Operator times operator.
function (*)(op1 :: LinearOperator, op2 :: LinearOperator)
  (m1, n1) = size(op1)
  (m2, n2) = size(op2)
  if m2 != n1
    error("Shape mismatch")
  end
  result_type = promote_type(op1.dtype, op2.dtype)
  return LinearOperator(m1, n2, result_type, false, false,
                        v -> op1 * (op2 * v),
                        u -> op2.' * (op1.' * u),
                        w -> op2' * (op1' * w))
end

## Matrix times operator.
(*)(M :: KindOfMatrix, op :: LinearOperator) = LinearOperator(M) * op
(*)(op :: LinearOperator, M :: KindOfMatrix) = op * LinearOperator(M)

## Scalar times operator.
(*)(op :: LinearOperator, x :: Number) = LinearOperator(op.nrow, op.ncol,
                                                        promote_type(op.dtype, typeof(x)),
                                                        op.symmetric,
                                                        op.hermitian && isreal(x),
                                                        v -> (op * v) * x,
                                                        u -> x * (op.' * u),
                                                        w -> x' * (op' * w))
(*)(x :: Number, op :: LinearOperator) = LinearOperator(op.nrow, op.ncol,
                                                        promote_type(op.dtype, typeof(x)),
                                                        op.symmetric,
                                                        op.hermitian && isreal(x),
                                                        v -> x * (op * v),
                                                        u -> (op.' * u) * x,
                                                        w -> (op' * w) * x')
(.*)(op :: LinearOperator, x :: Number) = op * x
(.*)(x :: Number, op :: LinearOperator) = x * op

# Operator + operator.
function (+)(op1 :: LinearOperator, op2 :: LinearOperator)
  (m1, n1) = size(op1)
  (m2, n2) = size(op2)
  if (m1 != m2) || (n1 != n2)
    error("Shape mismatch")
  end
  return LinearOperator(m1, n1, promote_type(op1.dtype, op2.dtype),
                        op1.symmetric && op2.symmetric,
                        op1.hermitian && op2.hermitian,
                        v -> (op1   * v) + (op2   * v),
                        u -> (op1.' * u) + (op2.' * u),
                        w -> (op1'  * w) + (op2'  * w))
end

# Operator + matrix.
(+)(M :: KindOfMatrix, op :: LinearOperator) = LinearOperator(M) + op
(+)(op :: LinearOperator, M :: KindOfMatrix) = op + LinearOperator(M)

# Operator .+ scalar.
(.+)(op :: LinearOperator, x :: Number) = op + x * opOnes(op.nrow, op.ncol)
(.+)(x :: Number, op :: LinearOperator) = x * opOnes(op.nrow, op.ncol) + op

# Operator - operator
(-)(op1 :: LinearOperator, op2 :: LinearOperator) = op1 + (-op2)

# Operator - matrix.
(-)(M :: KindOfMatrix, op :: LinearOperator) = LinearOperator(M) - op
(-)(op :: LinearOperator, M :: KindOfMatrix) = op - LinearOperator(M)

# Operator - scalar.
(.-)(op :: LinearOperator, x :: Number) = op .+ (-x)
(.-)(x :: Number, op :: LinearOperator) = x .+ (-op)


# Utility functions.

@doc "Cheap check that the operator and its conjugate transposed are related." ->
function check_ctranspose(op :: LinearOperator)
  (m, n) = size(op);
  x = rand(n);
  y = rand(m);
  yAx = dot(y, op * x);
  xAty = dot(x, op' * y);
  ε = eps(Float64);
  return abs(yAx - conj(xAty)) < (abs(yAx) + ε) * ε^(1/3);
end

check_ctranspose(M :: KindOfMatrix) = check_ctranspose(LinearOperator(M))

@doc "Cheap check that the operator is Hermitian." ->
function check_hermitian(op :: LinearOperator)
  m, n = size(op);
  v = rand(n);
  w = op * v;
  s = dot(w, w);  # = (Av)'(Av) = v' A' A v.
  y = op * w;
  t = dot(v, y);  # = v' A A v.
  ε = eps(Float64);
  return abs(s - t) < (abs(s) + ε) * ε^(1/3);
end

check_hermitian(M :: KindOfMatrix) = check_hermitian(LinearOperator(M))

@doc "Cheap check that the operator is positive (semi-)definite." ->
function check_positive_definite(op :: LinearOperator; semi=false)
  m, n = size(op);
  v = rand(n);
  w = op * v;
  vw = dot(v, w);
  ε = eps(Float64);
  if imag(vw) > sqrt(ε) * abs(vw)
    return false
  end
  vw = real(vw);
  return semi ? (vw ≥ 0) : (vw > 0)
end

check_positive_definite(M :: KindOfMatrix) = check_positive_definite(LinearOperator(M))

# Special linear operators.

@doc "Identity operator of order `n` and of data type `dtype`." ->
opEye(n :: Int; dtype=Float64) = LinearOperator(n, n, dtype, true, true,
                                                v -> v, u -> u, w -> w)

@doc "Operator of all ones of size `nrow`-by-`ncol` and of data type `dtype`." ->
opOnes(nrow, ncol; dtype=Float64) = LinearOperator(nrow, ncol, dtype,
                                                   nrow == ncol, nrow == ncol,
                                                   v -> sum(v) * ones(nrow),
                                                   u -> sum(u) * ones(ncol),
                                                   w -> sum(w) * ones(ncol))

@doc "Zero operator of size `nrow`-by-`ncol` and of data type `dtype`." ->
opZeros(nrow, ncol; dtype=Float64) = LinearOperator(nrow, ncol, dtype,
                                                   nrow == ncol, nrow == ncol,
                                                   v -> zeros(nrow),
                                                   u -> zeros(ncol),
                                                   w -> zeros(ncol))

@doc "Diagonal operator with the vector `d` on its main diagonal." ->
opDiagonal(d :: Vector) = LinearOperator(length(d), length(d), typeof(d[1]),
                                         true, !(typeof(d[1]) <: Complex),
                                         v -> v .* d,
                                         u -> u .* d,
                                         w -> w .* conj(d))

@doc """Rectangular diagonal operator of size `nrow`-by-`ncol`
with the vector `d` on its main diagonal.""" ->
function opDiagonal(nrow :: Int, ncol :: Int, d :: Vector)
  if nrow == ncol
    return opDiagonal(d)
  end
  if nrow > ncol
    D = LinearOperator(nrow, ncol, typeof(d[1]), false, false,
                       v -> [v .* d ; zeros(nrow-ncol)],
                       u -> u[1:ncol] .* d,
                       w -> w[1:ncol] .* conj(d));
  else
    D = LinearOperator(nrow, ncol, typeof(d[1]), false, false,
                       v -> v[1:nrow] .* d,
                       u -> [u .* d ; zeros(ncol-nrow)],
                       w -> [w .* conj(d) ; zeros(ncol-nrow)]);
  end
  return D
end


import Base.hcat
function hcat(A :: LinearOperator, B :: LinearOperator)
  A.nrow != B.nrow && error("hcat: inconsistent row sizes")

  nrow  = A.nrow
  ncol  = A.ncol + B.ncol
  dtype = promote_type(A.dtype, B.dtype)

  prod(v)   =  A * v[1:A.ncol] + B * v[A.ncol+1:end]
  tprod(v)  =  [A.' * v; B.' * v;]
  ctprod(v) =  [A' * v; B' * v;]

  return LinearOperator(nrow, ncol, A.dtype, false, false, prod, tprod, ctprod)
end

function hcat(ops :: LinearOperator...)
  op = ops[1]
  for i = 2:length(ops)
    op = [op ops[i]];
  end
  return op
end

import Base.vcat

function vcat(A::LinearOperator, B::LinearOperator)
  A.ncol != B.ncol && error("vcat: inconsistent column sizes")

  nrow  = A.nrow + B.nrow
  ncol  = A.ncol
  dtype = promote_type(A.dtype, B.dtype)

  prod(v)   =  [A * v; B * v;]
  tprod(v)  =  A.' * v +  B.' * v
  ctprod(v) =  A' * v[1:A.nrow] + B' * v[A.nrow+1:end]

  return LinearOperator(nrow, ncol, dtype, false, false, prod, tprod, ctprod)
end

function vcat(ops :: LinearOperator...)
  op = ops[1]
  for i = 2:length(ops)
    op = [op; ops[i]];
  end
  return op
end


@doc """Inverse of a matrix as a linear operator using `\`.
Useful for triangular matrices. Note that each application of this
operator applies `\`.""" ->
opInverse(M :: KindOfMatrix; symmetric=false, hermitian=false) =
  LinearOperator(size(M,2), size(M,1), typeof(M[1,1]), symmetric, hermitian,
                 v -> M \ v, u -> M.' \ u, w -> M' \ w);

@doc """Inverse of a positive definite matrix as a linear operator
using its Cholesky factorization. The factorization is computed only once.
The optional `check` argument will perform cheap hermicity and definiteness
checks.""" ->
function opCholesky(M :: KindOfMatrix; check=false)
  (m, n) = size(M)
  if m != n
    error("Shape mismatch")
  end
  if check
    if !check_hermitian(M)
      error("Matrix is not Hermitian")
    end
    # Cheap positive definiteness check.
    if !check_positive_definite(M)
      error("Matrix is not positive definite")
    end
  end
  L = issparse(M) ? cholfact(M) : chol(M, :L);
  return LinearOperator(m, m, typeof(M[1,1]),
                        !(typeof(M[1,1]) <: Complex), true,
                        v -> L' \ (L \ v),
                        u -> L.' \ (conj(L \ conj(u))),
                        w -> L' \ (L \ w))
  # Todo: use iterative refinement.
end

@doc """Apply a Householder transformation defined by the vector `h`.
The result is `x -> (I - 2 h h') x`.""" ->
opHouseholder(h :: Vector) = LinearOperator(length(h), length(h), typeof(h[1]),
                                            !(typeof(h[1]) <: Complex), true,
                                            v -> (v - 2 * dot(h, v) * h),
                                            Nullable{Function}(),  # Will be inferred.
                                            w -> (w - 2 * dot(h, w) * h))



@doc "A symmetric/hermitian operator based on the diagonal and lower triangle." ->
function opHermitian(d :: Vector, T :: KindOfMatrix)
  L = tril(T, -1);
  return LinearOperator(length(d), length(d), typeof(d[1]),
                        !(typeof(d[1]) <: Complex), true,
                        v -> (d .* v + L * v + (v' * L)')[:],
                        Nullable{Function}(),
                        Nullable{Function}());
end


@doc "A symmetric/hermitian operator based on a matrix." ->
function opHermitian(T :: KindOfMatrix)
  d = diag(T);
  return opHermitian(d, T);
end

end  # module

