#include "DeferredShading.fxh"
#include "CommonDef.h"
RasterizerState RStateMSAAON
{
	MultisampleEnable = FALSE; // performance hit is too high with MSAA for this sample
};

Texture2D<float> g_txArea;
Texture2D<float> DepthTex0;
Texture2D<float2> DepthMip2;
Texture2D<float4> ShadowMapPos;
Texture2D<float4> g_txHSMKernel;
Texture2D<float4> g_txPreviousResult;

Texture2D DiffuseTex;
SamplerComparisonState DepthCompare;
SamplerState DepthSampler
{
    Filter = MIN_MAG_MIP_POINT;
    AddressU = Clamp;
    AddressV = Clamp;
};
SamplerState DiffuseSampler
{
    Filter = MIN_MAG_MIP_LINEAR;
    AddressU = Wrap;
    AddressV = Wrap;
};
cbuffer cb0 : register(b0)
{
	float4 g_vLightAmbientClr = {0.522,0.498,0.498,1};
	float3 g_vCameraInLight;//specular
    float4 g_vMaterialKd;
    float3 g_vLightPos; ///< light in world CS
    float4 g_vLightFlux;
    float  g_vLightAmbient = 0.2;
    float g_fFilterSize, g_fDoubleFilterSizeRev;
    row_major float4x4 mViewProj;
    row_major float4x4 mLightView;
    row_major float4x4 mLightViewProjClip2Tex;
    row_major float4x4 mLightProjClip2TexInv;
    row_major float4x4 mLightProj;
    bool bTextured;
    
    int  SkinSpecCoe = 1;
    int  HelmetSpecCoe = 4;
    int  StoneSpecCoe = 10;
    
    float4 spec_clr_ogre = {0.243,0.282,0.247,1};
    float4 spec_clr_hel  = {1,1,1,1};
    float4 spec_clr_stone = {1,1,1,1};
    float4 spec_clr_floor = {1,1,1,1};
    float DepthBiasDefault = 0.0;
    float g_fLightZn;
    float g_fLumiFactor;

};

cbuffer cb1 : register(b1)
{
	RES_REV;//Marco in CommonDef.h, defines the constants representing the rev of the res of HSM levels
	RES;//Marco in CommonDef.h, defines the constants representing the res of HSM levels
	MS;
};

//--------------------------------------------------------------------------------------
// Vertex shader output structure
//--------------------------------------------------------------------------------------
struct VS_IN
{
    float3 vPos : POSITION; ///< vertex position
    float3 vNorm : NORMAL; ///< vertex diffuse color (note that COLOR0 is clamped from 0..1)
    float2 vTCoord : TEXCOORD0; ///< vertex texture coords
};
struct VS_OUT0
{
    float4 vPos : SV_Position; ///< vertex position
    float4 vDiffColor : COLOR0; ///< vertex diffuse color (note that COLOR0 is clamped from 0..1)
    float2 vTCoord : TEXCOORD0; ///< vertex texture coords 
    float4 vLightPos : TEXCOORD2;
    float3 vNorm : TEXCOORD3;
};
struct VS_OUT1
{
    float4 vPos : SV_Position; ///< vertex position
    float4 vDiffColor : TEXCOORD0; ///< vertex diffuse color (note that COLOR0 is clamped from 0..1)
    float2 vTCoord : TEXCOORD1; ///< vertex texture coords 
    float3 vNorm : TEXCOORD2;
};

VS_OUT1 RenderSceneNoShadowsVS(VS_IN invert)
{
    VS_OUT1 outvert;

    // transform the position from object space to clip space
    outvert.vPos = mul(float4(invert.vPos, 1), mViewProj);
    outvert.vNorm = invert.vNorm;
    outvert.vTCoord = invert.vTCoord;

    return outvert;
}

VS_OUT0 RenderSceneAccVS(VS_IN invert)
{
    VS_OUT0 outvert;

    // transform the position from object space to clip space
    outvert.vPos = mul(float4(invert.vPos, 1), mViewProj);
    outvert.vLightPos = mul(float4(invert.vPos, 1), mLightView);
    // compute light direction
    float3 vLightDir = normalize(g_vLightPos - invert.vPos);
    // compute lighting
    outvert.vDiffColor = (g_vMaterialKd * g_vLightFlux);
    outvert.vDiffColor.xyz *= max(0, dot(invert.vNorm, vLightDir));
    outvert.vTCoord = invert.vTCoord;
    outvert.vNorm = mul(invert.vNorm,(float3x3)mLightView);

    return outvert;
}
//--------------------------------------------------------------------------------------
// Pixel shader output structure
//--------------------------------------------------------------------------------------

float4 phong_shading( float3 light_space_pos, float3 light_space_camera_pos, float3 surf_norm, 
					  int high_light_coe, float4 diffuse_clr,float4 shadow_coe,
					  float4 spec_clr )
{
    float3 lightDirInLightView = normalize(float3( 0,0,0 ) - light_space_pos);
    float3 viewDirInLightView  = normalize(light_space_camera_pos - light_space_pos);
    
 	float3 surfNorm = surf_norm;
 	float3 H = normalize(viewDirInLightView+lightDirInLightView);
	float  spec_coe = saturate(dot(H,surfNorm));
	spec_coe = pow( spec_coe,50);
	//spec_coe = pow( spec_coe,high_light_coe);
	float  diff_coe = saturate(dot(surfNorm,lightDirInLightView));

	float4 ret_color = ( diffuse_clr * diff_coe + spec_coe * spec_clr ) * g_vLightFlux * shadow_coe;

   return ret_color;

}

float4 RenderSceneNoShadowsPS(VS_OUT1 infragm) : SV_Target0
{
    return float4(1,0,0,1);
}

float4 RenderSceneAccPS(VS_OUT0 In) : SV_Target0
{
    float3 lightDirInLightView = normalize(float3( 0,0,0 ) - In.vLightPos.xyz);

	float3 surfNorm = In.vNorm;
	REVERT_NORM;
	float  diff_coe = saturate(dot(surfNorm,lightDirInLightView));
	
	float4 ret_color = {1,1,1,1};
    float4 diff = float4(1,1,1,1);
   	[flatten] if (bTextured) diff *= DiffuseTex.Sample(DiffuseSampler, In.vTCoord);	

	diff.a = 1;
	float4 curr_result = phong_shading(In.vLightPos.xyz,g_vCameraInLight.xyz,surfNorm,SkinSpecCoe,diff,ret_color,spec_clr_ogre);
	float4 pre_result = g_txPreviousResult.Load( int3( In.vPos.x - 0.5, In.vPos.y - 0.5, 0 ) );
	return pre_result + curr_result  * g_fLumiFactor;

}


technique10 RenderNoShadows
{
    pass P0
    {
        SetVertexShader(CompileShader(vs_4_0, RenderSceneNoShadowsVS()));
        SetGeometryShader(NULL);
        SetPixelShader(CompileShader(ps_4_0, RenderSceneNoShadowsPS()));
		SetRasterizerState(RStateMSAAON);
    }
}
technique10 RenderAcc
{
    pass P0
    {
        SetVertexShader(CompileShader(vs_4_0, RenderSceneAccVS()));
        SetGeometryShader(NULL);
        SetPixelShader(CompileShader(ps_4_0, RenderSceneAccPS()));
		SetRasterizerState(RStateMSAAON);
    }
}

float4 RenderSceneObjPS(VS_OUT0 In) : SV_Target0
{
    float3 lightDirInLightView = normalize(float3( 0,0,0 ) - In.vLightPos.xyz);

	float4 diff = float4(1,1,1,1);
	[flatten] if (bTextured) diff = DiffuseTex.Sample( DiffuseSampler, In.vTCoord);
    diff.a = 1;

	float3 surfNorm = In.vNorm;
	REVERT_NORM;
	float  diff_coe = saturate(dot(surfNorm,lightDirInLightView));
	
	float4 ret_color = {1,1,1,1};
			
	float4 curr_result = phong_shading(In.vLightPos.xyz,g_vCameraInLight.xyz,surfNorm,SkinSpecCoe,diff,ret_color,spec_clr_ogre);
	float4 pre_result = g_txPreviousResult.Load( int3( In.vPos.x - 0.5, In.vPos.y - 0.5, 0 ) );
	return pre_result + curr_result  * g_fLumiFactor;

}


technique10 RenderSceneObj
{
    pass P0
    {
        SetVertexShader(CompileShader(vs_4_0, RenderSceneAccVS()));
        SetGeometryShader(NULL);
        SetPixelShader(CompileShader(ps_4_0, RenderSceneObjPS()));
		SetRasterizerState(RStateMSAAON);
    }
}


VS_OUT_SCREEN_POS RenderScreenPixelPosVS(VS_IN_SCREEN_POS invert)
{
    VS_OUT_SCREEN_POS outvert;

    // transform the position from object space to clip space
    outvert.vPos = mul(float4(invert.vPos, 1), mViewProj);
    outvert.vLightViewPos = mul(float4(invert.vPos, 1), mLightView);

    return outvert;
}

float4 RenderScreenPixelPosPS(VS_OUT_SCREEN_POS In) : SV_Target0
{
	return In.vLightViewPos;
}

technique10 RenderScreenPixelPos
{
	pass P0
	{
		SetVertexShader(CompileShader(vs_4_0, RenderScreenPixelPosVS()));
		SetGeometryShader(NULL);
		SetPixelShader(CompileShader(ps_4_0, RenderScreenPixelPosPS()));
		SetRasterizerState(RStateMSAAON);
	}
}

float4 RenderDepthVS(float3 vPos : POSITION) : SV_Position
{
    if( vPos.y == 0.0 ) return float4(0,0,-1,1);//ignore floor when rendering shadow map, this is a dirty trick which effectively avoid depth bias when rendering front face in shadow map
    return mul(float4(vPos, 1), mViewProj);
}
// This technique renders depth
technique10 RenderDepth
{
    pass RenderDepth
    {
        SetVertexShader(CompileShader(vs_4_0, RenderDepthVS()));
        SetGeometryShader(NULL);
        SetPixelShader(NULL);
    }
}

//--------------------------------------------------------------------------------------
// File: MotionBlur10.fx
//
// The effect file for the SoftShadow sample.
//
// Copyright (c) Microsoft Corporation. All rights reserved.
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

SamplerState g_samLinear
{
    Filter = MIN_MAG_MIP_LINEAR;
    AddressU = Wrap;
    AddressV = Wrap;
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


//--------------------------------------------------------------------------------------
// Rendering Geometry with Texture Motion Blur
//--------------------------------------------------------------------------------------
struct VSSceneInAni
{
    float3 Pos : POSITION;
    float3 Normal : NORMAL;
    float2 Tex : TEXCOORD;
    float3 Tan : TANGENT;
};

struct VSSceneOutAni
{
    float4 Pos : SV_POSITION;
    float4 Color : COLOR0;
    float2 Tex : TEXCOORD0;
    float4 vLightPos : TEXCOORD1;
    float3 vNorm: TEXCOORD2;
};


float4 ComputeLighting( float3 normal )
{
    float4 color = saturate( dot( normal, g_vLightDir ) );
    color += float4(0.5,0.5,0.5,0.0);
    return color;
}



VSSceneOutAni VSSceneMain( VSSceneInAni Input )
{
    VSSceneOutAni Output = (VSSceneOutAni)0;
	// Normal transformation and lighting for the middle position
	matrix mWorldNow = g_mBlurWorld[ MID_TIME_STEP ];
	matrix mViewProjNow = g_mBlurViewProj[ MID_TIME_STEP ];

    if( Input.Pos.y == 0.0 ) Output.Pos = float4(0,0,-1,1);//ignore floor when rendering shadow map, this is a dirty trick which effectively avoid depth bias when rendering front face in shadow map
	else
	{ 	    
		Output.Pos = mul( float4(Input.Pos,1), mWorldNow );
		Output.Pos = mul( Output.Pos, mViewProjNow );
	}
    float3 wNormal = mul( Input.Normal, (float3x3)mWorldNow );
    
    Output.vNorm = normalize( mul( Input.Normal, (float3x3)mLightView ) );
    
    Output.Color = float4(1,1,1,1);
    Output.Tex = Input.Tex;
 
    Output.vLightPos = mul(float4(Input.Pos, 1), mWorldNow);
    Output.vLightPos = mul( Output.vLightPos, g_mScale);
    Output.vLightPos = mul( Output.vLightPos,mLightView); 

 
    return Output;
}

float4 PSSceneMain( VSSceneOutAni Input ) : SV_TARGET
{
    float3 lightDirInLightView = normalize(float3( 0,0,0 ) - Input.vLightPos.xyz);

	float4 diff = float4(1,1,1,1);
	[flatten] if (bTextured) diff = DiffuseTex.Sample( g_samLinear, Input.Tex);
    diff.a = 1;

	float3 surfNorm = Input.vNorm;
	REVERT_NORM;
	float  diff_coe = saturate(dot(surfNorm,lightDirInLightView));

	float4 ret_color = {1,1,1,1};
			
	float4 curr_result = phong_shading(Input.vLightPos.xyz,g_vCameraInLight.xyz,surfNorm,SkinSpecCoe,diff,ret_color,spec_clr_hel);
	float4 pre_result = g_txPreviousResult.Load( int3( Input.Pos.x - 0.5, Input.Pos.y - 0.5, 0 ) );
	return pre_result + curr_result  * g_fLumiFactor;

}

//--------------------------------------------------------------------------------------
// Rendering Skinned Geometry with Texture Motion Blur
//--------------------------------------------------------------------------------------
struct VSSkinnedSceneInAni
{
    float3 Pos : POSITION;
    float3 Normal : NORMAL;
    float2 Tex : TEXCOORD;
    float3 Tan : TANGENT;
    uint4 Bones : BONES;
    float4 Weights : WEIGHTS;
};

struct SkinnedInfo
{
    float4 Pos;
    float3 Norm;
};

SkinnedInfo SkinVert( VSSkinnedSceneInAni Input, uint iTimeShift )
{
    SkinnedInfo Output = (SkinnedInfo)0;
    
    float4 pos = float4(Input.Pos,1);
    float3 norm = Input.Normal;
    
    uint iBone = Input.Bones.x;
    float fWeight = Input.Weights.x;
    //fWeight = 1.0f;
    matrix m = g_mBoneWorld[ iTimeShift*MAX_BONE_MATRICES + iBone ];
    Output.Pos += fWeight * mul( pos, m );
    Output.Norm += fWeight * mul( norm, m );
    
    iBone = Input.Bones.y;
    fWeight = Input.Weights.y;
    m = g_mBoneWorld[ iTimeShift*MAX_BONE_MATRICES + iBone ];
    Output.Pos += fWeight * mul( pos, m );
    Output.Norm += fWeight * mul( norm, m );

    iBone = Input.Bones.z;
    fWeight = Input.Weights.z;
    m = g_mBoneWorld[ iTimeShift*MAX_BONE_MATRICES + iBone ];
    Output.Pos += fWeight * mul( pos, m );
    Output.Norm += fWeight * mul( norm, m );
    
    iBone = Input.Bones.w;
    fWeight = Input.Weights.w;
    m = g_mBoneWorld[ iTimeShift*MAX_BONE_MATRICES + iBone ];
    Output.Pos += fWeight * mul( pos, m );
    Output.Norm += fWeight * mul( norm, m );
    
    return Output;
}

VSSceneOutAni VSSkinnedSceneMain( VSSkinnedSceneInAni Input )
{
    VSSceneOutAni Output = (VSSceneOutAni)0;
    
    // Skin the vetex
    SkinnedInfo vSkinned = SkinVert( Input, MID_TIME_STEP );
    
    // ViewProj transform
    if( vSkinned.Pos.y == 0.0 ) Output.Pos = float4(0,0,-1,1);//ignore floor when rendering shadow map, this is a dirty trick which effectively avoid depth bias when rendering front face in shadow map
	else Output.Pos = mul( vSkinned.Pos, g_mBlurViewProj[ MID_TIME_STEP ] );
    
    // Lighting
    float3 blendNorm = vSkinned.Norm;
    Output.Color = float4(1,1,1,1);
    Output.Tex = Input.Tex;

    Output.vNorm = normalize( mul( Input.Normal, (float3x3)mLightView ) );

    Output.vLightPos = mul(vSkinned.Pos, g_mScale);
    Output.vLightPos = mul(Output.vLightPos, mLightView);

    return Output;
}










//--------------------------------------------------------------------------------------
// Techniques
//--------------------------------------------------------------------------------------


technique10 RenderScene
{
    pass p0
    {
        SetVertexShader( CompileShader( vs_4_0, VSSceneMain() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_4_0, PSSceneMain() ) );
        
        SetDepthStencilState( DepthTestNormal, 0 );
    }
};

technique10 RenderSkinnedScene
{
    pass p0
    {
        SetVertexShader( CompileShader( vs_4_0, VSSkinnedSceneMain() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_4_0, PSSceneMain() ) );
        
        SetDepthStencilState( DepthTestNormal, 0 );
    }
};