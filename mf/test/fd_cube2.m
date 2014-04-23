% Seven-point stencil on the unit cube, variable-coefficient Poisson.

function fd_cube2(n,occ,symm)

  % set default parameters
  if nargin < 1 || isempty(n)
    n = 32;
  end
  if nargin < 2 || isempty(occ)
    occ = 4;
  end
  if nargin < 3 || isempty(symm)
    symm = 'p';
  end

  % initialize
  [x1,x2,x3] = ndgrid((1:n-1)/n);
  x = [x1(:) x2(:) x3(:)]';
  N = size(x,2);
  clear x1 x2 x3

  % set up sparse matrix
  h = 1/n;
  idx = zeros(n+1,n+1,n+1);
  idx(2:n,2:n,2:n) = reshape(1:N,n-1,n-1,n-1);

  % set up potentials
  a = rand(n,n,n);
  a(a > 0.5) = 100;
  a(a < 0.5) = 0.01;
  V = zeros(n+1,n+1,n+1);
  V(2:n,2:n,2:n) = randn(n-1,n-1,n-1);

  % initialize indices
  mid = 2:n;
  lft = 1:n-1;
  rgt = 3:n+1;
  slft = 1:n-1;
  srgt = 2:n;

  % interactions with left node
  Il = idx(mid,mid,mid);
  Jl = idx(lft,mid,mid);
  Sl = -0.25/h^2*(a(slft,slft,slft) + a(slft,slft,srgt) + ...
                  a(slft,srgt,slft) + a(slft,srgt,srgt));

  % interactions with right node
  Ir = idx(mid,mid,mid);
  Jr = idx(rgt,mid,mid);
  Sr = -0.25/h^2*(a(srgt,slft,slft) + a(srgt,slft,srgt) + ...
                  a(srgt,srgt,slft) + a(srgt,srgt,srgt));

  % interactions with bottom node
  Id = idx(mid,mid,mid);
  Jd = idx(mid,lft,mid);
  Sd = -0.25/h^2*(a(slft,slft,slft) + a(slft,slft,srgt) + ...
                  a(srgt,slft,slft) + a(srgt,slft,srgt));

  % interactions with top node
  Iu = idx(mid,mid,mid);
  Ju = idx(mid,rgt,mid);
  Su = -0.25/h^2*(a(slft,srgt,slft) + a(slft,srgt,srgt) + ...
                  a(srgt,srgt,slft) + a(srgt,srgt,srgt));

  % interactions with back node
  Ib = idx(mid,mid,mid);
  Jb = idx(mid,mid,lft);
  Sb = -0.25/h^2*(a(slft,slft,slft) + a(slft,srgt,slft) + ...
                  a(srgt,slft,slft) + a(srgt,srgt,slft));

  % interactions with front node
  If = idx(mid,mid,mid);
  Jf = idx(mid,mid,rgt);
  Sf = -0.25/h^2*(a(slft,slft,srgt) + a(slft,srgt,srgt) + ...
                  a(srgt,slft,srgt) + a(srgt,srgt,srgt));

  % interactions with self
  Im = idx(mid,mid,mid);
  Jm = idx(mid,mid,mid);
  Sm = -(Sl + Sr + Sd + Su + Sb + Sf) + V(mid,mid,mid);

  % form sparse matrix
  I = [Il(:); Ir(:); Id(:); Iu(:); Ib(:); If(:); Im(:)];
  J = [Jl(:); Jr(:); Jd(:); Ju(:); Jb(:); Jf(:); Jm(:)];
  S = [Sl(:); Sr(:); Sd(:); Su(:); Sb(:); Sf(:); Sm(:)];
  idx = find(I > 0 & J > 0);
  I = I(idx);
  J = J(idx);
  S = S(idx);
  A = sparse(I,J,S,N,N);
  clear idx Il Jl Sl Ir Jr Sr Id Jd Sd Iu Ju Su Ib Jb Sb If Jf Sf Im Jm Sm I J S

  % factor matrix
  opts = struct('symm',symm,'verb',1);
  F = mf3(A,n,occ,opts);
  w = whos('F');
  fprintf([repmat('-',1,80) '\n'])
  fprintf('mem: %6.2f (MB)\n', w.bytes/1e6)

  % test accuracy using randomized power method
  X = rand(N,1);
  X = X/norm(X);

  % NORM(A - F)/NORM(A)
  tic
  mf_mv(F,X);
  t = toc;
  [e,niter] = snorm(N,@(x)(A*x - mf_mv(F,x)),[],[],1);
  e = e/snorm(N,@(x)(A*x),[],[],1);
  fprintf('mv: %10.4e / %4d / %10.4e (s)\n',e,niter,t)

  % NORM(INV(A) - INV(F))/NORM(INV(A)) <= NORM(I - A*INV(F))
  tic
  Y = mf_sv(F,X);
  t = toc;
  [e,niter] = snorm(N,@(x)(x - A*mf_sv(F,x)),[],[],1);
  fprintf('sv: %10.4e / %4d / %10.4e (s)\n',e,niter,t)

  % run CG
  [~,~,~,iter] = pcg(@(x)(A*x),X,1e-12,128);

  % run PCG
  tic
  [Z,~,~,piter] = pcg(@(x)(A*x),X,1e-12,32,@(x)(mf_sv(F,x)));
  t = toc;
  e1 = norm(Z - Y)/norm(Z);
  e2 = norm(X - A*Z)/norm(X);
  fprintf('cg: %10.4e / %10.4e / %4d (%4d) / %10.4e (s)\n',e1,e2, ...
          piter,iter,t)
end