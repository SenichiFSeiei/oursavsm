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
    float DepthBiasDefault = 0.02;
    float DepthBiasKernel = 0.0;
    float fLightZn;
    float fLightZf;
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

float est_occ_depth_and_chebshev_ineq( int light_per_row, float BLeft, float BRight,float BTop, float pixel_linear_z, out float fPartLit, out float occ_depth, out float unocc_part )
{
	float2 moments = {0.0,0.0};
	float  sub_light_size_01 = ( BRight - BLeft ) / light_per_row;
	float  rescale = 1/g_NormalizedFloatToSATUINT;
	
	float2 curr_lt = float2( BLeft, BTop );
	float sum_x = 0, sum_sqr_x = 0;
	for( int i = 0; i<light_per_row; ++i )
	{
		uint2  d_lt = SatVSM.Load( int3(round(curr_lt*DEPTH_RES), 0) );			
		uint2  d_lb = SatVSM.Load( int3(round((curr_lt + float2(0,sub_light_size_01))*DEPTH_RES), 0 ));
		for( int j = 0; j<light_per_row; ++j )
		{
			int2 crd_lt = int2(round(curr_lt*DEPTH_RES));
			int2 crd_rb = int2(round((curr_lt + float2(sub_light_size_01,sub_light_size_01))*DEPTH_RES));

			uint2  d_rt = SatVSM.Load( int3( crd_rb.x, crd_lt.y, 0 ));
			uint2  d_rb = SatVSM.Load( int3( crd_rb, 0 ));

			moments = (d_rb - d_rt - d_lb + d_lt) * rescale / ( (crd_rb.x - crd_lt.x)*(crd_rb.y - crd_lt.y) );

			if( moments.x > pixel_linear_z + DepthBiasKernel )
				++unocc_part;
			else
			{
				sum_x += moments.x;
				sum_sqr_x += moments.y;
			}
			curr_lt.x += sub_light_size_01;
			d_lt = d_rt;
			d_lb = d_rb;
		}
		curr_lt.x = BLeft;
		curr_lt.y += sub_light_size_01;
	}
	
	float Ex = sum_x / ((light_per_row * light_per_row)-unocc_part);
	float E_sqr_x = sum_sqr_x / ((light_per_row * light_per_row)-unocc_part);
	float VARx = E_sqr_x - Ex * Ex;
	float est_depth = pixel_linear_z - Ex;
	fPartLit = VARx / (VARx + est_depth * est_depth );
	occ_depth =  fLightZn + max( 0,( Ex - fPartLit * pixel_linear_z )/( 1 - fPartLit ))*(fLightZf-fLightZn);
	return Ex;
}

//#define PCF_EST
//external dependency: mLightView, mLightProj, fLightZn, fLightZf, fFilterSize
float4 AccurateShadowIntSATMultiSMP4(float4 vPos, float4 vDiffColor, bool limit_kernel = false, bool use_bias = true)
{
	float4 vPosLight = TexPosInWorld.Load(int3(vPos.x-0.5,vPos.y-0.5,0));	
	vPosLight = mul( float4(vPosLight.xyz,1), mLightView );
	vPosLight = mul( float4(vPosLight.xyz,1), mLightProj );
	float2 ShadowTexC = ( vPosLight.xy/vPosLight.w ) * 0.5 + float2( 0.5, 0.5 ) ;
	ShadowTexC.y = 1.0 - ShadowTexC.y;
	[branch]if( ShadowTexC.x > 1.0 || ShadowTexC.x < 0.0  || ShadowTexC.y > 1.0 || ShadowTexC.y < 0.0 )
		return float4( 1,1,1,1 );	
	float pixel_linear_z = (vPosLight.w - fLightZn) / (fLightZf-fLightZn);

	//calculate the filter kernel -------------------------------------------------------------------------------------
	float  scale = ( vPosLight.w - fLightZn )/vPosLight.w;
	float  LightWidthPers  = fFilterSize  * scale,		LightHeightPers = fFilterSize * scale;
	float  NpWidth  = fLightZn/mLightProj[0][0],		NpHeight = fLightZn/mLightProj[1][1];
		     
	float  LightWidthPersNorm  = LightWidthPers /NpWidth,		LightHeightPersNorm = LightHeightPers/NpHeight;

	//top is smaller than bottom		   
	float  BLeft   = max( vPosLight.x/vPosLight.w-LightWidthPersNorm,-1) * 0.5 + 0.5,			BRight  = min( vPosLight.x/vPosLight.w+LightWidthPersNorm,1) * 0.5 + 0.5,
		   BTop    = 1 -( min( vPosLight.y/vPosLight.w+LightHeightPersNorm,1) * 0.5 + 0.5 ),	BBottom = 1 -( max( vPosLight.y/vPosLight.w-LightHeightPersNorm,-1) * 0.5 + 0.5 ); 
		   
	float	S_LightWidthNorm = LightWidthPersNorm,		S_LightHeightNorm = LightHeightPersNorm;
			
	float  rescale = 1/g_NormalizedFloatToSATUINT;
	float Zmin = 0;
	{
		float fPartLit = 0, unocc_part = 0;
		int    light_per_row = 4;
		est_occ_depth_and_chebshev_ineq( light_per_row, BLeft, BRight,BTop, pixel_linear_z, fPartLit, Zmin, unocc_part );
		[branch]if( unocc_part == (light_per_row * light_per_row) )
			return float4(1,1,1,1);
		[branch]if( Zmin >= pixel_linear_z * (fLightZf-fLightZn) + fLightZn)
			return float4(1,1,1,1);		
	}
	
	float	T_LightWidth  = ( vPosLight.w - Zmin ) * ( fFilterSize ) / vPosLight.w;
	float	S_LightWidth  = fLightZn * T_LightWidth  / Zmin;
	S_LightWidthNorm  = S_LightWidth  / NpWidth,
		
	BLeft   = saturate(max( vPosLight.x/vPosLight.w-S_LightWidthNorm,-1) * 0.5 + 0.5);		BRight  = saturate(min( vPosLight.x/vPosLight.w+S_LightWidthNorm, 1) * 0.5 + 0.5);
	BTop = saturate(1 -( min( vPosLight.y/vPosLight.w+S_LightWidthNorm,1) * 0.5 + 0.5 ));	BBottom  = saturate(1 -( max( vPosLight.y/vPosLight.w-S_LightWidthNorm,-1) * 0.5 + 0.5 )); 
	
	if( BRight - BLeft < 0.0039 )
		return float4( 1,1,1,1 );
			
	float fPartLit = 0, unocc_part = 0;
	int    light_per_row = 4;
	float Ex = est_occ_depth_and_chebshev_ineq( light_per_row, BLeft, BRight,BTop, pixel_linear_z, fPartLit, Zmin, unocc_part );
	[branch]if( unocc_part == (light_per_row * light_per_row) )
		return float4(1,1,1,1);
	[branch]if( Zmin + 0.1 >= pixel_linear_z * (fLightZf-fLightZn) + fLightZn)
		return float4(1,1,1,1);		
	fPartLit = (1 - unocc_part/(light_per_row * light_per_row)) * fPartLit + unocc_part/(light_per_row * light_per_row);	;
	if( Ex > pixel_linear_z )
		return float4(1,1,1,1);	
	
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

/*
#ifdef PCF_EST
	float pixel_unit_z = vPosLight.z/vPosLight.w;
	float fPartLit = 0;
	float2 moments = {0.0,0.0};

	int   light_per_row = 10;
	float   sub_light_size_01 = ( BRight - BLeft ) / light_per_row;
		
	float2 curr_lt = float2( BLeft, BTop );
	float	num_occ = 0;
	for( int i = 0; i<light_per_row; ++i )
	{
		for( int j = 0; j<light_per_row; ++j )
		{
			float  curr_depth = TexDepthMap.Load( int3(round(curr_lt*DEPTH_RES), 0) );			
			if( curr_depth < pixel_unit_z - DepthBiasDefault )
			{
				num_occ += 1.0;
			}
					
			curr_lt.x += sub_light_size_01;
		}
		curr_lt.x = BLeft;
		curr_lt.y += sub_light_size_01;
	}
	fPartLit = num_occ;
	fPartLit /= (light_per_row * light_per_row) ;
	fPartLit = 1 - fPartLit;
	
#else				
		float fPartLit = 0, unocc_part = 0;
		int    light_per_row = 4;
		float Ex = est_occ_depth_and_chebshev_ineq( light_per_row, BLeft, BRight,BTop, pixel_linear_z, fPartLit, Zmin, unocc_part );
		[branch]if( unocc_part == (light_per_row * light_per_row) )
			return float4(1,1,1,1);
		[branch]if( Zmin + 0.1 >= pixel_linear_z * (fLightZf-fLightZn) + fLightZn)
			return float4(1,1,1,1);		
		fPartLit = (1 - unocc_part/(light_per_row * light_per_row)) * fPartLit + unocc_part/(light_per_row * light_per_row);	;
		if( Ex > pixel_linear_z )
			return float4(1,1,1,1);	
#endif
*/