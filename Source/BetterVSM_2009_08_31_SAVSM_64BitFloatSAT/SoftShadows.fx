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

#include "DeferredShading.fxh"
#include "CommonDef.h"
RasterizerState RStateMSAAON
{
	MultisampleEnable = FALSE; // performance hit is too high with MSAA for this sample
};

Texture2D<float>  TexDepthMap;
Texture2D<float2> TexHSM;

Texture2D<float>  TexRadialArea;
Texture2D<float4> TexPosInWorld;
Texture2D<float4> TexPreviousResult;
Texture2D<float4> TexNormalInWorld;
Texture2D<float4> TexColor;
Texture2D<float4> TexHSMKernel;

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
    float DepthBiasDefault = 0.001;
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
};


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
	spec_coe = pow( spec_coe,50);
	float  diff_coe = saturate(dot(surfNorm,lightDirInLightView));

	float4 ret_color = ( diffuse_clr * diff_coe + spec_coe * spec_clr ) * VLightFlux * shadow_coe;

   return ret_color;

}

float2 tex2Dlod( float2 texC, int level )
{
	texC = saturate( texC );
	float2 vPixel = floor( texC * g_fRes[level] ) + 0.5;
    [flatten] if (level != 0)
    { vPixel += float2(DEPTH_RES, 1 << (N_LEVELS - level)); }
    vPixel -= float2(0.5,0.5);
    float2 vMinMax = TexHSM.Load( int3( vPixel.x, vPixel.y, 0 ) );
    return vMinMax;
}

float2 BackProj0( float2 vDepthMin, float3 vLightPos, uint2 iPixel )
{

	vDepthMin = 1. / (vDepthMin * mLightProjClip2TexInv[2][3] + mLightProjClip2TexInv[3][3]);
	float2 vMin = 0.5 - float2(iPixel.x, iPixel.y) * g_fResRev[0];
	vMin *= 2 * float2(mLightProjClip2TexInv[3][0], mLightProjClip2TexInv[3][1]);
	vMin = (vMin * vLightPos.zz - vLightPos.xy) / (vLightPos.zz / vDepthMin.xy - 1);
	
	vMin.x=min(fFilterSize,max(-fFilterSize,vMin.x));
	vMin.y=min(fFilterSize,max(-fFilterSize,vMin.y));
	
	vMin = (vMin + fFilterSize)/(2*fFilterSize);//normalized between 0,1
	
	return vMin;
	
}
float2 BackProj1( float2 vDepthMin, float3 vLightPos, uint2 iPixel )
{

	vDepthMin = 1. / (vDepthMin * mLightProjClip2TexInv[2][3] + mLightProjClip2TexInv[3][3]);
	float2 vMin = 0.5 - float2(iPixel.x, iPixel.y) * g_fResRev[0];
	vMin *= 2 * float2(mLightProjClip2TexInv[3][0], mLightProjClip2TexInv[3][1]);
	vMin = (vMin * vLightPos.zz - vLightPos.xy) / (vLightPos.zz / vDepthMin.xy - 1);
	
	vMin.x=min(fFilterSize,max(-fFilterSize,vMin.x));
	vMin.y=min(fFilterSize,max(-fFilterSize,vMin.y));
	return vMin;
	
}


float4 AccurateShadow(float4 vPos, float4 vDiffColor, bool limit_kernel = false, bool use_bias = true)
{
	bool use_mul_res = true;
	//float4 vLightPos = TexPosInWorld.Load(int3(vPos.x-0.5,vPos.y-0.5,0));
	float4 vLightPos = TexPosInWorld.Load(int3(vPos.x-0.5,vPos.y-0.5,0));	
	vLightPos = mul( float4(vLightPos.xyz,1), mLightView );
	
	float4 vHSMKernel = TexHSMKernel.Load(int3(vPos.x-0.5,vPos.y-0.5,0));
	float4 vPosLight = mul( float4(vLightPos.xyz,1), mLightProj );
	float2 ShadowTexC = ( vPosLight.xy/vPosLight.w ) * 0.5 + float2( 0.5, 0.5 ) ;
	ShadowTexC.y = 1.0 - ShadowTexC.y;
	
	if(   ShadowTexC.x<0.01   || ShadowTexC.y<0.01
		||ShadowTexC.x>0.99 || ShadowTexC.y>0.99 )
		return float4(1,1,1,1);
		

	float  Zn = fLightZn;
	float  Zf = fLightZn + LIGHT_ZF_DELTA;
	
	
	float  LightSize = fFilterSize;
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
	vDepthMin[0] =  TexDepthMap.Load( int3( right_bottom_x-1,right_bottom_y  ,0));
	vDepthMin[1] =  TexDepthMap.Load( int3( right_bottom_x  ,right_bottom_y  ,0));
	vDepthMin[2] =  TexDepthMap.Load( int3( right_bottom_x  ,right_bottom_y-1,0));
	vDepthMin[3] =  TexDepthMap.Load( int3( right_bottom_x-1,right_bottom_y-1,0));
	uint idx = 0;
	
	float depth_bias;
	if( use_bias )
		depth_bias = DepthBiasDefault;
	else
		depth_bias = 0;

	idx |= !(vDepthMin[3]>pixel_unit_z - max(0.00000,depth_bias));
	idx<<=1;
	idx |=! (vDepthMin[2]>pixel_unit_z - max(0.00000,depth_bias));
	idx<<=1;
	idx |=! (vDepthMin[1]>pixel_unit_z - max(0.00000,depth_bias));
	idx<<=1;
	idx |=! (vDepthMin[0]>pixel_unit_z - max(0.00000,depth_bias));
	uint gidx = idx;
	
	float init_vf = 1;
	
	float2 mar_sqr_idx = g_fMarchingSquare[idx];
	
	uint2  vMinCr = uint2(CoordX[ mar_sqr_idx.x ],CoordY[ mar_sqr_idx.x ]),
		   vMaxCr = uint2(CoordX[ mar_sqr_idx.y ],CoordY[ mar_sqr_idx.y ]);
	
	float2 vMin = BackProj0(vDepthMin[mar_sqr_idx.x].xx,vLightPos,vMinCr);
	float2 vMax = BackProj0(vDepthMin[mar_sqr_idx.y].xx,vLightPos,vMaxCr);
	
	float3 center_edge = float3(vMax,0)-float3(vMin,0);
	float3 center_from_edge_start = float3(float3(x/w,y/w,0)-float3(vMin,0));
	float  len = cross(center_edge,center_from_edge_start).z;
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
		
	uint march_square_increment = 1;
	
	idx = 0;
	[loop]for( uint i = nBBottom; i<=nBTop+1;i+=march_square_increment){
		[loop]for ( uint j=nBLeft;j<=nBRight+1;j+=march_square_increment)
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
			vDepthMin[0] =  TexDepthMap.Load( int3( iPixel.x-1,iPixel.y ,0));
			vDepthMin[1] =  TexDepthMap.Load( int3( iPixel.x  ,iPixel.y,0));
			vDepthMin[2] =  TexDepthMap.Load( int3( iPixel.x  ,iPixel.y-1,0));
			vDepthMin[3] =  TexDepthMap.Load( int3( iPixel.x-1,iPixel.y-1,0));

			
			idx = 0;
			idx |= !(vDepthMin[3]>pixel_unit_z - depth_bias);
			idx<<=1;
			idx |=! (vDepthMin[2]>pixel_unit_z - depth_bias);
			idx<<=1;
			idx |=! (vDepthMin[1]>pixel_unit_z - depth_bias);
			idx<<=1;
			idx |=! (vDepthMin[0]>pixel_unit_z - depth_bias);

			[branch]if( idx>0&&idx<15){
				float2 mar_sqr_idx = g_fMarchingSquare[idx];
				
				uint2  vMinCr = uint2(CoordX[ mar_sqr_idx.x ],CoordY[ mar_sqr_idx.x ]),
					   vMaxCr = uint2(CoordX[ mar_sqr_idx.y ],CoordY[ mar_sqr_idx.y ]);
				
				float2 vMin = BackProj0(vDepthMin[mar_sqr_idx.x].xx,vLightPos,vMinCr);
				float2 vMax = BackProj0(vDepthMin[mar_sqr_idx.y].xx,vLightPos,vMaxCr);
				
				int R = 32 - 1;
				vMin = floor((vMin*2*R + 1)/2);
				vMax = floor((vMax*2*R + 1)/2);
				int2 texcrd;
				//originally is as annoted above, which left hand convention applied
				//now use right hand convention
				texcrd = vMax * 32 + vMin;
				float tmp_area = TexRadialArea.Load(int3(texcrd,0));
				tmp_area = -tmp_area;
				OccArea += tmp_area;
			}				
		}
	}
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
		

    return float4(fTotShadow,fTotShadow,fTotShadow,1); // this is never reached, but compiler curses if the line is not here
    
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
	[branch]if( 0 == diff_coe )
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



//-------------------------------------------------------------------------------------------------
//		Render Kernel Size
//-------------------------------------------------------------------------------------------------

float4 HSMKernel(float4 vPos)
{
	float4 vLightPos = TexPosInWorld.Load(int3(vPos.x-0.5,vPos.y-0.5,0));	
	vLightPos = mul( float4(vLightPos.xyz,1), mLightView );
		
	float4 vPosLight = mul( float4(vLightPos.xyz,1), mLightProj );
	float2 ShadowTexC = ( vPosLight.xy/vPosLight.w ) * 0.5 + float2( 0.5, 0.5 ) ;
	ShadowTexC.y = 1.0 - ShadowTexC.y;
	
	if(   ShadowTexC.x<0   || ShadowTexC.y<0
		||ShadowTexC.x>1.0 || ShadowTexC.y>1.0 )
		return float4(1,1,1,1);
	
	float  Zn = fLightZn;
	float  Zf = fLightZn + LIGHT_ZF_DELTA;
	
	
	float  LightSize = fFilterSize;
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
	[loop]for( int cnt = 0; cnt < 4 ; cnt ++ ){
	
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
		return float4(-100,1,1,1);
	}
	else if( Zmax<w )
	{
		return float4(-200,1,1,1);
	}
	else
	{
		return float4(BLeft,BRight,BBottom,BTop);
	}
}

float4 RenderHSMKernelPS(QuadVS_Output Input) : SV_Target0
{
    return HSMKernel(Input.Pos);
}

technique10 RenderHSMKernel
{
    pass P0
    {
        SetVertexShader(CompileShader(vs_4_0, QuadVS()));
        SetGeometryShader(NULL);
        SetPixelShader(CompileShader(ps_4_0, RenderHSMKernelPS()));
		SetRasterizerState(RStateMSAAON);
    }
}


