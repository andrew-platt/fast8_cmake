
cmake_minimum_required(VERSION 3.3.2)
project(FAST8 Fortran C CXX)

# Check for BLAS and LAPACK libraries
find_package(BLAS REQUIRED)
find_package(LAPACK REQUIRED)

# Set user selectable option to turn on/off double precision 
option(DOUBLE_PRECISION "Set single or double precision" off)
option(LIB_LOAD "Control library loading" off)
# By default we set the preprocessor and position independent code
# directives
set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -cpp -fPIC")
# Set the fortran modules to be stored in a common directory 
set(CMAKE_Fortran_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/ftnmods )
# Add that to the include path 
include_directories( ${CMAKE_Fortran_MODULE_DIRECTORY} )
if (DOUBLE_PRECISION)
  add_definitions(-DDOUBLE_PRECISION)
endif (DOUBLE_PRECISION)
if (LIB_LOAD)
  add_definitions(-DLibLoad)
else (LIB_LOAD)
  add_definitions(-DNO_LibLoad)
endif (NO_LIB_LOAD)
  

# Force free-form compilation 
get_filename_component(FCNAME ${CMAKE_Fortran_COMPILER} NAME)
if (FCNAME MATCHES "gfortran.*")
  set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -ffree-line-length-none")
elseif (FCNAME MATCHES "ifort.*")
  set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -free")
endif (FCNAME MATCHES "gfortran.*")




add_subdirectory(Registry)

add_subdirectory(NWTC_Library)
add_subdirectory(InflowWind)
add_subdirectory(AeroDyn14)
add_subdirectory(AeroDyn)
add_subdirectory(ServoDyn)
add_subdirectory(ElastoDyn)
add_subdirectory(BeamDyn)
add_subdirectory(SubDyn)
add_subdirectory(FEAMooring)
add_subdirectory(IceDyn)
add_subdirectory(IceFloe)
add_subdirectory(MAP)
add_subdirectory(MoorDyn)
add_subdirectory(HydroDyn)


add_library(fast8lib SHARED
  FAST/FAST_Mods.f90
  FAST/FAST_Prog.f90
  FAST/FAST_Subs.f90
  FAST/FAST_Types.f90
  OpenFOAM/OpenFOAM.f90
  OpenFOAM/OpenFOAM_Types.f90
  OrcaFlex/OrcaFlexInterface_Types.f90
  OrcaFlex/OrcaFlexInterface.f90)
add_executable(fast8 FAST/FAST_Prog.f90)

target_link_libraries(fast8lib nwtclibs inflowwind aerodyn aerodyn14 servodyn
                      elastodyn beamdyn subdyn feamooring icedyn icefloe
                      map_fast mapcpp moordyn hydrodyn)
target_link_libraries(fast8 fast8lib)