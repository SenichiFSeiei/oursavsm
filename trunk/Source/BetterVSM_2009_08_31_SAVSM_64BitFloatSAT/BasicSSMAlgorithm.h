#pragma once
#include <d3d10.h>
#include "InputBuffer.h"

class BasicSSMAlgorithm
{
public:
	Parameters m_par;
	ID3D10RenderTargetView *m_pRTV;
	ID3D10ShaderResourceView *m_pSRV;
	D3DXVECTOR4 m_vec4LightColor;
	InputBuffer *m_pInputBuffer;
	void set_parameters( Parameters par, 
						 ID3D10RenderTargetView *pRTV, 
						 D3DXVECTOR4 *p_light_color,
						 ID3D10ShaderResourceView *pSRV = NULL)
	{
		m_par.fLightZn					=	par.fLightZn;
		m_pRTV = pRTV;
		m_pSRV = pSRV;

		if( p_light_color != NULL )
		{
			m_vec4LightColor = *p_light_color;
		}
		else
		{
			m_vec4LightColor = D3DXVECTOR4(1,0,0,1);
		}

	}
	void set_input_buffer( InputBuffer *par_pInputBuffer )
	{
		m_pInputBuffer = par_pInputBuffer;
	}
	void DumpMatrices( char *FileName,D3DXMATRIX &mat );
	void DumpFloat( char *FileName, float val );
	void DumpVec3( char *FileName, D3DXVECTOR3 vec );

};

//#define B_DO_DUMP
void BasicSSMAlgorithm::DumpMatrices( char *FileName,D3DXMATRIX &mat )
{
#ifdef B_DO_DUMP
	FILE *fp= fopen( FileName,"w" );
	fprintf( fp, "float4x4(" );
	for( int i = 0; i < 4; ++i )
	{
		fprintf( fp, "float4(" );
		for( int j = 0; j < 4; ++j )
		{
			fprintf( fp, "%f,", mat(i,j) ); 
		}
		fprintf( fp, "),\n" );
	}
	fprintf( fp, ");\n" );
	fclose( fp );
#endif
}

void BasicSSMAlgorithm::DumpFloat( char *FileName, float val )
{
#ifdef B_DO_DUMP
	FILE *fp = fopen( FileName,"w" );
	fprintf( fp, "%f", val );
	fclose( fp );
#endif
}

void BasicSSMAlgorithm::DumpVec3( char *FileName, D3DXVECTOR3 vec )
{
#ifdef B_DO_DUMP
	FILE *fp = fopen( FileName,"w" );
	fprintf( fp, "float4(%f,%f,%f)", vec.x,vec.y,vec.z );
	fclose( fp );
#endif
}
