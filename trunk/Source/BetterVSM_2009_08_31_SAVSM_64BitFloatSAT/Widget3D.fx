//----------------------------------------------------------------------------------
// File:   Widget3D.fx
// Author: Baoguang Yang
// 
// Copyright (c) 2009 _COMPANYNAME_. All rights reserved.
// 
// Drawing light, frustrum et., al
//
//----------------------------------------------------------------------------------

#include "DeferredShading.fxh"

Texture2D<float>  TexDepthMap;

struct VS_IN
{
    float3 vPos : POSITION; ///< vertex position
};

struct VS_OUT1
{
    float4 vPos : SV_Position; ///< vertex position
    float3 vPosLightSpace : TEXCOORD0;
};

row_major float4x4 mViewProj;
float g_fNearPlaneWidth;

VS_OUT1 RenderLightVS(VS_IN invert)
{
    VS_OUT1 outvert;

    // transform the position from object space to clip space
    outvert.vPos = mul(float4(invert.vPos, 1), mViewProj);
    outvert.vPosLightSpace = invert.vPos;

    return outvert;
}

float4 RenderLightPS(VS_OUT1 infragm) : SV_Target0
{
    return float4(0.8,0.8,0.0,0);
}

VS_OUT1 RenderNearPlaneVS(VS_IN invert)
{
    VS_OUT1 outvert;

    // transform the position from object space to clip space
    outvert.vPos = mul(float4(invert.vPos, 1), mViewProj);
    outvert.vPosLightSpace = invert.vPos;

    return outvert;
}


float4 RenderNearPlanePS(VS_OUT1 infragm) : SV_Target0
{

	float2 ShadowTexC = { (infragm.vPosLightSpace.x+g_fNearPlaneWidth/2)/g_fNearPlaneWidth,1-(infragm.vPosLightSpace.y+g_fNearPlaneWidth/2)/g_fNearPlaneWidth };
	float  depth = TexDepthMap.SampleLevel( LinearSampler, ShadowTexC, 0 );
    return float4(depth,depth,depth,0);
}


float4 RenderAxisPS(VS_OUT1 infragm, uniform int axis_dir) : SV_Target0	//axis_dir 0:X, 1:Y, 2:Z
{
	if( axis_dir == 0 )
		return float4(0,1,0,0);
	else if( axis_dir == 1 )
		return float4(0,0,1,0);
	else if( axis_dir == 2 )
		return float4(1,0,0,0);
    else
		return float4(1,1,1,0);
}

float4 RenderFrustumPS(VS_OUT1 infragm) : SV_Target0
{
    return float4( 0,0.2,0.8,0);
}

technique10 RenderLight
{
    pass P0
    {
        SetVertexShader(CompileShader(vs_4_0, RenderLightVS()));
        SetGeometryShader(NULL);
        SetPixelShader(CompileShader(ps_4_0, RenderLightPS()));
    }
}

technique10 RenderAxis
{
    pass X
    {
        SetVertexShader(CompileShader(vs_4_0, RenderLightVS()));
        SetGeometryShader(NULL);
        SetPixelShader(CompileShader(ps_4_0, RenderAxisPS(0)));
    }
    pass Y
    {
        SetVertexShader(CompileShader(vs_4_0, RenderLightVS()));
        SetGeometryShader(NULL);
        SetPixelShader(CompileShader(ps_4_0, RenderAxisPS(1)));
    }
    pass Z
    {
        SetVertexShader(CompileShader(vs_4_0, RenderLightVS()));
        SetGeometryShader(NULL);
        SetPixelShader(CompileShader(ps_4_0, RenderAxisPS(2)));
    }
}

technique10 RenderFrustum
{
    pass P0
    {
        SetVertexShader(CompileShader(vs_4_0, RenderLightVS()));
        SetGeometryShader(NULL);
        SetPixelShader(CompileShader(ps_4_0, RenderFrustumPS()));
    }
}

technique10 RenderNearPlane
{
    pass P0
    {
        SetVertexShader(CompileShader(vs_4_0, RenderNearPlaneVS()));
        SetGeometryShader(NULL);
        SetPixelShader(CompileShader(ps_4_0, RenderNearPlanePS()));
    }
}