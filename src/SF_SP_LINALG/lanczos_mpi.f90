!---------------------------------------------------------------------
!Purpose: use plain lanczos to get the groundstate energy
!---------------------------------------------------------------------
subroutine mpi_lanczos_eigh_d(MpiComm,MatVec,Ndim,Nitermax,Egs,Vect,iverbose,threshold,ncheck)
  integer                              :: MpiComm
  interface 
     subroutine MatVec(Nloc,vin,vout)
       integer :: Nloc
       real(8) :: vin(Nloc)
       real(8) :: vout(Nloc)
     end subroutine MatVec
  end interface
  integer                              :: Ndim
  integer                              :: Nitermax
  integer                              :: Nloc
  real(8)                              :: egs
  real(8),dimension(:)                 :: vect !Nloc
  real(8),optional                     :: threshold
  integer,optional                     :: ncheck
  logical,optional                     :: iverbose
  !
  real(8),dimension(size(vect))        :: vin,vout
  integer                              :: iter,nlanc
  real(8),dimension(Nitermax+1)        :: alanc,blanc
  real(8),dimension(Nitermax,Nitermax) :: Z
  real(8),dimension(Nitermax)          :: diag,subdiag,esave
  real(8)                              :: a_,b_,norm,diff,norm_tmp
  integer                              :: i,ierr
  !
  logical                              :: mpi_master
  !
  if(MpiComm /= MPI_COMM_NULL)then
     !
     mpi_master=get_master_MPI(MpiComm)
     !
     Nloc = size(vect)
     !
     if(present(iverbose))verb=iverbose
     if(present(threshold))threshold_=threshold
     if(present(ncheck))ncheck_=ncheck
     !
     norm_tmp=dot_product(vect,vect)
     call AllReduce_MPI(MpiComm,norm_tmp,norm)
     !
     if(norm==0d0)then
        call random_seed(size=nrandom)
        if(allocated(seed_random))deallocate(seed_random)
        allocate(seed_random(nrandom))
        seed_random=1234567
        call random_seed(put=seed_random)
        call random_number(vect)
        norm_tmp=dot_product(vect,vect)
        call AllReduce_MPI(MpiComm,norm_tmp,norm)
        vect=vect/sqrt(norm)
        if(verb.AND.mpi_master)write(*,*)"MPI_LANCZOS_EIGH: random initial vector generated:"
     endif
     !
     !============= LANCZOS LOOP =====================
     !
     Vin  = Vect                   !save input vector for Eigenvector calculation:
     Vout = 0d0
     alanc= 0d0
     blanc= 0d0
     nlanc= 0
     !
     lanc_loop: do iter=1,Nitermax
        !

        !
        call mpi_lanczos_iteration_d(MpiComm,MatVec,iter,vin,vout,a_,b_)
        if(abs(b_)<threshold_)exit lanc_loop
        !
        nlanc=nlanc+1
        !
        alanc(iter) = a_ ; blanc(iter+1) = b_
        !
        diag    = 0d0
        subdiag = 0.d0
        Z       = eye(Nlanc)
        diag(1:Nlanc)    = alanc(1:Nlanc)
        subdiag(2:Nlanc) = blanc(2:Nlanc)
        call tql2(Nlanc,diag,subdiag,Z,ierr)
        !
        if(verb.AND.mpi_master)write(*,*)"Lanczos iteration, E_lowest    = ",iter,diag(1)
        !
        if(nlanc >= Ncheck_)then
           esave(nlanc-(Ncheck_-1))=diag(1)
           if(nlanc >= (Ncheck_+1))then
              diff=esave(Nlanc-(Ncheck_-1))-esave(Nlanc-(Ncheck_-1)-1)
              if(verb.AND.mpi_master)write(*,*)'test deltaE = ',diff
              if(abs(diff).le.threshold_)exit lanc_loop
           endif
        endif
        if(verb.AND.mpi_master)write(*,*)""
        !
     enddo lanc_loop
     if(verb.AND.mpi_master)write(*,*)""
     if(verb.AND.mpi_master)write(*,*)""
     if(verb.AND.mpi_master)write(*,*)'Lanczos deltaE = ',diff
     if(nlanc==nitermax)print*,"LANCZOS_SIMPLE: reach Nitermax"
     !
     !============== END LANCZOS LOOP ======================
     !
     diag    = 0d0
     subdiag = 0.d0
     Z       = eye(Nlanc)
     diag(1:Nlanc)    = alanc(1:Nlanc)
     subdiag(2:Nlanc) = blanc(2:Nlanc)
     call tql2(Nlanc,diag,subdiag,Z,ierr)
     !
     !Get the Eigenvalues:
     egs = diag(1)
     !
     !Get the Eigenvector:
     Vin = Vect
     vout= 0d0
     vect= 0d0
     do iter=1,nlanc
        call mpi_lanczos_iteration_d(MpiComm,MatVec,iter,vin,vout,alanc(iter),blanc(iter))
        vect = vect + vin*Z(iter,1)
     end do
     norm_tmp = dot_product(vect,vect)
     call Allreduce_MPI(MpiComm,norm_tmp,norm)
     vect=vect/sqrt(norm)
  endif
end subroutine mpi_lanczos_eigh_d

subroutine mpi_lanczos_eigh_c(MpiComm,MatVec,Ndim,Nitermax,Egs,Vect,iverbose,threshold,ncheck)
  integer                              :: MpiComm
  interface 
     subroutine MatVec(Nloc,vin,vout)
       integer    :: Nloc
       complex(8) :: vin(Nloc)
       complex(8) :: vout(Nloc)
     end subroutine MatVec
  end interface
  integer                              :: Ndim
  integer                              :: Nitermax
  integer                              :: Nloc
  real(8)                              :: egs
  complex(8),dimension(:)              :: vect
  real(8),optional                     :: threshold
  integer,optional                     :: ncheck
  logical,optional                     :: iverbose
  !
  complex(8),dimension(size(vect))     :: vin,vout
  integer                              :: iter,nlanc
  real(8),dimension(Nitermax+1)        :: alanc,blanc
  real(8),dimension(Nitermax,Nitermax) :: Z
  real(8),dimension(Nitermax)          :: diag,subdiag,esave
  real(8)                              :: a_,b_,norm,diff,ran(2),norm_tmp
  integer                              :: i,ierr
  !
  logical                              :: mpi_master
  !
  if(MpiComm /= MPI_COMM_NULL)then
     !
     mpi_master=get_master_MPI(MpiComm)
     !
     Nloc = size(vect)
     !
     if(present(iverbose))verb=iverbose
     if(present(threshold))threshold_=threshold
     if(present(ncheck))ncheck_=ncheck
     !
     norm_tmp=dot_product(vect,vect)
     call AllReduce_Mpi(MpiComm,norm_tmp,norm)
     if(norm==0d0)then
        call random_seed(size=nrandom)
        if(allocated(seed_random))deallocate(seed_random)
        allocate(seed_random(nrandom))
        seed_random=1234567
        call random_seed(put=seed_random)
        do i=1,Nloc
           call random_number(ran)
           vect(i)=dcmplx(ran(1),ran(2))
        enddo
        norm_tmp=dot_product(vect,vect)
        call AllReduce_Mpi(MpiComm,norm_tmp,norm)
        vect=vect/sqrt(norm)
        if(verb.AND.mpi_master)write(*,*)"MPI_LANCZOS_EIGH: random initial vector generated:"
     endif
     !
     !============= LANCZOS LOOP =====================
     !
     vin = vect
     vout= zero
     alanc=0d0
     blanc=0d0
     nlanc=0
     !
     lanc_loop: do iter=1,Nitermax
        !
        if(verb.AND.mpi_master)write(*,*)"Lanczos iteration:",iter
        !
        call mpi_lanczos_iteration_c(MpiComm,MatVec,iter,vin,vout,a_,b_)
        if(abs(b_)<threshold_)exit lanc_loop
        !
        nlanc=nlanc+1
        !
        alanc(iter) = a_ ; blanc(iter+1) = b_
        !
        diag    = 0d0
        subdiag = 0d0
        Z       = eye(Nlanc)
        diag(1:Nlanc)    = alanc(1:Nlanc)
        subdiag(2:Nlanc) = blanc(2:Nlanc)
        call tql2(Nlanc,diag,subdiag,Z,ierr)
        !
        if(verb.AND.mpi_master)write(*,*)"E_lowest    = ",diag(1)
        !
        if(nlanc >= Ncheck_)then
           esave(nlanc-(Ncheck_-1))=diag(1)
           if(nlanc >= (Ncheck_+1))then
              diff=esave(Nlanc-(Ncheck_-1))-esave(Nlanc-(Ncheck_-1)-1)
              if(verb.AND.mpi_master)write(*,*)'test deltaE = ',diff
              if(abs(diff).le.threshold_)exit lanc_loop
           endif
        endif
        if(verb.AND.mpi_master)write(*,*)
        !
     enddo lanc_loop
     if(verb.AND.mpi_master)write(*,*)
     if(verb.AND.mpi_master)write(*,*)
     if(verb.AND.mpi_master)write(*,*)'Lanczos deltaE = ',diff
     if(nlanc==nitermax)print*,"LANCZOS_SIMPLE: reach Nitermax"
     !
     !============== END LANCZOS LOOP ======================
     !
     diag    = 0d0
     subdiag = 0.d0
     Z       = eye(Nlanc)
     diag(1:Nlanc)    = alanc(1:Nlanc)
     subdiag(2:Nlanc) = blanc(2:Nlanc)
     call tql2(Nlanc,diag,subdiag,Z,ierr)
     !
     !Get the Eigenvalues:
     egs = diag(1)
     !
     !Get the Eigenvector:
     vin = vect
     vout= zero
     do iter=1,nlanc
        call mpi_lanczos_iteration_c(MpiComm,MatVec,iter,vin,vout,alanc(iter),blanc(iter))
        vect = vect + vin*Z(iter,1)
     end do
     norm_tmp=sqrt(dot_product(vect,vect))
     call AllReduce_MPI(MpiComm,norm_tmp,norm)
     vect=vect/sqrt(norm)
  endif
end subroutine mpi_lanczos_eigh_c






!---------------------------------------------------------------------
!Purpose: use simple Lanczos to tri-diagonalize a matrix H (defined 
! in the H*v function).
!---------------------------------------------------------------------
subroutine mpi_lanczos_tridiag_d(MpiComm,MatVec,vin,alanc,blanc,threshold)
  integer                                      :: MpiComm
  interface
     subroutine MatVec(Nloc,vin,vout)
       integer                 :: Nloc
       real(8),dimension(Nloc) :: vin
       real(8),dimension(Nloc) :: vout
     end subroutine MatVec
  end interface
  real(8),dimension(:),intent(inout)           :: vin !Nloc
  real(8),dimension(size(vin))                 :: vout,vtmp
  real(8),dimension(:),intent(inout)           :: alanc
  real(8),dimension(size(alanc)),intent(inout) :: blanc
  integer                                      :: Nitermax,Nloc,i
  integer                                      :: iter
  real(8)                                      :: a_,b_
  real(8),optional                             :: threshold
  !
  logical                                      :: mpi_master
  !
  if(MpiComm /= MPI_COMM_NULL)then
     !
     mpi_master=get_master_MPI(MpiComm)
     !
     Nloc = size(vin)
     !
     if(present(threshold))threshold_=threshold
     !
     vtmp = vin
     Nitermax = size(alanc)
     a_=0d0
     b_=0d0
     vout=0d0
     do iter=1,Nitermax
        call mpi_lanczos_iteration_d(MpiComm,MatVec,iter,vtmp,vout,a_,b_)
        alanc(iter)=a_
        if(abs(b_)<threshold_)exit
        if(iter<nitermax)blanc(iter+1)=b_
     enddo
     if(iter==nitermax.AND.mpi_master)write(*,"(A)")"MPI_LANCZOS_TRIDIAG_D: reach Nitermax"
  endif
end subroutine mpi_lanczos_tridiag_d

subroutine mpi_lanczos_tridiag_c(MpiComm,MatVec,vin,alanc,blanc,threshold)
  integer                                      :: MpiComm
  interface
     subroutine MatVec(Nloc,vin,vout)
       integer                    :: Nloc
       complex(8),dimension(Nloc) :: vin
       complex(8),dimension(Nloc) :: vout
     end subroutine MatVec
  end interface
  complex(8),dimension(:),intent(inout)        :: vin !Nloc
  complex(8),dimension(size(vin))              :: vout,vtmp
  real(8),dimension(:),intent(inout)           :: alanc
  real(8),dimension(size(alanc)),intent(inout) :: blanc
  integer                                      :: Nitermax,Nloc,i
  integer                                      :: iter
  real(8)                                      :: a_,b_
  real(8),optional                             :: threshold
  !
  logical                                      :: mpi_master
  !
  if(MpiComm /= MPI_COMM_NULL)then
     !
     mpi_master=get_master_MPI(MpiComm)
     !
     Nloc = size(vin)
     !
     if(present(threshold))threshold_=threshold
     !
     vtmp=vin
     Nitermax = size(alanc)
     a_=0d0
     b_=0d0
     vout=zero
     do iter=1,Nitermax
        call mpi_lanczos_iteration_c(MpiComm,MatVec,iter,vtmp,vout,a_,b_)
        alanc(iter)=a_
        if(abs(b_)<threshold_)exit
        if(iter<nitermax)blanc(iter+1)=b_
     enddo
     if(iter==nitermax.AND.mpi_master)write(*,"(A)")"MPI_LANCZOS_TRIDIAG_C: reach Nitermax"
  endif
end subroutine mpi_lanczos_tridiag_c




!---------------------------------------------------------------------
!Purpose: plain homebrew lanczos iteration (no orthogonalization)
!note: the a,b variables are real, even in the complex matrix case
!to understand why check out the Gollub-Van Loan textbook.
!a it is easy: hermiticity->diag\in\RRR
!b: is fixed by requiring |b|^2 = <v,v> thus you can only fix the 
!the absolute value. A lemma shows that the phase can be chosen 
!identically zero
!MPI VERSION
!---------------------------------------------------------------------
subroutine mpi_lanczos_iteration_d(MpiComm,MatVec,iter,vin,vout,a,b)
  integer                                    :: MpiComm
  interface
     subroutine MatVec(Nloc,vin,vout)
       integer                 :: Nloc
       real(8),dimension(Nloc) :: vin
       real(8),dimension(Nloc) :: vout
     end subroutine MatVec
  end interface
  real(8),dimension(:),intent(inout)         :: vin !Nloc
  real(8),dimension(size(vin)),intent(inout) :: vout
  real(8),dimension(size(vin))               :: tmp
  real(8),intent(inout)                      :: a,b
  real(8)                                    :: atmp,btmp
  integer                                    :: iter,ndim,nloc
  real(8)                                    :: norm,norm_tmp
  !
  logical                                    :: mpi_master
  !
  nloc=size(vin)
  !
  mpi_master=get_master_MPI(MpiComm)
  !
  if(iter==1)then
     norm = 0d0
     norm_tmp=dot_product(vin,vin)
     call AllReduce_MPI(MpiComm,norm_tmp,norm)
     if(mpi_master.AND.norm==0d0)stop "MPI_LANCZOS_ITERATION_D: norm = 0!!"
     vin=vin/sqrt(norm)
     b=0d0
  end if
  !
  call MatVec(nloc,vin,tmp)
  tmp   = tmp-b*vout
  atmp  = dot_product(vin,tmp)
  a     = 0d0
  call AllReduce_MPI(MpiComm,atmp,a)
  tmp   = tmp-a*vin
  btmp  = dot_product(tmp,tmp) !sqrt(dot_product(tmp,tmp))
  b     = 0d0
  call AllReduce_MPI(MpiComm,btmp,b)
  b     = sqrt(b)
  vout  = vin
  vin   = tmp/b
end subroutine mpi_lanczos_iteration_d

subroutine mpi_lanczos_iteration_c(MpiComm,MatVec,iter,vin,vout,a,b)
  integer                                       :: MpiComm
  interface
     subroutine MatVec(Nloc,vin,vout)
       integer                    :: Nloc
       complex(8),dimension(Nloc) :: vin
       complex(8),dimension(Nloc) :: vout
     end subroutine MatVec
  end interface
  complex(8),dimension(:),intent(inout)         :: vin !Nloc
  complex(8),dimension(size(vin)),intent(inout) :: vout
  complex(8),dimension(size(vin))               :: tmp
  real(8),intent(inout)                         :: a,b
  real(8)                                       :: atmp,btmp
  integer                                       :: iter,ndim,nloc
  real(8)                                       :: norm,norm_tmp
  !
  logical                                       :: mpi_master
  !
  nloc=size(vin)
  !
  mpi_master=get_master_MPI(MpiComm)
  !
  if(iter==1)then
     norm = 0d0
     norm_tmp=dot_product(vin,vin)
     call AllReduce_MPI(MpiComm,norm_tmp,norm)
     if(mpi_master.AND.norm==0d0)stop "MPI_LANCZOS_ITERATION_C: norm = 0!!"
     vin=vin/sqrt(norm)
     b=0d0
  end if
  !
  call MatVec(nloc,vin,tmp)
  tmp   = tmp-b*vout
  atmp  = dot_product(vin,tmp)
  a     = 0d0
  call AllReduce_MPI(MpiComm,atmp,a)
  tmp   = tmp-a*vin
  btmp  = dot_product(tmp,tmp) !sqrt(dot_product(tmp,tmp))
  b     = 0d0
  call AllReduce_MPI(MpiComm,btmp,b)
  b     = sqrt(b)
  vout  = vin
  vin   = tmp/b
end subroutine mpi_lanczos_iteration_c
