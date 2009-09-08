#include "CommonDef.h"
#include "DeferredShading.fxh"

RasterizerState RStateMSAAON
{
	MultisampleEnable = FALSE;
};

Texture2D DiffuseTex;

cbuffer cb0 : register(b0)
{
    row_major float4x4 mViewProj;
    bool bTextured;
    float g_fScreenWidth;
    float g_fScreenHeight;
};

struct PS_OUT_DEFERRED_SHADING
{
	float4 vWorldPos	   : SV_Target0; // save depth
	float3 vNormWorldSpace : SV_Target1; // save depth
	float4 vColor		   : SV_Target2; // save depth
	float4 vDummy		   : SV_Target3; // save depth
};

VS_OUT_DEFERRED_SHADING RenderInputAttriVS_StaticObj(VS_IN_DEFERRED_SHADING invert)
{
    VS_OUT_DEFERRED_SHADING outvert;

    // transform the position from object space to screen space
    outvert.vPos = mul(float4(invert.vPos, 1), mViewProj);
	outvert.vNorm = invert.vNorm;
	outvert.vTCoord = float4(invert.vTCoord,0,0);
	outvert.vWorldPos = float4(invert.vPos,1);
	
    return outvert;
}

PS_OUT_DEFERRED_SHADING RenderInputAttriPS_StaticObj(VS_OUT_DEFERRED_SHADING inpix)
{
	PS_OUT_DEFERRED_SHADING outpix;
	outpix.vWorldPos = inpix.vWorldPos;
#ifdef CORRECTNESS_DBG
	float depth = outpix.vPerspectivePos.z/outpix.vPerspectivePos.w;
	outpix.vPerspectivePos = float4( depth, depth, depth, 1 );
#endif
	outpix.vNormWorldSpace = normalize(inpix.vNorm);
	[flatten] if (bTextured)
	{
		outpix.vColor = DiffuseTex.Sample( LinearSampler, inpix.vTCoord);
	}
	outpix.vDummy		   = float4(0,0,1,1);
	return outpix;
}


//--------------------------------------------------------------------------------------
//Render animated mesh
//--------------------------------------------------------------------------------------
#define MAX_TIME_STEPS 3
#define MID_TIME_STEP 1

cbuffer cbTimeMatrices
{
    matrix g_mBlurViewProj[MAX_TIME_STEPS];
    matrix g_mBlurWorld[MAX_TIME_STEPS];
    matrix g_mBoneWorld[MAX_TIME_STEPS*MAX_BONE_MATRICES];
};

cbuffer cbPerFrame
{
    float g_fFrameTime;
};

cbuffer cbPerUser
{
    uint g_iNumSteps = 3;
    float g_fTextureSmear = 0.5f;
    float3 g_vLightDir = float3(0,0.707f,-0.707f);
};

DepthStencilState DepthTestNormal
{
    DepthEnable = true;
    DepthWriteMask = ALL;
    DepthFunc = LESS;
    StencilEnable = false;
    StencilReadMask = 0;
    StencilWriteMask = 0;
};


VS_OUT_DEFERRED_SHADING RenderInputAttriVS_WarriorSuit( VS_IN_DEFERRED_SHADING invert )
{
    VS_OUT_DEFERRED_SHADING outvert = (VS_OUT_DEFERRED_SHADING)0;
	// Normal transformation and lighting for the middle position
	matrix mWorldNow = g_mBlurWorld[ MID_TIME_STEP ];
	matrix mViewProjNow = g_mBlurViewProj[ MID_TIME_STEP ];

    if( invert.vPos.y == 0.0 ) outvert.vPos = float4(0,0,-1,1);//ignore floor when rendering shadow map, this is a dirty trick which effectively avoid depth bias when rendering front face in shadow map
	else
	{ 	    
		outvert.vPos = mul( float4(invert.vPos,1), mWorldNow );
	    //g_mScale is included in g_mBlurViewProj. But when transforming to only world or view space, you must do scaling yourself.
	    //Ugly, IMO. Someday I will fix this.
   		outvert.vWorldPos = mul( outvert.vPos, g_mScale );

		outvert.vPos = mul( outvert.vPos, mViewProjNow );
	}
    float3 wNormal = mul( invert.vNorm, (float3x3)mWorldNow );
    
    outvert.vNorm = invert.vNorm;
    outvert.vTCoord = float4(invert.vTCoord,0,0);
 
    return outvert;
}

//temporarily put here, will move to DeferredShading.fxh sooner
struct SkinnedInfo
{
    float4 vPos;
    float3 vNorm;
};

SkinnedInfo SkinVert( VS_IN_DEFERRED_SHADING_SKINNED invert, uint iTimeShift )
{
    SkinnedInfo outvert = (SkinnedInfo)0;
    
    float4 pos = float4(invert.vPos,1);
    float3 norm = invert.vNorm;
    
    uint iBone = invert.Bones.x;
    float fWeight = invert.Weights.x;
    
    matrix m = g_mBoneWorld[ iTimeShift*MAX_BONE_MATRICES + iBone ];
    outvert.vPos += fWeight * mul( pos, m );
    outvert.vNorm += fWeight * mul( norm, m );
    
    iBone = invert.Bones.y;
    fWeight = invert.Weights.y;
    m = g_mBoneWorld[ iTimeShift*MAX_BONE_MATRICES + iBone ];
    outvert.vPos += fWeight * mul( pos, m );
    outvert.vNorm += fWeight * mul( norm, m );

    iBone = invert.Bones.z;
    fWeight = invert.Weights.z;
    m = g_mBoneWorld[ iTimeShift*MAX_BONE_MATRICES + iBone ];
    outvert.vPos += fWeight * mul( pos, m );
    outvert.vNorm += fWeight * mul( norm, m );
    
    iBone = invert.Bones.w;
    fWeight = invert.Weights.w;
    m = g_mBoneWorld[ iTimeShift*MAX_BONE_MATRICES + iBone ];
    outvert.vPos += fWeight * mul( pos, m );
    outvert.vNorm += fWeight * mul( norm, m );
    
    return outvert;
}

VS_OUT_DEFERRED_SHADING RenderInputAttriVS_WarriorSkin( VS_IN_DEFERRED_SHADING_SKINNED invert )
{
    VS_OUT_DEFERRED_SHADING outvert = (VS_OUT_DEFERRED_SHADING)0;
    
    // Skin the vetex
    SkinnedInfo vSkinned = SkinVert( invert, MID_TIME_STEP );
    
    // ViewProj transform
    if( vSkinned.vPos.y == 0.0 ) outvert.vPos = float4(0,0,-1,1);//ignore floor when rendering shadow map, this is a dirty trick which effectively avoid depth bias when rendering front face in shadow map
	else outvert.vPos = mul( vSkinned.vPos, g_mBlurViewProj[ MID_TIME_STEP ] );
    
    float3 blendNorm = vSkinned.vNorm;
    outvert.vTCoord = float4(invert.vTCoord,0,0);

    outvert.vNorm = invert.vNorm;
    //g_mScale is included in g_mBlurViewProj. But when transforming to only world or view space, you must do scaling yourself.
    //Ugly, IMO. Someday I will fix this.
   	outvert.vWorldPos = mul( vSkinned.vPos, g_mScale );

    return outvert;
}

//--------------------------------------------------------------------------------------
// Techniques
//--------------------------------------------------------------------------------------
technique10 RenderInputAttriTech_StaticObj
{
	pass P0
	{
		SetVertexShader(CompileShader(vs_4_0, RenderInputAttriVS_StaticObj()));
		SetGeometryShader(NULL);
		SetPixelShader(CompileShader(ps_4_0, RenderInputAttriPS_StaticObj()));
		SetRasterizerState(RStateMSAAON);
	}
}

technique10 RenderInputAttriTech_WarriorSuit
{
    pass p0
    {
        SetVertexShader( CompileShader( vs_4_0, RenderInputAttriVS_WarriorSuit() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_4_0, RenderInputAttriPS_StaticObj() ) );
    }
};

technique10 RenderInputAttriTech_WarriorSkin
{
    pass p0
    {
        SetVertexShader( CompileShader( vs_4_0, RenderInputAttriVS_WarriorSkin() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_4_0, RenderInputAttriPS_StaticObj() ) );   
        SetDepthStencilState( DepthTestNormal, 0 );
    }
};

//they are useless, but you can not delete them
//they are implicitly used by the mesh container
cbuffer useless
{
	float4 g_vLightAmbientClr = {0.522,0.498,0.498,1};
	float3 g_vCameraInLight;//specular
    float4 g_vMaterialKd;
    float3 g_vLightPos; ///< light in world CS
    float4 g_vLightFlux;
    float  g_vLightAmbient = 0.2;
    float g_fFilterSize, g_fDoubleFilterSizeRev;
    row_major float4x4 mLightView;
    row_major float4x4 mLightViewProjClip2Tex;
    row_major float4x4 mLightProjClip2TexInv;
    row_major float4x4 mLightProj;
    
    int  SkinSpecCoe = 1;
    int  HelmetSpecCoe = 4;
    int  StoneSpecCoe = 10;
    
    float4 spec_clr_ogre = {0.243,0.282,0.247,1};
    float4 spec_clr_hel  = {1,1,1,1};
    float4 spec_clr_stone = {1,1,1,1};
    float4 spec_clr_floor = {1,1,1,1};
    float DepthBiasDefault = 0.1;
    float g_fLightZn;
    float g_fLumiFactor;
}