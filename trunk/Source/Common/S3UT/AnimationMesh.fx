//only used to create the input layout for the animation mesh

Texture2D<float2> DiffuseTex;

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
    float2 Tex : TEXCOORD;
};


float4 ComputeLighting( float3 normal )
{
    return float4(1,1,1,1);
}

VSSceneOutAni VSSceneMain( VSSceneInAni Input )
{
    VSSceneOutAni Output = (VSSceneOutAni)0;
    
    Output.Pos = float4(1,1,1,1);//mul( float4(Input.Pos,1), mWorldNow );
    float3 wNormal = float3(1,1,1);//mul( Input.Normal, (float3x3)mWorldNow );
    Output.Color = float4(1,1,1,1);//ComputeLighting( wNormal );
    Output.Tex = Input.Tex;
 

 
    return Output;
}

float4 PSSceneMain( VSSceneOutAni Input ) : SV_TARGET
{
    return float4(1,1,1,1);//diff*Input.Color;
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


VSSceneOutAni VSSkinnedSceneMain( VSSkinnedSceneInAni Input )
{
    VSSceneOutAni Output = (VSSceneOutAni)0;
    Output.Pos = float4(1,1,1,1);//mul( vSkinned.Pos, g_mBlurViewProj[ MID_TIME_STEP ] );
    float3 blendNorm = float3(1,1,1);//vSkinned.Norm;
    Output.Color = float4(1,1,1,1);//ComputeLighting( blendNorm );
    Output.Tex = Input.Tex;
    return Output;
}


technique10 RenderScene
{
    pass p0
    {
        SetVertexShader( CompileShader( vs_4_0, VSSceneMain() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_4_0, PSSceneMain() ) );
    }
};

technique10 RenderSkinnedScene
{
    pass p0
    {
        SetVertexShader( CompileShader( vs_4_0, VSSkinnedSceneMain() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_4_0, PSSceneMain() ) );
    }
};