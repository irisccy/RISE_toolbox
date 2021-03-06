function [Resids,Fits]=residuals(kdata,B)

Y=kdata.Y;

X=kdata.X;

nregs=size(B,3);

for ii=1:nregs
    
    Fit_i=B(:,:,ii)*X;
    
    tmpR=Y - Fit_i;
    
    if ii==1
        
        Fits = Fit_i(:,:,ones(1,nregs));
        
        Resids = tmpR(:,:,ones(1,nregs));
        
    else
        
        Fits(:,:,ii)=Fit_i;
        
        Resids(:,:,ii)=tmpR;
        
    end


end