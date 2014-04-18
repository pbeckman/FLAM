% Second-kind integral equation on the unit sphere, Laplace double-layer.

function ie_sphere(n,nquad,occ,p,rank_or_tol,store)

  % set default parameters
  if nargin < 1 || isempty(n)
    n = 20480;
  end
  if nargin < 2 || isempty(nquad)
    nquad = 4;
  end
  if nargin < 3 || isempty(occ)
    occ = 1024;
  end
  if nargin < 4 || isempty(p)
    p = 512;
  end
  if nargin < 5 || isempty(rank_or_tol)
    rank_or_tol = 1e-6;
  end
  if nargin < 6 || isempty(store)
    store = 'a';
  end

  % initialize
  [V,F] = trisphere_subdiv(n);
  [x,nu,area] = tri3geom(V,F);
  N = size(x,2);
  proxy = randn(3,p);
  proxy = 1.5*bsxfun(@rdivide,proxy,sqrt(sum(proxy.^2)));

  % compute quadrature corrections
  tic
  if nquad > 0

    % generate reference transformations for each triangle
    [trans,rot,V2,V3] = tri3transrot(V,F);

    % initialize quadrature on the unit square
    [xq,wq] = glegquad(nquad,0,1);
    [xq,yq] = meshgrid(xq);
    wq = wq*wq';
    xq = xq(:);
    yq = yq(:);
    wq = wq(:);

    % find neighbors of each triangle
    nlvl = 0;
    l = 2;
    h = sqrt(8*pi/N);
    while l > h
      nlvl = nlvl + 1;
      l = 0.5*l;
    end
    nlvl = max(1,nlvl);
    T = hypoct(x,0,nlvl);

    % initialize storage
    nz = 0;
    for i = T.lvp(nlvl)+1:T.lvp(nlvl+1)
      node = T.nodes(i);
      nslf = length(node.xi);
      nnbr = length([T.nodes(node.nbor).xi]);
      nz = nz + nslf*(nslf + nnbr - 1);
    end
    I = zeros(nz,1);
    J = zeros(nz,1);
    S = zeros(nz,1);

    % compute near-field quadratures
    nz = 0;
    for i = T.lvp(nlvl)+1:T.lvp(nlvl+1)
      node = T.nodes(i);
      nbor = [T.nodes(node.nbor).xi];
      for j = node.xi
        [X,Y,W] = qmap_sqtri2(xq,yq,wq,V2(j),V3(:,j));
        for k = [node.xi nbor]
          if j == k
            continue
          end
          trg = rot(:,:,j)*(x(:,k) + trans(:,j));
          q = W'*quadfun(X,Y,trg);
          nz = nz + 1;
          I(nz) = k;
          J(nz) = j;
          S(nz) = q;
        end
      end
    end
  else
    I = [];
    J = [];
    S = [];
  end
  S = sparse(I,J,S,N,N);
  P = zeros(N,1);
  t = toc;
  w = whos('S');
  fprintf('quad: %10.4e (s) / %6.2f (MB)\n',t,w.bytes/1e6)
  clear V F trans rot V2 V3 T I J

  % compress matrix
  opts = struct('store',store,'verb',1);
  F = ifmm(@Afun,x,x,occ,rank_or_tol,@pxyfun,opts);
  w = whos('F');
  fprintf([repmat('-',1,80) '\n'])
  fprintf('mem: %6.2f (MB)\n',w.bytes/1e6)

  % test matrix apply accuracy
  X = rand(N,1);
  X = X/norm(X);
  tic
  ifmm_mv(F,X,@Afun,'n');
  t = toc;
  X = rand(N,16);
  X = X/norm(X);
  r = randperm(N);
  r = r(1:min(N,128));
  A = Afun(r,1:N);
  Y = ifmm_mv(F,X,@Afun,'n');
  Z = A*X;
  e = norm(Z - Y(r,:))/norm(Z);
  fprintf('mv:  %10.4e / %10.4e (s)\n',e,t)

  % test matrix adjoint apply accuracy
  X = rand(N,1);
  X = X/norm(X);
  tic
  ifmm_mv(F,X,@Afun,'c');
  t = toc;
  X = rand(N,16);
  X = X/norm(X);
  r = randperm(N);
  r = r(1:min(N,128));
  A = Afun(1:N,r);
  Y = ifmm_mv(F,X,@Afun,'c');
  Z = A'*X;
  e = norm(Z - Y(r,:))/norm(Z);
  fprintf('mva: %10.4e / %10.4e (s)\n',e,t)

  % generate field due to exterior sources
  m = 16;
  src = randn(3,m);
  src = 2*bsxfun(@rdivide,src,sqrt(sum(src.^2)));
  q = rand(m,1);
  B = Kfun(x,src,'s')*q;

  % solve for surface density
  tic
  [X,~,~,iter] = gmres(@(x)(ifmm_mv(F,x,@Afun)),B,[],1e-6,32);
  t = toc;
  r = randperm(N);
  r = r(1:min(N,128));
  A = Afun(r,1:N);
  e = norm(B(r) - A*X)/norm(B(r));
  fprintf('gmres: %10.4e / %4d / %10.4e (s)\n',e,iter(2),t)

  % evaluate field at interior targets
  trg = randn(3,m);
  trg = 0.5*bsxfun(@rdivide,trg,sqrt(sum(trg.^2)));
  Y = bsxfun(@times,Kfun(trg,x,'d',nu),area)*X;

  % compare against exact field
  Z = Kfun(trg,src,'s')*q;
  e = norm(Z - Y)/norm(Z);
  fprintf('pde: %10.4e\n',e)

  % quadrature function
  function f = quadfun(x,y,trg)
    dx = trg(1) - x;
    dy = trg(2) - y;
    dz = trg(3);
    dr = sqrt(dx.^2 + dy.^2 + dz.^2);
    f = 1/(4*pi).*dz./dr.^3;
  end

  % kernel function
  function K = Kfun(x,y,lp,nu)
    if nargin < 4
      nu = [];
    end
    dx = bsxfun(@minus,x(1,:)',y(1,:));
    dy = bsxfun(@minus,x(2,:)',y(2,:));
    dz = bsxfun(@minus,x(3,:)',y(3,:));
    dr = sqrt(dx.^2 + dy.^2 + dz.^2);
    if strcmp(lp,'s')
      K = 1/(4*pi)./dr;
    elseif strcmp(lp,'d')
      rdotn = bsxfun(@times,dx,nu(1,:)) + bsxfun(@times,dy,nu(2,:)) + ...
              bsxfun(@times,dz,nu(3,:));
      K = 1/(4*pi).*rdotn./dr.^3;
    end
    K(dr == 0) = 0;
  end

  % matrix entries
  function A = Afun(i,j)
    if isempty(i) || isempty(j)
      A = zeros(length(i),length(j));
      return
    end
    [I,J] = ndgrid(i,j);
    A = bsxfun(@times,Kfun(x(:,i),x(:,j),'d',nu(:,j)),area(j));
    M = spget(i,j);
    idx = M ~= 0;
    A(idx) = M(idx);
    A(I == J) = -0.5;
  end

  % proxy function
  function K = pxyfun(rc,rx,cx,slf,nbr,l,ctr)
    pxy = bsxfun(@plus,proxy*l,ctr');
    if strcmp(rc,'r')
      K = Kfun(rx(:,slf),pxy,'s');
    elseif strcmp(rc,'c')
      K = bsxfun(@times,Kfun(pxy,cx(:,slf),'d',nu(:,slf)),area(slf));
    end
  end

  % sparse matrix access
  function A = spget(I_,J_)
    m_ = length(I_);
    n_ = length(J_);
    [I_sort,E] = sort(I_);
    P(I_sort) = E;
    A = zeros(m_,n_);
    [I_,J_,S_] = find(S(:,J_));
    idx = ismembc(I_,I_sort);
    I_ = I_(idx);
    J_ = J_(idx);
    S_ = S_(idx);
    A(P(I_) + (J_ - 1)*m_) = S_;
  end
end