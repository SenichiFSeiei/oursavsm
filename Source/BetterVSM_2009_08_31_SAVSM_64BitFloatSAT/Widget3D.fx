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
    return float4(1,0,0,1);
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
