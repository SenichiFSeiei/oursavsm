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
#define EXPERIMENT
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
Texture2D<float2> SatVSM;
#endif

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
    float DepthBiasDefault = 0.00;
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
	int depth_sample_num = 25;
	float2 Poisson25[] = {
		{-0.978698, -0.0884121},
		{-0.841121, 0.521165},
		{-0.71746, -0.50322},
		{-0.702933, 0.903134},
		{-0.663198, 0.15482},
		{-0.495102, -0.232887},
		{-0.364238, -0.961791},
		{-0.345866, -0.564379},
		{-0.325663, 0.64037},
		{-0.182714, 0.321329},
		{-0.142613, -0.0227363},
		{-0.0564287, -0.36729},
		{-0.0185858, 0.918882},
		{0.0381787, -0.728996},
		{0.16599, 0.093112},
		{0.253639, 0.719535},
		{0.369549, -0.655019},
		{0.423627, 0.429975},
		{0.530747, -0.364971},
		{0.566027, -0.940489},
		{0.639332, 0.0284127},
		{0.652089, 0.669668},
		{0.773797, 0.345012},
		{0.968871, 0.840449},
		{0.991882, -0.657338},
	};
	float2 Poisson5[] = {
		{-0.978698, -0.0884121},
		{-0.0185858, 0.918882},
		{0.0381787, -0.728996},
		{0.16599, 0.093112},
		{0.639332, 0.0284127},
	};
	float2 Poisson64[] = {
		{-0.934812, 0.366741},
		{-0.918943, -0.0941496},
		{-0.873226, 0.62389},
		{-0.8352, 0.937803},
		{-0.822138, -0.281655},
		{-0.812983, 0.10416},
		{-0.786126, -0.767632},
		{-0.739494, -0.535813},
		{-0.681692, 0.284707},
		{-0.61742, -0.234535},
		{-0.601184, 0.562426},
		{-0.607105, 0.847591},
		{-0.581835, -0.00485244},
		{-0.554247, -0.771111},
		{-0.483383, -0.976928},
		{-0.476669, -0.395672},
		{-0.439802, 0.362407},
		{-0.409772, -0.175695},
		{-0.367534, 0.102451},
		{-0.35313, 0.58153},
		{-0.341594, -0.737541},
		{-0.275979, 0.981567},
		{-0.230811, 0.305094},
		{-0.221656, 0.751152},
		{-0.214393, -0.0592364},
		{-0.204932, -0.483566},
		{-0.183569, -0.266274},
		{-0.123936, -0.754448},
		{-0.0859096, 0.118625},
		{-0.0610675, 0.460555},
		{-0.0234687, -0.962523},
		{-0.00485244, -0.373394},
		{0.0213324, 0.760247},
		{0.0359813, -0.0834071},
		{0.0877407, -0.730766},
		{0.14597, 0.281045},
		{0.18186, -0.529649},
		{0.188208, -0.289529},
		{0.212928, 0.063509},
		{0.23661, 0.566027},
		{0.266579, 0.867061},
		{0.320597, -0.883358},
		{0.353557, 0.322733},
		{0.404157, -0.651479},
		{0.410443, -0.413068},
		{0.413556, 0.123325},
		{0.46556, -0.176183},
		{0.49266, 0.55388},
		{0.506333, 0.876888},
		{0.535875, -0.885556},
		{0.615894, 0.0703452},
		{0.637135, -0.637623},
		{0.677236, -0.174291},
		{0.67626, 0.7116},
		{0.686331, -0.389935},
		{0.691031, 0.330729},
		{0.715629, 0.999939},
		{0.8493, -0.0485549},
		{0.863582, -0.85229},
		{0.890622, 0.850581},
		{0.898068, 0.633778},
		{0.92053, -0.355693},
		{0.933348, -0.62981},
		{0.95294, 0.156896},
	};

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





float4 AccurateShadow(float4 vPos, float4 vDiffColor, bool limit_kernel = false, bool use_bias = true)
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
	float3  center_coord = float3( floor( ShadowTexC * DEPTH_RES ) + float2(0.5,0.5), 0 );	   
#ifndef FIX_KERNEL		
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
			
	float sum_depth = 0,
		  num_occlu = 0;

#ifdef GAUSSIAN_SAMPLE
	float2 instant_off = {0.1,0.1};
	for( uint i = 0; i < depth_sample_num; ++i )
	{
		float2 offset = Poisson64[i%64] + instant_off * (i/64);
		int2   cur_sample = center_coord + radius_in_pixel * offset;
		
		float depth = TexDepthMap.Load( int3( cur_sample, 0 ) ); 
		if( depth < pixel_unit_z && depth>0.00001 )
		{
			sum_depth += depth;
			num_occlu += 1.0;
		}

	}
#else
	for( int v = -radius_in_pixel; v < radius_in_pixel; v += 6 )
	{
		for( int u = -radius_in_pixel; u < radius_in_pixel; u += 6 )
		{
			float depth = TexDepthMap.Load( int3(center_coord) + int3( u, v, 0 ) );	
			if( depth < pixel_unit_z && depth>0.00001 )
			{
				sum_depth += depth;
				num_occlu += 1.0;
			}
		}
	}
#endif
	if( num_occlu == 0 ) return float4(1,1,1,1);
	sum_depth /= num_occlu;
	
	
	float ZminPers = sum_depth;
	float Zmin = -( Zf * Zn ) / ( ( Zf - Zn ) * ( ZminPers - Zf / ( Zf - Zn ) ) );

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
#endif	
	
//---------------------------
	
#ifdef USE_INT_SAT
#ifdef BILINEAR_INT_SMP
	float2 uv_off = frac( ShadowTexC * DEPTH_RES - float2(0.5,0.5) );
	center_coord = float3( floor( ShadowTexC * DEPTH_RES ) - float2(0.5,0.5), 0 );

	float2 moments = {0.0,0.0};
	float2 moments0, moments1, moments2, moments3;
	float  rescale = 1/g_NormalizedFloatToSATUINT;
#ifdef FIX_KERNEL
	int   offset = 30;
#else
	int   offset = max(1,( BRight - BLeft ) * DEPTH_RES / 2);
#endif
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

#else
	int   offset = 10;//max(1,( BRight - BLeft ) * DEPTH_RES / 2);
	int3  int_coord_rb = center_coord + int3(  offset, offset,0 );
	int3  int_coord_lt = center_coord + int3( -offset,-offset,0 );
	int3  int_coord_rt = center_coord + int3(  offset,-offset,0 );
	int3  int_coord_lb = center_coord + int3( -offset, offset,0 );

	uint2  d_rb = SatVSM.Load( int_coord_rb );
	uint2  d_lt = SatVSM.Load( int_coord_lt );
	uint2  d_rt = SatVSM.Load( int_coord_rt ); 
	uint2  d_lb = SatVSM.Load( int_coord_lb ); 
	float2 moments = (d_rb - d_rt - d_lb + d_lt);
	moments /= ((offset*2)*(offset*2));
	moments /= g_NormalizedFloatToSATUINT;
#endif
#else
	float2  d_rb = SatVSM.Load( int_coord_rb );
	float2  d_lt = SatVSM.Load( int_coord_lt );
	float2  d_rt = SatVSM.Load( int_coord_rt );
	float2  d_lb = SatVSM.Load( int_coord_lb );
	float2 moments = (d_rb - d_rt - d_lb + d_lt);
	moments /= ((offset*2)*(offset*2));
#endif

	float  mu = moments.x;
	float  delta_sqr = moments.y - mu * mu;
	
	float fPartLit = 0;
	if( pixel_unit_z < mu + DepthBiasDefault && pixel_unit_z * pixel_unit_z < moments.y + DepthBiasDefault*0.1 )
		fPartLit = 1.0;
	else
		fPartLit = delta_sqr / ( delta_sqr + ( pixel_unit_z - mu ) * ( pixel_unit_z - mu ) );
	return float4( fPartLit,fPartLit,fPartLit,1);
	
}

//use screen space points' depths the estimate the depth of points on shadow maps that larger than t
float4 AccurateShadowExperiment(float4 vPos, float4 vDiffColor, bool limit_kernel = false, bool use_bias = true)
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
	float  LightSize = fFilterSize * 0.2;
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

	float sum_depth = 0;
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
		
		float fPartLit = 0;
		
		fPartLit = VARx / ( VARx + ( pixel_unit_z - Ex ) * ( pixel_unit_z - Ex ) );
				
		sum_depth = min( pixel_unit_z, max( 0,( moments.x - fPartLit * pixel_unit_z )/( 1 - fPartLit )) );
		
		//for those outside shadow map
		if( sum_depth == 0 )
			return float4(1,1,1,1);
			
		
	}	
	
	float ZminPers = sum_depth;
	float Zmin = -( Zf * Zn ) / ( ( Zf - Zn ) * ( ZminPers - Zf / ( Zf - Zn ) ) );

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
	int   offset = max(3,( BRight - BLeft ) * DEPTH_RES / 2);
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
#ifdef EXPERIMENT
		ret_color = AccurateShadowExperiment(Input.Pos,float4(1,1,1,1),true);
#else
		ret_color = AccurateShadow(Input.Pos,float4(1,1,1,1),true);
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

