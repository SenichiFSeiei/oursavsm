#include "CommonDef.h"
#include "DeferredShading.fxh"
RasterizerState RStateMSAAON
{
	MultisampleEnable = FALSE; // performance hit is too high with MSAA for this sample
};

Texture2D<float> DepthTex0;
Texture2D<float2> DepthMip2;
Texture2D<float4> VSMMip2;
Texture2D DiffuseTex;
Texture2DArray<float2> DepthNBuffer;

#ifdef  USE_INT_SAT
Texture2D<uint2> SatSrcTex;
Texture2D<uint2> SatTex;
#else
Texture2D<float4> SatSrcTex;
Texture2D<float4> SatTex;
#endif

SamplerComparisonState DepthCompare;
SamplerState DepthSampler
{
    Filter = MIN_MAG_MIP_POINT;
    AddressU = Clamp;
    AddressV = Clamp;
};

cbuffer cb2 : register (b0)
{
	float nSatSampleInterval;
};
cbuffer cb0 : register(b1)
{
    row_major float4x4 mViewProj;
    row_major float4x4 mLightView;
    row_major float4x4 mLightViewProjClip2Tex;
    float DepthBiasDefault;
    int SkinSpecCoe;//Can not remove this, shadow maps class calls mesh render, and mesh render always require a SkinSpecCoe, this is ugly
	int nBufferLevel;
	int nSampleNum;
#ifdef USE_LINEAR_Z	
	row_major float4x4 mLightProjClip2TexInv;
	float Zf;
	float Zn;
#endif

};

float4 RenderDepthVS(float3 vPos : POSITION) : SV_Position
{
    if( abs(vPos.y) == 0.0 ) vPos.y = -0.5;//ignore floor when rendering shadow map, this is a dirty trick which effectively avoid depth bias when rendering front face in shadow map
    return mul(float4(vPos, 1), mViewProj);
}
float4 ConvertDepthVS(uint iv : SV_VertexID) : SV_Position
{
    return float4((iv << 1) & 2, iv & 2, 0.5, 1) * 2 - 1;
}

float2 ConvertDepth2PS(float4 vPos : SV_Position) : SV_Target0
{
    float fDepth = DepthTex0.Load(uint3(vPos.x, vPos.y, 0));
    return float2(fDepth, fDepth);
}
float2 ConvertDepth2PSWithAdj(float4 vPos : SV_Position) : SV_Target0
{
   
	float minfDepth    = DepthTex0.Load(uint3(vPos.x, vPos.y, 0));    
    float minfDepth_l  = DepthTex0.Load(uint3(vPos.x - 1, vPos.y, 0));
    float minfDepth_t  = DepthTex0.Load(uint3(vPos.x, vPos.y - 1, 0));
    float minfDepth_lt = DepthTex0.Load(uint3(vPos.x - 1, vPos.y - 1, 0));
	
	float min_depth = min(min(minfDepth,minfDepth_l),min(minfDepth_t,minfDepth_lt));
	float max_depth = max(max(minfDepth,minfDepth_l),max(minfDepth_t,minfDepth_lt));
    
	return float2(min_depth, max_depth);
}
float2 CreateMip2PS(float4 vPos : SV_Position) : SV_Target0
{
    uint3 iPos = uint3((int)vPos.x << 1, (int)vPos.y << 1, 0);
    float2 vDepth = DepthMip2.Load(iPos), vDepth1;
    ++iPos.x;
    vDepth1 = DepthMip2.Load(iPos);
    vDepth = float2(min(vDepth.x, vDepth1.x), max(vDepth.y, vDepth1.y));
    ++iPos.y;
    vDepth1 = DepthMip2.Load(iPos);
    vDepth = float2(min(vDepth.x, vDepth1.x), max(vDepth.y, vDepth1.y));
    --iPos.x;
    vDepth1 = DepthMip2.Load(iPos);
    vDepth = float2(min(vDepth.x, vDepth1.x), max(vDepth.y, vDepth1.y));
    return vDepth;
}
float2 ConvertToBigPS(float4 vPos : SV_Position) : SV_Target0
{
    uint3 iPos;
    if (vPos.x < DEPTH_RES)
    { // we fetch from the most detailed mip level
        iPos.xy = uint2(vPos.x, vPos.y);
        iPos.z = 0;
    }
    else
    { // compute the level from which we fetch
      iPos.z = N_LEVELS - (int)log2(vPos.y);
      iPos.x = (vPos.x - DEPTH_RES);
      iPos.y = (vPos.y - pow(2, N_LEVELS - iPos.z));
    }
    float2 ret_color = DepthMip2.Load(iPos);
    if( ret_color.x==0 && ret_color.y==0 )
		ret_color = float2(1.7,1.7);
	//we must guarantee undrawed part of the HSM have value (1,1) not ( 0,0 ) which can cause problem when calculating Kernel size
	return ret_color;
}

float2 CreateNBufferPS(float4 vPos : SV_Position) : SV_Target0
{	
	float2 sourcevals0,sourcevals1,sourcevals2,sourcevals3;
	float NBLevel = pow( 2,nBufferLevel );
    sourcevals0 = DepthNBuffer.Load( int4(vPos.x, vPos.y, 0, 0) + int4( 0,       (-1) * NBLevel, 0, 0 ) );  
    sourcevals1 = DepthNBuffer.Load( int4(vPos.x, vPos.y, 0, 0) + int4( NBLevel,              0, 0, 0 ) );  
    sourcevals2 = DepthNBuffer.Load( int4(vPos.x, vPos.y, 0, 0) + int4( NBLevel, (-1) * NBLevel, 0, 0 ) );  
    sourcevals3 = DepthNBuffer.Load( int4(vPos.x, vPos.y, 0, 0) + int4( 0,                    0, 0, 0 ) );  		

	float2 Color;
	Color.x = min( min( abs(sourcevals0.x),abs(sourcevals1.x)), min(abs(sourcevals2.x),abs(sourcevals3.x)) );
	Color.y = max( max( abs(sourcevals0.y),abs(sourcevals1.y)), max(abs(sourcevals2.y),abs(sourcevals3.y)) );

	return Color;
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
// This technique creates depth mip
technique10 ReworkDepth2
{
    pass ConvertDepth
    {
        SetVertexShader(CompileShader(vs_4_0, ConvertDepthVS()));
        SetGeometryShader(NULL);
        SetPixelShader(CompileShader(ps_4_0, ConvertDepth2PS()));
    }
    pass CreateMip
    {
        SetVertexShader(CompileShader(vs_4_0, ConvertDepthVS()));
        SetGeometryShader(NULL);
        SetPixelShader(CompileShader(ps_4_0, CreateMip2PS()));
    }
    pass ConvertToBig
    {
        SetVertexShader(CompileShader(vs_4_0, ConvertDepthVS()));
        SetGeometryShader(NULL);
        SetPixelShader(CompileShader(ps_4_0, ConvertToBigPS()));
    }
    pass ConvertDepthWithAdj
    {
        SetVertexShader(CompileShader(vs_4_0, ConvertDepthVS()));
        SetGeometryShader(NULL);
        SetPixelShader(CompileShader(ps_4_0, ConvertDepth2PSWithAdj()));
    }
    pass CreateNBuffer
    {
        SetVertexShader(CompileShader(vs_4_0, ConvertDepthVS()));
        SetGeometryShader(NULL);
        SetPixelShader(CompileShader(ps_4_0, CreateNBufferPS()));
    }

}


float4 ConvertDepth2VSMPS(float4 vPos : SV_Position) : SV_Target0
{
    float fDepth = DepthTex0.Load(uint3(vPos.x, vPos.y, 0));
    float squared_depth = fDepth * fDepth;
    
    float dx = DepthTex0.Load(uint3(vPos.x+1,vPos.y,0)) - fDepth;
    float dy = DepthTex0.Load(uint3(vPos.x,vPos.y+1,0)) - fDepth;
    
    float moment2 = fDepth * fDepth + 0.25 *(dx*dx+dy*dy);
    
    return float4(fDepth, moment2, fDepth, fDepth);
}

float4 CreateMip2VSMPS(float4 vPos : SV_Position) : SV_Target0
{
    uint3 iPos = uint3((int)vPos.x << 1, (int)vPos.y << 1, 0);
    float4 vDepth = VSMMip2.Load(iPos), vDepth1;
    ++iPos.x;
    vDepth1 = VSMMip2.Load(iPos);
    vDepth = float4(vDepth.x + vDepth1.x,vDepth.y + vDepth1.y, min(vDepth.z, vDepth1.z), max(vDepth.w, vDepth1.w)); 
    ++iPos.y;
    vDepth1 = VSMMip2.Load(iPos);
    vDepth = float4(vDepth.x + vDepth1.x,vDepth.y + vDepth1.y, min(vDepth.z, vDepth1.z), max(vDepth.w, vDepth1.w));
    --iPos.x;
    vDepth1 = VSMMip2.Load(iPos);
    vDepth = float4(vDepth.x + vDepth1.x,vDepth.y + vDepth1.y, min(vDepth.z, vDepth1.z), max(vDepth.w, vDepth1.w));
    vDepth.xy /= 4;
    return vDepth;
}

// This technique creates VSM: the VSM stores M1, M2, min, max
// Reuse ConvertDepthVS in building HSM, for VSM mip construction
technique10 ReworkVSM2
{
    pass ConvertDepth
    {
        SetVertexShader(CompileShader(vs_4_0, ConvertDepthVS()));
        SetGeometryShader(NULL);
        SetPixelShader(CompileShader(ps_4_0, ConvertDepth2VSMPS()));
    }
    pass CreateMip
    {
        SetVertexShader(CompileShader(vs_4_0, ConvertDepthVS()));
        SetGeometryShader(NULL);
        SetPixelShader(CompileShader(ps_4_0, CreateMip2VSMPS()));
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
        SetPixelShader( NULL );
    }
};

technique10 RenderSkinnedScene
{
    pass p0
    {
        SetVertexShader( CompileShader( vs_4_0, VSSkinnedSceneMain() ) );
        SetGeometryShader( NULL );
        SetPixelShader( NULL );
    }
};

#ifdef USE_INT_SAT
uint4 RenderSATHorizontalPS(float4 vPos : SV_Position) : SV_Target0
#else
float4 RenderSATHorizontalPS(float4 vPos : SV_Position) : SV_Target0
#endif
{
    int3 current_coord = int3( vPos.x, vPos.y, 0 );

#ifdef USE_INT_SAT
	uint2  sum_result = 0;
#else
    float4 sum_result = 0;
#endif

    for( int i = 0; i < nSampleNum; ++i )
    {
		sum_result += SatSrcTex.Load( current_coord );
		current_coord.x -= nSatSampleInterval;
    }
    
#ifdef USE_INT_SAT
	uint2  ret = sum_result;
	return uint4( ret.x, ret.y, 0, 0 );
#else
	float4 ret = sum_result;
	return ret;
#endif
}

#ifdef USE_INT_SAT
uint4 RenderSATVerticalPS(float4 vPos : SV_Position) : SV_Target0
#else
float4 RenderSATVerticalPS(float4 vPos : SV_Position) : SV_Target0
#endif
{
    int3 current_coord = int3( vPos.x, vPos.y, 0 );

#ifdef USE_INT_SAT
	uint2  sum_result = 0;
#else
    float4 sum_result = 0;
#endif

    for( int i = 0; i < nSampleNum; ++i )
    {
		sum_result += SatSrcTex.Load( current_coord );
		current_coord.y -= nSatSampleInterval;
    }

#ifdef USE_INT_SAT
	uint2  ret = sum_result;
	return uint4( ret.x, ret.y, 0, 0 );
#else
	float4 ret = sum_result;
	return ret;
#endif

}

#ifdef USE_INT_SAT
uint4 ConvertDepth2SATPS(float4 vPos : SV_Position) : SV_Target0
{
    float fDepth = DepthTex0.Load(uint3(vPos.x, vPos.y, 0));
#ifdef USE_LINEAR_Z
	fDepth = 1. / (fDepth * mLightProjClip2TexInv[2][3] + mLightProjClip2TexInv[3][3]);
	fDepth -= Zn;
	fDepth /= (Zf-Zn);
	fDepth += 0.001;
#endif
    
    float dx = DepthTex0.Load(uint3(vPos.x+1,vPos.y,0)) - fDepth;
    float dy = DepthTex0.Load(uint3(vPos.x,vPos.y+1,0)) - fDepth;
 #ifdef EVSM
	fDepth = exp(EXPC*fDepth);
 #endif   
    
    float moment2 = fDepth * fDepth;
   
    uint  uDepth  = round( fDepth * g_NormalizedFloatToSATUINT );
    uint  uMoment = round( moment2 * g_NormalizedFloatToSATUINT );
    
    return uint4(uDepth, uMoment, uDepth, uDepth);
}
#else
#ifdef DISTRIBUTE_PRECISION
// Distribute float precision
// NOTE: We want cheap reconstruction, so do most of the work here
// Moments may be already biased here, so have to also handle negatives.
float4 DistributeFP(float2 Value)
{
    float FactorInv = 1 / g_DistributeFPFactor;
    
    // Split precision
    float2 IntPart;
    float2 FracPart = modf(Value * g_DistributeFPFactor, IntPart);
    
    // Compose outputs to make it cheap to recombine
    return float4(IntPart * FactorInv, FracPart);
}

float4 ConvertDepth2SATPS(float4 vPos : SV_Position) : SV_Target0
{
    float fDepth = DepthTex0.Load(uint3(vPos.x, vPos.y, 0));
    float squared_depth = fDepth * fDepth;
    
    float dx = DepthTex0.Load(uint3(vPos.x+1,vPos.y,0)) - fDepth;
    float dy = DepthTex0.Load(uint3(vPos.x,vPos.y+1,0)) - fDepth;
    
    float moment2 = fDepth * fDepth;// + 0.25 *(dx*dx+dy*dy);
    float2 moments = float2(fDepth,moment2);
    
    return DistributeFP(moments);
}
#else
float4 ConvertDepth2SATPS(float4 vPos : SV_Position) : SV_Target0
{
    float fDepth = DepthTex0.Load(uint3(vPos.x, vPos.y, 0));
    float squared_depth = fDepth * fDepth;
    
    float dx = DepthTex0.Load(uint3(vPos.x+1,vPos.y,0)) - fDepth;
    float dy = DepthTex0.Load(uint3(vPos.x,vPos.y+1,0)) - fDepth;
    
    float moment2 = fDepth * fDepth;// + 0.25 *(dx*dx+dy*dy);
    return float4(fDepth, moment2, fDepth, fDepth);
}
#endif
#endif


// This technique renders depth
technique10 RenderSAT
{
    pass HorizontalPass
    {
        SetVertexShader(CompileShader(vs_4_0, ConvertDepthVS()));
        SetGeometryShader(NULL);
		SetPixelShader(CompileShader(ps_4_0, RenderSATHorizontalPS()));
    }
    pass VerticalPass
    {
        SetVertexShader(CompileShader(vs_4_0, ConvertDepthVS()));
        SetGeometryShader(NULL);
		SetPixelShader(CompileShader(ps_4_0, RenderSATVerticalPS()));
    }
    pass ConvertDepth//External dependency on vsm mip
    {
        SetVertexShader(CompileShader(vs_4_0, ConvertDepthVS()));
        SetGeometryShader(NULL);
        SetPixelShader(CompileShader(ps_4_0, ConvertDepth2SATPS()));
    }

}
