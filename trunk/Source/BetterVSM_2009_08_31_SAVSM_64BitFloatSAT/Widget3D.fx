struct VS_IN
{
    float3 vPos : POSITION; ///< vertex position
};

struct VS_OUT1
{
    float4 vPos : SV_Position; ///< vertex position
};

row_major float4x4 mViewProj;

VS_OUT1 RenderLightVS(VS_IN invert)
{
    VS_OUT1 outvert;

    // transform the position from object space to clip space
    outvert.vPos = mul(float4(invert.vPos, 1), mViewProj);

    return outvert;
}

float4 RenderLightPS(VS_OUT1 infragm) : SV_Target0
{
    return float4(0.5,0.2,0,1);
}

float4 RenderAxisPS(VS_OUT1 infragm, uniform int axis_dir) : SV_Target0	//axis_dir 0:X, 1:Y, 2:Z
{
	if( axis_dir == 0 )
		return float4(0,1,0,1);
	else if( axis_dir == 1 )
		return float4(0,0,1,1);
	else if( axis_dir == 2 )
		return float4(1,0,0,1);
    else
		return float4(1,1,1,1);
}

float4 RenderFrustumPS(VS_OUT1 infragm) : SV_Target0
{
    return float4( 0,0.2,0.8,1);
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