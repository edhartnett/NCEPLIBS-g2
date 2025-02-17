!> @file
!> @brief Pack up a data field using a GRIB2 algorithm with missing
!> value management.
!> @author Stephen Gilbert @date 2000-06-21

!> Pack up a data field using a GRIB2 algorithm with missing value
!> management.
!>
!> This subroutine packs up a data field using a complex packing
!> algorithm as defined in the GRIB2 documention. It supports GRIB2
!> complex packing templates with or without spatial differences
!> (i.e. Data Representation Tables [5.2]
!> (https://www.nco.ncep.noaa.gov/pmb/docs/grib2/grib2_doc/grib2_table5-2.shtml)
!> and
!> [5.3](https://www.nco.ncep.noaa.gov/pmb/docs/grib2/grib2_doc/grib2_table5-3.shtml)).
!>
!> This subroutine also fills in GRIB2 Data Representation Template
!> 5.2 or 5.3 with the appropriate values. It assumes that Missing
!> Value Management is being used and that 1 or 2 missing values
!> appear in the data.
!>
!> @param[in] fld Contains the data values to pack.
!> @param[in] ndpts The number of data values in array fld.
!> @param[in] idrsnum Data Representation Template number. Must
!> equal 2 or 3.
!> @param[inout] idrstmpl Contains the array of values for Data
!> Representation Template 5.2 or 5.3
!> - idrstmpl(1) Reference value - ignored on input set by compack routine.
!> - idrstmpl(2) Binary Scale Factor.
!> - idrstmpl(3) Decimal Scale Factor.
!> - idrstmpl(4) number of bits for each data value - ignored on input.
!> - idrstmpl(5) Original field type, currently ignored on input, set = 0 on
!> !output, Data values assumed to be reals.
!> - idrstmpl(6) = 0 use lossless compression or = 1 use lossy compression.
!> - idrstmpl(7) Missing value management.
!> - idrstmpl(8) Primary missing value.
!> - idrstmpl(9) Secondary missing value.
!> - idrstmpl(17) Order of Spatial Differencing (1 or 2).
!> @param[out] cpack The packed data field (character*1 array).
!> @param[out] lcpack length of packed field cpack. -1 is returned if
!> idrstmpl(7) is not set correctly.
!>
!> @author Stephen Gilbert @date 2000-06-21
      subroutine misspack(fld,ndpts,idrsnum,idrstmpl,cpack,lcpack)

      use intmath
      integer,intent(in) :: ndpts,idrsnum
      real,intent(in) :: fld(ndpts)
      character(len=1),intent(out) :: cpack(*)
      integer,intent(inout) :: idrstmpl(*)
      integer,intent(out) :: lcpack

      real(4) :: ref, rmin4
      integer(4) :: iref
      integer,allocatable :: ifld(:),ifldmiss(:),jfld(:)
      integer,allocatable :: jmin(:),jmax(:),lbit(:)
      integer,parameter :: zero=0
      integer,allocatable :: gref(:),gwidth(:),glen(:)
      integer :: glength,grpwidth
      logical :: simple_alg
      logical :: have_rmin

      simple_alg = .false.
      have_rmin = .false.
      bscale=2.0**real(-idrstmpl(2))
      dscale=10.0**real(idrstmpl(3))
      missopt=idrstmpl(7)
      if ( missopt.ne.1 .AND. missopt.ne.2 ) then
         print *,'misspack: Unrecognized option.'
         lcpack=-1
         return
      else     !  Get missing values
         call rdieee(idrstmpl(8),rmissp,1)
         if (missopt.eq.2) call rdieee(idrstmpl(9),rmisss,1)
      endif
!
!  Find min value of non-missing values in the data,
!  AND set up missing value mapping of the field.
!
      allocate(ifldmiss(ndpts))
c     rmin=huge(rmin)

      if ( missopt .eq. 1 ) then        ! Primary missing value only
         do j=1,ndpts
           if (fld(j).eq.rmissp) then
              ifldmiss(j)=1
           else
              ifldmiss(j)=0
              if(have_rmin) then
                 if (fld(j).lt.rmin) rmin=fld(j)
              else
                 rmin=fld(j)
                 have_rmin=.true.
              endif
           endif
         enddo
         if(.not.have_rmin) rmin=rmissp
      endif
      if ( missopt .eq. 2 ) then        ! Primary and secondary missing values
         do j=1,ndpts
           if (fld(j).eq.rmissp) then
              ifldmiss(j)=1
           elseif (fld(j).eq.rmisss) then
              ifldmiss(j)=2
           else
              ifldmiss(j)=0
              if(have_rmin) then
                 if (fld(j).lt.rmin) rmin=fld(j)
              else
                 rmin=fld(j)
                 have_rmin=.true.
              endif
           endif
           if(.not.have_rmin) rmin=rmissp
         enddo
      endif
!
!  Allocate work arrays:
!  Note: -ifldmiss(j),j=1,ndpts is a map of original field indicating 
!         which of the original data values
!         are primary missing (1), sencondary missing (2) or non-missing (0).
!        -jfld(j),j=1,nonmiss is a subarray of just the non-missing values from
!         the original field.
!
      !if (rmin.ne.rmax) then
        iofst=0
        allocate(ifld(ndpts))
        allocate(jfld(ndpts))
        allocate(gref(ndpts))
        allocate(gwidth(ndpts))
        allocate(glen(ndpts))
        !
        !  Scale original data
        !
        nonmiss=0
        if (idrstmpl(2).eq.0) then        !  No binary scaling
           imin=nint(rmin*dscale)
           !imax=nint(rmax*dscale)
           rmin=real(imin)
           do j=1,ndpts
              if (ifldmiss(j).eq.0) then
                nonmiss=nonmiss+1
                jfld(nonmiss)=max(0,nint(fld(j)*dscale)-imin)
              endif
           enddo
        else                              !  Use binary scaling factor
           rmin=rmin*dscale
           !rmax=rmax*dscale
           do j=1,ndpts
              if (ifldmiss(j).eq.0) then
                nonmiss=nonmiss+1
                jfld(nonmiss)=max(0,nint(((fld(j)*dscale)-rmin)*bscale))
              endif
           enddo
        endif
        !
        !  Calculate Spatial differences, if using DRS Template 5.3
        !
        if (idrsnum.eq.3) then        ! spatial differences
           if (idrstmpl(17).ne.1.and.idrstmpl(17).ne.2) idrstmpl(17)=2
           if (idrstmpl(17).eq.1) then      ! first order
              if(nonmiss<1) then
                 ival1=1.0
              else
                 ival1=jfld(1)
              endif
              do j=nonmiss,2,-1
                 jfld(j)=jfld(j)-jfld(j-1)
              enddo
              if(nonmiss>0)             jfld(1)=0
           elseif (idrstmpl(17).eq.2) then      ! second order
              if(nonmiss==1) then
                 ival1=jfld(1)
                 ival2=jfld(1)
              elseif(nonmiss<1) then
                 ival1=1.0
                 ival2=1.0
              else
                 ival1=jfld(1)
                 ival2=jfld(2)
              endif
              do j=nonmiss,3,-1
                 jfld(j)=jfld(j)-(2*jfld(j-1))+jfld(j-2)
              enddo
              if(nonmiss>=1) jfld(1)=0
              if(nonmiss>=2) jfld(2)=0
           endif
           !
           !  subtract min value from spatial diff field
           !
           isd=idrstmpl(17)+1
           minsd=minval(jfld(isd:nonmiss))
           do j=isd,nonmiss
              jfld(j)=jfld(j)-minsd
           enddo
           !
           !   find num of bits need to store minsd and add 1 extra bit
           !   to indicate sign
           !
           temp=i1log2(abs(minsd))
           nbitsd=ceiling(temp)+1
           !
           !   find num of bits need to store ifld(1) ( and ifld(2)
           !   if using 2nd order differencing )
           !
           maxorig=ival1
           if (idrstmpl(17).eq.2.and.ival2.gt.ival1) maxorig=ival2
           temp=i1log2(maxorig)
           nbitorig=ceiling(temp)+1
           if (nbitorig.gt.nbitsd) nbitsd=nbitorig
           !   increase number of bits to even multiple of 8 ( octet )
           if (mod(nbitsd,8).ne.0) nbitsd=nbitsd+(8-mod(nbitsd,8))
           !
           !  Store extra spatial differencing info into the packed
           !  data section.
           !
           if (nbitsd.ne.0) then
              !   pack first original value
              if (ival1.ge.0) then
                 call g2_sbytec(cpack,ival1,iofst,nbitsd)
                 iofst=iofst+nbitsd
              else
                 call g2_sbytec(cpack,1,iofst,1)
                 iofst=iofst+1
                 call g2_sbytec(cpack,iabs(ival1),iofst,nbitsd-1)
                 iofst=iofst+nbitsd-1
              endif
              if (idrstmpl(17).eq.2) then
               !  pack second original value
                 if (ival2.ge.0) then
                    call g2_sbytec(cpack,ival2,iofst,nbitsd)
                    iofst=iofst+nbitsd
                 else
                    call g2_sbytec(cpack,1,iofst,1)
                    iofst=iofst+1
                    call g2_sbytec(cpack,iabs(ival2),iofst,nbitsd-1)
                    iofst=iofst+nbitsd-1
                 endif
              endif
              !  pack overall min of spatial differences
              if (minsd.ge.0) then
                 call g2_sbytec(cpack,minsd,iofst,nbitsd)
                 iofst=iofst+nbitsd
              else
                 call g2_sbytec(cpack,1,iofst,1)
                 iofst=iofst+1
                 call g2_sbytec(cpack,iabs(minsd),iofst,nbitsd-1)
                 iofst=iofst+nbitsd-1
              endif
           endif
         !print *,'SDp ',ival1,ival2,minsd,nbitsd
        endif     !  end of spatial diff section
        !
        !  Expand non-missing data values to original grid.
        !
        miss1=minval(jfld(1:nonmiss))-1
        miss2=miss1-1
        n=0
        do j=1,ndpts
           if ( ifldmiss(j).eq.0 ) then
              n=n+1
              ifld(j)=jfld(n)
           elseif ( ifldmiss(j).eq.1 ) then
              ifld(j)=miss1
           elseif ( ifldmiss(j).eq.2 ) then
              ifld(j)=miss2
           endif
        enddo
        if(ndpts<2) simple_alg=.true.
        !
        !   Determine Groups to be used.
        !
        if ( simple_alg ) then
           !  set group length to 10 :  calculate number of groups
           !  and length of last group
           ngroups=ndpts/10
           glen(1:ngroups)=10
           itemp=mod(ndpts,10)
           if (itemp.ne.0) then
              ngroups=ngroups+1
              glen(ngroups)=itemp
           endif
        else
           ! Use Dr. Glahn's algorithm for determining grouping.
           !
           kfildo=6
           minpk=10 
           inc=1
           maxgrps=(ndpts/minpk)+1
           allocate(jmin(maxgrps))
           allocate(jmax(maxgrps))
           allocate(lbit(maxgrps))
           call pack_gp(kfildo,ifld,ndpts,missopt,minpk,inc,miss1,miss2,
     &                  jmin,jmax,lbit,glen,maxgrps,ngroups,ibit,jbit,
     &                  kbit,novref,lbitref,ier)
           !print *,'SAGier = ',ier,ibit,jbit,kbit,novref,lbitref
           do ng=1,ngroups
              glen(ng)=glen(ng)+novref
           enddo
           deallocate(jmin)
           deallocate(jmax)
           deallocate(lbit)
        endif
        !  
        !  For each group, find the group's reference value (min)
        !  and the number of bits needed to hold the remaining values
        !
        n=1
        do ng=1,ngroups
           !  how many of each type?
           num0=count(ifldmiss(n:n+glen(ng)-1) .EQ. 0)
           num1=count(ifldmiss(n:n+glen(ng)-1) .EQ. 1)
           num2=count(ifldmiss(n:n+glen(ng)-1) .EQ. 2)
           if ( num0.eq.0 ) then      ! all missing values
              if ( num1.eq.0 ) then       ! all secondary missing
                gref(ng)=-2
                gwidth(ng)=0
              elseif ( num2.eq.0 ) then       ! all primary missing
                gref(ng)=-1
                gwidth(ng)=0
              else                           ! both primary and secondary
                gref(ng)=0
                gwidth(ng)=1
              endif
           else                       ! contains some non-missing data
             !    find max and min values of group
             gref(ng)=huge(n)
             imax=-1*huge(n)
             j=n
             do lg=1,glen(ng)
                if ( ifldmiss(j).eq.0 ) then
                  if (ifld(j).lt.gref(ng)) gref(ng)=ifld(j) 
                  if (ifld(j).gt.imax) imax=ifld(j) 
                endif
                j=j+1
             enddo
             if (missopt.eq.1) imax=imax+1
             if (missopt.eq.2) imax=imax+2
             !   calc num of bits needed to hold data
             if ( gref(ng).ne.imax ) then
                temp=i1log2(imax-gref(ng))
                gwidth(ng)=ceiling(temp)
             else
                gwidth(ng)=0
             endif
           endif
           !   Subtract min from data
           j=n
           mtemp=2**gwidth(ng)
           do lg=1,glen(ng)
              if (ifldmiss(j).eq.0) then       ! non-missing
                 ifld(j)=ifld(j)-gref(ng)
              elseif (ifldmiss(j).eq.1) then    ! primary missing
                 ifld(j)=mtemp-1
              elseif (ifldmiss(j).eq.2) then    ! secondary missing
                 ifld(j)=mtemp-2
              endif
              j=j+1
           enddo
           !   increment fld array counter
           n=n+glen(ng)
        enddo
        !  
        !  Find max of the group references and calc num of bits needed 
        !  to pack each groups reference value, then
        !  pack up group reference values
        !
        !write(77,*)'GREFS: ',(gref(j),j=1,ngroups)
        igmax=maxval(gref(1:ngroups))
        if (missopt.eq.1) igmax=igmax+1
        if (missopt.eq.2) igmax=igmax+2
        if (igmax.ne.0) then
           temp=i1log2(igmax)
           nbitsgref=ceiling(temp)
           ! restet the ref values of any "missing only" groups.
           mtemp=2**nbitsgref
           do j=1,ngroups
               if (gref(j).eq.-1) gref(j)=mtemp-1
               if (gref(j).eq.-2) gref(j)=mtemp-2
           enddo
           call g2_sbytesc(cpack,gref,iofst,nbitsgref,0,ngroups)
           itemp=nbitsgref*ngroups
           iofst=iofst+itemp
           !         Pad last octet with Zeros, if necessary,
           if (mod(itemp,8).ne.0) then
              left=8-mod(itemp,8)
              call g2_sbytec(cpack,zero,iofst,left)
              iofst=iofst+left
           endif
        else
           nbitsgref=0
        endif
        !
        !  Find max/min of the group widths and calc num of bits needed
        !  to pack each groups width value, then
        !  pack up group width values
        !
        !write(77,*)'GWIDTHS: ',(gwidth(j),j=1,ngroups)
        iwmax=maxval(gwidth(1:ngroups))
        ngwidthref=minval(gwidth(1:ngroups))
        if (iwmax.ne.ngwidthref) then
           temp=i1log2(iwmax-ngwidthref)
           nbitsgwidth=ceiling(temp)
           do i=1,ngroups
              gwidth(i)=gwidth(i)-ngwidthref
           enddo
           call g2_sbytesc(cpack,gwidth,iofst,nbitsgwidth,0,ngroups)
           itemp=nbitsgwidth*ngroups
           iofst=iofst+itemp
           !         Pad last octet with Zeros, if necessary,
           if (mod(itemp,8).ne.0) then
              left=8-mod(itemp,8)
              call g2_sbytec(cpack,zero,iofst,left)
              iofst=iofst+left
           endif
        else
           nbitsgwidth=0
           gwidth(1:ngroups)=0
        endif
        !
        !  Find max/min of the group lengths and calc num of bits needed
        !  to pack each groups length value, then
        !  pack up group length values
        !
        !write(77,*)'GLENS: ',(glen(j),j=1,ngroups)
        ilmax=maxval(glen(1:ngroups-1))
        nglenref=minval(glen(1:ngroups-1))
        if(ngroups>0) then
           nglenlast=glen(ngroups)
        else
           nglenlast=0
        endif
        if (ilmax.ne.nglenref) then
           temp=i1log2(ilmax-nglenref)
           nbitsglen=ceiling(temp)
           do i=1,ngroups-1
              glen(i)=glen(i)-nglenref
           enddo
           call g2_sbytesc(cpack,glen,iofst,nbitsglen,0,ngroups)
           itemp=nbitsglen*ngroups
           iofst=iofst+itemp
           !         Pad last octet with Zeros, if necessary,
           if (mod(itemp,8).ne.0) then
              left=8-mod(itemp,8)
              call g2_sbytec(cpack,zero,iofst,left)
              iofst=iofst+left
           endif
        else
           nbitsglen=0
           glen(1:ngroups)=0
        endif
        !
        !  For each group, pack data values
        !
        !write(77,*)'IFLDS: ',(ifld(j),j=1,ndpts)
        n=1
        ij=0
        do ng=1,ngroups
           glength=glen(ng)+nglenref
           if (ng.eq.ngroups ) glength=nglenlast
           grpwidth=gwidth(ng)+ngwidthref
       !write(77,*)'NGP ',ng,grpwidth,glength,gref(ng)
           if ( grpwidth.ne.0 ) then
              call g2_sbytesc(cpack,ifld(n),iofst,grpwidth,0,glength)
              iofst=iofst+(grpwidth*glength)
           endif
           do kk=1,glength
              ij=ij+1
        !write(77,*)'SAG ',ij,fld(ij),ifld(ij),gref(ng),bscale,rmin,dscale
           enddo
           n=n+glength
        enddo
        !         Pad last octet with Zeros, if necessary,
        if (mod(iofst,8).ne.0) then
           left=8-mod(iofst,8)
           call g2_sbytec(cpack,zero,iofst,left)
           iofst=iofst+left
        endif
        lcpack=iofst/8
        !
        if ( allocated(ifld) ) deallocate(ifld)
        if ( allocated(jfld) ) deallocate(jfld)
        if ( allocated(ifldmiss) ) deallocate(ifldmiss)
        if ( allocated(gref) ) deallocate(gref)
        if ( allocated(gwidth) ) deallocate(gwidth)
        if ( allocated(glen) ) deallocate(glen)
      !else           !   Constant field ( max = min )
      !  nbits=0
      !  lcpack=0
      !  nbitsgref=0
      !  ngroups=0
      !endif

!
!  Fill in ref value and number of bits in Template 5.2
!
      rmin4 = rmin
      call mkieee(rmin4,ref,1)   ! ensure reference value is IEEE format
!      call g2_gbytec(ref,idrstmpl(1),0,32)
      iref=transfer(ref,iref)
      idrstmpl(1)=iref
      idrstmpl(4)=nbitsgref
      idrstmpl(5)=0         ! original data were reals
      idrstmpl(6)=1         ! general group splitting
      idrstmpl(10)=ngroups          ! Number of groups
      idrstmpl(11)=ngwidthref       ! reference for group widths
      idrstmpl(12)=nbitsgwidth      ! num bits used for group widths
      idrstmpl(13)=nglenref         ! Reference for group lengths
      idrstmpl(14)=1                ! length increment for group lengths
      idrstmpl(15)=nglenlast        ! True length of last group
      idrstmpl(16)=nbitsglen        ! num bits used for group lengths
      if (idrsnum.eq.3) then
         idrstmpl(18)=nbitsd/8      ! num bits used for extra spatial
                                    ! differencing values
      endif

      return
      end
