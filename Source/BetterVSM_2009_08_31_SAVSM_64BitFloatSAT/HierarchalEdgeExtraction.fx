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
	spec_coe = pow( spec_coe,high_light_coe);
	float  diff_coe = saturate(dot(surfNorm,lightDirInLightView));

	float4 ret_color = g_vLightAmbient*diffuse_clr*g_vLightAmbientClr + ( diffuse_clr * diff_coe + spec_coe * spec_clr ) * shadow_coe;

   return ret_color;

}

SamplerComparisonState ShadowSampler
{
    ComparisonFunc = GREATER;
    Filter = COMPARISON_MIN_MAG_MIP_POINT;
    AddressU = Border;
    AddressV = Border;
    BorderColor = float4(1.e30f, 0, 0, 0);
};

//--------------------------------------------------------------------------------------
// Pixel shader output structure
//--------------------------------------------------------------------------------------
float4 RenderSceneNoShadowsPS(VS_OUT1 infragm) : SV_Target0
{
    return 1;
}


float2 tex2Dlod( float2 texC, int level )
{
	texC = saturate( texC );
	float2 vPixel = floor( texC * g_fRes[level] ) + 0.5;
    [flatten] if (level != 0)
    { vPixel += float2(DEPTH_RES, 1 << (N_LEVELS - level)); }
    vPixel /= float2(DEPTH_RES * 3 / 2, DEPTH_RES);
    float2 vMinMax = DepthMip2.SampleLevel(DepthSampler, vPixel, 0);
    return vMinMax;

}


float2 BackProj0( float2 vDepthMin, float3 vLightPos, uint2 iPixel )
{

	vDepthMin = 1. / (vDepthMin * mLightProjClip2TexInv[2][3] + mLightProjClip2TexInv[3][3]);
	float2 vMin = 0.5 - float2(iPixel.x, iPixel.y) * g_fResRev[0];
	vMin *= 2 * float2(mLightProjClip2TexInv[3][0], mLightProjClip2TexInv[3][1]);
	vMin = (vMin * vLightPos.zz - vLightPos.xy) / (vLightPos.zz / vDepthMin.xy - 1);
	
	vMin.x=min(g_fFilterSize,max(-g_fFilterSize,vMin.x));
	vMin.y=min(g_fFilterSize,max(-g_fFilterSize,vMin.y));
	
	vMin = (vMin + g_fFilterSize)/(2*g_fFilterSize);//normalized between 0,1
	
	return vMin;
	
}

//if you want to use light space multi-res method, you cant only change mip_level, other changes must be made
float4 AccurateShadow(float4 vPos,float4 vDiffColor)
{
	float4 vLightPos = ShadowMapPos.Load(int3(vPos.x-0.5,vPos.y-0.5,0));
	float4 vHSMKernel = g_txHSMKernel.Load(int3(vPos.x-0.5,vPos.y-0.5,0));
	float4 vPosLight = mul( float4(vLightPos.xyz,1), mLightProj );
	float2 ShadowTexC = ( vPosLight.xy/vPosLight.w ) * 0.5 + float2( 0.5, 0.5 ) ;
	ShadowTexC.y = 1.0 - ShadowTexC.y;
	
	if(   ShadowTexC.x<0   || ShadowTexC.y<0
		||ShadowTexC.x>1.0 || ShadowTexC.y>1.0 )
		return float4(1,1,1,1);

	float  Zn = g_fLightZn;
	float  Zf = g_fLightZn + LIGHT_ZF_DELTA;
	
	
	float  LightSize = g_fFilterSize;
	float  w = vPosLight.w,
		   x = vPosLight.x,
		   y = vPosLight.y;
		   
	float pixel_unit_z = vPosLight.z/vPosLight.w;
	float refPX = ( ( x/w ) * 0.5 + 0.5 ) * DEPTH_RES + 0.5,
		  refPY = ( 1 - ( ( y/w )*0.5 + 0.5 ) ) * DEPTH_RES + 0.5;

	//---------------------------------	  
	uint  right_bottom_x = round(refPX);
	uint  right_bottom_y = round(refPY);
	float frc_x = frac( refPX );
	float frc_y = frac( refPY );
	
	int4 CoordX;
	CoordX[0] = right_bottom_x-1;
	CoordX[1] = right_bottom_x  ;
	CoordX[2] = right_bottom_x  ;
	CoordX[3] = right_bottom_x-1;

	int4 CoordY;
	CoordY[0] = right_bottom_y  ;
	CoordY[1] = right_bottom_y  ;
	CoordY[2] = right_bottom_y-1;
	CoordY[3] = right_bottom_y-1;

	float4 vDepthMin;
	vDepthMin[0] =  DepthTex0.Load( int3( right_bottom_x-1,right_bottom_y  ,0));
	vDepthMin[1] =  DepthTex0.Load( int3( right_bottom_x  ,right_bottom_y  ,0));
	vDepthMin[2] =  DepthTex0.Load( int3( right_bottom_x  ,right_bottom_y-1,0));
	vDepthMin[3] =  DepthTex0.Load( int3( right_bottom_x-1,right_bottom_y-1,0));
	uint idx = 0;
	float depth_bias = DepthBiasDefault;

	idx |= !(vDepthMin[3]>pixel_unit_z - depth_bias);
	idx<<=1;
	idx |=! (vDepthMin[2]>pixel_unit_z - depth_bias);
	idx<<=1;
	idx |=! (vDepthMin[1]>pixel_unit_z - depth_bias);
	idx<<=1;
	idx |=! (vDepthMin[0]>pixel_unit_z - depth_bias);
	uint gidx = idx;
	
	float init_vf = 1;
	
	float2 mar_sqr_idx = g_fMarchingSquare[idx];
	
	uint2  vMinCr = uint2(CoordX[ mar_sqr_idx.x ],CoordY[ mar_sqr_idx.x ]),
		   vMaxCr = uint2(CoordX[ mar_sqr_idx.y ],CoordY[ mar_sqr_idx.y ]);
	
	float2 vMin = BackProj0(vDepthMin[mar_sqr_idx.x].xx,vLightPos,vMinCr);
	float2 vMax = BackProj0(vDepthMin[mar_sqr_idx.y].xx,vLightPos,vMaxCr);
	
	float3 center_edge = float3(vMax,0)-float3(vMin,0);
	float3 center_from_edge_start = float3(float3(x/w,y/w,0)-float3(vMin,0));
	float  len = length(cross(center_edge,center_from_edge_start));
	if( len > 0 )
		init_vf = 0;
	if( idx == 0 ) init_vf = 1;
	if( idx == 15 ) init_vf = 0;

    float fTotShadow  = 1,
		  OccArea     = 0;
		  
	uint  nBLeft   = vHSMKernel.x*DEPTH_RES,
		  nBRight  = vHSMKernel.y*DEPTH_RES,
		  nBBottom = vHSMKernel.z*DEPTH_RES,
		  nBTop    = vHSMKernel.w*DEPTH_RES;

	[flatten]if( nBLeft >= nBRight || nBBottom >= nBTop )
	{
	
		nBLeft  = refPX - 1;
		nBRight = refPX + 1;
		nBBottom = refPY - 1;
		nBTop = refPY + 1;
	}
		
	uint mip_level = 0;
	
	nBLeft = clamp( nBLeft, 0, DEPTH_RES );
	nBRight = clamp( nBRight, 0, DEPTH_RES );
	nBBottom = clamp( nBBottom, 0, DEPTH_RES );
	nBTop = clamp( nBTop, 0, DEPTH_RES );
	
	nBLeft>>=mip_level;
	nBRight>>=mip_level;
	nBBottom>>=mip_level;
	nBTop>>=mip_level;
	
	if( nBTop - nBBottom > 400 || nBRight - nBLeft > 400 )
		return float4(1,0,0,1);
	
		
	idx = 0;   
    uint pStackLow = 0xffffffff, pStackHigh;
    uint iPix = 0;
    
    uint3 iLevel = uint3(0, 0, N_LEVELS - 1);
    
    uint left = DEPTH_RES,right =0 ,bottom = DEPTH_RES, top = 0;
    float minZ = 1, maxZ =0;

	float sample_num = 0;

    [loop] for ( ; ; )
    {
        uint2 iPixel = uint2(iLevel.x + (iPix & 1), iLevel.y + (iPix >> 1));
        float2 vPixel = iPixel + 0.5;
        
        uint l_left = nBLeft>>iLevel.z;
        uint l_right = (nBRight>>iLevel.z) + 1;
        uint l_bottom = nBBottom>>iLevel.z;
        uint l_top = (nBTop>>iLevel.z) +1;
        									  									  
        [flatten] if (iLevel.z != 0)
        { vPixel += float2(DEPTH_RES, 1 << (N_LEVELS - iLevel.z)); }
        vPixel /= float2(DEPTH_RES * 3 / 2, DEPTH_RES);
        float2 vMinMax = DepthMip2.SampleLevel(DepthSampler, vPixel, 0);
        
        sample_num += 1.0;

        bool is_occluder_edge = clamp(iPixel.x, l_left, l_right)==iPixel.x &&
								clamp(iPixel.y, l_bottom, l_top)==iPixel.y &&
								clamp( pixel_unit_z, vMinMax.x, vMinMax.y ) == pixel_unit_z;

        bool bNextLevel = (iLevel.z > mip_level) && is_occluder_edge;
                          
        [branch] if (iLevel.z == mip_level && is_occluder_edge){
			
			int4 CoordX = {iPixel.x-1,iPixel.x,iPixel.x,iPixel.x-1};

			int4 CoordY = {iPixel.y,iPixel.y,iPixel.y-1,iPixel.y-1};

			float4 vDepthMin;
			vDepthMin[0] =  DepthTex0.Load( int3( iPixel.x-1,iPixel.y   ,0));
			vDepthMin[1] =  DepthTex0.Load( int3( iPixel.x  ,iPixel.y   ,0));
			vDepthMin[2] =  DepthTex0.Load( int3( iPixel.x  ,iPixel.y-1 ,0));
			vDepthMin[3] =  DepthTex0.Load( int3( iPixel.x-1,iPixel.y-1 ,0));
						
			idx = 0;
			idx |= !(vDepthMin[3]>pixel_unit_z - depth_bias);
			idx<<=1;
			idx |=! (vDepthMin[2]>pixel_unit_z - depth_bias);
			idx<<=1;
			idx |=! (vDepthMin[1]>pixel_unit_z - depth_bias);
			idx<<=1;
			idx |=! (vDepthMin[0]>pixel_unit_z - depth_bias);
			
						
			[branch]if( idx>1&&idx<15){

				float2 mar_sqr_idx = g_fMarchingSquare[idx];
				
				uint2  vMinCr = uint2(CoordX[ mar_sqr_idx.x ],CoordY[ mar_sqr_idx.x ]),
					   vMaxCr = uint2(CoordX[ mar_sqr_idx.y ],CoordY[ mar_sqr_idx.y ]);
				
				float2 vMin = BackProj0(vDepthMin[mar_sqr_idx.x].xx,vLightPos,vMinCr);
				float2 vMax = BackProj0(vDepthMin[mar_sqr_idx.y].xx,vLightPos,vMaxCr);
				
				//int R = 32 - 1;
				vMin = floor((vMin*62 + 1)/2);//62=2*R
				vMax = floor((vMax*62 + 1)/2);
				//int2 texcrd = vMax * 32 + vMin;
				float tmp_area = -g_txArea.Load(int3(vMax * 32 + vMin,0));
				//tmp_area = -tmp_area;
				OccArea += tmp_area;
			}				

		}
        
        [flatten] if (bNextLevel) iLevel.xy = iPixel + iPixel;
        // new values only rewrite old ones if we actually go to the next level
        bool bPushToStack = bNextLevel & (iPix < 3);
        [flatten] if (bPushToStack)
        {
            pStackHigh = (pStackLow & 0xfc000000) | (pStackHigh >> 6);
            pStackLow = (pStackLow << 6) | iLevel.z * 4 | (iPix + 1);
        }
        iLevel.z -= bNextLevel; // go to more detailed level
        [flatten] if (bNextLevel) iPix = 0;
        else iPix += 1;

        // now get values from stack if necessary
        uint iPrevLevel = iLevel.z;
        [branch] if (iPix >= 4)
        {
            iLevel.z = (pStackLow >> 2) & 0xf;
            iPix = pStackLow & 3;
            pStackLow = (pStackLow >> 6) | (pStackHigh & 0xfc000000);
            pStackHigh *= 64;
        }
        iLevel.xy = (iLevel.xy >> (iLevel.z - iPrevLevel)) & 0xfffffffe;
        if (iLevel.z == 0xf)
        {
			fTotShadow = init_vf + OccArea;
			if( fTotShadow < 0 && gidx != 15)
			{
				fTotShadow = 1.0 + OccArea;
			}
			if( fTotShadow > 1 && gidx != 0)
			{ 
				fTotShadow = 0 + OccArea;
			}
			if( OccArea == 0 && gidx != 15 )
				fTotShadow = 1 + OccArea;
			if( OccArea == 1.0 )
				fTotShadow = 0.0;
				
	   		if( /*fTotShadow <= 0 ||*/ fTotShadow >= 1) return float4(1,1,1,1);
			float factor = sample_num / 2500.0;
			float4 red = {1,0,0,1};
			float4 blue = {0,0,1,1};
			float4 ratio = red * factor + blue * (1-factor); 
            return ratio;

			//return float4(fTotShadow,fTotShadow,fTotShadow,1); // this is never reached, but compiler curses if the line is not here
        }
    }
    return float4(1, 0, 0, 1); // this is never reached, but compiler curses if the line is not here
}

float4 RenderSceneAccPS(VS_OUT0 In) : SV_Target0
{
    if (dot(In.vDiffColor.xyz, In.vDiffColor.xyz) == 0)
        return float4(0, 0, 0, 1);
    [flatten] if (bTextured) In.vDiffColor *= DiffuseTex.Sample(DiffuseSampler, In.vTCoord);
    return AccurateShadow(In.vPos, In.vDiffColor) * diffuse_color;
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
	float4 diff = float4(1,1,1,1);
	[flatten] if (bTextured) diff = DiffuseTex.Sample( DiffuseSampler, In.vTCoord);
    diff.a = 1;

	float3 surfNorm = In.vNorm;

	float4 ret_color;
	ret_color = AccurateShadow(In.vPos,float4(1,1,1,1));
			
	return phong_shading(In.vLightPos.xyz,g_vCameraInLight.xyz,surfNorm,SkinSpecCoe,diff,ret_color,spec_clr_ogre);
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

//-------------------------------------------------------------------------------------------------
//		Render Kernel Size
//-------------------------------------------------------------------------------------------------

float4 HSMKernel(float4 vPos)
{
	float4 vLightPos = ShadowMapPos.Load(int3(vPos.x-0.5,vPos.y-0.5,0));
	float4 vPosLight = mul( float4(vLightPos.xyz,1), mLightProj );
	float2 ShadowTexC = ( vPosLight.xy/vPosLight.w ) * 0.5 + float2( 0.5, 0.5 ) ;
	ShadowTexC.y = 1.0 - ShadowTexC.y;
	
	if(   ShadowTexC.x<0   || ShadowTexC.y<0
		||ShadowTexC.x>1.0 || ShadowTexC.y>1.0 )
		return float4(1,1,1,1);
	
	float  Zn = g_fLightZn;
	float  Zf = g_fLightZn + LIGHT_ZF_DELTA;
	
	
	float  LightSize = g_fFilterSize;
	float  w = vPosLight.w,
		   x = vPosLight.x,
		   y = vPosLight.y;
		   
	float pixel_unit_z = vPosLight.z/vPosLight.w;
		   
	float  scale = ( w - Zn )/w;
	float  LightWidthPers  = LightSize  * scale,
		   LightHeightPers = LightSize * scale;
	
	float4x4 g_mLightProj = mLightProj;
	float	 NpWidth  = Zn/g_mLightProj[0][0],
		     NpHeight = Zn/g_mLightProj[1][1];
		     
	float  LightWidthPersNorm  = LightWidthPers /NpWidth,
		   LightHeightPersNorm = LightHeightPers/NpHeight;
		   
	float  BLeft   = max( x/w-LightWidthPersNorm,-1) * 0.5 + 0.5,
		   BRight  = min( x/w+LightWidthPersNorm,1) * 0.5 + 0.5,
		   BBottom = 1 -( min( y/w+LightHeightPersNorm,1) * 0.5 + 0.5 ),
		   BTop    = 1 -( max( y/w-LightHeightPersNorm,-1) * 0.5 + 0.5 ); 

	float	T_LightWidth, 
			T_LightHeight,
			S_LightWidth ,
			S_LightHeight,
			S_LightWidthNorm = LightWidthPersNorm, 
			S_LightHeightNorm = LightHeightPersNorm;
	
	float2	Depth1,
			Depth2,
			Depth3,
			Depth4;
	
	float Zmin,Zmax;		
	[loop]for( int cnt = 0; cnt < 2 ; cnt ++ ){
	
		//we calculate the mip_level to cover a range 2*S_LightXXXXNorm, not to cover S_LightXXXXNorm
		//you misunderstood that before and write max( S_LightWidthNorm, S_LightHeightNorm ) which causes some incorrect kernel size
		int  MipLevel = max( 2*S_LightWidthNorm, 2*S_LightHeightNorm ) * DEPTH_RES;
		MipLevel = min(ceil( log2( (float)MipLevel ) ),N_LEVELS - 1);
		//you must limit the mip level, otherwise it will sample outside the plannar HSM and return 1.0
		
		Depth1 = saturate(abs( tex2Dlod( float2( BLeft,  BTop    ), MipLevel ) ));
		Depth2 = saturate(abs( tex2Dlod( float2( BLeft,  BBottom ), MipLevel ) ));
		Depth3 = saturate(abs( tex2Dlod( float2( BRight, BTop    ), MipLevel ) ));
		Depth4 = saturate(abs( tex2Dlod( float2( BRight, BBottom ), MipLevel ) ));
		
		float ZminPers = min( min( Depth1.x, Depth2.x ), min( Depth3.x, Depth4.x ) );
		Zmin = -( Zf * Zn ) / ( ( Zf - Zn ) * ( ZminPers - Zf / ( Zf - Zn ) ) );
		float ZmaxPers = max( max( Depth1.y, Depth2.y ), max( Depth3.y, Depth4.y ) );
		Zmax = -( Zf * Zn ) / ( ( Zf - Zn ) * ( ZmaxPers - Zf / ( Zf - Zn ) ) );
				  
		T_LightWidth  = ( w - Zmin ) * ( LightSize  ) / w,
		T_LightHeight = ( w - Zmin ) * ( LightSize ) / w,

		S_LightWidth  = Zn * T_LightWidth  / Zmin,
		S_LightHeight = Zn * T_LightHeight / Zmin,
		S_LightWidthNorm  = S_LightWidth  / NpWidth,
		S_LightHeightNorm = S_LightHeight / NpHeight;
		
		BLeft   = saturate(max( x/w-S_LightWidthNorm,-1) * 0.5 + 0.5);
		BRight  = saturate(min( x/w+S_LightWidthNorm,1) * 0.5 + 0.5);
		BBottom = saturate(1 -( min( y/w+S_LightHeightNorm,1) * 0.5 + 0.5 ));
		BTop    = saturate(1 -( max( y/w-S_LightHeightNorm,-1) * 0.5 + 0.5 )); 
	}
	
	if( Zmin>w )
	{
		return float4(1,1,1,1);
	}
	else
	{
		return float4(BLeft,BRight,BBottom,BTop);
	}
}


float4 RenderHSMKernelPS(VS_OUT0 In) : SV_Target0
{
    if (dot(In.vDiffColor.xyz, In.vDiffColor.xyz) == 0)
        return float4(0, 0, 0, 0);
    return HSMKernel(In.vPos);
}

technique10 RenderHSMKernel
{
    pass P0
    {
        SetVertexShader(CompileShader(vs_4_0, RenderSceneAccVS()));
        SetGeometryShader(NULL);
        SetPixelShader(CompileShader(ps_4_0, RenderHSMKernelPS()));
		SetRasterizerState(RStateMSAAON);
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
    
    Output.Pos = mul( float4(Input.Pos,1), mWorldNow );
    Output.Pos = mul( Output.Pos, mViewProjNow );
    float3 wNormal = mul( Input.Normal, (float3x3)mWorldNow );
    
    Output.vNorm = normalize( mul( Input.Normal, (float3x3)mLightView ) );
    
    Output.Color = ComputeLighting( wNormal );
    Output.Tex = Input.Tex;
 
    Output.vLightPos = mul(float4(Input.Pos, 1), mWorldNow);
    Output.vLightPos = mul( Output.vLightPos, g_mScale);
    Output.vLightPos = mul( Output.vLightPos,mLightView); 

 
    return Output;
}

float4 PSSceneMain( VSSceneOutAni Input ) : SV_TARGET
{
	float4 diff = float4(1,1,1,1);
	[flatten] if (bTextured) diff = DiffuseTex.Sample( g_samLinear, Input.Tex);
    diff.a = 1;

	float3 surfNorm = Input.vNorm;

	REVERT_NORM;

	float4 ret_color;
	ret_color = AccurateShadow(Input.Pos,float4(1,1,1,1));
			
	return phong_shading(Input.vLightPos.xyz,g_vCameraInLight.xyz,surfNorm,SkinSpecCoe,diff,ret_color,spec_clr_ogre);
}

float4 PSKernelMain( VSSceneOutAni Input ) : SV_TARGET
{
    return HSMKernel(Input.Pos);
}

float4 PSPosMain( VSSceneOutAni Input ) : SV_TARGET
{
    return Input.vLightPos;
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
    Output.Pos = mul( vSkinned.Pos, g_mBlurViewProj[ MID_TIME_STEP ] );
    
    // Lighting
    float3 blendNorm = vSkinned.Norm;
    Output.Color = ComputeLighting( blendNorm );
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

technique10 RenderSceneKernel
{
    pass p0
    {
        SetVertexShader( CompileShader( vs_4_0, VSSceneMain() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_4_0, PSKernelMain() ) );
        
        SetDepthStencilState( DepthTestNormal, 0 );
    }
};

technique10 RenderSkinnedSceneKernel
{
    pass p0
    {
        SetVertexShader( CompileShader( vs_4_0, VSSkinnedSceneMain() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_4_0, PSKernelMain() ) );
        
        SetDepthStencilState( DepthTestNormal, 0 );
    }
};

technique10 RenderScenePos
{
    pass p0
    {
        SetVertexShader( CompileShader( vs_4_0, VSSceneMain() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_4_0, PSPosMain() ) );
    }
};

technique10 RenderSkinnedScenePos
{
    pass p0
    {
        SetVertexShader( CompileShader( vs_4_0, VSSkinnedSceneMain() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_4_0, PSPosMain() ) );
        
        SetDepthStencilState( DepthTestNormal, 0 );
    }
};