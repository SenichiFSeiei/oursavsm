//----------------------------------------------------------------------------------
// File:   NVUTMesh.h
// Email:  sdkfeedback@nvidia.com
// 
// Copyright (c) 2007 NVIDIA Corporation. All rights reserved.
//
// TO  THE MAXIMUM  EXTENT PERMITTED  BY APPLICABLE  LAW, THIS SOFTWARE  IS PROVIDED
// *AS IS*  AND NVIDIA AND  ITS SUPPLIERS DISCLAIM  ALL WARRANTIES,  EITHER  EXPRESS
// OR IMPLIED, INCLUDING, BUT NOT LIMITED  TO, IMPLIED WARRANTIES OF MERCHANTABILITY
// AND FITNESS FOR A PARTICULAR PURPOSE.  IN NO EVENT SHALL  NVIDIA OR ITS SUPPLIERS
// BE  LIABLE  FOR  ANY  SPECIAL,  INCIDENTAL,  INDIRECT,  OR  CONSEQUENTIAL DAMAGES
// WHATSOEVER (INCLUDING, WITHOUT LIMITATION,  DAMAGES FOR LOSS OF BUSINESS PROFITS,
// BUSINESS INTERRUPTION, LOSS OF BUSINESS INFORMATION, OR ANY OTHER PECUNIARY LOSS)
// ARISING OUT OF THE  USE OF OR INABILITY  TO USE THIS SOFTWARE, EVEN IF NVIDIA HAS
// BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.
//
//
//----------------------------------------------------------------------------------

#pragma once
#ifndef NVUTMESH_H
#define NVUTMESH_H

#include <sdkmesh_old.h>
#include "AnimationMesh.h"

class NVUTMesh : public CDXUTMesh10
{
public:
    NVUTMesh();
	void set_parameters( bool render_animation_mesh, bool render_scene_mesh, bool render_fan_mesh, bool render_floor = true )
	{
		m_bRenderAnimationMesh = render_animation_mesh;
		m_bRenderSceneMesh = render_scene_mesh;
		m_bRenderFanMesh = render_fan_mesh;
		m_bRenderFloor = render_floor;
	}
	void set_biases( float *biases, int n )
	{
		for( int i = 0; i < n; ++i )
		{
			m_fBiases[ i ] = biases[i];
		}
		m_nBiasCounter = 0;
		m_pAMesh->set_biases( biases, n );
	}
	void increase_bias_counter( int cnt )
	{
		m_nBiasCounter += cnt;
		m_pAMesh->increase_bias_counter( cnt );
	}

    // method first loads .x file using standard CDXUTMesh10::Create() method, then
    // computes bounding box for the mesh and stores it into m_vBox
    HRESULT Create(ID3D10Device *pDev10, LPCTSTR szFileName, D3D10_INPUT_ELEMENT_DESC* playout, UINT cElements, bool bOptimize=true);
	HRESULT Create( WCHAR *pMeshName,
					WCHAR *pAnimName,
					ID3D10Device *pDev10, 
					D3D10_INPUT_ELEMENT_DESC *pSuitLayout,
					D3D10_INPUT_ELEMENT_DESC *pBodyLayout,
					LPCTSTR szFileName,
					LPCTSTR *szSceneFileNames,
					UINT num_scene_meshes,
					D3D10_INPUT_ELEMENT_DESC* pLayout, 
					UINT nSceneElements, 
					LPCTSTR szFanFileNames0,
					LPCTSTR szFanFileNames1,
					bool bOptimize);


    // Methods to load and render with normal maps, functions of based mesh are hidden for objects of NVUTMesh class.
    HRESULT CreateWithNormalMaps(ID3D10Device *pDev10, LPCTSTR szFileName, D3D10_INPUT_ELEMENT_DESC* playout, UINT cElements, bool bOptimize=true, const char*szNormalSuffix="_nm");
    void Render( ID3D10Device *pDev );
    void Render( ID3D10Device *pDev, 
                 ID3D10EffectTechnique *pTechnique, 
                 ID3D10EffectShaderResourceVariable* ptxDiffuse = NULL,
                 ID3D10EffectVectorVariable* pvDiffuse = NULL, 
                 ID3D10EffectVectorVariable* pvSpecular = NULL, 
                 DWORD dwSubset = (DWORD)-1,
                 ID3D10EffectShaderResourceVariable* ptxNormal = NULL);

	void Render(UINT max_bone_matrices,
				float scale,
				ID3D10Effect*	pEffect,
				ID3D10EffectTechnique*	pSuitTechnique,	
				ID3D10EffectTechnique*	pBodyTechnique,	
				ID3D10EffectTechnique*	pTechnique,	
				ID3D10EffectTechnique*	pSceneTechnique,	
				D3DXMATRIX* p_view_proj_matrix,
				ID3D10Device* pDev, 
				double fTime, float fElapsedTime, void* pUserContext,bool use_bias = false);


    void RenderInstanced( ID3D10Device *pDev, 
                          ID3D10EffectTechnique *pTechnique, 
                          UINT uiInstanceCount,
                          ID3D10EffectShaderResourceVariable* ptxDiffuse = NULL,
                          ID3D10EffectVectorVariable* pvDiffuse = NULL, 
                          ID3D10EffectVectorVariable* pvSpecular = NULL );
    void Destroy();


    D3DXVECTOR3 m_vBox[2]; ///< bounding box for the mesh

    // Vars to to hold loaded normal maps if used.
    ID3D10Texture2D **m_ppNormalTextures;
    ID3D10ShaderResourceView **m_ppNormalSRVs;

	AnimationMesh       *m_pAMesh;
	bool m_bRenderAnimationMesh;
	bool m_bRenderSceneMesh;
	bool m_bRenderFanMesh;
	bool m_bRenderFloor;
	CDXUTMesh10			m_SceneMeshes[100];
	UINT				m_nSceneMeshes;
	CDXUTSDKMesh		m_FanMeshes0;
	CDXUTSDKMesh		m_FanMeshes1;
	float m_fBiases[100]; 
	int   m_nBiasCounter;
};

#endif // NVUTMESH_H
