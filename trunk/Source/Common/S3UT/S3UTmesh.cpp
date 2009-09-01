//----------------------------------------------------------------------------------
// File:   S3UTMesh.cpp
// Author: Baoguang Yang
// 
// Copyright (c) 2009 S3Graphics Corporation. All rights reserved.
// 
// Contains code manipulating various kinds of meshes, including .x, .sdkmesh
//
//----------------------------------------------------------------------------------

#include <dxut.h>
#include "SDKmisc.h"
#include <S3UTmesh.h>
#pragma warning (disable:4995)
#include <string>
#include <assert.h>

S3UTMesh::S3UTMesh()
{
    CDXUTMesh10();

    m_ppNormalTextures = NULL;
    m_ppNormalSRVs = NULL;

	m_pWarriorMesh = NULL;
	m_bRenderWarrior = true;
	m_bRenderStaticObjs = true;
	m_bRenderFan = true;
	m_bRenderFloor = true;
	m_bRenderFence = true;
	m_bRenderWindmill = true;

}

HRESULT S3UTMesh::Create( 
							WCHAR *pWarriorMeshName,
							WCHAR *pWarriorAnimName,
							LPCTSTR szWindmillBaseName,
							LPCTSTR szWindmillFanName,
							LPCTSTR szPlaneMeshName,
							LPCTSTR *szStaticObjFileNames,//Notice: this is a list of static objects, not a single object
							UINT num_static_meshes,
							D3D10_INPUT_ELEMENT_DESC *pSuitLayout,
							D3D10_INPUT_ELEMENT_DESC *pBodyLayout,
							D3D10_INPUT_ELEMENT_DESC* pStaticMeshLayout, 
							ID3D10Device *pDev10 
			   )
{
    HRESULT hr;

	UINT nSceneElements = 3;
	bool bOptimize = true;

	m_nNumStaticMesh = num_static_meshes;

    V_RETURN(CDXUTMesh10::Create(pDev10, szPlaneMeshName, pStaticMeshLayout, nSceneElements, bOptimize));

	for( UINT idx = 0; idx < m_nNumStaticMesh; ++idx )
	{
		m_StaticMeshes[idx].Create(pDev10, szStaticObjFileNames[idx], pStaticMeshLayout, nSceneElements, bOptimize);
	}

	m_WindmillBaseMesh.Create(pDev10, szWindmillBaseName);
	m_WindmillFanMesh.Create(pDev10, szWindmillFanName);
	
	m_pWarriorMesh = new AnimationMesh();
	m_pWarriorMesh->OnD3D10CreateDevice(	pWarriorMeshName,
											pWarriorAnimName,
											pDev10,
											pSuitLayout,
											pBodyLayout );


    return S_OK;
}


//Used when not drawing animated meshes
HRESULT S3UTMesh::Create( ID3D10Device *pDev10, LPCTSTR szFileName, D3D10_INPUT_ELEMENT_DESC* pLayout, UINT nElements, bool bOptimize)
{
    HRESULT hr;
    V_RETURN(CDXUTMesh10::Create(pDev10, szFileName, pLayout, nElements, bOptimize));

    m_vBox[0] = D3DXVECTOR3(-1, -1, -1);
    m_vBox[1] = D3DXVECTOR3( 1,  1,  1);

    // find bounding box of the mesh we have just loaded
    UINT iPosSemantics = 0;
    for ( ; ; )
    {
        if ( (strcmp(pLayout[iPosSemantics].SemanticName, "POSITION") == 0) || strcmp(pLayout[iPosSemantics].SemanticName, "SV_Position" ) )
        {
            if (pLayout[iPosSemantics].Format != DXGI_FORMAT_R32G32B32_FLOAT)
            {
                MessageBox(NULL, L"Vertices are not in DXGI_FORMAT_R32G32B32_FLOAT format - can not compute bounding box", L"Warning", MB_OK);
                return S_OK;
            }
            break;
        }
        if (++iPosSemantics == nElements)
        {
            MessageBox(NULL, L"\"POSITION\" semantics was not found - can not compute boundingbox.", L"Warning", MB_OK);
            return S_OK;
        }
    }

    ID3DX10MeshBuffer *pVBuffer = NULL;
    V_RETURN(m_pMesh10->GetVertexBuffer(0, &pVBuffer));
    char *pVerts = NULL;
    SIZE_T iSize = 0xffffffff;
    pVBuffer->Map((void **)&pVerts, &iSize);
    m_vBox[0] = D3DXVECTOR3( 1E38f,  1E38f,  1E38f);
    m_vBox[1] = D3DXVECTOR3(-1E38f, -1E38f, -1E38f);
    for (UINT iv = 0; iv < m_dwNumVerts; ++iv)
    {
        D3DXVECTOR3 v = *(D3DVECTOR *)((char *)pVerts + m_uStride * iv);
        m_vBox[0] = D3DXVECTOR3(min(m_vBox[0].x, v.x), min(m_vBox[0].y, v.y), min(m_vBox[0].z, v.z));
        m_vBox[1] = D3DXVECTOR3(max(m_vBox[1].x, v.x), max(m_vBox[1].y, v.y), max(m_vBox[1].z, v.z));
    }
    pVBuffer->Unmap();
    pVBuffer->Release();

    return S_OK;
}

/*
    Do normal mesh loading(our mesh load uses base class first and then calcs bbox), 
    but afterwards load normals based on the file pattern suffix provided.

    With remove all texture filename extensions, add suffix and reattach extensions.  then search for that file.  
    Create Resources and SRVs for each, and add to our list.
*/
HRESULT S3UTMesh::CreateWithNormalMaps(ID3D10Device *pDev10, LPCTSTR szFileName, D3D10_INPUT_ELEMENT_DESC* pLayout, UINT cElements, bool bOptimize, const char*szNormalSuffix)
{
    HRESULT hr;
    V_RETURN(Create(pDev10, szFileName, pLayout, cElements, bOptimize));

    // Set strPath to the path of the mesh file, assuming all normal maps are relative to mesh folder.
    WCHAR        strPath[MAX_PATH];
    DXUTFindDXSDKMediaFileCch( strPath, sizeof(strPath) / sizeof(WCHAR), szFileName );
    WCHAR *pLastBSlash = wcsrchr( strPath, L'\\' );
    if( pLastBSlash )
        *(pLastBSlash + 1) = L'\0';
    else
        *strPath = L'\0';

    // 
    m_ppNormalTextures = new ID3D10Texture2D *[m_dwNumAttr]; 
    ZeroMemory(m_ppNormalTextures,m_dwNumAttr*sizeof(ID3D10Texture2D *));

    m_ppNormalSRVs = new ID3D10ShaderResourceView *[m_dwNumAttr];
    ZeroMemory(m_ppNormalSRVs,m_dwNumAttr*sizeof(ID3D10ShaderResourceView *));

    // Only parse for active attribues
    for(unsigned int iAttrib=0;iAttrib<m_dwNumAttr;iAttrib++)
    {
        if(m_pMats[m_pAttr[iAttrib].AttribId].pTextureFilename)
        {
            ID3D10Resource *pRes = NULL;
            std::string filename = m_pMats[m_pAttr[iAttrib].AttribId].pTextureFilename;

            // Now construct a normals filename implicitly... ugh.
            std::string::size_type pos;
            pos = filename.find_last_of('.');
            if(pos == -1) continue;
            filename.insert(pos,szNormalSuffix);

            WCHAR strTexture[MAX_PATH];
            WCHAR strName[MAX_PATH];
            MultiByteToWideChar( CP_ACP, 0, filename.c_str(), -1, strName, MAX_PATH );
            StringCchCopyW( strTexture, MAX_PATH, strPath );
            StringCchCatW( strTexture, MAX_PATH, strName );

            hr = D3DX10CreateTextureFromFile( pDev10, strTexture, NULL, NULL, &pRes, NULL );
            if( SUCCEEDED(hr) && pRes )
            {
                pRes->QueryInterface( __uuidof( ID3D10Texture2D ), (LPVOID*)&m_ppNormalTextures[iAttrib] );
                D3D10_TEXTURE2D_DESC desc;
                m_ppNormalTextures[iAttrib]->GetDesc( &desc );
                D3D10_SHADER_RESOURCE_VIEW_DESC SRVDesc;
                ZeroMemory( &SRVDesc, sizeof(SRVDesc) );
                SRVDesc.Format = desc.Format;
                SRVDesc.ViewDimension = D3D10_SRV_DIMENSION_TEXTURE2D;
                SRVDesc.Texture2D.MipLevels = desc.MipLevels;
                pDev10->CreateShaderResourceView( m_ppNormalTextures[iAttrib], &SRVDesc, &m_ppNormalSRVs[iAttrib] );
                SAFE_RELEASE( pRes );
            }
        }
    }

    return S_OK;
}

// Overridden to bind the normal map SRV if we have one...
void S3UTMesh::Render( ID3D10Device *pDev )
{
    if( m_pMesh10 && m_ppTexture && m_ppSRV )
    {
        for( DWORD subset = 0; subset < m_dwNumAttr; ++subset )
        {
            pDev->PSSetShaderResources( 0, 1, &m_ppSRV[subset] );
            if(m_ppNormalSRVs != NULL) pDev->PSSetShaderResources( 1, 1, &m_ppNormalSRVs[subset] );
            m_pMesh10->DrawSubset( subset );
        }
    }
}

// NOTE, these functions are NOT virtual, so calling into base class will not call back into us.  didn't want to change the 
//  class interface.  expanded functions and code copied from sdkmesh_old.cpp

void S3UTMesh::Render( ID3D10Device *pDev, 
                 ID3D10EffectTechnique *pTechnique, 
                 ID3D10EffectShaderResourceVariable* ptxDiffuse,
                 ID3D10EffectVectorVariable* pvDiffuse, 
                 ID3D10EffectVectorVariable* pvSpecular, 
                 DWORD dwSubset,
                 ID3D10EffectShaderResourceVariable* ptxNormal)
{
    if( !m_pMesh10 )
        return;

    // Draw
    D3D10_TECHNIQUE_DESC techDesc;
    pTechnique->GetDesc( &techDesc );

    for( UINT p = 0; p < techDesc.Passes; ++p )
    {
        DWORD subSetStart = 0;
        DWORD subSetEnd = m_dwNumAttr;

        // If we only want a specific subset, then set range appropriately.
        if( (DWORD)-1 != dwSubset )
        {
            subSetStart = dwSubset;
            subSetEnd = dwSubset+1;
        }

        for( DWORD subset = 0; subset < m_dwNumAttr; ++subset )
        {
            if( m_ppTexture && m_ppSRV[subset] && ptxDiffuse )
                ptxDiffuse->SetResource( m_ppSRV[subset] );

            if( m_ppNormalTextures && m_ppNormalSRVs[subset] && ptxNormal )
                ptxNormal->SetResource( m_ppNormalSRVs[subset] );

            
            if( m_pMats )
            {
                int iMat = m_pAttr[ subset ].AttribId;
                D3DXVECTOR4 v4Diff( m_pMats[iMat].MatD3D.Diffuse.r, 
                                    m_pMats[iMat].MatD3D.Diffuse.g, 
                                    m_pMats[iMat].MatD3D.Diffuse.b, 
                                    m_pMats[iMat].MatD3D.Diffuse.a );
                D3DXVECTOR4 v4Spec( m_pMats[iMat].MatD3D.Specular.r, 
                                    m_pMats[iMat].MatD3D.Specular.g, 
                                    m_pMats[iMat].MatD3D.Specular.b, 
                                    m_pMats[iMat].MatD3D.Specular.a );
                if(pvDiffuse)
                    pvDiffuse->SetFloatVector( (float*)&v4Diff );
                if(pvSpecular)
                    pvSpecular->SetFloatVector( (float*)&v4Spec );
            }

            pTechnique->GetPassByIndex( p )->Apply(0);

            m_pMesh10->DrawSubset( subset );
        }
    }
}


void S3UTMesh::Render(UINT MAX_BONE_MATRICES,
						float scale,
						ID3D10Effect*	pEffect,
						ID3D10EffectTechnique*	pSuitTechnique,	
						ID3D10EffectTechnique*	pBodyTechnique,	
						ID3D10EffectTechnique*	pTechnique,	
						ID3D10EffectTechnique*	pSceneTechnique,	
						D3DXMATRIX* p_view_proj_matrix,
						ID3D10Device* pDev, 
						double fTime, float fElapsedTime, void* pUserContext,bool use_bias )
{
	assert( m_nBiasCounter == 0 );

	HRESULT hr;
	if( m_bRenderFloor )
	{
		Render( pDev, pTechnique, pEffect->GetVariableByName("DiffuseTex")->AsShaderResource() );
	}

	if( m_bRenderStaticObjs )
	{
		int start_cnt = m_nBiasCounter;
		for( UINT idx = 0; idx<m_nNumStaticMesh; ++idx )
		{
			if( use_bias )
			{
				V(pEffect->GetVariableByName("DepthBiasDefault")->AsScalar()->SetFloat(m_fBiases[start_cnt + idx]));
			}
			m_StaticMeshes[idx].Render( pDev, pSceneTechnique, pEffect->GetVariableByName("DiffuseTex")->AsShaderResource() );
		}
	}
	increase_bias_counter( m_nNumStaticMesh );

	if( m_bRenderWindmill )
	{
		ID3D10EffectMatrixVariable* m_pmBlurViewProj = pEffect->GetVariableByName( "g_mBlurViewProj" )->AsMatrix();
		ID3D10EffectMatrixVariable* m_pmBlurWorld	 = pEffect->GetVariableByName( "g_mBlurWorld" )->AsMatrix();
		ID3D10EffectShaderResourceVariable* m_ptxDiffuse = pEffect->GetVariableByName( "DiffuseTex" )->AsShaderResource();

	    // Fix the camera motion for now
		D3DXMATRIX mWorldViewProj; 
		D3DXMatrixScaling( &mWorldViewProj,(FLOAT)scale, (FLOAT)scale, (FLOAT)scale );
		D3DXMatrixMultiply( &mWorldViewProj, &mWorldViewProj, p_view_proj_matrix );

		D3DXMATRIX mBlurViewProj[MAX_TIME_STEPS];
		for(int i=0; i<MAX_TIME_STEPS; i++)
		{
			mBlurViewProj[i] = mWorldViewProj;//Might have problem
		}
		m_pmBlurViewProj->SetMatrixArray( (float*)mBlurViewProj, 0, MAX_TIME_STEPS );

		pDev->IASetInputLayout( m_pWarriorMesh->m_pSuitVertexLayout );

		int start_cnt = m_nBiasCounter;
		if( use_bias )
		{
			V(pEffect->GetVariableByName("DepthBiasDefault")->AsScalar()->SetFloat(m_fBiases[start_cnt]));
		}

		D3DXMATRIX mWorld;
		D3DXMatrixIdentity( &mWorld );

		for( int i=0; i<MAX_TIME_STEPS; i++ )
			m_pmBlurWorld->SetMatrixArray( (float*)mWorld, i, 1 );

		if( m_bRenderFence )
		{
			m_WindmillBaseMesh.Render( pDev, pSuitTechnique, m_ptxDiffuse );
		}

		D3DXMATRIX mRot,g_mFanWorld;

		float fRotStep = (1.0f/30.0f) / MAX_TIME_STEPS;
		float fRot = ((float)fTime - fRotStep*2.0f);
		float g_fFanSpeed = 2*D3DX_PI;

		D3DXMatrixTranslation( &g_mFanWorld, 0.0f, 3.62f, 2.012f );

		for( int i=0; i<MAX_TIME_STEPS; i++ )
		{
			D3DXMatrixRotationZ( &mRot, -g_fFanSpeed*fRot );
			mWorld = mRot * g_mFanWorld;
			m_pmBlurWorld->SetMatrixArray( (float*)mWorld, i, 1 );
			fRot += fRotStep;
		}

		if( use_bias )
		{
			V(pEffect->GetVariableByName("DepthBiasDefault")->AsScalar()->SetFloat(m_fBiases[1+start_cnt]));
		}

		if( m_bRenderFan )
		{
			m_WindmillFanMesh.Render( pDev, pSuitTechnique, m_ptxDiffuse );
		}
	
	}

	//increase_bias_counter( 2 );

	if( m_bRenderWarrior )
	{
		m_pWarriorMesh->OnD3D10FrameRender( MAX_BONE_MATRICES,
									  scale,
									  pEffect,
									  pSuitTechnique,
									  pBodyTechnique,
									  p_view_proj_matrix,
									  pDev,
									  fTime, fElapsedTime, pUserContext, use_bias );
	}

	m_nBiasCounter = 0;
}

void S3UTMesh::RenderInstanced( ID3D10Device *pDev, 
                          ID3D10EffectTechnique *pTechnique, 
                          UINT uiInstanceCount,
                          ID3D10EffectShaderResourceVariable* ptxDiffuse,
                          ID3D10EffectVectorVariable* pvDiffuse, 
                          ID3D10EffectVectorVariable* pvSpecular )
{
    CDXUTMesh10::RenderInstanced( pDev, pTechnique, uiInstanceCount,ptxDiffuse,pvDiffuse, pvSpecular );
}

// Need to overload to release out normals and SRVs
void S3UTMesh::Destroy()
{
    if(m_ppNormalTextures)
    {
        for(unsigned int i=0;i<m_dwNumAttr;i++)
        {
            SAFE_RELEASE(m_ppNormalTextures[i]);
            SAFE_RELEASE(m_ppNormalSRVs[i]);
        }
    }

    delete [] m_ppNormalTextures;
    delete [] m_ppNormalSRVs;

	if( m_pWarriorMesh )
		m_pWarriorMesh->OnD3D10DestroyDevice(NULL);

	for( UINT idx = 0; idx < m_nNumStaticMesh; ++idx )
	{
		m_StaticMeshes[idx].Destroy();
	}

	m_WindmillBaseMesh.Destroy();
	m_WindmillFanMesh.Destroy();

    CDXUTMesh10::Destroy();
}

