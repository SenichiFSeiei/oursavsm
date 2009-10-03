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
Texture2D<float4> DepthMip2;

Texture2D<uint4> SatVSM;
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
    row_major float4x4 mLightViewProj;
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
	float4 moments = {0.0,0.0,0.0,0.0};
	float  sub_light_size_01 = ( BRight - BLeft ) / light_per_row;
	float  rescale = 1/g_NormalizedFloatToSATUINT;
	
	float2 curr_lt = float2( BLeft, BTop );
	float sum_x = 0, sum_sqr_x = 0;
	unocc_part = 0.0;
	for( int i = 0; i<light_per_row; ++i )
	{
		uint4  d_lt = SatVSM.Load( int3(round(curr_lt*DEPTH_RES), 0) );
		uint4  d_lb = SatVSM.Load( int3(round((curr_lt + float2(0,sub_light_size_01))*DEPTH_RES), 0 ));
		for( uint j = 0; j<light_per_row; ++j )
		{
			int2 crd_lt  = int2(round(curr_lt*DEPTH_RES)); 
			int2 crd_rb = int2(round((curr_lt + float2(sub_light_size_01,sub_light_size_01))*DEPTH_RES));

			uint4  d_rt = SatVSM.Load( int3( crd_rb.x, crd_lt.y, 0 ));
			uint4  d_rb = SatVSM.Load( int3( crd_rb, 0 ));
			moments = (d_rb - d_rt - d_lb + d_lt) * rescale / ( (crd_rb.x - crd_lt.x)*(crd_rb.y - crd_lt.y) );

			if( moments.x > expCZ + bias )
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
	float est_depth = expCZ - Ex;
	fPartLit = VARx / (VARx + est_depth * est_depth );
	occ_depth =  max( 1,( Ex - fPartLit * expCZ )/( 1 - fPartLit ));
	occ_depth = log(occ_depth);
	occ_depth /= EXPC;
	occ_depth = occ_depth*(fLightZf-fLightZn) + fLightZn;
	return Ex;
}

//external dependency: mLightViewProj, mLightProj, fLightZn, fLightZf, fFilterSize
float4 AccurateShadowIntSATMultiSMP4(float4 vPos, float4 vDiffColor, bool limit_kernel = false, bool use_bias = true)
{
	//load pixel's world position, and transform it to light space nonlinear position
	float4 vPosLight = TexPosInWorld.Load(int3(vPos.x-0.5,vPos.y-0.5,0));	
	vPosLight = mul( float4(vPosLight.xyz,1), mLightViewProj );
	
	//calculate the pixel's projection on to shadow map texture space
	float2 ShadowTexC = (( vPosLight.xy/vPosLight.w ) * 0.5 + float2( 0.5, 0.5 )) * float2( 1.0, -1.0 ) + float2(0.0,1.0) ;
	
	//artifacts appears around light frustum faces, hack to remove them
	float loSide = 0.1, hiSide = 0.9;
	[branch]if( ShadowTexC.x > hiSide || ShadowTexC.x < loSide  || ShadowTexC.y > hiSide || ShadowTexC.y < loSide )
		return float4( 1,1,1,1 );
			
	float pixel_linear_z = (vPosLight.w - fLightZn) / (fLightZf-fLightZn);	
	
	//calculate the initial filter kernel 
	float  scale = ( vPosLight.w - fLightZn )/vPosLight.w;
	float  LightWidthPers  = fFilterSize  * scale;
	float  NpWidth  = fLightZn/mLightProj[0][0];
	float  LightWidthPersNorm  = LightWidthPers /NpWidth;
	//top is smaller than bottom		   
	float  BLeft   = max( vPosLight.x/vPosLight.w-LightWidthPersNorm,-1) * 0.5 + 0.5,			BRight  = min( vPosLight.x/vPosLight.w+LightWidthPersNorm,1) * 0.5 + 0.5,
		   BTop    = 1 -( min( vPosLight.y/vPosLight.w+LightWidthPersNorm,1) * 0.5 + 0.5 ),	BBottom = 1 -( max( vPosLight.y/vPosLight.w-LightWidthPersNorm,-1) * 0.5 + 0.5 ); 
	
	//calculate HSM mip level, use HSM to help identify complex depth relationship
	int mipL = round(log(LightWidthPersNorm * DEPTH_RES));
	float2 depth0 = DepthMip2.SampleLevel(LinearSampler,float2(BLeft,BTop),mipL);
	float2 depth1 = DepthMip2.SampleLevel(LinearSampler,float2(BLeft,BBottom),mipL);
	float2 depth2 = DepthMip2.SampleLevel(LinearSampler,float2(BRight,BBottom),mipL);
	float2 depth3 = DepthMip2.SampleLevel(LinearSampler,float2(BRight,BTop),mipL);
	float max_depth = max( max(depth0.y,depth1.y),max(depth2.y,depth3.y) );	
	float min_depth = min( min(depth0.x,depth1.x),min(depth2.x,depth3.x) );
	if( pixel_linear_z < min_depth )
		return float4(1,1,1,1);
		
	//this is the variable used to control the level of filter area subdivision	
	int    light_per_row = 1;
	//those stuck in complex depth relationship are subdivided, others dont
	if( pixel_linear_z + 0.037 < max_depth && pixel_linear_z > min_depth + 0.05 )
	{
		float factor = ( pixel_linear_z - min_depth )/0.037;
		light_per_row = 7;
		//uncomment the line below to see regions subdivided
		//return float4(0,0,1,1);
	}
	
	//used to scale float to integer and vice versa
	float  rescale = 1/g_NormalizedFloatToSATUINT;
	//Zmin is the estimated occluding depth in light space
	float Zmin = 0, fPartLit = 0, unocc_part = 0;
	//the estimation below returns the fPartLit, Zmin and unocc_part
	est_occ_depth_and_chebshev_ineq( 0,light_per_row, BLeft, BRight,BTop, pixel_linear_z, fPartLit, Zmin, unocc_part );
	
	//estimated the shrinked filter region
	float	T_LightWidth  = ( vPosLight.w - Zmin ) * ( fFilterSize ) / vPosLight.w;
	float	S_LightWidth  = fLightZn * T_LightWidth  / Zmin;
	LightWidthPersNorm  = S_LightWidth  / NpWidth,
		
	BLeft   = saturate(max( vPosLight.x/vPosLight.w-LightWidthPersNorm,-1) * 0.5 + 0.5);		BRight  = saturate(min( vPosLight.x/vPosLight.w+LightWidthPersNorm, 1) * 0.5 + 0.5);
	BTop = saturate(1 -( min( vPosLight.y/vPosLight.w+LightWidthPersNorm,1) * 0.5 + 0.5 ));	BBottom  = saturate(1 -( max( vPosLight.y/vPosLight.w-LightWidthPersNorm,-1) * 0.5 + 0.5 )); 
	
	//very small filter region usually means completely lit
	if( BRight - BLeft < 0.01 )
		return float4( 1,1,1,1 );
			
	if( light_per_row == 7 )	//slightly increase the subdivision level
		light_per_row = 9;
		
	est_occ_depth_and_chebshev_ineq( 0.0,light_per_row, BLeft, BRight,BTop, pixel_linear_z, fPartLit, Zmin, unocc_part );
	//dont try to remove these 2 branch, otherwise black acne appears
	[branch]if( unocc_part == (light_per_row * light_per_row) )
		return float4(1,1,1,1);
	[branch]if( Zmin + 0.1 >= pixel_linear_z * (fLightZf-fLightZn) + fLightZn)
		return float4(1,1,1,1);		
	fPartLit = (1 - unocc_part/(light_per_row * light_per_row)) * fPartLit + unocc_part/(light_per_row * light_per_row);	;
	
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
	
	float  diff_coe = saturate(dot(surfNorm,lightDirInputLightView));
	
	float4 ret_color;
	[flatten]if( 0 == diff_coe )
		ret_color = float4(1,0,0,1);
	else
		ret_color = AccurateShadowIntSATMultiSMP4(Input.Pos,float4(1,1,1,1),true);
			
	float4 curr_result = phong_shading(vLightPos.xyz,VCameraInLight.xyz,surfNorm,SkinSpecCoe,diff,ret_color,spec_clr_ogre);
	//float4 pre_result = TexPreviousResult.Load( int3( Input.Pos.x - 0.5, Input.Pos.y - 0.5, 0 ) );
	//return pre_result + curr_result  * fLumiFactor;
	return curr_result;
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
