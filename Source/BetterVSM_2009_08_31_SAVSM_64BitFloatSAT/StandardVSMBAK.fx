/*
//2009 9 20
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
					if( pixel_unit_z < Ex  )
					{
						return float4(1,1,1,1);
					}
					else
						fPartLit = VARx / ( VARx + ( pixel_unit_z - Ex ) * ( pixel_unit_z - Ex ) );
					//return float4( fPartLit, fPartLit, fPartLit, 1);
					sum_depth +=  max( 0,( moments0.x - fPartLit * pixel_unit_z )/( 1 - fPartLit ));
				}
				curr_lt.x += sub_light_size_01;
			}
			curr_lt.x = BLeft;
			curr_lt.y += sub_light_size_01;
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
	
	float  rescale = 1/g_NormalizedFloatToSATUINT;
	float2 moments = {0.0,0.0};
	float2 moments0, moments1, moments2, moments3;

//----------- experiment -----------------
	float fPartLit2 = 0.0;
	float delta_incre = 0;
	{
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
				delta_incre = mu;
				float  delta_sqr = moments0.y - mu * mu;
				if( pixel_unit_z < mu + DepthBiasDefault  )
				{
					fPartLit2 += 1.0;
				}
				else
					fPartLit2 += delta_sqr / ( delta_sqr + ( pixel_unit_z - mu ) * ( pixel_unit_z - mu ) );
				curr_lt.x += sub_light_size_01;
			}
			curr_lt.x = BLeft;
			curr_lt.y += sub_light_size_01;
		}
		fPartLit2 /= (light_per_row * light_per_row) ;
		
	}
//----------- experiment -----------------
	
	float fPartLit = 0;

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
			float  bias_limit = -0.05;
			float  tmp_pixel_z = pixel_unit_z + min(min( 0, mu - delta_incre ),bias_limit);
			float  tmp_pixel_z2 = pixel_unit_z + min(min( 0, mu - delta_incre ),bias_limit)*0.2 ;
			if( tmp_pixel_z < mu + DepthBiasDefault && delta_sqr < 0.01 )
			{
				fPartLit += 1.0;
			}
			else
			{
				fPartLit += delta_sqr / ( delta_sqr + ( tmp_pixel_z2 - mu ) * ( tmp_pixel_z2 - mu ) );
			}
			curr_lt.x += sub_light_size_01;
		}
		curr_lt.x = BLeft;
		curr_lt.y += sub_light_size_01;
	}
	fPartLit /= (light_per_row * light_per_row) ;
	//fPartLit += fPartLit2 * 0.00001;

//---------------------------
	return float4( fPartLit,fPartLit,fPartLit,1);
	
}

//2009 9 20
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
	float  Zf = fLightZf;
	float  w = vPosLight.w,
		   x = vPosLight.x,
		   y = vPosLight.y;
	float pixel_unit_z = vPosLight.z/vPosLight.w;
#ifdef	USE_LINEAR_Z
	float pixel_linear_z = (vPosLight.w - Zn) / (Zf-Zn);
#endif

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
		
		int    light_per_row = 3;
		float  sub_light_size_01 = ( BRight - BLeft ) / light_per_row;
		
		float2 curr_lt = float2( BLeft, BTop );
		float unocc_part = 0, sum_ex = 0, sum_varx = 0;
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
#ifdef USE_LINEAR_Z
				if( Ex > pixel_linear_z + DepthBiasKernel )
#else
				if( Ex > pixel_unit_z + DepthBiasKernel )
#endif
				{
					++unocc_part;
				}
				else
				{
					sum_ex += Ex;
					sum_varx += VARx;
				}
				curr_lt.x += sub_light_size_01;
			}
			curr_lt.x = BLeft;
			curr_lt.y += sub_light_size_01;
		}
		if( unocc_part == (light_per_row * light_per_row) )
			return float4(1,1,1,1);
		sum_ex /= ((light_per_row * light_per_row)-unocc_part);
		sum_varx /= ((light_per_row * light_per_row)-unocc_part);
#ifdef USE_LINEAR_Z
		fPartLit = sum_varx / ( sum_varx + ( pixel_linear_z - sum_ex ) * ( pixel_linear_z - sum_ex ) );
		sum_depth =  Zn + max( 0,( sum_ex - fPartLit * pixel_linear_z )/( 1 - fPartLit ))*(Zf-Zn);
#else
		fPartLit = sum_varx / ( sum_varx + ( pixel_unit_z - sum_ex ) * ( pixel_unit_z - sum_ex ) );
		sum_depth =  max( 0,( sum_ex - fPartLit * pixel_unit_z )/( 1 - fPartLit ));
#endif


		//---------------------------
		
		//The bias is necessary due to the numerical precision. Sometimes when the occluder is very close to the receiver
		//although the occluder is slightly nearer to the light, the precision loss makes it equally distant to the light, or worse
		//makes it farther
		//A second thought, you may want to check the Cheveshev Inequality Proof for the root of this bias
#ifdef USE_LINEAR_Z
		[branch]if( sum_depth >= pixel_linear_z * (Zf-Zn) + Zn )
			return float4(1,1,1,1);
#else
		[branch]if( sum_depth >= pixel_unit_z - DepthBiasKernel )
			return float4(1,1,1,1);
#endif		
		
	}
	
#ifdef USE_LINEAR_Z
	Zmin = sum_depth;
#else
	float ZminPers = sum_depth;
	Zmin = -( Zf * Zn ) / ( ( Zf - Zn ) * ( ZminPers - Zf / ( Zf - Zn ) ) );
#endif

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

	int   light_per_row = 2;
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
#ifdef USE_LINEAR_Z
			if( pixel_linear_z < mu + DepthBiasDefault)
			{
				fPartLit += 1.0;
			}
			else
				fPartLit += delta_sqr / ( delta_sqr + ( pixel_linear_z - mu ) * ( pixel_linear_z - mu ) );
#else
			if( pixel_unit_z < mu + DepthBiasDefault)
			{
				fPartLit += 1.0;
			}
			else
				fPartLit += delta_sqr / ( delta_sqr + ( pixel_unit_z - mu ) * ( pixel_unit_z - mu ) );
#endif

			curr_lt.x += sub_light_size_01;
		}
		curr_lt.x = BLeft;
		curr_lt.y += sub_light_size_01;
	}
	fPartLit /= (light_per_row * light_per_row) ;

//---------------------------

	
	return float4( fPartLit,fPartLit,fPartLit,1);
	
}

//9.21
//#define PCF_EST
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
	float  Zf = fLightZf;
	float  w = vPosLight.w,
		   x = vPosLight.x,
		   y = vPosLight.y;
	float pixel_unit_z = vPosLight.z/vPosLight.w;
#ifdef	USE_LINEAR_Z
	float pixel_linear_z = (vPosLight.w - Zn) / (Zf-Zn);
#endif

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
		
		int    light_per_row = 4;
		
		float old_sum_depth = 0;
		float unocc_part = 0;
		float converge_bias = 0.02;
		for( ;light_per_row < 5; light_per_row += 2 )
		{
			float  sub_light_size_01 = ( BRight - BLeft ) / light_per_row;
			
			float2 curr_lt = float2( BLeft, BTop );
			unocc_part = 0;
			float sum_ex = 0, sum_varx = 0;
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
					if( Ex > pixel_linear_z + DepthBiasKernel )
					{
						++unocc_part;
					}
					else
					{
						sum_ex += Ex;
						sum_varx += VARx;
					}
					curr_lt.x += sub_light_size_01;
				}
				curr_lt.x = BLeft;
				curr_lt.y += sub_light_size_01;
			}
			sum_ex /= ((light_per_row * light_per_row)-unocc_part);
			sum_varx /= ((light_per_row * light_per_row)-unocc_part);
			fPartLit = sum_varx / ( sum_varx + ( pixel_linear_z - sum_ex ) * ( pixel_linear_z - sum_ex ) );
			sum_depth =  Zn + max( 0,( sum_ex - fPartLit * pixel_linear_z )/( 1 - fPartLit ))*(Zf-Zn);
			if(		(light_per_row > 1 && abs( sum_depth - old_sum_depth ) < converge_bias )
				 && sum_depth != Zn	)
				break;
			old_sum_depth = sum_depth;
		}
		if( unocc_part == (light_per_row * light_per_row) )
			return float4(0,1,0,1);


		//---------------------------
		
		//The bias is necessary due to the numerical precision. Sometimes when the occluder is very close to the receiver
		//although the occluder is slightly nearer to the light, the precision loss makes it equally distant to the light, or worse
		//makes it farther
		//A second thought, you may want to check the Cheveshev Inequality Proof for the root of this bias
		[branch]if( sum_depth >= pixel_linear_z * (Zf-Zn) + Zn)
			return float4(1,0,0,1);		
	}
	
	Zmin = sum_depth;

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
#ifdef PCF_EST
	float fPartLit = 0;
	float  rescale = 1/g_NormalizedFloatToSATUINT;
	float2 moments = {0.0,0.0};
	float2 moments0, moments1, moments2, moments3;

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
		float fPartLit = 0;
		float  rescale = 1/g_NormalizedFloatToSATUINT;
		float2 moments = {0.0,0.0};
		float2 moments0, moments1, moments2, moments3;
		
		int    light_per_row = 1;
		
		float unocc_part = 0;
		
			float  sub_light_size_01 = ( BRight - BLeft ) / light_per_row;
			
			float2 curr_lt = float2( BLeft, BTop );
			unocc_part = 0;
			float sum_ex = 0, sum_varx = 0;
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
					float this_bias = 0.001;
					if( Ex > pixel_linear_z - this_bias )
					{
						++unocc_part;
					}
					else
					{
						sum_ex += Ex;
						sum_varx += VARx;
					}
					curr_lt.x += sub_light_size_01;
				}
				curr_lt.x = BLeft;
				curr_lt.y += sub_light_size_01;
			}
			if( unocc_part == (light_per_row * light_per_row) )
				return float4( 1,1,1,1);
			sum_ex /= ((light_per_row * light_per_row)-unocc_part);
			sum_varx /= ((light_per_row * light_per_row)-unocc_part);
			if( sum_ex > pixel_linear_z )
				return float4(1,1,1,1);
			fPartLit = sum_varx / ( sum_varx + ( pixel_linear_z - sum_ex ) * ( pixel_linear_z - sum_ex ) ) + unocc_part/(light_per_row * light_per_row);	
	
#endif
//---------------------------
	
	return float4( fPartLit,fPartLit,fPartLit,1);
	
}


*/