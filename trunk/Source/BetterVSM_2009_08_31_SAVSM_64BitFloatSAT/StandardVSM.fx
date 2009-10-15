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
    float f3rdDepthDelta;
    float f1stDepthDelta;
    float fMainBias;

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
	ret_color.w = 1.0f;
   return ret_color;

}

float est_occ_depth_and_chebshev_ineq( float bias,int light_per_row, float BLeft, float BRight,float BTop, float pixel_linear_z, out float fPartLit, out float occ_depth, out float unocc_part, out float unsure_part )
{
	float lit_bias = 0.00;
	float occ_depth_limit = 0.02;
#ifdef EVSM
	float  expCZ = exp(pixel_linear_z*EXPC);
#endif
	float4 moments = {0.0,0.0,0.0,0.0};
	float  sub_light_size_01 = ( BRight - BLeft ) / light_per_row;
	float  rescale = 1/g_NormalizedFloatToSATUINT;
	
	float2 curr_lt = float2( BLeft, BTop );
	float sum_x = 0, sum_sqr_x = 0;
	unocc_part = 0.0;
	unsure_part = 0.0;
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

			if( moments.y > 1 )
				unsure_part += 1.0;

#ifdef EVSM
			if( moments.x > expCZ + bias )
#else
			if( moments.x > pixel_linear_z )
#endif
				unocc_part += 1.0;
			else if( moments.y <= 1 )
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
	
	float Ex = sum_x / ((light_per_row * light_per_row)-unocc_part-unsure_part);
	if( Ex + lit_bias > pixel_linear_z )//according to VSM formula, Ex larger than pixel depth means lit
		fPartLit = 1.0f;
	else
	{
		float E_sqr_x = sum_sqr_x / ((light_per_row * light_per_row)-unocc_part-unsure_part);

		float VARx = E_sqr_x - Ex * Ex;
	#ifdef EVSM
		float est_depth = expCZ - Ex;
	#else
		float est_depth = pixel_linear_z - Ex;
	#endif
		fPartLit = VARx / (VARx + est_depth * est_depth );
	#ifdef EVSM
		occ_depth = max( 1,( Ex - fPartLit * expCZ )/( 1 - fPartLit ));
		occ_depth = log(occ_depth);
		occ_depth /= EXPC;
	#else
		occ_depth = max( occ_depth_limit,( Ex - fPartLit * pixel_linear_z )/( 1 - fPartLit ));
	#endif
		occ_depth = occ_depth*(fLightZf-fLightZn) + fLightZn;
		fPartLit = (1 - unocc_part/(light_per_row * light_per_row-unsure_part)) * fPartLit + unocc_part/(light_per_row * light_per_row-unsure_part);
	}
	return Ex;
}

float4	compute_moments( float sub_light_size_01, float2 curr_lt, int2 offset )
{
	float  rescale = 1/g_NormalizedFloatToSATUINT;

	uint4  d_lt = SatVSM.Load( int3(floor(curr_lt*DEPTH_RES), 0),offset );
	uint4  d_lb = SatVSM.Load( int3(floor((curr_lt + float2(0,sub_light_size_01))*DEPTH_RES), 0 ),offset );

	int2 crd_lt = int2(floor(curr_lt*DEPTH_RES)); 
	int2 crd_rb = int2(floor((curr_lt + float2(sub_light_size_01,sub_light_size_01))*DEPTH_RES));

	uint4  d_rt = SatVSM.Load( int3( crd_rb.x, crd_lt.y, 0 ),offset);
	uint4  d_rb = SatVSM.Load( int3( crd_rb, 0 ),offset);
	float4 moments = (d_rb - d_rt - d_lb + d_lt) * rescale / ( (crd_rb.x - crd_lt.x)*(crd_rb.y - crd_lt.y) );
	return moments;
}

float est_occ_depth_and_chebshev_ineq_blur( float bias,int light_per_row, float BLeft, float BRight,float BTop, float pixel_linear_z, out float fPartLit, out float occ_depth, out float unocc_part, out float unsure_part )
{
	float lit_bias = 0.00;
	float occ_depth_limit = 0.02;
#ifdef EVSM
	float  expCZ = exp(pixel_linear_z*EXPC);
#endif
	float4 moments = {0.0,0.0,0.0,0.0};
	float  sub_light_size_01 = 20.0f/DEPTH_RES;//( BRight - BLeft )  / light_per_row;
	float  rescale = 1/g_NormalizedFloatToSATUINT;
	
	float2 curr_lt = float2( BLeft, BTop );
	float sum_x = 0, sum_sqr_x = 0;
	unocc_part = 0.0;
	unsure_part = 0.0;
	for( int i = 0; i<light_per_row; ++i )
	{
		for( uint j = 0; j<light_per_row; ++j )
		{
			float2 uv_off = frac( curr_lt * DEPTH_RES );
			float4 moments0 = compute_moments( sub_light_size_01, curr_lt, int2(0,0) );
			float4 moments1 = compute_moments( sub_light_size_01, curr_lt, int2(1,0) );
			float4 moments2 = compute_moments( sub_light_size_01, curr_lt, int2(0,1) );
			float4 moments3 = compute_moments( sub_light_size_01, curr_lt, int2(1,1) );
			moments0 = moments0 * ( 1-uv_off.x ) + uv_off.x * moments1;
			moments2 = moments2 * ( 1-uv_off.x ) + uv_off.x * moments3;
			moments  = moments0 * ( 1-uv_off.y ) + uv_off.y * moments2;

			if( moments.y > 1 )
				unsure_part += 1.0;

#ifdef EVSM
			if( moments.x > expCZ + bias )
#else
			if( moments.x > pixel_linear_z )
#endif
				unocc_part += 1.0;
			else if( moments.y <= 1 )
			{
				sum_x += moments.x;
				sum_sqr_x += moments.y;
			}
			
			curr_lt.x += sub_light_size_01;
			//d_lt = d_rt;
			//d_lb = d_rb;
		}
		curr_lt.x = BLeft;
		curr_lt.y += sub_light_size_01;
	}
	
	float Ex = sum_x / ((light_per_row * light_per_row)-unocc_part-unsure_part);
	if( Ex + lit_bias > pixel_linear_z )//according to VSM formula, Ex larger than pixel depth means lit
		fPartLit = 1.0f;
	else
	{
		float E_sqr_x = sum_sqr_x / ((light_per_row * light_per_row)-unocc_part-unsure_part);

		float VARx = E_sqr_x - Ex * Ex;
	#ifdef EVSM
		float est_depth = expCZ - Ex;
	#else
		float est_depth = pixel_linear_z - Ex;
	#endif
		fPartLit = VARx / (VARx + est_depth * est_depth );
	#ifdef EVSM
		occ_depth = max( 1,( Ex - fPartLit * expCZ )/( 1 - fPartLit ));
		occ_depth = log(occ_depth);
		occ_depth /= EXPC;
	#else
		occ_depth = max( occ_depth_limit,( Ex - fPartLit * pixel_linear_z )/( 1 - fPartLit ));
	#endif
		occ_depth = occ_depth*(fLightZf-fLightZn) + fLightZn;
		fPartLit = (1 - unocc_part/(light_per_row * light_per_row-unsure_part)) * fPartLit + unocc_part/(light_per_row * light_per_row-unsure_part);
	}
	return Ex;
}


//closely related to this context, could not be used alone
uint4 SampleSatVSMBilinear( float2 texC )
{
	float2 uv_off = frac( texC * DEPTH_RES );
	//uv_off *= float2( 0.5,0.5 );
	int3   texel_idx = { floor( texC * DEPTH_RES),0 };
	uint4  depth0 = SatVSM.Load( texel_idx );
	uint4  depth1 = SatVSM.Load( texel_idx + int3( 1,0,0 ) );
	uint4  depth2 = SatVSM.Load( texel_idx + int3( 0,1,0 ) );
	uint4  depth3 = SatVSM.Load( texel_idx + int3( 1,1,0 ) );
	
	uint4  depth_avg = ( depth0 * ( 1 - uv_off.x ) * ( 1 - uv_off.y )  +  depth1 * uv_off.x * ( 1 - uv_off.y ) 
						+ depth2 * ( 1 - uv_off.x ) * uv_off.y  +  depth3 * uv_off.x * uv_off.y );
	
	return depth_avg;	
} 

float est_occ_depth_and_chebshev_ineq_bilinear( float bias,int light_per_row, float BLeft, float BRight,float BTop, float pixel_linear_z, out float fPartLit, out float occ_depth, out float unocc_part, out float unsure_part )
{
	float lit_bias = 0.00;
#ifdef EVSM
	float  expCZ = exp(pixel_linear_z*EXPC);
#endif
	float4 moments = {0.0,0.0,0.0,0.0};
	float  sub_light_size_01 = 10.0f/DEPTH_RES;//( BRight - BLeft ) / light_per_row;
	float  rescale = 1/g_NormalizedFloatToSATUINT;
	
	float2 curr_lt = float2( BLeft, BTop );
	
	float sum_x = 0, sum_sqr_x = 0;
	unocc_part = 0.0;
	unsure_part = 0.0;
	for( int i = 0; i<light_per_row; ++i )
	{
		for( uint j = 0; j<light_per_row; ++j )
		{
			float2 crd_lt  = float2( curr_lt*DEPTH_RES - float2(0.5,0.5) ); 
			float2 crd_rb  = float2( (curr_lt + float2(sub_light_size_01,sub_light_size_01))*DEPTH_RES - float2(0.5,0.5) );
			
			uint4  d_lt = SampleSatVSMBilinear( curr_lt );
			uint4  d_lb = SampleSatVSMBilinear( curr_lt + float2(0,sub_light_size_01) );

			uint4  d_rt = SampleSatVSMBilinear( curr_lt + float2(sub_light_size_01,0) );
			uint4  d_rb = SampleSatVSMBilinear( curr_lt + float2(sub_light_size_01,sub_light_size_01) );
			
			moments = (d_rb - d_rt - d_lb + d_lt) * rescale / ( max((crd_rb.x - crd_lt.x)*(crd_rb.y - crd_lt.y),1) );
			
#ifdef EVSM
			if( moments.y > 10 )
#else			
			if( moments.y > 1 )
#endif
				unsure_part += 1.0;
			
#ifdef EVSM
			if( moments.x > expCZ + bias )
#else
			if( moments.x > pixel_linear_z  )
#endif
				unocc_part += 1.0;
#ifdef EVSM
			else if( moments.y <= 10 )
#else
			else if( moments.y <= 1 )
#endif
			{
				sum_x += moments.x;
				sum_sqr_x += moments.y;
			}
				
			curr_lt.x += sub_light_size_01;
			//d_lt = d_rt;
			//d_lb = d_rb;
		}
		curr_lt.x = BLeft;
		curr_lt.y += sub_light_size_01;
	}
	
	float Ex = sum_x / ((light_per_row * light_per_row)-unocc_part-unsure_part);
	
	if( Ex + lit_bias > pixel_linear_z )//according to VSM formula, Ex larger than pixel depth means lit
		fPartLit = 1.0f;
	else
	{
		float E_sqr_x = sum_sqr_x / ((light_per_row * light_per_row)-unocc_part-unsure_part);

		float VARx = E_sqr_x - Ex * Ex;
	#ifdef EVSM
		float est_depth = expCZ - Ex;
	#else
		float est_depth = pixel_linear_z - Ex;
	#endif
		fPartLit = VARx / (VARx + est_depth * est_depth );
	#ifdef EVSM
		occ_depth = max( 1,( Ex - fPartLit * expCZ )/( 1 - fPartLit ));
		occ_depth = log(occ_depth);
		occ_depth /= EXPC;
	#else
		occ_depth = max( 0,( Ex - fPartLit * pixel_linear_z )/( 1 - fPartLit ));
	#endif
		occ_depth = occ_depth*(fLightZf-fLightZn) + fLightZn;
		fPartLit = (1 - unocc_part/(light_per_row * light_per_row-unsure_part)) * fPartLit + unocc_part/(light_per_row * light_per_row-unsure_part);
	}
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
	[branch]if( pixel_linear_z > 1.0 ) return float4(1,1,1,1);	

	//calculate the initial filter kernel 
	float  scale = ( vPosLight.w - fLightZn )/vPosLight.w;
	float  LightWidthPers  = fFilterSize  * scale;
	float  NpWidth  = fLightZn/mLightProj[0][0];
	float  LightWidthPersNorm  = LightWidthPers /NpWidth;
	//top is smaller than bottom		   
	float  BLeft   = max( vPosLight.x/vPosLight.w-LightWidthPersNorm,-1) * 0.5 + 0.5,			BRight  = min( vPosLight.x/vPosLight.w+LightWidthPersNorm,1) * 0.5 + 0.5,
		   BTop    = 1 -( min( vPosLight.y/vPosLight.w+LightWidthPersNorm,1) * 0.5 + 0.5 ),	BBottom = 1 -( max( vPosLight.y/vPosLight.w-LightWidthPersNorm,-1) * 0.5 + 0.5 ); 
	
	//calculate HSM mip level, use HSM to help identify complex depth relationship
	int sub_lev = 4;
	int sub_len = (LightWidthPersNorm * DEPTH_RES + sub_lev - 1) / sub_lev;
	int mipL = ceil(log2(sub_len));
	int mip_res = DEPTH_RES / (1<<mipL);
	int start_x = floor( BLeft * mip_res - float2( 0.5,0.5 ) );
	int end_x = ceil( BRight * mip_res - float2( 0.5,0.5 ) );
	int start_y = floor( BTop * mip_res - float2( 0.5,0.5 ) );
	int end_y = ceil( BBottom * mip_res - float2( 0.5,0.5 ) );

	float max_depth = -100;
	float min_depth =  100;	
	for( int i = start_y; i <= end_y; ++i )
	{
		for( int j = start_x; j <= end_x; ++j )
		{
			float2 depth = DepthMip2.Load(int3(j,i,mipL));
			max_depth = max( depth.y, max_depth );
			min_depth = min( depth.x, min_depth );

		}
	}
	
	[branch]if( pixel_linear_z - 0.06 < min_depth ) // completely lit
		return float4(0,0,1,1);
	[branch]if( pixel_linear_z - 0.03 * (max_depth-min_depth) > max_depth ) // completely dark
		return float4(1,0,0,1);
	
	//this is the variable used to control the level of filter area subdivision	
	int    light_per_row = 1;
	//those stuck in complex depth relationship are subdivided, others dont
	if( pixel_linear_z + 0.059 < max_depth && pixel_linear_z > min_depth + 0.06 )
	{
		light_per_row = 8;
		light_per_row = min( light_per_row, min( BRight - BLeft, BBottom - BTop ) * DEPTH_RES );
		//uncomment the line below to see regions subdivided
		return float4(1,0,1,1);
	}
	
	//used to scale float to integer and vice versa
	float  rescale = 1/g_NormalizedFloatToSATUINT;
	//Zmin is the estimated occluding depth in light space
	float Zmin = 0, fPartLit = 0, unocc_part = 0, unsure_part = 0;
	//the estimation below returns the fPartLit, Zmin and unocc_part
	est_occ_depth_and_chebshev_ineq( 0,light_per_row, BLeft, BRight,BTop, pixel_linear_z, fPartLit, Zmin, unocc_part, unsure_part );
	
	[branch]if( fPartLit <= 0.0 ) return float4(0,0,0,1); // some results in neg fPartLit, due to neg VARx and est_depth^2 larger than VARx, I found all of them are dark
	[branch]if( fPartLit >= 1.0 ) return float4(1,1,1,1); // some results in fPartLit > 1, due to neg VARx but est_depth^2 smaller than VARx, I found all of them are lit 

	//estimated the shrinked filter region
	float	T_LightWidth  = ( vPosLight.w - Zmin ) * ( fFilterSize ) / vPosLight.w;
	float	S_LightWidth  = fLightZn * T_LightWidth  / Zmin;
	LightWidthPersNorm  = S_LightWidth  / NpWidth;
		
	BLeft   = saturate(max( vPosLight.x/vPosLight.w-LightWidthPersNorm,-1) * 0.5 + 0.5);		BRight  = saturate(min( vPosLight.x/vPosLight.w+LightWidthPersNorm, 1) * 0.5 + 0.5);
	BTop = saturate(1 -( min( vPosLight.y/vPosLight.w+LightWidthPersNorm,1) * 0.5 + 0.5 ));	BBottom  = saturate(1 -( max( vPosLight.y/vPosLight.w-LightWidthPersNorm,-1) * 0.5 + 0.5 )); 
	
	if( light_per_row == 8 )	//slightly increase the subdivision level
		light_per_row = 10;
		
	//guarantee that the subdivision is not too fine, subarea smaller than a texel would introduce back ance artifact ( subarea len becomes 0  )		
	light_per_row = min( light_per_row, min( BRight - BLeft, BBottom - BTop ) * DEPTH_RES );
		
	est_occ_depth_and_chebshev_ineq_blur( fMainBias,light_per_row, BLeft, BRight,BTop, pixel_linear_z, fPartLit, Zmin, unocc_part, unsure_part );

	//dont try to remove these 2 branch, otherwise black acne appears
	[branch]if( fPartLit <= 0.0 )
		return float4(0,0,0,1);		
	[branch]if( unocc_part == (light_per_row * light_per_row) )
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

