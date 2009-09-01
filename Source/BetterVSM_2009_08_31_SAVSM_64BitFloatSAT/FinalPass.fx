#include "DeferredShading.fxh"
#include "CommonDef.h"

Texture2D<float4> TexFinalResult;

float4 FinalPresentQuadPS( QuadVS_Output Input ) : SV_TARGET
{   
    return TexFinalResult.Load( int3( Input.Pos.x - 0.5, Input.Pos.y - 0.5, 0 ) );
}
technique10 FinalPresentPass
{
    pass p0
    {
        SetVertexShader( CompileShader( vs_4_0, QuadVS() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_4_0, FinalPresentQuadPS() ) );  
        SetDepthStencilState( DisableDepth, 0 );
    }
}

