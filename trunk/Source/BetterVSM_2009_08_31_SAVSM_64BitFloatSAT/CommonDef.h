#ifndef SCRIPT
#define SCRIPT
//--------------------------------------------------------------------------------------
// UI control IDs
//--------------------------------------------------------------------------------------
#define IDC_CHANGEDEVICE        4
#define IDC_LIGHT_SIZE_LABEL    5
#define IDC_LIGHT_SIZE          6
#define IDC_SHADOW_ALGORITHM    7
#define IDC_SHADOW_ALGORITHM_LABEL 8
#define IDC_BTEXTURED 9
#define IDC_BMOVECAMERA 11
#define IDC_BDUMP_SHADOWMAP 10
#define IDC_BP_EDGE_TOLERANCE 12
#define IDC_LIGHT_ZN 13

#define IDC_fDefaultDepthBias 14
#define IDC_fDepthBiasHammer 15
#define IDC_fDepthBiasLeftForearm 16
#define IDC_fDepthBiasRightForearm 17
#define IDC_fDepthBiasLeftShoulder 18
#define IDC_fDepthBiasRightShoulder 19
#define IDC_fDepthBiasBlackPlate 20
#define IDC_fDepthBiasHelmet 21
#define IDC_fDepthBiasEyes 22
#define IDC_fDepthBiasBelt 23
#define IDC_fDepthBiasLeftThigh 24
#define IDC_fDepthBiasRightThigh 25
#define IDC_fDepthBiasLeftShin 26
#define IDC_fDepthBiasRightShin 27
#define IDC_fDepthBiasObject0 29

#define IDC_COMMON_LABEL 28
#define IDC_NUM_LIGHT_SAMPLE 30
#define IDC_LIGHT_ZF 31
#define IDC_LIGHT_FOV 32
#define IDC_SHOW_3DWIDGET 33

#define IDC_STATIC 100
#define IDC_ANIMATE 101
#define IDC_SCENE 102
#define IDC_FAN 103

#define IDC_FRAME_DUMP 104

struct Parameters//soft shadow mapping algorithm parameter set
{
	float	fLightZn;
};

struct Biases
{
	float	fDepthBiasObject0;
	float	fDefaultDepthBias;
	float	fDepthBiasHammer;
	float	fDepthBiasLeftForearm;
	float	fDepthBiasRightForearm;
	float	fDepthBiasLeftShoulder;
	float	fDepthBiasRightShoulder;
	float	fDepthBiasBlackPlate;
	float	fDepthBiasHelmet;
	float	fDepthBiasEyes;
	float	fDepthBiasBelt;
	float	fDepthBiasLeftThigh;
	float	fDepthBiasRightThigh;
	float	fDepthBiasLeftShin;
	float	fDepthBiasRightShin; 

};

#define STANDARD_BP 0
#define BP_MSSM_KERNEL	1
#define STD_VSM 2
#define HIR_EDGE_EXTRACTION 3
#define HIR_BP 4
#define BP_GI 5
#define NO_SHADOW_ALGORITHM 6
#define SINGLE_LIGHT 7
#define STD_PCSS 8

#define USE_INT_SAT
//#define DISTRIBUTE_PRECISION
#define BILINEAR_INT_SMP
#define USE_LINEAR_Z

#include "FirstScript.h"

#endif