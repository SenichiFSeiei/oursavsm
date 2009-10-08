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

   return ret_color;

}

float est_occ_depth_and_chebshev_ineq( float bias,int light_per_row, float BLeft, float BRight,float BTop, float pixel_linear_z, out float fPartLit, out float occ_depth, out float unocc_part )
{
#ifdef EVSM
	float  expCZ = exp(pixel_linear_z*EXPC);
#endif
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

#ifdef EVSM
			if( moments.x > expCZ + bias )
#else
			if( moments.x > pixel_linear_z )
#endif
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
	return Ex;
}

//closely related to this context, could not be used alone
void SampleSatVSMBilinear( float2 texC, out uint4  depth0, out uint4  depth1, out uint4  depth2, out uint4  depth3 )
{
	float2 uv_off = frac( texC * DEPTH_RES );
	int3   texel_idx = { floor( texC * DEPTH_RES ),0 };

	depth0 = SatVSM.Load( texel_idx );
	depth1 = SatVSM.Load( texel_idx + int3( 1,0,0 ) );
	depth2 = SatVSM.Load( texel_idx + int3( 0,1,0 ) );
	depth3 = SatVSM.Load( texel_idx + int3( 1,1,0 ) );
}

float4 BilinearFilter( float2 texC, float4 depth0, float4 depth1,float4 depth2, float4 depth3 )
{
	float2 uv_off = frac( texC * DEPTH_RES );
	int3   texel_idx = { floor( texC * DEPTH_RES ),0 };
	float4 depth_avg = depth0 * ( 1 - uv_off.x ) * ( 1 - uv_off.y )  + round( depth1 * uv_off.x * ( 1 - uv_off.y ) )
						+ depth2 * ( 1 - uv_off.x ) * uv_off.y  + round( depth3 * uv_off.x * uv_off.y );
	return depth_avg;
} 

float est_occ_depth_and_chebshev_ineq_bilinear( float bias,int light_per_row, float BLeft, float BRight,float BTop, float pixel_linear_z, out float fPartLit, out float occ_depth, out float unocc_part )
{
#ifdef EVSM
	float  expCZ = exp(pixel_linear_z*EXPC);
#endif
	float4 moments = {0.0,0.0,0.0,0.0};
	float  sub_light_size_01 = ( BRight - BLeft ) / light_per_row;
	float  rescale = 1/g_NormalizedFloatToSATUINT;
	int	   int_sub_light_size = ( sub_light_size_01 * DEPTH_RES );	
	
	float2 curr_lt = float2( BLeft, BTop );
	float sum_x = 0, sum_sqr_x = 0;
	unocc_part = 0.0;
	for( int i = 0; i<light_per_row; ++i )
	{
		uint4  d_lt0, d_lt1, d_lt2, d_lt3;
		SampleSatVSMBilinear( curr_lt, d_lt0,d_lt1,d_lt2,d_lt3 );
		uint4  d_lb0, d_lb1, d_lb2, d_lb3;
		SampleSatVSMBilinear( curr_lt + float2(0,int_sub_light_size/(float)DEPTH_RES), d_lb0,d_lb1,d_lb2,d_lb3 );
		
		for( uint j = 0; j<light_per_row; ++j )
		{
			float2 crd_lt  = curr_lt*DEPTH_RES; 
			float2 crd_rb  = (curr_lt + float2(sub_light_size_01,sub_light_size_01))*DEPTH_RES;

			uint4  d_rt0,d_rt1,d_rt2,d_rt3; 
			SampleSatVSMBilinear( curr_lt + float2(int_sub_light_size/(float)DEPTH_RES,0),d_rt0,d_rt1,d_rt2,d_rt3 );
			uint4  d_rb0,d_rb1,d_rb2,d_rb3;
			SampleSatVSMBilinear( curr_lt + float2(int_sub_light_size/(float)DEPTH_RES,int_sub_light_size/(float)DEPTH_RES),d_rb0,d_rb1,d_rb2,d_rb3 );
			
			float4 moments0 = (d_rb0 - d_rt0 - d_lb0 + d_lt0) * rescale / ( int_sub_light_size );
			float4 moments1 = (d_rb1 - d_rt1 - d_lb1 + d_lt1) * rescale / ( int_sub_light_size );
			float4 moments2 = (d_rb2 - d_rt2 - d_lb2 + d_lt2) * rescale / ( int_sub_light_size );
			float4 moments3 = (d_rb3 - d_rt3 - d_lb3 + d_lt3) * rescale / ( int_sub_light_size );
			
			moments = BilinearFilter( curr_lt, moments0, moments1,moments2, moments3 );
#ifdef EVSM
			if( moments.x > expCZ + bias )
#else
			if( moments.x > pixel_linear_z )
#endif
				++unocc_part;
			else
			{
				sum_x += moments.x;
				sum_sqr_x += moments.y;
			}
			
			curr_lt.x += int_sub_light_size/(float)DEPTH_RES;
			d_lt0 = d_rt0;
			d_lt1 = d_rt1;
			d_lt2 = d_rt2;
			d_lt3 = d_rt3;
			
			d_lb0 = d_rb0;
			d_lb1 = d_rb1;
			d_lb2 = d_rb2;
			d_lb3 = d_rb3;
		}
		curr_lt.x = BLeft;
		curr_lt.y += int_sub_light_size/(float)DEPTH_RES;
	}
	
	float Ex = sum_x / ((light_per_row * light_per_row)-unocc_part);
	float E_sqr_x = sum_sqr_x / ((light_per_row * light_per_row)-unocc_part);
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
	return Ex;
}

#define STEPNUM 1.0f
#define TexelDim (1.0f/DEPTH_RES)
#define NUM_SUBDIV_VSM_Shadow 8
#define NUM_SUBDIV_VSM_Depth 6
#define BIAS_SUBDEPTH 5
#define g_InvNormalizedFloatToSATUINT (1/g_NormalizedFloatToSATUINT)
#define g_VSMMinVariance 1E-6
#define SM_Dimension DEPTH_RES
// Computes Chebyshev's Inequality
// Returns an upper bound given the first two moments and mean
float ChebyshevUpperBound(float2 Moments, float Mean, float MinVariance)
{
    // Standard shadow map comparison
    float p = (Mean <= Moments.x);
    
    // Compute variance
    float Variance = Moments.y - (Moments.x * Moments.x);
    Variance = max(Variance, MinVariance);
    
    // Compute probabilistic upper bound
    float d     = Mean - Moments.x;
    float p_max = Variance / (Variance + d*d);
    
    return max(p, p_max);
}

float EvaluateVSMShadow_SubDiv_Bilinear(float filterWidth, float2 uv, float curDepth)
{
 float searchWidth = filterWidth;
 searchWidth *= SM_Dimension;//current texel number
 float NumOfTexels = max(1.0,floor(STEPNUM*searchWidth));//2 texels
 searchWidth = round(max(1.0f, searchWidth)) * TexelDim; //round -->int -->bilinear consistent
 float2 TileSize = searchWidth;
 float2 CoordsUL = uv - 0.5f*(TileSize);
 // Compute bilinear weights and coordinates
 
 //CoordsUL = (floor(CoordsUL*SM_Dimension - 0.5) + 0.5) * TexelDim;    //alignment
 float fNumVSMDepthSubdiv = min(NumOfTexels, NUM_SUBDIV_VSM_Shadow);
 float fSubStep = searchWidth/fNumVSMDepthSubdiv;
 
 float2 curr_lt_init = (floor(CoordsUL*SM_Dimension - 0.5)+0.5)*TexelDim;
 float2 curr_lt = curr_lt_init;
 float sum_x = 0, sum_sqr_x = 0;
 float unocc_part = 0.0;
 
 for(int j = 0; j < fNumVSMDepthSubdiv; j++)
 {
  float2 crd_lt_f = floor(curr_lt*SM_Dimension);
  int2 crd_lt = crd_lt_f;
  uint2 d_lt_0 = SatVSM.Load( int3(crd_lt+int2(1, 0), 0)).xy;
  uint2 d_lt_1 = SatVSM.Load( int3(crd_lt+int2(0, 1), 0)).xy;
  uint2 d_lt_2 = SatVSM.Load( int3(crd_lt+int2(1, 1), 0)).xy;
  uint2 d_lt_3 = SatVSM.Load( int3(crd_lt+int2(0, 0), 0)).xy;

  float2 crd_lb_f = floor(float2(curr_lt.x,curr_lt.y+fSubStep)*SM_Dimension);     
  int2 crd_lb = crd_lb_f; 
  uint2 d_lb_0 = SatVSM.Load( int3(crd_lb+int2(1, 0), 0)).xy;
  uint2 d_lb_1 = SatVSM.Load( int3(crd_lb+int2(0, 1), 0)).xy;
  uint2 d_lb_2 = SatVSM.Load( int3(crd_lb+int2(1, 1), 0)).xy;
  uint2 d_lb_3 = SatVSM.Load( int3(crd_lb+int2(0, 0), 0)).xy;
  
  for(int i = 0; i < fNumVSMDepthSubdiv; i++)
  {
       // Compute bilinear weights and coordinates
         float4 BilWeights;
         float2 BilCoordsUL = GetBilCoordsAndWeights(crd_lt*TexelDim, SM_Dimension, BilWeights);
            
   crd_lt_f  = floor(curr_lt*SM_Dimension); 
   
   float2 crd_rt_f = floor((curr_lt+float2(fSubStep,0))*SM_Dimension);
   int2 crd_rt = crd_rt_f;
   uint2 d_rt_0 = SatVSM.Load( int3(crd_rt+int2(1, 0), 0)).xy;
   uint2 d_rt_1 = SatVSM.Load( int3(crd_rt+int2(0, 1), 0)).xy;
   uint2 d_rt_2 = SatVSM.Load( int3(crd_rt+int2(1, 1), 0)).xy;
   uint2 d_rt_3 = SatVSM.Load( int3(crd_rt+int2(0, 0), 0)).xy;

   float2 crd_rb_f = floor((curr_lt + float2(fSubStep,fSubStep))*SM_Dimension);
   int2 crd_rb = crd_rb_f;
   uint2 d_rb_0 = SatVSM.Load( int3(crd_rb+int2(1, 0), 0)).xy;
   uint2 d_rb_1 = SatVSM.Load( int3(crd_rb+int2(0, 1), 0)).xy;
   uint2 d_rb_2 = SatVSM.Load( int3(crd_rb+int2(1, 1), 0)).xy;
   uint2 d_rb_3 = SatVSM.Load( int3(crd_rb+int2(0, 0), 0)).xy;


   float fPatchSize = (crd_rb_f.x - crd_lt_f.x)*(crd_rb_f.y - crd_lt_f.y);
   float2 moments0 = (d_rb_0 - d_rt_0 - d_lb_0 + d_lt_0) * g_InvNormalizedFloatToSATUINT / ( fPatchSize );
   float2 moments1 = (d_rb_1 - d_rt_1 - d_lb_1 + d_lt_1) * g_InvNormalizedFloatToSATUINT / ( fPatchSize );
   float2 moments2 = (d_rb_2 - d_rt_2 - d_lb_2 + d_lt_2) * g_InvNormalizedFloatToSATUINT / ( fPatchSize );
   float2 moments3 = (d_rb_3 - d_rt_3 - d_lb_3 + d_lt_3) * g_InvNormalizedFloatToSATUINT / ( fPatchSize );

   //BilWeights = float4(0.1,0.4,0.0,0.5);
   float2 moments;
   moments.x = dot(BilWeights, float4(moments0.x, moments1.x, moments2.x, moments3.x));
   moments.y = dot(BilWeights, float4(moments0.y, moments1.y, moments2.y, moments3.y));

   if( moments.x > curDepth + BIAS_SUBDEPTH*0.001 )
    ++unocc_part;
   else
   {
    sum_x += moments.x;
    sum_sqr_x += moments.y;
   }
   
   curr_lt.x += fSubStep;
   
   d_lt_0 = d_rt_0;d_lt_1 = d_rt_1;d_lt_2 = d_rt_2;d_lt_3 = d_rt_3;
   d_lb_0 = d_rb_0;d_lb_1 = d_rb_1;d_lb_2 = d_rb_2;d_lb_3 = d_rb_3;
  }
  curr_lt.x = curr_lt_init.x;
  curr_lt.y += fSubStep;
  
 }

 [branch]if( unocc_part == (fNumVSMDepthSubdiv * fNumVSMDepthSubdiv) )
  return 1.0f; 
 
 int num_occ_part = ((fNumVSMDepthSubdiv * fNumVSMDepthSubdiv)-unocc_part);
 float2 Moments1;
 Moments1.x = sum_x / num_occ_part;
 Moments1.y = sum_sqr_x / num_occ_part;
 
 float fPartLit = ChebyshevUpperBound(Moments1,curDepth,g_VSMMinVariance);
 
 fPartLit = (num_occ_part/(fNumVSMDepthSubdiv * fNumVSMDepthSubdiv)) * fPartLit + unocc_part/(fNumVSMDepthSubdiv * fNumVSMDepthSubdiv); 

 return fPartLit;  
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
	if( pixel_linear_z > 1.0 ) return float4(1,1,1,1);	
	
	//calculate the initial filter kernel 
	float  scale = ( vPosLight.w - fLightZn )/vPosLight.w;
	float  LightWidthPers  = fFilterSize  * scale;
	float  NpWidth  = fLightZn/mLightProj[0][0];
	float  LightWidthPersNorm  = LightWidthPers /NpWidth;
	//top is smaller than bottom		   
	float  BLeft   = max( vPosLight.x/vPosLight.w-LightWidthPersNorm,-1) * 0.5 + 0.5,			BRight  = min( vPosLight.x/vPosLight.w+LightWidthPersNorm,1) * 0.5 + 0.5,
		   BTop    = 1 -( min( vPosLight.y/vPosLight.w+LightWidthPersNorm,1) * 0.5 + 0.5 ),	BBottom = 1 -( max( vPosLight.y/vPosLight.w-LightWidthPersNorm,-1) * 0.5 + 0.5 ); 
	
	//calculate HSM mip level, use HSM to help identify complex depth relationship
	int mipL = round(log(LightWidthPersNorm * DEPTH_RES)) - 1;
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
	if( pixel_linear_z + f3rdDepthDelta < max_depth && pixel_linear_z > min_depth + f1stDepthDelta )
	{
		light_per_row = 1;
		light_per_row = min( light_per_row, min( BRight - BLeft, BBottom - BTop ) * DEPTH_RES );
		//uncomment the line below to see regions subdivided
		//return float4(0,0,1,1);
	}
	
	//used to scale float to integer and vice versa
	float  rescale = 1/g_NormalizedFloatToSATUINT;
	//Zmin is the estimated occluding depth in light space
	float Zmin = 0, fPartLit = 0, unocc_part = 0;
	//the estimation below returns the fPartLit, Zmin and unocc_part
	est_occ_depth_and_chebshev_ineq( 0,light_per_row, BLeft, BRight,BTop, pixel_linear_z, fPartLit, Zmin, unocc_part );
	
	//[branch]if( fPartLit < 0.0 ) return float4(0,0,0,1);

	//estimated the shrinked filter region
	float	T_LightWidth  = ( vPosLight.w - Zmin ) * ( fFilterSize ) / vPosLight.w;
	float	S_LightWidth  = fLightZn * T_LightWidth  / Zmin;
	LightWidthPersNorm  = S_LightWidth  / NpWidth,
		
	BLeft   = saturate(max( vPosLight.x/vPosLight.w-LightWidthPersNorm,-1) * 0.5 + 0.5);		BRight  = saturate(min( vPosLight.x/vPosLight.w+LightWidthPersNorm, 1) * 0.5 + 0.5);
	BTop = saturate(1 -( min( vPosLight.y/vPosLight.w+LightWidthPersNorm,1) * 0.5 + 0.5 ));	BBottom  = saturate(1 -( max( vPosLight.y/vPosLight.w-LightWidthPersNorm,-1) * 0.5 + 0.5 )); 
	
	if( light_per_row == 1 )	//slightly increase the subdivision level
		light_per_row = 1;
		
	//guarantee that the subdivision is not too fine, subarea smaller than a texel would introduce back ance artifact ( subarea len becomes 0  )		
	light_per_row = min( light_per_row, min( BRight - BLeft, BBottom - BTop ) * DEPTH_RES );
		
	//est_occ_depth_and_chebshev_ineq( fMainBias,light_per_row, BLeft, BRight,BTop, pixel_linear_z, fPartLit, Zmin, unocc_part );
	fPartLit = EvaluateVSMShadow_SubDiv_Bilinear((BRight-BLeft)/2, ShadowTexC, pixel_linear_z);
	//dont try to remove these 2 branch, otherwise black acne appears
	[branch]if( fPartLit <= 0.0 )
		return float4(0,0,0,1);		
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

