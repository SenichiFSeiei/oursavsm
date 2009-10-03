//----------------------------------------------------------------------------------
// File:   MipVSM.fx
// Author: Baoguang Yang
// 
// Copyright (c) 2009 S3Graphics Corporation. All rights reserved.
// 
// The render algorithm of Mip mapped variance shadow map
//
//----------------------------------------------------------------------------------
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
Texture2D<uint4> SatVSM;
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

float est_occ_depth_and_chebshev_ineq( float bias,int light_per_row, float BLeft, float BRight,float BTop, float pixel_linear_z, out float fPartLit, out float occ_depth, out float unocc_part )
{
	float  expCZ = exp(pixel_linear_z*EXPC);
	float  neg_exp_negCZ = -exp(-(pixel_linear_z)*EXPC);
	float4 moments = {0.0,0.0,0.0,0.0};
	float  rescale = 1/g_NormalizedFloatToSATUINT;
	float  unocc_part2 = 0;
	float sum_x = 0, sum_sqr_x = 0;

	int    iBLeft = round( BLeft * DEPTH_RES );
	int    iBRight = round( BRight * DEPTH_RES );
	int    iBTop = round( BTop * DEPTH_RES );		
	int    iKernelLen = iBRight - iBLeft;
	int    iMipLevel = max( 0, min( log(iKernelLen) + 1,8 ) );

	iBLeft >>= iMipLevel;
	iBRight = ( iBRight + 1<<iMipLevel ) >> iMipLevel;
	iBTop >>= iMipLevel;
	iKernelLen = ( iKernelLen + 1<<iMipLevel ) >> iMipLevel;

	
	for( int j = iBTop; j <= iBTop + iKernelLen; ++j )
	{
		for( int i = iBLeft; i <= iBLeft + iKernelLen; ++i )
		{
			moments = VSMMip2.Load( int3(i,j,iMipLevel) );
			if( moments.x > expCZ + bias )
				++unocc_part;
			else
			{
				sum_x += moments.x;
				sum_sqr_x += moments.y;
			}			
		}
	}
	iKernelLen += 1;
	float Ex = sum_x / ((iKernelLen * iKernelLen)-unocc_part);
	float E_sqr_x = sum_sqr_x / ((iKernelLen * iKernelLen)-unocc_part);
	float VARx = E_sqr_x - Ex * Ex;
	float est_depth = expCZ - Ex;
	fPartLit = VARx / (VARx + est_depth * est_depth );
	occ_depth =  max( 1,( Ex - fPartLit * expCZ )/( 1 - fPartLit ));
	occ_depth = log(occ_depth);
	occ_depth /= EXPC;
	occ_depth = occ_depth*(fLightZf-fLightZn) + fLightZn;
	return Ex;
}

float4 AccurateShadow(float4 vPos, float4 vDiffColor, bool limit_kernel = false, bool use_bias = true)
{
	float4 vPosLight = TexPosInWorld.Load(int3(vPos.x-0.5,vPos.y-0.5,0));	
	vPosLight = mul( float4(vPosLight.xyz,1), mLightView );
	vPosLight = mul( float4(vPosLight.xyz,1), mLightProj );
	float2 ShadowTexC = ( vPosLight.xy/vPosLight.w ) * 0.5 + float2( 0.5, 0.5 ) ;
	ShadowTexC.y = 1.0 - ShadowTexC.y;
	[branch]if( ShadowTexC.x > 1.0 || ShadowTexC.x < 0.0  || ShadowTexC.y > 1.0 || ShadowTexC.y < 0.0 )
		return float4( 1,1,1,1 );	

	//calculate the filter kernel -------------------------------------------------------------------------------------
	float  scale = ( vPosLight.w - fLightZn )/vPosLight.w;
	float  LightWidthPers  = fFilterSize  * scale,		LightHeightPers = fFilterSize * scale;
	float  NpWidth  = fLightZn/mLightProj[0][0],		NpHeight = fLightZn/mLightProj[1][1];
		     
	float  LightWidthPersNorm  = LightWidthPers /NpWidth,		LightHeightPersNorm = LightHeightPers/NpHeight;
		   //LightWidthPersNorm = 0.004;
		   LightHeightPersNorm = LightWidthPersNorm;

	//top is smaller than bottom		   
	float  BLeft   = max( vPosLight.x/vPosLight.w-LightWidthPersNorm,-1) * 0.5 + 0.5,			BRight  = min( vPosLight.x/vPosLight.w+LightWidthPersNorm,1) * 0.5 + 0.5,
		   BTop    = 1 -( min( vPosLight.y/vPosLight.w+LightHeightPersNorm,1) * 0.5 + 0.5 ),	BBottom = 1 -( max( vPosLight.y/vPosLight.w-LightHeightPersNorm,-1) * 0.5 + 0.5 ); 
		   
	float	S_LightWidthNorm = LightWidthPersNorm,		S_LightHeightNorm = LightHeightPersNorm;
			
	float  rescale = 1/g_NormalizedFloatToSATUINT;
	float Zmin = 0;
	float pixel_unit_z = vPosLight.z/vPosLight.w;
	float pixel_linear_z = (vPosLight.w - fLightZn) / (fLightZf-fLightZn);

	{
		float fPartLit = 0, unocc_part = 0;
		int    light_per_row = 1;
		est_occ_depth_and_chebshev_ineq( 0,light_per_row, BLeft, BRight,BTop, pixel_linear_z, fPartLit, Zmin, unocc_part );
		return float4( fPartLit,fPartLit,fPartLit,1 );
	}

	float	T_LightWidth  = ( vPosLight.w - Zmin ) * ( fFilterSize ) / vPosLight.w;
	float	S_LightWidth  = fLightZn * T_LightWidth  / Zmin;
	S_LightWidthNorm  = S_LightWidth  / NpWidth,
		
	BLeft   = saturate(max( vPosLight.x/vPosLight.w-S_LightWidthNorm,-1) * 0.5 + 0.5);		BRight  = saturate(min( vPosLight.x/vPosLight.w+S_LightWidthNorm, 1) * 0.5 + 0.5);
	BTop = saturate(1 -( min( vPosLight.y/vPosLight.w+S_LightWidthNorm,1) * 0.5 + 0.5 ));	BBottom  = saturate(1 -( max( vPosLight.y/vPosLight.w-S_LightWidthNorm,-1) * 0.5 + 0.5 )); 
	
	float fPartLit = 0, unocc_part = 0;
	int    light_per_row = 1;
	float Ex = est_occ_depth_and_chebshev_ineq( 0,light_per_row, BLeft, BRight,BTop, pixel_linear_z, fPartLit, Zmin, unocc_part );
	fPartLit = (1 - unocc_part/(light_per_row * light_per_row)) * fPartLit + unocc_part/(light_per_row * light_per_row);	;
	
	return float4( fPartLit,fPartLit,fPartLit,1);

	
/*
	float2 moments = VSMMip2.SampleLevel( LinearSampler, ShadowTexC,0 ).xy;
	float  mu = moments.x;
	float  delta_sqr = moments.y - mu * mu;
	
	float fTotShadow = 0;
	
	if( pixel_linear_z <= mu+DepthBiasDefault )
		fTotShadow = 1.0;
	else
		fTotShadow = delta_sqr / ( delta_sqr + ( pixel_linear_z - mu ) * ( pixel_linear_z - mu ) );
	
    return float4(fTotShadow,fTotShadow,fTotShadow,1);
  */  
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
	ret_color = AccurateShadow(Input.Pos,float4(1,1,1,1),true);
			
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

