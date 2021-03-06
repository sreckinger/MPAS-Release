! Copyright (c) 2013,  Los Alamos National Security, LLC (LANS) (LA-CC-13-047)
! and the University Corporation for Atmospheric Research (UCAR).
!
! Unless noted otherwise source code is licensed under the BSD license.
! Additional copyright and license information can be found in the LICENSE file
! distributed with this code, or at http://mpas-dev.github.com/license.html
!
!==================================================================================================
 module mpas_atmphys_initialize_real
 use mpas_kind_types
 use mpas_configure, only: config_met_prefix,  &
                           config_frac_seaice, &
                           config_input_sst,   &
                           config_nsoillevels, &
                           config_start_time,  &
                           config_sfc_prefix
 use mpas_dmpar
 use mpas_grid_types
 use mpas_init_atm_surface
 use mpas_atmphys_date_time
 use mpas_atmphys_utilities

 implicit none
 private
 public:: physics_initialize_real

 contains

!==================================================================================================
 subroutine physics_initialize_real(mesh,fg,dminfo)
!==================================================================================================
!input arguments:
 type(mesh_type),intent(in):: mesh
 type(dm_info),intent(in)  :: dminfo

!inout arguments:
 type(fg_type),intent(inout):: fg 

!local variables:
 character(len=StrKIND):: initial_date

 integer:: iCell,nCellsSolve
 integer,dimension(:),pointer:: landmask

 real(kind=RKIND),dimension(:)  ,pointer:: sfc_albbck
 real(kind=RKIND),dimension(:,:),pointer:: albedo12m

 real(kind=RKIND),dimension(:),pointer:: seaice,xice,xland
 real(kind=RKIND),dimension(:),pointer:: snoalb 
 real(kind=RKIND),dimension(:),pointer:: vegfra,shdmin,shdmax
 real(kind=RKIND),dimension(:),pointer:: snow,snowc,snowh
 real(kind=RKIND),dimension(:,:),pointer:: greenfrac

 real(kind=RKIND),dimension(:),pointer:: skintemp,sst
 
!--------------------------------------------------------------------------------------------------

 write(0,*)
 write(0,*) '--- enter physics_initialize_real:'

 nCellsSolve = mesh % nCellsSolve

 landmask   => mesh % landmask  % array
 albedo12m  => mesh % albedo12m % array
 greenfrac  => mesh % greenfrac % array
 shdmin     => mesh % shdmin    % array
 shdmax     => mesh % shdmax    % array
 snoalb     => mesh % snoalb    % array

 sfc_albbck => fg % sfc_albbck % array
 vegfra     => fg % vegfra     % array
 snow       => fg % snow       % array
 snowc      => fg % snowc      % array
 snowh      => fg % snowh      % array
 skintemp   => fg % skintemp   % array
 sst        => fg % sst        % array
 seaice     => fg % seaice     % array
 xice       => fg % xice       % array
 xland      => fg % xland      % array

!initialization of the sea-surface temperature and seaice if they are read from a separate
!input file. calling this subroutine will overwrite the arrays sst and seaice already read
!in the file defined by config_input_name:
 if(config_input_sst) then
    write(0,*) '--- read sea-surface temperature from auxillary file:'
    call interp_sfc_to_MPAS(config_start_time(1:13),mesh,fg,dminfo)
    call physics_init_sst(mesh,fg)
 endif

!initialization of the surface background albedo: interpolation of the monthly values to the
!initial date:
 initial_date = trim(config_start_time)
 call monthly_interp_to_date(nCellsSolve,initial_date,albedo12m,sfc_albbck)

 do iCell = 1, nCellsSolve
    sfc_albbck(iCell) = sfc_albbck(iCell) / 100._RKIND
    if(landmask(iCell) .eq. 0) sfc_albbck(iCell) = 0.08_RKIND
 enddo

!initialization of the green-ness (vegetation) fraction: interpolation of the monthly values to
!the initial date. get the min/max for each cell for the monthly green-ness fraction:
!initial_date = trim(config_init_date)
 initial_date = trim(config_start_time)
 call monthly_interp_to_date(nCellsSolve,initial_date,greenfrac,vegfra)

!calculates the maximum and minimum green-ness (vegetation) fraction:
 call monthly_min_max(nCellsSolve,greenfrac,shdmin,shdmax)

!limit the annual maximum snow albedo to 0.08 over open-ocean and to 0.75 over sea-ice cells::
 do iCell = 1, nCellsSolve
    if(landmask(iCell) .eq. 0 .and. seaice(iCell) .eq. 0._RKIND) then
       snoalb(iCell) = 0.08_RKIND
    elseif(landmask(iCell) .eq. 0 .and. seaice(iCell) .eq. 1._RKIND) then
       snoalb(iCell) = 0.75_RKIND
    endif
 enddo

!initialization of the flag indicating the presence of snow (0 or 1) and of the snow depth
!(m) as functions of the input snow water content (kg/m2). we use a 5:1 ratio from liquid
!water equivalent to snow depth:
 do iCell = 1, nCellsSolve
    if(snow(iCell) .ge. 10._RKIND) then
       snowc(iCell) = 1._RKIND
    else
       snowc(iCell) = 0._RKIND
    endif
    snowh(iCell) = snow(iCell) * 5.0_RKIND / 1000._RKIND
 enddo

!initialization of soil layers properties:
 call init_soil_layers(mesh,fg,dminfo)

!initialize seaice points:
 call physics_init_seaice(mesh,fg)

!define xland over land and ocean:
 do iCell = 1, nCellsSolve
    if(landmask(iCell) .eq. 1 .or. (landmask(iCell).eq.0 .and. seaice(iCell).eq.1._RKIND)) then
       xland(iCell) = 1._RKIND
    elseif(landmask(iCell) .eq. 0) then
       xland(iCell) = 2._RKIND
    endif
 enddo

 write(0,*) '--- end physics_initialize_real:'

 end subroutine physics_initialize_real

!==================================================================================================
 subroutine init_soil_layers(mesh,fg,dminfo)
!==================================================================================================

!input arguments:
 type(mesh_type),intent(in):: mesh
 type(dm_info),intent(in)  :: dminfo

!inout arguments:
 type(fg_type),intent(inout):: fg

!--------------------------------------------------------------------------------------------------

!adjust the annual mean deep soil temperature:
 call adjust_input_soiltemps(mesh,fg)

!initialize the depth of the soil layers:
 call init_soil_layers_depth(mesh,fg)
 
!initialize the temperature, moisture, and liquid water of the individual soil layers:
 call init_soil_layers_properties(mesh,fg,dminfo)

 end subroutine init_soil_layers

!==================================================================================================
 subroutine adjust_input_soiltemps(mesh,fg)
!==================================================================================================

!input arguments:
 type(mesh_type),intent(in) :: mesh

!inout arguments:
 type(fg_type),intent(inout):: fg 

!local variables:
 integer:: iCell,ifgSoil
 integer:: nCellsSolve,nFGSoilLevels
 integer,dimension(:),pointer:: landmask

 real(kind=RKIND),dimension(:),pointer  :: soilz,ter
 real(kind=RKIND),dimension(:),pointer  :: skintemp,soiltemp,tmn
 real(kind=RKIND),dimension(:,:),pointer:: st_fg

!--------------------------------------------------------------------------------------------------

 nCellsSolve   = mesh % nCellsSolve
 nFGSoilLevels = mesh % nFGSoilLevels

 landmask => mesh % landmask % array
 soiltemp => mesh % soiltemp % array
 ter      => mesh % ter      % array

 skintemp => fg % skintemp % array
 tmn      => fg % tmn      % array
 st_fg    => fg % st_fg    % array
 soilz    => fg % soilz    % array

 do iCell = 1, nCellsSolve
    if(landmask(iCell) .eq. 1) then

       !adjust the annual deep mean soil temperature and skin temperatures over land: 
       tmn(iCell) = soiltemp(iCell) - 0.0065_RKIND * ter(iCell)
       skintemp(iCell) = skintemp(iCell) - 0.0065_RKIND * (ter(iCell)-soilz(iCell))

       !adjust the soil layer temperatures:
       do ifgSoil = 1, nFGSoilLevels
          st_fg(ifgSoil,iCell) = st_fg(ifgSoil,iCell) - 0.0065_RKIND * (ter(iCell)-soilz(iCell))
       enddo

    elseif(landmask(iCell) .eq. 0) then

       tmn(iCell) = skintemp(iCell)
       
    endif
 enddo

 end subroutine adjust_input_soiltemps

!==================================================================================================
 subroutine init_soil_layers_depth(mesh,fg)
!==================================================================================================

!input arguments:
 type(mesh_type),intent(in):: mesh

!inout arguments:
 type(fg_type),intent(inout):: fg 

!local variables:
 integer:: iCell,iSoil

!--------------------------------------------------------------------------------------------------

 write(0,*)
 write(0,*) '--- enter subroutine init_soil_layers_depth:'

 if(config_nsoillevels .ne. 4) &
    call physics_error_fatal('NOAH lsm uses 4 soil layers. Correct config_nsoillevels.')

 do iCell = 1, mesh % nCells

    iSoil = 1
    fg % zs_fg % array(iSoil,iCell) = 0.5_RKIND * fg % dzs_fg % array(iSoil,iCell)
    do iSoil = 2, mesh % nFGSoilLevels
       fg % zs_fg % array(iSoil,iCell) = fg % zs_fg % array(iSoil-1,iCell)        &
                                 + 0.5_RKIND * fg % dzs_fg % array(iSoil-1,iCell) &
                                 + 0.5_RKIND * fg % dzs_fg % array(iSoil,iCell)
    enddo

 enddo

 do iCell = 1, mesh % nCells
    fg % dzs % array(1,iCell) = 0.10_RKIND
    fg % dzs % array(2,iCell) = 0.30_RKIND
    fg % dzs % array(3,iCell) = 0.60_RKIND
    fg % dzs % array(4,iCell) = 1.00_RKIND

    iSoil = 1
    fg % zs % array(iSoil,iCell)  = 0.5_RKIND * fg % dzs % array(iSoil,iCell)
    do iSoil = 2, mesh % nSoilLevels
       fg % zs % array(iSoil,iCell) = fg % zs % array(iSoil-1,iCell)              &
                                    + 0.5_RKIND * fg % dzs % array(iSoil-1,iCell) &
                                    + 0.5_RKIND * fg % dzs % array(iSoil,iCell)
    enddo

 enddo

 end subroutine init_soil_layers_depth

!==================================================================================================
 subroutine init_soil_layers_properties(mesh,fg,dminfo)
!==================================================================================================

!input arguments:
 type(mesh_type),intent(in):: mesh
 type(dm_info),intent(in)  :: dminfo

!inout arguments:
 type(fg_type),intent(inout):: fg 

!local variables:
 integer:: iCell,ifgSoil,iSoil
 integer:: nCells,nFGSoilLevels,nSoilLevels
 integer:: num_sm,num_st
 integer,dimension(:),pointer:: landmask
 
 real(kind=RKIND),dimension(:,:),allocatable:: zhave,sm_input,st_input

 real(kind=RKIND),dimension(:),pointer  :: skintemp,tmn
 real(kind=RKIND),dimension(:,:),pointer:: dzs,zs,tslb,smois,sh2o,smcrel
 real(kind=RKIND),dimension(:,:),pointer:: sm_fg,st_fg,zs_fg

!--------------------------------------------------------------------------------------------------

!write(0,*)
 write(0,*) '--- enter subroutine init_soil_layers_properties:'

 nCells        = mesh % nCells
 nSoilLevels   = mesh % nSoilLevels
 nFGSoilLevels = mesh % nFGSoilLevels
 write(0,*) 'nSoilLevels   =',nSoilLevels
 write(0,*) 'nFGSoilLevels =',nFGSoilLevels

 landmask => mesh % landmask % array

 zs_fg => fg % zs_fg % array
 st_fg => fg % st_fg % array
 sm_fg => fg % sm_fg % array

 zs     => fg % zs  % array
 dzs    => fg % dzs % array 
 sh2o   => fg % sh2o    % array
 smcrel => fg % smcrel % array
 smois  => fg % smois   % array 
 tslb   => fg % tslb    % array
 skintemp => fg % skintemp % array
 tmn      => fg % tmn      % array

!check that interpolation of the meteorological data to the MPAS grid did not create negative
!values for the first-guess soil temperatures and soil moistures.
 num_sm = 0
 num_st = 0
 do iCell = 1, nCells
    do ifgSoil = 1, nFGSoilLevels
       if(st_fg(ifgSoil,iCell) .le. 0._RKIND) num_st = num_st + 1
       if(sm_fg(ifgSoil,iCell) .lt. 0._RKIND) num_sm = num_sm + 1
    enddo
 enddo
 if(num_st .gt. 0) then
    write(0,*) 'Error in interpolation of st_fg to MPAS grid: num_st =', num_st
    call mpas_dmpar_abort(dminfo)
 elseif(num_sm .gt. 0) then
    write(0,*) 'Error in interpolation of sm_fg to MPAS grid: num_sm =', num_sm
    call mpas_dmpar_abort(dminfo)
 endif 

 if(config_nsoillevels .ne. 4) &
    call physics_error_fatal('NOAH lsm uses 4 soil layers. Correct config_nsoillevels.')

 if(.not.allocated(zhave)   ) allocate(zhave(nFGSoilLevels+2,nCells)   )
 if(.not.allocated(st_input)) allocate(st_input(nFGSoilLevels+2,nCells))
 if(.not.allocated(sm_input)) allocate(sm_input(nFGSoilLevels+2,nCells))

 do iCell = 1, nCells

    ifgSoil = 1
    zhave(ifgSoil,iCell)    = 0._RKIND
    st_input(ifgSoil,iCell) = skintemp(iCell)
    sm_input(ifgSoil,iCell) = sm_fg(ifgSoil+1,iCell)

    do ifgSoil = 1, nFGSoilLevels
       zhave(ifgSoil+1,iCell) = zs_fg(ifgSoil,iCell) / 100._RKIND
       st_input(ifgSoil+1,iCell) = st_fg(ifgSoil,iCell)
       sm_input(ifgSoil+1,iCell) = sm_fg(ifgSoil,iCell)
    enddo

    zhave(nFGSoilLevels+2,iCell) = 300._RKIND/100._RKIND
    st_input(nFGSoilLevels+2,iCell) = tmn(iCell)
    sm_input(nFGSoilLevels+2,iCell) = sm_input(nFGSoilLevels,iCell)

    if(iCell .eq. 1) then
       do ifgSoil = 1,nFGSoilLevels+2
          write(0,101) ifgSoil,zhave(ifgSoil,iCell)
       enddo
    endif

 enddo

!... interpolate the soil temperature, soil moisture, and soil liquid temperature to the four
!    layers used in the NOAH land surface scheme:

 do iCell = 1, nCells

    if(landmask(iCell) .eq. 1) then

       noah: do iSoil = 1 , nSoilLevels
          input: do ifgSoil = 1 , nFGSoilLevels+2-1
             if(iCell .eq. 1) write(0,102) iSoil,ifgSoil,zs(iSoil,iCell), &
                zhave(ifgSoil,iCell),zhave(ifgSoil+1,iCell)

             if(zs(iSoil,iCell).ge.zhave(ifgSoil,iCell) .and. &
                zs(iSoil,iCell).le.zhave(ifgSoil+1,iCell)) then

                tslb(iSoil,iCell) = &
                      (st_input(ifgSoil,iCell) * (zhave(ifgSoil+1,iCell)-zs(iSoil,iCell))    &
                    +  st_input(ifgSoil+1,iCell) * (zs(iSoil,iCell)-zhave(ifgSoil,iCell)))   &
                         / (zhave(ifgSoil+1,iCell)-zhave(ifgSoil,iCell))
                if(iCell .eq. 1) write(6,102) iSoil,ifgSoil,zs(iSoil,iCell), &
                   zhave(ifgSoil,iCell),zhave(ifgSoil+1,iCell)
                         
                smois(iSoil,iCell) = &
                       (sm_input(ifgSoil,iCell) * (zhave(ifgSoil+1,iCell)-zs(iSoil,iCell))   &
                    +  sm_input(ifgSoil+1,iCell) * (zs(iSoil,iCell)-zhave(ifgSoil,iCell)))   &
                    / (zhave(ifgSoil+1,iCell)-zhave(ifgSoil,iCell))

                sh2o(iSoil,iCell)   = 0._RKIND
                smcrel(iSoil,iCell) = 0._RKIND

                exit input
             endif
          enddo input
          if(iCell.eq. 1) write(0,*)
       enddo noah

    elseif(landmask(iCell) .eq. 0) then

       !fill the soil temperatures with the skin temperatures over oceans:
       do iSoil = 1, nSoilLevels
          tslb(iSoil,iCell)    = skintemp(iCell)
          smois(iSoil,iCell)   = 1._RKIND
          sh2o(iSoil,iCell)    = 1._RKIND
          smcrel(iSoil,iCell)  = 0._RKIND
       enddo

    endif

 enddo

!... final checks:

 do iCell = 1, nCells

    if(landmask(iCell).eq. 1 .and. tslb(1,iCell).gt.170._RKIND .and. tslb(1,iCell).lt.400._RKIND &
       .and. smois(1,iCell).lt.0.005_RKIND) then
       do iSoil = 1, nSoilLevels
          smois(iSoil,iCell) = 0.005_RKIND
       enddo
    endif

 enddo

!formats:
 101 format(i4,4(1x,e15.8))
 102 format(2i5,5(1x,e15.8))

 if(allocated(zhave)   ) deallocate(zhave )
 if(allocated(st_input)) deallocate(st_input)
 if(allocated(sm_input)) deallocate(sm_input)

 end subroutine init_soil_layers_properties

!==================================================================================================
 subroutine physics_init_sst(mesh,input)
!==================================================================================================

!input arguments: 
 type(mesh_type),intent(in):: mesh

#if !defined(non_hydrostatic_core)
!inout arguments: this subroutine is called from the MPAS initialization side.
 type(fg_type),intent(inout):: input
#else
!inout arguments: this subroutine is called from the MPAS model side.
 type(sfc_input_type),intent(inout):: input
#endif

!local variables:
 integer:: iCell,nCells
 integer,dimension(:),pointer:: landmask

 real(kind=RKIND),dimension(:),pointer  :: sst,tsk,xice
 real(kind=RKIND),dimension(:,:),pointer:: tslb

!--------------------------------------------------------------------------------------------------
 write(0,*)
 write(0,*) '--- enter subroutine physics_update_sst:'

!initialization:
 nCells = mesh % nCells

 landmask => mesh % landmask % array
 sst  => input % sst      % array
 tsk  => input % skintemp % array
 tslb => input % tslb     % array
 xice => input % xice     % array

!update the skin temperature and the soil temperature of the first soil layer with the updated
!sea-surface temperatures:
!change made so that the SSTs read for the surface update file are the same as the skin temperature
!over the oceans.
!do iCell = 1, nCells
!   if(landmask(iCell) == 0 .and. xice(iCell) == 0) then
!      tsk(iCell) = sst(iCell)
!   endif
!enddo
 do iCell = 1, nCells
    if(landmask(iCell) == 0) then
       tsk(iCell) = sst(iCell)
    endif
 enddo

 write(0,*) '--- end subroutine physics_update_sst:'

 end subroutine physics_init_sst

!==================================================================================================
 subroutine physics_init_seaice(mesh,input)
!==================================================================================================

!input arguments:
 type(mesh_type),intent(in) :: mesh

#if !defined(non_hydrostatic_core)
!inout arguments: this subroutine is called from the MPAS initialization side.
 type(fg_type),intent(inout):: input
#else
!inout arguments: this subroutine is called from the MPAS model side.
 type(sfc_input_type),intent(inout):: input
#endif

!local variables:
 character(len=StrKIND):: mess
 integer:: iCell,iSoil,nCells,nSoilLevels
 integer:: num_seaice_changes
 integer,dimension(:),pointer:: landmask,isltyp,ivgtyp

 real(kind=RKIND):: xice_threshold
 real(kind=RKIND):: mid_point_depth
 real(kind=RKIND),dimension(:),pointer  :: vegfra
 real(kind=RKIND),dimension(:),pointer  :: seaice,xice
 real(kind=RKIND),dimension(:),pointer  :: skintemp,tmn
 real(kind=RKIND),dimension(:,:),pointer:: tslb,smois,sh2o,smcrel

!note that this threshold is also defined in module_physics_vars.F.It is defined here to avoid
!adding "use module_physics_vars" since this subroutine is only used for the initialization of
!a "real" forecast with $CORE = init_nhyd_atmos.
 real(kind=RKIND),parameter:: xice_tsk_threshold = 271.
 real(kind=RKIND),parameter:: total_depth        = 3.   ! 3-meter soil depth.

!--------------------------------------------------------------------------------------------------
 write(0,*)
 write(0,*) '--- enter physics_init_seaice:'

 nCells     = mesh % nCells
 nSoilLevels = mesh % nSoilLevels

 landmask => mesh % landmask    % array
 isltyp   => mesh % soilcat_top % array
 ivgtyp   => mesh % lu_index    % array

 seaice   => input % seaice     % array
 xice     => input % xice       % array
 vegfra   => input % vegfra     % array

 skintemp => input % skintemp   % array
 tmn      => input % tmn        % array

 tslb     => input % tslb       % array
 smois    => input % smois      % array
 sh2o     => input % sh2o       % array
 smcrel   => input % smcrel     % array

 do iCell = 1, nCells
    seaice(iCell) = 0._RKIND
 enddo

!make sure that all the cells flagged as sea-ice cells are defined as ocean cells:
 num_seaice_changes = 0
 do iCell = 1, nCells
    if((landmask(iCell).eq.1 .and. xice(iCell).gt.0._RKIND) .or. xice(iCell).gt.200._RKIND) then
       num_seaice_changes = num_seaice_changes + 1
       seaice(iCell) = 0._RKIND
       xice(iCell)   = 0._RKIND
    endif
 enddo
 write(mess,fmt='(A,i12)') 'number of seaice cells converted to land cells 1 =', &
       num_seaice_changes
 call physics_message(mess)

!assign the threshold value for xice as a function of config_frac_seaice:
 if(.not. config_frac_seaice) then
    xice_threshold = 0.5_RKIND
    do iCell = 1,nCells
       if(xice(iCell) >= xice_threshold) then
          xice(iCell) = 1._RKIND
       else
          xice(iCell) = 0._RKIND
       endif
    enddo
 elseif(config_frac_seaice) then
    xice_threshold = 0.02
 endif
 write(0,*) '--- config_frac_seaice      :', config_frac_seaice
 write(0,*) '--- xice_threshold          :', xice_threshold

!convert seaice points to land points:
 num_seaice_changes = 0
 do iCell = 1, nCells

    if(xice(iCell) .ge. xice_threshold .or. &
      (landmask(iCell).eq.0 .and. skintemp(iCell).lt.xice_tsk_threshold)) then

       num_seaice_changes = num_seaice_changes + 1
       !sea-ice points are converted to land points:
       if(.not. config_frac_seaice) xice(iCell) = 1._RKIND
       if(landmask(iCell) .eq. 0) tmn(iCell) = 271.4_RKIND

       ivgtyp(iCell)   = 24 ! (isice = 24)
       isltyp(iCell)   = 16
       vegfra(iCell)   = 0._RKIND
       landmask(iCell) = 1._RKIND

       do iSoil = 1, nSoilLevels
          mid_point_depth = total_depth/nSoilLevels/2. &
                          + (iSoil-1)*(total_depth/nSoilLevels)
          tslb(iSoil,iCell) = ((total_depth-mid_point_depth) * skintemp(iCell) &
                            +  mid_point_depth * tmn(iCell)) / total_depth
          smois(iSoil,iCell)  = 1._RKIND
          sh2o(iSoil,iCell)   = 0._RKIND
          smcrel(iSoil,iCell) = 0._RKIND
       enddo
       
    elseif(xice(iCell) .lt. xice_threshold) then
       xice(iCell) = 0._RKIND

    endif

 enddo
 write(mess,fmt='(A,i12)') 'number of seaice cells converted to land cells 2 =', &
       num_seaice_changes
 call physics_message(mess)

!finally, update the sea-ice flag:
 do iCell = 1, nCells
    if(xice(iCell) > 0._RKIND) seaice(iCell) = 1._RKIND
 enddo
 write(0,*) '--- end physics_init_seaice:'

 end subroutine physics_init_seaice

!==================================================================================================
 end module mpas_atmphys_initialize_real
!==================================================================================================

