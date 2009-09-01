#include "RadialAreaIntegration.fxh"
#include "CommonDef.h"
RasterizerState RStateMSAAON
{
	MultisampleEnable = FALSE; // performance hit is too high with MSAA for this sample
};

Texture2D<float> g_txArea;
Texture2D<float> DepthTex0;
Texture2D<float2> DepthMip2;
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
    float4 g_vMaterialKd;
    float3 g_vLightPos; ///< light in world CS
    float4 g_vLightFlux;
    float g_fFilterSize, g_fDoubleFilterSizeRev;
    row_major float4x4 mViewProj;
    row_major float4x4 mLightView;
    row_major float4x4 mLightViewProjClip2Tex;
    row_major float4x4 mLightProjClip2TexInv;
    row_major float4x4 mLightProj;
    bool bTextured;
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
VS_OUT0 RenderSceneFastVS(VS_IN invert)
{
    VS_OUT0 outvert;

    // transform the position from object space to clip space
    outvert.vPos = mul(float4(invert.vPos, 1), mViewProj);
    outvert.vLightPos = mul(float4(invert.vPos, 1), mLightViewProjClip2Tex);
    // compute light direction
    float3 vLightDir = normalize(g_vLightPos - invert.vPos);
    // compute lighting
    outvert.vDiffColor = (g_vMaterialKd * g_vLightFlux);
    outvert.vDiffColor.xyz *= max(0, dot(invert.vNorm, vLightDir));
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

    return outvert;
}
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
	return vMin;
	
}

float4 AccurateShadow(float3 vLightPos, float4 vDiffColor)
{
return float4(1,1,1,1);
/*	
	float4 vPosLight = mul( float4(vLightPos,1), mLightProj );
	float2 ShadowTexC = ( vPosLight.xy/vPosLight.w ) * 0.5 + float2( 0.5, 0.5 ) ;
	ShadowTexC.y = 1.0 - ShadowTexC.y;
	
	if(   ShadowTexC.x<0   || ShadowTexC.y<0
		||ShadowTexC.x>1.0 || ShadowTexC.y>1.0 )
		return float4(1,1,1,1);
	
	float  Zn = LIGHT_ZN;
	float  Zf = LIGHT_ZF;
	
	
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
		
		Depth1 = abs( tex2Dlod( float2( BLeft,  BTop    ), MipLevel ) );
		Depth2 = abs( tex2Dlod( float2( BLeft,  BBottom ), MipLevel ) );
		Depth3 = abs( tex2Dlod( float2( BRight, BTop    ), MipLevel ) );
		Depth4 = abs( tex2Dlod( float2( BRight, BBottom ), MipLevel ) );
		
		float ZminPers = min( min( Depth1.x, Depth2.x ), min( Depth3.x, Depth4.x ) );
		Zmin = -( Zf * Zn ) / ( ( Zf - Zn ) * ( ZminPers - Zf / ( Zf - Zn ) ) );
		float ZmaxPers = max( max( Depth1.y, Depth2.y ), max( Depth3.y, Depth4.y ) );
		Zmax = -( Zf * Zn ) / ( ( Zf - Zn ) * ( ZmaxPers - Zf / ( Zf - Zn ) ) );
		
		if( Zmin>w )
		{
			return float4(1,1,1,1);
		}
		  
		T_LightWidth  = ( w - Zmin ) * ( LightSize  ) / w,
		T_LightHeight = ( w - Zmin ) * ( LightSize ) / w,

		S_LightWidth  = Zn * T_LightWidth  / Zmin,
		S_LightHeight = Zn * T_LightHeight / Zmin,
		S_LightWidthNorm  = S_LightWidth  / NpWidth,
		S_LightHeightNorm = S_LightHeight / NpHeight;
		
		BLeft   = max( x/w-S_LightWidthNorm,-1) * 0.5 + 0.5;
		BRight  = min( x/w+S_LightWidthNorm,1) * 0.5 + 0.5;
		BBottom = 1 -( min( y/w+S_LightHeightNorm,1) * 0.5 + 0.5 );
		BTop    = 1 -( max( y/w-S_LightHeightNorm,-1) * 0.5 + 0.5 ); 

	}
		
	uint refPX = ( ( x/w ) * 0.5 + 0.5 ) * DEPTH_RES,
		 refPY = ( 1 - ( ( y/w )*0.5 + 0.5 ) ) * DEPTH_RES;
	

    float fTotShadow  = 1,
		  OccArea     = 0;
		  
	uint  nBLeft   = BLeft  *DEPTH_RES,
		  nBRight  = BRight *DEPTH_RES,
		  nBBottom = BBottom*DEPTH_RES,
		  nBTop    = BTop   *DEPTH_RES;
		  
	
	[flatten]if( nBLeft > nBRight || nBBottom > nBTop )
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
	
	uint idx = 0;*/
	return float4(1,1,1,1);
/*	
	[loop]for( int i = nBBottom; i<=nBTop+1;++i){
		[loop]for ( int j=nBLeft;j<=nBRight+1;++j)
		{
			uint2 iPixel = uint2(j,i);
			
			int4 CoordX;
			CoordX[0] = iPixel.x-1;
			CoordX[1] = iPixel.x  ;
			CoordX[2] = iPixel.x  ;
			CoordX[3] = iPixel.x-1;

			int4 CoordY;
			CoordY[0] = iPixel.y  ;
			CoordY[1] = iPixel.y  ;
			CoordY[2] = iPixel.y-1;
			CoordY[3] = iPixel.y-1;

			float4 vDepthMin;
			vDepthMin[0] =  DepthTex0.Load( int3( iPixel.x-1,iPixel.y ,0));
			vDepthMin[1] =  DepthTex0.Load( int3( iPixel.x  ,iPixel.y,0));
			vDepthMin[2] =  DepthTex0.Load( int3( iPixel.x  ,iPixel.y-1,0));
			vDepthMin[3] =  DepthTex0.Load( int3( iPixel.x-1,iPixel.y-1,0));

			
			idx = 0;
			idx |= !(iPixel.x-1<nBLeft || iPixel.x-1>nBRight ||iPixel.y-1<nBBottom || iPixel.y-1>nBTop || vDepthMin[3]>pixel_unit_z);
			idx<<=1;
			idx |=! (iPixel.x<nBLeft   || iPixel.x>nBRight || iPixel.y-1<nBBottom || iPixel.y-1>nBTop || vDepthMin[2]>pixel_unit_z);
			idx<<=1;
			idx |=! (iPixel.x<nBLeft   || iPixel.x>nBRight || iPixel.y<nBBottom || iPixel.y>nBTop || vDepthMin[1]>pixel_unit_z);
			idx<<=1;
			idx |=! (iPixel.x-1<nBLeft || iPixel.x-1>nBRight || iPixel.y<nBBottom || iPixel.y>nBTop || vDepthMin[0]>pixel_unit_z);

			[branch]if( idx>1&&idx<15){
				float2 mar_sqr_idx = g_fMarchingSquare[idx];
				
				uint2  vMinCr = uint2(CoordX[ mar_sqr_idx.x ],CoordY[ mar_sqr_idx.x ]),
					   vMaxCr = uint2(CoordX[ mar_sqr_idx.y ],CoordY[ mar_sqr_idx.y ]);
				
				float2 vMin = BackProj0(vDepthMin[mar_sqr_idx.x].xx,vLightPos,vMinCr);
				float2 vMax = BackProj0(vDepthMin[mar_sqr_idx.y].xx,vLightPos,vMaxCr);
				
				OccArea += (vMin.x+vMax.x)*(vMin.y-vMax.y);
			}				
		}
	}
	fTotShadow-=(OccArea*0.5/(4*g_fFilterSize*g_fFilterSize));
    return float4(fTotShadow,fTotShadow,fTotShadow,1); // this is never reached, but compiler curses if the line is not here
    */
}


float4 RenderSceneAccPS(VS_OUT0 In) : SV_Target0
{
    if (dot(In.vDiffColor.xyz, In.vDiffColor.xyz) == 0)
        return float4(0, 0, 0, 1);
    [flatten] if (bTextured) In.vDiffColor *= DiffuseTex.Sample(DiffuseSampler, In.vTCoord);
    return AccurateShadow(In.vLightPos.xyz, In.vDiffColor);
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

