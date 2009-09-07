//----------------------------------------------------------------------------------
// File:   S3UTMesh.h
// Author: Baoguang Yang
// 
// Copyright (c) 2009 S3Graphics Corporation. All rights reserved.
// 
// Contains code manipulating various kinds of meshes, including .x, .sdkmesh
//
//----------------------------------------------------------------------------------

#pragma once
#ifndef S3UTMESH_H
#define S3UTMESH_H

#define MAX_STATIC_OBJ 100

#include <sdkmesh_old.h>
#include "AnimationMesh.h"

class S3UTMesh : public CDXUTMesh10
{
public:
    S3UTMesh();
	void set_parameters( bool render_warrior, 
						 bool render_static_obj, 
						 bool render_windmill, 
						 bool render_floor = true )
	{
		m_bRenderWarrior = render_warrior;
		m_bRenderStaticObjs = render_static_obj;
		m_bRenderWindmill = render_windmill;
		m_bRenderFloor = render_floor;
	}
	void render_fence( bool swh )
	{
		m_bRenderFence = swh;
	}
	void render_fan( bool swh )
	{
		m_bRenderFan = swh;
	}
	void set_biases( float *biases, int n )
	{
		for( int i = 0; i < n; ++i )
		{
			m_fBiases[ i ] = biases[i];
		}
		m_nBiasCounter = 0;
		m_pWarriorMesh->set_biases( biases, n );
	}
	void increase_bias_counter( int cnt )
	{
		m_nBiasCounter += cnt;
		m_pWarriorMesh->increase_bias_counter( cnt );
	}

    HRESULT Create(ID3D10Device *pDev10, LPCTSTR szFileName, D3D10_INPUT_ELEMENT_DESC* playout, UINT cElements, bool bOptimize=true);
	
	//main interface of the mesh class in my design
	HRESULT Create( 		
							WCHAR *pWarriorMeshName,
							WCHAR *pWarriorAnimName,
							LPCTSTR szWindmillBaseName,
							LPCTSTR szWindmillFanName,
							LPCTSTR szPlaneMeshName,
							LPCTSTR *szStaticObjFileNames,
							UINT num_static_meshes,
							D3D10_INPUT_ELEMENT_DESC *pSuitLayout,
							D3D10_INPUT_ELEMENT_DESC *pBodyLayout,
							D3D10_INPUT_ELEMENT_DESC* pStaticMeshLayout, 
							ID3D10Device *pDev10 
	);


    // Methods to load and render with normal maps, functions of based mesh are hidden for objects of S3UTMesh class.
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

private:
    D3DXVECTOR3 m_vBox[2]; ///< bounding box for the mesh

    // Vars to to hold loaded normal maps if used.
    ID3D10Texture2D **m_ppNormalTextures;
    ID3D10ShaderResourceView **m_ppNormalSRVs;

	AnimationMesh       *m_pWarriorMesh;
	bool m_bRenderWarrior;
	bool m_bRenderStaticObjs;
	bool m_bRenderWindmill;//including the fan and the fence
	bool m_bRenderFan;//take effect only when m_bRenderWindmill is true
	bool m_bRenderFence;//take effect only when m_bRenderWindmill is true
	bool m_bRenderFloor;
	CDXUTMesh10			m_StaticMeshes[MAX_STATIC_OBJ];
	UINT				m_nNumStaticMesh;
	CDXUTSDKMesh		m_WindmillBaseMesh;
	CDXUTSDKMesh		m_WindmillFanMesh;
	float m_fBiases[MAX_STATIC_OBJ]; //POTENTIALLY DANGEROUS
	int   m_nBiasCounter;
};

#endif // S3UTMESH_H
