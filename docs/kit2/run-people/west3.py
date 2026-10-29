# Coale–Demeny Model West life tables (port of demogR cdmltw, Coale, Demeny
# and Vaughan 1983 with Oeppen 2018 corrections). Prints the level-3 hazards
# used in sim/src/life.rs (MU_F, MU_M) and writes west3.json.

import numpy as np, json, sys
def cdw(sex):
    if sex=='F':
        eten=np.array([21.40549,25.32904,28.86351,32.07396,35.01032,37.71173,40.20992,42.53003,44.69388,46.71830,48.61905,50.40814,52.08187,53.35198,54.56192,55.83317,57.16274,58.54485,59.97243,61.43625,62.99381,65.49800,68.71056,72.92253,78.62273])
        ax=[.53774,.39368,.10927,.08548,.10979,.1358,.15134,.17032,.18464,.1939,.20138,.2535,.31002,.43445,.53481,.69394,.84589]
        bx=[-.008044,-.006162,-.001686,-.00132,-.001672,-.002051,-.002276,-.002556,-.002745,-.002828,-.002831,-.003487,-.004118,-.005646,-.00646,-.007713,-.008239]
        a1x=[5.8992,7.4576,6.2018,5.9627,5.9335,5.9271,5.8145,5.6578,5.3632,4.96,4.5275,4.4244,4.3131,4.3439,4.2229,4.1838,4.1294]
        b1x=[-.05406,-.08834,-.0741,-.07181,-.06812,-.06577,-.06262,-.05875,-.05232,-.0438,-.03436,-.03004,-.02554,-.02295,-.01773,-.01376,-.00978]
        m105c=0.613
    else:
        eten=np.array([21.86761,25.44740,28.67272,31.60223,34.28159,36.74631,39.02583,41.14277,43.11689,44.96458,46.69839,48.33115,49.85796,51.01729,52.12115,53.28135,54.49441,55.75599,57.05851,58.39447,59.81638,62.10227,65.03413,68.87841,74.08120])
        ax=[0.63726,0.40548,0.10393,0.07435,0.09880,0.14009,0.15785,0.18260,0.21175,0.25049,0.27894,0.33729,0.38425,0.48968,0.59565,0.73085,0.89876]
        bx=[-0.009958,-0.006653,-0.001662,-0.001183,-0.001539,-0.002183,-0.002479,-0.002875,-0.003312,-0.003864,-0.004158,-0.004856,-0.005190,-0.006300,-0.007101,-0.007911,-0.008695]
        a1x=[5.8061,7.1062,5.4472,5.0654,4.8700,5.0677,5.2660,5.3438,5.2792,5.0415,4.6666,4.4506,4.2202,4.1851,4.1249,4.1051,4.1133]
        b1x=[-0.05338,-0.08559,-0.06295,-0.05817,-0.05070,-0.05156,-0.05471,-0.05511,-0.05229,-0.04573,-0.03637,-0.02961,-0.02256,-0.01891,-0.01491,-0.01161,-0.00895]
        m105c=0.551
    ax,bx,a1x,b1x=map(np.array,(ax,bx,a1x,b1x))
    nqxa=np.outer(np.ones_like(eten),ax)+np.outer(eten,bx)
    nqxl=1e-4*10**(np.outer(np.ones_like(eten),a1x)+np.outer(eten,b1x))
    slope=np.outer(np.full_like(eten,1/np.log(10)),bx/b1x)/nqxl
    nqx=(nqxa+nqxl)/2
    nqx=np.where((nqxa<=nqxl)&(slope<1),nqxa,nqx)
    nqx=np.where((nqxa<=nqxl)&(slope>=1),nqxl,nqx)
    u=np.log(1-nqx); uu=np.cumsum(u,axis=1)
    lx=np.hstack([np.ones((25,1)),np.exp(uu[:,:16])])
    nL75=5*lx[:,16]*(1-nqx[:,16])+0.5*5*lx[:,16]*nqx[:,16]
    l80=lx[:,16]*(1-nqx[:,16]); m77=lx[:,16]*nqx[:,16]/nL75
    m105=m105c+1.75*nqx[:,16]; kappa=np.log(m105/m77)/27.5; m80=m77*np.exp(kappa*2.5)
    xl=np.arange(0,41.0001,0.2)
    llx=l80[:,None]*np.exp((-m80/kappa)[:,None]*np.exp(np.outer(kappa,xl))-(-m80/kappa)[:,None])
    w=np.array([.5]+[1]*24+[.5])/5
    nL80=llx[:,0:26]@w; nL85=llx[:,25:51]@w; nL90=llx[:,50:76]@w; nL95=llx[:,75:101]@w
    T100=llx[:,100:201]@(np.array([.5]+[1]*99+[.5])/5)
    lxf=np.hstack([lx[:,:17],llx[:,[0,25,50,75]]])
    qq=(llx[:,[0,25,50]]-llx[:,[25,50,75]])/llx[:,[0,25,50]]
    nqxf=np.hstack([nqx[:,:17],qq,np.ones((25,1))])
    return lxf,nqxf,T100,(nL80,nL85,nL90,nL95)
ages=[0,1]+list(range(5,100,5)); width=[1,4]+[5]*18+[None]
out={}
for s in 'FM':
    lx,qx,T100,_=cdw(s)
    L=lx[2]; Q=qx[2]  # level 3
    # constant hazard per interval: mu = -ln(1-q)/n ; last open interval: mu = l95/T95
    mu=[]
    for i in range(20):
        mu.append(-np.log(1-Q[i])/width[i])
    # open interval 95+: use T100+nL95 approx -> mean remaining ~ (T95)/l95
    _,_,T100,(a,b,c,d)=cdw(s); T95=d[2]+T100[2]
    mu.append(L[20]/T95)
    out[s]=[float(x) for x in mu]
    # e0 from constant hazards
    l=1.0; e=0.0
    for i in range(21):
        m=mu[i]; n=width[i]
        if n is None: e+=l/m; break
        e+=l*(1-np.exp(-m*n))/m; l*=np.exp(-m*n)
    print(s,'e0=%.2f'%e,'l15=%.3f'%L[5] if False else '', 'q0=%.4f'%Q[0])
json.dump(out,open('west3.json','w'),indent=1)
print(json.dumps({k:[round(x,5) for x in v] for k,v in out.items()}))
