#include "commondef.h"

#define EVSM
#define EXPC 1
SamplerState PointSampler
{
    Filter = MIN_MAG_MIP_POINT;
    AddressU = Clamp;
    AddressV = Clamp;
};

SamplerState LinearSampler
{
    Filter = MIN_MAG_MIP_LINEAR;
    AddressU = Wrap;
    AddressV = Wrap;
};


struct VS_OUT_SCREEN_POS
{
    float4 vPos : SV_Position; ///< vertex position
    float4 vLightViewPos : TEXCOORD4;
};

struct VS_IN_SCREEN_POS
{
    float3 vPos : POSITION; ///< vertex position
    float3 vNorm : NORMAL; ///< vertex diffuse color (note that COLOR0 is clamped from 0..1)
    float2 vTCoord : TEXCOORD0; ///< vertex texture coords
};

struct VS_OUT_DEFERRED_SHADING
{
    float4 vPos : SV_Position; ///< vertex position
    float3 vNorm : TEXCOORD0;
    float4 vTCoord : TEXCOORD1;
    float4 vWorldPos : TEXCOORD2;
};

struct VS_IN_DEFERRED_SHADING
{
    float3 vPos : POSITION; ///< vertex position
    float3 vNorm : NORMAL; ///< vertex diffuse color (note that COLOR0 is clamped from 0..1)
    float2 vTCoord : TEXCOORD0; ///< vertex texture coords
};

struct VS_IN_DEFERRED_SHADING_SKINNED
{
    float3 vPos : POSITION;
    float3 vNorm : NORMAL;
    float2 vTCoord : TEXCOORD;
    float3 vTan : TANGENT;
    uint4 Bones : BONES;
    float4 Weights : WEIGHTS;
};


float4x4 g_mScale = { SCALE,0,0,0,
					  0,SCALE,0,0,
					  0,0,SCALE,0,
					  0,0,0,1.0 };


float4 diffuse_color = { 185.0/256.0, 185.0/256.0, 255.0/256.0, 1 };

//-----------------------------------------------------------------------------
// Name: QuadVS
// Type: Vertex Shader
// Desc: 
//-----------------------------------------------------------------------------
struct QuadVS_Input
{
    float4 Pos : POSITION;
    float4 Tex : TEXCOORD0;
};

struct QuadVS_Output
{
    float4 Pos : SV_POSITION;              // Transformed position
    float4 Tex : TEXCOORD0;
};

QuadVS_Output QuadVS( QuadVS_Input Input )
{
    QuadVS_Output Output;
    Output.Pos = Input.Pos;
    Output.Tex = Input.Tex;
    return Output;
}

//-----------------------------------------------------------------------------
// Name: FinalPass
// Type: Pixel Shader
// Desc: 
//-----------------------------------------------------------------------------
float4 QuadPS( QuadVS_Output Input ) : SV_TARGET
{   
    return Input.Tex;
}
DepthStencilState DisableDepth
{
    DepthEnable = FALSE;
    DepthWriteMask = ZERO;
};
technique10 FinalPass
{
    pass p0
    {
        SetVertexShader( CompileShader( vs_4_0, QuadVS() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_4_0, QuadPS() ) );  
        SetDepthStencilState( DisableDepth, 0 );
    }
}

// Converting normalized floats to UINTs for storage in a SAT
// NOTE: Can compute a "safe" value for this from texture size and filter width ranges,
// but this value works quite well for our demo, and trial and error will arguably 
// produce better results anyways.
// However, most applications won't need gigantic filters, in which case this value can
// be raised to obtain even better numeric precision.
static const uint g_SATUINTPrecisionBits = 14;
//static const float g_SATUINTMaxFilterWidth = 1 << ((32 - g_SATUINTPrecisionBits) / 2);
static const float g_NormalizedFloatToSATUINT = 1 << g_SATUINTPrecisionBits;
// Factor to use to distribute FP precision
// TODO: Perhaps make this dependent on shadow map size and z-scale at least
// Really we're just waiting for GPU doubles though...
static const float g_DistributeFPFactor = 512;
