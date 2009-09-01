#include "DXUT.h"
#include "DXUTgui.h"
#include "DXUTcamera.h"
#include "DXUTsettingsdlg.h"
#include "SDKmisc.h"
#include "SDKMesh.h"
#include <AnimationMesh.h>

	struct MESHLINK
	{
		WCHAR szMeshName[MAX_PATH];
		UINT iBone;
	};

	MESHLINK m_MeshLinkages[] = 
	{
		{ L"MotionBlur\\Hammer.sdkmesh", 13 },
		{ L"MotionBlur\\LeftForearm.sdkmesh", 54 },
		{ L"MotionBlur\\RightForearm.sdkmesh", 66 },
		{ L"MotionBlur\\RightShoulder.sdkmesh", 72 },
		{ L"MotionBlur\\LeftShoulder.sdkmesh", 72 },
		{ L"MotionBlur\\BackPlate.sdkmesh", 72 },
		{ L"MotionBlur\\Helmet.sdkmesh", 51 },
		{ L"MotionBlur\\Eyes.sdkmesh", 51 },
		{ L"MotionBlur\\Belt.sdkmesh", 63 },
		{ L"MotionBlur\\LeftThigh.sdkmesh", 58 },
		{ L"MotionBlur\\RightThigh.sdkmesh", 70 },
		{ L"MotionBlur\\LeftShin.sdkmesh", 56 },
		{ L"MotionBlur\\RightShin.sdkmesh", 68 },
	};	

HRESULT AnimationMesh::OnD3D10CreateDevice(  WCHAR *pMeshName,
											 WCHAR *pAnimName,
											 ID3D10Device* pd3dDevice,
											 D3D10_INPUT_ELEMENT_DESC *pSuitLayout,
											 D3D10_INPUT_ELEMENT_DESC *pBodyLayout
											)
{
    HRESULT hr;

    WCHAR str[MAX_PATH];
    V_RETURN(DXUTFindDXSDKMediaFileCch(str, MAX_PATH, L"AnimationMesh.fx"));
    ID3D10Blob *pErrors;
	ID3D10Effect *l_pEffect = NULL;
    if (D3DX10CreateEffectFromFile(str, NULL, NULL, "fx_4_0",0, 0, pd3dDevice, NULL, NULL, &l_pEffect, &pErrors, &hr) != S_OK)
    {
        MessageBoxA(NULL, (char *)pErrors->GetBufferPointer(), "Compilation error", MB_OK);
        exit(0);
    }

	m_NumLinkedMeshes = sizeof( m_MeshLinkages )/sizeof( MESHLINK );

    D3D10_PASS_DESC PassDesc;
	l_pEffect->GetTechniqueByName("RenderScene")->GetPassByIndex( 0 )->GetDesc( &PassDesc );
    V_RETURN( pd3dDevice->CreateInputLayout( pSuitLayout, 4, PassDesc.pIAInputSignature, PassDesc.IAInputSignatureSize, &m_pSuitVertexLayout ) );
    
    //Create the Linked Meshes
    m_pLinkedMeshes = new CDXUTSDKMesh[ m_NumLinkedMeshes ];
    if( !m_pLinkedMeshes )
        return E_OUTOFMEMORY;
    for( UINT iMesh = 0; iMesh < m_NumLinkedMeshes; iMesh++ )
    {
        m_pLinkedMeshes[iMesh].Create( pd3dDevice, m_MeshLinkages[iMesh].szMeshName );
    }

	l_pEffect->GetTechniqueByName("RenderSkinnedScene")->GetPassByIndex( 0 )->GetDesc( &PassDesc );
    V_RETURN( pd3dDevice->CreateInputLayout( pBodyLayout, 6, PassDesc.pIAInputSignature, PassDesc.IAInputSignatureSize, &m_pBodyVertexLayout ) );
    m_AnimMesh.Create( pd3dDevice, pMeshName );
    m_AnimMesh.LoadAnimation( pAnimName );

	SAFE_RELEASE(l_pEffect);

    return S_OK;
}

void AnimationMesh::RenderLinkedMesh( ID3D10Device* pd3dDevice, CDXUTSDKMesh* pLinkedMesh, CDXUTSDKMesh* pAnimMesh, 
									  UINT iInfluence, double fTime, ID3D10EffectTechnique*	pTechnique)
{
    // Set the bone matrices
    double fStepSize = 1.0f/60.0f;
    double fTimeShift = fTime-MAX_TIME_STEPS*fStepSize;
    for( int s=0; s<MAX_TIME_STEPS; s++ )
    {
        fTimeShift += fStepSize;
        
        D3DXMATRIX mIdentity;
        D3DXMatrixIdentity( &mIdentity );
        pAnimMesh->TransformMesh( &mIdentity, fTimeShift );

        const D3DXMATRIX* pMat = pAnimMesh->GetMeshInfluenceMatrix( 0, iInfluence );
        m_pmBlurWorld->SetMatrixArray( (float*)pMat, s, 1 );
    }


	pd3dDevice->IASetInputLayout( m_pSuitVertexLayout );
    pLinkedMesh->Render( pd3dDevice, pTechnique, m_ptxDiffuse );
}

void AnimationMesh::RenderSkinnedMesh( UINT max_bone_matrices,ID3D10Device* pd3dDevice, CDXUTSDKMesh* pAnimMesh, double fTime, ID3D10EffectTechnique*	pTechnique )
{
    ID3D10Buffer *pBuffers[1];
    UINT stride[1];
    UINT offset[1] = { 0 };

    // Set vertex Layout
    pd3dDevice->IASetInputLayout( m_pBodyVertexLayout );
            
    // Render the meshes
    for( UINT m=0; m<pAnimMesh->GetNumMeshes(); m++ )
    {
        pBuffers[0] = pAnimMesh->GetVB10(m,0);
        stride[0] = (UINT)pAnimMesh->GetVertexStride(m,0);
        offset[0] = 0;

        pd3dDevice->IASetVertexBuffers( 0, 1, pBuffers, stride, offset );
        pd3dDevice->IASetIndexBuffer( pAnimMesh->GetIB10(m), pAnimMesh->GetIBFormat10(m), 0 );

        SDKMESH_SUBSET* pSubset = NULL;
        SDKMESH_MATERIAL* pMat = NULL;
        D3D10_PRIMITIVE_TOPOLOGY PrimType;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            
        // Set the bone matrices
        double fStepSize = 1.0f/60.0f;
        double fTimeShift = fTime-MAX_TIME_STEPS*fStepSize;
        for( int s=0; s<MAX_TIME_STEPS; s++ )
        {
            fTimeShift += fStepSize;
            
            D3DXMATRIX mIdentity;
            D3DXMatrixIdentity( &mIdentity );
            pAnimMesh->TransformMesh( &mIdentity, fTimeShift );

            for( UINT i=0; i<pAnimMesh->GetNumInfluences( m ); i++ )
            {
                const D3DXMATRIX* pMat = pAnimMesh->GetMeshInfluenceMatrix( m, i );
                m_pmBoneWorld->SetMatrixArray( (float*)pMat, max_bone_matrices*s + i, 1 );
            }
        }

        D3D10_TECHNIQUE_DESC techDesc;
        ID3D10EffectTechnique* pTech;
        pTech = pTechnique;
        pTech->GetDesc( &techDesc );
        for( UINT p = 0; p < techDesc.Passes; ++p )
        {
            for( UINT subset = 0; subset < pAnimMesh->GetNumSubsets(m); subset++ )
            {
                pSubset = pAnimMesh->GetSubset(m,subset);

                PrimType = pAnimMesh->GetPrimitiveType10( (SDKMESH_PRIMITIVE_TYPE)pSubset->PrimitiveType );
                pd3dDevice->IASetPrimitiveTopology( PrimType );

                pMat = pAnimMesh->GetMaterial( pSubset->MaterialID );
                if( pMat )
                {
                    m_ptxDiffuse->SetResource( pMat->pDiffuseRV10 );
                }
        
                pTech->GetPassByIndex( p )->Apply(0);
                pd3dDevice->DrawIndexed( (UINT)pSubset->IndexCount, (UINT)pSubset->IndexStart, (UINT)pSubset->VertexStart );
            }
        }
	}

}

void AnimationMesh::OnD3D10FrameRender(	UINT max_bone_matrices,
									    float scale,
									    ID3D10Effect*	pEffect,
									    ID3D10EffectTechnique*	pSuitTechnique,	
									    ID3D10EffectTechnique*	pBodyTechnique,	
										D3DXMATRIX* p_view_proj_matrix,
									    ID3D10Device* pd3dDevice, 
										double fTime, float fElapsedTime, void* pUserContext,bool use_bias
									   )
{
	HRESULT hr;
    // Obtain the parameter handles
    m_pmBlurViewProj = pEffect->GetVariableByName( "g_mBlurViewProj" )->AsMatrix();
    m_pmBlurWorld	 = pEffect->GetVariableByName( "g_mBlurWorld" )->AsMatrix();
    m_pmBoneWorld	 = pEffect->GetVariableByName( "g_mBoneWorld" )->AsMatrix();
    m_ptxDiffuse	 = pEffect->GetVariableByName( "DiffuseTex" )->AsShaderResource();

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

	int bias_idx = m_nBiasCounter;
	if( use_bias )
	{
		V(pEffect->GetVariableByName("DepthBiasDefault")->AsScalar()->SetFloat(m_fBiases[bias_idx]));
		++bias_idx;
		increase_bias_counter(1);
	}
	else
	{
		V(pEffect->GetVariableByName("DepthBiasDefault")->AsScalar()->SetFloat(0));
	}
    RenderSkinnedMesh( max_bone_matrices, pd3dDevice, &m_AnimMesh, fTime, pBodyTechnique );
    
	V(pEffect->GetVariableByName("SkinSpecCoe")->AsScalar()->SetInt(4));

	for( UINT iMesh=0; iMesh < m_NumLinkedMeshes; iMesh++ )
	{
		if( use_bias )
		{
			V(pEffect->GetVariableByName("DepthBiasDefault")->AsScalar()->SetFloat(m_fBiases[bias_idx]));
			++bias_idx;
		}
		else
		{
			V(pEffect->GetVariableByName("DepthBiasDefault")->AsScalar()->SetFloat(0));
		}
        RenderLinkedMesh( pd3dDevice, &m_pLinkedMeshes[iMesh], &m_AnimMesh, m_MeshLinkages[iMesh].iBone, fTime, pSuitTechnique );
	}
	m_nBiasCounter = 0;
}

void AnimationMesh::OnD3D10DestroyDevice( void* pUserContext )
{
    SAFE_RELEASE( m_pSuitVertexLayout );
    SAFE_RELEASE( m_pBodyVertexLayout );

    for( UINT iMesh=0; iMesh < m_NumLinkedMeshes; iMesh++ )
        m_pLinkedMeshes[iMesh].Destroy();
    SAFE_DELETE_ARRAY( m_pLinkedMeshes );

    m_AnimMesh.Destroy();
}
