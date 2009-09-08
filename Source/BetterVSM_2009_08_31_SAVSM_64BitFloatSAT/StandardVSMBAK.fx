/*
float4 AccurateShadowIntSATNBuffer(float4 vPos, float4 vDiffColor, bool limit_kernel = false, bool use_bias = true)
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
	//------------------------------------- NBuffer Kernel Reduction
	
	float Zmin,Zmax;

	for( int cnt = 0; cnt < 4 ; cnt ++ ){
		int nBufferLevel = max( S_LightWidthNorm, S_LightHeightNorm ) * DEPTH_RES;
			nBufferLevel = min(floor( log2( (float)nBufferLevel ) ), N_LEVELS-1);
		
		float2 ZPers;

		if(nBufferLevel<0)
			ZPers = FiveCase( 0, 1, 1, BLeft*DEPTH_RES, BLeft*DEPTH_RES+1, BBottom*DEPTH_RES+1, BBottom*DEPTH_RES );
		else
			ZPers = FiveCase( nBufferLevel, S_LightWidthNorm*DEPTH_RES, S_LightHeightNorm*DEPTH_RES, BLeft*DEPTH_RES, BRight*DEPTH_RES, BTop*DEPTH_RES, BBottom*DEPTH_RES );
		       
		Zmin = -( Zf * Zn ) / ( ( Zf - Zn ) * ( ZPers.x - Zf / ( Zf - Zn ) ) );
		Zmax = -( Zf * Zn ) / ( ( Zf - Zn ) * ( ZPers.y - Zf / ( Zf - Zn ) ) );

	    T_LightWidth  = max( ( w - Zmin ), 0 ) * ( LightSize ) / w,
		T_LightHeight = max( ( w - Zmin ), 0 ) * ( LightSize ) / w,
		S_LightWidth  = Zn * T_LightWidth  / Zmin,
		S_LightHeight = Zn * T_LightHeight / Zmin,
		S_LightWidthNorm  = S_LightWidth  / NpWidth,
		S_LightHeightNorm = S_LightHeight / NpHeight;
		BLeft   = saturate(max( x/w-S_LightWidthNorm,-1) * 0.5 + 0.5);
		BRight  = saturate(min( x/w+S_LightWidthNorm, 1) * 0.5 + 0.5);
		BBottom = saturate(1 -( min( y/w+S_LightHeightNorm, 1) * 0.5 + 0.5));
		BTop    = saturate(1 -( max( y/w-S_LightHeightNorm,-1) * 0.5 + 0.5));

		if((S_LightWidthNorm == 0)||(S_LightHeightNorm == 0))
		{
			return float4(1,1,1,1);
			//Zmin = Zf;
			//break;
		}
	}
	
	if( Zmin>w )
	{
		//return float4(1,1,1,1);
	}
	else if( Zmax<w)
	{
		return float4(0,0,0,1);
	}
  
	//-------------------------------------

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
		
		//if( VARx < 0.001 )
			//return VARx /= 2;
			//return float4(0,1,0,1);
			//Ex -= 0.005 ;
		
		float fPartLit = 0;
		
		fPartLit = VARx / ( VARx + ( pixel_unit_z - Ex ) * ( pixel_unit_z - Ex ) );
						
		sum_depth = min( pixel_unit_z, max( 0,( moments.x - fPartLit * pixel_unit_z )/( 1 - fPartLit )) );
		
		//for those outside shadow map
		//if( sum_depth == 0 )
			//return float4(1,1,1,1);
			//return float4(0,1,0,1);
		
		//if( sum_depth == pixel_unit_z )
		//	return float4(0,0,1,1);
			
		
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
	int   offset = max(5,( BRight - BLeft ) * DEPTH_RES / 2);
	//if( offset == 3 )
	//	return float4(1,0,0,1);
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
	
//---------------------------
	int   offset = max(1,( BRight - BLeft ) * DEPTH_RES / 2);
	int3  int_coord_rb = center_coord + int3(  offset, offset,0 );
	int3  int_coord_lt = center_coord + int3( -offset,-offset,0 );
	int3  int_coord_rt = center_coord + int3(  offset,-offset,0 );
	int3  int_coord_lb = center_coord + int3( -offset, offset,0 );

	float2  d_rb = SatVSM.Load( int_coord_rb );
	float2  d_lt = SatVSM.Load( int_coord_lt );
	float2  d_rt = SatVSM.Load( int_coord_rt );
	float2  d_lb = SatVSM.Load( int_coord_lb );
	float2 moments = (d_rb - d_rt - d_lb + d_lt);
	moments /= ((offset*2)*(offset*2));

	float  mu = moments.x;
	float  delta_sqr = moments.y - mu * mu;
	
	float fPartLit = 0;
	if( pixel_unit_z < mu + DepthBiasDefault && pixel_unit_z * pixel_unit_z < moments.y + DepthBiasDefault*0.1 )
		fPartLit = 1.0;
	else
		fPartLit = delta_sqr / ( delta_sqr + ( pixel_unit_z - mu ) * ( pixel_unit_z - mu ) );
	return float4( fPartLit,fPartLit,fPartLit,1);
	
}

float4 AccurateShadowFloatSAT(float4 vPos, float4 vDiffColor, bool limit_kernel = false, bool use_bias = true)
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
		int   offset = max(1,( BRight - BLeft ) * DEPTH_RES / 2);
		{
			int3  int_coord_rb = center_coord + int3(  offset, offset,0 );
			int3  int_coord_lt = center_coord + int3( -offset,-offset,0 );
			int3  int_coord_rt = center_coord + int3(  offset,-offset,0 );
			int3  int_coord_lb = center_coord + int3( -offset, offset,0 );

			float2  d_rb = SatVSM.Load( int_coord_rb );
			float2  d_lt = SatVSM.Load( int_coord_lt );
			float2  d_rt = SatVSM.Load( int_coord_rt ); 
			float2  d_lb = SatVSM.Load( int_coord_lb ); 
			moments0 = (d_rb - d_rt - d_lb + d_lt);
			moments0 /= ((offset*2)*(offset*2));
		}
		{
			center_coord = float3( floor( ShadowTexC * DEPTH_RES )  - float2(0.5,0.5) + float2(1,0), 0 );
			int3  int_coord_rb = center_coord + int3(  offset, offset,0 );
			int3  int_coord_lt = center_coord + int3( -offset,-offset,0 );
			int3  int_coord_rt = center_coord + int3(  offset,-offset,0 );
			int3  int_coord_lb = center_coord + int3( -offset, offset,0 );

			float2  d_rb = SatVSM.Load( int_coord_rb );
			float2  d_lt = SatVSM.Load( int_coord_lt );
			float2  d_rt = SatVSM.Load( int_coord_rt ); 
			float2  d_lb = SatVSM.Load( int_coord_lb ); 
			moments1 = (d_rb - d_rt - d_lb + d_lt);
			moments1 /= ((offset*2)*(offset*2));
		}
		moments0.x = dot( float2(uv_off.x,1-uv_off.x),float2(moments0.x,moments1.x) );
		moments0.y = dot( float2(uv_off.x,1-uv_off.x),float2(moments0.y,moments1.y) );

		{
			center_coord = float3( floor( ShadowTexC * DEPTH_RES )  - float2(0.5,0.5) + float2(0,1), 0 );
			int3  int_coord_rb = center_coord + int3(  offset, offset,0 );
			int3  int_coord_lt = center_coord + int3( -offset,-offset,0 );
			int3  int_coord_rt = center_coord + int3(  offset,-offset,0 );
			int3  int_coord_lb = center_coord + int3( -offset, offset,0 );

			float2  d_rb = SatVSM.Load( int_coord_rb );
			float2  d_lt = SatVSM.Load( int_coord_lt );
			float2  d_rt = SatVSM.Load( int_coord_rt ); 
			float2  d_lb = SatVSM.Load( int_coord_lb ); 
			moments2 = (d_rb - d_rt - d_lb + d_lt);			
			moments2 /= ((offset*2)*(offset*2));
		}
		{
			center_coord = float3( floor( ShadowTexC * DEPTH_RES )  - float2(0.5,0.5) + float2(1,1), 0 );
			int3  int_coord_rb = center_coord + int3(  offset, offset,0 );
			int3  int_coord_lt = center_coord + int3( -offset,-offset,0 );
			int3  int_coord_rt = center_coord + int3(  offset,-offset,0 );
			int3  int_coord_lb = center_coord + int3( -offset, offset,0 );

			float2  d_rb = SatVSM.Load( int_coord_rb );
			float2  d_lt = SatVSM.Load( int_coord_lt );
			float2  d_rt = SatVSM.Load( int_coord_rt ); 
			float2  d_lb = SatVSM.Load( int_coord_lb ); 
			moments3 = (d_rb - d_rt - d_lb + d_lt);
			moments3 /= ((offset*2)*(offset*2));
		}
		moments1.x = dot( float2(uv_off.x,1-uv_off.x),float2(moments2.x,moments3.x) );
		moments1.y = dot( float2(uv_off.x,1-uv_off.x),float2(moments2.y,moments3.y) );
		moments.x = dot( float2(uv_off.y,1-uv_off.y), float2(moments0.x,moments1.x) );
		moments.y = dot( float2(uv_off.y,1-uv_off.y), float2(moments0.y,moments1.y) );


		float  Ex = moments.x;
		float  VARx = moments.y - Ex * Ex;
		
		float fPartLit = 0;
		
		fPartLit = VARx / ( VARx + ( pixel_unit_z - Ex ) * ( pixel_unit_z - Ex ) );
		
		//dealing with pixel_unit_z is very close to Ex and at the same time VARx is very small
		if( fPartLit > 0.99 )
			fPartLit = 1;
				
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
	int   offset = max(3,( BRight - BLeft ) * DEPTH_RES / 2);
	{
		int3  int_coord_rb = center_coord + int3(  offset, offset,0 );
		int3  int_coord_lt = center_coord + int3( -offset,-offset,0 );
		int3  int_coord_rt = center_coord + int3(  offset,-offset,0 );
		int3  int_coord_lb = center_coord + int3( -offset, offset,0 );

		float2  d_rb = SatVSM.Load( int_coord_rb );
		float2  d_lt = SatVSM.Load( int_coord_lt );
		float2  d_rt = SatVSM.Load( int_coord_rt ); 
		float2  d_lb = SatVSM.Load( int_coord_lb ); 
		moments0 = (d_rb - d_rt - d_lb + d_lt);
		moments0 /= ((offset*2)*(offset*2));
	}
	{
		center_coord = float3( floor( ShadowTexC * DEPTH_RES )  - float2(0.5,0.5) + float2(1,0), 0 );
		int3  int_coord_rb = center_coord + int3(  offset, offset,0 );
		int3  int_coord_lt = center_coord + int3( -offset,-offset,0 );
		int3  int_coord_rt = center_coord + int3(  offset,-offset,0 );
		int3  int_coord_lb = center_coord + int3( -offset, offset,0 );

		float2  d_rb = SatVSM.Load( int_coord_rb );
		float2  d_lt = SatVSM.Load( int_coord_lt );
		float2  d_rt = SatVSM.Load( int_coord_rt ); 
		float2  d_lb = SatVSM.Load( int_coord_lb ); 
		moments1 = (d_rb - d_rt - d_lb + d_lt);
		moments1 /= ((offset*2)*(offset*2));
	}
	moments0.x = dot( float2(uv_off.x,1-uv_off.x),float2(moments0.x,moments1.x) );
	moments0.y = dot( float2(uv_off.x,1-uv_off.x),float2(moments0.y,moments1.y) );

	{
		center_coord = float3( floor( ShadowTexC * DEPTH_RES )  - float2(0.5,0.5) + float2(0,1), 0 );
		int3  int_coord_rb = center_coord + int3(  offset, offset,0 );
		int3  int_coord_lt = center_coord + int3( -offset,-offset,0 );
		int3  int_coord_rt = center_coord + int3(  offset,-offset,0 );
		int3  int_coord_lb = center_coord + int3( -offset, offset,0 );

		float2  d_rb = SatVSM.Load( int_coord_rb );
		float2  d_lt = SatVSM.Load( int_coord_lt );
		float2  d_rt = SatVSM.Load( int_coord_rt ); 
		float2  d_lb = SatVSM.Load( int_coord_lb ); 
		moments2 = (d_rb - d_rt - d_lb + d_lt);
		moments2 /= ((offset*2)*(offset*2));
	}
	{
		center_coord = float3( floor( ShadowTexC * DEPTH_RES )  - float2(0.5,0.5) + float2(1,1), 0 );
		int3  int_coord_rb = center_coord + int3(  offset, offset,0 );
		int3  int_coord_lt = center_coord + int3( -offset,-offset,0 );
		int3  int_coord_rt = center_coord + int3(  offset,-offset,0 );
		int3  int_coord_lb = center_coord + int3( -offset, offset,0 );

		float2  d_rb = SatVSM.Load( int_coord_rb );
		float2  d_lt = SatVSM.Load( int_coord_lt );
		float2  d_rt = SatVSM.Load( int_coord_rt ); 
		float2  d_lb = SatVSM.Load( int_coord_lb ); 
		moments3 = (d_rb - d_rt - d_lb + d_lt);
		moments3 /= ((offset*2)*(offset*2));
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
#ifndef USE_INT_SAT
#ifdef DISTRIBUTE_PRECISION
// Recombine distributed floats (inverse of the above)
float2 RecombineFP(float4 Value)
{
    float FactorInv = 1 / g_DistributeFPFactor;
    return (Value.zw * FactorInv + Value.xy);
}

float4 AccurateShadowDoubleSAT(float4 vPos, float4 vDiffColor, bool limit_kernel = false, bool use_bias = true)
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

	float sum_depth = 0;
	{
		float2 uv_off = frac( ShadowTexC * DEPTH_RES - float2(0.5,0.5) );

		float2 moments = {0.0,0.0};
		float2 moments0, moments1, moments2, moments3;
		int   offset = max(1,( BRight - BLeft ) * DEPTH_RES / 2);
		{
			int3  int_coord_rb = center_coord + int3(  offset, offset,0 );
			int3  int_coord_lt = center_coord + int3( -offset,-offset,0 );
			int3  int_coord_rt = center_coord + int3(  offset,-offset,0 );
			int3  int_coord_lb = center_coord + int3( -offset, offset,0 );

			float2  d_rb = RecombineFP( SatVSM.Load( int_coord_rb ) );
			float2  d_lt = RecombineFP( SatVSM.Load( int_coord_lt ) );
			float2  d_rt = RecombineFP( SatVSM.Load( int_coord_rt ) ); 
			float2  d_lb = RecombineFP( SatVSM.Load( int_coord_lb ) ); 
			moments0 = (d_rb - d_rt - d_lb + d_lt);
			moments0 /= ((offset*2)*(offset*2));
		}
		{
			center_coord = float3( floor( ShadowTexC * DEPTH_RES )  - float2(0.5,0.5) + float2(1,0), 0 );
			int3  int_coord_rb = center_coord + int3(  offset, offset,0 );
			int3  int_coord_lt = center_coord + int3( -offset,-offset,0 );
			int3  int_coord_rt = center_coord + int3(  offset,-offset,0 );
			int3  int_coord_lb = center_coord + int3( -offset, offset,0 );

			float2  d_rb = RecombineFP( SatVSM.Load( int_coord_rb ) );
			float2  d_lt = RecombineFP( SatVSM.Load( int_coord_lt ) );
			float2  d_rt = RecombineFP( SatVSM.Load( int_coord_rt ) );  
			float2  d_lb = RecombineFP( SatVSM.Load( int_coord_lb ) );  
			moments1 = (d_rb - d_rt - d_lb + d_lt);
			moments1 /= ((offset*2)*(offset*2));
		}
		moments0.x = dot( float2(uv_off.x,1-uv_off.x),float2(moments0.x,moments1.x) );
		moments0.y = dot( float2(uv_off.x,1-uv_off.x),float2(moments0.y,moments1.y) );

		{
			center_coord = float3( floor( ShadowTexC * DEPTH_RES )  - float2(0.5,0.5) + float2(0,1), 0 );
			int3  int_coord_rb = center_coord + int3(  offset, offset,0 );
			int3  int_coord_lt = center_coord + int3( -offset,-offset,0 );
			int3  int_coord_rt = center_coord + int3(  offset,-offset,0 );
			int3  int_coord_lb = center_coord + int3( -offset, offset,0 );

			float2  d_rb = RecombineFP( SatVSM.Load( int_coord_rb ) );
			float2  d_lt = RecombineFP( SatVSM.Load( int_coord_lt ) );
			float2  d_rt = RecombineFP( SatVSM.Load( int_coord_rt ) ); 
			float2  d_lb = RecombineFP( SatVSM.Load( int_coord_lb ) ); 
			moments2 = (d_rb - d_rt - d_lb + d_lt);			
			moments2 /= ((offset*2)*(offset*2));
		}
		{
			center_coord = float3( floor( ShadowTexC * DEPTH_RES )  - float2(0.5,0.5) + float2(1,1), 0 );
			int3  int_coord_rb = center_coord + int3(  offset, offset,0 );
			int3  int_coord_lt = center_coord + int3( -offset,-offset,0 );
			int3  int_coord_rt = center_coord + int3(  offset,-offset,0 );
			int3  int_coord_lb = center_coord + int3( -offset, offset,0 );

			float2  d_rb = RecombineFP( SatVSM.Load( int_coord_rb ) );
			float2  d_lt = RecombineFP( SatVSM.Load( int_coord_lt ) );
			float2  d_rt = RecombineFP( SatVSM.Load( int_coord_rt ) ); 
			float2  d_lb = RecombineFP( SatVSM.Load( int_coord_lb ) ); 
			moments3 = (d_rb - d_rt - d_lb + d_lt);
			moments3 /= ((offset*2)*(offset*2));
		}
		moments1.x = dot( float2(uv_off.x,1-uv_off.x),float2(moments2.x,moments3.x) );
		moments1.y = dot( float2(uv_off.x,1-uv_off.x),float2(moments2.y,moments3.y) );
		moments.x = dot( float2(uv_off.y,1-uv_off.y), float2(moments0.x,moments1.x) );
		moments.y = dot( float2(uv_off.y,1-uv_off.y), float2(moments0.y,moments1.y) );


		float  Ex = moments.x;
		float  VARx = moments.y - Ex * Ex;
		
		float fPartLit = 0;
		
		fPartLit = VARx / ( VARx + ( pixel_unit_z - Ex ) * ( pixel_unit_z - Ex ) );
		
		//dealing with pixel_unit_z is very close to Ex and at the same time VARx is very small
		//if( fPartLit > 0.99 )
		//	fPartLit = 1;
				
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
	int   offset = max(3,( BRight - BLeft ) * DEPTH_RES / 2);
	{
		int3  int_coord_rb = center_coord + int3(  offset, offset,0 );
		int3  int_coord_lt = center_coord + int3( -offset,-offset,0 );
		int3  int_coord_rt = center_coord + int3(  offset,-offset,0 );
		int3  int_coord_lb = center_coord + int3( -offset, offset,0 );

		float2  d_rb = RecombineFP( SatVSM.Load( int_coord_rb ) );
		float2  d_lt = RecombineFP( SatVSM.Load( int_coord_lt ) );
		float2  d_rt = RecombineFP( SatVSM.Load( int_coord_rt ) );  
		float2  d_lb = RecombineFP( SatVSM.Load( int_coord_lb ) );  
		moments0 = (d_rb - d_rt - d_lb + d_lt);
		moments0 /= ((offset*2)*(offset*2));
	}
	{
		center_coord = float3( floor( ShadowTexC * DEPTH_RES )  - float2(0.5,0.5) + float2(1,0), 0 );
		int3  int_coord_rb = center_coord + int3(  offset, offset,0 );
		int3  int_coord_lt = center_coord + int3( -offset,-offset,0 );
		int3  int_coord_rt = center_coord + int3(  offset,-offset,0 );
		int3  int_coord_lb = center_coord + int3( -offset, offset,0 );

		float2  d_rb = RecombineFP( SatVSM.Load( int_coord_rb ) );
		float2  d_lt = RecombineFP( SatVSM.Load( int_coord_lt ) );
		float2  d_rt = RecombineFP( SatVSM.Load( int_coord_rt ) ); 
		float2  d_lb = RecombineFP( SatVSM.Load( int_coord_lb ) ); 
		moments1 = (d_rb - d_rt - d_lb + d_lt);
		moments1 /= ((offset*2)*(offset*2));
	}
	moments0.x = dot( float2(uv_off.x,1-uv_off.x),float2(moments0.x,moments1.x) );
	moments0.y = dot( float2(uv_off.x,1-uv_off.x),float2(moments0.y,moments1.y) );

	{
		center_coord = float3( floor( ShadowTexC * DEPTH_RES )  - float2(0.5,0.5) + float2(0,1), 0 );
		int3  int_coord_rb = center_coord + int3(  offset, offset,0 );
		int3  int_coord_lt = center_coord + int3( -offset,-offset,0 );
		int3  int_coord_rt = center_coord + int3(  offset,-offset,0 );
		int3  int_coord_lb = center_coord + int3( -offset, offset,0 );

		float2  d_rb = RecombineFP( SatVSM.Load( int_coord_rb ) );
		float2  d_lt = RecombineFP( SatVSM.Load( int_coord_lt ) );
		float2  d_rt = RecombineFP( SatVSM.Load( int_coord_rt ) );  
		float2  d_lb = RecombineFP( SatVSM.Load( int_coord_lb ) );  
		moments2 = (d_rb - d_rt - d_lb + d_lt);
		moments2 /= ((offset*2)*(offset*2));
	}
	{
		center_coord = float3( floor( ShadowTexC * DEPTH_RES )  - float2(0.5,0.5) + float2(1,1), 0 );
		int3  int_coord_rb = center_coord + int3(  offset, offset,0 );
		int3  int_coord_lt = center_coord + int3( -offset,-offset,0 );
		int3  int_coord_rt = center_coord + int3(  offset,-offset,0 );
		int3  int_coord_lb = center_coord + int3( -offset, offset,0 );

		float2  d_rb = RecombineFP( SatVSM.Load( int_coord_rb ) );
		float2  d_lt = RecombineFP( SatVSM.Load( int_coord_lt ) );
		float2  d_rt = RecombineFP( SatVSM.Load( int_coord_rt ) );  
		float2  d_lb = RecombineFP( SatVSM.Load( int_coord_lb ) );  
		moments3 = (d_rb - d_rt - d_lb + d_lt);
		moments3 /= ((offset*2)*(offset*2));
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
#endif
#endif

float4 AccurateShadowIntSATNBuffer(float4 vPos, float4 vDiffColor, bool limit_kernel = false, bool use_bias = true)
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
			
			fPartLit = 0.90 * VARx / ( VARx + ( pixel_unit_z - Ex ) * ( pixel_unit_z - Ex ) );
							
			sum_depth =  max( 0,( moments.x - fPartLit * pixel_unit_z )/( 1 - fPartLit ));
		}
		
		//The bias is necessary due to the numerical precision. Sometimes when the occluder is very close to the receiver
		//although the occluder is slightly nearer to the light, the precision loss makes it equally distant to the light, or worse
		//makes it farther
		//A second thought, you may want to check the Cheveshev Inequality Proof for the root of this bias
		[branch]if( sum_depth >= pixel_unit_z + 0.1 )
			return float4(1,1,1,1);
			
		
	}	
	
	float ZminPers = sum_depth;
	Zmin = -( Zf * Zn ) / ( ( Zf - Zn ) * ( ZminPers - Zf / ( Zf - Zn ) ) );
	float estimated_zmin = Zmin;

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
	
	//------------------------------------- NBuffer Kernel Reduction
	
	for( int cnt = 0; cnt < 1 ; cnt ++ ){
		int nBufferLevel = max( S_LightWidthNorm, S_LightHeightNorm ) * DEPTH_RES;
			nBufferLevel = min(floor( log2( (float)nBufferLevel ) ), N_LEVELS-1);
		
		float2 ZPers;

		if(nBufferLevel<0)
			ZPers = FiveCase( 0, 1, 1, BLeft*DEPTH_RES, BLeft*DEPTH_RES+1, BBottom*DEPTH_RES+1, BBottom*DEPTH_RES );
		else
			ZPers = FiveCase( nBufferLevel, S_LightWidthNorm*DEPTH_RES, S_LightHeightNorm*DEPTH_RES, BLeft*DEPTH_RES, BRight*DEPTH_RES, BTop*DEPTH_RES, BBottom*DEPTH_RES );
		       
		Zmin = -( Zf * Zn ) / ( ( Zf - Zn ) * ( ZPers.x - Zf / ( Zf - Zn ) ) );
		Zmax = -( Zf * Zn ) / ( ( Zf - Zn ) * ( ZPers.y - Zf / ( Zf - Zn ) ) );
	}
	
	//if( estimated_zmin - Zmin > 0.3 )
	//	return float4( 0,1,0,1 );
	//-------------------------------------

	
//---------------------------
	
	float2 uv_off = frac( ShadowTexC * DEPTH_RES - float2(0.5,0.5) );
	center_coord = float3( floor( ShadowTexC * DEPTH_RES ) - float2(0.5,0.5), 0 );

	float2 moments = {0.0,0.0};
	float2 moments0, moments1, moments2, moments3;
	float  rescale = 1/g_NormalizedFloatToSATUINT;
	int   offset = max(5,( BRight - BLeft ) * DEPTH_RES / 2);
	//if( offset == 3 )
	//	return float4(1,0,0,1);
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
float4 AccurateShadowIntSATMultiSMP(float4 vPos, float4 vDiffColor, bool limit_kernel = false, bool use_bias = true)
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

		float  Ex = moments0.x;
		float  VARx = moments0.y - Ex * Ex;
				
		{
			float fPartLit = 0;
			//Why this bias?
			fPartLit = 0.94 * VARx / ( VARx + ( pixel_unit_z - Ex ) * ( pixel_unit_z - Ex ) );
							
			sum_depth =  max( 0,( moments0.x - fPartLit * pixel_unit_z )/( 1 - fPartLit ));
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
	
	
	float2 uv_off = frac( ShadowTexC * DEPTH_RES - float2(0.5,0.5) );
	center_coord = float3( floor( ShadowTexC * DEPTH_RES ) - float2(0.5,0.5), 0 );

//---------------------------
	int   offset = max(4,( BRight - BLeft ) * DEPTH_RES / 2);
	float fPartLit = 0;
	float  rescale = 1/g_NormalizedFloatToSATUINT;
	float2 moments = {0.0,0.0};
	float2 moments0, moments1, moments2, moments3;

	int3  int_coord_rb = center_coord + int3(  offset, offset,0 );
	int3  int_coord_lt = center_coord + int3( -offset,-offset,0 );
	int3  int_coord_rt = center_coord + int3(  offset,-offset,0 );
	int3  int_coord_lb = center_coord + int3( -offset, offset,0 );
	
	int   num_sub_light = 0;
	int   sub_light_size_texel = offset * 2 / 2;
	for( int u = int_coord_lt.x; u < int_coord_rb.x; u += sub_light_size_texel )
	{
		for( int v = int_coord_lt.y; v < int_coord_rb.y; v += sub_light_size_texel )
		{
			int    curr_r = min( u + sub_light_size_texel, int_coord_rb.x );
			int    curr_b = min( v + sub_light_size_texel, int_coord_rb.y );
			uint2  d_lt = SatVSM.Load( int3( u,v,0 ) );
			uint2  d_rt = SatVSM.Load( int3( curr_r, v,0 ) ); 
			uint2  d_lb = SatVSM.Load( int3( u, curr_b,0 ) ); 
			uint2  d_rb = SatVSM.Load( int3( curr_r, curr_b, 0 ) );	
			moments0 = (d_rb - d_rt - d_lb + d_lt);
			moments0 /= ( (curr_r - u) * (curr_b - v) );
			moments0 *= rescale;
			float  mu = moments0.x;
			float  delta_sqr = moments0.y - mu * mu;
			if( pixel_unit_z < mu + DepthBiasDefault && pixel_unit_z * pixel_unit_z < moments0.y + DepthBiasDefault*0.1 )
				fPartLit += 1.0;
			else
				fPartLit += delta_sqr / ( delta_sqr + ( pixel_unit_z - mu ) * ( pixel_unit_z - mu ) );
			++num_sub_light;
		}
	}
	fPartLit /= num_sub_light;

//---------------------------

	
	return float4( fPartLit,fPartLit,fPartLit,1);
	
}
float4 AccurateShadowIntSATMultiSMP3(float4 vPos, float4 vDiffColor, bool limit_kernel = false, bool use_bias = true)
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

		//---------------------------
		int   offset = max(4,( BRight - BLeft ) * DEPTH_RES / 2);
		float fPartLit = 0;
		float  rescale = 1/g_NormalizedFloatToSATUINT;
		float2 moments = {0.0,0.0};
		float2 moments0, moments1, moments2, moments3;

		int3  int_coord_rb = center_coord + int3(  offset, offset,0 );
		int3  int_coord_lt = center_coord + int3( -offset,-offset,0 );
		int3  int_coord_rt = center_coord + int3(  offset,-offset,0 );
		int3  int_coord_lb = center_coord + int3( -offset, offset,0 );
		
		int   num_sub_light = 0;
		int   sub_light_size_texel = offset * 2 / 1;
		for( int u = int_coord_lt.x; u < int_coord_rb.x; u += sub_light_size_texel )
		{
			for( int v = int_coord_lt.y; v < int_coord_rb.y; v += sub_light_size_texel )
			{
				int    curr_r = min( u + sub_light_size_texel + 4, int_coord_rb.x );
				int    curr_b = min( v + sub_light_size_texel + 4, int_coord_rb.y );
				uint2  d_lt = SatVSM.Load( int3( u,v,0 ) );
				uint2  d_rt = SatVSM.Load( int3( curr_r, v,0 ) ); 
				uint2  d_lb = SatVSM.Load( int3( u, curr_b,0 ) ); 
				uint2  d_rb = SatVSM.Load( int3( curr_r, curr_b, 0 ) );	
				moments0 = (d_rb - d_rt - d_lb + d_lt);
				moments0 /= ( (curr_r - u) * (curr_b - v) );
				moments0 *= rescale;
				float  Ex = moments0.x;
				float  VARx = moments0.y - Ex * Ex;
				{
					float fPartLit = 0;
					//Why this bias?
					fPartLit = 0.94 * VARx / ( VARx + ( pixel_unit_z - Ex ) * ( pixel_unit_z - Ex ) );
									
					sum_depth +=  max( 0,( moments0.x - fPartLit * pixel_unit_z )/( 1 - fPartLit ));
				}
				++ num_sub_light;
			}
		}
		sum_depth /= num_sub_light;

		//---------------------------
		
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
	
	
	float2 uv_off = frac( ShadowTexC * DEPTH_RES - float2(0.5,0.5) );
	center_coord = float3( floor( ShadowTexC * DEPTH_RES ) - float2(0.5,0.5), 0 );

//---------------------------
	int   offset = max(4,( BRight - BLeft ) * DEPTH_RES / 2);
	float fPartLit = 0;
	float  rescale = 1/g_NormalizedFloatToSATUINT;
	float2 moments = {0.0,0.0};
	float2 moments0, moments1, moments2, moments3;

	int3  int_coord_rb = center_coord + int3(  offset, offset,0 );
	int3  int_coord_lt = center_coord + int3( -offset,-offset,0 );
	int3  int_coord_rt = center_coord + int3(  offset,-offset,0 );
	int3  int_coord_lb = center_coord + int3( -offset, offset,0 );
	
	int   num_sub_light = 0;
	int   sub_light_size_texel = offset * 2 / 4;
	for( int u = int_coord_lt.x; u < int_coord_rb.x; u += sub_light_size_texel )
	{
		for( int v = int_coord_lt.y; v < int_coord_rb.y; v += sub_light_size_texel )
		{
			int    curr_r = min( u + sub_light_size_texel, int_coord_rb.x );
			int    curr_b = min( v + sub_light_size_texel, int_coord_rb.y );
			
			uint2  d_lt = SatVSM.Load( int3( u,v,0 ) ); d_lt += SatVSM.Load( int3( u - 1,v - 1,0 ) );d_lt += SatVSM.Load( int3( u,v - 1,0 ) );
				   d_lt += SatVSM.Load( int3( u + 1,v - 1,0 ) ); d_lt += SatVSM.Load( int3( u - 1,v,0 ) ); d_lt += SatVSM.Load( int3( u + 1,v,0 ) );
				   d_lt += SatVSM.Load( int3( u - 1,v + 1,0 ) ); d_lt += SatVSM.Load( int3( u ,v + 1,0 ) );d_lt += SatVSM.Load( int3( u + 1,v + 1,0 ) );
				   d_lt /= 9;
			
			uint2  d_rt = SatVSM.Load( int3( curr_r, v,0 ) ); d_rt += SatVSM.Load( int3( curr_r - 1, v - 1,0 ) );d_rt += SatVSM.Load( int3( curr_r, v-1,0 ) ); 
				   d_rt += SatVSM.Load( int3( curr_r + 1, v - 1,0 ) ); d_rt += SatVSM.Load( int3( curr_r - 1, v,0 ) );d_rt += SatVSM.Load( int3( curr_r + 1, v,0 ) );	
				   d_rt += SatVSM.Load( int3( curr_r - 1, v + 1,0 ) ); d_rt += SatVSM.Load( int3( curr_r, v + 1,0 ) );d_rt += SatVSM.Load( int3( curr_r+1, v+1,0 ) );
				   d_rt /= 9;
			
			uint2  d_lb = SatVSM.Load( int3( u, curr_b,0 ) ); d_lb += SatVSM.Load( int3( u - 1, curr_b -1,0 ) ); d_lb += SatVSM.Load( int3( u, curr_b -1,0 ) );
			       d_lb += SatVSM.Load( int3( u - 1, curr_b,0 ) );d_lb += SatVSM.Load( int3( u + 1, curr_b,0 ) );d_lb += SatVSM.Load( int3( u + 1, curr_b -1,0 ) );
			       d_lb += SatVSM.Load( int3( u - 1, curr_b +1,0 ) );d_lb += SatVSM.Load( int3( u, curr_b +1,0 ) );d_lb += SatVSM.Load( int3( u + 1, curr_b +1,0 ) );
			       d_lb /= 9;
			
			uint2  d_rb = SatVSM.Load( int3( curr_r, curr_b, 0 ) );	 d_rb += SatVSM.Load( int3( curr_r-1, curr_b-1, 0 ) );d_rb += SatVSM.Load( int3( curr_r, curr_b-1, 0 ) );		
			       d_rb += SatVSM.Load( int3( curr_r+1, curr_b-1, 0 ) );d_rb += SatVSM.Load( int3( curr_r-1, curr_b, 0 ) );	d_rb += SatVSM.Load( int3( curr_r+1, curr_b, 0 ) );	
			       d_rb += SatVSM.Load( int3( curr_r-1, curr_b+1, 0 ) );d_rb += SatVSM.Load( int3( curr_r, curr_b+1, 0 ) );	d_rb += SatVSM.Load( int3( curr_r+1, curr_b+1, 0 ) );	
			       d_rb /= 9;
			       	
			moments0 = (d_rb - d_rt - d_lb + d_lt);
			moments0 /= ( (curr_r - u) * (curr_b - v) );
			moments0 *= rescale;
			float  mu = moments0.x;
			float  delta_sqr = moments0.y - mu * mu;
			if( pixel_unit_z < mu + DepthBiasDefault && pixel_unit_z * pixel_unit_z < moments0.y + DepthBiasDefault*0.1 )
				fPartLit = 1.0;
			else
				fPartLit = delta_sqr / ( delta_sqr + ( pixel_unit_z - mu ) * ( pixel_unit_z - mu ) );
			++num_sub_light;
			if( num_sub_light == 4 )
			 	return float4( fPartLit,fPartLit,fPartLit,1);
		}
	}
	fPartLit /= num_sub_light;

//---------------------------

	
	return float4( fPartLit,fPartLit,fPartLit,1);
	
}
float4 AccurateShadowIntSATMultiSMP2(float4 vPos, float4 vDiffColor, bool limit_kernel = false, bool use_bias = true)
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

		//---------------------------
		int   offset = max(4,( BRight - BLeft ) * DEPTH_RES / 2);
		float fPartLit = 0;
		float  rescale = 1/g_NormalizedFloatToSATUINT;
		float2 moments = {0.0,0.0};
		float2 moments0, moments1, moments2, moments3;

		int3  int_coord_rb = center_coord + int3(  offset, offset,0 );
		int3  int_coord_lt = center_coord + int3( -offset,-offset,0 );
		int3  int_coord_rt = center_coord + int3(  offset,-offset,0 );
		int3  int_coord_lb = center_coord + int3( -offset, offset,0 );
		
		int   num_sub_light = 0;
		int   sub_light_size_texel = offset * 2 / 1;
		for( int u = int_coord_lt.x; u < int_coord_rb.x; u += sub_light_size_texel )
		{
			for( int v = int_coord_lt.y; v < int_coord_rb.y; v += sub_light_size_texel )
			{
				int    curr_r = min( u + sub_light_size_texel + 4, int_coord_rb.x );
				int    curr_b = min( v + sub_light_size_texel + 4, int_coord_rb.y );
				uint2  d_lt = SatVSM.Load( int3( u,v,0 ) );
				uint2  d_rt = SatVSM.Load( int3( curr_r, v,0 ) ); 
				uint2  d_lb = SatVSM.Load( int3( u, curr_b,0 ) ); 
				uint2  d_rb = SatVSM.Load( int3( curr_r, curr_b, 0 ) );	
				moments0 = (d_rb - d_rt - d_lb + d_lt);
				moments0 /= ( (curr_r - u) * (curr_b - v) );
				moments0 *= rescale;
				float  Ex = moments0.x;
				float  VARx = moments0.y - Ex * Ex;
				{
					float fPartLit = 0;
					//Why this bias?
					fPartLit = 0.94 * VARx / ( VARx + ( pixel_unit_z - Ex ) * ( pixel_unit_z - Ex ) );
									
					sum_depth +=  max( 0,( moments0.x - fPartLit * pixel_unit_z )/( 1 - fPartLit ));
				}
				++ num_sub_light;
			}
		}
		sum_depth /= num_sub_light;

		//---------------------------
		
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
	
	
	float2 uv_off = frac( ShadowTexC * DEPTH_RES - float2(0.5,0.5) );
	center_coord = float3( floor( ShadowTexC * DEPTH_RES ) - float2(0.5,0.5), 0 );

//---------------------------
	int   offset = max(8,( BRight - BLeft ) * DEPTH_RES / 2);
	float fPartLit = 0;
	float  rescale = 1/g_NormalizedFloatToSATUINT;
	float2 moments = {0.0,0.0};
	float2 moments0, moments1, moments2, moments3;

	int3  int_coord_rb = center_coord + int3(  offset, offset,0 );
	int3  int_coord_lt = center_coord + int3( -offset,-offset,0 );
	int3  int_coord_rt = center_coord + int3(  offset,-offset,0 );
	int3  int_coord_lb = center_coord + int3( -offset, offset,0 );
	
	int   num_sub_light = 0;
	int   sub_light_size_texel = offset * 2 / 4;
	for( int u = int_coord_lt.x; u < int_coord_rb.x; u += sub_light_size_texel )
	{
		for( int v = int_coord_lt.y; v < int_coord_rb.y; v += sub_light_size_texel )
		{
			int    curr_r = min( u + sub_light_size_texel, int_coord_rb.x );
			int    curr_b = min( v + sub_light_size_texel, int_coord_rb.y );
			
			uint2  d_lt = SatVSM.Load( int3( u,v,0 ) );
			uint2  d_rt = SatVSM.Load( int3( curr_r, v,0 ) );
			uint2  d_lb = SatVSM.Load( int3( u, curr_b,0 ) );
			uint2  d_rb = SatVSM.Load( int3( curr_r, curr_b, 0 ) );
			       	
			moments0 = (d_rb - d_rt - d_lb + d_lt);
			moments0 /= ( (curr_r - u) * (curr_b - v) );
			moments0 *= rescale;
			float  mu = moments0.x;
			float  delta_sqr = moments0.y - mu * mu;
			if( pixel_unit_z < mu + DepthBiasDefault && pixel_unit_z * pixel_unit_z < moments0.y + DepthBiasDefault*0.1 )
			{
				fPartLit += 1.0;
			}
			else
				fPartLit += delta_sqr / ( delta_sqr + ( pixel_unit_z - mu ) * ( pixel_unit_z - mu ) );
			++num_sub_light;
			//if( num_sub_light == 4 )
			// 	return float4( fPartLit,fPartLit,fPartLit,1);
		}
	}
	fPartLit /= num_sub_light;

//---------------------------

	
	return float4( fPartLit,fPartLit,fPartLit,1);
	
}

float4 AccurateShadowIntSATMultiSMP4(float4 vPos, float4 vDiffColor, bool limit_kernel = false, bool use_bias = true)
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

		//---------------------------
		int   offset = max(4,( BRight - BLeft ) * DEPTH_RES / 2);
		float fPartLit = 0;
		float  rescale = 1/g_NormalizedFloatToSATUINT;
		float2 moments = {0.0,0.0};
		float2 moments0, moments1, moments2, moments3;

		int3  int_coord_rb = center_coord + int3(  offset, offset,0 );
		int3  int_coord_lt = center_coord + int3( -offset,-offset,0 );
		int3  int_coord_rt = center_coord + int3(  offset,-offset,0 );
		int3  int_coord_lb = center_coord + int3( -offset, offset,0 );
		
		int   num_sub_light = 0;
		int   sub_light_size_texel = offset * 2 / 1;
		for( int u = int_coord_lt.x; u < int_coord_rb.x; u += sub_light_size_texel )
		{
			for( int v = int_coord_lt.y; v < int_coord_rb.y; v += sub_light_size_texel )
			{
				int    curr_r = min( u + sub_light_size_texel + 4, int_coord_rb.x );
				int    curr_b = min( v + sub_light_size_texel + 4, int_coord_rb.y );
				uint2  d_lt = SatVSM.Load( int3( u,v,0 ) );
				uint2  d_rt = SatVSM.Load( int3( curr_r, v,0 ) ); 
				uint2  d_lb = SatVSM.Load( int3( u, curr_b,0 ) ); 
				uint2  d_rb = SatVSM.Load( int3( curr_r, curr_b, 0 ) );	
				moments0 = (d_rb - d_rt - d_lb + d_lt);
				moments0 /= ( (curr_r - u) * (curr_b - v) );
				moments0 *= rescale;
				float  Ex = moments0.x;
				float  VARx = moments0.y - Ex * Ex;
				{
					float fPartLit = 0;
					//Why this bias?
					fPartLit = 0.94 * VARx / ( VARx + ( pixel_unit_z - Ex ) * ( pixel_unit_z - Ex ) );
									
					sum_depth +=  max( 0,( moments0.x - fPartLit * pixel_unit_z )/( 1 - fPartLit ));
				}
				++ num_sub_light;
			}
		}
		sum_depth /= num_sub_light;

		//---------------------------
		
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
	
	
	float2 uv_off = frac( ShadowTexC * DEPTH_RES - float2(0.5,0.5) );
	center_coord = float3( floor( ShadowTexC * DEPTH_RES ) - float2(0.5,0.5), 0 );

//---------------------------
	float fPartLit = 0;
	float  rescale = 1/g_NormalizedFloatToSATUINT;
	float2 moments = {0.0,0.0};
	float2 moments0, moments1, moments2, moments3;

	int   num_sub_light = 4;
	float   sub_light_size_01 = ( BRight - BLeft ) / 4;
	
	float2 curr_lt = float2( BLeft, BTop );
	for( int i = 0; i<num_sub_light; ++i )
	{
		for( int j = 0; j<num_sub_light; ++j )
		{
						
			uint2  d_lt = SatVSM.SampleLevel( PointSampler,curr_lt, 0 );
			uint2  d_rt = SatVSM.SampleLevel( PointSampler,curr_lt + float2(sub_light_size_01,0), 0 );
			uint2  d_lb = SatVSM.SampleLevel( PointSampler,curr_lt + float2(0,sub_light_size_01), 0 );
			uint2  d_rb = SatVSM.SampleLevel( PointSampler,curr_lt + float2(sub_light_size_01,sub_light_size_01), 0 );
			       	
			moments0 = (d_rb - d_rt - d_lb + d_lt);
			moments0 /= ( (curr_r - u) * (curr_b - v) );
			moments0 *= rescale;
			float  mu = moments0.x;
			float  delta_sqr = moments0.y - mu * mu;
			if( pixel_unit_z < mu + DepthBiasDefault && pixel_unit_z * pixel_unit_z < moments0.y + DepthBiasDefault*0.1 )
			{
				fPartLit += 1.0;
			}
			else
				fPartLit += delta_sqr / ( delta_sqr + ( pixel_unit_z - mu ) * ( pixel_unit_z - mu ) );
			++num_sub_light;
			//if( num_sub_light == 4 )
			// 	return float4( fPartLit,fPartLit,fPartLit,1);
		}
	}
	fPartLit /= num_sub_light;

//---------------------------

	
	return float4( fPartLit,fPartLit,fPartLit,1);
	
}


*/