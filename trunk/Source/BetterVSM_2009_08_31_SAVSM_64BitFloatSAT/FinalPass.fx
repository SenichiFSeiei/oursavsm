#include "DeferredShading.fxh"
#include "CommonDef.h"

Texture2D<float4> TexFinalResult;
Texture2D<float4> TexPosInWorld;

float4 FinalPresentQuadPS( QuadVS_Output Input ) : SV_TARGET
{
	//return TexFinalResult.Load( int3( Input.Pos.x - 0.5, Input.Pos.y - 0.5, 0 ) );
	int off = 1;
	float4 result = {0,0,0,0};
	int effect_num = 0;
	float4 ref = TexPosInWorld.Load( int3( Input.Pos.x - 0.5, Input.Pos.y - 0.5, 0 ) );
	for( int i = -off; i<=off; ++i )
	{
		for( int j = -off; j<=off; ++j )
		{
			float4 tmp = TexFinalResult.Load( int3( Input.Pos.x - 0.5, Input.Pos.y - 0.5, 0 ), int2(i,j) ); 
			float4 tmp_pos = TexPosInWorld.Load( int3( Input.Pos.x - 0.5, Input.Pos.y - 0.5, 0 ), int2(i,j) ); 
			if( (tmp_pos.x - ref.x)*(tmp_pos.x - ref.x)+(tmp_pos.y - ref.y)*(tmp_pos.y - ref.y)+(tmp_pos.z - ref.z)*(tmp_pos.z - ref.z) < 0.1 )
			{
				++effect_num;
				result += tmp;
			}
			
		}
	} 
	result /= effect_num;
	return result;
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

