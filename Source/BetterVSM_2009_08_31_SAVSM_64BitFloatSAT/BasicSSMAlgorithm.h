#pragma once
#include <d3d10.h>
#include "InputBuffer.h"

class BasicSSMAlgorithm
{
public:
	Parameters m_par;
	ID3D10RenderTargetView *m_pRTV;
	ID3D10ShaderResourceView *m_pPreResult;
	D3DXVECTOR4 m_vec4LightColor;
	InputBuffer *m_pInputBuffer;
	void set_parameters( Parameters par, 
						 ID3D10RenderTargetView *pRTV, 
						 ID3D10ShaderResourceView *pPreResult,
						 D3DXVECTOR4 *p_light_color )
	{
		m_par.fLightZn					=	par.fLightZn;
		m_pRTV = pRTV;
		m_pPreResult = pPreResult;

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
};