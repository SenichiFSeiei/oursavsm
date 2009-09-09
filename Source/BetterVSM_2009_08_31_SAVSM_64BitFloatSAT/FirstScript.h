#ifndef FIRSTSCRIPT
#define FIRSTSCRIPT

#define DEPTH_RES 1024
#define N_LEVELS 10
//#define RES_REV float g_fResRev[N_LEVELS] = { 1./512, 1./256, 1./128, 1./64, 1./32, 1./16, 1./8, 1./4, 1./2 };
#define RES_REV float g_fResRev[N_LEVELS] = { 1./1024, 1./512, 1./256, 1./128, 1./64, 1./32, 1./16, 1./8, 1./4, 1./2 };
#define RES float g_fRes[N_LEVELS] = { 1024, 512, 256, 128, 64, 32, 16, 8, 4, 2 };

#define SILHOUETTE_BP_SCENE_TECH "RenderAcc"
#define SILHOUETTE_BP_SCENE_OBJECT_TECH "RenderSceneObj"
#define SILHOUETTE_BP_SCENE_VF_TECH "RenderSceneVF"//for low res shadow rendering,dont count color in
#define UPSAMPLE_TECH "RenderUpsample"

#define EYE_POS			D3DXVECTOR3(12, 60.96, -19.6)
#define LOOK_AT_POS		D3DXVECTOR3(0,6,1)
//#define LOOK_AT_POS		D3DXVECTOR3(-20,30,1)

#define SILHOUETTE_BP_EFFECT_FILE_NAME L"SoftShadows.fx"
#define SILHOUETTE_BP_MSSM_KERNEL_EFFECT_FILE_NAME L"SilhouetteBPMSSMKernel.fx"
#define STANDARD_VSM_EFFECT_FILE_NAME L"StandardVSM.fx"
#define PCSS_EFFECT_FILE_NAME L"PCSS.fx"
#define HIERARCHAL_EDGE_EXTRACTION_EFFECT_FILE_NAME L"HierarchalEdgeExtraction.fx"
#define HIERBP_FILE_NAME L"HierBP.fx"
#define BPGI_EFFECT_FILE_NAME L"BPGI.fx"
#define RENDER_FINAL_FILE_NAME L"FinalPass.fx"
#define NO_SHADOW_EFFECT_FILE_NAME L"NoShadow.fx"
#define INPUT_BUFFER_EFFECT_FILE_NAME L"InputBuffer.fx"

#define SHADOWMAP_CULL	D3D10_CULL_NONE

#define DEFAULT_HDR_ENVMAP                 L"HDRRendering\\pisa.hdr" 
//#define DEFAULT_HDR_ENVMAP                 L"HDRRendering\\uffizi_cross.hdr" 

    //Marching square with left hand law applied
               //-------------------------------     0     --     1    --     2    --      3     --     4    --     5     --      6    --      7    --      8    --      9    --     10    --		11   --		12    --	 13    --	  14    --	   15    --
#define MS float2 g_fMarchingSquare[16] = { float2(0,0), float2(0,0), float2(1,1), float2(0,1), float2(2,2), float2(0,0), float2(1,2), float2(0,2), float2(3,3), float2(3,0), float2(1,1), float2(3,1), float2(2,3), float2(2,0), float2(1,3), float2(0,0) };


#include "OGRE.h"
//#include "LightSettings.h"
#include "SingleLight.h"

#define BACKGROUND_COLOR	{ 0, 0, 0, 1 }		


#define LIGHT_SCALE_FACTOR 10
#endif