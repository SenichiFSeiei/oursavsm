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
#include "QTConstants.fx"
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
	float lit_bias = 0.005;
	float occ_depth_limit = 0.02;
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

			if( moments.x > pixel_linear_z )
				unocc_part += 1.0;
			else if( moments.y <= 1 )
			{
				sum_x += moments.x;
				sum_sqr_x += moments.y;
				float Ex = moments.x;
				float E_sqr_x = moments.y;
				float VARx = E_sqr_x - Ex * Ex;
				float est_depth = pixel_linear_z - Ex;
				if( Ex + lit_bias * 2 > pixel_linear_z )
					fPartLit += 1;
				else
					fPartLit += VARx / (VARx + est_depth * est_depth );

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
		float est_depth = pixel_linear_z - Ex;
		fPartLit /= ((light_per_row * light_per_row)-unocc_part-unsure_part);
		fPartLit = min( fPartLit,VARx / (VARx + est_depth * est_depth ) );
		occ_depth = max( occ_depth_limit,( Ex - fPartLit * pixel_linear_z )/( 1 - fPartLit ));
		occ_depth = occ_depth*(fLightZf-fLightZn) + fLightZn;
		fPartLit = (1 - unocc_part/(light_per_row * light_per_row-unsure_part)) * fPartLit + unocc_part/(light_per_row * light_per_row-unsure_part);
	}
	if( light_per_row * light_per_row == unocc_part )
		fPartLit = 1.0;

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

//closely related to this context, could not be used alone

uint4 SampleSatVSMBilinear( float2 texC )
{
	float2 uv_off = frac( texC * DEPTH_RES - float2(0.5,0.5) );
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


uint2 SampleSatVSMBilinear2( float2 texC )
{
	float2 uv_off = frac( texC * DEPTH_RES - float2(0.5,0.5) );

	int3   texel_idx = int3( floor( texC.x * DEPTH_RES-0.5),floor( texC.y * DEPTH_RES-0.5),0 );
	uint2  depth_avg;
	uint2  depth0 = SatVSM.Load(int3(texel_idx.x,texel_idx.y,0));
	uint2  depth1 = SatVSM.Load(int3(texel_idx.x + 1,texel_idx.y,0));
	uint2  depth2 = SatVSM.Load(int3(texel_idx.x,texel_idx.y + 1,0));
	uint2  depth3 = SatVSM.Load(int3(texel_idx.x+1,texel_idx.y + 1,0));
	depth_avg.x = ( ((float)depth0.x) * ( 1 - uv_off.x ) * ( 1 - uv_off.y )  +  ((float)depth1.x) * uv_off.x * ( 1 - uv_off.y ) 
						+ ((float)depth2.x) * ( 1 - uv_off.x ) * uv_off.y  +  ((float)depth3.x) * uv_off.x * uv_off.y );
	
	depth_avg.y = ( ((float)depth0.y) * ( 1 - uv_off.x ) * ( 1 - uv_off.y )  +  ((float)depth1.y) * uv_off.x * ( 1 - uv_off.y ) 
							+ ((float)depth2.y) * ( 1 - uv_off.x ) * uv_off.y  +  ((float)depth3.y) * uv_off.x * uv_off.y );
	return depth_avg;	
} 

uint2 SampleSatVSMPoint( float2 texC )
{
	int3   texel_idx = int3( round( texC.x * DEPTH_RES-0.5),round( texC.y * DEPTH_RES-0.5),0 );
	uint2  depth = SatVSM.Load(int3(texel_idx.x,texel_idx.y,0));	
	return depth;
} 

float est_occ_depth_and_chebshev_ineq_aligned( float bias,int light_per_row, float BLeft, float BRight,float BTop, float pixel_linear_z, out float fPartLit,out float occ_depth, out float unocc_part, out float unsure_part )
{
	float BBottom = BTop + BRight - BLeft;
	/*
	if( BRight - BLeft < 2/(float)DEPTH_RES )
	{
		BLeft = (floor(BLeft*DEPTH_RES+0.5)+0.5)/(float)DEPTH_RES;
		BTop = (floor(BTop*DEPTH_RES+0.5)+0.5)/(float)DEPTH_RES;
		BRight = (floor(BRight*DEPTH_RES+0.5)+0.5)/(float)DEPTH_RES;
		BBottom = (floor(BBottom*DEPTH_RES+0.5)+0.5)/(float)DEPTH_RES;
	}
	*/
	float lit_bias = 0.00;
	float4 moments = float4(0.0,0.0,0.0,0.0);
	float  sub_light_size_01 = max((BRight-BLeft)/light_per_row,2.0f/1024.0);
	float  rescale = 1/g_NormalizedFloatToSATUINT;
	
	float2 curr_lt = float2( BLeft, BTop );
	
	float sum_x = 0, sum_sqr_x = 0;
	unocc_part = 0.0;
	unsure_part = 0.0;
	int idx = 0;
	float total_area = 0;
	float test_area = 0;
	
	float2 crd_lt = float2(BLeft,BTop-sub_light_size_01);
	float2 crd_rb = float2(BLeft,BTop);

	while( crd_rb.y < BBottom )
	{
		crd_lt.x = BLeft;
		crd_lt.y = crd_rb.y;
		
		if( crd_lt.y == BTop )
			crd_rb.y = (floor(crd_lt.y*DEPTH_RES+0.5)+0.5)/(float)DEPTH_RES;
		else
			crd_rb.y += sub_light_size_01;
		crd_rb.y = min( crd_rb.y, BBottom );
		crd_rb.x = crd_lt.x;


		while( crd_rb.x < BRight )
		{
			if( crd_lt.x == BLeft )
			{
				crd_rb.x = (floor(crd_lt.x*DEPTH_RES+0.5)+0.5)/(float)DEPTH_RES;
			}
			else
			{
				crd_rb.x += sub_light_size_01;
			}
			crd_rb.x = min( crd_rb.x,BRight );
#ifdef DUMP
			FILE *fp = fopen("detail.txt","a");
			//fprintf(fp,"crd_lt:<%f,%f>   crd_rp:<%f,%f>\n",crd_lt.x,crd_lt.y,crd_rb.x,crd_rb.y);
#endif		
			uint2  d_lt = SampleSatVSMBilinear2( crd_lt );
			uint2  d_lb = SampleSatVSMBilinear2( float2(crd_lt.x,crd_rb.y) );

			uint2  d_rt = SampleSatVSMBilinear2( float2(crd_rb.x,crd_lt.y) );
			uint2  d_rb = SampleSatVSMBilinear2( crd_rb );
			
			moments.x = (d_rb.x - d_rt.x - d_lb.x + d_lt.x) * rescale / ((crd_rb.x - crd_lt.x)*(crd_rb.y - crd_lt.y)*DEPTH_RES*DEPTH_RES);
			moments.y = (d_rb.y - d_rt.y - d_lb.y + d_lt.y) * rescale / ((crd_rb.x - crd_lt.x)*(crd_rb.y - crd_lt.y)*DEPTH_RES*DEPTH_RES);
#ifdef DUMP
			fprintf(fp,"moments:<%f,%f>\n",moments.x,moments.y);
			fclose(fp);
#endif		
			
			//if( pixel_linear_z - moments.x<0 && pixel_linear_z - moments.x > -0.001 )
			//	unsure_part += 1.0;
			
			if( moments.x > pixel_linear_z  )
				unocc_part += 1.0;
			else if( moments.y <= 1 )
			{
				float this_area = ( crd_rb.x - crd_lt.x ) * ( crd_rb.y - crd_lt.y );
				sum_x += ( moments.x * this_area );
				sum_sqr_x += ( moments.y * this_area );
				total_area += this_area;
			}
			test_area += ( crd_rb.x - crd_lt.x ) * ( crd_rb.y - crd_lt.y );
			crd_lt.x = crd_rb.x;
			++idx;
		}

	}
	float Ex = sum_x / total_area;
	
	if( Ex + lit_bias > pixel_linear_z )//according to VSM formula, Ex larger than pixel depth means lit
		fPartLit = 1.0f;
	else
	{
		float E_sqr_x = sum_sqr_x / total_area;

		float VARx = max(E_sqr_x - Ex * Ex,0.000001);
		float est_depth = pixel_linear_z - Ex;//too small compared to VARx
		fPartLit = VARx / (VARx + est_depth * est_depth );
		occ_depth = max( 0,( Ex - fPartLit * pixel_linear_z )/( 1 - fPartLit ));
		occ_depth = occ_depth*(fLightZf-fLightZn) + fLightZn;
		float entire_area = (BRight - BLeft)*(BRight - BLeft);
		fPartLit = (total_area * fPartLit + ( entire_area - total_area ))/entire_area;
	}
	if( idx == unocc_part )
		fPartLit = 1.0;
	if( total_area == 0.0 )
		fPartLit = 1.0;

	return Ex;
}

float est_occ_depth_and_chebshev_ineq_QT( float bias,int light_per_row, float BLeft, float BRight,float BTop, float pixel_linear_z, out float fPartLit, out float occ_depth, out float unocc_part, out float unsure_part )
{
	float BBottom = BTop + BRight - BLeft;

	float lit_bias = 0.00;
	float4 moments = float4(0.0,0.0,0.0,0.0);
	float  light_size_01 = BRight-BLeft;
	float  rescale = 1/g_NormalizedFloatToSATUINT;
		
	float sum_x = 0, sum_sqr_x = 0;
	unocc_part = 0.0;	unsure_part = 0.0;
	int idx = 0;
	float total_area = 0,//effective total area, except those leaves with very large variance, pcf_area not included 
		  pcf_area = 0,//area that can not apply vsm formula, should be leaf level area with unreasonable variance OR non-planar leaf appears as not occluding
		  unocc_area = 0,//area that are sure to be not occluder 
		  penu_area = 0;//area that can safely apply vsm formula
	float pcf_visibility = 0;
	
	float2 crd_lt = float2(BLeft,BTop), crd_rb = float2(BRight,BBottom), crd_ct = float2( (BLeft+BRight)/2, (BTop+BBottom)/2 );

    int QTA_idx = 0, old_QTA_idx = -1, loop_cnt = 0, leave_level = 3;
    float4 qt_entry = QTConstants[QTA_idx];
    
	//Adjust the tree level.
	//When handling leave smaller than 1 texel, the algorithm produces black noise, even on completely lit area.
	//I tried to use floor on those integer related operations, and the result is not very good. Round gives very good result on the contrary.
	float texelwise_size = round((BRight - BLeft) * (float)DEPTH_RES);
	texelwise_size = max( texelwise_size, 1 );
	leave_level = round( log( texelwise_size ) );
	leave_level = min( 3, leave_level );
	//this slightly decreases the image quality, discontinuty could be observed at where different subdivid numbers are applied
	//unless force it here, there is no leave_level == 0 case in the quad_staple scene
	if( light_per_row == 1 )
		leave_level = 1;
	float kernel_size = (BRight-BLeft)*DEPTH_RES;
    do{
		old_QTA_idx = QTA_idx;
		
		if( crd_lt.x != BLeft) crd_lt.x = (floor(crd_lt.x*DEPTH_RES+0.5)-0.5)/(float)DEPTH_RES;
		if( crd_lt.y != BTop ) crd_lt.y = (floor(crd_lt.y*DEPTH_RES+0.5)-0.5)/(float)DEPTH_RES;
		if( crd_rb.x != BRight  ) crd_rb.x = (floor(crd_rb.x*DEPTH_RES+0.5)-0.5)/(float)DEPTH_RES;
		if( crd_rb.y != BBottom ) crd_rb.y = (floor(crd_rb.y*DEPTH_RES+0.5)-0.5)/(float)DEPTH_RES;
	
		
 		uint2  d_lt = SampleSatVSMBilinear2( crd_lt );
		uint2  d_lb = SampleSatVSMBilinear2( float2(crd_lt.x,crd_rb.y) );

		uint2  d_rt = SampleSatVSMBilinear2( float2(crd_rb.x,crd_lt.y) );
		uint2  d_rb = SampleSatVSMBilinear2( crd_rb );
		
		moments.x = (d_rb.x - d_rt.x - d_lb.x + d_lt.x) * rescale / ((crd_rb.x - crd_lt.x)*(crd_rb.y - crd_lt.y)*DEPTH_RES*DEPTH_RES);
		
		uint ui_y = d_rb.y - d_rt.y - d_lb.y + d_lt.y;
		moments.y = (ui_y) * rescale / ((crd_rb.x - crd_lt.x)*(crd_rb.y - crd_lt.y)*DEPTH_RES*DEPTH_RES);
        float variance = max(moments.y - moments.x * moments.x,0.000001);

		//the current area of the node.
        float this_area = ( crd_rb.x - crd_lt.x ) * ( crd_rb.y - crd_lt.y );

		//non-leaf node
		if( qt_entry.x != leave_level )
		{
			//planar node that is unoccluded
			if( moments.x > pixel_linear_z && variance<0.0001 )
			{
				unocc_area += this_area;
				QTA_idx += qt_entry.y;
				total_area += this_area;
			}
			//planar node that can safely apply vsm formula
			else if( moments.x < pixel_linear_z && qt_entry.x != leave_level && variance<0.0001 )
			{
				sum_x += ( moments.x * this_area );
				sum_sqr_x += ( moments.y * this_area );
				penu_area += this_area;
				QTA_idx += qt_entry.y;
				total_area += this_area; 
			}
			else
				QTA_idx += 1;
		}
		//leaf node
		else
		{
			//planar leaf that is unoccluded
			if( moments.x > pixel_linear_z && variance<0.0001 )
			{
				unocc_area += this_area;
				QTA_idx += qt_entry.y;
				total_area += this_area;
			}
			//non-planar leaf that is unoccluded(potentially error, special care).
			else if( moments.x > pixel_linear_z && variance>0.0001 )
			{
/////////////////////////////////////////////////////////////////////////////////////////////
//				comment the fragment below to involve PCF
				unocc_area += this_area;
				QTA_idx += qt_entry.y;
				total_area += this_area;
/////////////////////////////////////////////////////////////////////////////////////////////
//				uncomment the fragment below to involve PCF
/*
				QTA_idx += qt_entry.y;
				int   n = 3;
				float result = 0;
				float u_step = abs(crd_lt.x-crd_rb.x)/(float)(n-1);
				float v_step = abs(crd_lt.y-crd_rb.y)/(float)(n-1);
				float current_v = crd_lt.y;
				for( int i = 0; i<n; ++i )
				{
					float current_u = crd_lt.x;
					for( int j = 0; j<n; ++j )
					{
						float cur_depth = DepthMip2.SampleLevel( PointSampler,float2(current_u,current_v),0 );
						if( cur_depth > pixel_linear_z )
							result += 1;
						current_u += u_step;
					}
					current_v += v_step;
				}
				result /= (float)(n*n);
				result *= this_area;
				pcf_area += this_area;
				pcf_visibility += result;
*/
			}
			//leaf can safely apply vsm formula, potential condition (moments.x <= pixel_linear_z)
			//planar leaf ( can safely apply vsm formula )
			//non-planar leaf ( can safely apply vsm formula ), those with reasonable variance
			else if( variance < 0.5 )
			{
				sum_x += ( moments.x * this_area );
				sum_sqr_x += ( moments.y * this_area );
				penu_area += this_area;
				QTA_idx += qt_entry.y;
				total_area += this_area;
			}
			//non-planar leaf with unreasonable variance, error prone, either ignore or use pcf
			//note pcf only applied on leaf level as node with large variance are subdivided(only planar node gets early process)
			else if( qt_entry.x == leave_level && variance >= 0.5 )
			{
				QTA_idx += qt_entry.y;
/////////////////////////////////////////////////////////////////////////////////////////////
//				uncomment the fragment below to involve PCF
/*
				int   n = 3;
				float result = 0;
				float u_step = abs(crd_lt.x-crd_rb.x)/(float)(n-1);
				float v_step = abs(crd_lt.y-crd_rb.y)/(float)(n-1);
				float current_v = crd_lt.y;
				for( int i = 0; i<n; ++i )
				{
					float current_u = crd_lt.x;
					for( int j = 0; j<n; ++j )
					{
						float cur_depth = DepthMip2.SampleLevel( PointSampler,float2(current_u,current_v),0 );
						if( cur_depth > pixel_linear_z - 0.0 )
							result += 1;
						current_u += u_step;
					}
					current_v += v_step;
				}
				result /= (float)(n*n);
				result *= this_area;
				pcf_area += this_area;
				pcf_visibility += result;
*/	
			}
			else
				QTA_idx += qt_entry.y;
		}

        qt_entry = QTConstants[QTA_idx];
        crd_ct = float2(BLeft,BTop) + light_size_01 * float2((qt_entry.z+1)*0.5,(qt_entry.w+1)*0.5);
        float half_extent = light_size_01 / pow(2,1+qt_entry.x);
        crd_lt = crd_ct - float2(half_extent,half_extent);
        crd_rb = crd_ct + float2(half_extent,half_extent);
        loop_cnt ++;
    }while(QTA_idx!=old_QTA_idx&&loop_cnt<86);
	float Ex = 0;
	if( sum_x == 0 && penu_area == 0 )//no occluder at all
	{
		fPartLit = 1.0;
	}
	else
	{
		Ex = sum_x / penu_area;
		
		if( Ex + lit_bias > pixel_linear_z )//according to VSM formula, Ex larger than pixel depth means lit
			fPartLit = 1.0f;
		else
		{
			float E_sqr_x = sum_sqr_x / penu_area;

			float VARx = max(E_sqr_x - Ex * Ex,0.000001);
			float est_depth = pixel_linear_z - Ex;//too small compared to VARx
			fPartLit = VARx / (VARx + est_depth * est_depth );
			occ_depth = max( 0,( Ex - fPartLit * pixel_linear_z )/( 1 - fPartLit ));
			occ_depth = occ_depth*(fLightZf-fLightZn) + fLightZn;
			float entire_area = (BRight - BLeft)*(BRight - BLeft);
			fPartLit = (penu_area * fPartLit + ( total_area - penu_area ))/total_area;
		}
	}
	fPartLit = ( fPartLit * total_area + pcf_visibility/* *pcf_area/pcf_area */ ) / ( total_area + pcf_area );
	//if( abs( total_area - unocc_area ) == 0 )
	//	fPartLit = 1.0;
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
		return float4(1,1,0,1);
	
	//this is the variable used to control the level of filter area subdivision	
	int    light_per_row = 1;
	//those stuck in complex depth relationship are subdivided, others dont
	if( pixel_linear_z + 0.059 < max_depth && pixel_linear_z > min_depth + 0.06 )
	{
		light_per_row = 5;
		light_per_row = min( light_per_row, min( BRight - BLeft, BBottom - BTop ) * DEPTH_RES );
		//uncomment the line below to see regions subdivided
		//return float4(1,0,1,1);
	}
	
	//used to scale float to integer and vice versa
	float  rescale = 1/g_NormalizedFloatToSATUINT;
	//Zmin is the estimated occluding depth in light space
	float Zmin = 0, fPartLit = 0, unocc_part = 0, unsure_part = 0;
	//the estimation below returns the fPartLit, Zmin and unocc_part
	est_occ_depth_and_chebshev_ineq( 0,light_per_row, BLeft, BRight,BTop, pixel_linear_z, fPartLit, Zmin, unocc_part, unsure_part );
	//Should comment it back//[branch]if( fPartLit <= 0.0 ) return float4(0,0,1,1); // some results in neg fPartLit, due to neg VARx and est_depth^2 larger than VARx, I found all of them are dark
	[branch]if( fPartLit >= 1.0 ) return float4(1,1,0,1); // some results in fPartLit > 1, due to neg VARx but est_depth^2 smaller than VARx, I found all of them are lit 

	//estimated the shrinked filter region
	float	T_LightWidth  = ( vPosLight.w - Zmin ) * ( fFilterSize ) / vPosLight.w;
	float	S_LightWidth  = fLightZn * T_LightWidth  / Zmin;
	LightWidthPersNorm  = S_LightWidth  / NpWidth;
		
	BLeft   = saturate(max( vPosLight.x/vPosLight.w-LightWidthPersNorm,-1) * 0.5 + 0.5);		BRight  = saturate(min( vPosLight.x/vPosLight.w+LightWidthPersNorm, 1) * 0.5 + 0.5);
	BTop = saturate(1 -( min( vPosLight.y/vPosLight.w+LightWidthPersNorm,1) * 0.5 + 0.5 ));	BBottom  = saturate(1 -( max( vPosLight.y/vPosLight.w-LightWidthPersNorm,-1) * 0.5 + 0.5 )); 
	
/*	
	[branch]if( ( BRight - BLeft ) * DEPTH_RES < 9 )
	{
		float result = 0;
		int iSamplePoint = 5;//must be odd number
		float SampleInterval = ( BRight - BLeft )/(iSamplePoint-1);
		for( int i = 0; i<iSamplePoint; ++i )
		{
			for( int j = 0; j<iSamplePoint; ++j )
			{
				float2 pcfTexC = float2(BLeft,BTop) + float2(i*SampleInterval,j*SampleInterval);
				float cur_depth = DepthMip2.SampleLevel( LinearSampler, pcfTexC,0 );
				if( cur_depth > pixel_linear_z - 0.0 )
					result += 1;
			}
		}
		result /= (iSamplePoint*iSamplePoint);
		//if( result < 0.05 )
			return float4( result, result, result, 1 );
	}
*/
	if( light_per_row == 5 )	//slightly increase the subdivision level
		light_per_row = 10;
	//guarantee that the subdivision is not too fine, subarea smaller than a texel would introduce back ance artifact ( subarea len becomes 0  )		
	light_per_row = min( light_per_row, min( BRight - BLeft, BBottom - BTop ) * DEPTH_RES );

	est_occ_depth_and_chebshev_ineq_QT( fMainBias,light_per_row, BLeft, BRight,BTop, pixel_linear_z, fPartLit, Zmin, unocc_part, unsure_part );

	//dont try to remove these 2 branch, otherwise black acne appears
	[branch]if( fPartLit <= 0.0 )
		return float4(0,0,0,1);		
	//[branch]if( unocc_part == (light_per_row * light_per_row) )
	//	return float4(1,1,1,1);
	
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
		ret_color = float4(1,1,0,1);
	else
		ret_color = AccurateShadowIntSATMultiSMP4(Input.Pos,float4(1,1,1,1),true);
			
	float4 curr_result = phong_shading(vLightPos.xyz,VCameraInLight.xyz,surfNorm,SkinSpecCoe,diff,ret_color,spec_clr_ogre);
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

