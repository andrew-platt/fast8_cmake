!**********************************************************************************************************************************
! The FAST_Prog.f90, FAST_IO.f90, and FAST_Mods.f90 make up the FAST glue code in the FAST Modularization Framework.
!..................................................................................................................................
! LICENSING
! Copyright (C) 2013-2015  National Renewable Energy Laboratory
!
!    This file is part of FAST.
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
! File last committed: $Date: 2015-06-15 12:51:05 -0600 (Mon, 15 Jun 2015) $
! (File) Revision #: $Rev: 1035 $
! URL: $HeadURL: https://windsvn.nrel.gov/FAST/branches/BJonkman/Source/FAST_Prog.f90 $
!**********************************************************************************************************************************
PROGRAM FAST
! This program models 2- or 3-bladed turbines of a standard configuration.
!
! noted compilation switches:
!   SOLVE_OPTION_1_BEFORE_2 (uses a different order for solving input-output relationships)
!   OUTPUT_ADDEDMASS        (outputs a file called "<RootName>.AddedMass" that contains HydroDyn's added-mass matrix.
!   OUTPUT_JACOBIAN
!   FPE_TRAP_ENABLED        (use with gfortran when checking for floating point exceptions)
!   DOUBLE_PRECISION        (compile in double precision)
!.................................................................................................


USE FAST_Subs   ! all of the ModuleName and ModuleName_types modules are inherited from FAST_IO_Subs
                       
IMPLICIT  NONE
   
   ! Local parameters:
REAL(DbKi),             PARAMETER     :: t_initial = 0.0_DbKi                    ! Initial time
INTEGER(IntKi),         PARAMETER     :: NumTurbines = 1
   
   ! Other/Misc variables
TYPE(FAST_TurbineType)                :: Turbine(NumTurbines)                    ! Data for each turbine instance

INTEGER(IntKi)                        :: i_turb                                  ! current turbine number
INTEGER(IntKi)                        :: n_t_global                              ! simulation time step, loop counter for global (FAST) simulation
INTEGER(IntKi)                        :: ErrStat                                 ! Error status
CHARACTER(1024)                       :: ErrMsg                                  ! Error message

   ! data for restart:
CHARACTER(1024)                       :: CheckpointRoot                          ! Rootname of the checkpoint file
CHARACTER(20)                         :: FlagArg                                 ! flag argument from command line
INTEGER(IntKi)                        :: Restart_step                            ! step to start on (for restart) 


      !+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
      ! determine if this is a restart from checkpoint
      !+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   CALL NWTC_Init() ! open console for writing
   ProgName = 'FAST'
   CheckpointRoot = ""
   CALL CheckArgs( CheckpointRoot, ErrStat, Flag=FlagArg )  ! if ErrStat /= ErrID_None, we'll ignore and deal with the problem when we try to read the input file
      
   IF ( TRIM(FlagArg) == 'RESTART' ) THEN ! Restart from checkpoint file
      CALL FAST_RestoreFromCheckpoint_Tary(t_initial, Restart_step, Turbine, CheckpointRoot, ErrStat, ErrMsg  )
         CALL CheckError( ErrStat, ErrMsg, 'during restore from checkpoint'  )            
   ELSE
      Restart_step = 0
      
      DO i_turb = 1,NumTurbines
         !+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
         ! initialization
         !+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
         
         CALL FAST_InitializeAll_T( t_initial, i_turb, Turbine(i_turb), ErrStat, ErrMsg )     ! bjj: we need to get the input files for each turbine (not necessarially the same one)
         CALL CheckError( ErrStat, ErrMsg, 'during module initialization' )
                        
      !+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
      ! loose coupling
      !+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
      
         !...............................................................................................................................
         ! Initialization: (calculate outputs based on states at t=t_initial as well as guesses of inputs and constraint states)
         !...............................................................................................................................     
         CALL FAST_Solution0_T( Turbine(i_turb), ErrStat, ErrMsg )
         CALL CheckError( ErrStat, ErrMsg, 'during simulation initialization'  )
      
      END DO
   END IF
   

      
   !...............................................................................................................................
   ! Time Stepping:
   !...............................................................................................................................         
   
   DO n_t_global = Restart_step, Turbine(1)%p_FAST%n_TMax_m1 ! bjj: we have to make sure the n_TMax_m1 and n_ChkptTime are the same for all turbines or have some logic
            
      ! write checkpoint file if requested
      IF (mod(n_t_global, Turbine(1)%p_FAST%n_ChkptTime) == 0 .AND. Restart_step /= n_t_global) then
         CheckpointRoot = TRIM(Turbine(1)%p_FAST%OutFileRoot)//'.'//TRIM(Num2LStr(n_t_global))
         
         CALL FAST_CreateCheckpoint_Tary(t_initial, n_t_global, Turbine, CheckpointRoot, ErrStat, ErrMsg)
            IF(ErrStat >= AbortErrLev .and. AbortErrLev >= ErrID_Severe) THEN
               ErrStat = MIN(ErrStat,ErrID_Severe) ! We don't need to stop simulation execution on this error
               ErrMsg = TRIM(ErrMsg)//Newline//'WARNING: Checkpoint file could not be generated. Simulation continuing.'
            END IF
            CALL CheckError( ErrStat, ErrMsg  )
      END IF
      
      
      ! this takes data from n_t_global and gets values at n_t_global + 1
      DO i_turb = 1,NumTurbines
  
         CALL FAST_Solution_T( t_initial, n_t_global, Turbine(i_turb), ErrStat, ErrMsg )
            CALL CheckError( ErrStat, ErrMsg  )
                                    
      END DO

      
   END DO ! n_t_global
  
  
   !+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   !  Write simulation times and stop
   !+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   
   DO i_turb = 1,NumTurbines
      CALL ExitThisProgram_T( Turbine(i_turb), ErrID_None )
   END DO
   

CONTAINS
   !...............................................................................................................................
   SUBROUTINE CheckError(ErrID,Msg,ErrLocMsg)
   ! This subroutine sets the error message and level and cleans up if the error is >= AbortErrLev
   !...............................................................................................................................

         ! Passed arguments
      INTEGER(IntKi), INTENT(IN)           :: ErrID       ! The error identifier (ErrStat)
      CHARACTER(*),   INTENT(IN)           :: Msg         ! The error message (ErrMsg)
      CHARACTER(*),   INTENT(IN), OPTIONAL :: ErrLocMsg   ! an optional message describing the location of the error

      CHARACTER(1024)                      :: SimMsg      
      
      IF ( ErrID /= ErrID_None ) THEN
         CALL WrScr( NewLine//TRIM(Msg)//NewLine )
         IF ( ErrID >= AbortErrLev ) THEN
            
            IF (PRESENT(ErrLocMsg)) THEN
               SimMsg = ErrLocMsg
            ELSE
               SimMsg = 'at simulation time '//TRIM(Num2LStr(Turbine(1)%m_FAST%t_global))//' of '//TRIM(Num2LStr(Turbine(1)%p_FAST%TMax))//' seconds'
            END IF
            
            DO i_turb = 1,NumTurbines
               CALL ExitThisProgram_T( Turbine(i_turb), ErrID, SimMsg )
            END DO
                        
         END IF
         
      END IF


   END SUBROUTINE CheckError   
   !...............................................................................................................................
END PROGRAM FAST
!=======================================================================
