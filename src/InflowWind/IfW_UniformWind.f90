MODULE IfW_UniformWind
!> This module contains all the data and procedures that define uniform wind files (formerly known as
!! hub-height files). This could more accurately be called a point wind file since the wind speed at
!! any point is calculated by shear applied to the point where wind is defined.  It is basically uniform
!! wind over the rotor disk.  The entire file is read on initialization, then the columns that make up
!! the wind file are interpolated to the time requested, and wind is calculated based on the location
!! in space.
!!
!! the file contains header information (rows that contain "!"), followed by numeric data stored in
!! 8 columns:   (1) Time                                  [s]
!!              (2) Horizontal wind speed       (V)       [m/s]
!!              (3) Wind direction              (Delta)   [deg]
!!              (4) Vertical wind speed         (VZ)      [m/s]
!!              (5) Horizontal linear shear     (HLinShr) [-]
!!              (6) Vertical power-law shear    (VShr)    [-]
!!              (7) Vertical linear shear       (VLinShr) [-]
!!              (8) Gust (horizontal) velocity  (VGust)   [m/s]
!!
!! The horizontal wind speed at (X, Y, Z) is then calculated using the interpolated columns by
!!   Vh = V * ( Z/RefHt ) ** VShr                                        ! power-law wind shear
!!      + V * HLinShr/RefWid * ( Y * COS(Delta) + X * SIN(Delta) )       ! horizontal linear shear
!!      + V * VLinShr/RefWid * ( Z-RefHt )                               ! vertical linear shear
!!      + VGust                                                          ! gust speed
!----------------------------------------------------------------------------------------------------
!! Feb 2013    v2.00.00         A. Platt
!!    -- updated to the new framework
!!    -- Note:  Jacobians are not included in this version.
!!
!! Feb 2015    v2.01.00         A. Platt
!!    -- Further updates to the new framework
!!    -- name change from 'hub-height wind files' to 'Uniform wind files'.
!!
!**********************************************************************************************************************************
! LICENSING
! Copyright (C) 2015  National Renewable Energy Laboratory
!
!    This file is part of InflowWind.
!
! Licensed under the Apache License, Version 2.0 (the "License");
! you may not use this file except in compliance with the License.
! You may obtain a copy of the License at
!
!     http://www.apache.org/licenses/LICENSE-2.0
!
! Unless required by applicable law or agreed to in writing, software
! distributed under the License is distributed on an "AS IS" BASIS,
! WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
! See the License for the specific language governing permissions and
! limitations under the License.
!
!**********************************************************************************************************************************
! File last committed: $Date: 2014-10-29 16:28:35 -0600 (Wed, 29 Oct 2014) $
! (File) Revision #: $Rev: 125 $
! URL: $HeadURL: https://windsvn.nrel.gov/InflowWind/branches/modularization2/Source/IfW_UniformWind.f90 $
!**********************************************************************************************************************************

   USE                                       NWTC_Library
   USE                                       IfW_UniformWind_Types

   IMPLICIT                                  NONE
   PRIVATE

   TYPE(ProgDesc),   PARAMETER               :: IfW_UniformWind_Ver = ProgDesc( 'IfW_UniformWind', 'v2.02.00', '02-Apr-2015' )

   PUBLIC                                    :: IfW_UniformWind_Init
   PUBLIC                                    :: IfW_UniformWind_End
   PUBLIC                                    :: IfW_UniformWind_CalcOutput

CONTAINS

!====================================================================================================

!----------------------------------------------------------------------------------------------------
!> A subroutine to initialize the UniformWind module.  It reads the uniform wind file and stores the data in an
!! array to use later.  It requires an initial reference height (hub height) and width (rotor diameter),
!! both in meters, which are used to define the volume where wind velocities will be calculated.  This
!! information is necessary because of the way the shears are defined.
!!
!! @note    This routine does not conform to the framework.  The InputType has been replaced with just
!!          the PositionXYZ array.
!! @date    16-Apr-2013 - A. Platt, NREL.  Converted to modular framework. Modified for NWTC_Library 2.0
!----------------------------------------------------------------------------------------------------
SUBROUTINE IfW_UniformWind_Init(InitData, PositionXYZ, ParamData, OtherStates, OutData, Interval, InitOutData, ErrStat, ErrMsg)


   IMPLICIT                                                       NONE

   CHARACTER(*),           PARAMETER                           :: RoutineName="IfW_UniformWind_Init"


      ! Passed Variables
   TYPE(IfW_UniformWind_InitInputType),         INTENT(IN   )  :: InitData          ! Input data for initialization
   REAL(ReKi),       ALLOCATABLE,               INTENT(INOUT)  :: PositionXYZ(:,:)  ! Array of positions to find wind speed at
   TYPE(IfW_UniformWind_ParameterType),         INTENT(  OUT)  :: ParamData         ! Parameters
   TYPE(IfW_UniformWind_OtherStateType),        INTENT(  OUT)  :: OtherStates       ! Other State data   (storage for the main data)
   TYPE(IfW_UniformWind_OutputType),            INTENT(  OUT)  :: OutData           ! Initial output
   TYPE(IfW_UniformWind_InitOutputType),        INTENT(  OUT)  :: InitOutData       ! Initial output

   REAL(DbKi),                                  INTENT(IN   )  :: Interval          ! We don't change this.



      ! Error handling
   INTEGER(IntKi),                              INTENT(  OUT)  :: ErrStat           ! determines if an error has been encountered
   CHARACTER(*),                                INTENT(  OUT)  :: ErrMsg            ! A message about the error

      ! local variables

   INTEGER(IntKi),            PARAMETER                        :: NumCols = 8       ! Number of columns in the Uniform file
   REAL(ReKi)                                                  :: TmpData(NumCols)  ! Temp variable for reading all columns from a line
   REAL(ReKi)                                                  :: DelDiff           ! Temp variable for storing the direction difference

   INTEGER(IntKi)                                              :: UnitWind     ! Unit number for the InflowWind input file
   INTEGER(IntKi)                                              :: I
   INTEGER(IntKi)                                              :: NumComments
   INTEGER(IntKi)                                              :: ILine             ! Counts the line number in the file
   INTEGER(IntKi),            PARAMETER                        :: MaxTries = 100
   CHARACTER(1024)                                             :: Line              ! Temp variable for reading whole line from file

      ! Temporary variables for error handling
   INTEGER(IntKi)                                              :: TmpErrStat        ! Temp variable for the error status
   CHARACTER(ErrMsgLen)                                        :: TmpErrMsg      ! temporary error message


      !-------------------------------------------------------------------------------------------------
      ! Set the Error handling variables
      !-------------------------------------------------------------------------------------------------

   ErrStat     = ErrID_None
   ErrMsg      = ""

   TmpErrStat  = ErrID_None
   TmpErrMsg   = ""


      ! Check that the PositionXYZ array has been allocated.  The OutData%Velocity does not need to be allocated yet.
   IF ( .NOT. ALLOCATED(PositionXYZ) ) THEN
      CALL SetErrStat(ErrID_Fatal,' Programming error: The PositionXYZ array has not been allocated prior to call to '//RoutineName//'.',   &
                  ErrStat,ErrMsg,'')
   ENDIF

   IF ( ErrStat >= AbortErrLev ) RETURN


      ! Check that the PositionXYZ and OutData%Velocity arrays are the same size.
   IF ( ALLOCATED(OutData%Velocity) .AND. & 
        ( (SIZE( PositionXYZ, DIM = 1 ) /= SIZE( OutData%Velocity, DIM = 1 )) .OR. &
          (SIZE( PositionXYZ, DIM = 2 ) /= SIZE( OutData%Velocity, DIM = 2 ))      )  ) THEN
      CALL SetErrStat(ErrID_Fatal,' Programming error: Different number of XYZ coordinates and expected output velocities.', &
                  ErrStat,ErrMsg,RoutineName)
      RETURN
   ENDIF




      !-------------------------------------------------------------------------------------------------
      ! Check that it's not already initialized
      !-------------------------------------------------------------------------------------------------

   IF ( OtherStates%TimeIndex /= 0 ) THEN
      CALL SetErrStat(ErrID_Warn,' UniformWind has already been initialized.',ErrStat,ErrMsg,RoutineName)
      RETURN
   END IF


      ! Get a unit number to use

   CALL GetNewUnit(UnitWind, TmpErrStat, TmpErrMsg)
   CALL SetErrStat(TmpErrStat,TmpErrMsg,ErrStat,ErrMsg,RoutineName)
   IF (ErrStat >= AbortErrLev) RETURN


      !-------------------------------------------------------------------------------------------------
      ! Copy things from the InitData to the ParamData
      !-------------------------------------------------------------------------------------------------

   ParamData%RefHt            =  InitData%ReferenceHeight
   ParamData%RefLength        =  InitData%RefLength
   ParamData%WindFileName     =  InitData%WindFileName


      !-------------------------------------------------------------------------------------------------
      ! Open the file for reading
      !-------------------------------------------------------------------------------------------------

   CALL OpenFInpFile (UnitWind, TRIM(InitData%WindFileName), TmpErrStat, TmpErrMsg)
   CALL SetErrStat(TmpErrStat,TmpErrMsg,ErrStat,ErrMsg,RoutineName)
   IF ( ErrStat >= AbortErrLev ) RETURN


      !-------------------------------------------------------------------------------------------------
      ! Find the number of comment lines
      !-------------------------------------------------------------------------------------------------

   LINE = '!'                          ! Initialize the line for the DO WHILE LOOP
   NumComments = -1

   DO WHILE ( (INDEX( LINE, '!' ) > 0) .OR. (INDEX( LINE, '#' ) > 0) .OR. (INDEX( LINE, '%' ) > 0) ) ! Lines containing "!" are treated as comment lines
      NumComments = NumComments + 1

      READ(UnitWind,'( A )',IOSTAT=TmpErrStat) LINE

      IF ( TmpErrStat /=0 ) THEN
         CALL SetErrStat(ErrID_Fatal,' Error reading from uniform wind file on line '//TRIM(Num2LStr(NumComments))//'.',   &
               ErrStat, ErrMsg, RoutineName)
         CLOSE(UnitWind)
         RETURN
      END IF

   END DO !WHILE


      !-------------------------------------------------------------------------------------------------
      ! Find the number of data lines
      !-------------------------------------------------------------------------------------------------

   ParamData%NumDataLines = 0

   READ(LINE,*,IOSTAT=TmpErrStat) ( TmpData(I), I=1,NumCols )

   DO WHILE (TmpErrStat == ErrID_None)  ! read the rest of the file (until an error occurs)
      ParamData%NumDataLines = ParamData%NumDataLines + 1

      READ(UnitWind,*,IOSTAT=TmpErrStat) ( TmpData(I), I=1,NumCols )

   END DO !WHILE


   IF (ParamData%NumDataLines < 1) THEN
      TmpErrMsg=  ' Error reading data from Uniform wind file on line '// &
                  TRIM(Num2LStr(1+NumComments))//'.'
      CALL SetErrStat(ErrID_Fatal,TmpErrMsg,ErrStat,ErrMsg,RoutineName)
      CLOSE(UnitWind)
      RETURN
   END IF


      !-------------------------------------------------------------------------------------------------
      ! Allocate arrays for the uniform wind data
      !-------------------------------------------------------------------------------------------------
      ! BJJ note: If the subroutine AllocAry() is called, the CVF compiler with A2AD does not work
      !   properly.  The arrays are not properly read even though they've been allocated.
      ! ADP note: the above note may or may not apply after conversion to the modular framework in 2013
      !-------------------------------------------------------------------------------------------------

   IF (.NOT. ALLOCATED(ParamData%Tdata) ) THEN
      CALL AllocAry( ParamData%Tdata, ParamData%NumDataLines, 'Uniform wind time', TmpErrStat, TmpErrMsg )
      CALL SetErrStat(TmpErrStat,TmpErrMsg,ErrStat,ErrMsg,RoutineName)
      IF ( ErrStat >= AbortErrLev ) THEN
         CLOSE(UnitWind)
         RETURN
      ENDIF
   END IF

   IF (.NOT. ALLOCATED(ParamData%V) ) THEN
      CALL AllocAry( ParamData%V, ParamData%NumDataLines, 'Uniform wind horizontal wind speed', TmpErrStat, TmpErrMsg )
      CALL SetErrStat(TmpErrStat,TmpErrMsg,ErrStat,ErrMsg,RoutineName)
      IF ( ErrStat >= AbortErrLev ) THEN
         CLOSE(UnitWind)
         RETURN
      ENDIF
   END IF

   IF (.NOT. ALLOCATED(ParamData%Delta) ) THEN
      CALL AllocAry( ParamData%Delta, ParamData%NumDataLines, 'Uniform wind direction', TmpErrStat, TmpErrMsg )
      CALL SetErrStat(TmpErrStat,TmpErrMsg,ErrStat,ErrMsg,RoutineName)
      IF ( ErrStat >= AbortErrLev ) THEN
         CLOSE(UnitWind)
         RETURN
      ENDIF
   END IF

   IF (.NOT. ALLOCATED(ParamData%VZ) ) THEN
      CALL AllocAry( ParamData%VZ, ParamData%NumDataLines, 'Uniform vertical wind speed', TmpErrStat, TmpErrMsg )
      CALL SetErrStat(TmpErrStat,TmpErrMsg,ErrStat,ErrMsg,RoutineName)
      IF ( ErrStat >= AbortErrLev ) THEN
         CLOSE(UnitWind)
         RETURN
      ENDIF
   END IF

   IF (.NOT. ALLOCATED(ParamData%HShr) ) THEN
      CALL AllocAry( ParamData%HShr, ParamData%NumDataLines, 'Uniform horizontal linear shear', TmpErrStat, TmpErrMsg )
      CALL SetErrStat(TmpErrStat,TmpErrMsg,ErrStat,ErrMsg,RoutineName)
      IF ( ErrStat >= AbortErrLev ) THEN
         CLOSE(UnitWind)
         RETURN
      ENDIF
   END IF

   IF (.NOT. ALLOCATED(ParamData%VShr) ) THEN
      CALL AllocAry( ParamData%VShr, ParamData%NumDataLines, 'Uniform vertical power-law shear exponent', TmpErrStat, TmpErrMsg )
      CALL SetErrStat(TmpErrStat,TmpErrMsg,ErrStat,ErrMsg,RoutineName)
      IF ( ErrStat >= AbortErrLev ) THEN
         CLOSE(UnitWind)
         RETURN
      ENDIF
   END IF

   IF (.NOT. ALLOCATED(ParamData%VLinShr) ) THEN
      CALL AllocAry( ParamData%VLinShr, ParamData%NumDataLines, 'Uniform vertical linear shear', TmpErrStat, TmpErrMsg )
      CALL SetErrStat(TmpErrStat,TmpErrMsg,ErrStat,ErrMsg,RoutineName)
      IF ( ErrStat >= AbortErrLev ) THEN
         CLOSE(UnitWind)
         RETURN
      ENDIF
   END IF

   IF (.NOT. ALLOCATED(ParamData%VGust) ) THEN
      CALL AllocAry( ParamData%VGust, ParamData%NumDataLines, 'Uniform gust velocity', TmpErrStat, TmpErrMsg )
      CALL SetErrStat(TmpErrStat,TmpErrMsg,ErrStat,ErrMsg,RoutineName)
      IF ( ErrStat >= AbortErrLev ) THEN
         CLOSE(UnitWind)
         RETURN
      ENDIF
   END IF


      !-------------------------------------------------------------------------------------------------
      ! Rewind the file (to the beginning) and skip the comment lines
      !-------------------------------------------------------------------------------------------------

   REWIND( UnitWind )

   DO I=1,NumComments
      CALL ReadCom( UnitWind, TRIM(InitData%WindFileName), 'Header line #'//TRIM(Num2LStr(I)), TmpErrStat, TmpErrMsg )
      CALL SetErrStat(TmpErrStat,TmpErrMsg,ErrStat,ErrMsg,RoutineName)
      IF ( ErrStat >= AbortErrLev ) THEN
         CLOSE(UnitWind)
         RETURN
      ENDIF
   END DO !I


      !-------------------------------------------------------------------------------------------------
      ! Read the data arrays
      !-------------------------------------------------------------------------------------------------

   DO I=1,ParamData%NumDataLines

      CALL ReadAry( UnitWind, TRIM(InitData%WindFileName), TmpData(1:NumCols), NumCols, 'TmpData', &
                'Data from uniform wind file line '//TRIM(Num2LStr(NumComments+I)), TmpErrStat, TmpErrMsg)
      CALL SetErrStat(TmpErrStat,'Error retrieving data from the uniform wind file line'//TRIM(Num2LStr(NumComments+I)),   &
            ErrStat,ErrMsg,RoutineName)
      IF ( ErrStat >= AbortErrLev ) THEN
         CLOSE(UnitWind)
         RETURN
      ENDIF

      ParamData%Tdata(  I) = TmpData(1)
      ParamData%V(      I) = TmpData(2)
      ParamData%Delta(  I) = TmpData(3)*D2R
      ParamData%VZ(     I) = TmpData(4)
      ParamData%HShr(   I) = TmpData(5)
      ParamData%VShr(   I) = TmpData(6)
      ParamData%VLinShr(I) = TmpData(7)
      ParamData%VGust(  I) = TmpData(8)

   END DO !I


      !-------------------------------------------------------------------------------------------------
      ! Make sure the wind direction isn't jumping more than 180 degrees between any 2 consecutive
      ! input times.  (Avoids interpolation errors with modular arithemetic.)
      !-------------------------------------------------------------------------------------------------

   DO I=2,ParamData%NumDataLines

      ILine = 1

      DO WHILE ( ILine < MaxTries )

         DelDiff = ( ParamData%Delta(I) - ParamData%Delta(I-1) )

         IF ( ABS( DelDiff ) < Pi ) EXIT  ! exit inner loop

         ParamData%Delta(I) = ParamData%Delta(I) - SIGN( TwoPi, DelDiff )

         ILine = ILine + 1

      END DO

      IF ( ILine >= MaxTries ) THEN
         TmpErrMsg= ' Error calculating wind direction from uniform wind file. ParamData%Delta(' &
               // TRIM(Num2LStr(I  )) // ') = ' // TRIM(Num2LStr(ParamData%Delta(I))) // '; ParamData%Delta(' &
               // TRIM(Num2LStr(I+1)) // ') = ' // TRIM(Num2LStr(ParamData%Delta(I+1)))
         CALL SetErrStat(ErrID_Fatal,TmpErrMsg,ErrStat,ErrMsg,RoutineName)
      END IF


   END DO !I



      !-------------------------------------------------------------------------------------------------
      ! Find out information on the timesteps and range
      !-------------------------------------------------------------------------------------------------

      ! Uniform timesteps
   IF ( ParamData%NumDataLines > 3 ) THEN

      InitOutData%WindFileConstantDT =  .TRUE.
      InitOutData%WindFileDT        = ParamData%Tdata(2) - ParamData%Tdata(1)

      DO I=3,ParamData%NumDataLines

         IF ( .NOT. EqualRealNos( (ParamData%Tdata(I  ) - ParamData%Tdata(I-1) ), REAL(InitOutData%WindFileDT,ReKi )) ) THEN
            InitOutData%WindFileConstantDT  =  .FALSE.
            EXIT
         END IF

      END DO !I

   ELSE

         ! There aren't enough points to check, so report that the timesteps are not uniform
      InitOutData%WindFileConstantDT =  .FALSE.
      InitOutData%WindFileDT        =  0.0_ReKi

   END IF


      ! Time range
   InitOutData%WindFileTRange(1)    =  ParamData%Tdata(1)
   InitOutData%WindFileTRange(2)    =  ParamData%Tdata(ParamData%NumDataLines)

      ! Number of timesteps
   InitOutData%WindFileNumTSteps    =  ParamData%NumDataLines



      !-------------------------------------------------------------------------------------------------
      ! Close the file
      !-------------------------------------------------------------------------------------------------

   CLOSE( UnitWind )


      !-------------------------------------------------------------------------------------------------
      ! Print warnings and messages
      !-------------------------------------------------------------------------------------------------
   CALL WrScr( '   Processed '//TRIM( Num2LStr( ParamData%NumDataLines ) )//' records of uniform wind data from '''// &
               TRIM(ADJUSTL(InitData%WindFileName))//'''')


   IF ( ParamData%Tdata(1) > 0.0 ) THEN
      TmpErrMsg=  'The uniform wind file : "'//TRIM(ADJUSTL(InitData%WindFileName))// &
                  '" starts at a time '//'greater than zero. Interpolation errors may result.'
      CALL SetErrStat(ErrID_Warn,TmpErrMsg,ErrStat,ErrMsg,RoutineName)
   ENDIF

   IF ( ParamData%NumDataLines == 1 ) THEN
      TmpErrMsg=  ' Only 1 line in uniform wind file. Steady, horizontal wind speed at the hub height is '// &
                  TRIM(Num2LStr(ParamData%V(1)))//' m/s.'
      CALL SetErrStat(ErrID_Info,TmpErrMsg,ErrStat,ErrMsg,RoutineName)
   END IF



      !-------------------------------------------------------------------------------------------------
      ! Write to the summary file
      !-------------------------------------------------------------------------------------------------

   IF ( InitData%SumFileUnit > 0 ) THEN
      WRITE(InitData%SumFileUnit,'(A)',        IOSTAT=TmpErrStat)
      WRITE(InitData%SumFileUnit,'(A)',        IOSTAT=TmpErrStat)    'Uniform wind.  Module '//TRIM(IfW_UniformWind_Ver%Name)//  &
                                                                                 ' '//TRIM(IfW_UniformWind_Ver%Ver)
      WRITE(InitData%SumFileUnit,'(A)',        IOSTAT=TmpErrStat)    '     FileName:                    '//TRIM(ParamData%WindFileName)
      WRITE(InitData%SumFileUnit,'(A34,G12.4)',IOSTAT=TmpErrStat)    '     Reference height (m):        ',ParamData%RefHt
      WRITE(InitData%SumFileUnit,'(A34,G12.4)',IOSTAT=TmpErrStat)    '     Reference length (m):        ',ParamData%RefLength
      WRITE(InitData%SumFileUnit,'(A32,I8)',   IOSTAT=TmpErrStat)    '     Number of data lines:        ',ParamData%NumDataLines
      WRITE(InitData%SumFileUnit,'(A)',        IOSTAT=TmpErrStat)    '     Time range (s):              [ '// &
                  TRIM(Num2LStr(InitOutData%WindFileTRange(1)))//' : '//TRIM(Num2LStr(InitOutData%WindFileTRange(2)))//' ]'

         ! We are assuming that if the last line was written ok, then all of them were.
      IF (TmpErrStat /= 0_IntKi) THEN
         CALL SetErrStat(ErrID_Fatal,'Error writing to summary file.',ErrStat,ErrMsg,RoutineName)
         RETURN
      ENDIF   
   ENDIF 



      !-------------------------------------------------------------------------------------------------
      ! Set the initial index into the time array (it indicates that we've initialized the module, too)
      ! and initialize the spatial scaling for the wind calculations
      !-------------------------------------------------------------------------------------------------

   OtherStates%TimeIndex   = 1


      !-------------------------------------------------------------------------------------------------
      ! Set the InitOutput information
      !-------------------------------------------------------------------------------------------------

   InitOutdata%Ver         = IfW_UniformWind_Ver


   RETURN

END SUBROUTINE IfW_UniformWind_Init

!====================================================================================================

!-------------------------------------------------------------------------------------------------
!>  This routine and its subroutines calculate the wind velocity at a set of points given in
!!  PositionXYZ.  The UVW velocities are returned in OutData%Velocity
!!
!! @note  This routine does not satisfy the Modular framework.  The InputType is not used, rather
!!          an array of points is passed in. 
!! @date  16-Apr-2013 - A. Platt, NREL.  Converted to modular framework. Modified for NWTC_Library 2.0
!-------------------------------------------------------------------------------------------------
SUBROUTINE IfW_UniformWind_CalcOutput(Time, PositionXYZ, ParamData, OtherStates, OutData, ErrStat, ErrMsg)

   IMPLICIT                                                       NONE

   CHARACTER(*),           PARAMETER                           :: RoutineName="IfW_UniformWind_CalcOutput"


      ! Passed Variables
   REAL(DbKi),                                  INTENT(IN   )  :: Time              ! time from the start of the simulation
   REAL(ReKi), ALLOCATABLE,                     INTENT(IN   )  :: PositionXYZ(:,:)  ! Array of XYZ coordinates, 3xN
   TYPE(IfW_UniformWind_ParameterType),         INTENT(IN   )  :: ParamData         ! Parameters
   TYPE(IfW_UniformWind_OtherStateType),        INTENT(INOUT)  :: OtherStates       ! Other State data   (storage for the main data)
   TYPE(IfW_UniformWind_OutputType),            INTENT(INOUT)  :: OutData           ! Initial output     (Set to INOUT so that array does not get deallocated)

      ! Error handling
   INTEGER(IntKi),                              INTENT(  OUT)  :: ErrStat           ! error status
   CHARACTER(*),                                INTENT(  OUT)  :: ErrMsg            ! The error message


      ! local variables
   INTEGER(IntKi)                                              :: NumPoints      ! Number of points specified by the PositionXYZ array

      ! local counters
   INTEGER(IntKi)                                              :: PointNum       ! a loop counter for the current point

      ! temporary variables
   INTEGER(IntKi)                                              :: TmpErrStat     ! temporary error status
   CHARACTER(ErrMsgLen)                                        :: TmpErrMsg      ! temporary error message



      !-------------------------------------------------------------------------------------------------
      ! Initialize some things
      !-------------------------------------------------------------------------------------------------

   ErrStat     = ErrID_None
   ErrMsg      = ""
   TmpErrStat  = ErrID_None
   TmpErrMsg   = ""

      ! The array is transposed so that the number of points is the second index, x/y/z is the first.
      ! This is just in case we only have a single point, the SIZE command returns the correct number of points.
   NumPoints   =  SIZE(PositionXYZ,DIM=2)

      ! Allocate Velocity output array
   IF ( .NOT. ALLOCATED(OutData%Velocity)) THEN
      CALL AllocAry( OutData%Velocity, 3, NumPoints, "Velocity matrix at timestep", TmpErrStat, TmpErrMsg )
      CALL SetErrStat(TmpErrStat," Could not allocate the output velocity array.",   &
         ErrStat,ErrMsg,RoutineName)
      IF ( ErrStat >= AbortErrLev ) RETURN
   ELSEIF ( SIZE(OutData%Velocity,DIM=2) /= NumPoints ) THEN
      CALL SetErrStat( ErrID_Fatal," Programming error: Position and Velocity arrays are not sized the same.",  &
         ErrStat, ErrMsg, RoutineName)
      RETURN
   ENDIF


      ! Step through all the positions and get the velocities
   DO PointNum = 1, NumPoints

         ! Calculate the velocity for the position
      OutData%Velocity(:,PointNum) = GetWindSpeed(Time, PositionXYZ(:,PointNum), ParamData, OtherStates, TmpErrStat, TmpErrMsg)

         ! Error handling
      CALL SetErrStat(TmpErrStat,TmpErrMsg,ErrStat,ErrMsg,RoutineName)
      IF (ErrStat >= AbortErrLev) THEN
         TmpErrMsg=  " Error calculating the wind speed at position ("//   &
                     TRIM(Num2LStr(PositionXYZ(1,PointNum)))//", "// &
                     TRIM(Num2LStr(PositionXYZ(2,PointNum)))//", "// &
                     TRIM(Num2LStr(PositionXYZ(3,PointNum)))//") in the wind-file coordinates"
         CALL SetErrStat(TmpErrStat,TmpErrMsg,ErrStat,ErrMsg,RoutineName)
         RETURN
      ENDIF

   ENDDO



      ! DiskVel term -- this represents the average across the disk -- sort of.  This changes for AeroDyn 15
   OutData%DiskVel   =  WindInf_ADhack_diskVel(Time, ParamData, OtherStates, TmpErrStat, TmpErrMsg)

   RETURN

CONTAINS
   !+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
   FUNCTION GetWindSpeed(Time,   InputPosition,   ParamData,     OtherStates,   ErrStat, ErrMsg)
   !----------------------------------------------------------------------------------------------------
   ! This subroutine linearly interpolates the columns in the uniform input file to get the values for
   ! the requested time, then uses the interpolated values to calclate the wind speed at a point
   ! in space represented by InputPosition.
   !
   !  16-Apr-2013 - A. Platt, NREL.  Converted to modular framework. Modified for NWTC_Library 2.0
   !----------------------------------------------------------------------------------------------------

         ! Passed Variables
      REAL(DbKi),                            INTENT(IN   )  :: Time              ! time from the start of the simulation
      REAL(ReKi),                            INTENT(IN   )  :: InputPosition(3)  ! input information: positions X,Y,Z
      TYPE(IfW_UniformWind_ParameterType),   INTENT(IN   )  :: ParamData         ! Parameters
      TYPE(IfW_UniformWind_OtherStateType),  INTENT(INOUT)  :: OtherStates       ! Other State data   (storage for the main data)

      INTEGER(IntKi),                        INTENT(  OUT)  :: ErrStat           ! error status
      CHARACTER(*),                          INTENT(  OUT)  :: ErrMsg            ! The error message

         ! Returned variables
      REAL(ReKi)                                            :: GetWindSpeed(3)   ! return velocities (U,V,W)


         ! Local Variables
      REAL(ReKi)                                            :: CosDelta          ! cosine of Delta_tmp
      REAL(ReKi)                                            :: Delta_tmp         ! interpolated Delta   at input TIME
      REAL(ReKi)                                            :: HShr_tmp          ! interpolated HShr    at input TIME
      REAL(ReKi)                                            :: P                 ! temporary storage for slope (in time) used in linear interpolation
      REAL(ReKi)                                            :: SinDelta          ! sine of Delta_tmp
      REAL(ReKi)                                            :: V_tmp             ! interpolated V       at input TIME
      REAL(ReKi)                                            :: VGust_tmp         ! interpolated VGust   at input TIME
      REAL(ReKi)                                            :: VLinShr_tmp       ! interpolated VLinShr at input TIME
      REAL(ReKi)                                            :: VShr_tmp          ! interpolated VShr    at input TIME
      REAL(ReKi)                                            :: VZ_tmp            ! interpolated VZ      at input TIME
      REAL(ReKi)                                            :: V1                ! temporary storage for horizontal velocity


      ErrStat  =  ErrID_None
      ErrMsg   =  ""

      !-------------------------------------------------------------------------------------------------
      ! verify the module was initialized first
      !-------------------------------------------------------------------------------------------------

      IF ( OtherStates%TimeIndex == 0 ) THEN
         CALL SetErrStat(ErrID_Fatal,' Error: Call UniformWind_Init() before getting wind speed.',ErrStat,ErrMsg,'')
         RETURN
      END IF

      !-------------------------------------------------------------------------------------------------
      ! Linearly interpolate in time (or used nearest-neighbor to extrapolate)
      ! (compare with NWTC_Num.f90\InterpStpReal)
      !-------------------------------------------------------------------------------------------------

         ! Let's check the limits.
      IF ( Time <= ParamData%Tdata(1) .OR. ParamData%NumDataLines == 1 )  THEN

         OtherStates%TimeIndex      = 1
         V_tmp         = ParamData%V      (1)
         Delta_tmp     = ParamData%Delta  (1)
         VZ_tmp        = ParamData%VZ     (1)
         HShr_tmp      = ParamData%HShr   (1)
         VShr_tmp      = ParamData%VShr   (1)
         VLinShr_tmp   = ParamData%VLinShr(1)
         VGust_tmp     = ParamData%VGust  (1)


      ELSE IF ( Time >= ParamData%Tdata(ParamData%NumDataLines) )  THEN

         OtherStates%TimeIndex      = ParamData%NumDataLines - 1
         V_tmp         = ParamData%V      (ParamData%NumDataLines)
         Delta_tmp     = ParamData%Delta  (ParamData%NumDataLines)
         VZ_tmp        = ParamData%VZ     (ParamData%NumDataLines)
         HShr_tmp      = ParamData%HShr   (ParamData%NumDataLines)
         VShr_tmp      = ParamData%VShr   (ParamData%NumDataLines)
         VLinShr_tmp   = ParamData%VLinShr(ParamData%NumDataLines)
         VGust_tmp     = ParamData%VGust  (ParamData%NumDataLines)

      ELSE

            ! Let's interpolate!  Linear interpolation.
         OtherStates%TimeIndex = MAX( MIN( OtherStates%TimeIndex, ParamData%NumDataLines-1 ), 1 )

         DO

            IF ( Time < ParamData%Tdata(OtherStates%TimeIndex) )  THEN

               OtherStates%TimeIndex = OtherStates%TimeIndex - 1

            ELSE IF ( Time >= ParamData%Tdata(OtherStates%TimeIndex+1) )  THEN

               OtherStates%TimeIndex = OtherStates%TimeIndex + 1

            ELSE
               P           = ( Time - ParamData%Tdata(OtherStates%TimeIndex) )/( ParamData%Tdata(OtherStates%TimeIndex+1) &
                              - ParamData%Tdata(OtherStates%TimeIndex) )
               V_tmp       = ( ParamData%V(      OtherStates%TimeIndex+1) - ParamData%V(      OtherStates%TimeIndex) )*P  &
                              + ParamData%V(      OtherStates%TimeIndex)
               Delta_tmp   = ( ParamData%Delta(  OtherStates%TimeIndex+1) - ParamData%Delta(  OtherStates%TimeIndex) )*P  &
                              + ParamData%Delta(  OtherStates%TimeIndex)
               VZ_tmp      = ( ParamData%VZ(     OtherStates%TimeIndex+1) - ParamData%VZ(     OtherStates%TimeIndex) )*P  &
                              + ParamData%VZ(     OtherStates%TimeIndex)
               HShr_tmp    = ( ParamData%HShr(   OtherStates%TimeIndex+1) - ParamData%HShr(   OtherStates%TimeIndex) )*P  &
                              + ParamData%HShr(   OtherStates%TimeIndex)
               VShr_tmp    = ( ParamData%VShr(   OtherStates%TimeIndex+1) - ParamData%VShr(   OtherStates%TimeIndex) )*P  &
                              + ParamData%VShr(   OtherStates%TimeIndex)
               VLinShr_tmp = ( ParamData%VLinShr(OtherStates%TimeIndex+1) - ParamData%VLinShr(OtherStates%TimeIndex) )*P  &
                              + ParamData%VLinShr(OtherStates%TimeIndex)
               VGust_tmp   = ( ParamData%VGust(  OtherStates%TimeIndex+1) - ParamData%VGust(  OtherStates%TimeIndex) )*P  &
                              + ParamData%VGust(  OtherStates%TimeIndex)
               EXIT

            END IF

         END DO

      END IF


      !-------------------------------------------------------------------------------------------------
      ! calculate the wind speed at this time
      !-------------------------------------------------------------------------------------------------

      if ( InputPosition(3) < 0.0_ReKi ) then
         call SetErrStat(ErrID_Fatal,'Height must not be negative.',ErrStat,ErrMsg,'GetWindSpeed')
      end if
      
      
      CosDelta = COS( Delta_tmp )
      SinDelta = SIN( Delta_tmp )
      V1 = V_tmp * ( ( InputPosition(3)/ParamData%RefHt ) ** VShr_tmp &                                  ! power-law wind shear
           + ( HShr_tmp   * ( InputPosition(2) * CosDelta + InputPosition(1) * SinDelta ) &              ! horizontal linear shear
           +  VLinShr_tmp * ( InputPosition(3)-ParamData%RefHt ) )/ParamData%RefLength  ) &              ! vertical linear shear
           + VGust_tmp                                                                                   ! gust speed
      GetWindSpeed(1) =  V1 * CosDelta
      GetWindSpeed(2) = -V1 * SinDelta
      GetWindSpeed(3) =  VZ_tmp


      RETURN

   END FUNCTION GetWindSpeed


   FUNCTION WindInf_ADhack_diskVel( Time,ParamData, OtherStates,ErrStat, ErrMsg )
   ! This function should be deleted ASAP.  Its purpose is to reproduce results of AeroDyn 12.57;
   ! when a consensus on the definition of "average velocity" is determined, this function will be
   ! removed.
   !----------------------------------------------------------------------------------------------------
   
         ! Passed variables
   
      REAL(DbKi),                            INTENT(IN   )  :: Time              !< Time
      TYPE(IfW_UniformWind_ParameterType),   INTENT(IN   )  :: ParamData         ! Parameters
      TYPE(IfW_UniformWind_OtherStateType),  INTENT(INOUT)  :: OtherStates       ! Other State data   (storage for the main data)
   
      INTEGER(IntKi),                        INTENT(  OUT)  :: ErrStat
      CHARACTER(*),                          INTENT(  OUT)  :: ErrMsg
   
         ! Function definition
      REAL(ReKi)                    :: WindInf_ADhack_diskVel(3)
   
         ! Local variables
      REAL(ReKi)                    :: Delta_tmp            ! interpolated Delta   at input TIME
      REAL(ReKi)                    :: P                    ! temporary storage for slope (in time) used in linear interpolation
      REAL(ReKi)                    :: V_tmp                ! interpolated V       at input TIME
      REAL(ReKi)                    :: VZ_tmp               ! interpolated VZ      at input TIME
   
   
      
      ErrStat = ErrID_None
      ErrMsg  = ""
   
         !-------------------------------------------------------------------------------------------------
         ! Linearly interpolate in time (or use nearest-neighbor to extrapolate)
         ! (compare with NWTC_Num.f90\InterpStpReal)
         !-------------------------------------------------------------------------------------------------


            ! Let's check the limits.
         IF ( Time <= ParamData%Tdata(1) .OR. ParamData%NumDataLines == 1 )  THEN

            OtherStates%TimeIndex      = 1
            V_tmp         = ParamData%V      (1)
            Delta_tmp     = ParamData%Delta  (1)
            VZ_tmp        = ParamData%VZ     (1)

         ELSE IF ( Time >= ParamData%Tdata(ParamData%NumDataLines) )  THEN

            OtherStates%TimeIndex = ParamData%NumDataLines - 1
            V_tmp                 = ParamData%V      (ParamData%NumDataLines)
            Delta_tmp             = ParamData%Delta  (ParamData%NumDataLines)
            VZ_tmp                = ParamData%VZ     (ParamData%NumDataLines)

         ELSE

              ! Let's interpolate!

            OtherStates%TimeIndex = MAX( MIN( OtherStates%TimeIndex, ParamData%NumDataLines-1 ), 1 )

            DO

               IF ( Time < ParamData%Tdata(OtherStates%TimeIndex) )  THEN

                  OtherStates%TimeIndex = OtherStates%TimeIndex - 1

               ELSE IF ( Time >= ParamData%Tdata(OtherStates%TimeIndex+1) )  THEN

                  OtherStates%TimeIndex = OtherStates%TimeIndex + 1

               ELSE
                  P           =  ( Time - ParamData%Tdata(OtherStates%TimeIndex) )/     &
                                 ( ParamData%Tdata(OtherStates%TimeIndex+1)             &
                                 - ParamData%Tdata(OtherStates%TimeIndex) )
                  V_tmp       =  ( ParamData%V(      OtherStates%TimeIndex+1)           &
                                 - ParamData%V(      OtherStates%TimeIndex) )*P         &
                                 + ParamData%V(      OtherStates%TimeIndex)
                  Delta_tmp   =  ( ParamData%Delta(  OtherStates%TimeIndex+1)           &
                                 - ParamData%Delta(  OtherStates%TimeIndex) )*P         &
                                 + ParamData%Delta(  OtherStates%TimeIndex)
                  VZ_tmp      =  ( ParamData%VZ(     OtherStates%TimeIndex+1)           &
                                 - ParamData%VZ(     OtherStates%TimeIndex) )*P  &
                                 + ParamData%VZ(     OtherStates%TimeIndex)
                  EXIT

               END IF

            END DO

         END IF

      !-------------------------------------------------------------------------------------------------
      ! calculate the wind speed at this time
      !-------------------------------------------------------------------------------------------------
   
         WindInf_ADhack_diskVel(1) =  V_tmp * COS( Delta_tmp )
         WindInf_ADhack_diskVel(2) = -V_tmp * SIN( Delta_tmp )
         WindInf_ADhack_diskVel(3) =  VZ_tmp
   
   
   
      RETURN

   END FUNCTION WindInf_ADhack_diskVel





END SUBROUTINE IfW_UniformWind_CalcOutput

!====================================================================================================

!----------------------------------------------------------------------------------------------------
!>  This routine closes any open files and clears all data stored in UniformWind derived Types
!!
!! @note  This routine does not satisfy the Modular framework.  The InputType is not used, rather
!!          an array of points is passed in. 
!! @date:  16-Apr-2013 - A. Platt, NREL.  Converted to modular framework. Modified for NWTC_Library 2.0
!----------------------------------------------------------------------------------------------------
SUBROUTINE IfW_UniformWind_End( PositionXYZ, ParamData, OtherStates, OutData, ErrStat, ErrMsg)


   IMPLICIT                                                       NONE

   CHARACTER(*),           PARAMETER                           :: RoutineName="IfW_UniformWind_End"


      ! Passed Variables
   REAL(ReKi),    ALLOCATABLE,                  INTENT(INOUT)  :: PositionXYZ(:,:)  ! Array of XYZ positions to find wind speeds at
   TYPE(IfW_UniformWind_ParameterType),         INTENT(INOUT)  :: ParamData         ! Parameters
   TYPE(IfW_UniformWind_OtherStateType),        INTENT(INOUT)  :: OtherStates       ! Other State data   (storage for the main data)
   TYPE(IfW_UniformWind_OutputType),            INTENT(INOUT)  :: OutData           ! Initial output


      ! Error Handling
   INTEGER(IntKi),                              INTENT(  OUT)  :: ErrStat           ! determines if an error has been encountered
   CHARACTER(*),                                INTENT(  OUT)  :: ErrMsg            ! Message about errors


      ! Local Variables
   INTEGER(IntKi)                                              :: TmpErrStat        ! temporary error status
   CHARACTER(ErrMsgLen)                                        :: TmpErrMsg         ! temporary error message


      !-=- Initialize the routine -=-

   ErrMsg   = ''
   ErrStat  = ErrID_None


      ! Destroy the position array

   IF (ALLOCATED(PositionXYZ))      DEALLOCATE(PositionXYZ)


      ! Destroy parameter data

   CALL IfW_UniformWind_DestroyParam(       ParamData,     TmpErrStat, TmpErrMsg )
   CALL SetErrStat( TmpErrStat, TmpErrMsg, ErrStat, ErrMsg, RoutineName )


      ! Destroy the state data

   CALL IfW_UniformWind_DestroyOtherState(  OtherStates,   TmpErrStat, TmpErrMsg )
   CALL SetErrStat( TmpErrStat, TmpErrMsg, ErrStat, ErrMsg, RoutineName )


      ! Destroy the output data

   CALL IfW_UniformWind_DestroyOutput(      OutData,       TmpErrStat, TmpErrMsg )
   CALL SetErrStat( TmpErrStat, TmpErrMsg, ErrStat, ErrMsg, RoutineName )


      ! reset time index so we know the module is no longer initialized

   OtherStates%TimeIndex   = 0

END SUBROUTINE IfW_UniformWind_End


!====================================================================================================
!====================================================================================================
!====================================================================================================
END MODULE IfW_UniformWind
