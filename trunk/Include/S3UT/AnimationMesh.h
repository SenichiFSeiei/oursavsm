#pragma once

#include "DXUT.h"
#include "DXUTgui.h"
#include "DXUTcamera.h"
#include "DXUTsettingsdlg.h"
#include "SDKmisc.h"
#include "SDKMesh.h"

//An animation file should define the macro below
#define MAX_TIME_STEPS 3    // This must stay in sync with MAX_TIME_STEPS in the FX file
#define MID_TIME_STEP 1
//#define MAX_BONE_MATRICES 100  // This must stay in sync with MAX_BONE_MATRICES in the FX file

class AnimationMesh
{
public:
	int m_nBiasCounter;
	float m_fBiases[100];
	UINT m_NumLinkedMeshes;
	ID3D10InputLayout*      m_pSuitVertexLayout;
	ID3D10InputLayout*      m_pBodyVertexLayout;

	CDXUTSDKMesh*           m_pLinkedMeshes;
	CDXUTSDKMesh            m_AnimMesh;

	// Effect Variables
	ID3D10EffectMatrixVariable* m_pmBlurViewProj;
	ID3D10EffectMatrixVariable* m_pmBlurWorld;
	ID3D10EffectMatrixVariable* m_pmBoneWorld;
	ID3D10EffectShaderResourceVariable* m_ptxDiffuse;

	AnimationMesh(){}
	void set_biases( float *biases, int n )
	{
		for( int i = 0; i < n; ++i )
		{
			m_fBiases[ i ] = biases[i];
		}
		m_nBiasCounter = 0;
	}
	void increase_bias_counter( int cnt )
	{
		m_nBiasCounter += cnt;
	}

	HRESULT OnD3D10CreateDevice( WCHAR *pMeshName,
								 WCHAR *pAnimName,
								 ID3D10Device* pd3dDevice,
								 D3D10_INPUT_ELEMENT_DESC *pSuitLayout,
								 D3D10_INPUT_ELEMENT_DESC *pBodyLayout
								);

	void RenderLinkedMesh( ID3D10Device* pd3dDevice, CDXUTSDKMesh* pLinkedMesh, CDXUTSDKMesh* pAnimMesh, 
						   UINT iInfluence, double fTime, ID3D10EffectTechnique*	pTechnique);

	void RenderSkinnedMesh( UINT max_bone_matrices,ID3D10Device* pd3dDevice, CDXUTSDKMesh* pAnimMesh, double fTime, ID3D10EffectTechnique*	pTechnique );

	void OnD3D10FrameRender(	UINT max_bone_matrices,
								float scale,
								ID3D10Effect*	pEffect,
								ID3D10EffectTechnique*	pSuitTechnique,	
								ID3D10EffectTechnique*	pBodyTechnique,	
								D3DXMATRIX* p_view_proj_matrix,
								ID3D10Device* pd3dDevice, 
								double fTime, float fElapsedTime, void* pUserContext,bool use_bias );

	void OnD3D10DestroyDevice( void* pUserContext );

};
