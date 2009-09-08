//----------------------------------------------------------------------------------
// File:   SoftShadows.fx
// Author: Baoguang Yang
// 
// Copyright (c) 2009 S3Graphics Corporation. All rights reserved.
// 
// The render algorithm of High Quality Adaptive Soft Shadow Mapping without adaptive
// Accelerations.
//
//----------------------------------------------------------------------------------
//#define FIX_KERNEL
//#define GAUSSIAN_SAMPLE

#include "DeferredShading.fxh"
#include "IntSATUtil.fxh"
#include "CommonDef.h"
RasterizerState RStateMSAAON
{
	MultisampleEnable = FALSE; // performance hit is too high with MSAA for this sample
};

Texture2D<float4> VSMMip2;
Texture2D<float>  TexDepthMap;

#ifdef USE_INT_SAT
Texture2D<uint2> SatVSM;
#else
#ifdef DISTRIBUTE_PRECISION
Texture2D<float4> SatVSM;
#else
Texture2D<float2> SatVSM;
#endif
#endif
Texture2DArray<float2> DepthNBuffer;

Texture2D<float4> TexPosInWorld;
Texture2D<float4> TexPreviousResult;
Texture2D<float4> TexNormalInWorld;
Texture2D<float4> TexColor;

cbuffer cb0 : register(b0)
{
	float3 VCameraInLight;//specular
    float4 VLightFlux;
    float fFilterSize;
    row_major float4x4 mViewProj;
    row_major float4x4 mLightView;
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
    float fLightZn;
    float fScreenWidth;
    float fScreenHeight;
    float fLumiFactor;

};

cbuffer cb1 : register(b1)
{
	RES_REV;//Marco in CommonDef.h, defines the constants representing the rev of the res of HSM levels
	RES;//Marco in CommonDef.h, defines the constants representing the res of HSM levels
	MS;
	int depth_sample_num = 64;

};

float4 phong_shading( float3 light_space_pos, float3 light_space_camera_pos, float3 surf_norm, 
					  int high_light_coe, float4 diffuse_clr,float4 shadow_coe,
					  float4 spec_clr )
{
    float3 lightDirInLightView = normalize(float3( 0,0,0 ) - light_space_pos);
    float3 viewDirInLightView  = normalize(light_space_camera_pos - light_space_pos);
    
 	float3 surfNorm = surf_norm;
 	float3 H = normalize(viewDirInLightView+lightDirInLightView);
	float  spec_coe = saturate(dot(H,surfNorm));
	spec_coe = pow( spec_coe,50);
	float  diff_coe = saturate(dot(surfNorm,lightDirInLightView));

	float4 ret_color = ( diffuse_clr * diff_coe + spec_coe * spec_clr ) * VLightFlux * shadow_coe;

   return ret_color;

}

float2 FiveCase( int nBufferLevel, float Width, float Height, float Left, float Right, float Top, float Bottom )
{
	float2 Depth1, Depth2, Depth3, Depth4;
	int NBLevel_Squared0 = pow( 2, nBufferLevel );
	int NBLevel_Squared1 = pow( 2, nBufferLevel-1 );
	if ( (Width >= NBLevel_Squared0) && (Width < (2*NBLevel_Squared0)) && (Height >= NBLevel_Squared0) && (Height < (2*NBLevel_Squared0)) )
	{
		Depth1 = DepthNBuffer.Load( int4(                    Left, Bottom + NBLevel_Squared0, nBufferLevel, 0) );
		Depth2 = DepthNBuffer.Load( int4(                    Left,                       Top, nBufferLevel, 0) );
		Depth3 = DepthNBuffer.Load( int4(Right - NBLevel_Squared0,                       Top, nBufferLevel, 0) );
		Depth4 = DepthNBuffer.Load( int4(Right - NBLevel_Squared0, Bottom + NBLevel_Squared0, nBufferLevel, 0) );
		return float2(min( min( abs(Depth1.x), abs(Depth2.x) ), min( abs(Depth3.x), abs(Depth4.x) ) ), max( max( abs(Depth1.y), abs(Depth2.y) ), max( abs(Depth3.y), abs(Depth4.y) ) ));
	}
	else if ( Width > Height )
	{
		if ( (Width > NBLevel_Squared0) && (Width < (2*NBLevel_Squared0)) && ( Height < NBLevel_Squared0 ) )
		{
			Depth1 = DepthNBuffer.Load( int4(                    Left, Bottom + NBLevel_Squared0, nBufferLevel, 0) );
			Depth2 = DepthNBuffer.Load( int4(Right - NBLevel_Squared0, Bottom + NBLevel_Squared0, nBufferLevel, 0) );
			return float2(min( abs(Depth1.x), abs(Depth2.x) ),max( abs(Depth1.y), abs(Depth2.y) ));
		}
		else
		{
			Depth1 = DepthNBuffer.Load( int4(                     Left, Bottom + NBLevel_Squared1, nBufferLevel-1, 0) );
			Depth2 = DepthNBuffer.Load( int4(  Left + NBLevel_Squared1, Bottom + NBLevel_Squared1, nBufferLevel-1, 0) );
			Depth3 = DepthNBuffer.Load( int4( Right - NBLevel_Squared1, Bottom + NBLevel_Squared1, nBufferLevel-1, 0) );
			Depth4 = DepthNBuffer.Load( int4( Right - NBLevel_Squared0, Bottom + NBLevel_Squared1, nBufferLevel-1, 0) );
			return float2(min( min( abs(Depth1.x), abs(Depth2.x) ), min( abs(Depth3.x), abs(Depth4.x) ) ), max( max( abs(Depth1.y), abs(Depth2.y) ), max( abs(Depth3.y), abs(Depth4.y) ) ));
		}
	}
	else
	{
		if ( (Height > NBLevel_Squared0) && (Height < (2*NBLevel_Squared0)) && ( Width < NBLevel_Squared0 ) )
		{
			Depth1 = DepthNBuffer.Load( int4( Left,                       Top, nBufferLevel, 0) );
			Depth2 = DepthNBuffer.Load( int4( Left, Bottom + NBLevel_Squared0, nBufferLevel, 0) );
			return float2(min( abs(Depth1.x), abs(Depth2.x) ),max( abs(Depth1.y), abs(Depth2.y) ));
		}
		else
		{
			Depth1 = DepthNBuffer.Load( int4( Left,                       Top, nBufferLevel-1, 0) );
			Depth2 = DepthNBuffer.Load( int4( Left,    Top - NBLevel_Squared1, nBufferLevel-1, 0) );
			Depth3 = DepthNBuffer.Load( int4( Left, Bottom + NBLevel_Squared1, nBufferLevel-1, 0) );
			Depth4 = DepthNBuffer.Load( int4( Left, Bottom + NBLevel_Squared0, nBufferLevel-1, 0) );
			return float2(min( min( abs(Depth1.x), abs(Depth2.x) ), min( abs(Depth3.x), abs(Depth4.x) ) ), max( max( abs(Depth1.y), abs(Depth2.y) ), max( abs(Depth3.y), abs(Depth4.y) ) ));
		}		
	}
}

float4 AccurateShadowIntSAT(float4 vPos, float4 vDiffColor, bool limit_kernel = false, bool use_bias = true)
{
	float depth_bias = 0.01;
	float4 vLightPos = TexPosInWorld.Load(int3(vPos.x-0.5,vPos.y-0.5,0));	
	vLightPos = mul( float4(vLightPos.xyz,1), mLightView );
	
	float4 vPosLight = mul( float4(vLightPos.xyz,1), mLightProj );
	float2 ShadowTexC = ( vPosLight.xy/vPosLight.w ) * 0.5 + float2( 0.5, 0.5 ) ;
	ShadowTexC.y = 1.0 - ShadowTexC.y;
	
	if( ShadowTexC.x > 1.0 || ShadowTexC.x < 0.0  || ShadowTexC.y > 1.0 || ShadowTexC.y < 0.0 )
		return float4( 1,1,1,1 );
	
	//---------------------------------------------------------------------------------
	float  Zn = fLightZn;
	float  Zf = fLightZn + LIGHT_ZF_DELTA;
	float  w = vPosLight.w,
		   x = vPosLight.x,
		   y = vPosLight.y;
	float pixel_unit_z = vPosLight.z/vPosLight.w;
	
	if( pixel_unit_z > 0.99 ) 
		return float4( 1,1,1,1 );
	
//calculate the filter kernel -------------------------------------------------------------------------------------
	float  LightSize = fFilterSize;
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
		   
	float radius_in_pixel = ( BRight - BLeft ) * DEPTH_RES / 2;
	float3  center_coord = float3( floor( ShadowTexC * DEPTH_RES ) - float2(0.5,0.5), 0 );	   
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
	float sum_depth = 0;
	bool variance_not_reliable = false;
	{
		float2 uv_off = frac( ShadowTexC * DEPTH_RES - float2(0.5,0.5) );

		float2 moments = {0.0,0.0};
		float2 moments0, moments1, moments2, moments3;
		float  rescale = 1/g_NormalizedFloatToSATUINT;
		int   offset = max(1,( BRight - BLeft ) * DEPTH_RES / 2);
		{
			int3  int_coord_rb = center_coord + int3(  offset, offset,0 );
			int3  int_coord_lt = center_coord + int3( -offset,-offset,0 );
			int3  int_coord_rt = center_coord + int3(  offset,-offset,0 );
			int3  int_coord_lb = center_coord + int3( -offset, offset,0 );

			uint2  d_rb = SatVSM.Load( int_coord_rb );
			uint2  d_lt = SatVSM.Load( int_coord_lt );
			uint2  d_rt = SatVSM.Load( int_coord_rt ); 
			uint2  d_lb = SatVSM.Load( int_coord_lb ); 
			moments0 = (d_rb - d_rt - d_lb + d_lt);
			moments0 /= ((offset*2)*(offset*2));
			moments0 *= rescale;
		}
		{
			center_coord = float3( floor( ShadowTexC * DEPTH_RES )  - float2(0.5,0.5) + float2(1,0), 0 );
			int3  int_coord_rb = center_coord + int3(  offset, offset,0 );
			int3  int_coord_lt = center_coord + int3( -offset,-offset,0 );
			int3  int_coord_rt = center_coord + int3(  offset,-offset,0 );
			int3  int_coord_lb = center_coord + int3( -offset, offset,0 );

			uint2  d_rb = SatVSM.Load( int_coord_rb );
			uint2  d_lt = SatVSM.Load( int_coord_lt );
			uint2  d_rt = SatVSM.Load( int_coord_rt ); 
			uint2  d_lb = SatVSM.Load( int_coord_lb ); 
			moments1 = (d_rb - d_rt - d_lb + d_lt);
			moments1 /= ((offset*2)*(offset*2));
			moments1 *= rescale;
		}
		moments0.x = dot( float2(uv_off.x,1-uv_off.x),float2(moments0.x,moments1.x) );
		moments0.y = dot( float2(uv_off.x,1-uv_off.x),float2(moments0.y,moments1.y) );

		{
			center_coord = float3( floor( ShadowTexC * DEPTH_RES )  - float2(0.5,0.5) + float2(0,1), 0 );
			int3  int_coord_rb = center_coord + int3(  offset, offset,0 );
			int3  int_coord_lt = center_coord + int3( -offset,-offset,0 );
			int3  int_coord_rt = center_coord + int3(  offset,-offset,0 );
			int3  int_coord_lb = center_coord + int3( -offset, offset,0 );

			uint2  d_rb = SatVSM.Load( int_coord_rb );
			uint2  d_lt = SatVSM.Load( int_coord_lt );
			uint2  d_rt = SatVSM.Load( int_coord_rt ); 
			uint2  d_lb = SatVSM.Load( int_coord_lb ); 
			moments2 = (d_rb - d_rt - d_lb + d_lt);
			moments2 /= ((offset*2)*(offset*2));
			moments2 *= rescale;
		}
		{
			center_coord = float3( floor( ShadowTexC * DEPTH_RES )  - float2(0.5,0.5) + float2(1,1), 0 );
			int3  int_coord_rb = center_coord + int3(  offset, offset,0 );
			int3  int_coord_lt = center_coord + int3( -offset,-offset,0 );
			int3  int_coord_rt = center_coord + int3(  offset,-offset,0 );
			int3  int_coord_lb = center_coord + int3( -offset, offset,0 );

			uint2  d_rb = SatVSM.Load( int_coord_rb );
			uint2  d_lt = SatVSM.Load( int_coord_lt );
			uint2  d_rt = SatVSM.Load( int_coord_rt ); 
			uint2  d_lb = SatVSM.Load( int_coord_lb ); 
			moments3 = (d_rb - d_rt - d_lb + d_lt);
			moments3 /= ((offset*2)*(offset*2));
			moments3 *= rescale;
		}
		moments1.x = dot( float2(uv_off.x,1-uv_off.x),float2(moments2.x,moments3.x) );
		moments1.y = dot( float2(uv_off.x,1-uv_off.x),float2(moments2.y,moments3.y) );
		moments.x = dot( float2(uv_off.y,1-uv_off.y), float2(moments0.x,moments1.x) );
		moments.y = dot( float2(uv_off.y,1-uv_off.y), float2(moments0.y,moments1.y) );


		float  Ex = moments.x;
		float  VARx = moments.y - Ex * Ex;
				
		{
			float fPartLit = 0;
			
			fPartLit = 0.94 * VARx / ( VARx + ( pixel_unit_z - Ex ) * ( pixel_unit_z - Ex ) );
							
			sum_depth =  max( 0,( moments.x - fPartLit * pixel_unit_z )/( 1 - fPartLit ));
		}
		
		//The bias is necessary due to the numerical precision. Sometimes when the occluder is very close to the receiver
		//although the occluder is slightly nearer to the light, the precision loss makes it equally distant to the light, or worse
		//makes it farther
		//A second thought, you may want to check the Cheveshev Inequality Proof for the root of this bias
		[branch]if( sum_depth >= pixel_unit_z + 0.09 )
			return float4(1,1,1,1);
			
		
	}	
	
	float ZminPers = sum_depth;
	Zmin = -( Zf * Zn ) / ( ( Zf - Zn ) * ( ZminPers - Zf / ( Zf - Zn ) ) );

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
	
//---------------------------
	
	float2 uv_off = frac( ShadowTexC * DEPTH_RES - float2(0.5,0.5) );
	center_coord = float3( floor( ShadowTexC * DEPTH_RES ) - float2(0.5,0.5), 0 );

	float2 moments = {0.0,0.0};
	float2 moments0, moments1, moments2, moments3;
	float  rescale = 1/g_NormalizedFloatToSATUINT;
	int   offset = max(4,( BRight - BLeft ) * DEPTH_RES / 2);
	{
		int3  int_coord_rb = center_coord + int3(  offset, offset,0 );
		int3  int_coord_lt = center_coord + int3( -offset,-offset,0 );
		int3  int_coord_rt = center_coord + int3(  offset,-offset,0 );
		int3  int_coord_lb = center_coord + int3( -offset, offset,0 );

		uint2  d_rb = SatVSM.Load( int_coord_rb );
		uint2  d_lt = SatVSM.Load( int_coord_lt );
		uint2  d_rt = SatVSM.Load( int_coord_rt ); 
		uint2  d_lb = SatVSM.Load( int_coord_lb ); 
		moments0 = (d_rb - d_rt - d_lb + d_lt);
		moments0 /= ((offset*2)*(offset*2));
		moments0 *= rescale;
	}
	{
		center_coord = float3( floor( ShadowTexC * DEPTH_RES )  - float2(0.5,0.5) + float2(1,0), 0 );
		int3  int_coord_rb = center_coord + int3(  offset, offset,0 );
		int3  int_coord_lt = center_coord + int3( -offset,-offset,0 );
		int3  int_coord_rt = center_coord + int3(  offset,-offset,0 );
		int3  int_coord_lb = center_coord + int3( -offset, offset,0 );

		uint2  d_rb = SatVSM.Load( int_coord_rb );
		uint2  d_lt = SatVSM.Load( int_coord_lt );
		uint2  d_rt = SatVSM.Load( int_coord_rt ); 
		uint2  d_lb = SatVSM.Load( int_coord_lb ); 
		moments1 = (d_rb - d_rt - d_lb + d_lt);
		moments1 /= ((offset*2)*(offset*2));
		moments1 *= rescale;
	}
	moments0.x = dot( float2(uv_off.x,1-uv_off.x),float2(moments0.x,moments1.x) );
	moments0.y = dot( float2(uv_off.x,1-uv_off.x),float2(moments0.y,moments1.y) );

	{
		center_coord = float3( floor( ShadowTexC * DEPTH_RES )  - float2(0.5,0.5) + float2(0,1), 0 );
		int3  int_coord_rb = center_coord + int3(  offset, offset,0 );
		int3  int_coord_lt = center_coord + int3( -offset,-offset,0 );
		int3  int_coord_rt = center_coord + int3(  offset,-offset,0 );
		int3  int_coord_lb = center_coord + int3( -offset, offset,0 );

		uint2  d_rb = SatVSM.Load( int_coord_rb );
		uint2  d_lt = SatVSM.Load( int_coord_lt );
		uint2  d_rt = SatVSM.Load( int_coord_rt ); 
		uint2  d_lb = SatVSM.Load( int_coord_lb ); 
		moments2 = (d_rb - d_rt - d_lb + d_lt);
		moments2 /= ((offset*2)*(offset*2));
		moments2 *= rescale;
	}
	{
		center_coord = float3( floor( ShadowTexC * DEPTH_RES )  - float2(0.5,0.5) + float2(1,1), 0 );
		int3  int_coord_rb = center_coord + int3(  offset, offset,0 );
		int3  int_coord_lt = center_coord + int3( -offset,-offset,0 );
		int3  int_coord_rt = center_coord + int3(  offset,-offset,0 );
		int3  int_coord_lb = center_coord + int3( -offset, offset,0 );

		uint2  d_rb = SatVSM.Load( int_coord_rb );
		uint2  d_lt = SatVSM.Load( int_coord_lt );
		uint2  d_rt = SatVSM.Load( int_coord_rt ); 
		uint2  d_lb = SatVSM.Load( int_coord_lb ); 
		moments3 = (d_rb - d_rt - d_lb + d_lt);
		moments3 /= ((offset*2)*(offset*2));
		moments3 *= rescale;
	}
	moments1.x = dot( float2(uv_off.x,1-uv_off.x),float2(moments2.x,moments3.x) );
	moments1.y = dot( float2(uv_off.x,1-uv_off.x),float2(moments2.y,moments3.y) );
	moments.x = dot( float2(uv_off.y,1-uv_off.y), float2(moments0.x,moments1.x) );
	moments.y = dot( float2(uv_off.y,1-uv_off.y), float2(moments0.y,moments1.y) );


	float  mu = moments.x;
	float  delta_sqr = moments.y - mu * mu;
	
	float fPartLit = 0;
	if( pixel_unit_z < mu + DepthBiasDefault && pixel_unit_z * pixel_unit_z < moments.y + DepthBiasDefault*0.1 )
		fPartLit = 1.0;
	else
		fPartLit = delta_sqr / ( delta_sqr + ( pixel_unit_z - mu ) * ( pixel_unit_z - mu ) );
	return float4( fPartLit,fPartLit,fPartLit,1);
	
}

float4 AccurateShadowIntSATMultiSMP4(float4 vPos, float4 vDiffColor, bool limit_kernel = false, bool use_bias = true)
{
	float4 vLightPos = TexPosInWorld.Load(int3(vPos.x-0.5,vPos.y-0.5,0));	
	vLightPos = mul( float4(vLightPos.xyz,1), mLightView );
	
	float4 vPosLight = mul( float4(vLightPos.xyz,1), mLightProj );
	float2 ShadowTexC = ( vPosLight.xy/vPosLight.w ) * 0.5 + float2( 0.5, 0.5 ) ;
	ShadowTexC.y = 1.0 - ShadowTexC.y;
	
	float tmp = TexDepthMap.SampleLevel( PointSampler, ShadowTexC,0 );
	
	if( ShadowTexC.x > 1.0 || ShadowTexC.x < 0.0  || ShadowTexC.y > 1.0 || ShadowTexC.y < 0.0 )
		return float4( 1,1,1,1 );
	
	//---------------------------------------------------------------------------------
	float  Zn = fLightZn;
	float  Zf = fLightZn + LIGHT_ZF_DELTA;
	float  w = vPosLight.w,
		   x = vPosLight.x,
		   y = vPosLight.y;
	float pixel_unit_z = vPosLight.z/vPosLight.w;

//calculate the filter kernel -------------------------------------------------------------------------------------
	float  LightSize = fFilterSize;
	float  scale = ( w - Zn )/w;
	float  LightWidthPers  = LightSize  * scale,
		   LightHeightPers = LightSize * scale;
	float4x4 g_mLightProj = mLightProj;
	float	 NpWidth  = Zn/g_mLightProj[0][0],
		     NpHeight = Zn/g_mLightProj[1][1];
		     
	float  LightWidthPersNorm  = LightWidthPers /NpWidth,
		   LightHeightPersNorm = LightHeightPers/NpHeight;

	//top is smaller than bottom		   
	float  BLeft   = max( x/w-LightWidthPersNorm,-1) * 0.5 + 0.5,
		   BRight  = min( x/w+LightWidthPersNorm,1) * 0.5 + 0.5,
		   BTop    = 1 -( min( y/w+LightHeightPersNorm,1) * 0.5 + 0.5 ),
		   BBottom = 1 -( max( y/w-LightHeightPersNorm,-1) * 0.5 + 0.5 ); 
		   
	float	T_LightWidth, 
			T_LightHeight,
			S_LightWidth ,
			S_LightHeight,
			S_LightWidthNorm = LightWidthPersNorm, 
			S_LightHeightNorm = LightHeightPersNorm;
	
	float Zmin,Zmax;
	float sum_depth = 0;
	{
		float fPartLit = 0;
		float  rescale = 1/g_NormalizedFloatToSATUINT;
		float2 moments = {0.0,0.0};
		float2 moments0, moments1, moments2, moments3;
		
		int    light_per_row = 1;
		float  sub_light_size_01 = ( BRight - BLeft ) / light_per_row;
		
		float2 curr_lt = float2( BLeft, BTop );
		for( int i = 0; i<light_per_row; ++i )
		{
			for( int j = 0; j<light_per_row; ++j )
			{

				uint2  d_lt = SatVSM.Load( int3(round(curr_lt*DEPTH_RES), 0) );			
				uint2  d_rt = SatVSM.Load( int3(round((curr_lt + float2(sub_light_size_01,0))*DEPTH_RES), 0 ));
				uint2  d_lb = SatVSM.Load( int3(round((curr_lt + float2(0,sub_light_size_01))*DEPTH_RES), 0 ));
				uint2  d_rb = SatVSM.Load( int3(round((curr_lt + float2(sub_light_size_01,sub_light_size_01))*DEPTH_RES), 0 ));
				int2 crd_lt = int2(round(curr_lt*DEPTH_RES));
				int2 crd_rb = int2(round((curr_lt + float2(sub_light_size_01,sub_light_size_01))*DEPTH_RES));

				moments0 = (d_rb - d_rt - d_lb + d_lt);
				moments0 /= (crd_rb.x - crd_lt.x)*(crd_rb.y - crd_lt.y);
				moments0 *= rescale;
				float  Ex = moments0.x;
				float  VARx = moments0.y - Ex * Ex;
				{
					float fPartLit = 0;
					//Why this bias?
					fPartLit = VARx / ( VARx + ( pixel_unit_z - Ex ) * ( pixel_unit_z - Ex ) );
									
					sum_depth +=  max( 0,( moments0.x - fPartLit * pixel_unit_z )/( 1 - fPartLit ));
				}
				curr_lt += float2(sub_light_size_01,0);
			}
			curr_lt.x = BLeft;
			curr_lt += float2(0,sub_light_size_01);
		}
		sum_depth /= (light_per_row * light_per_row);

		//---------------------------
		
		//The bias is necessary due to the numerical precision. Sometimes when the occluder is very close to the receiver
		//although the occluder is slightly nearer to the light, the precision loss makes it equally distant to the light, or worse
		//makes it farther
		//A second thought, you may want to check the Cheveshev Inequality Proof for the root of this bias
		[branch]if( sum_depth >= pixel_unit_z - 0.05 )
			return float4(1,1,1,1);
			
		
	}
	
	float ZminPers = sum_depth;
	Zmin = -( Zf * Zn ) / ( ( Zf - Zn ) * ( ZminPers - Zf / ( Zf - Zn ) ) );

	T_LightWidth  = ( w - Zmin ) * ( LightSize  ) / w,
	T_LightHeight = ( w - Zmin ) * ( LightSize ) / w,

	S_LightWidth  = Zn * T_LightWidth  / Zmin,
	S_LightHeight = Zn * T_LightHeight / Zmin,
	S_LightWidthNorm  = S_LightWidth  / NpWidth,
	S_LightHeightNorm = S_LightHeight / NpHeight;
		
	BLeft   = saturate(max( x/w-S_LightWidthNorm,-1) * 0.5 + 0.5);
	BRight  = saturate(min( x/w+S_LightWidthNorm,1) * 0.5 + 0.5);
	BTop = saturate(1 -( min( y/w+S_LightHeightNorm,1) * 0.5 + 0.5 ));
	BBottom  = saturate(1 -( max( y/w-S_LightHeightNorm,-1) * 0.5 + 0.5 )); 
	

//---------------------------
	float fPartLit = 0;
	float  rescale = 1/g_NormalizedFloatToSATUINT;
	float2 moments = {0.0,0.0};
	float2 moments0, moments1, moments2, moments3;

	int   light_per_row = 1;
	float   sub_light_size_01 = ( BRight - BLeft ) / light_per_row;
		
	float2 curr_lt = float2( BLeft, BTop );
	for( int i = 0; i<light_per_row; ++i )
	{
		for( int j = 0; j<light_per_row; ++j )
		{
						
			uint2  d_lt = SatVSM.Load( int3(round(curr_lt*DEPTH_RES), 0) );			
			uint2  d_rt = SatVSM.Load( int3(round((curr_lt + float2(sub_light_size_01,0))*DEPTH_RES), 0 ));
			uint2  d_lb = SatVSM.Load( int3(round((curr_lt + float2(0,sub_light_size_01))*DEPTH_RES), 0 ));
			uint2  d_rb = SatVSM.Load( int3(round((curr_lt + float2(sub_light_size_01,sub_light_size_01))*DEPTH_RES), 0 ));
			       	
			int2 crd_lt = int2(round(curr_lt*DEPTH_RES));
			int2 crd_rb = int2(round((curr_lt + float2(sub_light_size_01,sub_light_size_01))*DEPTH_RES));
			moments0 = (d_rb - d_rt - d_lb + d_lt);
			moments0 /= (crd_rb.x - crd_lt.x)*(crd_rb.y - crd_lt.y);
			moments0 *= rescale;
			float  mu = moments0.x;
			float  delta_sqr = moments0.y - mu * mu;
			if( pixel_unit_z < mu + DepthBiasDefault/* && pixel_unit_z * pixel_unit_z < moments0.y + DepthBiasDefault*DepthBiasDefault*/ )
			{
				fPartLit += 1.0;
			}
			else
				fPartLit += delta_sqr / ( delta_sqr + ( pixel_unit_z - mu ) * ( pixel_unit_z - mu ) );
			curr_lt.x += sub_light_size_01;
		}
		curr_lt.x = BLeft;
		curr_lt.y += sub_light_size_01;
	}
	fPartLit /= (light_per_row * light_per_row) ;

//---------------------------

	
	return float4( fPartLit,fPartLit,fPartLit,1);
	
}


float4 SSMBackprojectionPS(QuadVS_Output Input) : SV_Target0
{
	float4 vLightPos = TexPosInWorld.Load(int3(Input.Pos.x-0.5,Input.Pos.y-0.5,0));	
	vLightPos = mul( float4(vLightPos.xyz,1), mLightView );


    float3 lightDirInputLightView = normalize(float3( 0,0,0 ) - vLightPos.xyz);

	float4 diff = float4(1,1,1,1);
	[flatten] if (bTextured) diff = TexColor.Load(int3(Input.Pos.x-0.5,Input.Pos.y-0.5,0));	
    diff.a = 1;

	float3 surfNorm = TexNormalInWorld.Load(int3(Input.Pos.x-0.5,Input.Pos.y-0.5,0));//Input.vNorm;
    surfNorm = mul(surfNorm,(float3x3)mLightView);
	surfNorm = normalize( surfNorm );
	
	REVERT_NORM;
	float  diff_coe = saturate(dot(surfNorm,lightDirInputLightView));
	
	float4 ret_color;
	[flatten]if( 0 == diff_coe )
		ret_color = float4(1,0,0,1);
	else
#ifdef USE_INT_SAT
		ret_color = AccurateShadowIntSATMultiSMP4(Input.Pos,float4(1,1,1,1),true);
#else
#ifdef DISTRIBUTE_PRECISION
		ret_color = AccurateShadowDoubleSAT(Input.Pos,float4(1,1,1,1),true);
#else
		ret_color = AccurateShadowFloatSAT(Input.Pos,float4(1,1,1,1),true);
#endif
#endif
			
	float4 curr_result = phong_shading(vLightPos.xyz,VCameraInLight.xyz,surfNorm,SkinSpecCoe,diff,ret_color,spec_clr_ogre);
	float4 pre_result = TexPreviousResult.Load( int3( Input.Pos.x - 0.5, Input.Pos.y - 0.5, 0 ) );
	return pre_result + curr_result  * fLumiFactor;
}



technique10 SSMBackprojection
{
    pass P0
    {
        SetVertexShader(CompileShader(vs_4_0, QuadVS()));
        SetGeometryShader(NULL);
        SetPixelShader(CompileShader(ps_4_0, SSMBackprojectionPS()));
		SetRasterizerState(RStateMSAAON);
    }
}

